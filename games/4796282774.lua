-- ============================================================
--  games/4796282774.lua  --  Custom Minigames (Customs Community)
--
--  Rotating minigame modes share one loadout of classic gear. Each feature
--  self-detects the tool/remote it needs and no-ops when that mode isn't up,
--  so every toggle is safe to leave on across rounds.
--
--  Vectors:
--    Auto Push  -- "push" tool exposes Tool.Hit RemoteEvent; FireServer("Hit",part)
--                  applies server-side knockback. Server range-gates it, so we only
--                  fire when an enemy is genuinely close (defensive auto-bump).
--    Gear Aimbot-- Slingshot/RocketLauncher/Trowel/Superball ask the client for its
--                  aim via MouseLoc:InvokeClient(); we override OnClientInvoke to
--                  return the nearest enemy's position -> projectiles home in.
--    Sword Aura -- ClassicSword damage is server-side Handle.Touched. We firetouchinterest
--                  the real Handle onto nearby enemies, after deleting the local
--                  SwordClient honeypot (it BreakJoints-es you on >15-stud touches).
--                  [experimental: SwordMain server range check is unverified]
--    Phys Boost -- disable physics throttle/sleep, extend sim radius, and raise the
--                  DFIntS2PhysicsSenderRate fflag so your pos replicates far tighter.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local function gv() return (getgenv and getgenv()) or nil end

local MainPage = Window:Page({ Name = "Main" })

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

