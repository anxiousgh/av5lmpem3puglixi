-- ============================================================
--  games/78105732598311.lua  --  Scratchy Loot (SIGMA ISLAND)
--
--  Scratch-ticket gambling idle game. This module does NOT load the
--  universal shell (vampire's request) -- the Scratchy pages are the
--  whole UI for this game.
--
--  Mechanics (decoded + live-validated 2026-07-12):
--    Remotes in ReplicatedStorage.Remotes.Functions (plain RemoteFunctions):
--      BuyTicket(typeName)           -> {success, ticketId, cells, ...}
--                                       ("Plate" is a free type = day job)
--      ScratchTicket(id, indices)    -> {success, won, prize, ...}
--                                       indices = 1..#cells (over-sending ok)
--      ClaimTicket(id)               -> {success, floatAmount, Money}
--      WashPlate(plateId)            -> {success, broken, reward, ...}
--      GetTickets()                  -> array of table tickets
--      GetPlayerStats()              -> {unlockedTickets = {name=true}, ...}
--    Table cards = ImageButtons named <ticketId> in MainUI ...
--    Table.TicketsContainer, attr IsPlate marks day-job plates.
--
--  Visual mode drives the game's OWN client modules (require'd from
--  PlayerGui.MainUI.MainLocalHandler -- LocalScript with ModuleScript kids):
--    ScratchEngine.scratchAt({X,Y}, nil, true) erases pixels at a SCREEN
--    position (it subtracts the 58px GuiInset itself, so pass abs+inset),
--    then TicketPresenter.checkThreshold() auto-submits, auto-claims and
--    closes with the real result animation. Plates use WashPresenter.washAt
--    + checkThreshold, then their ClaimBtn must be clicked (getconnections
--    .Function -- firesignal on GuiButton signals does NOT work in Volt).
-- ============================================================
local ctx = ({ ... })[1]

local Library = ctx.Library
local Window  = ctx.Window

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

local Functions = RS:WaitForChild("Remotes"):WaitForChild("Functions")
local BuyTicket      = Functions:WaitForChild("BuyTicket")
local ScratchTicket  = Functions:WaitForChild("ScratchTicket")
local ClaimTicket    = Functions:WaitForChild("ClaimTicket")
local WashPlate      = Functions:WaitForChild("WashPlate")
local GetTickets     = Functions:WaitForChild("GetTickets")
local GetPlayerStats = Functions:WaitForChild("GetPlayerStats")
local BuyGadget      = Functions:WaitForChild("BuyGadget")
local DeleteTicket   = RS.Remotes:WaitForChild("DeleteTicket")

local TicketConfig  = require(RS.Modules.ScratchTickets.ScratchTicketConfig)
local GadgetsClient = require(RS.Modules.Client.GadgetsClient)

-- generation token: re-executing the hub kills the old loops
local gen = (getgenv()._WH_SL_gen or 0) + 1
getgenv()._WH_SL_gen = gen
local function alive() return getgenv()._WH_SL_gen == gen end

-- ---- state ----
local S = {
    autoScratch   = false,
    mode          = "Instant",
    visSpeed      = 5,
    autoBuy       = false,
    buyType       = "Best affordable",
    plateFallback = true,
    autoPlates    = false,
    buyTrash      = true,
    earned        = 0,
    status        = "idle",
}

-- ============================================================
--  shared helpers
-- ============================================================
local function mainUI()
    return LocalPlayer:FindFirstChild("PlayerGui")
        and LocalPlayer.PlayerGui:FindFirstChild("MainUI")
end

local function ticketsContainer()
    local ui = mainUI()
    return ui and ui:FindFirstChild("TicketsContainer", true)
end

local function clickButton(btn)
    for _, sig in ipairs({ "MouseButton1Click", "Activated" }) do
        for _, c in ipairs(getconnections(btn[sig])) do
            pcall(c.Function)
        end
    end
end

