-- ============================================================
--  games/5315046213.lua  --  Strafe / bhop game (Source-style air physics)
--
--  Decoded live (2026-07-11): custom CFrame-driven movement on an anchored HRP,
--  Source AirAccelerate physics (air_accel*dt in wishdir, capped at style `mv`),
--  ~100Hz tick, standard WASD + Space. The velocity object is obfuscated, so we
--  drive INPUTS and let the game's own physics build the speed:
--    * velocity  -> derived from HumanoidRootPart position deltas (direction)
--    * grounded  -> short downward raycast
--    * jump      -> VirtualInputManager Space tap on landing (auto-bhop)
--    * strafe    -> hold A/D + turn the camera via mousemoverel
--
--  Strafe method ported from a CS:S strafe optimizer (unknowncheats): instead of
--  a blind constant turn, TRACK the velocity vector -- turn the camera to follow
--  it so the held strafe key's wishdir stays ~perpendicular to velocity (where
--  AirAccelerate adds the most speed). Gain / Max angle / Smoothness / Min speed
--  / wall-check mirror that cheat's knobs. Camera sens ~6.6 px/deg (measured).
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM        = game:GetService("VirtualInputManager")
local Workspace  = workspace
local LocalPlayer = Players.LocalPlayer

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local PX_PER_DEG = 6.6   -- mousemoverel(120) turned ~18deg -> 120/18

local S = {
    bhop = false,
    strafe = false,
    dir = "Alternate",   -- Right | Left | Alternate
    altPeriod = 0.28,    -- seconds per side when alternating
    gain = 1.0,          -- how hard to follow velocity (1 = exact; >1 leads, <1 lags)
    maxAngle = 6,        -- max degrees turned per frame (0 = unlimited)
    smooth = 0.55,       -- 0..1 turn smoothing (lower = smoother)
    minSpeed = 8,        -- min horizontal speed to activate
    wallCheck = 6,       -- studs ahead to check for a wall (0 = off; stops strafing into walls)
    turnSign = 1,        -- calibration for mousemoverel turn direction (+1/-1)
}
-- expose for live tuning (Claude reads/writes via getgenv().WH.strafe)
do local g = getgenv and getgenv(); if g then g.WH = g.WH or {}; g.WH.strafe = S end end

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- signed horizontal angle (radians) from vector a to vector b
local function signedYaw(a, b)
    local cross = a.X * b.Z - a.Z * b.X
    local dot = math.clamp(a.X * b.X + a.Z * b.Z, -1, 1)
    return math.atan2(cross, dot)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function raycast(origin, dir)
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    return Workspace:Raycast(origin, dir, rayParams)
end

-- ---- input helpers ----
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
local lastPos, _altT, _altSide, _turnAccum = nil, 0, 1, 0

track(RunService.RenderStepped:Connect(function(dt)
    local hrp = myHRP()
    if not hrp then lastPos = nil; releaseStrafe(); return end
    local pos = hrp.Position
    if not lastPos then lastPos = pos; return end

    local delta = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z)
    local speed = delta.Magnitude / math.max(dt, 1 / 240)
    lastPos = pos
    local grounded = raycast(pos, Vector3.new(0, -5, 0)) ~= nil

    if S.bhop and grounded then tapJump() end   -- auto-bhop

    if not S.strafe or grounded or speed < S.minSpeed or delta.Magnitude < 1e-4 then
        releaseStrafe(); _turnAccum = 0
        return
    end

    local velDir = delta.Unit
    -- wall ahead? stop strafing so we don't curve into it
    if S.wallCheck > 0 and raycast(pos, velDir * S.wallCheck) then
        releaseStrafe(); return
    end

    -- pick a side
    local side = _altSide
    if S.dir == "Right" then side = 1
    elseif S.dir == "Left" then side = -1
    else
        _altT = _altT + dt
        if _altT >= S.altPeriod then _altT = 0; _altSide = -_altSide end
        side = _altSide
    end
    holdStrafe(side == 1 and Enum.KeyCode.D or Enum.KeyCode.A)

    -- follow the velocity vector: turn the camera-look toward it so the held
    -- strafe key's wishdir (camera-relative) stays ~perpendicular to velocity.
    local look = Vector3.new(0, 0, 0)
    local lv = Workspace.CurrentCamera.CFrame.LookVector
    look = Vector3.new(lv.X, 0, lv.Z)
    if look.Magnitude < 1e-3 then return end
    look = look.Unit

    local errDeg = math.deg(signedYaw(look, velDir))
    local turnDeg = errDeg * S.gain
    if S.maxAngle > 0 then turnDeg = math.clamp(turnDeg, -S.maxAngle, S.maxAngle) end
    _turnAccum = _turnAccum + (turnDeg - _turnAccum) * math.clamp(S.smooth, 0.05, 1)
    pcall(function() mousemoverel(_turnAccum * PX_PER_DEG * S.turnSign, 0) end)
end))

-- ============================================================
--  UI
-- ============================================================
do
    local Page = Window:Page({ Name = "Strafe" })
    local Sub  = Page:SubPage({ Name = "Optimizer" })

    local Sec = Sub:Section({ Name = "Movement", Side = 1 })
    Sec:Toggle({ Name = "Auto Bhop", Flag = "ST_Bhop", Default = false,
        Callback = function(v) S.bhop = v end })
    Sec:Toggle({ Name = "Auto Strafe", Flag = "ST_Strafe", Default = false,
        Callback = function(v) S.strafe = v; if not v then releaseStrafe() end end })
    Sec:Dropdown({ Name = "Strafe direction", Flag = "ST_Dir", Default = "Alternate", Multi = false,
        Items = { "Alternate", "Right", "Left" },
        Callback = function(v) S.dir = (type(v) == "table" and v[1]) or v or "Alternate" end })
    Sec:Slider({ Name = "Min speed", Flag = "ST_MinSpeed", Min = 0, Max = 60, Default = 8, Decimals = 0,
        Callback = function(v) S.minSpeed = v end })
    Sec:Toggle({ Name = "Flip turn direction", Flag = "ST_TurnSign", Default = false,
        Callback = function(v) S.turnSign = v and -1 or 1 end })

    local Sec2 = Sub:Section({ Name = "Tuning", Side = 2 })
    Sec2:Slider({ Name = "Gain", Flag = "ST_Gain", Min = 10, Max = 200, Default = 100, Decimals = 0, Suffix = " %",
        Callback = function(v) S.gain = v / 100 end })
    Sec2:Slider({ Name = "Max angle / frame", Flag = "ST_MaxAngle", Min = 0, Max = 30, Default = 6, Decimals = 0, Suffix = " deg",
        Callback = function(v) S.maxAngle = v end })
    Sec2:Slider({ Name = "Smoothness", Flag = "ST_Smooth", Min = 5, Max = 100, Default = 55, Decimals = 0, Suffix = " %",
        Callback = function(v) S.smooth = v / 100 end })
    Sec2:Slider({ Name = "Wall check", Flag = "ST_Wall", Min = 0, Max = 20, Default = 6, Decimals = 0, Suffix = " studs",
        Callback = function(v) S.wallCheck = v end })
    Sec2:Slider({ Name = "Alternate period", Flag = "ST_AltPeriod", Min = 100, Max = 800, Default = 280,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.altPeriod = v / 1000 end })
    Sec2:Label({ Name = "tracks your velocity -- Gain/Max angle are the main knobs" })
end

pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    S.bhop, S.strafe = false, false
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
