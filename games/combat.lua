-- ============================================================
--  games/combat.lua  --  the Combat hub (per-game opt-in)
--
--  Split out of universal.lua so non-combat games (Cook & Sell, etc.) don't
--  load it. A game module opts in with:  ctx.load("games/combat.lua")(ctx)
--
--  Builds a "Combat" page on the shared Window with subpages:
--    Target | Aimbot (camlock) | Triggerbot | Orbit
--  The locked target is shared by all of them and published to
--  getgenv().WH.lockTarget so universal's Fling > Velocity can read it.
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = workspace
local LocalPlayer      = Players.LocalPlayer

local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- shared "server position" beacon. ANY desync feature -- here OR a future game module --
-- calls getgenv().WH.markServerCF(cf) each frame it spoofs the root (Desync page, Fling
-- orbit, HC stomp/knife, etc.), and the Server Pos visualizer renders the freshest mark.
-- Works regardless of which mechanism the desync uses (CFrame, velocity, PhysicsRepRootPart)
-- and regardless of connection/load order.
local function markServerCF(cf)
    local g = getgenv and getgenv(); if not g then return end
    g.WH = g.WH or {}
    g.WH._serverCF, g.WH._serverCFt = cf, os.clock()
end
do local g = getgenv and getgenv(); if g then g.WH = g.WH or {}; g.WH.markServerCF = markServerCF end end
local function serverCFnow(realCF)   -- freshest marked server CF (within 0.2s), else your real CF
    local g = getgenv and getgenv()
    if g and g.WH and g.WH._serverCF and (os.clock() - (g.WH._serverCFt or 0)) < 0.2 then
        return g.WH._serverCF
    end
    return realCF
end

-- shared combat helpers
local function aliveChar(plr)
    local c = plr.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if h and h.Health > 0 then return c, h end
    return nil
end
local function teamOk(plr, teamCheck)
    if not teamCheck then return true end
    return plr.Team == nil or plr.Team ~= LocalPlayer.Team
