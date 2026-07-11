-- ============================================================
--  games/5315046213.lua  --  Strafe / bhop game (Source-style air physics)
--
--  Decoded live (2026-07-11): custom CFrame movement, Source AirAccelerate,
--  ~100Hz tick, WASD + Space. Velocity object obfuscated -> velocity DIRECTION
--  from HRP position deltas.
--
--  Strafe ASSIST (v5): you steer, it just makes your turn faster/slower while
--  strafing (hold Space). It's a proportional multiplier on YOUR real mouse
--  movement, so the output always tracks your mouse exactly -- just boosted.
--
--  KEY FIX: GetMouseDelta re-reads our injected mousemoverel at 0.4x scale
--  (inject 40 -> reads 16). Earlier versions subtracted the raw px and corrupted
--  the "your movement" signal (drift/glitch/freeze). We now subtract in the
--  correct GetMouseDelta units, so your real turn is measured accurately.
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local VIM        = game:GetService("VirtualInputManager")
local Workspace  = workspace
local LocalPlayer = Players.LocalPlayer

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local GMD_SCALE = 0.4   -- GetMouseDelta units per mousemoverel px (measured live)

local S = {
    bhop = false,
    assist = false,
    boost = 0.4,        -- +40% turn speed while strafing (negative = slow you down)
    smartBoost = true,  -- only boost when you turn the optimal strafe way; gently slow otherwise
    slow = 0.3,         -- how much to slow when turning the "wrong" way (smartBoost)
    minSpeed = 8,
    deadzone = 2,       -- min real mouse px/frame before assisting (you must be turning)
    autoKey = true,     -- auto-hold A/D matching your turn direction
    mouseSign = 1,      -- calibration for smartBoost/autoKey direction only
}
do local g = getgenv and getgenv(); if g then g.WH = g.WH or {}; g.WH.strafe = S end end

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function signedYaw(a, b)
    local cross = a.X * b.Z - a.Z * b.X
    local dot = math.clamp(a.X * b.X + a.Z * b.Z, -1, 1)
    return math.atan2(cross, dot)
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function grounded(pos)
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    return Workspace:Raycast(pos, Vector3.new(0, -5, 0), rayParams) ~= nil
end

local heldKey = nil
local function holdStrafe(keyCode)
    if heldKey == keyCode then return end
    if heldKey then pcall(function() VIM:SendKeyEvent(false, heldKey, false, game) end) end
    heldKey = keyCode
    if keyCode then pcall(function() VIM:SendKeyEvent(true, keyCode, false, game) end) end
end
local function releaseStrafe() holdStrafe(nil) end
local _lastJump = 0
local function tapJump()
    if os.clock() - _lastJump < 0.04 then return end
    _lastJump = os.clock()
    pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game) end)
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
end

local lastPos, velSmooth, _lastInjGMD = nil, nil, 0

track(RunService.RenderStepped:Connect(function(dt)
    local hrp = myHRP()
    if not hrp then lastPos = nil; releaseStrafe(); _lastInjGMD = 0; return end
    local pos = hrp.Position
    if not lastPos then lastPos = pos; return end
    local delta = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z)
    local speed = delta.Magnitude / math.max(dt, 1 / 240)
    lastPos = pos
    local onGround = grounded(pos)

    if S.bhop and onGround then tapJump() end

    if not S.assist or onGround or speed < S.minSpeed
        or not UIS:IsKeyDown(Enum.KeyCode.Space) then
        if S.autoKey then releaseStrafe() end
        _lastInjGMD = 0
        return
    end

    -- your REAL mouse turn this frame, measured accurately (subtract injection in
    -- GetMouseDelta units, then convert to mousemoverel px)
    local playerPx = (UIS:GetMouseDelta().X - _lastInjGMD) / GMD_SCALE
    if math.abs(playerPx) < S.deadzone then
        if S.autoKey then releaseStrafe() end
        _lastInjGMD = 0
        return
    end

    if S.autoKey then holdStrafe((playerPx * S.mouseSign) > 0 and Enum.KeyCode.D or Enum.KeyCode.A) end

    local factor = 1 + S.boost
    if S.smartBoost and delta.Magnitude > 1e-4 then
        local velDir = delta.Unit
        velSmooth = velSmooth and (velSmooth * 0.6 + velDir * 0.4).Unit or velDir
        local lv = Workspace.CurrentCamera.CFrame.LookVector
        local look = Vector3.new(lv.X, 0, lv.Z)
        if look.Magnitude > 1e-3 then
            look = look.Unit
            local errDeg = math.deg(signedYaw(look, velSmooth))       -- +: velocity right of look
            local turnRight = (playerPx * S.mouseSign) > 0
            local good = (turnRight and errDeg > 0) or ((not turnRight) and errDeg < 0)
            if not good then factor = 1 - S.slow end
        end
    end

    -- boost is proportional to YOUR real movement -> output tracks your mouse exactly
    local injectPx = playerPx * (factor - 1)
    pcall(function() mousemoverel(injectPx, 0) end)
    _lastInjGMD = injectPx * GMD_SCALE
end))

-- ============================================================
--  UI
-- ============================================================
do
    local Page = Window:Page({ Name = "Strafe" })
    local Sub  = Page:SubPage({ Name = "Optimizer" })

    local Sec = Sub:Section({ Name = "Strafe assist", Side = 1 })
    Sec:Toggle({ Name = "Strafe assist (hold Space)", Flag = "ST_Assist", Default = false,
        Callback = function(v) S.assist = v; if not v then releaseStrafe() end end })
    Sec:Toggle({ Name = "Auto strafe key (A/D)", Flag = "ST_AutoKey", Default = true,
        Callback = function(v) S.autoKey = v end })
    Sec:Toggle({ Name = "Auto Bhop", Flag = "ST_Bhop", Default = false,
        Callback = function(v) S.bhop = v end })
    Sec:Slider({ Name = "Min speed", Flag = "ST_MinSpeed", Min = 0, Max = 60, Default = 8, Decimals = 0,
        Callback = function(v) S.minSpeed = v end })
    Sec:Label({ Name = "amplifies your own mouse turn while strafing" })

    local Sec2 = Sub:Section({ Name = "Tuning", Side = 2 })
    Sec2:Slider({ Name = "Boost", Flag = "ST_Boost", Min = -50, Max = 150, Default = 40, Decimals = 0, Suffix = " %",
        Callback = function(v) S.boost = v / 100 end })
    Sec2:Toggle({ Name = "Smart boost (only optimal way)", Flag = "ST_Smart", Default = true,
        Callback = function(v) S.smartBoost = v end })
    Sec2:Slider({ Name = "Wrong-way slow", Flag = "ST_Slow", Min = 0, Max = 80, Default = 30, Decimals = 0, Suffix = " %",
        Callback = function(v) S.slow = v / 100 end })
    Sec2:Slider({ Name = "Deadzone", Flag = "ST_Deadzone", Min = 0, Max = 15, Default = 2, Decimals = 0, Suffix = " px",
        Callback = function(v) S.deadzone = v end })
    Sec2:Toggle({ Name = "Flip mouse read", Flag = "ST_MouseSign", Default = false,
        Callback = function(v) S.mouseSign = v and -1 or 1 end })
end

pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    S.bhop, S.assist = false, false
    pcall(releaseStrafe)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
end
do
    local g = (getgenv and getgenv()) or nil
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full() pcall(cleanup); if prev then pcall(prev) end end
        g.WH.disableAll = full
        Library.OnExit = full
    else
        Library.OnExit = cleanup
    end
end