-- settings live in getgenv so state + the (one-time) gear hooks survive a re-exec
local S = (gv() and gv()._CMG_S) or {
    push = false, pushRange = 5, pushCD = 0.35,
    showRange = false, rangeColor = Color3.fromRGB(255, 80, 80),
    aim = false,
    sword = false, swordRange = 14, swordCD = 0.2,
    swordLunge = true, swordLungeCD = 0.6,
    phys = false, sendRate = 240,
}
-- backfill fields added in later versions onto a persisted (re-exec'd) table
if S.showRange == nil then S.showRange = false end
if S.rangeColor == nil then S.rangeColor = Color3.fromRGB(255, 80, 80) end
if S.swordLunge == nil then S.swordLunge = true end
if S.swordLungeCD == nil then S.swordLungeCD = 0.6 end
if gv() then gv()._CMG_S = S end

-- ---- shared target helpers ----
local function myHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function aimPart(char)
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end
local function nearestEnemyPart()
    local hrp = myHRP(); if not hrp then return nil end
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum  = p.Character:FindFirstChildOfClass("Humanoid")
            local part = aimPart(p.Character)
            if hum and hum.Health > 0 and part then
                local d = (part.Position - hrp.Position).Magnitude
                if not bestD or d < bestD then best, bestD = part, d end
            end
        end
    end
    return best
end
-- iterate every living enemy body part within `range` studs, respecting a
-- per-target cooldown table; calls fn(part) for each one that is due to fire.
local function forEnemiesInRange(range, cdTable, cd, fn)
    local hrp = myHRP(); if not hrp then return end
    local now = os.clock()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum  = p.Character:FindFirstChildOfClass("Humanoid")
            local part = p.Character:FindFirstChild("Torso") or p.Character:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and part
               and (part.Position - hrp.Position).Magnitude <= range
               and now - (cdTable[p] or 0) >= cd then
                cdTable[p] = now
                fn(part)
            end
        end
    end
end

-- ============================================================
--  AUTO PUSH  -- defensive: bump anyone who gets close. No teleporting.
-- ============================================================
do
    local lastPush = {}
    local function pushRemote()  -- any equipped tool exposing a Hit RemoteEvent
        local char = LocalPlayer.Character
        if not char then return nil end
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then
                local h = t:FindFirstChild("Hit")
                if h and h:IsA("RemoteEvent") then return h end
            end
        end
    end
    track(RunService.Heartbeat:Connect(function()
        if not S.push then return end
        local hit = pushRemote()
        if not hit then return end
        forEnemiesInRange(S.pushRange, lastPush, S.pushCD, function(part)
            hit:FireServer("Hit", part)
        end)
    end))
end

-- ---- range visualizer: a flat translucent disc at your feet, radius = pushRange.
--      doubles as a debug aid -- if it shows, the render loop is alive. ----
do
    local disc
    track(RunService.RenderStepped:Connect(function()
        if not S.showRange then
            if disc then disc.Transparency = 1 end
            return
        end
        local hrp = myHRP()
        if not hrp then return end
        if not (disc and disc.Parent) then
            disc = Instance.new("Part")
            disc.Shape = Enum.PartType.Cylinder
            disc.Anchored, disc.CanCollide, disc.CanQuery = true, false, false
            disc.CanTouch, disc.Massless = false, true
            disc.Material = Enum.Material.ForceField
            disc.Name = "\0"
            pcall(function() disc.Parent = workspace end)
            S._discDestroy = function() if disc then pcall(function() disc:Destroy() end); disc = nil end end
        end
        local dia = S.pushRange * 2
        disc.Size = Vector3.new(0.2, dia, dia)
        disc.Color = S.rangeColor or Color3.fromRGB(255, 80, 80)
        disc.Transparency = 0.6
        -- lay the cylinder flat (axis up) so the circular face sits on the ground at your feet
        disc.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
    end))
end

-- ============================================================
--  GEAR AIMBOT  -- override MouseLoc.OnClientInvoke to return the nearest enemy.
--  Hooked once per gear; behaviour is gated by S.aim so toggling never un-hooks.
-- ============================================================
do
    local mouse  = LocalPlayer:GetMouse()
    local hooked = setmetatable({}, { __mode = "k" })
    local lastScan = 0
    local function aimQuery()
        if S.aim then
            local part = nearestEnemyPart()
            if part then return part.Position end
        end
        return mouse.Hit.p   -- off (or no target) -> behave exactly like the real gear
    end
    track(RunService.Heartbeat:Connect(function()
        if os.clock() - lastScan < 0.4 then return end
        lastScan = os.clock()
        for _, c in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack") }) do
            if c then
                for _, t in ipairs(c:GetChildren()) do
                    if t:IsA("Tool") then
                        local ml = t:FindFirstChild("MouseLoc")
                        if ml and ml:IsA("RemoteFunction") and not hooked[ml] then
                            hooked[ml] = true
                            ml.OnClientInvoke = aimQuery
                        end
                    end
                end
            end
        end
    end))
end

-- ============================================================
--  SWORD AURA  -- firetouchinterest the real Handle onto nearby enemies.
--  First delete the SwordClient honeypot (local-only, no server channel).
-- ============================================================
do
    local lastSword, lastSlash, lastLunge = {}, 0, 0
    local lunging = false
    local function targetInRange()
        local hrp = myHRP(); if not hrp then return false end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local hum  = p.Character:FindFirstChildOfClass("Humanoid")
                local part = p.Character:FindFirstChild("Torso") or p.Character:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and part and (part.Position - hrp.Position).Magnitude <= S.swordRange then
                    return true
                end
            end
        end
        return false
    end
    local function touchAll(handle)
        forEnemiesInRange(S.swordRange, lastSword, 0, function(part)
            firetouchinterest(handle, part, 0); firetouchinterest(handle, part, 1)
        end)
    end
    track(RunService.Heartbeat:Connect(function()
        if not S.sword or not firetouchinterest then return end
        local char  = LocalPlayer.Character
        local sword = char and char:FindFirstChild("ClassicSword")
        local handle = sword and sword:FindFirstChild("Handle")
        if not handle then return end
        -- kill the local BreakJoints trap if present (it has no server reporting)
        local main = sword:FindFirstChild("SwordMain")
        local trap = main and main:FindFirstChild("SwordClient")
        if trap then pcall(function() trap:Destroy() end) end
        if not targetInRange() then return end

        if S.swordLunge then
            -- triggerbot: when an enemy is in range, double-Activate within the lunge
            -- window so the server swaps in lunge (super) damage, then spray touches
            -- across the lunge damage window so the hits land as the super attack.
            if not lunging and os.clock() - lastLunge >= S.swordLungeCD then
                lunging = true; lastLunge = os.clock()
                task.spawn(function()
                    pcall(function() sword.Enabled = true end); pcall(function() sword:Activate() end)
                    task.wait(0.12)
                    pcall(function() sword.Enabled = true end); pcall(function() sword:Activate() end)
                    for _ = 1, 10 do
                        if not S.sword then break end
                        touchAll(handle)
                        task.wait(0.03)
                    end
                    lunging = false
                end)
            end
        else
            -- normal slash aura
            if os.clock() - lastSlash > 0.25 then
                lastSlash = os.clock()
                pcall(function() sword:Activate() end)
            end
            forEnemiesInRange(S.swordRange, lastSword, S.swordCD, function(part)
                firetouchinterest(handle, part, 0)
                firetouchinterest(handle, part, 1)
            end)
        end
    end))
end

-- ============================================================
--  PHYSICS / SEND-RATE BOOST  -- tighten how often you replicate to the server.
-- ============================================================
local function applyPhys(on)
    pcall(function()
        settings().Physics.PhysicsEnvironmentalThrottle =
            on and Enum.EnviromentalPhysicsThrottle.Disabled or Enum.EnviromentalPhysicsThrottle.DefaultAuto
    end)
    pcall(function() settings().Physics.AllowSleep = not on end)
    if on and sethiddenproperty then
        pcall(function() sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge) end)
        pcall(function() sethiddenproperty(LocalPlayer, "MaximumSimulationRadius", math.huge) end)
    end
    if on and setfflag then
        pcall(setfflag, "DFIntS2PhysicsSenderRate", tostring(math.floor(S.sendRate)))
        pcall(setfflag, "DFIntPhysicsSenderMaxBandwidthBps", "3000000")
    end
