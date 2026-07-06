-- ============================================================
--  games/104522435597696.lua  --  The Animal Hospital  (Animal Anomaly)
--
--  Horror job sim: treat animal patients; some visitors are SKINWALKERS
--  (anomalies disguised as patients) you must spot before they get you.
--
--  Mechanic (decoded live 2026-07-07, PlaceVersion 253):
--    * Every visitor NPC is a Model with CollectionService tag "NPC".
--    * The server replicates the truth straight to the client as attributes:
--          Skinwalker = true            -> this visitor is a skinwalker
--          SkinwalkerRevealed = true    -> already unmasked in-game
--          CameraEffect / CameraEffect2 -> name of its DisguiseReveals module
--            (e.g. "HiddenFace", "TwistNeck") -- the camera/photo systems use
--            these to render the reveal LOCALLY (PlayerScripts.UI.
--            SkinwalkerDisguiseRevealLocal), which is why the client knows.
--          IsPatient / InBed / DesignatedRoom / Strikes / MAX_STRIKES etc.
--    * So detection is a pure attribute read -- no remotes fired, nothing
--      replicates back to the server. ESP here is as safe as it gets.
--
--  Illness/cure data (ReplicatedStorage.Data.IllnessesAndCures) exists
--  client-side but the per-patient illness assignment wasn't confirmed
--  before the bridge dropped -- TODO next live session.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer       = Players.LocalPlayer

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local AH = {
    esp = false,
    showSafe = true,
    alert = true,
    cureMonitor = true,
    cureNotify = true,
}
local knownCures = {}   -- [patientName] = "Herbs" / "Bandages (SURGERY)" (filled by the cure helper below)

local RED   = Color3.fromRGB(255, 60, 60)
local GREEN = Color3.fromRGB(90, 220, 120)
local GREY  = Color3.fromRGB(200, 200, 200)

-- observed live: Skinwalker=true and Fake=true are separate anomaly flags
-- (a visitor can carry either); both mean "not a real patient"
local function anomalyType(npc)
    local sw = npc:GetAttribute("Skinwalker") == true
    local fake = npc:GetAttribute("Fake") == true
    if sw and fake then return "SKINWALKER+FAKE" end
    if sw then return "SKINWALKER" end
    if fake then return "FAKE" end
    return nil
end

