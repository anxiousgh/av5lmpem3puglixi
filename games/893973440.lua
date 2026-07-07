-- ============================================================
--  games/893973440.lua  --  Flee the Facility  (A.W. Apps)
--
--  Beast-vs-survivors: survivors hack computers to open the exits while
--  the beast downs them and freezes them in pods; teammates rescue.
--
--  Mechanics (decoded live 2026-07-07, PlaceVersion 324):
--    * ONE remote: ReplicatedStorage.RemoteEvent, string commands --
--        ("Input","Action",bool)   E press / release (hack, rescue, doors)
--        ("Input","Crawl",bool)    crawl down / stand up
--        ("Input","Trigger",bool)  client tells the server it's on a trigger
--        ("SetPlayerMinigameResult", bool)  <- the hack QTE verdict. The
--          CLIENT decides pass/fail (PlayerGui.ScreenGui.LocalGuiScript
--          line ~845: pin angle within [goal, goal+90] -> true).
--    * QTE state: Value objects under LocalPlayer.TempPlayerStatsModule --
--      TimingGoalPosition (goal angle; >0 starts a QTE, native handler
--      waits 0.4s then spins TimingPin from 0 at 360/(2-ActionProgress)
--      deg/s), ActionInput (a press; flipping it true exits the native pin
--      loop, which then reports the result itself), OnTrigger, IsBeast.
--      Auto-QTE below simulates a perfectly timed press through the game's
--      own path (remote + ActionInput), so exactly ONE result is sent and
--      the timing looks legit.
--    * Beast = the character carrying Model "Hammer" + "BeastPowers".
--    * Round state in ReplicatedStorage: CurrentMap (ObjectValue -> the
--      live map folder), ComputersLeft, GameStatus, IsGameActive.
--    * Computers = "ComputerTable" models in the map; Screen part color:
--      green = hacked, blue = still to do (read-only heuristic).
--    * Captured teammates = a player-named Model inside a "FreezePod".
--    * Exits = "ExitDoor" models; they matter once ComputersLeft == 0.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local FTF = {
    beastEsp = false,
    survEsp = false,
    compEsp = false,
    compShowHacked = false,
    podEsp = false,
    exitEsp = false,
    beastWarn = false,
    warnDist = 60,
    autoQte = false,
    qteHumanize = true,
}

local RED    = Color3.fromRGB(255, 60, 60)
local GREEN  = Color3.fromRGB(90, 220, 120)
local CYAN   = Color3.fromRGB(80, 190, 255)
local ORANGE = Color3.fromRGB(255, 170, 60)
local GREY   = Color3.fromRGB(160, 160, 160)

local function getStat(name)
    local ms = LocalPlayer:FindFirstChild("TempPlayerStatsModule")
    return ms and ms:FindFirstChild(name)
end

local function iAmBeast()
    local v = getStat("IsBeast")
    return v ~= nil and v.Value == true
end

local function isBeastChar(char)
    return char and (char:FindFirstChild("BeastPowers") or char:FindFirstChild("Hammer")) ~= nil
end

local function myRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function currentMap()
    local ov = ReplicatedStorage:FindFirstChild("CurrentMap")
    return ov and ov.Value
end

-- green screen = hacked (observed live: hacked 0.16,0.50,0.28 / todo 0.05,0.41,0.67)
local function isHacked(screen)
    local c = screen.Color
    return c.G > 0.4 and c.R < 0.3 and c.B < 0.35
end

-- ============================================================
--  ESP plumbing -- one Highlight + Billboard label per target, reused.
-- ============================================================
local esp = {}   -- [instance] = {hl=, bb=, label=}
local espGui

