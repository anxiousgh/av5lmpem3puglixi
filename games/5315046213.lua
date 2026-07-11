-- ============================================================
--  games/5315046213.lua  --  Strafe / bhop game (Source-style air physics)
--
--  Decoded live (2026-07-11). The game has a built-in strafe GAUGE; its needle =
--    (your yaw rate / tickrate) / atan2(mv, speed)
--  (from the "Gauges" module). needle 1 = white (optimal), >1 red (too fast),
--  <1 blue (too slow). So the OPTIMAL mouse turn rate is:
--    optimal_yaw_rate(rad/s) = atan2(mv, speed) * tickrate      -- SHRINKS as you speed up
--  where `speed` is the INTERNAL velocity (read from the movement Simulation
--  object; world speed from position deltas is aliased garbage) and mv/tickrate
--  come from the current style (Autohop: mv=2.7, tickrate=100). Verified against a
--  live run (at internal speed 40, optimal ~386 deg/s matched a perfect-white frame).
--
--  Strafe ASSIST v6 (closed loop on the game's own math): you steer; while Space is
--  held and airborne it reads your live internal speed + your turn, and boosts/slows
--  your mouse so your turn rate tracks the optimal (holds the needle white).
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

local PX_PER_DEG = 6.6   -- mousemoverel(120) -> ~18 deg camera turn

local S = {
    bhop = false,
    assist = false,
    strength = 0.8,     -- 0 = all you, 1 = force optimal
    maxAngle = 25,      -- cap deg/frame the assist may add/remove
    minSpeed = 6,       -- min INTERNAL speed to activate
    autoKey = true,     -- auto-hold A/D matching your turn direction
    mouseSign = 1,      -- calibration for autoKey / turn direction
    mv = 2.7, tickrate = 100,   -- style fallbacks if the Simulation isn't readable
}
do local g = getgenv and getgenv(); if g then g.WH = g.WH or {}; g.WH.strafe = S end end

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ---- find the live movement Simulation (obfuscated; pick the one that's moving) ----
local simCandidates = {}
local function scanSims()
    simCandidates = {}
    pcall(function()
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" and typeof(rawget(v, "Velocity")) == "Vector3"
                and rawget(v, "GameMechanics") ~= nil then
                simCandidates[#simCandidates + 1] = v
            end
        end
    end)
end
local function liveSim()
    local best, bestV = nil, 0.5
    for _, s in ipairs(simCandidates) do
        local ok, v = pcall(function() local vv = s.Velocity; return math.sqrt(vv.X * vv.X + vv.Z * vv.Z) end)
        if ok and v > bestV then bestV = v; best = s end
    end
    return best, bestV
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

scanSims()
local lastYaw, _lastInjPx, _rescanT = camYaw(), 0, 0

track(RunService.RenderStepped:Connect(function(dt)
    local hrp = myHRP()
    local onGround = hrp and grounded(hrp.Position)
    if S.bhop and hrp and onGround then tapJump() end

    if not S.assist or not hrp or onGround or not UIS:IsKeyDown(Enum.KeyCode.Space) then
        if S.autoKey then releaseStrafe() end
        lastYaw = camYaw(); _lastInjPx = 0
        return
    end

    local sim, ispeed = liveSim()
    if not sim then   -- lost it (respawn/new run) -> re-scan occasionally
        if os.clock() - _rescanT > 1 then _rescanT = os.clock(); scanSims() end
        lastYaw = camYaw(); _lastInjPx = 0
        return
    end
    if ispeed < S.minSpeed then lastYaw = camYaw(); _lastInjPx = 0; return end

    local si = sim.GameMechanics and sim.GameMechanics.StyleInfo
    local mv = (si and si.mv) or S.mv
    local tickrate = (si and si.tickrate) or S.tickrate

    -- your real turn this frame (camera yaw delta minus what our injection caused)
    local yaw = camYaw()
    local rawDeg = math.deg(math.atan2(math.sin(yaw - lastYaw), math.cos(yaw - lastYaw)))
    lastYaw = yaw
    local playerDeg = rawDeg - (_lastInjPx / PX_PER_DEG)

    if math.abs(playerDeg) < 0.05 then   -- you're not turning -> nothing to optimize
        if S.autoKey then releaseStrafe() end
        _lastInjPx = 0
        return
    end

    local dir = (playerDeg * S.mouseSign) > 0 and 1 or -1
    if S.autoKey then holdStrafe(dir > 0 and Enum.KeyCode.D or Enum.KeyCode.A) end

    -- optimal turn this frame = atan2(mv, speed) * tickrate * dt  (in YOUR direction)
    local optimalDeg = math.deg(math.atan2(mv, ispeed) * tickrate) * dt * (playerDeg > 0 and 1 or -1)
    local injectDeg = (optimalDeg - playerDeg) * S.strength
    injectDeg = math.clamp(injectDeg, -S.maxAngle, S.maxAngle)

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
    Sec:Label({ Name = "keeps the strafe needle in the white (optimal)" })

    local Sec2 = Sub:Section({ Name = "Tuning", Side = 2 })
    Sec2:Slider({ Name = "Strength", Flag = "ST_Strength", Min = 0, Max = 100, Default = 80, Decimals = 0, Suffix = " %",
        Callback = function(v) S.strength = v / 100 end })
    Sec2:Slider({ Name = "Max angle / frame", Flag = "ST_MaxAngle", Min = 1, Max = 60, Default = 25, Decimals = 0, Suffix = " deg",
        Callback = function(v) S.maxAngle = v end })
    Sec2:Slider({ Name = "Min speed", Flag = "ST_MinSpeed", Min = 0, Max = 60, Default = 6, Decimals = 0,
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