local function bankClaim(res)
    if type(res) == "table" and res.success and type(res.floatAmount) == "number" then
        S.earned += res.floatAmount
        return res.floatAmount
    end
    return nil
end

local function claim(id)
    local ok, res = pcall(function() return ClaimTicket:InvokeServer(id) end)
    return ok and bankClaim(res) or nil
end

local function indicesFor(tk)
    local n = 225
    if type(tk.cells) == "table" and #tk.cells > 0 then
        n = #tk.cells
    else
        local cfg = TicketConfig.TicketTypes[tk.ticketType]
        if cfg and cfg.size then n = cfg.size * cfg.size end
    end
    local idx = {}
    for i = 1, n do idx[i] = i end
    return idx
end

-- unlocked ticket types, most expensive first
local buyList, lastUnlockFetch = {}, 0
local function refreshBuyList(force)
    if not force and os.clock() - lastUnlockFetch < 15 then return end
    lastUnlockFetch = os.clock()
    local ok, stats = pcall(function() return GetPlayerStats:InvokeServer() end)
    if not ok or type(stats) ~= "table" or type(stats.unlockedTickets) ~= "table" then return end
    local list = {}
    for name in pairs(stats.unlockedTickets) do
        local cfg = TicketConfig.TicketTypes[name]
        if cfg and (cfg.cost or 0) > 0 then
            list[#list + 1] = { name = name, cost = cfg.cost }
        end
    end
    table.sort(list, function(a, b) return a.cost > b.cost end)
    buyList = list
end

-- card lookup by numeric id (card names are full-precision float strings;
-- tostring() would reformat, so compare parsed numbers instead)
local function findCard(id)
    local tc = ticketsContainer()
    if not tc then return nil end
    for _, card in ipairs(tc:GetChildren()) do
        if card:IsA("ImageButton") and card.Name ~= "Template" then
            local n = tonumber(card.Name)
            if n and math.abs(n - id) < 1e-3 then return card end
        end
    end
    return nil
end

-- trash a finished ticket/plate: the game's own delete remote (clears the
-- server entry, same as dragging it onto the bin) + local card removal
-- (card add/remove is client-driven, so remote claims leave ghosts otherwise)
local function trashTicket(id, waitForCard)
    pcall(function() DeleteTicket:FireServer(id) end)
    local deadline = os.clock() + (waitForCard and 2 or 0)
    repeat
        local card = findCard(id)
        if card then card:Destroy() return end
        if os.clock() >= deadline then return end
        task.wait(0.1)
    until false
end

local function washPlateInstant(plateId)
    pcall(function() WashPlate:InvokeServer(plateId) end)
    local got = claim(plateId)
    trashTicket(plateId, true)
    return got
end

-- one free day-job plate: buy -> wash -> claim -> trash
local function plateCycle()
    local ok, buy = pcall(function() return BuyTicket:InvokeServer("Plate") end)
    if not ok or type(buy) ~= "table" or not buy.success then return false end
    S.status = "washing plate"
    washPlateInstant(buy.plateId)
    return true
end

-- Trash Can gadget: rebuy whenever it's purchasable (resets on prestige)
local function buyTrashCan()
    local ok, state = pcall(function() return GadgetsClient.getState().Trash end)
    if not ok or type(state) ~= "table" then return end
    if state.atMax or state.locked or not state.price then return end
    S.status = "buying Trash Can"
    pcall(function() BuyGadget:InvokeServer("Trash") end)
end