local function gui()
    if espGui and espGui.Parent then return espGui end
    espGui = Instance.new("Folder")
    espGui.Name = "\0"
    pcall(function() espGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    return espGui
end

local function dropEsp(inst)
    local e = esp[inst]
    if not e then return end
    esp[inst] = nil
    pcall(function() e.hl:Destroy() end)
    pcall(function() e.bb:Destroy() end)
end

local function getEsp(inst)
    local e = esp[inst]
    if e then return e end
    local hl = Instance.new("Highlight")
    hl.Name = "\0"; hl.FillTransparency = 0.6; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = inst; hl.Enabled = false; hl.Parent = gui()

    local bb = Instance.new("BillboardGui")
    bb.Name = "\0"; bb.Size = UDim2.fromOffset(220, 30)
    bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.Adornee = inst; bb.Enabled = false
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold; label.TextSize = 13
    label.TextStrokeTransparency = 0.3; label.TextColor3 = GREY
    label.Text = ""; label.Parent = bb
    bb.Parent = gui()

    e = { hl = hl, bb = bb, label = label }
    esp[inst] = e
    return e
end

local function show(inst, color, text)
    local e = getEsp(inst)
    e.hl.FillColor = color; e.hl.OutlineColor = color; e.hl.Enabled = true
    e.label.TextColor3 = color; e.label.Text = text; e.bb.Enabled = true
    e._shown = true
end

local function hide(inst)
    local e = esp[inst]
    if not e or not e._shown then return end
    e.hl.Enabled = false; e.bb.Enabled = false; e._shown = false
end

local function dist(pos)
    local r = myRoot()
    return r and (pos - r.Position).Magnitude or 0
end

local function fmtDist(pos)
    return tostring(math.floor(dist(pos) + 0.5)) .. "m"
end

-- ============================================================
--  Map object scan -- computers / pods / exits, rescanned slowly (maps are
--  cloned in per round; screen colors + pod occupants change mid-round).
-- ============================================================
local mapObjs = { comps = {}, pods = {}, exits = {}, map = nil }

local function rescanMap()
    local map = currentMap()
    if map ~= mapObjs.map then
        -- new round / map swap: drop every map-object ESP we made
        for inst in pairs(esp) do
            if not (inst:IsA("Model") and Players:GetPlayerFromCharacter(inst)) then
                if not inst:IsDescendantOf(workspace) or (mapObjs.map and inst:IsDescendantOf(mapObjs.map)) then
                    dropEsp(inst)
                end
            end
        end
        mapObjs.map = map
    end
    mapObjs.comps = {}; mapObjs.pods = {}; mapObjs.exits = {}
    if not map then return end
    for _, m in ipairs(map:GetChildren()) do
        if m.Name == "ComputerTable" then
            local screen = m:FindFirstChild("Screen")
            if screen then mapObjs.comps[#mapObjs.comps + 1] = { model = m, screen = screen } end
        elseif m.Name == "ExitDoor" then
            mapObjs.exits[#mapObjs.exits + 1] = m
        end
    end
    for _, m in ipairs(map:GetDescendants()) do
        if m.Name == "FreezePod" and m:IsA("Model") then
            mapObjs.pods[#mapObjs.pods + 1] = m
        end
    end
end

local function podOccupant(pod)
    for _, c in ipairs(pod:GetChildren()) do
        if c:IsA("Model") and Players:FindFirstChild(c.Name) then return c.Name end
    end
    return nil
end

-- ============================================================
--  Main tick -- players @ every pass, map objects on the same pass using
--  the slow-rescanned lists. 4 Hz is plenty for labels and warnings.
-- ============================================================
local lastWarn = 0
local tickAcc, scanAcc = 0, 0

track(RunService.Heartbeat:Connect(function(dt)
    tickAcc = tickAcc + dt
    if tickAcc < 0.25 then return end
    tickAcc = 0
    scanAcc = scanAcc + 0.25
    if scanAcc >= 1.5 then scanAcc = 0; rescanMap() end

    local selfBeast = iAmBeast()

    -- players
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if char and root then
                local beast = isBeastChar(char)
                if beast and FTF.beastEsp then
                    show(char, RED, "BEAST " .. p.Name .. " " .. fmtDist(root.Position))
                    if FTF.beastWarn and not selfBeast then
                        local d = dist(root.Position)
                        if d <= FTF.warnDist and tick() - lastWarn > 6 then
                            lastWarn = tick()
                            pcall(function()
                                Library:Notification(("BEAST %dm away"):format(d), 3, Library.Theme["Risky"])
                            end)
                        end
                    end
                elseif not beast and FTF.survEsp then
                    show(char, GREEN, p.Name .. " " .. fmtDist(root.Position))
                else
                    hide(char)
                end
            end
        end
    end

    -- computers
    for _, c in ipairs(mapObjs.comps) do
        if c.model.Parent then
            local hacked = isHacked(c.screen)
            if FTF.compEsp and not hacked then
                show(c.model, CYAN, "PC " .. fmtDist(c.screen.Position))
            elseif FTF.compEsp and FTF.compShowHacked then
                show(c.model, GREY, "done")
            else
                hide(c.model)
            end
        end
    end

    -- freeze pods (only occupied ones matter -- rescue targets)
    for _, pod in ipairs(mapObjs.pods) do
        if pod.Parent then
            local who = FTF.podEsp and podOccupant(pod) or nil
            local base = pod:FindFirstChild("BasePart")
            if who and base then
                show(pod, ORANGE, "RESCUE " .. who .. " " .. fmtDist(base.Position))
            else
                hide(pod)
            end
        end
    end

    -- exits (once every computer is hacked)
    local left = ReplicatedStorage:FindFirstChild("ComputersLeft")
    local exitsOpen = left and left.Value == 0
    for _, door in ipairs(mapObjs.exits) do
        if door.Parent then
            local base = door:FindFirstChildWhichIsA("BasePart")
            if FTF.exitEsp and exitsOpen and base then
                show(door, GREEN, "EXIT " .. fmtDist(base.Position))
            else
                hide(door)
            end
        end
    end
end))

-- ============================================================
--  Auto perfect QTE -- when the hack minigame pops, wait until the native
--  pin (TimingPin.Rotation, written by the game's own GUI loop every frame)
--  is inside the pass window, then simulate a real press: the exact remote
--  a key press fires + the ActionInput flip that exits the native loop --
--  which then sends SetPlayerMinigameResult(true) itself. One result, sent
--  by the game's own code, at a plausible reaction time into the window.
-- ============================================================
local qteWatch

local function pressAction()
    local re = ReplicatedStorage:FindFirstChild("RemoteEvent")
    if not re then return end
    re:FireServer("Input", "Action", true)
    local ai = getStat("ActionInput")
    if ai then ai.Value = true end
    task.delay(0.12 + math.random() * 0.1, function()
        pcall(function() re:FireServer("Input", "Action", false) end)
    end)
end

local function timingPin()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local sg = pg and pg:FindFirstChild("ScreenGui")
    local circle = sg and sg:FindFirstChild("TimingCircle")
    return circle and circle:FindFirstChild("TimingPin")
end

local function onQte(goal)
    if not FTF.autoQte or goal <= 0 or iAmBeast() then return end
    local pin = timingPin()
    if not pin then return end
    if qteWatch then qteWatch:Disconnect(); qteWatch = nil end
    -- press a random 15-65% into the 90-degree window (humanized), or right
    -- after entering it; never past 80% so a frame of lag can't miss.
    local into = FTF.qteHumanize and (13 + math.random() * 47) or 8
    local target = goal + into
    local t0 = tick()
    qteWatch = RunService.Heartbeat:Connect(function()
        local rot = pin.Rotation
        if rot >= target and rot <= goal + 82 then
            qteWatch:Disconnect(); qteWatch = nil
            pressAction()
        elseif rot > goal + 82 or tick() - t0 > 6 then
            qteWatch:Disconnect(); qteWatch = nil   -- armed too late / stale: let the game miss
        end
    end)
end

-- keyed per hub instance (NOT an attribute -- an attribute would survive a
-- re-exec and leave the fresh instance unhooked after teardown)
local qteArmed = setmetatable({}, { __mode = "k" })
local function armQte()
    local tgp = getStat("TimingGoalPosition")
    if not tgp or qteArmed[tgp] then return end
    qteArmed[tgp] = true
    track(tgp.Changed:Connect(function() onQte(tgp.Value) end))
end
armQte()
track(LocalPlayer.ChildAdded:Connect(function(c)
    if c.Name == "TempPlayerStatsModule" then task.defer(armQte) end
end))

-- ============================================================
--  UI  (Flee the Facility page first -> first tab; universal loads after)
-- ============================================================
do
    local Page = Window:Page({ Name = "Flee the Facility" })
    local Main = Page:SubPage({ Name = "Main" })

    local Sec = Main:Section({ Name = "ESP", Side = 1 })
    Sec:Toggle({ Name = "Beast ESP", Flag = "FTF_BeastEsp", Default = false,
        Callback = function(v) FTF.beastEsp = v end })
    Sec:Toggle({ Name = "Survivor ESP", Flag = "FTF_SurvEsp", Default = false,
        Callback = function(v) FTF.survEsp = v end })
    Sec:Toggle({ Name = "Computer ESP", Flag = "FTF_CompEsp", Default = false,
        Callback = function(v) FTF.compEsp = v end })
    Sec:Toggle({ Name = "Also show hacked computers", Flag = "FTF_CompHacked", Default = false,
        Callback = function(v) FTF.compShowHacked = v end })
    Sec:Toggle({ Name = "Freeze pod ESP (rescues)", Flag = "FTF_PodEsp", Default = false,
        Callback = function(v) FTF.podEsp = v end })
    Sec:Toggle({ Name = "Exit ESP (when doors open)", Flag = "FTF_ExitEsp", Default = false,
        Callback = function(v) FTF.exitEsp = v end })
    Sec:Label({ Name = "read-only: no remotes fired, nothing replicates" })

    local Sec2 = Main:Section({ Name = "Alerts", Side = 2 })
    Sec2:Toggle({ Name = "Beast proximity warning", Flag = "FTF_BeastWarn", Default = false,
        Callback = function(v) FTF.beastWarn = v end })
    Sec2:Slider({ Name = "Warn distance", Flag = "FTF_WarnDist", Min = 20, Max = 150, Default = 60,
        Decimals = 0, Suffix = " studs", Callback = function(v) FTF.warnDist = v end })
    Sec2:Label({ Name = "needs Beast ESP on (same scan feeds both)" })

    local Sec3 = Main:Section({ Name = "Auto Hack", Side = 2 })
    Sec3:Toggle({ Name = "Auto perfect QTE", Flag = "FTF_AutoQte", Default = false,
        Callback = function(v) FTF.autoQte = v end })
    Sec3:Toggle({ Name = "Humanize timing", Flag = "FTF_QteHumanize", Default = true,
        Callback = function(v) FTF.qteHumanize = v end })
    Sec3:Label({ Name = "you still hold E on the computer; this only" })
    Sec3:Label({ Name = "lands every skill check dead-on" })
end

-- universal shell after our page (movement + generic ESP). Movement is the
-- usual anti-cheat risk; everything on this page is read-only or fires the
-- exact remotes a legit key press fires.
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    FTF.beastEsp = false; FTF.survEsp = false; FTF.compEsp = false
    FTF.podEsp = false; FTF.exitEsp = false; FTF.autoQte = false
    if qteWatch then pcall(function() qteWatch:Disconnect() end); qteWatch = nil end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for inst in pairs(esp) do dropEsp(inst) end
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
