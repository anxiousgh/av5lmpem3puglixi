-- ============================================================
--  games/138995385694035.lua  --  Hood Customs
--
--  "Main" tab first, then the universal base. Subpages:
--    Combat   : Target, Force Hit, Auto Reload, Auto Stomp, Auto Stomp Targets
--    Ragebot  : Auto Shoot, Auto Equip, Voidshoot
--    Knife Bot: knife aura (attach/orbit) + auto-equip knife
--    Misc     : Anti-AFK badge, Force-AFK badge
--    Util     : Target Line, Target Outline
--
--  HC Shoot payload (verified via witherhook):
--    MainEvent:FireServer("Shoot", { hits, targets, origin, aim, stamp })
--    hits[i]    = { Normal = pos, Instance = part, Position = pos }
--    targets[i] = { thePart = part, theOffset = Vector3.zero }
--  Force Hit hooks every outgoing Shoot and zeroes theOffset (null spread).
--  Auto Shoot builds that no-spread payload itself and fires at the target.
-- ============================================================
local ctx = ({ ... })[1]

local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS               = game:GetService("UserInputService")
local VIM               = game:GetService("VirtualInputManager")
local Workspace         = workspace
local LocalPlayer       = Players.LocalPlayer

local function gv() return (getgenv and getgenv()) or nil end

-- "Main" must come before the universal pages so it's the first tab.
local MainPage = Window:Page({ Name = "Main" })

local unloaded = false
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local function getMainEvent() return ReplicatedStorage:FindFirstChild("MainEvent") end

-- ============================================================
--  HC state (BodyEffects under workspace.Players.Characters.<name>)
-- ============================================================
local function hcModel(plr)
    local wsp = Workspace:FindFirstChild("Players")
    local chars = wsp and wsp:FindFirstChild("Characters")
    return (chars and chars:FindFirstChild(plr.Name)) or plr.Character
end
local function isKnocked(plr)
    local m = hcModel(plr)
    local fx = m and m:FindFirstChild("BodyEffects")
    local ko = fx and fx:FindFirstChild("K.O")
    return ko ~= nil and ko.Value == true
end
local function isDead(plr)
    local m = hcModel(plr)
    local fx = m and m:FindFirstChild("BodyEffects")
    local d = fx and fx:FindFirstChild("Dead")
    return d ~= nil and d.Value == true
end
local function isAlive(plr)
    local ch = plr and plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local HC = {
    -- target
    autoSwitch = true, priority = "Closest",
    -- force hit (always-on no-spread hook) + shooting
    forceHit = false, hitPart = "Head",
    autoShoot = false, autoShootDist = 250, autoShootCooldown = 0.15, autoShootVis = true,
    autoEquip = false, autoEquipTool = "",
    voidshoot = false,
    -- stomp / reload
    stomp = false, stompTargets = false, stompRadius = 5,
    reload = false, reloadKey = Enum.KeyCode.R, reloadThreshold = 0,
    -- knife bot
    knifeAura = false, knifeDist = 3, knifeInterval = 0.6, knifeOrbit = false, knifeOrbitSpeed = 180,
    knifeEquip = false,
    -- afk
    antiAfk = false, forceAfk = false,
    -- visuals
    targetLine = false, lineOrigin = "Bottom", lineColor = Color3.fromRGB(255, 60, 60),
    targetOutline = false, outlineColor = Color3.fromRGB(255, 80, 80),
}

-- ============================================================
--  Target system  (single ragebot target, auto-acquire / lock)
-- ============================================================
local RageTarget = nil

local function targetParts(char)
    return char:FindFirstChild(HC.hitPart) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end
local function validTarget(plr)
    if not plr or plr == LocalPlayer or not plr.Parent then return false end
    if not isAlive(plr) then return false end
    if isDead(plr) then return false end
    return plr.Character ~= nil and plr.Character:FindFirstChild("HumanoidRootPart") ~= nil
end

local function scorePlayer(plr)
    local cam = Workspace.CurrentCamera
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return math.huge end
    local mode = HC.priority
    if mode == "Mouse" then
        local sp, on = cam:WorldToViewportPoint(hrp.Position)
        if not on then return math.huge end
        return (UIS:GetMouseLocation() - Vector2.new(sp.X, sp.Y)).Magnitude
    elseif mode == "LowestHP" then
        local hum = char:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health or math.huge
    end
    -- Closest (to us)
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    return lhrp and (lhrp.Position - hrp.Position).Magnitude or math.huge
end