end

-- ============================================================
--  UI
-- ============================================================
local Combat = MainPage:SubPage({ Name = "Combat" })
do
    local Sec = Combat:Section({ Name = "Auto Push", Side = 1 })
    local pushTog = Sec:Toggle({ Name = "Enabled", Flag = "CMG_Push", Default = false,
        Callback = function(v) S.push = v end })
    Sec:Slider({ Name = "Range", Flag = "CMG_PushRange", Min = 3, Max = 25, Default = 5, Decimals = 0, Suffix = " studs",
        Callback = function(v) S.pushRange = v end })
    Sec:Slider({ Name = "Cooldown", Flag = "CMG_PushCD", Min = 50, Max = 1000, Default = 350, Decimals = 0, Suffix = " ms",
        Callback = function(v) S.pushCD = v / 1000 end })
    Sec:Label({ Name = "Toggle key" }):Keybind({ Name = "AutoPush", Flag = "CMG_PushKey", Mode = "Toggle",
        Callback = function(state) pushTog:Set(state and true or false) end })
    Sec:Toggle({ Name = "Show range", Flag = "CMG_PushViz", Default = false,
        Callback = function(v) S.showRange = v end })
    Sec:Label({ Name = "Range color" }):Colorpicker({ Flag = "CMG_PushVizColor", Default = Color3.fromRGB(255, 80, 80),
        Callback = function(c) S.rangeColor = c end })

    local Sec2 = Combat:Section({ Name = "Gear Aimbot", Side = 2 })
    Sec2:Label({ Name = "Slingshot / Rocket / Trowel / Superball" })
    local aimTog = Sec2:Toggle({ Name = "Enabled", Flag = "CMG_Aim", Default = false,
        Callback = function(v) S.aim = v end })
    Sec2:Label({ Name = "Toggle key" }):Keybind({ Name = "Aimbot", Flag = "CMG_AimKey", Mode = "Toggle",
        Callback = function(state) aimTog:Set(state and true or false) end })

    local Sec3 = Combat:Section({ Name = "Sword Aura", Side = 1 })
    Sec3:Label({ Name = "ClassicSword -- experimental" })
    local swordTog = Sec3:Toggle({ Name = "Enabled", Flag = "CMG_Sword", Default = false,
        Callback = function(v) S.sword = v end })
    Sec3:Slider({ Name = "Range", Flag = "CMG_SwordRange", Min = 5, Max = 30, Default = 14, Decimals = 0, Suffix = " studs",
        Callback = function(v) S.swordRange = v end })
    Sec3:Toggle({ Name = "Lunge (super) damage", Flag = "CMG_SwordLunge", Default = true,
        Callback = function(v) S.swordLunge = v end })
    Sec3:Slider({ Name = "Lunge cooldown", Flag = "CMG_SwordLungeCD", Min = 200, Max = 1500, Default = 600, Decimals = 0, Suffix = " ms",
        Callback = function(v) S.swordLungeCD = v / 1000 end })
    Sec3:Label({ Name = "Toggle key" }):Keybind({ Name = "SwordAura", Flag = "CMG_SwordKey", Mode = "Toggle",
        Callback = function(state) swordTog:Set(state and true or false) end })
end

local Net = MainPage:SubPage({ Name = "Network" })
do
    local Sec = Net:Section({ Name = "Physics send boost", Side = 1 })
    Sec:Label({ Name = "Tighter server-pos replication" })
    Sec:Toggle({ Name = "Enabled", Flag = "CMG_Phys", Default = false,
        Callback = function(v) S.phys = v; applyPhys(v) end })
    Sec:Slider({ Name = "Send rate", Flag = "CMG_SendRate", Min = 30, Max = 480, Default = 240, Decimals = 0, Suffix = " Hz",
        Callback = function(v) S.sendRate = v; if S.phys then applyPhys(true) end end })
    Sec:Label({ Name = "fflag applies best at launch; resets on rejoin" })
end

-- universal pages after Main so Main stays first
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    S.push, S.aim, S.sword, S.showRange = false, false, false, false
    if S._discDestroy then pcall(S._discDestroy) end
    if S.phys then pcall(function() applyPhys(false) end); S.phys = false end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
end
do
    local g = gv()
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full() pcall(cleanup); if prev then pcall(prev) end end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
