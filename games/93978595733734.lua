-- ============================================================
--  games/93978595733734.lua  --  [CURE] Violence District
--
--  Dead-by-Daylight-style asym horror: Survivors repair 7 generators while a
--  Killer (Cure/Veil/Stalker/Jason/...) hunts, hooks, and breaks things.
--
--  Decoded live 2026-07-03:
--    * Teams: "Survivors" / "Killer" / "Spectator" -- role = player.Team.Name.
--    * Generators: models under a "Generators" folder in workspace.Map with
--      attributes RepairProgress (0-100), Completed, Regressing, ProgressPaused,
--      PlayersRepairingCount. Map layout varies per map -> folders are found by
--      NAME anywhere under workspace.Map (Pallets/Vaults/Hooks may be absent).
--    * Killer character carries live attrs: Speed, IsChasing, ChaseTargetUserId,
--      TerrorRadius, SuspenseRadius, BloodLust, HookCount, breakspeed -- free
--      intel for the survivor side.
--    * Skill checks are CLIENT-decided: on fail the client itself fires
--      RepairEvent:FireServer(gen, false, 1.5) (SurvivorAnimationsController
--      _onSkillCheckFail). The minigame UI is PlayerGui.SkillCheckPromptGui
--      (and -con for console): Frame "Check" > rotating "Line", success zone
--      "Goal", "Space" prompt. Auto skill check watches Line's angular velocity
--      and presses Space exactly when it reaches the Goal zone -- no remote
--      spoofing at all, so there is nothing for the server to validate against.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end
local function espParent()
    return (gethui and gethui()) or game:GetService("CoreGui")
end
local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
--  ROLES / MAP LOOKUP
-- ============================================================
local function teamName(p) return (p.Team and p.Team.Name) or "" end
local function isKiller(p) return teamName(p) == "Killer" end
local function isSurvivor(p) return teamName(p) == "Survivors" end

local function getKillerPlayer()
    for _, p in ipairs(Players:GetPlayers()) do
        if isKiller(p) then return p end
    end
    return nil
end

-- Map folders (Generators/Pallets/Vaults/Hooks) move around per map; rescan
-- lazily instead of caching paths.
local mapFolders, lastScan = {}, 0
local function getMapFolder(name)
    local now = os.clock()
    if now - lastScan > 3 then
        lastScan = now
        mapFolders = {}
        local map = workspace:FindFirstChild("Map")
        if map then
            for _, d in ipairs(map:GetDescendants()) do
                if d:IsA("Folder") and not mapFolders[d.Name] then
                    mapFolders[d.Name] = d
                end
            end
        end
    end
    local f = mapFolders[name]
    return (f and f.Parent) and f or nil
end

local function genProgress(gen)
    return gen:GetAttribute("RepairProgress") or 0,
        gen:GetAttribute("Completed") == true,
        gen:GetAttribute("Regressing") == true
end

-- ============================================================
--  ESP POOLS  -- one Highlight + BillboardGui per tracked instance
-- ============================================================
-- ---------- GUI-matched theme ----------
-- Colors + font come straight from the menu library so the ESP reads as part
-- of the same UI: lavender accent, muted purple, "Risky" red, mono Code font.
local T = (Library and Library.Theme) or {}
local PAL = {
    killer  = T["Risky"] or Color3.fromRGB(255, 70, 80),
    accent  = T["Accent"] or Color3.fromRGB(200, 183, 247),
    muted   = T["Inactive Text"] or Color3.fromRGB(131, 120, 162),
    text    = T["Text"] or Color3.fromRGB(240, 240, 242),
    bg      = T["Background"] or Color3.fromRGB(22, 22, 25),
    outline = T["Outline"] or Color3.fromRGB(62, 57, 77),
}
local ESP_FONT = (Library and Library.Font) or Font.fromEnum(Enum.Font.Code)
local function hex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local HEX = { killer = hex(PAL.killer), accent = hex(PAL.accent), muted = hex(PAL.muted) }

local S = {
    killerEsp     = false,
    survEsp       = false,
    genEsp        = false,
    genHideDone   = true,
    objEsp        = false,   -- hooks / pallets / vaults
    autoSkill     = false,
    skillMode     = "Legit", -- "Legit" rides the needle, "Instant" snaps it
    skillHumanize = 25,      -- max extra reaction delay (ms) in Legit mode
    chaseWarn     = false,
}