local function acquireTarget()
    local best, bestScore = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if validTarget(plr) then
            local s = scorePlayer(plr)
            if s < bestScore then bestScore = s; best = plr end
        end
    end
    return best
end

-- current target: keep RageTarget while valid; auto-switch when it drops
local function getTarget()
    if validTarget(RageTarget) then return RageTarget end
    if HC.autoSwitch then RageTarget = acquireTarget(); return RageTarget end
    RageTarget = nil
    return nil
end

-- publish to the shared Target Indicator widget
local function publishTarget(plr)
    local g = gv()
    if g and g.WH then g.WH.currentTarget = plr; g.WH.currentTargetT = os.clock() end
end

-- ============================================================
--  Synthetic Shoot payload (no spread by construction)
-- ============================================================
local function isShotgun()
    local t = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not t then return false end
    local n = t.Name:lower()
    return n:find("shotgun", 1, true) ~= nil or n:find("barrel", 1, true) ~= nil
end
local function fireShootAt(part)
    if not part then return false end
    local me = getMainEvent(); if not me then return false end
    local c = LocalPlayer.Character
    local root = c and c:FindFirstChild("HumanoidRootPart"); if not root then return false end
    local pellets = isShotgun() and 5 or 1
    local hitPos = part.Position
    local hits, targets = table.create(pellets), table.create(pellets)
    for i = 1, pellets do
        hits[i]    = { Normal = hitPos, Instance = part, Position = hitPos }
        targets[i] = { thePart = part, theOffset = Vector3.zero }
    end
    -- origin = where the server thinks we are (spoofed during voidshoot)
    local g = gv()
    local sent = g and g._WH_HC_SENT
    local origin = (sent and sent.Position) or root.Position
    local payload = { hits, targets, origin, origin, Workspace:GetServerTimeNow() }
    return pcall(function() me:FireServer("Shoot", payload) end)
end

-- ============================================================
--  FORCE HIT  -- always-on outgoing-Shoot hook that NULLS the spread.
--  Installed once (survives reloads); gated on getgenv()._WH_HC_forceHit.
--  Works for manual shots too -- it just zeroes theOffset / centres every
--  pellet on its target part so there's no scatter.
-- ============================================================
--  Real Shoot payload: { serverHitData, serverOffsets, bulletOrigin,
--  probeHitPos, serverTime }. Single guns have no spread (one pellet); only
--  shotguns scatter, so we converge every pellet onto whichever pellet hit a
--  player part (HC accepts N identical pellets). The hook is kept dirt-cheap --
--  the previous version did a FindFirstChild on EVERY game namecall (HC fires
--  a remote every frame) which froze/crashed the client.
do
    local g = gv()
    if g and not g._WH_HC_FHOOK and hookmetamethod and getnamecallmethod then
        g._WH_HC_FHOOK = true
        g._WH_HC_forceHit = false
        local MainEvent = ReplicatedStorage:FindFirstChild("MainEvent")
        local charsFolder
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            -- fast path: only do anything when force-hit is on AND this is the
            -- exact cached MainEvent. No work for the millions of other namecalls.
            if g._WH_HC_forceHit then
                if not (MainEvent and MainEvent.Parent) then
                    MainEvent = ReplicatedStorage:FindFirstChild("MainEvent")
                end
                if self == MainEvent and getnamecallmethod() == "FireServer" then
                    local a1, payload = ...
                    if a1 == "Shoot" and type(payload) == "table"
                        and type(payload[1]) == "table" and type(payload[2]) == "table"
                        and #payload[1] > 1 then
                        pcall(function()
                            if not (charsFolder and charsFolder.Parent) then
                                local p = Workspace:FindFirstChild("Players")
                                charsFolder = p and p:FindFirstChild("Characters")
                            end
                            local hitData, offsets = payload[1], payload[2]
                            local bi
                            for i = 1, #hitData do
                                local inst = hitData[i] and hitData[i].Instance
                                if inst and charsFolder and inst:IsDescendantOf(charsFolder) then bi = i; break end
                            end
                            if bi then
                                local h, o = hitData[bi], offsets[bi]
                                for i = 1, #hitData do
                                    hitData[i] = { Instance = h.Instance, Position = h.Position, Normal = h.Normal }
                                    offsets[i] = { thePart = o.thePart, theOffset = o.theOffset }
                                end
                            end
                        end)
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
    end
end
local function setForceHit(on)
    HC.forceHit = on
    local g = gv(); if g then g._WH_HC_forceHit = on end
