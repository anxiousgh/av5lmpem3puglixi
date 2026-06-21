-- ============================================================
--  games/189707.lua  --  Natural Disaster Survival
--
--  Disaster + fall damage are server-side (custom "Health" attribute + State
--  Replicators) and POSITIONAL, so we beat them by movement, not by writing
--  health. No-fall caps descent BEFORE the physics step so the server never
--  sees a hard landing.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local RunService  = game:GetService("RunService")
local Workspace   = workspace
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local MainPage = Window:Page({ Name = "Main" })

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end
local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ---- No fall damage: fall damage is server-side off your landing velocity. We cap
--      descent on RenderStepped (runs BEFORE the physics step, so it lands this frame
--      instead of one frame late like Heartbeat) and look further ahead the faster we
--      fall, so it always engages in time -> the server only ever sees a soft landing.
local noFall = false
local FALL_CAP = 35
track(RunService.RenderStepped:Connect(function()
    if not noFall then return end
    local hrp = getHRP(); if not hrp then return end
    local v = hrp.AssemblyLinearVelocity
    if v.Y < -FALL_CAP then
        local reach = math.max(40, -v.Y * 0.4)   -- faster fall = detect the ground sooner
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { hrp.Parent }
        if Workspace:Raycast(hrp.Position, Vector3.new(0, -reach, 0), params) then
            hrp.AssemblyLinearVelocity = Vector3.new(v.X, -FALL_CAP, v.Z)
        end
    end
end)

do
    local Sub = MainPage:SubPage({ Name = "Survival" })
    local Sec = Sub:Section({ Name = "Disasters", Side = 1 })
    Sec:Toggle({ Name = "No fall damage", Flag = "NDS_NoFall", Default = false,
        Callback = function(v) noFall = v end })
end

-- universal pages after Main so Main stays first
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    noFall = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
end
do
    local g = (getgenv and getgenv()) or nil
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full() pcall(cleanup); if prev then pcall(prev) end end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