-- ============================================================
--  instant mode -- pure remotes, clears the whole table per pass
-- ============================================================
local function instantPass()
    local ok, tickets = pcall(function() return GetTickets:InvokeServer() end)
    if ok and type(tickets) == "table" then
        for _, tk in pairs(tickets) do
            if not (S.autoScratch and S.mode == "Instant" and alive()) then return end
            if type(tk) == "table" and tk.ticketId and not tk.locked then
                S.status = "scratching " .. tostring(tk.ticketType)
                if not tk.scratched then
                    pcall(function() ScratchTicket:InvokeServer(tk.ticketId, indicesFor(tk)) end)
                end
                if claim(tk.ticketId) ~= nil then
                    trashTicket(tk.ticketId, false)
                end
                task.wait(0.1)
            end
        end
    end
    -- day-job plates on the table are not in GetTickets -- sweep their cards
    local tc = ticketsContainer()
    if tc then
        for _, card in ipairs(tc:GetChildren()) do
            if not (S.autoScratch and S.mode == "Instant" and alive()) then return end
            if card:IsA("ImageButton") and card.Name ~= "Template"
                and card:GetAttribute("IsPlate") and not card:GetAttribute("Placing") then
                local id = tonumber(card.Name)
                if id then
                    S.status = "washing plate"
                    washPlateInstant(id)
                    task.wait(0.1)
                end
            end
        end
    end
    -- ghost sweep: ticket cards whose server ticket no longer exists
    local ok2, live = pcall(function() return GetTickets:InvokeServer() end)
    if ok2 and type(live) == "table" and tc then
        local exists = {}
        for _, tk in pairs(live) do
            if type(tk) == "table" and tk.ticketId then exists[#exists + 1] = tk.ticketId end
        end
        for _, card in ipairs(tc:GetChildren()) do
            if card:IsA("ImageButton") and card.Name ~= "Template"
                and not card:GetAttribute("IsPlate") and not card:GetAttribute("Placing") then
                local id = tonumber(card.Name)
                if id then
                    local found = false
                    for _, e in ipairs(exists) do
                        if math.abs(e - id) < 1e-3 then found = true break end
                    end
                    if not found then card:Destroy() end
                end
            end
        end
    end
end

-- ============================================================
--  visual mode -- opens the ticket and plays the real scratch effect
-- ============================================================
local function findClaimBtn()
    local ui = mainUI()
    if not ui then return nil end
    for _, d in ipairs(ui:GetDescendants()) do
        if d.Name == "ClaimBtn" and d:IsA("GuiButton") and d.Visible and d.AbsoluteSize.X > 0 then
            local a, vis = d.Parent, true
            while a and a ~= ui do
                if a:IsA("GuiObject") and not a.Visible then vis = false break end
                a = a.Parent
            end
            if vis then return d end
        end
    end
    return nil
end

-- serpentine eraser sweep over a set of frames (real scratch visuals)
local function sweepFrames(frames, scratchFn, radius)
    local inset = GuiService:GetGuiInset()
    local step = math.max(8, (radius or 29) * 0.5)
    local rowWait = 0.28 / math.max(1, S.visSpeed)
    for _, f in ipairs(frames) do
        if not (S.autoScratch and alive()) then return false end
        local p, sz = f.AbsolutePosition, f.AbsoluteSize
        local y = p.Y
        while y <= p.Y + sz.Y + step do
            local x = p.X
            while x <= p.X + sz.X + step do
                scratchFn({ X = x + inset.X, Y = y + inset.Y })
                x += step
            end
            y += step
            task.wait(rowWait)
        end
    end
    return true
end

local function visualTicket(TP, SE, card)
    clickButton(card)
    for _ = 1, 30 do
        if TP.getCurrentTicket() then break end
        task.wait(0.1)
    end
    if not TP.getCurrentTicket() then return end
    task.wait(0.6)

    S.status = "scratching " .. tostring(card:GetAttribute("Name") or "ticket")
    local done = sweepFrames(SE.getFlashCells(), function(pos)
        SE.scratchAt(pos, nil, true)
    end, SE.getEraserRadius())
    if not done then return end

    pcall(TP.checkThreshold)
    -- normally auto-submits + auto-claims + closes; ClaimBtn click is the
    -- fallback path (some ticket types keep the button)
    for _ = 1, 50 do
        if not TP.getCurrentTicket() then break end
        local btn = findClaimBtn()
        if btn then clickButton(btn) end
        task.wait(0.15)
    end
    if TP.getCurrentTicket() then pcall(TP.close, true) end
end

local function visualPlate(WP, card)
    clickButton(card)
    for _ = 1, 30 do
        if WP.hasClone() then break end
        task.wait(0.1)
    end
    if not WP.hasClone() then return end
    task.wait(0.6)

    S.status = "washing plate"
    local overlay = WP.getDirtOverlay and WP.getDirtOverlay()
    if overlay then
        sweepFrames({ overlay }, function(pos)
            WP.washAt(pos)
            pcall(WP.checkThreshold)
        end, WP.getEraserRadius and WP.getEraserRadius() or 35)
    end
    pcall(WP.checkThreshold)
    for _ = 1, 50 do
        if not WP.hasClone() then break end
        local btn = findClaimBtn()
        if btn then clickButton(btn) end
        task.wait(0.15)
    end
end

local function visualPass()
    local ui = mainUI()
    if not ui then return end
    local MLH = ui:FindFirstChild("MainLocalHandler")
    if not MLH then return end
    local okTP, TP = pcall(require, MLH:FindFirstChild("TicketPresenter"))
    local okSE, SE = pcall(require, MLH:FindFirstChild("ScratchEngine"))
    local okWP, WP = pcall(require, MLH:FindFirstChild("WashPresenter"))
    if not (okTP and okSE) then return end

    -- something already open (e.g. vampire opened it by hand)? finish it
    if TP.getCurrentTicket() then
        S.status = "scratching open ticket"
        local done = sweepFrames(SE.getFlashCells(), function(pos)
            SE.scratchAt(pos, nil, true)
        end, SE.getEraserRadius())
        if done then
            pcall(TP.checkThreshold)
            for _ = 1, 50 do
                if not TP.getCurrentTicket() then break end
                local btn = findClaimBtn()
                if btn then clickButton(btn) end
                task.wait(0.15)
            end
        end
        return
    end

    local tc = ticketsContainer()
    if not tc then return end
    for _, card in ipairs(tc:GetChildren()) do
        if card:IsA("ImageButton") and card.Name ~= "Template" and not card:GetAttribute("Placing") then
            if card:GetAttribute("IsPlate") then
                if okWP then visualPlate(WP, card) end
            else
                visualTicket(TP, SE, card)
            end
            return -- one card per pass, re-scan fresh
        end
    end
end

-- ============================================================
--  buying
-- ============================================================
local function tableBusy()
    if S.mode ~= "Visual" then return false end
    local tc = ticketsContainer()
    if not tc then return false end
    local n = 0
    for _, card in ipairs(tc:GetChildren()) do
        if card:IsA("ImageButton") and card.Name ~= "Template" then n += 1 end
    end
    return n >= 2 -- visual mode is slow; don't stack the table
end

local function buyPass()
    if tableBusy() then return end
    refreshBuyList(false)
    local wanted
    if S.buyType ~= "Best affordable" then
        wanted = { { name = S.buyType, cost = 0 } }
    else
        wanted = buyList
    end
    for _, entry in ipairs(wanted) do
        local ok, buy = pcall(function() return BuyTicket:InvokeServer(entry.name) end)
        if ok and type(buy) == "table" then
            if buy.success then
                S.status = "bought " .. entry.name
                return
            elseif buy.reason and tostring(buy.reason):lower():find("full") then
                S.status = "table full"
                return
            end
        end
    end
    S.status = "cant afford"
    if S.plateFallback then plateCycle() end
end

-- ============================================================
--  loops
-- ============================================================
task.spawn(function()
    while alive() do
        if S.autoScratch then
            if S.mode == "Instant" then
                pcall(instantPass)
            else
                pcall(visualPass)
            end
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while alive() do
        if S.autoBuy then pcall(buyPass) end
        task.wait(0.25)
    end
end)

task.spawn(function()
    while alive() do
        if S.autoPlates then pcall(plateCycle) end
        task.wait(0.15)
    end
end)

task.spawn(function()
    while alive() do
        if S.buyTrash then pcall(buyTrashCan) end
        task.wait(10)
    end
end)

-- anti-AFK
local idleConn = LocalPlayer.Idled:Connect(function()
    local vu = game:GetService("VirtualUser")
    vu:CaptureController()
    vu:ClickButton2(Vector2.new())
end)

-- ============================================================
--  UI
-- ============================================================
local Page = Window:Page({ Name = "Scratchy Loot" })
local Sub  = Page:SubPage({ Name = "Farm" })

local Sec = Sub:Section({ Name = "Auto scratch", Side = 1 })
Sec:Toggle({
    Name = "Auto scratch + claim", Flag = "SL_AutoScratch", Default = false,
    Callback = function(v) S.autoScratch = v end,
})
Sec:Dropdown({
    Name = "Mode", Flag = "SL_Mode", Default = "Instant", Multi = false,
    Items = { "Instant", "Visual" },
    Callback = function(v) S.mode = (type(v) == "table" and v[1]) or v or "Instant" end,
})
Sec:Slider({
    Name = "Visual speed", Flag = "SL_VisSpeed",
    Min = 1, Max = 10, Default = 5, Decimals = 0,
    Callback = function(v) S.visSpeed = v end,
})
Sec:Label({ Name = "Instant = remote, invisible + fast" })
Sec:Label({ Name = "Visual = opens tickets, plays the effect" })

local SecB = Sub:Section({ Name = "Auto buy", Side = 2 })
SecB:Toggle({
    Name = "Auto buy tickets", Flag = "SL_AutoBuy", Default = false,
    Callback = function(v)
        S.autoBuy = v
        if v then refreshBuyList(true) end
    end,
})
do
    refreshBuyList(true)
    local items = { "Best affordable" }
    for _, e in ipairs(buyList) do items[#items + 1] = e.name end
    SecB:Dropdown({
        Name = "Ticket", Flag = "SL_BuyType", Default = "Best affordable", Multi = false,
        Items = items,
        Callback = function(v) S.buyType = (type(v) == "table" and v[1]) or v or "Best affordable" end,
    })
end
SecB:Toggle({
    Name = "Wash plates when broke", Flag = "SL_PlateFallback", Default = true,
    Callback = function(v) S.plateFallback = v end,
})

local SecP = Sub:Section({ Name = "Day job", Side = 2 })
SecP:Toggle({
    Name = "Auto wash plates", Flag = "SL_AutoPlates", Default = false,
    Callback = function(v) S.autoPlates = v end,
})
SecP:Label({ Name = "free money loop -- works in loan debt" })
SecP:Toggle({
    Name = "Auto buy Trash Can", Flag = "SL_BuyTrash", Default = true,
    Callback = function(v) S.buyTrash = v end,
})

local SecI = Sub:Section({ Name = "Info", Side = 1 })
local lblStatus  = SecI:Label({ Name = "status: idle" })
local lblSession = SecI:Label({ Name = "session: +$0" })
local lblBal     = SecI:Label({ Name = "balance: ?" })

task.spawn(function()
    while alive() do
        pcall(function()
            lblStatus:SetText("status: " .. S.status)
            lblSession:SetText(("session: +$%d"):format(math.floor(S.earned)))
            local ls = LocalPlayer:FindFirstChild("leaderstats")
            local m = ls and ls:FindFirstChild("Money")
            lblBal:SetText("balance: $" .. tostring(m and m.Value or "?"))
        end)
        task.wait(0.5)
    end
end)

-- ---- teardown on unload / re-execution ----
do
    local g = getgenv and getgenv()
    local function teardown()
        getgenv()._WH_SL_gen = -1
        pcall(function() idleConn:Disconnect() end)
    end
    if g and g.WH then
        local prev = g.WH.disableAll
        g.WH.disableAll = function()
            pcall(teardown)
            if prev then pcall(prev) end
        end
    end
    Library.OnExit = function() pcall(teardown) end
end