end

-- ============================================================
--  AUTO SHOOT  -- fire the no-spread payload at the target whenever it's
--  hittable. Independent of Force Hit (which only de-spreads).
-- ============================================================
local _asLast = 0
local function tryEquipNamed(name)
    if name == "" then return end
    local lc = LocalPlayer.Character
    local hum = lc and lc:FindFirstChildOfClass("Humanoid")
    local held = lc and lc:FindFirstChildOfClass("Tool")
    if held and held.Name == name then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local tool = bp and bp:FindFirstChild(name)
    if tool and hum then pcall(function() hum:EquipTool(tool) end) end
end

-- ============================================================
--  VOIDSHOOT  -- desync our replicated root onto the target so shots
--  validate point-blank, then auto-fire. Restores our real pose each
--  RenderStep so we don't actually move locally.
-- ============================================================
local _vsSaved = nil
local function voidGlue(targetHrp)
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp or not targetHrp then return end
    _vsSaved = lhrp.CFrame
    local onTop = CFrame.new(targetHrp.Position)
    pcall(function() lhrp.CFrame = onTop end)
    local g = gv(); if g then g._WH_HC_SENT = onTop end
end
local function voidUnglue()
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if lhrp and _vsSaved then pcall(function() lhrp.CFrame = _vsSaved end) end
    local g = gv(); if g then g._WH_HC_SENT = nil end
    _vsSaved = nil
end
-- restore our real pose every frame so voidshoot stays put locally
RunService:BindToRenderStep("WH_HC_VS_RESTORE", Enum.RenderPriority.First.Value, function()
    if HC.voidshoot and _vsSaved then
        local lc = LocalPlayer.Character
        local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
        if lhrp then pcall(function() lhrp.CFrame = _vsSaved end) end
    end
end)

-- main shoot loop (auto shoot + voidshoot)
track(RunService.Heartbeat:Connect(function()
    if not (HC.autoShoot or HC.voidshoot) then return end
    if tick() - _asLast < HC.autoShootCooldown then return end
    local plr = getTarget()
    if not plr then voidUnglue(); return end
    publishTarget(plr)
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return end
    if (lhrp.Position - hrp.Position).Magnitude > HC.autoShootDist then return end
    if HC.autoShootVis and char:FindFirstChildOfClass("ForceField") then return end
    if HC.autoEquip and HC.autoEquipTool ~= "" then tryEquipNamed(HC.autoEquipTool) end
    local part = targetParts(char); if not part then return end
    _asLast = tick()
    if HC.voidshoot then
        voidGlue(hrp)
        fireShootAt(part)
        task.delay(0.05, function() if HC.voidshoot then voidUnglue() end end)
    else
        fireShootAt(part)
    end
end))

-- ============================================================
--  AUTO STOMP  (+ targets mode = only stomp the ragebot target list)
-- ============================================================
local function someoneBelow(onlyTarget)
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and (not onlyTarget or p == RageTarget) then
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and isKnocked(p) and not isDead(p) then
                local d = lhrp.Position - hrp.Position
                if Vector2.new(d.X, d.Z).Magnitude <= HC.stompRadius and d.Y <= 7 and d.Y >= -1 then
                    return true
                end
            end
        end
    end
    return false
end
local _stompLast = 0
track(RunService.Heartbeat:Connect(function()
    if not (HC.stomp or HC.stompTargets) then return end
    if tick() - _stompLast < 0.1 then return end
    local me = getMainEvent(); if not me then return end
    if not someoneBelow(HC.stompTargets and not HC.stomp) then return end
    _stompLast = tick()
    pcall(function() me:FireServer("Stomp") end)
end))

-- ============================================================
--  AUTO RELOAD
-- ============================================================
local function getAmmo()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local script = tool and tool:FindFirstChild("Script")
    local ammo = script and script:FindFirstChild("Ammo")
    if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then return ammo end
    return nil
end
local _reloadLast = 0
track(RunService.Heartbeat:Connect(function()
    if not HC.reload then return end
    if tick() - _reloadLast < 1.5 then return end
    local ammo = getAmmo(); if not ammo then return end
    if ammo.Value > HC.reloadThreshold then return end
    _reloadLast = tick()
    pcall(function()
        VIM:SendKeyEvent(true, HC.reloadKey, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, HC.reloadKey, false, game)
    end)
end))

