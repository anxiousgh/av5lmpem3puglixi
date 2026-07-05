-- ============================================================
--  games/87018676608089.lua  --  Pistol Arena  (Virtuals Games)
--
--  FFA one-shot-kill pistol duel (100 damage, 1000-stud range, R6 characters,
--  everyone Neutral -> every other player is a valid target).
--
--  Shoot mechanic (decoded + live-validated 2026-07-05):
--    The real damage remote is HIDDEN behind char-code obfuscation in
--    Shooter_Client as SystemResources.BufferCache.RequestActionSync (the
--    "buffer"/"cache" naming is just camouflage -- it's a plain RemoteEvent).
--    The visible RemoteEvents.Shoot is a decoy/effects remote.
--
--    Its payload is a TABLE that hands the server the hit outright:
--        RequestActionSync:FireServer({
--            origin      = camera.CFrame.Position,
--            direction   = camera.CFrame.LookVector,
--            hitPosition = <hit world pos>,
--            hitInstance = <hit BasePart>,   -- named "Head"/"HeadHitbox" => headshot
--            hitHumanoid = <target Humanoid>,
--            IsHeadshot  = <bool>,
--        })
--    No nonce/token. So a SILENT AIM = send direction = (targetHead - origin).Unit
--    with all three hit fields pointing at any enemy: geometrically self-consistent
--    (origin -> direction -> hitPosition all agree), so the server can't distinguish
--    it from a legit shot -- it only differs from where the crosshair actually points.
--    Live test: one payload dropped a target 57 studs away 100->0 without aiming.
--
--    ONLY works while DEPLOYED: an undeployed player has no server-side weapon and
--    the shot is silently dropped (confirmed -- the first test failed purely on this).
--
--  Deploy (from LobbyGui_Client): RemoteEvents.Deploy:FireServer() with NO args,
--    gated by the client on: LocalPlayer attr "Deployed" ~= true, LoadedMap attr
--    "CanDeploy" ~= false, and attr "Shooter_Client_Loaded" == true. Auto-deploy
--    watches the Deployed attribute and re-fires Deploy when it drops (death/round).
--
--  Cooldown: the gun auto-reloads ReloadDuration=1.1s after each shot, so ~1.1s is
--    the legit fire cadence. Firing faster is the obvious tell -> default gate 1100ms.
--
--  Deliberately does NOT load the universal shell: movement exploits (fly/speed/
--  noclip) are high-risk in a competitive FPS and weren't requested. Silent aim +
--  auto-deploy are the whole module.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer

local conns = {}
local unloaded = false
local function track(c) conns[#conns + 1] = c; return c end
local function gv() return (getgenv and getgenv()) or nil end

-- ---- resolve the hidden shoot remote + the deploy / effect remotes ----
local ShootRemote do
    local sr = ReplicatedStorage:FindFirstChild("SystemResources")
    local bc = sr and sr:FindFirstChild("BufferCache")
    ShootRemote = bc and bc:FindFirstChild("RequestActionSync")
end
local DeployRemote, FakeBulletRemote, MuzzleRemote do
    local ev = ReplicatedStorage:FindFirstChild("Events")
    local re = ev and ev:FindFirstChild("RemoteEvents")
    if re then
        DeployRemote     = re:FindFirstChild("Deploy")
        FakeBulletRemote = re:FindFirstChild("ReplicateFakeBullet")
        MuzzleRemote     = re:FindFirstChild("CharacterMuzzleFlash")
    end
end

-- ============================================================
--  STATE
-- ============================================================
local S = {
    silent = false,          -- auto-shoot silent aim
    mode = "Crosshair",      -- "Crosshair" (nearest to aim within FOV) or "Closest" (nearest in range)
    fov = 250,               -- screen-space radius (px) for Crosshair mode
    maxDist = 1000,          -- world range cap (game Range = 1000)
    cooldown = 1.1,          -- seconds between shots (gun reload = 1.1s; below is risky)
    headshot = true,         -- send IsHeadshot + aim the Head
    visibleCheck = false,    -- only target enemies with clear line of sight
    replicateBullet = true,  -- also fire the cosmetic tracer/muzzle so others see a shot
    autoDeploy = false,      -- re-fire Deploy when we're not deployed
}

-- ============================================================
--  TARGET HELPERS
-- ============================================================
local function myChar() return LocalPlayer.Character end
local function aliveEnemy(p)
    if p == LocalPlayer then return nil end
    local c = p.Character
    if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    if c:FindFirstChild("SpawnProtection") then return nil end   -- can't damage protected spawns
    return c, hum
end
local function aimPart(char)
    if S.headshot then return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
end

-- shared LoS params (exclude our own character; a clear ray to the target = visible)
local _visParams
local function visParams()
    if not _visParams then
        _visParams = RaycastParams.new()
        _visParams.FilterType = Enum.RaycastFilterType.Exclude
    end
    local ignore = {}
    local c = myChar(); if c then ignore[#ignore + 1] = c end
    _visParams.FilterDescendantsInstances = ignore
    return _visParams
end
local function hasLoS(fromPos, part)
    local res = Workspace:Raycast(fromPos, part.Position - fromPos, visParams())
    -- clear, or the first thing hit belongs to the target
    return res == nil or part:IsDescendantOf(res.Instance.Parent) or res.Instance == part
end

-- pick the best enemy to shoot given the current mode
local function bestTarget()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local origin = cam.CFrame.Position
    local mouse = UserInputService:GetMouseLocation()
    local best, bestPart, bestScore = nil, nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        local char, hum = aliveEnemy(p)
        if char and hum then
            local part = aimPart(char)
            if part then
                local dist = (part.Position - origin).Magnitude
                if dist <= S.maxDist then
                    local ok, score = true, nil
                    if S.mode == "Crosshair" then
                        local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                            if d <= S.fov then score = d else ok = false end
                        else
                            ok = false
                        end
                    else                       -- "Closest": nearest in range, any direction
                        score = dist
                    end
                    if ok and S.visibleCheck and not hasLoS(origin, part) then ok = false end
                    if ok and score < bestScore then bestScore, best, bestPart = score, p, part end
                end
            end
        end
    end
    return best, bestPart
end

-- ============================================================
--  SILENT AIM  (auto-shoot the hidden buffer remote at the best target)
-- ============================================================
local function isDeployed()
    return LocalPlayer:GetAttribute("Deployed") == true
        and myChar() ~= nil
        and myChar():FindFirstChildOfClass("Tool") ~= nil
end

local function muzzleWorld()
    -- the viewmodel muzzle (what the real client sends) if present, else the tool handle
    local cam = Workspace.CurrentCamera
    local vm = cam and cam:FindFirstChild("Viewmodel")
    local wa = vm and vm:FindFirstChild("WeaponAttachment")
    local ma = wa and wa:FindFirstChild("MuzzleAttachment")
    if ma then return ma.WorldCFrame end
    local c = myChar()
    local tool = c and c:FindFirstChildOfClass("Tool")
    local handle = tool and tool:FindFirstChild("Handle")
    if handle then return handle.CFrame end
    return cam and cam.CFrame or nil
end

local function fireAt(part)
    if not ShootRemote or not part then return end
    local char = part:FindFirstAncestorWhichIsA("Model")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local dir = (part.Position - origin).Unit          -- silent aim: point exactly at the target
    local head = S.headshot and (part.Name == "Head" or part.Name == "HeadHitbox")
    pcall(function()
        ShootRemote:FireServer({
            origin      = origin,
            direction   = dir,
            hitPosition = part.Position,
            hitInstance = part,
            hitHumanoid = hum,
            IsHeadshot  = head and true or false,
        })
    end)
    -- cosmetic: let other clients see a real tracer/muzzle flash along the same ray
    if S.replicateBullet then
        local mw = muzzleWorld()
        if mw and FakeBulletRemote then
            local mdir = (part.Position - mw.Position)
            mdir = (mdir.Magnitude > 1e-3) and mdir.Unit or dir
            pcall(function() FakeBulletRemote:FireServer(mw, mdir) end)
        end
        if MuzzleRemote then pcall(function() MuzzleRemote:FireServer() end) end
    end
end

local _lastShot = 0
track(RunService.Heartbeat:Connect(function()
    if unloaded or not S.silent then return end
    if not isDeployed() then return end
    if os.clock() - _lastShot < S.cooldown then return end
    local plr, part = bestTarget()
    if not plr or not part then return end
    _lastShot = os.clock()
    fireAt(part)
    -- publish for the shared Target Indicator widget
    local g = gv()
    if g and g.WH then g.WH.currentTarget = plr; g.WH.currentTargetT = os.clock() end
end))

-- ============================================================
--  AUTO DEPLOY  (re-fire Deploy whenever we drop out of the deployed state)
-- ============================================================
local _lastDeploy = 0
track(RunService.Heartbeat:Connect(function()
    if unloaded or not S.autoDeploy or not DeployRemote then return end
    if LocalPlayer:GetAttribute("Deployed") == true then return end
    if LocalPlayer:GetAttribute("Shooter_Client_Loaded") ~= true then return end
    local map = Workspace:FindFirstChild("LoadedMap")
    if map and map:GetAttribute("CanDeploy") == false then return end   -- round still starting
    if os.clock() - _lastDeploy < 0.6 then return end                   -- match the client's 0.2s debounce w/ margin
    _lastDeploy = os.clock()
    pcall(function() DeployRemote:FireServer() end)
end))

-- ============================================================
--  UI
-- ============================================================
do
    local Page = Window:Page({ Name = "Pistol Arena" })
    local Combat = Page:SubPage({ Name = "Combat" })

    local Sec = Combat:Section({ Name = "Silent Aim", Side = 1 })
    local silentToggle = Sec:Toggle({ Name = "Silent aim (auto-shoot)", Flag = "PA_Silent", Default = false,
        Callback = function(v) S.silent = v end })
    silentToggle:Keybind({ Name = "Toggle key", Flag = "PA_SilentKey", Mode = "Toggle",
        Default = Enum.KeyCode.E, Callback = function() silentToggle:Set(not silentToggle.Value) end })
    Sec:Dropdown({ Name = "Target", Flag = "PA_Mode", Default = "Crosshair", Multi = false,
        Items = { "Crosshair", "Closest" },
        Callback = function(v) S.mode = (type(v) == "table" and v[1]) or v or "Crosshair" end })
    Sec:Slider({ Name = "FOV (Crosshair mode)", Flag = "PA_Fov", Min = 30, Max = 1000, Default = 250,
        Decimals = 0, Suffix = " px", Callback = function(v) S.fov = v end })
    Sec:Slider({ Name = "Max distance", Flag = "PA_MaxDist", Min = 50, Max = 1000, Default = 1000,
        Decimals = 0, Suffix = " studs", Callback = function(v) S.maxDist = v end })
    Sec:Toggle({ Name = "Headshots", Flag = "PA_Head", Default = true,
        Callback = function(v) S.headshot = v end })

    local Sec2 = Combat:Section({ Name = "Behaviour", Side = 2 })
    Sec2:Slider({ Name = "Fire cooldown", Flag = "PA_Cooldown", Min = 200, Max = 2000, Default = 1100,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.cooldown = v / 1000 end })
    Sec2:Label({ Name = "gun reload = 1100ms; below that is faster than legit" })
    Sec2:Toggle({ Name = "Visible check (LoS)", Flag = "PA_Vis", Default = false,
        Callback = function(v) S.visibleCheck = v end })
    Sec2:Toggle({ Name = "Replicate bullet (visual)", Flag = "PA_FakeBullet", Default = true,
        Callback = function(v) S.replicateBullet = v end })

    local Sec3 = Combat:Section({ Name = "Deploy", Side = 1 })
    Sec3:Toggle({ Name = "Auto deploy on death", Flag = "PA_AutoDeploy", Default = false,
        Callback = function(v) S.autoDeploy = v end })
    Sec3:Label({ Name = "re-deploys the moment a round/respawn lets you" })
end

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    unloaded = true
    S.silent, S.autoDeploy = false, false
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
