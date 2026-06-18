-- ============================================================
--  games/universal.lua  --  the base "main" UI every game gets
--
--  Pages built on the Window passed in via ctx:
--    Combat   -- Aimbot (camera lock) + Triggerbot subpages (working)
--    Player   -- working movement (walkspeed/jump/cframe/fly/noclip/inf-jump)
--    Visuals  -- ESP (box / name / distance / health, working)
--
--  Settings (config + themes) is added by the loader after this runs.
--  ctx = { Library, Window, Watermark, KeybindList, fetch, load, base, placeId }
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

-- ---------- services / helpers ----------
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

-- ============================================================
--  MOVEMENT BACKEND  (enforced per-frame, survives respawn)
-- ============================================================
local Movement = {}

do  -- WalkSpeed
    local active, value, conn = false, 50, nil
    local function enforce()
        if not active then return end
        local hum = getHum()
        if hum and hum.WalkSpeed ~= value then pcall(function() hum.WalkSpeed = value end) end
    end
    function Movement.setWalkSpeedValue(v) value = v; enforce() end
    function Movement.setWalkSpeed(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then conn = RunService.Heartbeat:Connect(enforce)
        else local hum = getHum(); if hum then pcall(function() hum.WalkSpeed = 16 end) end end
    end
end

do  -- JumpPower / JumpHeight
    local active, value, conn = false, 50, nil
    local function enforce()
        if not active then return end
        local hum = getHum(); if not hum then return end
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
        pcall(function()
            if hum.UseJumpPower then
                if hum.JumpPower ~= value then hum.JumpPower = value end
            else
                local h = value / 7
                if math.abs(hum.JumpHeight - h) > 0.05 then hum.JumpHeight = h end
            end
        end)
    end
    function Movement.setJumpValue(v) value = v; enforce() end
    function Movement.setJump(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then conn = RunService.Heartbeat:Connect(enforce)
        else local hum = getHum(); if hum then pcall(function()
            if hum.UseJumpPower then hum.JumpPower = 50 else hum.JumpHeight = 7.2 end
        end) end end
    end
end

do  -- CFrame speed
    local active, mult, conn = false, 2, nil
    function Movement.setCFrameValue(v) mult = v end
    function Movement.setCFrame(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then
            conn = RunService.Heartbeat:Connect(function(dt)
                if not active or UserInputService:GetFocusedTextBox() then return end
                local hrp = getHRP(); if not hrp then return end
                local cam = Workspace.CurrentCamera
                local dir = Vector3.zero
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
                dir = Vector3.new(dir.X, 0, dir.Z)
                if dir.Magnitude > 0 then hrp.CFrame = hrp.CFrame + dir.Unit * (16 * (mult - 1)) * dt end
            end)
        end
    end
end

do  -- Fly
    local active, speed, conn = false, 60, nil
    function Movement.setFlyValue(v) speed = v end
    function Movement.setFly(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then
            conn = RunService.Heartbeat:Connect(function(dt)
                if not active then return end
                local hrp = getHRP(); if not hrp then return end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                if UserInputService:GetFocusedTextBox() then return end
                local cam = Workspace.CurrentCamera
                local dir = Vector3.zero
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.new(0, 1, 0) end
                if dir.Magnitude > 0 then hrp.CFrame = hrp.CFrame + dir.Unit * speed * dt end
            end)
        end
    end
end

do  -- Noclip
    local active = false
    local PARTS = { "HumanoidRootPart", "UpperTorso", "Torso", "Head", "LowerTorso" }
    function Movement.setNoclip(on)
        active = on
        pcall(function() RunService:UnbindFromRenderStep("WH_Noclip") end)
        if on then
            RunService:BindToRenderStep("WH_Noclip", Enum.RenderPriority.First.Value, function()
                if not active then return end
                local c = getChar(); if not c then return end
                for _, name in ipairs(PARTS) do
                    local p = c:FindFirstChild(name); if p then p.CanCollide = false end
                end
            end)
        else
            local c = getChar()
            if c then for _, name in ipairs(PARTS) do
                local p = c:FindFirstChild(name)
                if p and p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
            end end
        end
    end
end

do  -- Infinite jump
    local active, conn = false, nil
    function Movement.setInfJump(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then
            conn = UserInputService.JumpRequest:Connect(function()
                if not active then return end
                local hum = getHum()
                if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
            end)
        end
    end
end

-- ============================================================
--  CAMLOCK  (camera lock to the nearest target inside the FOV)
-- ============================================================
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

        local part
        if CamLock.sticky then
            -- keep the current target while valid; only re-acquire when it drops
            part = stickyPart(stickyTarget)
            if not part then
                stickyTarget, part = findClosest()
            end
        else
            stickyTarget = nil
            local _, p = findClosest()
            part = p
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
local Trig = { enabled = false, delay = 0, teamCheck = true }
do
    local VIM; pcall(function() VIM = VirtualInputManager end)
    local lastShot = 0
    local function fire()
        if not VIM then return end
        task.spawn(function()
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
            task.wait()
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
        end)
    end

    track(RunService.Heartbeat:Connect(function()
        if not Trig.enabled then return end
        if Library.WindowOpenState then return end   -- don't fire while clicking the menu
        local cam = Workspace.CurrentCamera
        local mouse = UserInputService:GetMouseLocation()
        local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignore = {}; local lc = getChar(); if lc then ignore[1] = lc end
        params.FilterDescendantsInstances = ignore
        local res = Workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
        if not res or not res.Instance then return end
        local model = res.Instance:FindFirstAncestorOfClass("Model")
        local plr = model and Players:GetPlayerFromCharacter(model)
        if not plr or plr == LocalPlayer then return end
        if not teamOk(plr, Trig.teamCheck) then return end
        if not aliveChar(plr) then return end
        if (tick() - lastShot) * 1000 < Trig.delay then return end
        lastShot = tick()
        fire()
    end))
end

-- ============================================================
--  ESP  (box / name / distance / health via Drawing)
-- ============================================================
local Esp = {
    enabled = false, names = false, distance = false, health = false,
    teamCheck = false, color = Color3.fromRGB(200, 183, 247),
}
do
    local objs = {}   -- plr -> { box, name, dist, health }

    local function add(plr)
        if plr == LocalPlayer or objs[plr] or not hasDrawing then return end
        objs[plr] = {
            box    = mkDraw("Square", { Thickness = 1, Filled = false, Visible = false, Transparency = 1 }),
            name   = mkDraw("Text",   { Size = 13, Center = true, Outline = true, Visible = false }),
            dist   = mkDraw("Text",   { Size = 12, Center = true, Outline = true, Visible = false }),
            health = mkDraw("Square", { Thickness = 1, Filled = true, Visible = false }),
        }
    end
    local function remove(plr)
        local o = objs[plr]; if not o then return end
        for _, d in pairs(o) do if d then pcall(function() d:Remove() end) end end
        objs[plr] = nil
    end

    for _, p in ipairs(Players:GetPlayers()) do add(p) end
    track(Players.PlayerAdded:Connect(add))
    track(Players.PlayerRemoving:Connect(remove))

    function Esp.clear()   -- remove all ESP drawings (used on unload)
        for plr in pairs(objs) do remove(plr) end
    end

    local function hideAll(o)
        if o.box then o.box.Visible = false end
        if o.name then o.name.Visible = false end
        if o.dist then o.dist.Visible = false end
        if o.health then o.health.Visible = false end
    end

    track(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        local myHRP = getHRP()
        for plr, o in pairs(objs) do
            if not o.box then continue end
            local shown = false
            if Esp.enabled and teamOk(plr, Esp.teamCheck) then
                local char, hum = aliveChar(plr)
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local center, on = cam:WorldToViewportPoint(hrp.Position)
                    if on then
                        local top = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                        local bot = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                        local height = math.max(math.abs(top.Y - bot.Y), 1)
                        local width  = height * 0.55
                        local x, y = center.X - width / 2, center.Y - height / 2
                        shown = true

                        o.box.Color = Esp.color
                        o.box.Size = Vector2.new(width, height)
                        o.box.Position = Vector2.new(x, y)
                        o.box.Visible = true

                        o.name.Visible = Esp.names
                        if Esp.names then
                            o.name.Text = plr.Name
                            o.name.Color = Esp.color
                            o.name.Position = Vector2.new(center.X, y - 14)
                        end

                        o.dist.Visible = Esp.distance
                        if Esp.distance then
                            local d = myHRP and math.floor((myHRP.Position - hrp.Position).Magnitude) or 0
                            o.dist.Text = tostring(d) .. "m"
                            o.dist.Color = Esp.color
                            o.dist.Position = Vector2.new(center.X, y + height + 2)
                        end

                        o.health.Visible = Esp.health
                        if Esp.health then
                            local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            o.health.Size = Vector2.new(2, height * hp)
                            o.health.Position = Vector2.new(x - 4, y + height * (1 - hp))
                            o.health.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(80, 255, 80), hp)
                        end
                    end
                end
            end
            if not shown then hideAll(o) end
        end
    end))
end

-- ============================================================
--  COMBAT  (Aimbot = camlock, Triggerbot)
-- ============================================================
local CombatPage = Window:Page({ Name = "Combat" })

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
    Sec:Toggle({ Name = "Team check", Flag = "TrigTeam", Default = true,
        Callback = function(v) Trig.teamCheck = v end })
end

-- ============================================================
--  DESYNC  (server sees a fake position; you stay put locally)
--   void / spin / velocity / custom -> spoof the HRP on Heartbeat (this is
--     what replicates), then restore your real CFrame each RenderStep so YOU
--     still see yourself correctly.
--   freeze -> RakNet: block the outbound physics packet (0x1B) so the server
--     stops getting position updates. Needs an executor with a `raknet` API.
-- ============================================================
local Desync = {
    enabled = false, method = "Void",
    voidMin = 5000, voidMax = 20000,
    spinSpeed = 2, velMag = 16384,
    customX = 0, customY = 0, customZ = 0,
}
do
    local RESTORE = "WH_DesyncRestore"
    local realCF, realLV, realAV
    local spinAngle = 0

    -- raknet state lives on getgenv so the hook closure survives reloads
    getgenv()._WH_DESYNC = getgenv()._WH_DESYNC or {}
    local SHARED = getgenv()._WH_DESYNC

    local function randVoid()
        local function axis()
            local mag = Desync.voidMin + math.random() * math.max(Desync.voidMax - Desync.voidMin, 0)
            return (math.random() < 0.5) and -mag or mag
        end
        return Vector3.new(axis(), axis(), axis())
    end

    local function applySpoof(hrp)
        local m = Desync.method
        if m == "Void" then
            hrp.CFrame = CFrame.new(randVoid())
        elseif m == "Spin" then
            spinAngle = (spinAngle + Desync.spinSpeed) % 360
            hrp.CFrame = hrp.CFrame * CFrame.Angles(
                math.rad(spinAngle), math.rad(spinAngle * 2), math.rad(spinAngle * 0.5))
        elseif m == "Velocity" then
            hrp.AssemblyLinearVelocity = Vector3.one * Desync.velMag
        elseif m == "Custom" then
            local rot = hrp.CFrame - hrp.CFrame.Position
            hrp.CFrame = CFrame.new(Desync.customX, Desync.customY, Desync.customZ) * rot
        end
    end

    -- ---- RakNet freeze ----
    local function findRaknet()
        local r = rawget(getgenv(), "raknet")
        if r then return r end
        local ok, v = pcall(function() return raknet end)
        if ok then return v end
        return nil
    end
    local function ensureRaknetHook()
        if SHARED.hookInstalled then return true end
        local r = findRaknet()
        if not r or not r.add_send_hook then return false end
        SHARED.hookFn = function(packet)
            if not SHARED.freeze then return end
            if packet.PacketId == 0x1B then     -- outbound physics replication
                pcall(function() packet:SetCanBeSent(false) end)
                pcall(function() packet:Drop() end)
                return false
            end
        end
        local ok = pcall(function() r.add_send_hook(SHARED.hookFn) end)
        if ok then SHARED.hookInstalled = true end
        return ok
    end

    -- ---- heartbeat spoof + renderstep restore (non-freeze methods) ----
    track(RunService.Heartbeat:Connect(function()
        if not Desync.enabled or Desync.method == "Freeze" then return end
        local hrp = getHRP(); if not hrp then return end
        realCF, realLV, realAV = hrp.CFrame, hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity
        pcall(applySpoof, hrp)
    end))

    RunService:BindToRenderStep(RESTORE, Enum.RenderPriority.First.Value, function()
        if not Desync.enabled or Desync.method == "Freeze" then return end
        local hrp = getHRP(); if not hrp or not realCF then return end
        pcall(function()
            if Desync.method ~= "Velocity" then hrp.CFrame = realCF end
            if realLV then hrp.AssemblyLinearVelocity = realLV end
            if realAV then hrp.AssemblyAngularVelocity = realAV end
        end)
    end)

    local function applyFreezeState()
        local on = Desync.enabled and Desync.method == "Freeze"
        SHARED.freeze = on
        if on and not ensureRaknetHook() then
            SHARED.freeze = false
            Desync.enabled = false
            Library:Notification("RakNet not available in this executor", 3, Library.Theme["Risky"])
        end
    end

    function Desync.setEnabled(on)
        Desync.enabled = on and true or false
        applyFreezeState()
    end
    function Desync.setMethod(m)
        Desync.method = m
        applyFreezeState()   -- re-evaluate freeze when switching methods
    end
    function Desync.stop()
        Desync.enabled = false
        SHARED.freeze = false
        pcall(function() RunService:UnbindFromRenderStep(RESTORE) end)
    end
end

-- ============================================================
--  PLAYER  (working universal movement)
-- ============================================================
local PlayerPage = Window:Page({ Name = "Player" })
local Move = PlayerPage:SubPage({ Name = "Movement" })

local SpeedSec = Move:Section({ Name = "Speed", Side = 1 })
SpeedSec:Toggle({ Name = "WalkSpeed", Flag = "WalkSpeedEnabled", Default = false,
    Callback = function(v) Movement.setWalkSpeed(v) end })
SpeedSec:Slider({ Name = "WalkSpeed amount", Flag = "WalkSpeedValue", Min = 16, Max = 500, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setWalkSpeedValue(v) end })
SpeedSec:Toggle({ Name = "CFrame speed", Flag = "CFrameEnabled", Default = false,
    Callback = function(v) Movement.setCFrame(v) end })
SpeedSec:Slider({ Name = "CFrame multiplier", Flag = "CFrameValue", Min = 1, Max = 10, Default = 2, Decimals = 1, Suffix = "x",
    Callback = function(v) Movement.setCFrameValue(v) end })

local JumpSec = Move:Section({ Name = "Jump", Side = 1 })
JumpSec:Toggle({ Name = "JumpPower", Flag = "JumpEnabled", Default = false,
    Callback = function(v) Movement.setJump(v) end })
JumpSec:Slider({ Name = "JumpPower amount", Flag = "JumpValue", Min = 50, Max = 500, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setJumpValue(v) end })
JumpSec:Toggle({ Name = "Infinite jump", Flag = "InfJumpEnabled", Default = false,
    Callback = function(v) Movement.setInfJump(v) end })

local FlySec = Move:Section({ Name = "Fly", Side = 2 })
local FlyToggle = FlySec:Toggle({ Name = "Fly", Flag = "FlyEnabled", Default = false,
    Callback = function(v) Movement.setFly(v) end })
FlySec:Slider({ Name = "Fly speed", Flag = "FlyValue", Min = 10, Max = 300, Default = 60, Decimals = 0,
    Callback = function(v) Movement.setFlyValue(v) end })
FlySec:Label({ Name = "Fly toggle key" }):Keybind({
    Name = "Fly",
    Flag = "FlyKey", Mode = "Toggle", Default = Enum.KeyCode.F,
    Callback = function(state) FlyToggle:Set(state and true or false) end })

local UtilSec = Move:Section({ Name = "Utility", Side = 2 })
UtilSec:Toggle({ Name = "Noclip", Flag = "NoclipEnabled", Default = false,
    Callback = function(v) Movement.setNoclip(v) end })

-- ---- Player > Desync subpage ----
local DesyncSub = PlayerPage:SubPage({ Name = "Desync" })
do
    local Sec = DesyncSub:Section({ Name = "Desync", Side = 1 })
    local showFor   -- forward-declared; defined after the controls exist

    Sec:Toggle({ Name = "Enabled", Flag = "DesyncEnabled", Default = false,
        Callback = function(v) Desync.setEnabled(v) end })

    Sec:Dropdown({
        Name = "Method", Flag = "DesyncMethod", Default = "Void", Multi = false,
        Items = { "Void", "Spin", "Velocity", "Freeze", "Custom" },
        Callback = function(v)
            local m = (type(v) == "table" and v[1]) or v or "Void"
            Desync.setMethod(m)
            if showFor then showFor(m) end
        end,
    })

    -- All controls are created up front; the dropdown shows only the chosen
    -- method's controls (the rest are hidden).
    local voidMin = Sec:Slider({ Name = "Void min", Flag = "DesyncVoidMin",
        Min = 500, Max = 1000000, Default = 5000, Decimals = 0, Suffix = " studs",
        Callback = function(v) Desync.voidMin = v end })
    local voidMax = Sec:Slider({ Name = "Void max", Flag = "DesyncVoidMax",
        Min = 500, Max = 1000000, Default = 20000, Decimals = 0, Suffix = " studs",
        Callback = function(v) Desync.voidMax = v end })
    local spin = Sec:Slider({ Name = "Spin speed", Flag = "DesyncSpin",
        Min = 1, Max = 90, Default = 2, Decimals = 0,
        Callback = function(v) Desync.spinSpeed = v end })
    local vel = Sec:Slider({ Name = "Velocity magnitude", Flag = "DesyncVel",
        Min = 50, Max = 16384, Default = 16384, Decimals = 0,
        Callback = function(v) Desync.velMag = v end })
    local freezeNote = Sec:Label({ Name = "Freeze uses RakNet (executor-dependent)." })
    local cx = Sec:Textbox({ Name = "Custom X", Flag = "DesyncX", Default = "0",
        Numeric = true, Placeholder = "X", Callback = function(v) Desync.customX = tonumber(v) or 0 end })
    local cy = Sec:Textbox({ Name = "Custom Y", Flag = "DesyncY", Default = "0",
        Numeric = true, Placeholder = "Y", Callback = function(v) Desync.customY = tonumber(v) or 0 end })
    local cz = Sec:Textbox({ Name = "Custom Z", Flag = "DesyncZ", Default = "0",
        Numeric = true, Placeholder = "Z", Callback = function(v) Desync.customZ = tonumber(v) or 0 end })

    local CONTROLS = {
        Void     = { voidMin, voidMax },
        Spin     = { spin },
        Velocity = { vel },
        Freeze   = { freezeNote },
        Custom   = { cx, cy, cz },
    }
    function showFor(method)
        for name, list in pairs(CONTROLS) do
            for _, el in ipairs(list) do
                pcall(function() el:SetVisibility(name == method) end)
            end
        end
    end

    showFor("Void")   -- initial visibility matches the default method
end

-- ============================================================
--  VISUALS  (ESP)
-- ============================================================
local VisualsPage = Window:Page({ Name = "Visuals" })
local EspSub = VisualsPage:SubPage({ Name = "ESP" })
do
    local Sec = EspSub:Section({ Name = "Player ESP", Side = 1 })
    if not hasDrawing then
        Sec:Label({ Name = "ESP needs a Drawing-capable executor." })
    end
    Sec:Toggle({ Name = "Enabled (box)", Flag = "EspEnabled", Default = false,
        Callback = function(v) Esp.enabled = v end })
    Sec:Toggle({ Name = "Names", Flag = "EspNames", Default = false,
        Callback = function(v) Esp.names = v end })
    Sec:Toggle({ Name = "Distance", Flag = "EspDistance", Default = false,
        Callback = function(v) Esp.distance = v end })
    Sec:Toggle({ Name = "Health bar", Flag = "EspHealth", Default = false,
        Callback = function(v) Esp.health = v end })

    local Sec2 = EspSub:Section({ Name = "Options", Side = 2 })
    Sec2:Toggle({ Name = "Team check", Flag = "EspTeam", Default = false,
        Callback = function(v) Esp.teamCheck = v end })
    Sec2:Label({ Name = "Box color" }):Colorpicker({
        Flag = "EspColor", Default = Color3.fromRGB(200, 183, 247),
        Callback = function(c) Esp.color = c end })
end

-- ============================================================
--  PLAYER TARGET ACTIONS  (operate on the player selected in the
--  floating Players widget): Goto / Fling / View / Follow.
-- ============================================================
local PlayerActions = {}

function PlayerActions.gotoPlayer(plr)
    local tc = plr.Character; local th = tc and tc:FindFirstChild("HumanoidRootPart")
    local h = getHRP()
    if th and h then h.CFrame = th.CFrame * CFrame.new(0, 0, 3) end
end

-- velocity-glue touch fling: snap behind the target with huge velocity for ~1.5s
function PlayerActions.fling(plr)
    task.spawn(function()
        local conn
        conn = RunService.Heartbeat:Connect(function()
            local h = getHRP()
            local tc = plr.Character; local th = tc and tc:FindFirstChild("HumanoidRootPart")
            if not h or not th then return end
            h.CFrame = th.CFrame * CFrame.new(0, 0, 1)
            h.AssemblyLinearVelocity = Vector3.one * 9e4
        end)
        local deadline = tick() + 1.5
        while tick() < deadline do
            if not plr.Character or not getChar() then break end
            task.wait()
        end
        if conn then conn:Disconnect() end
        local h = getHRP()
        if h then h.AssemblyLinearVelocity = Vector3.zero; h.AssemblyAngularVelocity = Vector3.zero end
    end)
end

do  -- View (spectate) -- toggles on the same target
    local viewing, prevSubject, charConn = nil, nil, nil
    function PlayerActions.view(plr)
        local cam = Workspace.CurrentCamera
        if charConn then charConn:Disconnect(); charConn = nil end
        if viewing == plr then
            cam.CameraSubject = getHum() or prevSubject
            viewing = nil
            return
        end
        if not viewing then prevSubject = cam.CameraSubject end
        viewing = plr
        local function apply()
            local tc = plr.Character; local hum = tc and tc:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum end
        end
        apply()
        charConn = plr.CharacterAdded:Connect(function()
            task.wait(0.2); if viewing == plr then apply() end
        end)
    end
    function PlayerActions.stopView()
        if charConn then charConn:Disconnect(); charConn = nil end
        if viewing then
            Workspace.CurrentCamera.CameraSubject = getHum() or prevSubject
            viewing = nil
        end
    end
end

do  -- Follow (pathfinding) -- toggles on the same target
    local PathfindingService = game:GetService("PathfindingService")
    local target, path = nil, nil
    function PlayerActions.stopFollow() target = nil end
    function PlayerActions.follow(plr)
        if target == plr then target = nil; return end
        target = plr
        path = PathfindingService:CreatePath({
            AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
            AgentJumpHeight = 7.2, AgentMaxSlope = 45,
        })
        task.spawn(function()
            local t = plr
            while target == t do
                local hum, hrp = getHum(), getHRP()
                local tc = t.Character; local thrp = tc and tc:FindFirstChild("HumanoidRootPart")
                if not (hum and hrp and thrp) then task.wait(0.2); continue end
                if (hrp.Position - thrp.Position).Magnitude < 8 then
                    pcall(function() hum:MoveTo(thrp.Position) end); task.wait(0.1); continue
                end
                local ok = pcall(function() path:ComputeAsync(hrp.Position, thrp.Position) end)
                if ok and path.Status == Enum.PathStatus.Success then
                    local wp = path:GetWaypoints()[2]
                    if wp then
                        if wp.Action == Enum.PathWaypointAction.Jump then pcall(function() hum.Jump = true end) end
                        pcall(function() hum:MoveTo(wp.Position) end)
                    end
                    task.wait(0.1)
                else
                    pcall(function() hum:MoveTo(thrp.Position) end); task.wait(0.1)
                end
            end
        end)
    end
end

-- wire the buttons onto the floating Players widget
do
    local PL = ctx.Playerlist
    if PL and PL.AddAction then
        local function needTarget(fn)
            return function(plr)
                if not plr then
                    Library:Notification("Select a player first", 2, Library.Theme["Accent"])
                    return
                end
                fn(plr)
            end
        end
        PL:AddAction("Goto",   needTarget(PlayerActions.gotoPlayer))
        PL:AddAction("Fling",  needTarget(PlayerActions.fling))
        PL:AddAction("View",   needTarget(PlayerActions.view))
        PL:AddAction("Follow", needTarget(PlayerActions.follow))
    end
end

-- ============================================================
--  TEARDOWN
--  Turn EVERYTHING off and disconnect every feature connection. Runs when the
--  GUI unloads (hooked to Library.OnExit, fired by Library:Exit / the Unload
--  button) and when the loader re-executes (it calls the previous instance's
--  disableAll). This is what stops you being stuck in cframe/camlock/etc. after
--  a reload.
-- ============================================================
local function disableAll()
    -- reset state-changing toggles (walkspeed->16, collide->true, velocity 0, ...)
    pcall(Movement.setWalkSpeed, false)
    pcall(Movement.setJump, false)
    pcall(Movement.setCFrame, false)
    pcall(Movement.setFly, false)
    pcall(Movement.setNoclip, false)
    pcall(Movement.setInfJump, false)
    -- combat / visuals: flag off (their connections are disconnected below)
    CamLock.enabled = false
    Trig.enabled = false
    Esp.enabled, Esp.names, Esp.distance, Esp.health = false, false, false, false
    pcall(function() if Desync.stop then Desync.stop() end end)
    -- player actions
    pcall(function() if PlayerActions.stopFollow then PlayerActions.stopFollow() end end)
    pcall(function() if PlayerActions.stopView then PlayerActions.stopView() end end)
    pcall(function() if Esp.clear then Esp.clear() end end)
    -- disconnect every tracked connection
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}
end

-- Fire teardown on unload (Library:Exit calls Library.OnExit) and expose it so
-- the loader can tear this instance down before re-executing.
Library.OnExit = disableAll
if getgenv then
    local g = getgenv()
    if g.WH then g.WH.disableAll = disableAll end
end
