-- ============================================================
--  games/universal.lua  --  the base "main" UI every game gets
--
--  Builds the shared pages on the Window passed in via ctx:
--    Combat  -- subpages (Aimbot / Triggerbot / ESP); per-game modules fill
--               these with real features later.
--    Player  -- working universal movement (walkspeed, jump, cframe, fly,
--               noclip, infinite jump).
--
--  The Settings page (config + themes) is added by the loader after this
--  module runs, so every game gets it automatically.
--
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

-- ============================================================
--  MOVEMENT BACKEND
--  Each feature enforces its state every frame, so it survives respawns
--  and games that try to reset the value. All guarded with pcall.
-- ============================================================
local Movement = {}

-- WalkSpeed: real Humanoid.WalkSpeed override with anti-restore.
do
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
        if on then
            conn = RunService.Heartbeat:Connect(enforce)
        else
            local hum = getHum()
            if hum then pcall(function() hum.WalkSpeed = 16 end) end
        end
    end
end

-- JumpPower / JumpHeight: handles both Humanoid jump models.
do
    local active, value, conn = false, 50, nil
    local function enforce()
        if not active then return end
        local hum = getHum(); if not hum then return end
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
        pcall(function()
            if hum.UseJumpPower then
                if hum.JumpPower ~= value then hum.JumpPower = value end
            else
                local h = value / 7   -- power 50 ~= height 7.2
                if math.abs(hum.JumpHeight - h) > 0.05 then hum.JumpHeight = h end
            end
        end)
    end
    function Movement.setJumpValue(v) value = v; enforce() end
    function Movement.setJump(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then
            conn = RunService.Heartbeat:Connect(enforce)
        else
            local hum = getHum()
            if hum then pcall(function()
                if hum.UseJumpPower then hum.JumpPower = 50 else hum.JumpHeight = 7.2 end
            end) end
        end
    end
end

-- CFrame speed: camera-WASD-driven horizontal CFrame nudge (a "speed hack").
do
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
                if dir.Magnitude > 0 then
                    hrp.CFrame = hrp.CFrame + dir.Unit * (16 * (mult - 1)) * dt
                end
            end)
        end
    end
end

-- Fly: camera-relative, velocity-zeroed CFrame fly. Space/Shift = up/down.
do
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

-- Noclip: keep the collision parts non-colliding every render frame.
do
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
                    local p = c:FindFirstChild(name)
                    if p then p.CanCollide = false end
                end
            end)
        else
            local c = getChar()
            if c then
                for _, name in ipairs(PARTS) do
                    local p = c:FindFirstChild(name)
                    if p and p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
                end
            end
        end
    end
end

-- Infinite jump: re-trigger a jump on every jump request.
do
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
--  COMBAT  (scaffold -- per-game modules fill these subpages)
-- ============================================================
Window:Category("Main")

local CombatPage = Window:Page({ Name = "Combat" })
do
    local Aimbot = CombatPage:SubPage({ Name = "Aimbot" })
    Aimbot:Section({ Name = "Aimbot", Side = 1 })
        :Label({ Name = "Aimbot features are added per game." })

    local Trigger = CombatPage:SubPage({ Name = "Triggerbot" })
    Trigger:Section({ Name = "Triggerbot", Side = 1 })
        :Label({ Name = "Triggerbot features are added per game." })

    local Esp = CombatPage:SubPage({ Name = "ESP" })
    Esp:Section({ Name = "ESP", Side = 1 })
        :Label({ Name = "ESP features are added per game." })
end

-- ============================================================
--  PLAYER  (working universal movement)
-- ============================================================
local PlayerPage = Window:Page({ Name = "Player" })
local Move = PlayerPage:SubPage({ Name = "Movement" })

local SpeedSec = Move:Section({ Name = "Speed", Side = 1 })
SpeedSec:Toggle({
    Name = "WalkSpeed", Flag = "WalkSpeedEnabled", Default = false,
    Callback = function(v) Movement.setWalkSpeed(v) end,
})
SpeedSec:Slider({
    Name = "WalkSpeed amount", Flag = "WalkSpeedValue",
    Min = 16, Max = 500, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setWalkSpeedValue(v) end,
})
SpeedSec:Toggle({
    Name = "CFrame speed", Flag = "CFrameEnabled", Default = false,
    Callback = function(v) Movement.setCFrame(v) end,
})
SpeedSec:Slider({
    Name = "CFrame multiplier", Flag = "CFrameValue",
    Min = 1, Max = 10, Default = 2, Decimals = 1, Suffix = "x",
    Callback = function(v) Movement.setCFrameValue(v) end,
})

local JumpSec = Move:Section({ Name = "Jump", Side = 1 })
JumpSec:Toggle({
    Name = "JumpPower", Flag = "JumpEnabled", Default = false,
    Callback = function(v) Movement.setJump(v) end,
})
JumpSec:Slider({
    Name = "JumpPower amount", Flag = "JumpValue",
    Min = 50, Max = 500, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setJumpValue(v) end,
})
JumpSec:Toggle({
    Name = "Infinite jump", Flag = "InfJumpEnabled", Default = false,
    Callback = function(v) Movement.setInfJump(v) end,
})

local FlySec = Move:Section({ Name = "Fly", Side = 2 })
local FlyToggle = FlySec:Toggle({
    Name = "Fly", Flag = "FlyEnabled", Default = false,
    Callback = function(v) Movement.setFly(v) end,
})
FlySec:Slider({
    Name = "Fly speed", Flag = "FlyValue",
    Min = 10, Max = 300, Default = 60, Decimals = 0,
    Callback = function(v) Movement.setFlyValue(v) end,
})
FlySec:Label({ Name = "Fly toggle key" }):Keybind({
    Flag = "FlyKey", Mode = "Toggle", Default = Enum.KeyCode.F,
    Callback = function(state) FlyToggle:Set(state and true or false) end,
})

local UtilSec = Move:Section({ Name = "Utility", Side = 2 })
UtilSec:Toggle({
    Name = "Noclip", Flag = "NoclipEnabled", Default = false,
    Callback = function(v) Movement.setNoclip(v) end,
})
