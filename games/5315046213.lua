-- ============================================================
--  games/5315046213.lua  --  Strafe / bhop game (Source-style air physics)
--
--  Decoded live (2026-07-11): custom CFrame-driven movement on an anchored HRP.
--  The physics engine is Source AirAccelerate -- each airborne tick it adds
--  air_accel*dt in your input direction (wishdir), capped so speed ALONG wishdir
--  can't exceed the style's `mv`. So strafing perpendicular to your velocity
--  gains speed every frame. Styles run at a fixed ~100Hz internal tick; movement
--  is standard WASD (read via the Roblox ControlModule) + Space to jump.
--
--  We can't cleanly latch the obfuscated velocity object, so this drives INPUTS
--  and lets the game's own physics produce the speed:
--    * velocity  -> derived from HumanoidRootPart position deltas
--    * grounded  -> short downward raycast
--    * jump      -> VirtualInputManager Space tap on landing (auto-bhop)
--    * strafe    -> hold A/D + turn the camera via mousemoverel (auto air-strafe)
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

local S = {
    bhop = false,
    strafe = false,
    dir = "Alternate",      -- Right | Left | Alternate
    altPeriod = 0.30,       -- seconds per side when alternating
    turnRate = 14,          -- mousemoverel px/frame while strafing (the main tuning knob)
    turnSign = 1,           -- calibration for which way mousemoverel turns (+1/-1)
    minSpeed = 6,           -- need this much horizontal speed before we bother strafing
}

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ---- ground check (short ray straight down; HRP pos is readable even anchored) ----
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function isGrounded(pos)
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    return Workspace:Raycast(pos, Vector3.new(0, -5, 0), rayParams) ~= nil
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

-- ---- main loop: derive velocity from position delta, drive bhop + strafe ----
local lastPos = nil
local _altT = 0
local _altSide = 1   -- 1 = Right (D), -1 = Left (A)

track(RunService.RenderStepped:Connect(function(dt)
    local hrp = myHRP()
    if not hrp then lastPos = nil; releaseStrafe(); return end
    local pos = hrp.Position
    if not lastPos then lastPos = pos; return end

    local delta = Vector3.new(pos.X - lastPos.X, 0, pos.Z - lastPos.Z)
    local speed = delta.Magnitude / math.max(dt, 1 / 240)
    lastPos = pos
    local grounded = isGrounded(pos)

    -- auto-bhop: tap jump the instant we're on the ground so we never lose momentum
    if S.bhop and grounded then tapJump() end

    -- auto air-strafe: only while airborne and actually moving
    if not S.strafe or grounded or speed < S.minSpeed then
        releaseStrafe()
        return
    end

    -- pick a side
    local side = _altSide
    if S.dir == "Right" then side = 1
    elseif S.dir == "Left" then side = -1
    else -- Alternate
        _altT = _altT + dt
        if _altT >= S.altPeriod then _altT = 0; _altSide = -_altSide end
        side = _altSide
    end

    -- hold the strafe key on that side and turn the camera the same way; the
    -- game's wishdir (camera-relative + strafe key) then curves with the turn,
    -- staying ~perpendicular to velocity so air_accel adds speed each tick.
    holdStrafe(side == 1 and Enum.KeyCode.D or Enum.KeyCode.A)
    pcall(function() mousemoverel(side * S.turnSign * S.turnRate, 0) end)
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
    Sec:Label({ Name = "Alternate = straightish, Left/Right = circle" })

    local Sec2 = Sub:Section({ Name = "Tuning", Side = 2 })
    Sec2:Slider({ Name = "Turn rate", Flag = "ST_TurnRate", Min = 2, Max = 60, Default = 14, Decimals = 0,
        Callback = function(v) S.turnRate = v end })
    Sec2:Slider({ Name = "Alternate period", Flag = "ST_AltPeriod", Min = 100, Max = 800, Default = 300,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.altPeriod = v / 1000 end })
    Sec2:Slider({ Name = "Min speed", Flag = "ST_MinSpeed", Min = 0, Max = 40, Default = 6, Decimals = 0,
        Callback = function(v) S.minSpeed = v end })
    Sec2:Toggle({ Name = "Flip turn direction", Flag = "ST_TurnSign", Default = false,
        Callback = function(v) S.turnSign = v and -1 or 1 end })
    Sec2:Label({ Name = "Turn rate is the main knob -- tune for max speed" })
end

-- universal shell after our page (ESP etc.); movement toggles there can conflict
-- with the strafe optimizer, so prefer the Strafe page above.
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