-- ============================================================
--  KNIFE BOT  -- attach/orbit the target + auto-click; auto-equip knife
-- ============================================================
local KNIFE_NAME = "[Knife]"
local _knifeOrbitAngle = 0
local function knifeTargetHrp()
    local plr = getTarget()
    local char = plr and plr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
track(RunService.Heartbeat:Connect(function(dt)
    if not HC.knifeAura then return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    local tHrp = knifeTargetHrp()
    if not lhrp or not tHrp then return end
    local tPos = tHrp.Position
    if tPos ~= tPos or tPos.Magnitude > 1e6 then return end
    local pos
    if HC.knifeOrbit then
        _knifeOrbitAngle = (_knifeOrbitAngle + HC.knifeOrbitSpeed * dt) % 360
        local rad = math.rad(_knifeOrbitAngle)
        pos = tPos + Vector3.new(math.cos(rad), 0, math.sin(rad)) * HC.knifeDist
    else
        pos = tPos - tHrp.CFrame.LookVector * HC.knifeDist
    end
    local move = pos - lhrp.Position
    if move.Magnitude > 60 then pos = lhrp.Position + move.Unit * 60 end
    if pos == pos and (pos - tPos).Magnitude >= 0.5 then
        pcall(function() lhrp.CFrame = CFrame.new(pos, tPos) end)
    end
end))
-- knife swing clicker
task.spawn(function()
    while not unloaded do
        if HC.knifeAura and knifeTargetHrp() then
            pcall(function()
                VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end)
            task.wait(HC.knifeInterval)
        else
            task.wait(0.1)
        end
    end
end)
local function tryEquipKnife()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or char:FindFirstChild(KNIFE_NAME) then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local tool = bp and bp:FindFirstChild(KNIFE_NAME)
    if tool then pcall(function() hum:EquipTool(tool) end) end
end
task.spawn(function()
    while not unloaded do
        if HC.knifeEquip then tryEquipKnife() end
        task.wait(0.25)
    end
end)

-- ============================================================
--  AFK BADGES  (MainEvent RequestAFKDisplay + watch HRP.CharacterAFK)
-- ============================================================
local function setAfkDisplay(state)
    local me = getMainEvent()
    if me then pcall(function() me:FireServer("RequestAFKDisplay", state) end) end
end
track(RunService.Heartbeat:Connect(function()
    if not (HC.antiAfk or HC.forceAfk) then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local gui = hrp and hrp:FindFirstChild("CharacterAFK")
    local shown = gui and gui.Enabled
    if HC.forceAfk and not shown then setAfkDisplay(true)
    elseif HC.antiAfk and shown then setAfkDisplay(false) end
end))

-- ============================================================
--  TARGET VISUALS  (Drawing.Line + Highlight on the ragebot target)
-- ============================================================
local hasDrawing = (Drawing ~= nil and Drawing.new ~= nil)
local rbLine, rbHL
if hasDrawing then
    rbLine = Drawing.new("Line")
    rbLine.Visible, rbLine.Thickness, rbLine.Transparency = false, 2, 1
