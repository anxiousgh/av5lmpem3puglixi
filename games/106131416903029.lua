-- ============================================================
--  games/106131416903029.lua  --  🍓 Cook & Sell! [ALPHA]  (Alpaca Games / "Riese")
--
--  Restaurant tycoon. Loop: cook food in the pot -> 8 plated items land in
--  UnplacedProducts -> stock shelves -> customers buy -> checkout at register
--  -> collect cash -> buy upgrades / expand.
--
--  Everything here is an independent, toggleable + customizable feature built
--  on the shared Window. The universal base is loaded first so movement/ESP/etc.
--  still work.
--
--  Validated remotes (live, 2026-06-29):
--    * Cooking (tap mode, the player's CookingInputMode):
--        StartCooking:InvokeServer(productId, true)         -- load recipe into pot
--        CookingAction:InvokeServer("PickUp", slotIndex)    -- slotIndex = ingredient's "CookingSlotIndex" attr
--        CookingAction:InvokeServer("AddToPot")             -- drop the held ingredient in
--        (pot auto-starts cooking once IngredientCount == IngredientsRequired)
--        pot.Remote:FireServer("ClaimDessert")              -- when ReadyToClaim -> +8 items to UnplacedProducts
--    * Register prompts (Workspace.Plots.<n>.Checkout.CashRegister.PromptAttachment):
--        CashPrompt    (ActionText "Checkout")  -- serve the queued customer
--        CollectPrompt (ActionText "Collect")   -- bank the register balance
--    * Economy:
--        BuyPotUpgrade:FireServer(key)   BuyCheckoutUpgrade:FireServer()
--        RedeemCode:InvokeServer(code)   GetDailyLoginReward:InvokeServer()
--        HireCashier:InvokeServer()
--
--  NOTE: stocking (UnplacedProducts -> shelf) is a physical ClickDetector/Tool
--  flow that isn't cleanly remote-drivable, and the checkout/collect side could
--  not be load-tested while the shop was closed (no customers). Cooking is fully
--  validated. The cleanest hands-off sell side is to hire a Cashier (auto-serves)
--  and use Auto-collect; everything is independently toggleable so you can mix.
-- ============================================================
local ctx = ({ ... })[1]

local Library = ctx.Library
local Window  = ctx.Window

-- Cook & Sell page is created FIRST so it's the first tab, THEN we load the
-- universal base (Player/Visuals) so those tabs come after it.
local Page = Window:Page({ Name = "Cook & Sell" })
pcall(function() ctx.load("games/universal.lua")(ctx) end)

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local CollectionService  = game:GetService("CollectionService")
local LP                 = Players.LocalPlayer

local function notify(msg, dur, col)
    pcall(function() Library:Notification(msg, dur or 3, col) end)
end

-- executor global for triggering ProximityPrompts
local FPP = rawget(getfenv(), "fireproximityprompt")
    or (getgenv and getgenv().fireproximityprompt)

-- ============================================================
--  dynamic resolvers (survive respawns / streaming / re-parents)
-- ============================================================
local function riese()    return ReplicatedStorage:FindFirstChild("Riese") end
local function remote(n)
    local r = riese(); local rem = r and r:FindFirstChild("Remotes")
    return rem and rem:FindFirstChild(n)
end

local _cache = {}
local function shared(name)
    if _cache[name] ~= nil then return _cache[name] or nil end
    local r = riese(); if not r then return nil end
    local folder = r:FindFirstChild("Shared")
    local mod = folder and folder:FindFirstChild(name)
    if not mod then return nil end
    local ok, m = pcall(require, mod)
    _cache[name] = ok and m or false
    return _cache[name] or nil
end

local function foodShop() return shared("FoodShop") end

local function plot()
    local fs = foodShop(); if not fs then return nil end
    local ok, p = pcall(fs.GetPlayerPlot, LP)
    if ok then return p end
end

local function pot()  local p = plot(); return p and p:FindFirstChild("CookingPotServerModel") end

-- player data replica (Cash / UncookedProducts / etc.)
local _rcm
local function rcm()
    if _rcm ~= nil then return _rcm or nil end
    local r = riese(); if not r then return nil end
    local c = r:FindFirstChild("Client")
    local mod = c and c:FindFirstChild("ReplicaControllerManager")
    if not mod then return nil end
    local ok, m = pcall(require, mod)
    _rcm = ok and m or false
    return _rcm or nil
end
local function pdata()
    local m = rcm(); if not m then return nil end
    local ok, rep = pcall(m.GetPlayerDataReplicaAsync)
    if ok and rep then return rep.Data end
end

local function cash()
    local d = pdata(); return d and tonumber(d.Cash) or 0
end

-- ============================================================
--  state (each feature has its own toggle + tunables)
-- ============================================================
local S = {
    -- cooking
    cook         = false,
    cookRecipe   = "Auto",
    cookPickWait = 0.32,   -- delay after PickUp before AddToPot (server animates ~PickupDuration)
    cookDropWait = 0.62,   -- delay after AddToPot before next ingredient (server animates the drop)
    cookLoopWait = 0.5,    -- pause between batches
    cookBusy     = false,
    -- stocking (UnplacedProducts -> shelf; cooked items are Backpack Tools tagged "CookedItem")
    stock        = false, stockInt = 3, stockAcc = 0,
    stockEquipWait = 0.3, stockPlaceWait = 0.7, stockBusy = false,
    -- register
    checkout     = false, checkoutInt = 0.5, checkoutAcc = 0,
    checkoutScanWait = 0.25, checkoutBusy = false,
    collect      = false, collectInt  = 5,   collectAcc  = 0,
    -- economy
    autoUpgrade  = false, upgradeInt  = 10,  upgradeAcc  = 0, keepCash = 0,
    upgPot       = true,  upgCheckout = true,
    hireCashier  = false, hireInt = 30, hireAcc = 0,
    redeemAuto   = false, redeemAcc = 0,
    dailyAuto    = false, dailyAcc  = 0,
}

local CODES = { "BONUS", "YUM", "MONEYBAG" }

-- ============================================================
--  COOKING backend (validated end-to-end)
-- ============================================================
local function pickRecipe()
    local d = pdata(); if not d then return nil end
    local up = d.UncookedProducts; if not up then return nil end
    if S.cookRecipe ~= "Auto" then
        return ((up[S.cookRecipe] or 0) > 0) and S.cookRecipe or nil
    end
    -- "Auto": cook anything we have stock of
    local best
    for k, v in pairs(up) do
        if type(v) == "number" and v > 0 then best = best or k end
    end
    return best
end

-- one full cook: load recipe -> fill ingredients -> (auto-cooks) -> claim
local function cookOnce()
    local p = pot(); if not p then return false, "no pot" end
    if p:GetAttribute("IsUpgrading") == true then return false, "pot upgrading" end

    -- finish a pending batch first
    if p:GetAttribute("ReadyToClaim") == true then
        local rem = p:FindFirstChild("Remote")
        if rem then pcall(function() rem:FireServer("ClaimDessert") end) end
        return true, "claimed"
    end
    if p:GetAttribute("Cooking") == true then return false, "cooking" end

    -- load a recipe if the pot is idle
    if p:GetAttribute("CurrentProductId") == nil then
        local recipe = pickRecipe()
        if not recipe then return false, "out of recipes" end
        local sc = remote("StartCooking"); if not sc then return false, "no StartCooking" end
        local ok = pcall(function() return sc:InvokeServer(recipe, true) end)
        if not ok then return false, "StartCooking failed" end
        task.wait(0.15)
    end

    -- fill the pot from the player's SpawnedIngredients (tap mode)
    local CA  = remote("CookingAction")
    local req = p:GetAttribute("IngredientsRequired") or 5
    local guard = 0
    while S.cook and (p:GetAttribute("IngredientCount") or 0) < req and guard < 40 do
        guard = guard + 1
        local pl   = plot()
        local ingF = pl and pl:FindFirstChild("SpawnedIngredients")
        local target
        if ingF then
            for _, it in ipairs(ingF:GetChildren()) do
                if it:GetAttribute("CookingOwnerUserId") == LP.UserId
                    and it:GetAttribute("CookingState") ~= "Held" then
                    target = it; break
                end
            end
        end
        if target and CA then
            local slot = target:GetAttribute("CookingSlotIndex")
            pcall(function() CA:InvokeServer("PickUp", slot) end)
            task.wait(S.cookPickWait)
            pcall(function() CA:InvokeServer("AddToPot") end)
            task.wait(S.cookDropWait)
        else
            task.wait(0.2)
        end
    end

    -- pot auto-starts cooking when full; wait it out, then claim
    local t0 = os.clock()
    while S.cook and p:GetAttribute("Cooking") == true and os.clock() - t0 < 30 do
        task.wait(0.4)
    end
    if p:GetAttribute("ReadyToClaim") == true then
        local rem = p:FindFirstChild("Remote")
        if rem then pcall(function() rem:FireServer("ClaimDessert") end) end
        return true, "cooked"
    end
    return true, "partial"
end

local function startCookLoop()
    if S.cookBusy then return end
    S.cookBusy = true
    task.spawn(function()
        local warned = false
        while S.cook do
            local ok, reason = cookOnce()
            if reason == "out of recipes" and not warned then
                notify("Cook & Sell: out of uncooked recipes — buy more from the recipe shop.", 5)
                warned = true
            elseif reason == "cooked" or reason == "claimed" then
                warned = false
            end
            task.wait(S.cookLoopWait)
        end
        S.cookBusy = false
    end)
end

-- ============================================================
--  STOCKING (validated: PlaceDownItem:FireServer(tool, counterModel, slotIndex))
--  Cooked batches arrive as Backpack Tools tagged "CookedItem" (one per product,
--  Stock = the count). Equipping + placing drops the WHOLE stack onto one empty
--  shelf slot. Slot model: CollectionService tag "CounterSlot", named by index,
--  parent = the counter model, attribute "Taken" marks occupancy.
-- ============================================================
local function cookedTools()
    local out = {}
    local function scan(p)
        if not p then return end
        for _, c in ipairs(p:GetChildren()) do
            if c:IsA("Tool") and CollectionService:HasTag(c, "CookedItem") then out[#out + 1] = c end
        end
    end
    scan(LP.Character)
    scan(LP:FindFirstChild("Backpack"))
    return out
end

-- Only the plot's "Counters" folder holds built/usable shelves; the "Buildables"
-- folder is unbuilt shop expansions and the server rejects placements there.
local function firstEmptySlot()
    local p = plot(); if not p then return nil end
    local counters = p:FindFirstChild("Counters"); if not counters then return nil end
    for _, s in ipairs(CollectionService:GetTagged("CounterSlot")) do
        if s:IsDescendantOf(counters) and s:GetAttribute("Taken") ~= true and tonumber(s.Name) then
            return s
        end
    end
    return nil
end

-- place every cooked tool we hold onto open slots; returns how many stacks placed
local function placeAll()
    local PDI = remote("PlaceDownItem"); if not PDI then return 0 end
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local placed = 0
    for _, tool in ipairs(cookedTools()) do
        local slot = firstEmptySlot()
        if not slot then break end
        if hum and tool.Parent ~= char then
            pcall(function() hum:EquipTool(tool) end)
            task.wait(S.stockEquipWait)
        end
        pcall(function() PDI:FireServer(tool, slot.Parent, tonumber(slot.Name)) end)
        task.wait(S.stockPlaceWait)
        placed = placed + 1
    end
    return placed
end

-- ============================================================
--  REGISTER (fire the CashRegister proximity prompts)
-- ============================================================
-- the whole checkout engine is server-side; the only client surface is these two
-- ProximityPrompts, and the server flips their .Enabled to signal "actionable now".
local function registerPrompt(matchName, matchAction)
    local p = plot(); if not p then return nil end
    local co = p:FindFirstChild("Checkout"); if not co then return nil end
    local reg = co:FindFirstChild("CashRegister"); if not reg then return nil end
    for _, d in ipairs(reg:GetDescendants()) do
        if d:IsA("ProximityPrompt") and (d.Name == matchName or d.ActionText == matchAction) then
            return d
        end
    end
    return nil
end

-- the customer being served is the NPC at QueuePosition 1 on our plot
local function customerAtTill()
    local m = rcm(); if not m or type(m.NPCReplicas) ~= "table" then return nil end
    local p = plot(); if not p then return nil end
    local co = p:FindFirstChild("Checkout")
    local q = co and co:FindFirstChild("Queue")
    local spot = q and q:FindFirstChild("1")
    for npc, rep in pairs(m.NPCReplicas) do
        if typeof(npc) == "Instance" and rep and rep.Data
            and rep.Data.QueuePosition == 1 and npc:IsDescendantOf(workspace) then
            local hrp = npc:FindFirstChild("HumanoidRootPart")
            if spot and hrp then
                if (hrp.Position - spot.Position).Magnitude <= 12 then return npc, rep end
            else
                return npc, rep
            end
        end
    end
    return nil
end

-- VALIDATED serve: scan the customer's bags via ManualCheckoutProgress, THEN fire
-- CashPrompt to finalize. The scan is the step the prompt-only approach was missing
-- (prompt does nothing until bags are marked scanned). Bags = min(#cart, 5), named "1"..N.
local function doCheckout()
    local p = plot(); if not p then return false end
    if p:GetAttribute("HasHiredCashier") == true then return false end -- the cashier serves
    local npc, rep = customerAtTill(); if not npc then return false end
    local MCP = remote("ManualCheckoutProgress"); if not MCP then return false end

    local N = 1
    local cdu = shared("CartDisplayUtils")
    if cdu and rep.Data then
        local ok, items = pcall(cdu.GetDisplayItems, rep.Data.Cart or {})
        if ok and type(items) == "table" then N = math.clamp(#items, 1, 5) end
    end
    local names = {}
    for i = 1, N do names[i] = tostring(i) end

    -- scan: empty Set starts the session, full Set marks every bag scanned
    pcall(function() MCP:FireServer("Set", npc, {}) end)
    task.wait(S.checkoutScanWait)
    pcall(function() MCP:FireServer("Set", npc, names) end)
    task.wait(S.checkoutScanWait)

    -- finalize: CashPrompt is enabled once bags are scanned; fire until cash moves
    local prompt = registerPrompt("CashPrompt", "Checkout")
    if not (prompt and FPP) then return false end
    local before = cash()
    for _ = 1, 5 do
        if cash() ~= before then break end
        pcall(function() FPP(prompt, math.max(0, prompt.HoldDuration or 0)) end)
        task.wait(0.35)
    end
    return cash() ~= before
end

local function doCollect()
    local d = pdata()
    local prompt = registerPrompt("CollectPrompt", "Collect")
    if not prompt then return false end
    -- collect when the prompt is live, or when the replica shows a banked balance
    if prompt.Enabled or (d and (tonumber(d.CashRegisterBalance) or 0) > 0) then
        if FPP then pcall(function() FPP(prompt, math.max(0, prompt.HoldDuration or 0)) end) end
        return true
    end
    return false
end

-- ============================================================
--  ECONOMY helpers
-- ============================================================
local function potUpgradeKeys()
    local data = shared("PotUpgradeData"); if type(data) ~= "table" then return {} end
    local keys = {}
    for k, v in pairs(data) do
        if type(k) == "string" and type(v) == "table" then keys[#keys + 1] = k end
    end
    return keys
end

local function doUpgrades()
    if cash() <= S.keepCash then return end
    if S.upgCheckout then
        local r = remote("BuyCheckoutUpgrade")
        if r then pcall(function() r:FireServer() end) end
    end
    if S.upgPot then
        local r = remote("BuyPotUpgrade")
        if r then
            for _, key in ipairs(potUpgradeKeys()) do
                pcall(function() r:FireServer(key) end)
            end
        end
    end
end

local function redeemAllCodes(silent)
    local rf = remote("RedeemCode"); if not rf then return end
    local d  = pdata()
    local done = d and d.RedeemedCodes or {}
    local n = 0
    for _, code in ipairs(CODES) do
        if not done[code] then
            local ok = pcall(function() return rf:InvokeServer(code) end)
            if ok then n = n + 1 end
            task.wait(0.25)
        end
    end
    if not silent then notify("Cook & Sell: redeemed " .. n .. " code(s).", 3) end
end

local function claimDaily(silent)
    local rf = remote("GetDailyLoginReward"); if not rf then return end
    pcall(function() return rf:InvokeServer() end)
    if not silent then notify("Cook & Sell: claimed daily login reward.", 3) end
end

local function hireCashierOnce()
    local rf = remote("HireCashier"); if not rf then return end
    pcall(function() return rf:InvokeServer() end)
end

-- ============================================================
--  master ticker (interval features; cooking has its own coroutine)
-- ============================================================
local tickConn
local function startTicker()
    if tickConn then return end
    tickConn = RunService.Heartbeat:Connect(function(dt)
        if S.stock and not S.stockBusy then
            S.stockAcc = S.stockAcc + dt
            if S.stockAcc >= S.stockInt then
                S.stockAcc = 0
                S.stockBusy = true
                task.spawn(function() pcall(placeAll); S.stockBusy = false end)
            end
        end
        if S.checkout and not S.checkoutBusy then
            S.checkoutAcc = S.checkoutAcc + dt
            if S.checkoutAcc >= S.checkoutInt then
                S.checkoutAcc = 0
                S.checkoutBusy = true
                task.spawn(function() pcall(doCheckout); S.checkoutBusy = false end)
            end
        end
        if S.collect then
            S.collectAcc = S.collectAcc + dt
            if S.collectAcc >= S.collectInt then S.collectAcc = 0; pcall(doCollect) end
        end
        if S.autoUpgrade then
            S.upgradeAcc = S.upgradeAcc + dt
            if S.upgradeAcc >= S.upgradeInt then S.upgradeAcc = 0; pcall(doUpgrades) end
        end
        if S.hireCashier then
            S.hireAcc = S.hireAcc + dt
            if S.hireAcc >= S.hireInt then S.hireAcc = 0; pcall(hireCashierOnce) end
        end
        if S.redeemAuto then
            S.redeemAcc = S.redeemAcc + dt
            if S.redeemAcc >= 60 then S.redeemAcc = 0; pcall(redeemAllCodes, true) end
        end
        if S.dailyAuto then
            S.dailyAcc = S.dailyAcc + dt
            if S.dailyAcc >= 120 then S.dailyAcc = 0; pcall(claimDaily, true) end
        end
    end)
end
local function stopTicker()
    if tickConn then tickConn:Disconnect(); tickConn = nil end
end

-- ============================================================
--  UI   (Page was created at the top so Cook & Sell is the first tab)
-- ============================================================

-- recipe dropdown items: "Auto" + the player's unlocked products
local recipeItems = { "Auto" }
do
    local seen = {}
    local d = pdata()
    if d then
        for _, src in ipairs({ d.UnlockedProducts, d.UncookedProducts }) do
            if type(src) == "table" then
                for k in pairs(src) do
                    if type(k) == "string" and not seen[k] then
                        seen[k] = true; recipeItems[#recipeItems + 1] = k
                    end
                end
            end
        end
    end
    table.sort(recipeItems, function(a, b)
        if a == "Auto" then return true end
        if b == "Auto" then return false end
        return a < b
    end)
end

-- ---------- Farm ----------
local Farm = Page:SubPage({ Name = "Farm" })
do
    local Sec = Farm:Section({ Name = "Cooking", Side = 1 })
    Sec:Label({ Name = "Tap-cook loop: load -> fill -> cook -> claim (+8 items)" })
    Sec:Toggle({
        Name = "Auto cook", Flag = "CS_AutoCook", Default = false,
        Callback = function(v) S.cook = v; if v then startCookLoop() end end,
    })
    Sec:Dropdown({
        Name = "Recipe", Flag = "CS_CookRecipe", Default = "Auto", Multi = false,
        Items = recipeItems,
        Callback = function(v) S.cookRecipe = (type(v) == "table" and v[1]) or v or "Auto" end,
    })
    Sec:Slider({
        Name = "Pickup wait", Flag = "CS_CookPick", Min = 0.15, Max = 1, Default = 0.32,
        Decimals = 2, Suffix = "s", Callback = function(v) S.cookPickWait = v end,
    })
    Sec:Slider({
        Name = "Drop wait", Flag = "CS_CookDrop", Min = 0.3, Max = 1.5, Default = 0.62,
        Decimals = 2, Suffix = "s", Callback = function(v) S.cookDropWait = v end,
    })
    Sec:Slider({
        Name = "Batch delay", Flag = "CS_CookLoop", Min = 0, Max = 5, Default = 0.5,
        Decimals = 1, Suffix = "s", Callback = function(v) S.cookLoopWait = v end,
    })
    Sec:Button({ Name = "Cook once", Callback = function() task.spawn(cookOnce) end })

    local St = Farm:Section({ Name = "Stocking", Side = 1 })
    St:Label({ Name = "Places cooked stacks onto open shelf slots" })
    St:Toggle({
        Name = "Auto stock shelves", Flag = "CS_AutoStock", Default = false,
        Callback = function(v) S.stock = v; S.stockAcc = 0 end,
    })
    St:Slider({
        Name = "Stock interval", Flag = "CS_StockInt", Min = 0.5, Max = 30, Default = 3,
        Decimals = 1, Suffix = "s", Callback = function(v) S.stockInt = v end,
    })
    St:Slider({
        Name = "Place delay", Flag = "CS_StockPlace", Min = 0.2, Max = 2, Default = 0.7,
        Decimals = 2, Suffix = "s", Callback = function(v) S.stockPlaceWait = v end,
    })
    St:Button({
        Name = "Place all now",
        Callback = function() task.spawn(function()
            local n = placeAll(); notify("Cook & Sell: placed " .. n .. " stack(s).", 3)
        end) end,
    })

    local Reg = Farm:Section({ Name = "Register", Side = 2 })
    if not FPP then
        Reg:Label({ Name = "fireproximityprompt missing in this executor" })
    end
    Reg:Toggle({
        Name = "Auto checkout customers", Flag = "CS_Checkout", Default = false,
        Callback = function(v) S.checkout = v; S.checkoutAcc = 0 end,
    })
    Reg:Slider({
        Name = "Checkout interval", Flag = "CS_CheckoutInt", Min = 0.2, Max = 10, Default = 0.5,
        Decimals = 1, Suffix = "s", Callback = function(v) S.checkoutInt = v end,
    })
    Reg:Slider({
        Name = "Scan speed", Flag = "CS_CheckoutScan", Min = 0.1, Max = 1, Default = 0.25,
        Decimals = 2, Suffix = "s", Callback = function(v) S.checkoutScanWait = v end,
    })
    Reg:Toggle({
        Name = "Auto collect cash", Flag = "CS_Collect", Default = false,
        Callback = function(v) S.collect = v; S.collectAcc = 0 end,
    })
    Reg:Slider({
        Name = "Collect interval", Flag = "CS_CollectInt", Min = 1, Max = 60, Default = 5,
        Decimals = 0, Suffix = "s", Callback = function(v) S.collectInt = v end,
    })
    Reg:Button({ Name = "Checkout now", Callback = function() task.spawn(doCheckout) end })
    Reg:Button({ Name = "Collect now",  Callback = function() pcall(doCollect)  end })
end

-- ---------- Economy ----------
local Eco = Page:SubPage({ Name = "Economy" })
do
    local Up = Eco:Section({ Name = "Upgrades", Side = 1 })
    Up:Toggle({
        Name = "Auto buy upgrades", Flag = "CS_AutoUpg", Default = false,
        Callback = function(v) S.autoUpgrade = v; S.upgradeAcc = 0 end,
    })
    Up:Toggle({ Name = "Pot upgrades",      Flag = "CS_UpgPot",  Default = true,
        Callback = function(v) S.upgPot = v end })
    Up:Toggle({ Name = "Checkout upgrades", Flag = "CS_UpgChk",  Default = true,
        Callback = function(v) S.upgCheckout = v end })
    Up:Slider({
        Name = "Interval", Flag = "CS_UpgInt", Min = 2, Max = 60, Default = 10,
        Decimals = 0, Suffix = "s", Callback = function(v) S.upgradeInt = v end,
    })
    Up:Slider({
        Name = "Keep cash above", Flag = "CS_KeepCash", Min = 0, Max = 1000000, Default = 0,
        Decimals = 0, Suffix = "$", Callback = function(v) S.keepCash = v end,
    })

    local Wk = Eco:Section({ Name = "Workers", Side = 2 })
    Wk:Label({ Name = "Cashier auto-serves the register (costs cash/cooldown)" })
    Wk:Toggle({
        Name = "Auto hire cashier", Flag = "CS_HireCashier", Default = false,
        Callback = function(v) S.hireCashier = v; S.hireAcc = 0 end,
    })
    Wk:Slider({
        Name = "Retry interval", Flag = "CS_HireInt", Min = 5, Max = 120, Default = 30,
        Decimals = 0, Suffix = "s", Callback = function(v) S.hireInt = v end,
    })
    Wk:Button({ Name = "Hire cashier now", Callback = hireCashierOnce })

    local Free = Eco:Section({ Name = "Free stuff", Side = 2 })
    Free:Button({ Name = "Redeem all codes", Callback = function() task.spawn(redeemAllCodes) end })
    Free:Toggle({ Name = "Auto redeem codes", Flag = "CS_RedeemAuto", Default = false,
        Callback = function(v) S.redeemAuto = v; S.redeemAcc = 55 end })
    Free:Button({ Name = "Claim daily login", Callback = function() task.spawn(claimDaily) end })
    Free:Toggle({ Name = "Auto claim daily", Flag = "CS_DailyAuto", Default = false,
        Callback = function(v) S.dailyAuto = v; S.dailyAcc = 115 end })
end

-- ---------- Info ----------
do
    local Info = Page:SubPage({ Name = "Info" })
    local Sec = Info:Section({ Name = "Status", Side = 1 })
    Sec:Label({ Name = "Pops a notification with live shop stats" })
    Sec:Button({
        Name = "Show stats",
        Callback = function()
            local d = pdata()
            if not d then notify("Cook & Sell: data not ready.", 3); return end
            local function count(t) local n = 0 if t then for _, v in pairs(t) do n = n + (type(v) == "number" and v or 1) end end return n end
            notify(("$%s | reg $%s | uncooked %d | unplaced %d | stocked %d")
                :format(tostring(d.Cash), tostring(d.CashRegisterBalance),
                    count(d.UncookedProducts), count(d.UnplacedProducts), count(d.StockedProducts)), 6)
        end,
    })
end

startTicker()

-- ============================================================
--  teardown: stop every loop on unload / re-execution
-- ============================================================
do
    local function full()
        S.cook = false
        S.stock = false
        S.checkout, S.collect, S.autoUpgrade = false, false, false
        S.hireCashier, S.redeemAuto, S.dailyAuto = false, false, false
        pcall(stopTicker)
    end
    local g = getgenv and getgenv()
    if g and g.WH then
        local prev = g.WH.disableAll
        local function wrapped()
            pcall(full)
            if prev then pcall(prev) end
        end
        g.WH.disableAll = wrapped
        Library.OnExit = wrapped
    else
        Library.OnExit = full
    end
end
