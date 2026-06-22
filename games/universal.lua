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

do  -- Respawn (keep position) + the canonical "land upright on my feet" teleport
    -- uprightTeleport: drop the player at `pos` STANDING -- keep only yaw (no pitch/roll
    -- so we never tip over) and sit on top of the floor under pos (no clipping in). Use
    -- this for every teleport so we always land on our feet, even from laying down.
    function Movement.uprightTeleport(hrp, pos, look, hum)
        if not (hrp and pos) then return end
        local flat = look and Vector3.new(look.X, 0, look.Z) or Vector3.new(0, 0, -1)
        if flat.Magnitude < 1e-3 then flat = Vector3.new(0, 0, -1) end
        flat = flat.Unit
        -- raycast down to find the floor so we stand ON it instead of half-buried (which tips us)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { hrp.Parent }
        local hit = Workspace:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -80, 0), params)
        local y = pos.Y
        if hit then y = hit.Position.Y + (hum and hum.HipHeight or 2) + hrp.Size.Y / 2 end
        local target = Vector3.new(pos.X, y, pos.Z)
        pcall(function()
            hrp.CFrame = CFrame.new(target, target + flat)  -- flat look vector => upright
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end

    -- Force-kill, then the instant we respawn put us back where our HRP was, upright.
    function Movement.respawn()
        local hrp = getHRP()
        local savedPos = hrp and hrp.Position
        local savedLook = hrp and hrp.CFrame.LookVector
        if savedPos then
            local conn
            conn = LocalPlayer.CharacterAdded:Connect(function(newChar)
                conn:Disconnect()
                local nh = newChar:WaitForChild("HumanoidRootPart", 8)
                local nhum = newChar:FindFirstChildOfClass("Humanoid") or newChar:WaitForChild("Humanoid", 2)
                if not nh then return end
                task.wait(0.2)  -- let the spawn settle so it doesn't fight our CFrame
                Movement.uprightTeleport(nh, savedPos, savedLook, nhum)
            end)
        end
        local hum = getHum()
        if hum then pcall(function() hum.Health = 0 end) end
    end
end

do  -- Anti-fling (velocity / spin guards on the root)
    local antiFling, conn = false, nil
    local MAX_LIN_H = 120   -- a real fling spikes horizontal velocity far past any movement
    local MAX_ANG   = 30    -- characters shouldn't spin; flings add huge angular velocity
    local function step()
        if not antiFling then return end
        local hrp = getHRP(); if not hrp then return end
        local v = hrp.AssemblyLinearVelocity
        local horiz = Vector3.new(v.X, 0, v.Z)
        if horiz.Magnitude > MAX_LIN_H then
            hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)  -- kill horizontal fling, keep gravity
        end
        if hrp.AssemblyAngularVelocity.Magnitude > MAX_ANG then
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end
        local cf = hrp.CFrame
        if cf.UpVector.Y < 0.7 then  -- tipped over by a fling -> stand back up (keep facing)
            local look = cf.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude < 1e-3 then flat = Vector3.new(0, 0, -1) end
            hrp.CFrame = CFrame.new(cf.Position, cf.Position + flat.Unit)
        end
    end
    function Movement.setAntiFling(on)
        antiFling = on
        if conn then conn:Disconnect(); conn = nil end
        if on then conn = track(RunService.Heartbeat:Connect(step)) end
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
        gui.Name = "_wh_target"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = false
        pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
        if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
        line = Instance.new("Frame")
        line.BorderSizePixel = 0; line.AnchorPoint = Vector2.new(0.5, 0.5); line.Visible = false; line.Parent = gui
    end
    track(RunService.RenderStepped:Connect(function()
        local part = combatPart()
        if Combat.line and part then
            ensureGui()
            local cam = Workspace.CurrentCamera
            local sp = cam:WorldToViewportPoint(part.Position)
            if sp.Z > 0 then
                local vs = cam.ViewportSize
                local o, a = Combat.lineOrigin
                if o == "Top" then a = Vector2.new(vs.X * 0.5, 0)
                elseif o == "Center" then a = Vector2.new(vs.X * 0.5, vs.Y * 0.5)
                elseif o == "Mouse" then a = UserInputService:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
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

-- ============================================================
--  ESP  (box / name / distance / health via Drawing)
-- ============================================================
local Esp = {
    enabled = false, box = true, names = false, distance = false, health = false,
    teamCheck = false, color = Color3.fromRGB(200, 183, 247),
    boxType = "Full",                 -- "Full" | "Corner" | "Solid"
    fillOpacity = 0.4,                -- Drawing alpha for the "Solid" filled box
    tracer = false, tracerOrigin = "Bottom",   -- "Bottom" | "Top" | "Mouse"
    chams = false,                    -- in-game Highlight
    chamsFill = Color3.fromRGB(200, 183, 247),
    chamsOutline = Color3.fromRGB(255, 255, 255),
    chamsTransparency = 0.6,          -- Highlight FillTransparency (0 = solid)
    skeleton = false,
}
-- expose for the ESP Preview widget (it reads these to draw a live preview box)
if getgenv then
    local g = getgenv()
    if g.WH then g.WH.espPreview = Esp end
end
do
    local objs = {}   -- plr -> { box, solid, name, dist, health, tracer, corners?, skel?, chams? }

    -- skeleton bone pairs (R15 first, then R6; missing parts are skipped)
    local BONES = {
        { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
        { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    }

    -- Drawing.Line and Drawing.Triangle flicker on some executors, while
    -- Drawing.Square / Text and in-game GUI frames are rock-steady. So the
    -- lines (tracer / corner brackets / skeleton) are drawn as thin rotated
    -- GUI frames on our own ScreenGui, and the body fill is a filled Square.
    local espGui = Instance.new("ScreenGui")
    espGui.Name = "\0"
    espGui.ResetOnSpawn = false
    espGui.IgnoreGuiInset = true    -- (0,0) at the very top, matching the 3D
                                    -- viewport that WorldToViewportPoint/Drawing use
                                    -- (false would push every line down by the 36px
                                    -- topbar inset -> lines land below the player)
    espGui.DisplayOrder = 5
    pcall(function() espGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not espGui.Parent then
        pcall(function() espGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
    end

    local function lineFrame()
        local f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BorderSizePixel = 0
        f.BackgroundColor3 = Esp.color
        f.Visible = false
        f.Parent = espGui
        return f
    end
    -- aim a thin frame from screen-point a to screen-point b (a rotated 1px bar).
    -- Center it on a pixel (floor + 0.5) so the 1px bar renders crisp instead of
    -- smearing across two rows -- a half-pixel-straddled line reads as a fat ~2px
    -- blur, so snapping it makes the tracer look properly thin.
    local function setLine(f, a, b, color, thickness)
        local d = b - a
        f.Size = UDim2.fromOffset(math.max(d.Magnitude, 1), thickness or 1)
        f.Position = UDim2.fromOffset(
            math.floor((a.X + b.X) / 2) + 0.5, math.floor((a.Y + b.Y) / 2) + 0.5)
        f.Rotation = math.deg(math.atan2(d.Y, d.X))
        f.BackgroundColor3 = color
        f.Visible = true
    end

    local function add(plr)
        if plr == LocalPlayer or objs[plr] or not hasDrawing then return end
        objs[plr] = {
            box    = mkDraw("Square", { Thickness = 1, Filled = false, Visible = false, Transparency = 1 }),
            solid  = mkDraw("Square", { Thickness = 0, Filled = true, Visible = false }),
            name   = mkDraw("Text",   { Size = 13, Center = true, Outline = true, Visible = false }),
            dist   = mkDraw("Text",   { Size = 12, Center = true, Outline = true, Visible = false }),
            health = mkDraw("Square", { Thickness = 1, Filled = true, Visible = false }),
            tracer = lineFrame(),
            corners = nil, skel = nil, chams = nil, glow = nil,   -- created lazily when used
        }
    end
    local function remove(plr)
        local o = objs[plr]; if not o then return end
        for _, k in ipairs({ "box", "solid", "name", "dist", "health" }) do
            if o[k] then pcall(function() o[k]:Remove() end) end   -- Drawing objects
        end
        if o.tracer then pcall(function() o.tracer:Destroy() end) end
        if o.corners then for _, d in ipairs(o.corners) do pcall(function() d:Destroy() end) end end
        if o.skel then for _, d in ipairs(o.skel) do pcall(function() d:Destroy() end) end end
        if o.chams then pcall(function() o.chams:Destroy() end) end
        if o.glow then pcall(function() o.glow:Destroy() end) end
        objs[plr] = nil
    end

    local function ensureCorners(o)
        if o.corners then return o.corners end
        local c = {}; for i = 1, 8 do c[i] = lineFrame() end
        o.corners = c; return c
    end
    local function ensureSkel(o)
        if o.skel then return o.skel end
        local s = {}; for i = 1, #BONES do s[i] = lineFrame() end
        o.skel = s; return s
    end
    local function ensureChams(o, char)   -- in-game Highlight
        -- key off the CURRENT character: on respawn the old char (and its
        -- Highlight) may linger, so checking Parent alone would keep adorning the
        -- dead body. Rebuild whenever the adornee no longer matches this char.
        if o.chams and o.chams.Adornee == char and o.chams.Parent then return o.chams end
        if o.chams then pcall(function() o.chams:Destroy() end) end
        local h = Instance.new("Highlight")
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Adornee = char
        h.Parent = char
        o.chams = h; return h
    end
    -- glow: make the CHARACTER glow so it conforms to the body, instead of a flat
    -- shape floating around them. Override each part's Material locally with
    -- ForceField (a soft energy glow on the real geometry) and remember the
    -- original material so it can be restored when chams turns off / the player
    -- leaves the closest-N set / on unload. Local-only -- not replicated.
    -- glow: a PointLight at the character's centre throws a soft 360-degree glow
    -- around the whole player (and lights nearby surfaces) -- it does NOT touch the
    -- character's body at all. Just an added instance, so cleanup is deleting it.
    local function ensureGlow(o, char)
        local part = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
        if not part then return nil end
        if o.glow and o.glow.Parent == part then return o.glow end
        if o.glow then pcall(function() o.glow:Destroy() end) end
        local light = Instance.new("PointLight")
        light.Range = 4          -- small, so the glow hugs the target and barely
        light.Brightness = 10    -- bleeds onto nearby players (incl. the local one)
        light.Shadows = false
        light.Parent = part
        o.glow = light; return light
    end

    for _, p in ipairs(Players:GetPlayers()) do add(p) end
    track(Players.PlayerAdded:Connect(add))
    track(Players.PlayerRemoving:Connect(remove))

    function Esp.clear()   -- remove all ESP objects (used on unload)
        for plr in pairs(objs) do remove(plr) end
        pcall(function() espGui:Destroy() end)
    end

    local CHAMS_LIMIT = 32   -- the engine only renders ~32 Highlights at once

    track(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        local vp = cam.ViewportSize
        local mouse = UserInputService:GetMouseLocation()
        local myHRP = getHRP()

        -- chams render budget: Roblox only draws ~32 Highlights, so each frame
        -- pick the CHAMS_LIMIT players closest to us and only those get one (the
        -- rest are disabled). Without this, far/extra players silently fail to
        -- highlight -- which also looked like "respawned/joined players don't get
        -- chams" once the cap was already used up by everyone else.
        local chamsTop = nil
        if Esp.enabled and Esp.chams then
            chamsTop = {}
            local list = {}
            local myPos = myHRP and myHRP.Position
            for plr2 in pairs(objs) do
                if teamOk(plr2, Esp.teamCheck) then
                    local ch = aliveChar(plr2)
                    local h2 = ch and ch:FindFirstChild("HumanoidRootPart")
                    if h2 then
                        list[#list + 1] = { plr2, myPos and (h2.Position - myPos).Magnitude or 0 }
                    end
                end
            end
            table.sort(list, function(a, b) return a[2] < b[2] end)
            for i = 1, math.min(#list, CHAMS_LIMIT) do chamsTop[list[i][1]] = true end
        end

        for plr, o in pairs(objs) do
            if not o.box then continue end
            -- hide everything first
            o.box.Visible = false; o.solid.Visible = false; o.name.Visible = false
            o.dist.Visible = false; o.health.Visible = false; o.tracer.Visible = false
            if o.corners then for _, d in ipairs(o.corners) do d.Visible = false end end
            if o.skel then for _, d in ipairs(o.skel) do d.Visible = false end end

            local active = Esp.enabled and teamOk(plr, Esp.teamCheck)
            local char, hum = nil, nil
            if active then char, hum = aliveChar(plr) end
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            -- chams: closest 32 get an AlwaysOnTop Highlight + a soft glow aura
            if active and char and Esp.chams and chamsTop and chamsTop[plr] then
                local h = ensureChams(o, char)
                h.Enabled = true
                h.FillColor = Esp.chamsFill
                h.OutlineColor = Esp.chamsOutline
                h.FillTransparency = Esp.chamsTransparency
                h.OutlineTransparency = 0
                local lt = ensureGlow(o, char)
                if lt then lt.Enabled = true; lt.Color = Esp.chamsFill end
            else
                if o.chams then o.chams.Enabled = false end
                -- destroy (not just disable) the glow light so it fully disappears
                -- the moment chams is off / the player drops out of the closest set
                if o.glow then pcall(function() o.glow:Destroy() end); o.glow = nil end
            end

            if active and hrp then
                local center, on = cam:WorldToViewportPoint(hrp.Position)
                local top = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                local bot = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                local height = math.max(math.abs(top.Y - bot.Y), 1)
                local width  = height * 0.55
                local x, y = center.X - width / 2, center.Y - height / 2

                -- tracer: drawn for EVERY target in front of the camera, including
                -- ones off-screen / not in view (the line just runs off the screen
                -- edge toward them). center.Z > 0 == in front; behind-camera points
                -- project inverted, so we skip those. 1px is the GUI floor (sub-1px
                -- frames render nothing), so this is as thin as a GUI line goes.
                if Esp.tracer and center.Z > 0 then
                    local origin
                    if Esp.tracerOrigin == "Top" then origin = Vector2.new(vp.X / 2, 0)
                    elseif Esp.tracerOrigin == "Mouse" then origin = mouse
                    else origin = Vector2.new(vp.X / 2, vp.Y) end
                    setLine(o.tracer, origin, Vector2.new(center.X, y + height), Esp.color, 1)
                end

                if on then
                    -- box: full outline / corner brackets / solid filled box
                    if not Esp.box then
                        -- box disabled; leave it hidden
                    elseif Esp.boxType == "Corner" then
                        local c = ensureCorners(o)
                        local cl = math.min(width, height) * 0.3
                        local pts = {
                            { x, y, x + cl, y }, { x, y, x, y + cl },                              -- TL
                            { x + width, y, x + width - cl, y }, { x + width, y, x + width, y + cl }, -- TR
                            { x, y + height, x + cl, y + height }, { x, y + height, x, y + height - cl }, -- BL
                            { x + width, y + height, x + width - cl, y + height }, { x + width, y + height, x + width, y + height - cl }, -- BR
                        }
                        for i, p in ipairs(pts) do
                            setLine(c[i], Vector2.new(p[1], p[2]), Vector2.new(p[3], p[4]), Esp.color)
                        end
                    elseif Esp.boxType == "Solid" then
                        -- filled translucent box (a Drawing.Square -- no flicker,
                        -- unlike the triangle-fan silhouette)
                        o.solid.Color = Esp.color
                        o.solid.Size = Vector2.new(width, height)
                        o.solid.Position = Vector2.new(x, y)
                        o.solid.Transparency = Esp.fillOpacity
                        o.solid.Visible = true
                    else
                        o.box.Color = Esp.color
                        o.box.Size = Vector2.new(width, height)
                        o.box.Position = Vector2.new(x, y)
                        o.box.Visible = true
                    end

                    if Esp.names then
                        o.name.Text = plr.Name; o.name.Color = Esp.color
                        o.name.Position = Vector2.new(center.X, y - 14); o.name.Visible = true
                    end
                    if Esp.distance then
                        local d = myHRP and math.floor((myHRP.Position - hrp.Position).Magnitude) or 0
                        o.dist.Text = tostring(d) .. "m"; o.dist.Color = Esp.color
                        o.dist.Position = Vector2.new(center.X, y + height + 2); o.dist.Visible = true
                    end
                    if Esp.health then
                        local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        o.health.Size = Vector2.new(2, height * hp)
                        o.health.Position = Vector2.new(x - 4, y + height * (1 - hp))
                        o.health.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(80, 255, 80), hp)
                        o.health.Visible = true
                    end
                end

                -- skeleton (per-part on-screen)
                if Esp.skeleton and char then
                    local s = ensureSkel(o)
                    for i, bone in ipairs(BONES) do
                        local p1, p2 = char:FindFirstChild(bone[1]), char:FindFirstChild(bone[2])
                        local line = s[i]
                        if p1 and p2 and line then
                            local a, aOn = cam:WorldToViewportPoint(p1.Position)
                            local b, bOn = cam:WorldToViewportPoint(p2.Position)
                            if aOn and bOn then
                                setLine(line, Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y), Esp.color)
                            end
                        end
                    end
                end
            end
        end
    end))
end

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
            local id; pcall(function() id = packet.PacketId end)
            if id == 0x1B then     -- outbound physics replication
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
            if realLV and realLV.Magnitude < 1000 then hrp.AssemblyLinearVelocity = realLV end  -- never re-apply a fling velocity
            if realAV and realAV.Magnitude < 1000 then hrp.AssemblyAngularVelocity = realAV end
        end)
    end)

    local function removeRaknetHook()
        if SHARED.hookInstalled and SHARED.hookFn then
            local r = findRaknet()
            if r and r.remove_send_hook then pcall(function() r.remove_send_hook(SHARED.hookFn) end) end
        end
        SHARED.hookInstalled = false
        SHARED.hookFn = nil
    end

    -- restore your REAL position (fixes being left at the fake spot on disable)
    local function restoreReal()
        local hrp = getHRP()
        if hrp and realCF then
            pcall(function()
                hrp.CFrame = realCF
                if realLV and realLV.Magnitude < 1000 then hrp.AssemblyLinearVelocity = realLV end  -- never re-apply a fling velocity
                if realAV and realAV.Magnitude < 1000 then hrp.AssemblyAngularVelocity = realAV end
            end)
        end
    end

    -- Enabled drives the heartbeat-spoof methods ONLY (void/spin/velocity/custom);
    -- it never touches raknet.
    function Desync.setEnabled(on)
        Desync.enabled = on and true or false
        if not Desync.enabled then
            restoreReal()
            -- forget the snapshot, otherwise the next enable's restore fires with
            -- this stale CFrame (before Heartbeat re-captures) and yanks you back to
            -- the old spot. Cleared = the next enable starts from where you are now.
            realCF, realLV, realAV = nil, nil, nil
        end
    end
    function Desync.setMethod(m) Desync.method = m end

    -- Freeze is the ONLY raknet mode, behind its own explicit toggle. RakNet can
    -- get accounts terminated, so the hook is only installed while this is on and
    -- removed the moment it's turned off. Returns false if raknet is unavailable
    -- so the UI can flip the toggle back off.
    function Desync.setFreeze(on)
        if on then
            if not ensureRaknetHook() then SHARED.freeze = false; return false end
            SHARED.freeze = true
            return true
        end
        SHARED.freeze = false
        removeRaknetHook()
        return true
    end

    function Desync.stop()
        Desync.setEnabled(false)   -- restores real position
        SHARED.freeze = false
        removeRaknetHook()
        pcall(function() RunService:UnbindFromRenderStep(RESTORE) end)
    end
end

-- ============================================================
--  PLAYER  (working universal movement)
-- ============================================================
local PlayerPage = Window:Page({ Name = "Player" })
local Move = PlayerPage:SubPage({ Name = "Movement" })

local SpeedSec = Move:Section({ Name = "Speed", Side = 1 })
local WalkToggle = SpeedSec:Toggle({ Name = "WalkSpeed", Flag = "WalkSpeedEnabled", Default = false,
    Callback = function(v) Movement.setWalkSpeed(v) end })
SpeedSec:Slider({ Name = "WalkSpeed amount", Flag = "WalkSpeedValue", Min = 16, Max = 2000, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setWalkSpeedValue(v) end })
SpeedSec:Label({ Name = "Toggle key" }):Keybind({ Name = "WalkSpeed", Flag = "WalkSpeedKey", Mode = "Toggle",
    Callback = function(state) WalkToggle:Set(state and true or false) end })
local CFrameToggle = SpeedSec:Toggle({ Name = "CFrame speed", Flag = "CFrameEnabled", Default = false,
    Callback = function(v) Movement.setCFrame(v) end })
SpeedSec:Slider({ Name = "CFrame multiplier", Flag = "CFrameValue", Min = 1, Max = 50, Default = 2, Decimals = 1, Suffix = "x",
    Callback = function(v) Movement.setCFrameValue(v) end })
SpeedSec:Label({ Name = "Toggle key" }):Keybind({ Name = "CFrame speed", Flag = "CFrameKey", Mode = "Toggle",
    Callback = function(state) CFrameToggle:Set(state and true or false) end })

local JumpSec = Move:Section({ Name = "Jump", Side = 1 })
local JumpToggle = JumpSec:Toggle({ Name = "JumpPower", Flag = "JumpEnabled", Default = false,
    Callback = function(v) Movement.setJump(v) end })
JumpSec:Slider({ Name = "JumpPower amount", Flag = "JumpValue", Min = 50, Max = 2000, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setJumpValue(v) end })
JumpSec:Label({ Name = "Toggle key" }):Keybind({ Name = "Jump power", Flag = "JumpKey", Mode = "Toggle",
    Callback = function(state) JumpToggle:Set(state and true or false) end })
JumpSec:Toggle({ Name = "Infinite jump", Flag = "InfJumpEnabled", Default = false,
    Callback = function(v) Movement.setInfJump(v) end })

local FlySec = Move:Section({ Name = "Fly", Side = 2 })
local FlyToggle = FlySec:Toggle({ Name = "Fly", Flag = "FlyEnabled", Default = false,
    Callback = function(v) Movement.setFly(v) end })
FlySec:Slider({ Name = "Fly speed", Flag = "FlyValue", Min = 10, Max = 1000, Default = 60, Decimals = 0,
    Callback = function(v) Movement.setFlyValue(v) end })
FlySec:Label({ Name = "Fly toggle key" }):Keybind({
    Name = "Fly",
    Flag = "FlyKey", Mode = "Toggle", Default = Enum.KeyCode.F,
    Callback = function(state) FlyToggle:Set(state and true or false) end })

local UtilSec = Move:Section({ Name = "Utility", Side = 2 })
UtilSec:Toggle({ Name = "Noclip", Flag = "NoclipEnabled", Default = false,
    Callback = function(v) Movement.setNoclip(v) end })
UtilSec:Button({ Name = "Respawn (keep position)",
    Callback = function() Movement.respawn() end })
UtilSec:Label({ Name = "Respawn key" }):Keybind({ Name = "Respawn", Flag = "RespawnKey", Mode = "Hold",
    Callback = function(state) if state then Movement.respawn() end end })
UtilSec:Toggle({ Name = "Anti-fling", Flag = "AntiFlingEnabled", Default = false,
    Callback = function(v) Movement.setAntiFling(v) end })

-- ---- Player > Desync subpage ----
local DesyncSub = PlayerPage:SubPage({ Name = "Desync" })
do
    local Sec = DesyncSub:Section({ Name = "Desync", Side = 1 })
    local showFor, enabledToggle, freezeToggle, freezeWarn  -- forward-declared

    Sec:Dropdown({
        Name = "Method", Flag = "DesyncMethod", Default = "Void", Multi = false,
        Items = { "Void", "Spin", "Freeze", "Custom" },
        Callback = function(v)
            local m = (type(v) == "table" and v[1]) or v or "Void"
            -- switching method = clean slate: turn both toggles off so a spoof
            -- (or raknet) never keeps running across a method change
            pcall(function() enabledToggle:Set(false) end)
            pcall(function() freezeToggle:Set(false) end)
            Desync.setMethod(m)
            if showFor then showFor(m) end
        end,
    })

    -- Enabled = heartbeat-spoof methods (void/spin/velocity/custom). No raknet.
    enabledToggle = Sec:Toggle({ Name = "Enabled", Flag = "DesyncEnabled", Default = false,
        Callback = function(v) Desync.setEnabled(v) end })
    Sec:Label({ Name = "Toggle key" }):Keybind({ Name = "Desync", Flag = "DesyncKey", Mode = "Toggle",
        Callback = function(state) enabledToggle:Set(state and true or false) end })

    -- RakNet freeze = the ONLY raknet path, behind its own explicit toggle.
    freezeToggle = Sec:Toggle({ Name = "RakNet freeze", Flag = "DesyncFreeze", Default = false,
        Callback = function(v)
            local ok = Desync.setFreeze(v)
            if v and not ok then
                Library:Notification("RakNet not available in this executor", 3, Library.Theme["Risky"])
                pcall(function() freezeToggle:Set(false) end)
            end
        end })
    freezeWarn = Sec:Label({ Name = "RakNet -- detection/ban risk." })

    -- value controls (shown only for their method)
    local voidMin = Sec:Slider({ Name = "Void min", Flag = "DesyncVoidMin",
        Min = 500, Max = 1000000, Default = 5000, Decimals = 0, Suffix = " studs",
        Callback = function(v) Desync.voidMin = v end })
    local voidMax = Sec:Slider({ Name = "Void max", Flag = "DesyncVoidMax",
        Min = 500, Max = 1000000, Default = 20000, Decimals = 0, Suffix = " studs",
        Callback = function(v) Desync.voidMax = v end })
    local spin = Sec:Slider({ Name = "Spin speed", Flag = "DesyncSpin",
        Min = 1, Max = 90, Default = 2, Decimals = 0,
        Callback = function(v) Desync.spinSpeed = v end })
    local cx = Sec:Textbox({ Name = "Custom X", Flag = "DesyncX", Default = "0",
        Numeric = true, Placeholder = "X", Callback = function(v) Desync.customX = tonumber(v) or 0 end })
    local cy = Sec:Textbox({ Name = "Custom Y", Flag = "DesyncY", Default = "0",
        Numeric = true, Placeholder = "Y", Callback = function(v) Desync.customY = tonumber(v) or 0 end })
    local cz = Sec:Textbox({ Name = "Custom Z", Flag = "DesyncZ", Default = "0",
        Numeric = true, Placeholder = "Z", Callback = function(v) Desync.customZ = tonumber(v) or 0 end })

    local VALUE_CONTROLS = {
        Void = { voidMin, voidMax }, Spin = { spin }, Custom = { cx, cy, cz },
    }
    function showFor(method)
        local isFreeze = (method == "Freeze")
        pcall(function() enabledToggle:SetVisibility(not isFreeze) end)
        pcall(function() freezeToggle:SetVisibility(isFreeze) end)
        pcall(function() freezeWarn:SetVisibility(isFreeze) end)
        for name, list in pairs(VALUE_CONTROLS) do
            for _, el in ipairs(list) do
                pcall(function() el:SetVisibility(name == method) end)
            end
        end
    end

    showFor("Void")   -- initial visibility matches the default method
end

-- ============================================================
--  Fling  (orbit the selected player + velocity fling)
--  Target = the player selected in the hub's player list (ctx.Playerlist).
-- ============================================================
local FlingSub = PlayerPage:SubPage({ Name = "Fling" })
do
    local function selectedHRP()
        local ch = combatChar()   -- the locked target (Combat > Target subpage)
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    -- ---------- Orbit ----------
    local orbit = { on = false, dist = 4, speed = 400, minH = 0, maxH = 0, heightOn = false,
        lookAt = true, fakePos = false, desync = false, pattern = "Orbit" }
    local _attached, _angle, _orbitReal = false, 0, nil
    local _hCur, _hTarget, _hTimer = 0, 0, 0   -- smooth random height (advanced in the loop by dt)
    -- offset around the target for the chosen pattern. _hCur is a smooth random height between
    -- Min/Max (independent of orbit speed), applied only when the Height toggle is on.
    local function orbitOffset()
        local rad = math.rad(_angle)
        local d = orbit.dist
        local bob = orbit.heightOn and _hCur or 0
        local p = orbit.pattern
        if p == "Planetary" then           -- tilted ring (rises over + dips under the target)
            return Vector3.new(math.cos(rad) * d, math.sin(rad) * d * 0.7 + bob, math.sin(rad) * d * 0.5)
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
        local pos = tHrp.Position + orbitOffset()
        local cf = orbit.lookAt and CFrame.new(pos, tHrp.Position) or CFrame.new(pos)
        if orbit.desync then
            -- custom-desync style: replicate the orbit pose to the server each Heartbeat but
            -- keep our REAL character where it is (restored each RenderStep) -- the server
            -- sees us orbiting (flings the target) while we don't actually move there.
            -- DON'T touch velocity here: zeroing it kills your walk speed + animations.
            if _attached then orbitDetach() end
            _orbitReal = hrp.CFrame   -- our real home (RenderStep restored it last frame)
            pcall(function() hrp.CFrame = cf end)
        else
            orbitRestoreReal()   -- in case desync was just turned off
            if orbit.fakePos then
                -- fake pos resolver: re-root our physics replication onto the target.
                pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
                pcall(function() tHrp:SetNetworkOwner(LocalPlayer) end)
                if sethiddenproperty then pcall(function() sethiddenproperty(hrp, "PhysicsRepRootPart", tHrp) end) end
                _attached = true
            elseif _attached then
                orbitDetach()
            end
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

    local OSec = FlingSub:Section({ Name = "Orbit", Side = 1 })
    local orbitToggle = OSec:Toggle({ Name = "Orbit target", Flag = "FlingOrbit", Default = false,
        Callback = function(v) orbit.on = v end })
    OSec:Label({ Name = "Toggle key" }):Keybind({ Name = "Orbit", Flag = "FlingOrbitKey", Mode = "Toggle",
        Callback = function(state) orbitToggle:Set(state and true or false) end })
    OSec:Dropdown({ Name = "Orbit directions", Flag = "FlingOrbitPattern", Default = "Orbit", Multi = false,
        Items = { "Orbit", "Planetary", "Vertical", "Spiral" },
        Callback = function(v) orbit.pattern = (type(v) == "table" and v[1]) or v or "Orbit" end })
    OSec:Slider({ Name = "Distance", Flag = "FlingOrbitDist", Min = 0, Max = 30, Default = 4, Decimals = 1, Suffix = " studs",
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
    OSec:Toggle({ Name = "Fake Pos", Flag = "FlingOrbitFakePos", Default = false,
        Callback = function(v) orbit.fakePos = v end })
    OSec:Toggle({ Name = "Desync", Flag = "FlingOrbitDesync", Default = false,
        Callback = function(v) orbit.desync = v end })

    -- ---------- Velocity (moved out of Desync) ----------
    -- Same as the old velocity desync: REPLICATE the huge velocity on Heartbeat (so the
    -- server flings whoever you touch) but RESTORE your real velocity on RenderStep, so
    -- locally you don't actually get launched.
    -- Velocity fling: apply huge LINEAR + ANGULAR (spin) velocity -- the spin makes the
    -- on-contact fling far more reliable. "Through target" overlaps the locked target (with
    -- network ownership) so contact is guaranteed instead of relying on bumping into them.
    -- Your real velocity/pose is restored each RenderStep so you stay put.
    local velOn, velThrough, velMag, velReal, velRealCF = false, false, 16384, nil, nil
    local function setVel(on)
        velOn = on
        if not on then   -- zero on disable so a leftover fling velocity can't launch you
            local hrp = getHRP()
            if hrp then pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end) end
            velReal, velRealCF = nil, nil
        end
    end
    track(RunService.Heartbeat:Connect(function()
        if not velOn then return end
        local hrp = getHRP(); if not hrp then return end
        local v = hrp.AssemblyLinearVelocity
        if v.Magnitude < velMag * 0.5 then velReal = v end   -- only capture your real (non-fling) velocity
        velRealCF = hrp.CFrame
        if velThrough then
            local tHrp = selectedHRP()   -- the locked target (Combat > Target)
            if tHrp then
                pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
                pcall(function() tHrp:SetNetworkOwner(LocalPlayer) end)
                pcall(function() hrp.CFrame = tHrp.CFrame end)   -- overlap = guaranteed contact
            end
        end
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.one * velMag   -- linear only (no spin), straight from the slider
        end)
    end))
    RunService:BindToRenderStep("WH_FlingVelRestore", Enum.RenderPriority.First.Value, function()
        if not velOn then return end
        local hrp = getHRP()
        if hrp then pcall(function()
            hrp.AssemblyLinearVelocity = velReal or Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            if velThrough and velRealCF then hrp.CFrame = velRealCF end   -- stay put while flinging through them
        end) end
    end)
    local VSec = FlingSub:Section({ Name = "Velocity", Side = 2 })
    local velToggle = VSec:Toggle({ Name = "Velocity fling", Flag = "FlingVel", Default = false,
        Callback = function(v) setVel(v) end })
    VSec:Slider({ Name = "Velocity magnitude", Flag = "FlingVelMag", Min = 50, Max = 16384, Default = 16384, Decimals = 0,
        Callback = function(v) velMag = v end })
    VSec:Label({ Name = "Toggle key" }):Keybind({ Name = "Velocity fling", Flag = "FlingVelKey", Mode = "Toggle",
        Callback = function(state) velToggle:Set(state and true or false) end })
end

-- ============================================================
--  VISUALS  (ESP)
-- ============================================================
local VisualsPage = Window:Page({ Name = "Visuals" })
-- subpages pre-declared here to control tab order: ESP first, Misc last
local EspSub    = VisualsPage:SubPage({ Name = "ESP" })
local SrvPosSub = VisualsPage:SubPage({ Name = "Server Pos" })
local WorldSub  = VisualsPage:SubPage({ Name = "World" })
local MiscSub   = VisualsPage:SubPage({ Name = "Misc" })

-- ---- Misc utility toggles (Force enable chat) ----
do
    local Sec = MiscSub:Section({ Name = "Chat", Side = 1 })
    local TextChatService = game:GetService("TextChatService")
    local StarterGui = game:GetService("StarterGui")
    local function cfg(name) return TextChatService:FindFirstChild(name) end
    local saved, chatOn, lastAssert = nil, false, 0

    local function forceOn()
        pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true) end)
        local cw, cib = cfg("ChatWindowConfiguration"), cfg("ChatInputBarConfiguration")
        if cw then pcall(function() cw.Enabled = true end) end       -- new TextChatService window
        if cib then pcall(function() cib.Enabled = true end) end     -- new chat input bar
    end
    local function applyChat(on)
        if on then
            if not saved then   -- remember the original state once, to restore later
                saved = {}
                local ok, v = pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat) end)
                saved.core = ok and v or nil
                local cw, cib = cfg("ChatWindowConfiguration"), cfg("ChatInputBarConfiguration")
                saved.window = cw and cw.Enabled
                saved.input  = cib and cib.Enabled
            end
            forceOn()
        elseif saved then       -- restore exactly what it was before we forced it on
            if saved.core ~= nil then
                pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, saved.core) end)
            end
            local cw, cib = cfg("ChatWindowConfiguration"), cfg("ChatInputBarConfiguration")
            if cw and saved.window ~= nil then pcall(function() cw.Enabled = saved.window end) end
            if cib and saved.input ~= nil then pcall(function() cib.Enabled = saved.input end) end
            saved = nil
        end
    end

    Sec:Toggle({ Name = "Force enable chat", Flag = "ForceChat", Default = false,
        Callback = function(v) chatOn = v; applyChat(v) end })
    -- re-assert while on so a game that keeps disabling chat can't win it back
    track(RunService.Heartbeat:Connect(function()
        if not chatOn then return end
        if tick() - lastAssert < 1 then return end
        lastAssert = tick()
        forceOn()
    end))
