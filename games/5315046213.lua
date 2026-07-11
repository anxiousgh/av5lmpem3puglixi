-- ============================================================
--  games/5315046213.lua  --  Strafe / bhop game (Source-style air physics)
--
--  Decoded live (2026-07-11): custom CFrame movement on an anchored HRP, Source
--  AirAccelerate physics (add air_accel*dt in wishdir, capped at style `mv`),
--  ~100Hz tick, WASD + Space. Velocity object is obfuscated, so we read velocity
--  DIRECTION from HumanoidRootPart position deltas and drive input.
--
--  Strafe ASSIST (v3, ported from a CS:S strafe optimizer's "Silent/legit" mode):
--  it does NOT move your camera on its own. YOU turn; while Space is held and
--  you're airborne it reads your mouse turn, holds the matching strafe key, and
--  BOOSTS or SLOWS your turn so it tracks your velocity vector (keeping the
--  wishdir ~perpendicular = max AirAccelerate gain). Strength blends between
--  "all you" (0%) and "fully optimal" (100%). Camera sens ~6.6 px/deg (measured).
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

local PX_PER_DEG = 6.6   -- mousemoverel(120) turned ~18deg

local S = {
    bhop = false,
    assist = false,
    strength = 0.5,      -- 0 = no help, 1 = fully optimal (hijack). Boost/slow amount.
    maxAngle = 8,        -- cap on degrees the assist adds/removes per frame
    minSpeed = 8,        -- min horizontal speed to activate
    deadzone = 1.5,      -- min mouse movement (px/frame) before we assist -- you must be turning
    autoKey = true,      -- auto-hold A/D matching your turn direction (else you press them)
    mouseSign = 1,       -- calibration: which sign of mouse-X = turning right
    turnSign = 1,        -- calibration: which sign of mousemoverel = turning right
}
-- expose for live tuning (Claude reads/writes via getgenv().WH.strafe)
do local g = getgenv and getgenv(); if g then g.WH = g.WH or {}; g.WH.strafe = S end end

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function signedYaw(a, b)   -- signed horizontal angle (rad) from a to b
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

-- ---- input ----
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

-- ---- main loop ----
local lastPos, _lastInject = nil, 0

track(RunService.RenderStepped:Connect(function(dt)
    local hrp = myHRP()
    if not hrp then lastPos = nil; releaseStrafe(); _lastInject = 0; return end
    local pos = hrp.Position
    if not lastPos then lastPos = pos; return end
    local delta = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z)
    local speed = delta.Magnitude / math.max(dt, 1 / 240)
    lastPos = pos
    local onGround = grounded(pos)

    if S.bhop and onGround then tapJump() end   -- auto-bhop (optional)

    -- assist gates: enabled + Space held + airborne + actually moving
    if not S.assist or onGround or speed < S.minSpeed or delta.Magnitude < 1e-4
        or not UIS:IsKeyDown(Enum.KeyCode.Space) then
        if S.autoKey then releaseStrafe() end
        _lastInject = 0
        return
    end

    -- your real mouse turn this frame (subtract our own injection to avoid a loop)
    local playerDx = (UIS:GetMouseDelta().X - _lastInject) * S.mouseSign

    -- you must actively be turning for the assist to kick in
    if math.abs(playerDx) < S.deadzone then
        if S.autoKey then releaseStrafe() end
        _lastInject = 0
        return
    end

    -- hold the strafe key matching your turn direction (turn right -> D)
    if S.autoKey then holdStrafe(playerDx > 0 and Enum.KeyCode.D or Enum.KeyCode.A) end

    -- optimal turn this frame = the amount that realigns look with your velocity
    -- (so the strafe key's wishdir stays perpendicular). Boost/slow you toward it.
    local velDir = delta.Unit
    local lv = Workspace.CurrentCamera.CFrame.LookVector
    local look = Vector3.new(lv.X, 0, lv.Z)
    if look.Magnitude < 1e-3 then return end
    look = look.Unit

    local desiredDeg = math.deg(signedYaw(look, velDir))     -- optimal turn (signed, toward velocity)
    local playerDeg = playerDx / PX_PER_DEG                  -- your turn this frame, in degrees
    local injectDeg = (desiredDeg - playerDeg) * S.strength  -- close the gap (boost/slow)
    if S.maxAngle > 0 then injectDeg = math.clamp(injectDeg, -S.maxAngle, S.maxAngle) end

    local injectPx = injectDeg * PX_PER_DEG * S.turnSign
    pcall(function() mousemoverel(injectPx, 0) end)
    _lastInject = injectPx
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
    Sec:Label({ Name = "you turn -- it boosts/slows your strafe to optimal" })

    local Sec2 = Sub:Section({ Name = "Tuning", Side = 2 })
    Sec2:Slider({ Name = "Strength", Flag = "ST_Strength", Min = 0, Max = 100, Default = 50, Decimals = 0, Suffix = " %",
        Callback = function(v) S.strength = v / 100 end })
    Sec2:Slider({ Name = "Max angle / frame", Flag = "ST_MaxAngle", Min = 0, Max = 30, Default = 8, Decimals = 0, Suffix = " deg",
        Callback = function(v) S.maxAngle = v end })
    Sec2:Slider({ Name = "Deadzone", Flag = "ST_Deadzone", Min = 0, Max = 10, Default = 15, Decimals = 1, Suffix = " px",
        Callback = function(v) S.deadzone = v / 10 end })
    Sec2:Toggle({ Name = "Flip mouse read", Flag = "ST_MouseSign", Default = false,
        Callback = function(v) S.mouseSign = v and -1 or 1 end })
    Sec2:Toggle({ Name = "Flip turn output", Flag = "ST_TurnSign", Default = false,
        Callback = function(v) S.turnSign = v and -1 or 1 end })
    Sec2:Label({ Name = "if it fights your turn, flip mouse read or turn output" })
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