local pool = {}   -- [Instance] = { hl=?, bb=?, lbl=?, used=bool }
local function getEsp(key, adornee, withHl)
    local e = pool[key]
    if not e then
        e = {}
        if withHl then
            e.hl = Instance.new("Highlight")
            e.hl.Name = "\0"
            e.hl.FillTransparency = 0.65
            e.hl.OutlineTransparency = 0
            e.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            pcall(function() e.hl.Parent = espParent() end)
        end
        e.bb = Instance.new("BillboardGui")
        e.bb.Name = "\0"
        e.bb.Size = UDim2.fromOffset(240, 22)
        e.bb.AlwaysOnTop = true
        e.bb.StudsOffset = Vector3.new(0, 3.2, 0)
        -- label styled like a menu element: snug dark box, thin purple outline,
        -- mono font, white text with theme-colored tags via rich text
        e.lbl = Instance.new("TextLabel")
        e.lbl.AnchorPoint = Vector2.new(0.5, 0.5)
        e.lbl.Position = UDim2.fromScale(0.5, 0.5)
        e.lbl.Size = UDim2.new()
        e.lbl.AutomaticSize = Enum.AutomaticSize.XY
        e.lbl.BackgroundColor3 = PAL.bg
        e.lbl.BackgroundTransparency = 0.15
        e.lbl.BorderSizePixel = 0
        e.lbl.RichText = true
        e.lbl.FontFace = ESP_FONT
        e.lbl.TextSize = 12
        e.lbl.TextColor3 = PAL.text
        e.lbl.TextStrokeTransparency = 1
        local pad = Instance.new("UIPadding")
        pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
        pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2)
        pad.Parent = e.lbl
        local stroke = Instance.new("UIStroke")
        stroke.Color = PAL.outline
        stroke.Thickness = 1
        stroke.Parent = e.lbl
        e.lbl.Parent = e.bb
        pcall(function() e.bb.Parent = espParent() end)
        pool[key] = e
    end
    if e.hl then e.hl.Adornee = adornee; e.hl.Enabled = true end
    e.bb.Adornee = adornee
    e.bb.Enabled = true
    e.used = true
    return e
end
local function sweepPool()
    for key, e in pairs(pool) do
        if not e.used then
            if e.hl then e.hl.Enabled = false; e.hl.Adornee = nil end
            e.bb.Enabled = false
            e.bb.Adornee = nil
            if typeof(key) == "Instance" and not key.Parent then
                if e.hl then pcall(function() e.hl:Destroy() end) end
                pcall(function() e.bb:Destroy() end)
                pool[key] = nil
            end
        else
            e.used = false
        end
    end
end

local function paint(e, col)
    if e.hl then e.hl.FillColor = col; e.hl.OutlineColor = col end
end

-- ---------- players ----------
local function stepPlayerEsp()
    local hrp = myHRP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local want = (isKiller(p) and S.killerEsp) or (isSurvivor(p) and S.survEsp)
            local c = p.Character
            local root = c and c:FindFirstChild("HumanoidRootPart")
            if want and root then
                local e = getEsp(p, c, true)
                paint(e, isKiller(p) and PAL.killer or PAL.accent)
                local dist = hrp and math.floor((root.Position - hrp.Position).Magnitude + 0.5) or 0
                if isKiller(p) then
                    local kname = tostring(p:GetAttribute("SelectedKiller") or "KILLER"):upper()
                    e.lbl.Text = ('<font color="%s"><b>%s</b></font> %s <font color="%s">%dm</font>')
                        :format(HEX.killer, kname, p.Name, HEX.muted, dist)
                else
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    local hp = hum and (math.floor(hum.Health + 0.5) .. "hp ") or ""
                    e.lbl.Text = ('%s <font color="%s">%s%dm</font>')
                        :format(p.Name, HEX.muted, hp, dist)
                end
            end
        end
    end
end

-- ---------- generators ----------
local function stepGenEsp()
    if not S.genEsp then return end
    local gens = getMapFolder("Generators") or getMapFolder("Gens")
    if not gens then return end
    local hrp = myHRP()
    for _, gen in ipairs(gens:GetChildren()) do
        local root = gen:FindFirstChild("RootPart") or gen:FindFirstChildWhichIsA("BasePart")
        if root then
            local prog, done, regress = genProgress(gen)
            if not (done and S.genHideDone) then
                local e = getEsp(gen, root, true)
                paint(e, done and PAL.muted or (regress and PAL.killer or PAL.accent))
                if e.hl then e.hl.FillTransparency = 0.85 end
                local dist = hrp and (('<font color="%s"> %dm</font>')
                    :format(HEX.muted, math.floor((root.Position - hrp.Position).Magnitude + 0.5))) or ""
                e.lbl.Text = done and (('<font color="%s">GEN DONE</font>'):format(HEX.muted) .. dist)
                    or (('<font color="%s"><b>GEN %d%%</b></font>%s%s'):format(
                        HEX.accent, math.floor(prog + 0.5),
                        regress and ((' <font color="%s">REGRESSING</font>'):format(HEX.killer)) or "", dist))
            end
        end
    end
