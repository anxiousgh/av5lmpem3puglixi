-- ============================================================
--  games/5315046213.lua  --  Strafe / bhop game (Source-style air physics)
--
--  Decoded live (2026-07-11): custom CFrame movement on an anchored HRP, Source
--  AirAccelerate physics, ~100Hz tick, WASD + Space. Velocity object obfuscated,
--  so we read velocity DIRECTION from HumanoidRootPart position deltas.
--
--  Strafe ASSIST (v4): you steer, it boosts/slows your turn toward the optimal
--  (tracking your velocity's rotation) -- active only while Space is held.
--  Fixes over v3: smoothed velocity (less choppy); target = velocity's turn RATE,
--  not zero, so it never fights your turning; slowing is clamped so it can never
--  cancel your own movement; lower magnitude. Debug recorder for tuning.
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
    strength = 0.5,     -- how hard to pull your turn toward optimal
    maxBoost = 6,       -- max deg/frame the assist may ADD (boost cap; also "too fast" fix)
    maxSlow = 0.5,      -- assist may remove at most this fraction of YOUR turn (never cancels you)
    smooth = 0.3,       -- injection smoothing (lower = smoother, fixes chop)
    minSpeed = 8,
    autoKey = true,
    mouseSign = 1, turnSign = 1,
    debug = false,
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

-- debug ring buffer (Claude reads getgenv().WH.strafe._dbg)
S._dbg = {}
local function dbg(row) if S.debug then local d = S._dbg; d[#d + 1] = row; if #d > 150 then table.remove(d, 1) end end end

local lastPos, velSmooth, prevVel, _turnAccum, _lastInject = nil, nil, nil, 0, 0

track(RunService.RenderStepped:Connect(function(dt)
    local hrp = myHRP()
    if not hrp then lastPos = nil; releaseStrafe(); _lastInject = 0; return end
    local pos = hrp.Position
    if not lastPos then lastPos = pos; return end
    local delta = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z)
    local speed = delta.Magnitude / math.max(dt, 1 / 240)
    lastPos = pos
    local onGround = grounded(pos)

    if S.bhop and onGround then tapJump() end

    if not S.assist or onGround or speed < S.minSpeed or delta.Magnitude < 1e-4
        or not UIS:IsKeyDown(Enum.KeyCode.Space) then
        if S.autoKey then releaseStrafe() end
        _lastInject = 0; velSmooth = nil; prevVel = nil; _turnAccum = 0
        return
    end

    -- smoothed velocity direction (raw position delta is jittery -> choppy)
    local velDir = delta.Unit
    velSmooth = velSmooth and (velSmooth * 0.6 + velDir * 0.4) or velDir
    if velSmooth.Magnitude > 1e-3 then velSmooth = velSmooth.Unit end
    -- how much the velocity vector rotated this frame = the ideal camera turn to track it
    local velTurnDeg = prevVel and math.deg(signedYaw(prevVel, velSmooth)) or 0
    prevVel = velSmooth

    -- your mouse turn this frame (best-effort remove our own injection)
    local playerDeg = ((UIS:GetMouseDelta().X - _lastInject) / PX_PER_DEG) * S.mouseSign

    -- strafe key follows your turn direction (fall back to velocity's rotation)
    local dirSign = (math.abs(playerDeg) > 0.2 and (playerDeg > 0 and 1 or -1))
        or (velTurnDeg > 0 and 1 or -1)
    if S.autoKey then holdStrafe(dirSign > 0 and Enum.KeyCode.D or Enum.KeyCode.A) end

    -- boost/slow YOUR turn toward the optimal (= velocity's rotation rate)
    local injectDeg = (velTurnDeg - playerDeg) * S.strength
    -- boost is capped; slowing can never remove more than maxSlow of your own turn
    injectDeg = math.clamp(injectDeg, -math.abs(playerDeg) * S.maxSlow, S.maxBoost)
    _turnAccum = _turnAccum + (injectDeg - _turnAccum) * math.clamp(S.smooth, 0.05, 1)

    local injectPx = _turnAccum * PX_PER_DEG * S.turnSign
    pcall(function() mousemoverel(injectPx, 0) end)
    _lastInject = injectPx

    dbg({ spd = math.floor(speed), vturn = math.floor(velTurnDeg * 10) / 10,
          you = math.floor(playerDeg * 10) / 10, inj = math.floor(_turnAccum * 10) / 10 })
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
    Sec:Label({ Name = "you turn -- it boosts/slows toward optimal" })

    local Sec2 = Sub:Section({ Name = "Tuning", Side = 2 })
    Sec2:Slider({ Name = "Strength", Flag = "ST_Strength", Min = 0, Max = 100, Default = 50, Decimals = 0, Suffix = " %",
        Callback = function(v) S.strength = v / 100 end })
    Sec2:Slider({ Name = "Boost cap", Flag = "ST_MaxBoost", Min = 1, Max = 20, Default = 6, Decimals = 0, Suffix = " deg",
        Callback = function(v) S.maxBoost = v end })
    Sec2:Slider({ Name = "Smoothness", Flag = "ST_Smooth", Min = 5, Max = 100, Default = 30, Decimals = 0, Suffix = " %",
        Callback = function(v) S.smooth = v / 100 end })
    Sec2:Toggle({ Name = "Flip mouse read", Flag = "ST_MouseSign", Default = false,
        Callback = function(v) S.mouseSign = v and -1 or 1 end })
    Sec2:Toggle({ Name = "Flip turn output", Flag = "ST_TurnSign", Default = false,
        Callback = function(v) S.turnSign = v and -1 or 1 end })
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