end
local function ensureHL()
    if rbHL and rbHL.Parent then return rbHL end
    rbHL = Instance.new("Highlight")
    rbHL.FillTransparency = 1
    rbHL.OutlineTransparency = 0
    rbHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    rbHL.Enabled = false
    pcall(function() rbHL.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not rbHL.Parent then rbHL.Parent = Workspace end
    return rbHL
end
track(RunService.RenderStepped:Connect(function()
    local plr = (HC.targetLine or HC.targetOutline) and getTarget() or nil
    local char = plr and plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    -- line
    if rbLine then
        if HC.targetLine and hrp then
            local cam = Workspace.CurrentCamera
            local sp = cam:WorldToViewportPoint(hrp.Position)
            local vs = cam.ViewportSize
            local from
            local o = HC.lineOrigin
            if o == "Top" then from = Vector2.new(vs.X * 0.5, 0)
            elseif o == "Center" then from = Vector2.new(vs.X * 0.5, vs.Y * 0.5)
            elseif o == "Mouse" then from = UIS:GetMouseLocation()
            else from = Vector2.new(vs.X * 0.5, vs.Y) end
            rbLine.From = from
            rbLine.To = Vector2.new(sp.X, sp.Y)
            rbLine.Color = HC.lineColor
            rbLine.Visible = sp.Z > 0
        else
            rbLine.Visible = false
        end
    end
    -- outline
    if HC.targetOutline and char then
        local hl = ensureHL()
        if hl.Adornee ~= char then hl.Adornee = char end
        hl.OutlineColor = HC.outlineColor
        hl.Enabled = true
    elseif rbHL then
        rbHL.Enabled = false
    end
end))

-- ============================================================
--  UI  (Main tab -- 5 subpages)
-- ============================================================

-- 1) Combat
local CombatSub = MainPage:SubPage({ Name = "Combat" })
do
    local Sec = CombatSub:Section({ Name = "Target", Side = 1 })
    Sec:Label({ Name = "Lock target" }):Keybind({ Name = "Lock target", Flag = "HC_LockKey", Mode = "Hold", Default = Enum.KeyCode.T,
        Callback = function(state) if state then RageTarget = acquireTarget() end end })
    Sec:Button({ Name = "Unlock target", Callback = function() RageTarget = nil end })
    Sec:Toggle({ Name = "Auto switch", Flag = "HC_AutoSwitch", Default = true,
        Callback = function(v) HC.autoSwitch = v end })
    Sec:Dropdown({ Name = "Priority", Flag = "HC_Priority", Default = "Closest", Multi = false,
        Items = { "Closest", "Mouse", "LowestHP" },
        Callback = function(v) HC.priority = (type(v) == "table" and v[1]) or v or "Closest" end })

    local Sec2 = CombatSub:Section({ Name = "Force Hit", Side = 1 })
    Sec2:Toggle({ Name = "Force Hit (null spread)", Flag = "HC_ForceHit", Default = false,
        Callback = function(v) setForceHit(v) end })
    Sec2:Dropdown({ Name = "Hit part", Flag = "HC_HitPart", Default = "Head", Multi = false,
        Items = { "Head", "UpperTorso", "HumanoidRootPart" },
        Callback = function(v) HC.hitPart = (type(v) == "table" and v[1]) or v or "Head" end })

    local Sec3 = CombatSub:Section({ Name = "Auto Reload", Side = 2 })
    Sec3:Toggle({ Name = "Auto reload (low ammo)", Flag = "HC_Reload", Default = false,
        Callback = function(v) HC.reload = v end })
    Sec3:Slider({ Name = "Reload at ammo <=", Flag = "HC_ReloadThreshold", Min = 0, Max = 30, Default = 0, Decimals = 0,
        Callback = function(v) HC.reloadThreshold = v end })

    local Sec4 = CombatSub:Section({ Name = "Auto Stomp", Side = 2 })
    Sec4:Toggle({ Name = "Auto stomp", Flag = "HC_Stomp", Default = false,
        Callback = function(v) HC.stomp = v end })
    Sec4:Toggle({ Name = "Auto stomp targets only", Flag = "HC_StompTargets", Default = false,
        Callback = function(v) HC.stompTargets = v end })
    Sec4:Slider({ Name = "Stomp radius", Flag = "HC_StompRadius", Min = 1, Max = 30, Default = 5, Decimals = 0,
        Callback = function(v) HC.stompRadius = v end })
end

-- 2) Ragebot
local RageSub = MainPage:SubPage({ Name = "Ragebot" })
do
    local Sec = RageSub:Section({ Name = "Auto Shoot", Side = 1 })
    Sec:Toggle({ Name = "Auto shoot", Flag = "HC_AutoShoot", Default = false,
        Callback = function(v) HC.autoShoot = v end })
    Sec:Slider({ Name = "Max distance", Flag = "HC_AutoShootDist", Min = 10, Max = 1000, Default = 250, Decimals = 0,
        Callback = function(v) HC.autoShootDist = v end })
    Sec:Slider({ Name = "Cooldown", Flag = "HC_AutoShootCd", Min = 0, Max = 1000, Default = 150, Decimals = 0, Suffix = " ms",
        Callback = function(v) HC.autoShootCooldown = v / 1000 end })
    Sec:Toggle({ Name = "Skip force-fielded", Flag = "HC_AutoShootVis", Default = true,
        Callback = function(v) HC.autoShootVis = v end })

    local Sec2 = RageSub:Section({ Name = "Auto Equip", Side = 2 })
    Sec2:Toggle({ Name = "Auto equip on shoot", Flag = "HC_AutoEquip", Default = false,
        Callback = function(v) HC.autoEquip = v end })
    Sec2:Textbox({ Name = "Tool name", Flag = "HC_AutoEquipTool", Placeholder = "exact tool name",
        Callback = function(v) HC.autoEquipTool = v or "" end })

    local Sec3 = RageSub:Section({ Name = "Voidshoot", Side = 2 })
    Sec3:Toggle({ Name = "Voidshoot (desync to target)", Flag = "HC_Voidshoot", Default = false,
        Callback = function(v) HC.voidshoot = v; if not v then voidUnglue() end end })