end

-- ---------- hooks / pallets / vaults ----------
local OBJ_FOLDERS = { { "Hooks", "HOOK", "killer" }, { "Pallets", "PALLET", "accent" }, { "Vaults", "VAULT", "muted" } }
local function stepObjEsp()
    if not S.objEsp then return end
    for _, spec in ipairs(OBJ_FOLDERS) do
        local f = getMapFolder(spec[1])
        if f then
            for _, obj in ipairs(f:GetChildren()) do
                local root = obj:IsA("BasePart") and obj
                    or obj:FindFirstChild("RootPart")
                    or obj:FindFirstChildWhichIsA("BasePart")
                if root then
                    local e = getEsp(obj, root, false)
                    e.lbl.Text = ('<font color="%s">%s</font>'):format(HEX[spec[3]], spec[2])
                    e.bb.StudsOffset = Vector3.new(0, 1.6, 0)
                end
            end
        end
    end
end

track(RunService.RenderStepped:Connect(function()
    if S.killerEsp or S.survEsp then stepPlayerEsp() end
    stepGenEsp()
    stepObjEsp()
    sweepPool()
end))

-- ============================================================
--  AUTO SKILL CHECK
--  The minigame is pure client UI: "Line" sweeps around the circle, "Goal"
--  marks the success zone. We measure Line's angular velocity each frame and
--  press Space when the time-to-goal drops under the lead time. One press per
--  check; re-arms when the check hides or the goal jumps to a new angle.
-- ============================================================
local VIM = game:GetService("VirtualInputManager")
local function pressSpace()
    local ok = pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.02)
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    if not ok and keypress then
        pcall(function() keypress(0x20); task.wait(0.02); keyrelease(0x20) end)
    end
end

local function findCheck()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, name in ipairs({ "SkillCheckPromptGui", "SkillCheckPromptGui-con" }) do
        local g = pg:FindFirstChild(name)
        if g and g.Enabled then
            local c = g:FindFirstChild("Check", true)
            if c and c.Visible then
                local line, goal = c:FindFirstChild("Line"), c:FindFirstChild("Goal")
                if line and goal then return c, line, goal end
            end
        end
    end
    return nil
end