end

-- ============================================================
--  SERVER POS  -- a local clone of your body pinned to where your client is
--  replicating to the server (the pre-physics / Stepped CFrame). With desync on
--  it shows the gap; in sync it overlaps you. Client-created -> only you see it.
-- ============================================================
do
    local SP = SrvPosSub
    local EXTRA_DELAY = 0.11   -- clone lags by network ping + this (fixed); sits where the server has you
    local cfg = {
        on = false, transparency = 0.5, material = "ForceField",
        color = Color3.fromRGB(255, 60, 60),
        outline = false, outlineColor = Color3.fromRGB(255, 255, 255),
    }
    local MATERIALS = { "ForceField", "Neon", "Plastic", "SmoothPlastic", "Glass", "Metal" }
    local clone, hl
    local history = {}      -- timestamped {t, cf} samples of the replicated CFrame, oldest-first
    local partMap = {}      -- clonePart -> realPart (handles duplicate-named accessory Handles)

    local function applyStyle()
        if not clone then return end
        local mat = Enum.Material[cfg.material] or Enum.Material.ForceField
        for _, p in ipairs(clone:GetChildren()) do
            if p:IsA("BasePart") then
                pcall(function()
                    p.Color = cfg.color; p.Transparency = cfg.transparency; p.Material = mat
                end)
            end
        end
        if cfg.outline then
            if not (hl and hl.Parent) then
                hl = Instance.new("Highlight")
                hl.FillTransparency = 1
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            end
            hl.Adornee = clone; hl.OutlineColor = cfg.outlineColor; hl.Parent = clone
        elseif hl then pcall(function() hl:Destroy() end); hl = nil end
    end

    local function clearClone()
        if hl then pcall(function() hl:Destroy() end); hl = nil end
        if clone then pcall(function() clone:Destroy() end); clone = nil end
    end
    local function prepPart(p)   -- bare mesh shape, NO textures, so custom color/material shows
        for _, ch in ipairs(p:GetChildren()) do
            if ch:IsA("Decal") or ch:IsA("Texture") then
                pcall(function() ch:Destroy() end)                 -- drop face / surface textures
            elseif ch:IsA("DataModelMesh") then
                if ch:IsA("SpecialMesh") then pcall(function() ch.TextureId = "" end) end  -- keep shape, drop its texture
            else
                pcall(function() ch:Destroy() end)                 -- welds / attachments / scripts / particles
            end
        end
        if p:IsA("MeshPart") then pcall(function() p.TextureID = "" end) end   -- clear MeshPart texture
        p.Anchored = true; p.CanCollide = false; p.CanQuery = false
        p.CanTouch = false; p.Massless = true
    end
    local function buildClone()
        clearClone()
        partMap = {}
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChild("HumanoidRootPart") then return end
        local m = Instance.new("Model"); m.Name = "\0"
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then               -- body part
                local ok, p = pcall(function() return part:Clone() end)
                if ok and p then
                    prepPart(p)
                    if p.Name == "HumanoidRootPart" then p.Name = "Root" end  -- a stray "HumanoidRootPart" gets nuked by anti-cheat; rename it
                    p.Parent = m
                    partMap[p] = part
                end
            elseif part:IsA("Accessory") then          -- hat / accessory: clone its Handle
                local handle = part:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then
                    local ok, p = pcall(function() return handle:Clone() end)
                    if ok and p then prepPart(p); p.Parent = m; partMap[p] = handle end
                end
            end
        end
        if not next(partMap) then m:Destroy(); return end
        m.Parent = workspace   -- client-created instance: stays local, never replicates
        clone = m
        applyStyle()
    end

    -- buffer the FULL pose (every tracked part's world CFrame, pre-physics), timestamped,
    -- so both position AND animation can be replayed delayed
    track(RunService.Stepped:Connect(function()
        if not cfg.on then return end
        local now = os.clock()
        local snap = {}
        for _, rp in pairs(partMap) do
            if rp.Parent then snap[rp] = rp.CFrame end
        end
        history[#history + 1] = { t = now, poses = snap }
        while history[1] and now - history[1].t > 2 do table.remove(history, 1) end   -- keep ~2s of samples
    end))
    -- render the clone from the snapshot (ping + 0.11) seconds ago = the server's pose+pos NOW
    track(RunService.RenderStepped:Connect(function()
        if not (cfg.on and clone) or #history == 0 then return end
        local ping = 0; pcall(function() ping = LocalPlayer:GetNetworkPing() end)   -- seconds
        local targetT = os.clock() - (ping + EXTRA_DELAY)
        local sample = history[1]
        for i = #history, 1, -1 do            -- newest sample at or before targetT
            if history[i].t <= targetT then sample = history[i]; break end
        end
        if not sample then return end
        for cp, rp in pairs(partMap) do       -- body parts + accessory handles
            local cf = sample.poses[rp]
            if cf and cp.Parent then cp.CFrame = cf end
        end
    end))
    track(LocalPlayer.CharacterAdded:Connect(function()
        if cfg.on then task.wait(0.6); buildClone() end
    end))

    local Sec = SP:Section({ Name = "Server position clone", Side = 1 })
    Sec:Toggle({ Name = "Enabled", Flag = "SrvPosOn", Default = false,
        Callback = function(v) cfg.on = v; if v then buildClone() else clearClone() end end })
    Sec:Slider({ Name = "Transparency", Flag = "SrvPosTrans", Min = 0, Max = 1, Default = 0.5, Decimals = 2,
        Callback = function(v) cfg.transparency = v; applyStyle() end })
    Sec:Dropdown({ Name = "Material", Flag = "SrvPosMat", Default = "ForceField", Multi = false, Items = MATERIALS,
        Callback = function(v) cfg.material = (type(v) == "table" and v[1]) or v or "ForceField"; applyStyle() end })
    Sec:Label({ Name = "Color" }):Colorpicker({ Flag = "SrvPosColor", Default = cfg.color,
        Callback = function(c) cfg.color = c; applyStyle() end })

    local Sec2 = SP:Section({ Name = "Outline", Side = 2 })
    Sec2:Toggle({ Name = "Outline", Flag = "SrvPosOutline", Default = false,
        Callback = function(v) cfg.outline = v; applyStyle() end })
    Sec2:Label({ Name = "Outline color" }):Colorpicker({ Flag = "SrvPosOutlineColor", Default = cfg.outlineColor,
        Callback = function(c) cfg.outlineColor = c; applyStyle() end })
end

-- EspSub pre-declared above (tab order)
do
    local Sec = EspSub:Section({ Name = "Player ESP", Side = 1 })
    if not hasDrawing then
        Sec:Label({ Name = "ESP needs a Drawing-capable executor." })
    end
    local EspToggle = Sec:Toggle({ Name = "Enabled", Flag = "EspEnabled", Default = false,
        Callback = function(v) Esp.enabled = v end })
    Sec:Label({ Name = "Toggle key" }):Keybind({ Name = "ESP", Flag = "EspKey", Mode = "Toggle",
        Callback = function(state) EspToggle:Set(state and true or false) end })
    Sec:Toggle({ Name = "Box", Flag = "EspBox", Default = true,
        Callback = function(v) Esp.box = v end })
    Sec:Dropdown({ Name = "Box style", Flag = "EspBoxType", Default = "Full", Multi = false,
        Items = { "Full", "Corner", "Solid" },
        Callback = function(v) Esp.boxType = (type(v) == "table" and v[1]) or v or "Full" end })
    Sec:Toggle({ Name = "Names", Flag = "EspNames", Default = false,
        Callback = function(v) Esp.names = v end })
    Sec:Toggle({ Name = "Distance", Flag = "EspDistance", Default = false,
        Callback = function(v) Esp.distance = v end })
    Sec:Toggle({ Name = "Health bar", Flag = "EspHealth", Default = false,
        Callback = function(v) Esp.health = v end })
    Sec:Toggle({ Name = "Tracer", Flag = "EspTracer", Default = false,
        Callback = function(v) Esp.tracer = v end })
    Sec:Toggle({ Name = "Skeleton", Flag = "EspSkeleton", Default = false,
        Callback = function(v) Esp.skeleton = v end })
    Sec:Toggle({ Name = "Chams", Flag = "EspChams", Default = false,
        Callback = function(v) Esp.chams = v end })

    local Sec2 = EspSub:Section({ Name = "Options", Side = 2 })
    Sec2:Toggle({ Name = "Team check", Flag = "EspTeam", Default = false,
        Callback = function(v) Esp.teamCheck = v end })
    Sec2:Dropdown({ Name = "Tracer origin", Flag = "EspTracerOrigin", Default = "Bottom", Multi = false,
        Items = { "Bottom", "Top", "Mouse" },
        Callback = function(v) Esp.tracerOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    Sec2:Label({ Name = "ESP color" }):Colorpicker({
        Flag = "EspColor", Default = Color3.fromRGB(200, 183, 247),
        Callback = function(c) Esp.color = c end })
    Sec2:Slider({ Name = "Solid box opacity", Flag = "EspFillOp",
        Min = 0, Max = 100, Default = 40, Decimals = 0, Suffix = "%",
        Callback = function(v) Esp.fillOpacity = v / 100 end })
    Sec2:Label({ Name = "Chams fill" }):Colorpicker({
        Flag = "EspChamsFill", Default = Color3.fromRGB(200, 183, 247),
        Callback = function(c) Esp.chamsFill = c end })
    Sec2:Label({ Name = "Chams outline" }):Colorpicker({
        Flag = "EspChamsOutline", Default = Color3.fromRGB(255, 255, 255),
        Callback = function(c) Esp.chamsOutline = c end })
    Sec2:Slider({ Name = "Chams opacity", Flag = "EspChamsOp",
        Min = 0, Max = 100, Default = 40, Decimals = 0, Suffix = "%",
        Callback = function(v) Esp.chamsTransparency = 1 - (v / 100) end })
end

-- ============================================================
--  WORLD  (Visuals > World): edit Lighting, optionally lock it so the game
--  can't change it back, and real 3D weather (rain / snow) that follows you.
-- ============================================================
local World = {}
do
    local Lighting = game:GetService("Lighting")
    -- every Lighting prop we manage. We snapshot them so "Lock" can enforce the
    -- whole set, and so we can restore them on unload.
    local MANAGED = { "Brightness", "ClockTime", "ExposureCompensation",
        "FogStart", "FogEnd", "FogColor", "Ambient", "OutdoorAmbient",
        "ColorShift_Top", "ColorShift_Bottom", "GlobalShadows" }
    local desired, original = {}, {}
    for _, prop in ipairs(MANAGED) do
        local ok, v = pcall(function() return Lighting[prop] end)
        if ok then desired[prop] = v; original[prop] = v end
    end

    local locked = false
    local function setProp(prop, value)
        desired[prop] = value
        pcall(function() Lighting[prop] = value end)
    end

    -- when locked, force our values back every frame so day/night scripts etc.
    -- can never change them
    track(RunService.RenderStepped:Connect(function()
        if not locked then return end
        for prop, value in pairs(desired) do
            pcall(function() Lighting[prop] = value end)
        end
    end))

    -- gate every control: the lib fires each callback once on load with its
    -- default. Without this guard that would create Atmosphere/Sky/Clouds and
    -- shove the world to the defaults on every game. Nothing applies until the
    -- user actually touches a control.
    local ready = false
    local function gated(fn) return function(...) if ready then fn(...) end end end

    -- Atmosphere / Sky / Clouds are made lazily on first use; we destroy only the
    -- ones WE created (pre-existing ones are left alone on unload).
    local Terrain = Workspace:FindFirstChildOfClass("Terrain")
    local mine = {}
    local function getAtmo()
        local a = Lighting:FindFirstChildOfClass("Atmosphere")
        if not a then a = Instance.new("Atmosphere"); a.Parent = Lighting; mine.atmo = a end
        return a
    end
    local function getSky()
        local s = Lighting:FindFirstChildOfClass("Sky")
        if not s then s = Instance.new("Sky"); s.Parent = Lighting; mine.sky = s end
        return s
    end
    local function getClouds()
        if not Terrain then return nil end
        local c = Terrain:FindFirstChildOfClass("Clouds")
        if not c then c = Instance.new("Clouds"); c.Parent = Terrain; mine.clouds = c end
        return c
    end

    -- ---- 3D weather: a big invisible part above the camera emitting particles
    local weather = { rain = false, snow = false, rainRate = 600, snowRate = 170,
        part = nil, rainE = nil, snowE = nil }
    local function ensureWeather()
        if weather.part and weather.part.Parent then return end
        local p = Instance.new("Part")
        p.Name = "\0"; p.Anchored = true; p.CanCollide = false
        p.CanQuery = false; p.CanTouch = false; p.Transparency = 1
        p.Size = Vector3.new(140, 1, 140); p.Parent = Workspace

        local rainE = Instance.new("ParticleEmitter")
        rainE.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))  -- white
        rainE.Transparency = NumberSequence.new(0.15)                   -- more visible
        rainE.Size = NumberSequence.new(0.3)
        rainE.Lifetime = NumberRange.new(0.5, 0.75)
        rainE.Speed = NumberRange.new(105, 125)
        rainE.SpreadAngle = Vector2.new(4, 4)
        rainE.Acceleration = Vector3.new(0, -55, 0)
        rainE.Squash = NumberSequence.new(2)        -- short streaks
        rainE.EmissionDirection = Enum.NormalId.Bottom
        rainE.LightEmission = 0.4
        rainE.Enabled = false
        rainE.Parent = p

        local snowE = Instance.new("ParticleEmitter")
        snowE.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
        snowE.Transparency = NumberSequence.new(0.1)
        snowE.Size = NumberSequence.new(0.35)
        snowE.Lifetime = NumberRange.new(6, 9)        -- long enough to reach the ground
        snowE.Speed = NumberRange.new(10, 16)
        snowE.SpreadAngle = Vector2.new(25, 25)
        snowE.Acceleration = Vector3.new(0, -5, 0)
        snowE.Rotation = NumberRange.new(0, 360)
        snowE.RotSpeed = NumberRange.new(-40, 40)
        snowE.Drag = 0                                -- 0 so it falls all the way down
        snowE.LightEmission = 0.2
        snowE.EmissionDirection = Enum.NormalId.Bottom
        snowE.Enabled = false
        snowE.Parent = p

        weather.part, weather.rainE, weather.snowE = p, rainE, snowE
    end
    track(RunService.RenderStepped:Connect(function()
        if weather.rain or weather.snow then
            ensureWeather()
            local cam = Workspace.CurrentCamera
            if cam then
                local pos = cam.CFrame.Position
                weather.part.CFrame = CFrame.new(pos.X, pos.Y + 35, pos.Z)
            end
            weather.rainE.Rate = weather.rainRate
            weather.snowE.Rate = weather.snowRate
            weather.rainE.Enabled = weather.rain
            weather.snowE.Enabled = weather.snow
        elseif weather.part then
            weather.rainE.Enabled = false
            weather.snowE.Enabled = false
        end
    end))

    function World.cleanup()
        locked = false
        if weather.part then pcall(function() weather.part:Destroy() end); weather.part = nil end
        for prop, value in pairs(original) do pcall(function() Lighting[prop] = value end) end
        for _, inst in pairs(mine) do pcall(function() inst:Destroy() end) end
    end

    -- ---- UI ----
    -- WorldSub pre-declared above (tab order)

    local LSec = WorldSub:Section({ Name = "Lighting", Side = 1 })
    LSec:Slider({ Name = "Time of day", Flag = "WorldTime", Min = 0, Max = 24,
        Default = math.clamp(math.floor(desired.ClockTime or 14), 0, 24), Decimals = 0,
        Callback = gated(function(v) setProp("ClockTime", v) end) })
    LSec:Slider({ Name = "Brightness", Flag = "WorldBrightness", Min = 0, Max = 10,
        Default = math.clamp(desired.Brightness or 2, 0, 10), Decimals = 1,
        Callback = gated(function(v) setProp("Brightness", v) end) })
    LSec:Slider({ Name = "Exposure", Flag = "WorldExposure", Min = -3, Max = 3,
        Default = math.clamp(desired.ExposureCompensation or 0, -3, 3), Decimals = 1,
        Callback = gated(function(v) setProp("ExposureCompensation", v) end) })
    LSec:Slider({ Name = "Fog start", Flag = "WorldFogStart", Min = 0, Max = 5000,
        Default = math.clamp(desired.FogStart or 0, 0, 5000), Decimals = 0,
        Callback = gated(function(v) setProp("FogStart", v) end) })
    LSec:Slider({ Name = "Fog end", Flag = "WorldFogEnd", Min = 0, Max = 10000,
        Default = math.clamp(desired.FogEnd or 10000, 0, 10000), Decimals = 0,
        Callback = gated(function(v) setProp("FogEnd", v) end) })
    LSec:Label({ Name = "Fog color" }):Colorpicker({ Flag = "WorldFogColor",
        Default = desired.FogColor or Color3.fromRGB(191, 191, 191),
        Callback = gated(function(c) setProp("FogColor", c) end) })
    LSec:Label({ Name = "Ambient" }):Colorpicker({ Flag = "WorldAmbient",
        Default = desired.Ambient or Color3.fromRGB(0, 0, 0),
        Callback = gated(function(c) setProp("Ambient", c) end) })
    LSec:Label({ Name = "Outdoor ambient" }):Colorpicker({ Flag = "WorldOutdoor",
        Default = desired.OutdoorAmbient or Color3.fromRGB(128, 128, 128),
        Callback = gated(function(c) setProp("OutdoorAmbient", c) end) })
    LSec:Label({ Name = "Color shift top" }):Colorpicker({ Flag = "WorldShiftTop",
        Default = desired.ColorShift_Top or Color3.fromRGB(0, 0, 0),
        Callback = gated(function(c) setProp("ColorShift_Top", c) end) })
    LSec:Label({ Name = "Color shift bottom" }):Colorpicker({ Flag = "WorldShiftBottom",
        Default = desired.ColorShift_Bottom or Color3.fromRGB(0, 0, 0),
        Callback = gated(function(c) setProp("ColorShift_Bottom", c) end) })

    local ASec = WorldSub:Section({ Name = "Atmosphere", Side = 1 })
    ASec:Slider({ Name = "Density", Flag = "WorldAtmoDensity", Min = 0, Max = 1, Default = 0.3, Decimals = 2,
        Callback = gated(function(v) getAtmo().Density = v end) })
    ASec:Slider({ Name = "Haze", Flag = "WorldAtmoHaze", Min = 0, Max = 10, Default = 0, Decimals = 1,
        Callback = gated(function(v) getAtmo().Haze = v end) })
    ASec:Slider({ Name = "Glare", Flag = "WorldAtmoGlare", Min = 0, Max = 10, Default = 0, Decimals = 1,
        Callback = gated(function(v) getAtmo().Glare = v end) })
    ASec:Label({ Name = "Color" }):Colorpicker({ Flag = "WorldAtmoColor", Default = Color3.fromRGB(199, 170, 107),
        Callback = gated(function(c) getAtmo().Color = c end) })
    ASec:Label({ Name = "Decay" }):Colorpicker({ Flag = "WorldAtmoDecay", Default = Color3.fromRGB(106, 112, 125),
        Callback = gated(function(c) getAtmo().Decay = c end) })

    local WSec = WorldSub:Section({ Name = "Weather & options", Side = 2 })
    WSec:Toggle({ Name = "Full bright", Flag = "WorldFullbright", Default = false,
        Callback = gated(function(v)
            if v then
                setProp("Ambient", Color3.fromRGB(255, 255, 255))
                setProp("OutdoorAmbient", Color3.fromRGB(255, 255, 255))
                setProp("GlobalShadows", false)
            else
                setProp("Ambient", original.Ambient or Color3.fromRGB(0, 0, 0))
                setProp("OutdoorAmbient", original.OutdoorAmbient or Color3.fromRGB(128, 128, 128))
                setProp("GlobalShadows", original.GlobalShadows ~= false)
            end
        end) })
    WSec:Toggle({ Name = "Lock world settings", Flag = "WorldLock", Default = false,
        Callback = gated(function(v) locked = v end) })
    WSec:Toggle({ Name = "Rain", Flag = "WorldRain", Default = false,
        Callback = gated(function(v) weather.rain = v end) })
    WSec:Slider({ Name = "Rain intensity", Flag = "WorldRainRate", Min = 50, Max = 3000, Default = 600, Decimals = 0,
        Callback = gated(function(v) weather.rainRate = v end) })
    WSec:Toggle({ Name = "Snow", Flag = "WorldSnow", Default = false,
        Callback = gated(function(v) weather.snow = v end) })
    WSec:Slider({ Name = "Snow intensity", Flag = "WorldSnowRate", Min = 20, Max = 1500, Default = 170, Decimals = 0,
        Callback = gated(function(v) weather.snowRate = v end) })

    local SSec = WorldSub:Section({ Name = "Sky & clouds", Side = 2 })
    SSec:Slider({ Name = "Star count", Flag = "WorldStars", Min = 0, Max = 3000, Default = 3000, Decimals = 0,
        Callback = gated(function(v) getSky().StarCount = v end) })
    SSec:Slider({ Name = "Sun size", Flag = "WorldSunSize", Min = 0, Max = 50, Default = 21, Decimals = 0,
        Callback = gated(function(v) getSky().SunAngularSize = v end) })
    SSec:Slider({ Name = "Moon size", Flag = "WorldMoonSize", Min = 0, Max = 50, Default = 11, Decimals = 0,
        Callback = gated(function(v) getSky().MoonAngularSize = v end) })
    SSec:Toggle({ Name = "Sun / moon / stars", Flag = "WorldCelestial", Default = true,
        Callback = gated(function(v) getSky().CelestialBodiesShown = v end) })
    SSec:Toggle({ Name = "Clouds", Flag = "WorldClouds", Default = false,
        Callback = gated(function(v) local c = getClouds(); if c then c.Enabled = v end end) })
    SSec:Slider({ Name = "Cloud cover", Flag = "WorldCloudCover", Min = 0, Max = 1, Default = 0.5, Decimals = 2,
        Callback = gated(function(v) local c = getClouds(); if c then c.Cover = v end end) })
    SSec:Slider({ Name = "Cloud density", Flag = "WorldCloudDensity", Min = 0, Max = 1, Default = 0.5, Decimals = 2,
        Callback = gated(function(v) local c = getClouds(); if c then c.Density = v end end) })
    SSec:Label({ Name = "Cloud color" }):Colorpicker({ Flag = "WorldCloudColor", Default = Color3.fromRGB(255, 255, 255),
        Callback = gated(function(c) local cl = getClouds(); if cl then cl.Color = c end end) })

    ready = true   -- setup done; controls now take effect on user interaction
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
    pcall(function() if World.cleanup then World.cleanup() end end)
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