end

-- 3) Knife Bot
local KnifeSub = MainPage:SubPage({ Name = "Knife Bot" })
do
    local Sec = KnifeSub:Section({ Name = "Knife aura", Side = 1 })
    Sec:Toggle({ Name = "Knife aura (attach + swing)", Flag = "HC_KnifeAura", Default = false,
        Callback = function(v) HC.knifeAura = v end })
    Sec:Slider({ Name = "Distance", Flag = "HC_KnifeDist", Min = 0, Max = 50, Default = 3, Decimals = 0,
        Callback = function(v) HC.knifeDist = v end })
    Sec:Slider({ Name = "Swing interval", Flag = "HC_KnifeInterval", Min = 5, Max = 200, Default = 60, Decimals = 0, Suffix = "0ms",
        Callback = function(v) HC.knifeInterval = v / 100 end })
    Sec:Toggle({ Name = "Orbit target", Flag = "HC_KnifeOrbit", Default = false,
        Callback = function(v) HC.knifeOrbit = v end })
    Sec:Slider({ Name = "Orbit speed", Flag = "HC_KnifeOrbitSpeed", Min = 0, Max = 720, Default = 180, Decimals = 0,
        Callback = function(v) HC.knifeOrbitSpeed = v end })

    local Sec2 = KnifeSub:Section({ Name = "Knife", Side = 2 })
    Sec2:Toggle({ Name = "Auto equip knife", Flag = "HC_KnifeEquip", Default = false,
        Callback = function(v) HC.knifeEquip = v end })
end

-- 4) Misc
local MiscSub = MainPage:SubPage({ Name = "Misc" })
do
    local Sec = MiscSub:Section({ Name = "AFK badge", Side = 1 })
    Sec:Toggle({ Name = "Anti-AFK badge", Flag = "HC_AntiAfk", Default = false,
        Callback = function(v) HC.antiAfk = v; if v then HC.forceAfk = false end end })
    Sec:Toggle({ Name = "Force-AFK badge", Flag = "HC_ForceAfk", Default = false,
        Callback = function(v) HC.forceAfk = v; if v then HC.antiAfk = false end end })
end

-- 5) Util
local UtilSub = MainPage:SubPage({ Name = "Util" })
do
    local Sec = UtilSub:Section({ Name = "Target Line", Side = 1 })
    if not hasDrawing then Sec:Label({ Name = "Needs a Drawing-capable executor." }) end
    Sec:Toggle({ Name = "Target line", Flag = "HC_TargetLine", Default = false,
        Callback = function(v) HC.targetLine = v end })
    Sec:Dropdown({ Name = "Line origin", Flag = "HC_LineOrigin", Default = "Bottom", Multi = false,
        Items = { "Bottom", "Top", "Center", "Mouse" },
        Callback = function(v) HC.lineOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    Sec:Label({ Name = "Line color" }):Colorpicker({ Flag = "HC_LineColor", Default = Color3.fromRGB(255, 60, 60),
        Callback = function(c) HC.lineColor = c end })

    local Sec2 = UtilSub:Section({ Name = "Target Outline", Side = 2 })
    Sec2:Toggle({ Name = "Target outline", Flag = "HC_TargetOutline", Default = false,
        Callback = function(v) HC.targetOutline = v end })
    Sec2:Label({ Name = "Outline color" }):Colorpicker({ Flag = "HC_OutlineColor", Default = Color3.fromRGB(255, 80, 80),
        Callback = function(c) HC.outlineColor = c end })
end

-- ============================================================
--  Universal base AFTER Main, so Main stays the first tab.
-- ============================================================
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function hcCleanup()
    unloaded = true
    setForceHit(false)
    HC.autoShoot, HC.voidshoot, HC.stomp, HC.stompTargets, HC.reload = false, false, false, false, false
    HC.knifeAura, HC.knifeEquip, HC.antiAfk, HC.forceAfk = false, false, false, false
    HC.targetLine, HC.targetOutline = false, false
    voidUnglue()
    pcall(function() RunService:UnbindFromRenderStep("WH_HC_VS_RESTORE") end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if rbLine then pcall(function() rbLine:Remove() end) end
    if rbHL then pcall(function() rbHL:Destroy() end) end
end
do
    local g = gv()
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full()
            pcall(hcCleanup)
            if prev then pcall(prev) end
        end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