do
    -- deactivate any lingering standalone vd-autoskill.lua instance (it snaps
    -- the needle and finishes every check instantly) -- this page owns it now
    if getgenv then getgenv().__VD_AUTOSKILL = (getgenv().__VD_AUTOSKILL or 0) + 1 end

    -- success zone (decoded from the game's Skillcheck script): a press lands
    -- when (Line.Rotation - Goal.Rotation) % 360 is inside [102, 116]
    local ZONE_LO, ZONE_HI = 102, 116

    local lastRot, lastT, vel = nil, nil, 0
    local armed, armedGoal, targetRel = true, nil, nil
    local lastInstant = 0

    track(RunService.RenderStepped:Connect(function()
        if not S.autoSkill then return end
        local check, line, goal = findCheck()
        if not check then
            lastRot, lastT, vel, armed, armedGoal, targetRel = nil, nil, 0, true, nil, nil
            return
        end
        -- goal jumped -> a fresh check inside the same visible session
        if armedGoal ~= nil and math.abs(goal.Rotation - armedGoal) > 5 then
            armed, targetRel = true, nil
        end
        armedGoal = goal.Rotation

        if S.skillMode == "Instant" then
            if os.clock() - lastInstant < 0.1 then return end
            lastInstant = os.clock()
            pcall(function() line.Rotation = goal.Rotation + 109 end)   -- mid-zone
            pressSpace()
            return
        end

        -- ---- Legit: ride the game's own needle, press inside the zone ----
        local now = os.clock()
        if lastRot ~= nil and lastT ~= nil and now > lastT then
            local d = (line.Rotation - lastRot + 540) % 360 - 180   -- signed shortest delta
            local v = d / (now - lastT)
            vel = vel == 0 and v or (vel * 0.7 + v * 0.3)
        end
        lastRot, lastT = line.Rotation, now

        if not armed or math.abs(vel) < 20 then return end
        local dir = vel >= 0 and 1 or -1

        -- press spot: random angle in the early half of the zone (relative to
        -- travel direction), re-rolled per check so timing never looks scripted
        if not targetRel then
            targetRel = dir == 1 and math.random(ZONE_LO + 2, ZONE_LO + 8)
                or math.random(ZONE_HI - 8, ZONE_HI - 2)
        end

        local rel = (line.Rotation - goal.Rotation) % 360
        if rel < ZONE_LO or rel > ZONE_HI then return end             -- not in zone yet
        local passed = (dir == 1 and rel >= targetRel) or (dir == -1 and rel <= targetRel)
        if not passed then return end
        armed = false

        -- humanized reaction: small random delay, capped so the needle can't
        -- leave the zone before the press lands
        local remain = (dir == 1 and (ZONE_HI - rel) or (rel - ZONE_LO)) / math.abs(vel)
        local delay = math.min(math.random(0, math.max(S.skillHumanize, 0)) / 1000,
            math.max(remain - 0.03, 0))
        if delay > 0.001 then
            task.delay(delay, function()
                if S.autoSkill then pressSpace() end
            end)
        else
            pressSpace()
        end
    end))
end

-- ============================================================
--  KILLER INTEL  -- live readout of the killer's attributes + chase warning
-- ============================================================
local warnGui, warnLbl
do
    warnGui = Instance.new("ScreenGui")
    warnGui.Name = "\0"
    warnGui.IgnoreGuiInset = true
    warnGui.Enabled = false
    warnLbl = Instance.new("TextLabel")
    warnLbl.BackgroundTransparency = 1
    warnLbl.Size = UDim2.new(1, 0, 0, 34)
    warnLbl.Position = UDim2.new(0, 0, 0, 90)
    warnLbl.FontFace = ESP_FONT
    warnLbl.TextSize = 26
    warnLbl.TextColor3 = PAL.killer
    warnLbl.TextStrokeTransparency = 0.2
    warnLbl.Text = "!!  YOU ARE BEING CHASED  !!"
    warnLbl.Parent = warnGui
    pcall(function() warnGui.Parent = espParent() end)
end

-- ---------- mouse-lock handoff ----------
-- This game's look scripts lock the mouse and do NOT re-assert the lock after
-- the menu frees the cursor, so closing the menu left the camera dead. Sample
-- whatever MouseBehavior the game runs while the menu is CLOSED, and hand that
-- exact mode back the moment it closes again (self-calibrating: lobby/spectate
-- naturally record Default and get Default back).
do
    local UIS = game:GetService("UserInputService")
    local lastGameMouseMode = UIS.MouseBehavior
    track(RunService.Heartbeat:Connect(function()
        if not Library.WindowOpenState then
            lastGameMouseMode = UIS.MouseBehavior
        end
    end))
    pcall(function()
        Library:BindToWindowVisibility(function(open)
            if open then return end
            local restore = lastGameMouseMode
            task.defer(function()
                pcall(function() UIS.MouseBehavior = restore end)
            end)
        end)
    end)
end

local intelLabels = {}   -- filled in the UI block below
local wasChased = false
local lastIntel = 0
track(RunService.Heartbeat:Connect(function()
    local kp = getKillerPlayer()
    local kc = kp and kp.Character
    local chased = false
    if kc then
        local target = kc:GetAttribute("ChaseTargetUserId")
        chased = (target == LocalPlayer.UserId) and kc:GetAttribute("IsChasing") == true
    end
    if S.chaseWarn and chased then
        warnGui.Enabled = true
        warnLbl.TextTransparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 7))
        if not wasChased then
            pcall(function() Library:Notification("The killer is chasing YOU", 3, PAL.killer) end)
        end
    else
        warnGui.Enabled = false
    end
    wasChased = chased

    -- labels only need a few updates a second; SetText at 60 Hz is wasted work
    if os.clock() - lastIntel < 0.25 then return end
    lastIntel = os.clock()

    if intelLabels.killer then
        local hrp = myHRP()
        if kp and kc then
            local root = kc:FindFirstChild("HumanoidRootPart")
            local dist = (hrp and root) and (math.floor((root.Position - hrp.Position).Magnitude + 0.5) .. "m") or "?"
            intelLabels.killer:SetText("Killer: " .. tostring(kp:GetAttribute("SelectedKiller") or "?") .. " (" .. kp.Name .. ")")
            intelLabels.dist:SetText("Distance: " .. dist .. "   Speed: " .. tostring(kc:GetAttribute("Speed") or "?"))
            local tgt = "-"
            local tid = kc:GetAttribute("ChaseTargetUserId")
            if tid then
                local tp = Players:GetPlayerByUserId(tid)
                tgt = tp and tp.Name or tostring(tid)
            end
            intelLabels.chase:SetText("Chasing: " .. (kc:GetAttribute("IsChasing") and tgt or "-")
                .. "   BloodLust: " .. tostring(kc:GetAttribute("BloodLust") or 0))
        else
            intelLabels.killer:SetText("Killer: -")
            intelLabels.dist:SetText("Distance: -")
            intelLabels.chase:SetText("Chasing: -")
        end
        local gens = getMapFolder("Generators") or getMapFolder("Gens")
        if gens then
            local done, total = 0, 0
            for _, gen in ipairs(gens:GetChildren()) do
                total = total + 1
                if gen:GetAttribute("Completed") then done = done + 1 end
            end
            intelLabels.gens:SetText("Generators: " .. done .. "/" .. total .. " done")
        end
    end
end))