local function revealNames(npc)
    local parts = {}
    for _, k in ipairs({ "CameraEffect", "CameraEffect2", "PhotoEffect", "PhotoEffect2" }) do
        local v = npc:GetAttribute(k)
        if v and v ~= "" then parts[#parts + 1] = tostring(v) end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "+")
end

-- ============================================================
--  SKINWALKER ESP -- per-NPC highlight + label, driven purely by the
--  server-replicated attributes above. Red = skinwalker, green = safe.
-- ============================================================
local esp = {}   -- [npc] = {hl=, bb=, label=, alerted=}
local espGui

local function gui()
    if espGui and espGui.Parent then return espGui end
    espGui = Instance.new("Folder")
    espGui.Name = "\0"
    pcall(function() espGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    return espGui
end

local function dropEsp(npc)
    local e = esp[npc]
    if not e then return end
    esp[npc] = nil
    pcall(function() e.hl:Destroy() end)
    pcall(function() e.bb:Destroy() end)
end

local function makeEsp(npc)
    if esp[npc] then return end
    local hl = Instance.new("Highlight")
    hl.Name = "\0"; hl.FillTransparency = 0.55; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = npc; hl.Enabled = false; hl.Parent = gui()

    local bb = Instance.new("BillboardGui")
    bb.Name = "\0"; bb.Size = UDim2.fromOffset(220, 34)
    bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0, 3.2, 0)
    bb.Adornee = npc; bb.Enabled = false
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold; label.TextSize = 14
    label.TextStrokeTransparency = 0.3; label.TextColor3 = GREY
    label.Text = ""; label.Parent = bb
    bb.Parent = gui()

    esp[npc] = { hl = hl, bb = bb, label = label, alerted = false }
end

local function alertIfAnomaly(npc)
    local e = esp[npc]
    if not e or e.alerted then return end
    local kind = anomalyType(npc)
    if AH.alert and kind then
        e.alerted = true
        pcall(function()
            Library:Notification(kind .. ": " .. npc.Name, 5, Library.Theme["Risky"])
        end)
    end
end

local function hookNpc(npc)
    makeEsp(npc)
    alertIfAnomaly(npc)
    -- the attributes can land after the tag does -> watch for them
    track(npc:GetAttributeChangedSignal("Skinwalker"):Connect(function()
        alertIfAnomaly(npc)
    end))
    track(npc:GetAttributeChangedSignal("Fake"):Connect(function()
        alertIfAnomaly(npc)
    end))
    track(npc.AncestryChanged:Connect(function(_, parent)
        if not parent then dropEsp(npc) end
    end))
end

for _, npc in ipairs(CollectionService:GetTagged("NPC")) do hookNpc(npc) end
track(CollectionService:GetInstanceAddedSignal("NPC"):Connect(hookNpc))
track(CollectionService:GetInstanceRemovedSignal("NPC"):Connect(dropEsp))

-- label/color refresh; cheap at visitor counts (<20), skinwalker state can
-- flip mid-visit so we re-read the attributes rather than caching them
track(RunService.Heartbeat:Connect(function()
    for npc, e in pairs(esp) do
        if not npc.Parent then
            dropEsp(npc)
        elseif not AH.esp then
            if e.hl.Enabled then e.hl.Enabled = false; e.bb.Enabled = false end
        else
            local kind = anomalyType(npc)
            local show = kind ~= nil or AH.showSafe
            e.hl.Enabled = show
            e.bb.Enabled = show
            if show then
                local col = kind and RED or GREEN
                e.hl.FillColor = col; e.hl.OutlineColor = col
                e.label.TextColor3 = col
                if kind then
                    local extra = revealNames(npc)
                    local room = npc:GetAttribute("DesignatedRoom")
                    e.label.Text = kind .. "  " .. npc.Name
                        .. (room and ("  [" .. tostring(room) .. "]") or "")
                        .. (extra and ("\n" .. extra) or "")
                    e.bb.Size = UDim2.fromOffset(220, extra and 44 or 34)
                else
                    local cure = knownCures[npc.Name]
                    e.label.Text = npc.Name .. "  (safe)"
                        .. (cure and ("\n-> " .. cure) or "")
                    e.bb.Size = UDim2.fromOffset(220, cure and 44 or 34)
                end
            end
        end
    end
end))

-- ============================================================
--  CURE HELPER -- decoded live 2026-07-07: when the analyzer minigame
--  finishes, the SERVER writes the DNA report straight onto the room
--  monitor (Rooms.*.RoomN.Minigame.Monitor.Screen.UI.Report: `race` =
--  patient name, `illnesses` = "- Stomach Ache\n- ..."). No client script
--  touches those labels (pure property replication), so the illness is
--  client-knowable the moment the report lands -- and the full
--  illness -> cure map ships in ReplicatedStorage.Data.IllnessesAndCures
--  (11 illnesses, HealedWith + Surgery flag). We parse the report, append
--  " -> cure" onto its lines, notify, and tag the patient's ESP label.
--  Idle monitors hold placeholder text with no live patient name in
--  `race`, so reports are gated on the name matching a tagged NPC.
-- ============================================================
local notifiedCure = {} -- [patientName .. "|" .. cures] = true

local IC
pcall(function()
    IC = require(game.ReplicatedStorage:WaitForChild("Data"):WaitForChild("IllnessesAndCures"))
end)

local function cureFor(illnessName)
    if not IC then return nil end
    local okI, ill = pcall(IC.GetIllnessByName, illnessName)
    if not okI or not ill then return nil end
    local cureName = ill.HealedWith
    local surgery = false
    pcall(function()
        local cure = IC.GetCureForIllness(ill)
        surgery = (cure and cure.Surgery) == true
    end)
    if not cureName or cureName == "Nothing" then return nil end
    return tostring(cureName), surgery
end

local function processReport(illLabel)
    if not (AH.cureMonitor or AH.cureNotify) then return end
    local report = illLabel.Parent
    local raceL = report and report:FindFirstChild("race")
    local patient = (raceL and raceL:IsA("TextLabel")) and raceL.Text or ""
    if patient == "" then return end
    local live = false
    for _, npc in ipairs(CollectionService:GetTagged("NPC")) do
        if npc.Name == patient then live = true break end
    end
    if not live then return end
    if illLabel.Text:find("->", 1, true) then return end -- already annotated (our write)

    local lines, cures = {}, {}
    for line in illLabel.Text:gmatch("[^\n]+") do
        local name = line:gsub("^%s*%-%s*", ""):gsub("%s+$", "")
        local cure, surgery = cureFor(name)
        if cure then
            local tag = cure .. (surgery and " (SURGERY)" or "")
            cures[#cures + 1] = tag
            lines[#lines + 1] = line .. "  -> " .. tag
        else
            lines[#lines + 1] = line
        end
    end
    if #cures == 0 then return end

    knownCures[patient] = table.concat(cures, ", ")
    if AH.cureMonitor then
        pcall(function() illLabel.Text = table.concat(lines, "\n") end)
    end
    local key = patient .. "|" .. knownCures[patient]
    if AH.cureNotify and not notifiedCure[key] then
        notifiedCure[key] = true
        pcall(function()
            Library:Notification(patient .. ": " .. knownCures[patient], 6, Library.Theme["Accent"])
        end)
    end
end

local function hookReport(illLabel)
    track(illLabel:GetPropertyChangedSignal("Text"):Connect(function()
        processReport(illLabel)
    end))
    -- the patient name can land after the illness list -> watch it too
    local raceL = illLabel.Parent and illLabel.Parent:FindFirstChild("race")
    if raceL and raceL:IsA("TextLabel") then
        track(raceL:GetPropertyChangedSignal("Text"):Connect(function()
            processReport(illLabel)
        end))
    end
    processReport(illLabel)
end

for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("TextLabel") and d.Name == "illnesses" then hookReport(d) end
end
track(workspace.DescendantAdded:Connect(function(d)
    if d:IsA("TextLabel") and d.Name == "illnesses" then task.defer(hookReport, d) end
end))

-- patient left -> forget their cure (names recycle across visitors)
track(CollectionService:GetInstanceRemovedSignal("NPC"):Connect(function(npc)
    knownCures[npc.Name] = nil
end))

-- ============================================================
--  UI  (Animal Hospital page first -> first tab; universal loads after)
-- ============================================================
do
    local Page = Window:Page({ Name = "Animal Hospital" })
    local Main = Page:SubPage({ Name = "Anomalies" })

    local Sec = Main:Section({ Name = "Skinwalker ESP", Side = 1 })
    Sec:Toggle({ Name = "Skinwalker ESP", Flag = "AH_Esp", Default = false,
        Callback = function(v) AH.esp = v end })
    Sec:Toggle({ Name = "Also show safe visitors", Flag = "AH_EspSafe", Default = true,
        Callback = function(v) AH.showSafe = v end })
    Sec:Label({ Name = "red = skinwalker / fake (server tells the client)" })
    Sec:Label({ Name = "read-only: no remotes fired, nothing replicates" })

    local Sec2 = Main:Section({ Name = "Alerts", Side = 2 })
    Sec2:Toggle({ Name = "Notify when an anomaly spawns", Flag = "AH_Alert", Default = true,
        Callback = function(v) AH.alert = v end })

    local Sec3 = Main:Section({ Name = "Cure Helper", Side = 2 })
    Sec3:Toggle({ Name = "Cure on DNA report", Flag = "AH_CureMonitor", Default = true,
        Callback = function(v) AH.cureMonitor = v end })
    Sec3:Toggle({ Name = "Notify illness -> cure", Flag = "AH_CureNotify", Default = true,
        Callback = function(v) AH.cureNotify = v end })
    Sec3:Label({ Name = "reads the server-written DNA report; cure also on ESP" })
end

-- universal shell after our page (movement + generic ESP). Horror game,
-- anti-cheat unknown -- the attribute ESP above is the safe core.
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    AH.esp = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for npc in pairs(esp) do dropEsp(npc) end
    pcall(function() if espGui then espGui:Destroy() end end)
end
do
    local g = (getgenv and getgenv()) or nil
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full() pcall(cleanup); if prev then pcall(prev) end end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