end
-- line-of-sight: nothing solid between the camera and `part`.
local function visibleTo(part)
    if not part then return false end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    local lc = getChar(); if lc then ignore[#ignore + 1] = lc end
    if part.Parent then ignore[#ignore + 1] = part.Parent end
    params.FilterDescendantsInstances = ignore
    local res = Workspace:Raycast(origin, part.Position - origin, params)
    return res == nil
end
-- guarded Drawing factory (nil if the executor has no Drawing API)
local hasDrawing = (Drawing ~= nil and Drawing.new ~= nil)
local function mkDraw(class, props)
    if not hasDrawing then return nil end
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    for k, v in pairs(props) do pcall(function() d[k] = v end) end
    return d
end

-- Every persistent feature connection is tracked here so the whole module can
-- be torn down on unload / re-execution (see disableAll at the bottom).
local Connections = {}
local function track(c) Connections[#Connections + 1] = c; return c end

--  CAMLOCK  (camera lock to the nearest target inside the FOV)
-- ============================================================
-- ============================================================
--  SHARED LOCKED TARGET  (Combat > Target subpage)
--  One locked Player that camlock, triggerbot and the Fling orbit all use. Lock =
--  the player nearest the mouse; pressing the lock key again clears it. Optional
--  tracer line + outline follow whoever's locked.
-- ============================================================
local Combat = {
    target = nil,
    line = false, lineOrigin = "Bottom", outline = false,
    lineColor = Color3.fromRGB(255, 60, 60), outlineColor = Color3.fromRGB(255, 80, 80),
}
local function combatValid()
    local plr = Combat.target
    if plr and (plr == LocalPlayer or not plr.Parent) then Combat.target = nil end
    return Combat.target
end
local function combatChar()
    local plr = combatValid()
    return plr and plr.Character
end
local function combatPart()   -- nil while dead (keep them locked through respawn)
    local ch = combatChar(); if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart")
end
local function combatLockClosest()
    local cam = Workspace.CurrentCamera
    local mouse = UserInputService:GetMouseLocation()
    local best, bestD
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local c = aliveChar(plr)
            local part = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
            if part then
                local sp, on = cam:WorldToViewportPoint(part.Position)
                if on then
                    local d = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
                    if not bestD or d < bestD then bestD, best = d, plr end
                end
            end
        end
    end
    Combat.target = best
end
local function combatToggleLock()
    if Combat.target then Combat.target = nil else combatLockClosest() end
end
-- target visuals: tracer (GUI frame -- Drawing.Line flickers on this executor) + outline
do
    local gui, line, hl
    local function ensureGui()
        if gui and gui.Parent then return end
        gui = Instance.new("ScreenGui")
        gui.Name = "_wh_target"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true   -- match WorldToViewportPoint (false drops the line below the target)
        pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
        if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
        line = Instance.new("Frame")
        line.BorderSizePixel = 0; line.AnchorPoint = Vector2.new(0.5, 0.5); line.Visible = false; line.Parent = gui
    end
    track(RunService.RenderStepped:Connect(function()
        local ch = combatChar()
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local part = (hum and hum.Health > 0) and ch:FindFirstChild("HumanoidRootPart") or nil   -- line points at the HRP, not the head
        if Combat.line and part then
            ensureGui()
            local cam = Workspace.CurrentCamera
            local sp = cam:WorldToViewportPoint(part.Position)
            if sp.Z > 0 then
                local vs = cam.ViewportSize
                local o, a = Combat.lineOrigin
                if o == "Top" then a = Vector2.new(vs.X * 0.5, 0)
                elseif o == "Center" then a = Vector2.new(vs.X * 0.5, vs.Y * 0.5)
                elseif o == "Mouse" then a = UserInputService:GetMouseLocation()   -- raw, matches the IgnoreGuiInset=true gui
                else a = Vector2.new(vs.X * 0.5, vs.Y) end   -- Bottom (default)
                local b = Vector2.new(sp.X, sp.Y)
                local mid, d = (a + b) / 2, (b - a)
                line.Size = UDim2.fromOffset(2, d.Magnitude)
                line.Position = UDim2.fromOffset(mid.X, mid.Y)
                line.Rotation = math.deg(math.atan2(d.Y, d.X)) - 90
                line.BackgroundColor3 = Combat.lineColor
                line.Visible = true
            elseif line then line.Visible = false end
        elseif line then line.Visible = false end

        local ch = combatChar()
        if Combat.outline and ch then
            if not (hl and hl.Parent) then
                hl = Instance.new("Highlight")
                hl.FillTransparency = 1; hl.OutlineTransparency = 0
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                pcall(function() hl.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
                if not hl.Parent then hl.Parent = Workspace end
            end
            if hl.Adornee ~= ch then hl.Adornee = ch end
            hl.OutlineColor = Combat.outlineColor
            hl.Enabled = true
        elseif hl then hl.Enabled = false end
    end))
end

local CamLock = {
    enabled = false, fov = 120, smoothing = 0.5, sticky = false,
    teamCheck = true, hitPart = "Head", visibleCheck = false, showFov = false,
}
do
    local fovCircle = mkDraw("Circle", {
        Thickness = 1, NumSides = 64, Filled = false, Visible = false,
        Transparency = 1, Color = Color3.fromRGB(200, 183, 247),
    })
    local stickyTarget = nil   -- Player held while sticky is on

    local function resolvePart(plr)
        local char = aliveChar(plr); if not char then return nil end
        return char:FindFirstChild(CamLock.hitPart) or char:FindFirstChild("HumanoidRootPart")
    end

    -- A held sticky target stays valid while alive + team-ok + (visible if
    -- checked). Returns its part when still valid, otherwise nil.
    local function stickyPart(plr)
        if not plr or plr == LocalPlayer or not plr.Parent then return nil end
        if not teamOk(plr, CamLock.teamCheck) then return nil end
        local part = resolvePart(plr); if not part then return nil end
        if CamLock.visibleCheck and not visibleTo(part) then return nil end
        return part
    end

    -- Nearest valid target to the crosshair within the FOV radius.
    local function findClosest()
        local cam = Workspace.CurrentCamera
        local mouse = UserInputService:GetMouseLocation()
        local bestPlr, bestPart, bestDist
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == LocalPlayer then continue end
            if not teamOk(plr, CamLock.teamCheck) then continue end
            local part = resolvePart(plr); if not part then continue end
            if CamLock.visibleCheck and not visibleTo(part) then continue end
            local sp, on = cam:WorldToViewportPoint(part.Position)
            if not on then continue end
            local d = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
            if d <= CamLock.fov and (not bestDist or d < bestDist) then
                bestPlr, bestPart, bestDist = plr, part, d
            end
        end
        return bestPlr, bestPart
    end

    track(RunService.RenderStepped:Connect(function(dt)
        if fovCircle then
            fovCircle.Visible = CamLock.showFov
            if CamLock.showFov then
                fovCircle.Radius = CamLock.fov
                fovCircle.Position = UserInputService:GetMouseLocation()
            end
        end
        if not CamLock.enabled then stickyTarget = nil; return end
        if Library.WindowOpenState then return end   -- don't fight you while in the menu

        -- camlock ONLY aims at the manually locked target (Combat > Target); nothing
        -- locked = it doesn't aim at all.
        local plr = combatValid()
        local part = plr and resolvePart(plr)
        -- publish the locked target for the Target Indicator widget (nil = none)
        if getgenv then
            local g = getgenv()
            if g.WH then g.WH.currentTarget = part and plr or nil; g.WH.currentTargetT = os.clock() end
        end
        if not part then return end

        local cam = Workspace.CurrentCamera
        local alpha = math.clamp(1 - (CamLock.smoothing ^ (dt * 60)), 0, 1)
        cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, part.Position), alpha)
    end))
end

-- ============================================================
--  TRIGGERBOT  (fire when the crosshair is on an enemy)
-- ============================================================
local Trig = { enabled = false, delay = 0, teamCheck = false }
do
    local VIM; pcall(function() VIM = VirtualInputManager end)
    local lastShot = 0
    local function fire()
        if not VIM then return end
        task.spawn(function()   -- press / release on separate frames so semi-auto guns re-fire
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
            task.wait()
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
        end)
    end

    -- Is the crosshair actually on the locked target's body? A plain raycast gets
    -- eaten by the viewmodel / arms / gun rendered in front of the camera (and by FX
    -- bubbles) -- those aren't part of YOUR character so the default filter misses
    -- them, the ray "hits a Part", and never reaches the enemy. So we penetrate:
    -- skip anything right next to the camera, non-collidable, or see-through
    -- (viewmodels / effects), stop at a real solid blocker (wall / other player),
    -- and report a hit only if we genuinely reach the target. Accessories on the
    -- target (masks/hats) are pre-filtered so the ray passes through to the body.
    local function aimingAt(char)
        local cam = Workspace.CurrentCamera
        local mouse = UserInputService:GetMouseLocation()
        local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
        local ignore = {}
        local lc = getChar(); if lc then ignore[#ignore + 1] = lc end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Accessory") then ignore[#ignore + 1] = d end
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore
        local origin, dir = ray.Origin, ray.Direction * 5000
        for _ = 1, 12 do
            local res = Workspace:Raycast(origin, dir, params)
            if not res or not res.Instance then return false end
            local inst = res.Instance
            if inst:IsDescendantOf(char) then return true end            -- reached the enemy
            if inst.CanCollide == false or inst.Transparency >= 0.5
                or (res.Position - origin).Magnitude < 6 then            -- viewmodel / fx: pass through
                ignore[#ignore + 1] = inst
                params.FilterDescendantsInstances = ignore
            else
                return false                                             -- solid wall / other player blocks
            end
        end
        return false
    end

    track(RunService.Heartbeat:Connect(function()
        if not Trig.enabled then return end
        if Library.WindowOpenState then return end   -- don't fire while clicking the menu
        local plr = combatValid()                    -- locked target only (Combat > Target)
        if not plr or plr == LocalPlayer then return end
        local char = plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum and hum.Health > 0) then return end
        if Trig.teamCheck and plr.Team and plr.Team == LocalPlayer.Team then return end
        if not aimingAt(char) then return end
        if (tick() - lastShot) * 1000 < Trig.delay then return end
        lastShot = tick()
        fire()
    end))
end

-- publish the locked target for universal's Fling > Velocity (through-target) and
-- any other module; nil while nothing is locked.
track(RunService.RenderStepped:Connect(function()
    local g = getgenv and getgenv()
    if g and g.WH then g.WH.lockTarget = combatValid() end
end))

-- ============================================================
--  COMBAT  (Aimbot = camlock, Triggerbot)
-- ============================================================
local CombatPage = Window:Page({ Name = "Combat" })

local TargetSub = CombatPage:SubPage({ Name = "Target" })
do
    local Sec = TargetSub:Section({ Name = "Lock", Side = 1 })
    Sec:Label({ Name = "Lock Target" }):Keybind({
        Name = "Lock target", Flag = "TargetLockKey", Mode = "Hold", Default = Enum.KeyCode.T,
        Callback = function(state) if state then combatToggleLock() end end })
    Sec:Button({ Name = "Lock nearest to mouse", Callback = combatLockClosest })
    Sec:Button({ Name = "Unlock", Callback = function() Combat.target = nil end })

    local Sec2 = TargetSub:Section({ Name = "Visuals", Side = 2 })
    Sec2:Toggle({ Name = "Tracer line", Flag = "TargetLine", Default = false,
        Callback = function(v) Combat.line = v end })
    Sec2:Dropdown({ Name = "Line origin", Flag = "TargetLineOrigin", Default = "Bottom", Multi = false,
        Items = { "Bottom", "Top", "Center", "Mouse" },
        Callback = function(v) Combat.lineOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    Sec2:Label({ Name = "Line color" }):Colorpicker({ Flag = "TargetLineColor", Default = Combat.lineColor,
        Callback = function(c) Combat.lineColor = c end })
    Sec2:Toggle({ Name = "Outline", Flag = "TargetOutline", Default = false,
        Callback = function(v) Combat.outline = v end })
    Sec2:Label({ Name = "Outline color" }):Colorpicker({ Flag = "TargetOutlineColor", Default = Combat.outlineColor,
        Callback = function(c) Combat.outlineColor = c end })
end

local AimSub = CombatPage:SubPage({ Name = "Aimbot" })
do
    local Sec = AimSub:Section({ Name = "Camera lock", Side = 1 })
    local Enabled = Sec:Toggle({
        Name = "Enabled", Flag = "CamLockEnabled", Default = false,
        Callback = function(v) CamLock.enabled = v end,
    })
    Sec:Label({ Name = "Toggle key" }):Keybind({
        Name = "Aimlock",
        Flag = "CamLockKey", Mode = "Toggle", Default = Enum.KeyCode.E,
        Callback = function(state) Enabled:Set(state and true or false) end,
    })
    Sec:Slider({
        Name = "FOV", Flag = "CamLockFov", Min = 10, Max = 600, Default = 120, Decimals = 0,
        Callback = function(v) CamLock.fov = v end,
    })
    Sec:Slider({
        Name = "Smoothing", Flag = "CamLockSmoothing", Min = 0, Max = 95, Default = 50, Decimals = 0, Suffix = "%",
        Callback = function(v) CamLock.smoothing = v / 100 end,
    })
    Sec:Dropdown({
        Name = "Hit part", Flag = "CamLockPart", Default = "Head", Multi = false,
        Items = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
        Callback = function(v) CamLock.hitPart = (type(v) == "table" and v[1]) or v or "Head" end,
    })

    local Sec2 = AimSub:Section({ Name = "Checks", Side = 2 })
    Sec2:Toggle({ Name = "Sticky target", Flag = "CamLockSticky", Default = false,
        Callback = function(v) CamLock.sticky = v end })
    Sec2:Toggle({ Name = "Team check", Flag = "CamLockTeam", Default = true,
        Callback = function(v) CamLock.teamCheck = v end })
    Sec2:Toggle({ Name = "Visible check (walls)", Flag = "CamLockVisible", Default = false,
        Callback = function(v) CamLock.visibleCheck = v end })
    Sec2:Toggle({ Name = "Show FOV", Flag = "CamLockShowFov", Default = false,
        Callback = function(v) CamLock.showFov = v end })
end

local TrigSub = CombatPage:SubPage({ Name = "Triggerbot" })
do
    local Sec = TrigSub:Section({ Name = "Triggerbot", Side = 1 })
    local Enabled = Sec:Toggle({
        Name = "Enabled", Flag = "TrigEnabled", Default = false,
        Callback = function(v) Trig.enabled = v end,
    })
    Sec:Label({ Name = "Toggle key" }):Keybind({
        Name = "Triggerbot",
        Flag = "TrigKey", Mode = "Toggle", Default = Enum.KeyCode.G,
        Callback = function(state) Enabled:Set(state and true or false) end,
    })
    Sec:Slider({
        Name = "Click delay", Flag = "TrigDelay", Min = 0, Max = 1000, Default = 0, Decimals = 0, Suffix = "ms",
        Callback = function(v) Trig.delay = v end,
    })
    Sec:Toggle({ Name = "Team check", Flag = "TrigTeam", Default = false,
        Callback = function(v) Trig.teamCheck = v end })
end

-- ============================================================
--  ORBIT  (orbit the locked target) -- moved here from Player > Fling
-- ============================================================
do
    local function selectedHRP()
        local ch = combatChar()   -- the locked target (Combat > Target subpage)
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local OrbitSub = CombatPage:SubPage({ Name = "Orbit" })

    -- ---------- Orbit ----------
    local orbit = { on = false, dist = 4, speed = 400, minH = 0, maxH = 0, heightOn = false,
        lookAt = true, fakePos = true, desync = false, pattern = "Orbit" }
    local _attached, _angle, _orbitReal = false, 0, nil
    local _hCur, _hTarget, _hTimer = 0, 0, 0   -- smooth random height (advanced in the loop by dt)
    local _randOff, _randTimer = Vector3.zero, 0                              -- Random: re-rolled spot
    local _planA, _planB, _planAt, _planBt, _planTimer = 0.5, 0.3, 0.5, 0.3, 0  -- Planetary: drifting tilt
    local _planC, _planCt = 0, 0                                             -- Planetary: drifting radius wobble
    -- offset around the target for the chosen pattern. _hCur is a smooth random height between
    -- Min/Max (independent of orbit speed), applied only when the Height toggle is on.
    -- a random point on the sphere of radius `dist` around the target (+ random height)
    local function randomOrbitOffset()
        local theta = math.random() * math.pi * 2
        local phi = (math.random() - 0.5) * math.pi
        local d = orbit.dist
        local h = orbit.heightOn and (orbit.minH + math.random() * (orbit.maxH - orbit.minH)) or 0
        return Vector3.new(math.cos(phi) * math.cos(theta) * d, math.sin(phi) * d + h, math.cos(phi) * math.sin(theta) * d)
    end
    local function orbitOffset()
        local rad = math.rad(_angle)
        local d = orbit.dist
        local bob = orbit.heightOn and _hCur or 0
        local p = orbit.pattern
        if p == "Random" then              -- teleport to re-rolled random spots around the target
            return _randOff
        elseif p == "Planetary" then       -- a ring whose tilt AND radius drift randomly, so the
                                           -- path + height wander and never repeat
            local rw = d * (1 + _planC)
            return Vector3.new(math.cos(rad) * rw, (math.cos(rad) * _planA + math.sin(rad) * _planB) * d + bob, math.sin(rad) * rw)
        elseif p == "Vertical" then        -- vertical loop straight over the top
            return Vector3.new(0, math.sin(rad) * d + bob, math.cos(rad) * d)
        elseif p == "Spiral" then          -- flat ring with a slow continuous vertical wind
            return Vector3.new(math.cos(rad) * d, math.sin(math.rad(_angle * 0.25)) * d + bob, math.sin(rad) * d)
        else                               -- "Orbit": plain flat horizontal ring
            return Vector3.new(math.cos(rad) * d, bob, math.sin(rad) * d)
        end
    end
    local function orbitDetach()
        if not _attached then return end
        local hrp = getHRP()
        if hrp and sethiddenproperty then pcall(function() sethiddenproperty(hrp, "PhysicsRepRootPart", hrp) end) end
        _attached = false
    end
    local function orbitRestoreReal()   -- put our real character back (desync mode)
        if not _orbitReal then return end
        local hrp = getHRP()
        if hrp then pcall(function() hrp.CFrame = _orbitReal end) end
        _orbitReal = nil
    end
    track(RunService.Heartbeat:Connect(function(dt)
        if not orbit.on then orbitDetach(); orbitRestoreReal(); return end
        local hrp, tHrp = getHRP(), selectedHRP()
        if not (hrp and tHrp) then orbitDetach(); orbitRestoreReal(); return end
        _angle = (_angle + orbit.speed * dt) % 360
        -- smooth random height: pick a new random target in [min,max] now and then, lerp to
        -- it by dt (so it glides between heights, never snaps, and ignores the orbit speed).
        if orbit.heightOn then
            _hTimer = _hTimer - dt
            if _hTimer <= 0 then
                _hTarget = orbit.minH + math.random() * (orbit.maxH - orbit.minH)
                _hTimer = 0.4 + math.random() * 0.8
            end
            _hCur = _hCur + (_hTarget - _hCur) * math.clamp(dt * 3, 0, 1)
        else
            _hCur = 0
        end
        -- pattern-specific randomisation, advanced by dt
        local _p = orbit.pattern
        if _p == "Random" then
            _randTimer = _randTimer - dt
            if _randTimer <= 0 then
                _randOff = randomOrbitOffset()
                local iv = math.clamp(50 / math.max(orbit.speed, 1), 0.012, 2)   -- higher Speed -> jump more often
                _randTimer = iv * (0.8 + math.random() * 0.4)
            end
        elseif _p == "Planetary" then
            _planTimer = _planTimer - dt
            if _planTimer <= 0 then                             -- drift tilt + radius toward new random targets
                _planAt, _planBt = (math.random() - 0.5) * 3, (math.random() - 0.5) * 3   -- wider tilt range
                _planCt = (math.random() - 0.5) * 0.8                                       -- radius wobble
                _planTimer = 0.4 + math.random() * 0.8                                      -- drift more often
            end
            _planA = _planA + (_planAt - _planA) * math.clamp(dt * 2, 0, 1)
            _planB = _planB + (_planBt - _planB) * math.clamp(dt * 2, 0, 1)
            _planC = _planC + (_planCt - _planC) * math.clamp(dt * 2, 0, 1)
        end
        local pos = tHrp.Position + orbitOffset()
        local cf = orbit.lookAt and CFrame.new(pos, tHrp.Position) or CFrame.new(pos)
        -- Fake Pos: re-root our physics replication onto the target. Applied in BOTH modes
        -- now (it used to be skipped while Desync was on).
        if orbit.fakePos then
            pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
            pcall(function() tHrp:SetNetworkOwner(LocalPlayer) end)
            if sethiddenproperty then pcall(function() sethiddenproperty(hrp, "PhysicsRepRootPart", tHrp) end) end
            _attached = true
        elseif _attached then
            orbitDetach()
        end
        if orbit.desync then
            -- custom-desync style: replicate the orbit pose to the server each Heartbeat but
            -- keep our REAL character where it is (restored each RenderStep) -- the server
            -- sees us orbiting (flings the target) while we don't actually move there.
            -- DON'T touch velocity here: zeroing it kills your walk speed + animations.
            _orbitReal = hrp.CFrame   -- our real home (RenderStep restored it last frame)
            pcall(function() hrp.CFrame = cf end)
            markServerCF(cf)          -- report orbit pos so the Server Pos clone follows it
        else
            orbitRestoreReal()   -- in case desync was just turned off
            pcall(function()
                hrp.CFrame = cf
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
        end
    end))
    RunService:BindToRenderStep("WH_FlingOrbitRestore", Enum.RenderPriority.First.Value, function()
        if orbit.on and orbit.desync and _orbitReal then
            local hrp = getHRP()
            if hrp then pcall(function() hrp.CFrame = _orbitReal end) end
        end
    end)

    local OSec = OrbitSub:Section({ Name = "Orbit", Side = 1 })
    local orbitToggle = OSec:Toggle({ Name = "Orbit target", Flag = "FlingOrbit", Default = false,
        Callback = function(v) orbit.on = v end })
    OSec:Label({ Name = "Toggle key" }):Keybind({ Name = "Orbit", Flag = "FlingOrbitKey", Mode = "Toggle",
        Callback = function(state) orbitToggle:Set(state and true or false) end })
    OSec:Dropdown({ Name = "Orbit directions", Flag = "FlingOrbitPattern", Default = "Orbit", Multi = false,
        Items = { "Orbit", "Planetary", "Random", "Vertical", "Spiral" },
        Callback = function(v) orbit.pattern = (type(v) == "table" and v[1]) or v or "Orbit" end })
    OSec:Slider({ Name = "Distance", Flag = "FlingOrbitDist", Min = 0.05, Max = 30, Default = 4, Decimals = 2, Suffix = " studs",
        Callback = function(v) orbit.dist = v end })
    OSec:Slider({ Name = "Speed", Flag = "FlingOrbitSpeed", Min = 0, Max = 3000, Default = 400, Decimals = 0,
        Callback = function(v) orbit.speed = v end })
    local minHSlider, maxHSlider
    OSec:Toggle({ Name = "Height (min/max)", Flag = "FlingOrbitHeightOn", Default = false,
        Callback = function(v)
            orbit.heightOn = v
            pcall(function() minHSlider:SetVisibility(v) end)
            pcall(function() maxHSlider:SetVisibility(v) end)
        end })
    minHSlider = OSec:Slider({ Name = "Min height", Flag = "FlingOrbitMinH", Min = -20, Max = 20, Default = 0, Decimals = 1, Suffix = " studs",
        Callback = function(v) orbit.minH = v end })
    maxHSlider = OSec:Slider({ Name = "Max height", Flag = "FlingOrbitMaxH", Min = -20, Max = 20, Default = 0, Decimals = 1, Suffix = " studs",
        Callback = function(v) orbit.maxH = v end })
    pcall(function() minHSlider:SetVisibility(false) end)   -- hidden until Height is on
    pcall(function() maxHSlider:SetVisibility(false) end)
    OSec:Toggle({ Name = "Lookat target", Flag = "FlingOrbitLook", Default = true,
        Callback = function(v) orbit.lookAt = v end })
    OSec:Toggle({ Name = "Fake Pos", Flag = "FlingOrbitFakePos", Default = true,
        Callback = function(v) orbit.fakePos = v end })
    OSec:Toggle({ Name = "Desync", Flag = "FlingOrbitDesync", Default = false,
        Callback = function(v) orbit.desync = v end })
end

-- ============================================================
--  teardown: drop all combat connections on unload / re-exec
-- ============================================================
do
    local function full()
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        pcall(function() RunService:UnbindFromRenderStep("WH_FlingOrbitRestore") end)
    end
    local g = getgenv and getgenv()
    if g and g.WH then
        local prev = g.WH.disableAll
        g.WH.disableAll = function() pcall(full); if prev then pcall(prev) end end
        Library.OnExit = g.WH.disableAll
    else
        Library.OnExit = full
    end
end
