-- ============================================================
--  games/5315046213.lua  --  Strafe / bhop game (Source-style air physics)
--
--  Decoded live (2026-07-11) incl. the on-screen gauge (video). The strafe GAUGE
--  needle = (your yaw rate / tickrate) / atan2(mv, speed)  [from the "Gauges"
--  module]. white = 1 (optimal), red >1 (too fast), blue <1 (too slow). So:
--    optimal_yaw_rate(rad/s) = atan2(mv, speed) * tickrate      -- shrinks as you speed up
--  CRITICAL: `speed` is the game's real horizontal speed (its "u/s" readout, ~8-29
--  in the clip) = the WORLD speed from HRP position deltas -- NOT the memory-scanned
--  "Simulation.Velocity" (that read ~106, a decoy; using it made v6 slow you down).
--  Style Autohop: mv=2.7, tickrate=100.
--
--  Strafe ASSIST v7: you steer; while Space is held + airborne it reads your real
--  turn + your smoothed world speed, and boosts/slows your mouse so your turn rate
--  matches the optimal -> holds the needle white. No memory scanning.
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

local PX_PER_DEG = 6.6

local S = {
    bhop = false,
    assist = false,
    strength = 0.7,
    maxAngle = 30,      -- cap deg/frame the assist adds/removes
    minSpeed = 6,       -- min world speed (u/s) to activate
    autoKey = true,
    mouseSign = 1,
    mv = 2.7, tickrate = 100,
    _spd = 0,           -- live smoothed speed (readback)
}
do local g = getgenv and getgenv(); if g then g.WH = g.WH or {}; g.WH.strafe = S end end

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
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
local function camYaw()
    local lv = Workspace.CurrentCamera.CFrame.LookVector
    return math.atan2(lv.X, lv.Z)
end

-- world speed is spiky (anchored HRP CFrame updates at the 100Hz tick, not per
-- render frame), so heavily smooth it to match the game's steady u/s readout.
local lastPos, speedEMA, lastYaw, _lastInjPx = nil, 0, camYaw(), 0

track(RunService.RenderStepped:Connect(function(dt)
    local hrp = myHRP()
    if not hrp then lastPos = nil; releaseStrafe(); _lastInjPx = 0; return end
    local pos = hrp.Position
    if lastPos then
        local inst = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z).Magnitude / math.max(dt, 1 / 240)
        speedEMA = speedEMA * 0.88 + inst * 0.12
    end
    lastPos = pos
    S._spd = math.floor(speedEMA)
    local onGround = grounded(pos)

    if S.bhop and onGround then tapJump() end

    if not S.assist or onGround or not UIS:IsKeyDown(Enum.KeyCode.Space) or speedEMA < S.minSpeed then
        if S.autoKey then releaseStrafe() end
        lastYaw = camYaw(); _lastInjPx = 0
        return
    end

    -- your real turn this frame (camera yaw delta minus what our injection caused)
    local yaw = camYaw()
    local rawDeg = math.deg(math.atan2(math.sin(yaw - lastYaw), math.cos(yaw - lastYaw)))
    lastYaw = yaw
    local playerDeg = rawDeg - (_lastInjPx / PX_PER_DEG)

    if math.abs(playerDeg) < 0.05 then
        if S.autoKey then releaseStrafe() end
        _lastInjPx = 0
        return
    end

    if S.autoKey then holdStrafe((playerDeg * S.mouseSign) > 0 and Enum.KeyCode.D or Enum.KeyCode.A) end

    -- optimal turn this frame, in YOUR direction
    local optimalDeg = math.deg(math.atan2(S.mv, speedEMA) * S.tickrate) * dt * (playerDeg > 0 and 1 or -1)
    local injectDeg = math.clamp((optimalDeg - playerDeg) * S.strength, -S.maxAngle, S.maxAngle)

    local injectPx = injectDeg * PX_PER_DEG
    pcall(function() mousemoverel(injectPx, 0) end)
    _lastInjPx = injectPx
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
    Sec:Label({ Name = "keeps the strafe needle in the white" })

    local Sec2 = Sub:Section({ Name = "Tuning", Side = 2 })
    Sec2:Slider({ Name = "Strength", Flag = "ST_Strength", Min = 0, Max = 100, Default = 70, Decimals = 0, Suffix = " %",
        Callback = function(v) S.strength = v / 100 end })
    Sec2:Slider({ Name = "Max angle / frame", Flag = "ST_MaxAngle", Min = 1, Max = 80, Default = 30, Decimals = 0, Suffix = " deg",
        Callback = function(v) S.maxAngle = v end })
    Sec2:Slider({ Name = "mv (style const)", Flag = "ST_MV", Min = 1, Max = 60, Default = 27, Decimals = 0,
        Callback = function(v) S.mv = v / 10 end })
    Sec2:Slider({ Name = "Min speed", Flag = "ST_MinSpeed", Min = 0, Max = 40, Default = 6, Decimals = 0,
        Callback = function(v) S.minSpeed = v end })
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