-- ============================================================
--  UI  (Violence District page first -> first tab; universal loads after)
-- ============================================================
do
    local Page = Window:Page({ Name = "Violence District" })

    local Vis = Page:SubPage({ Name = "ESP" })
    local PSec = Vis:Section({ Name = "Players", Side = 1 })
    PSec:Toggle({ Name = "Killer ESP", Flag = "VD_KillerEsp", Default = false,
        Callback = function(v) S.killerEsp = v end })
    PSec:Toggle({ Name = "Survivor ESP", Flag = "VD_SurvEsp", Default = false,
        Callback = function(v) S.survEsp = v end })
    PSec:Label({ Name = "red = killer, green = survivors (through walls)" })

    local OSec = Vis:Section({ Name = "Objectives", Side = 2 })
    OSec:Toggle({ Name = "Generator ESP (live %)", Flag = "VD_GenEsp", Default = false,
        Callback = function(v) S.genEsp = v end })
    OSec:Toggle({ Name = "Hide completed gens", Flag = "VD_GenHideDone", Default = true,
        Callback = function(v) S.genHideDone = v end })
    OSec:Toggle({ Name = "Hooks / Pallets / Vaults", Flag = "VD_ObjEsp", Default = false,
        Callback = function(v) S.objEsp = v end })
    OSec:Label({ Name = "orange gen = regressing, green = done" })

    local Game = Page:SubPage({ Name = "Gameplay" })
    local SSec = Game:Section({ Name = "Skill checks", Side = 1 })
    SSec:Toggle({ Name = "Auto skill check", Flag = "VD_AutoSkill", Default = false,
        Callback = function(v) S.autoSkill = v end })
    SSec:Dropdown({ Name = "Mode", Flag = "VD_SkillMode", Default = "Legit", Multi = false,
        Items = { "Legit", "Instant" },
        Callback = function(v) S.skillMode = (type(v) == "table" and v[1]) or v or "Legit" end })
    SSec:Slider({ Name = "Humanize", Flag = "VD_SkillHumanize", Min = 0, Max = 80, Default = 25,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.skillHumanize = v end })
    SSec:Label({ Name = "legit: waits for the needle, random press spot" })
    SSec:Label({ Name = "instant: snaps the needle, finishes immediately" })

    local KSec = Game:Section({ Name = "Killer intel", Side = 2 })
    KSec:Toggle({ Name = "Chase warning", Flag = "VD_ChaseWarn", Default = false,
        Callback = function(v) S.chaseWarn = v end })
    intelLabels.killer = KSec:Label({ Name = "Killer: -" })
    intelLabels.dist   = KSec:Label({ Name = "Distance: -" })
    intelLabels.chase  = KSec:Label({ Name = "Chasing: -" })
    intelLabels.gens   = KSec:Label({ Name = "Generators: -" })
end

-- universal shell after our page (movement + generic player ESP). No combat
-- module -- there is nothing to aimbot here.
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    S.killerEsp, S.survEsp, S.genEsp, S.objEsp, S.autoSkill, S.chaseWarn = false, false, false, false, false, false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, e in pairs(pool) do
        if e.hl then pcall(function() e.hl:Destroy() end) end
        pcall(function() e.bb:Destroy() end)
    end
    pool = {}
    pcall(function() warnGui:Destroy() end)
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
