-- ============================================================
--  games/87018676608089.lua  --  Pistol Arena  (Virtuals Games)
--
--  FFA one-shot-kill pistol duel (100 damage, 1000-stud range, R6 characters,
--  everyone Neutral -> every other player is a valid target).
--
--  Shoot mechanic (decoded + live-validated 2026-07-05):
--    The real damage remote is HIDDEN by char-code obfuscation in Shooter_Client
--    as ReplicatedStorage.SystemResources.BufferCache.RequestActionSync (a plain
--    RemoteEvent; the visible RemoteEvents.Shoot is a decoy). Its payload is a
--    TABLE that hands the server the hit outright:
--        { origin, direction, hitPosition, hitInstance, hitHumanoid, IsHeadshot }
--    No nonce. Silent aim = direction=(head-origin).Unit with all hit fields on
--    any enemy: self-consistent, indistinguishable from a legit shot server-side.
--    ONLY works while DEPLOYED (undeployed = no server weapon = shot dropped).
--
--  Rate limit: the gun is one-shot-then-1.1s-reload (no magazine burst). The
--    SERVER rate-limits RequestActionSync to that cadence and KICKS for rapid fire
--    below it -- the check is in a server Script, so there is NO client bypass.
--    Cooldown is floored at 1.0s.
--
--  Deploy: RemoteEvents.Deploy:FireServer() (no args), gated by the client on attrs
--    Deployed~=true + Shooter_Client_Loaded==true + workspace.LoadedMap CanDeploy~=
--    false. Auto-deploy is event-driven off the Deployed attribute -> instant.
--
--  Loads the universal shell (ESP + Player movement) after its page. Movement is
--    higher anti-cheat risk in a competitive FPS -- ESP is the safe part.
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

-- generation guard: a re-exec bumps the token, so any persistent loop left over from a
-- prior instance (whose teardown didn't run) goes inert instead of fighting this one --
-- e.g. a leaked 3rd-person loop that would keep forcing the camera / mouse.
local MYGEN = ((gv() and gv()._WH_PA_gen) or 0) + 1
if gv() then gv()._WH_PA_gen = MYGEN end
local function current() local g = gv(); return (g == nil) or g._WH_PA_gen == MYGEN end

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
    mode = "Closest to mouse", -- which enemy when several are in range (NO fov -- always shoots)
    maxDist = 1000,          -- world range cap (game Range = 1000)
    cooldown = 1.1,          -- seconds between shots (floored at 1.0 -- server kicks below)
    headshot = true,         -- send IsHeadshot + aim the Head
    visibleCheck = false,    -- only target enemies with clear line of sight
    replicateBullet = true,  -- fire the game's own tracer/muzzle so OTHERS see a shot
    autoDeploy = false,      -- re-fire Deploy the instant we're not deployed
    priority = {},           -- lowercased name fragments; deployed priority targets shot first

    -- tracer FX (ported from HC) -- LOCAL visual you see, drawn muzzle -> hit
    tracerEnabled = false, tracerStyle = "Standard", tracerColor = Color3.fromRGB(0, 255, 80),
    tracerThickness = 0.12, tracerLifetime = 0.2, tracerThroughWalls = true,

    -- kill sound (HC asset) -- plays on a confirmed kill
    killSound = false, killSoundId = 102740241606246, soundVolume = 1.0,

    -- camera: the game locks first person (CameraMode=LockFirstPerson); this frees it
    thirdPerson = false, tpZoom = 15, hideVM = true,   -- hideVM = hide the on-screen hands+gun
    freeMouse = true,   -- in 3rd person the game hides/locks the cursor -> free + show it
}

-- ============================================================
--  TRACER FX  (self-contained port of the HC tracer)
-- ============================================================
local _activeTracers, MAX_TRACERS = 0, 12
local _lastTracerAt, MIN_TRACER_GAP = 0, 0.04
local _hlModel, _sharedHL
local function ensureTracerHL()
    if _hlModel and _hlModel.Parent and _sharedHL and _sharedHL.Parent then return end
    if _hlModel then pcall(function() _hlModel:Destroy() end) end
    _hlModel = Instance.new("Model"); _hlModel.Name = "\0_fh"; _hlModel.Parent = Workspace
    _sharedHL = Instance.new("Highlight")
    _sharedHL.FillTransparency = 0.2
    _sharedHL.OutlineColor, _sharedHL.OutlineTransparency = Color3.new(0, 0, 0), 0
    pcall(function() _sharedHL.Adornee = _hlModel end)
    _sharedHL.Parent = _hlModel
end
local function clearTracerHL()
    if _hlModel then pcall(function() _hlModel:Destroy() end); _hlModel = nil; _sharedHL = nil end
end
local function invisAnchor(pos)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
    p.Size, p.Transparency, p.CFrame = Vector3.new(0.05, 0.05, 0.05), 1, CFrame.new(pos)
    p.Name = "\0_fh"; p.Parent = Workspace
    return p
end
-- muzzle (barrel tip): the tool attachment furthest from our body, else camera
local function muzzlePos()
    local c = LocalPlayer.Character
    local tool = c and c:FindFirstChildOfClass("Tool")
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local ref = (hrp and hrp.Position) or (c and c:FindFirstChild("Head") and c.Head.Position)
    if tool and ref then
        local best, bestD
        for _, d in ipairs(tool:GetDescendants()) do
            if d:IsA("Attachment") then
                local dd = (d.WorldPosition - ref).Magnitude
                if not bestD or dd > bestD then bestD, best = dd, d.WorldPosition end
            end
        end
        if best then return best end
    end
    local cam = Workspace.CurrentCamera
    return cam and cam.CFrame.Position or (ref)
end
local function spawnTracer(origin, hitPos)
    if not (S.tracerEnabled and origin and hitPos) then return end
    local dist = (hitPos - origin).Magnitude
    if dist < 0.5 then return end
    local nowT = tick()
    if nowT - _lastTracerAt < MIN_TRACER_GAP then return end
    if _activeTracers >= MAX_TRACERS then return end
    _lastTracerAt, _activeTracers = nowT, _activeTracers + 1
    task.delay(math.max(1.5, S.tracerLifetime + 1), function()
        _activeTracers = math.max(0, _activeTracers - 1)
    end)

    local dir = (hitPos - origin).Unit
    local col, th = S.tracerColor, S.tracerThickness
    local TEX = "rbxassetid://446111271"
    local startPart, endPart = invisAnchor(origin), invisAnchor(origin)
    local att0 = Instance.new("Attachment", startPart)
    local att1 = Instance.new("Attachment", endPart)
    local beams = {}
    local function mkBeam(width, transp, textured, colSeq)
        local b = Instance.new("Beam")
        b.Attachment0, b.Attachment1 = att0, att1
        b.LightEmission, b.LightInfluence, b.FaceCamera, b.Segments = 1, 0, true, 4
        b.Width0, b.Width1 = width, width
        b.Color = colSeq or ColorSequence.new(col)
        b.Transparency = NumberSequence.new(transp or 0)
        if textured then pcall(function()
            b.Texture, b.TextureMode = TEX, Enum.TextureMode.Wrap
            b.TextureLength, b.TextureSpeed = 4, 12
        end) end
        b.Parent = startPart; beams[#beams + 1] = b; return b
    end
    local whiteHot = ColorSequence.new({
        ColorSequenceKeypoint.new(0, col), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, col) })
    if S.tracerStyle == "Laser" then
        mkBeam(th * 3.5, 0.6)
        mkBeam(th * 1.2, 0, false, whiteHot)
        mkBeam(th * 0.5, 0, true)
    elseif S.tracerStyle == "Thin" then
        mkBeam(th * 1.4, 0.7)
        mkBeam(th * 0.55, 0.05, true)
    else
        local outer = mkBeam(th * 5, nil)
        outer.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0.35),
            NumberSequenceKeypoint.new(1, 0.6) })
        mkBeam(th * 2.6, 0.25)
        mkBeam(th * 1.1, 0.02, true, whiteHot)
    end

    ensureTracerHL()
    pcall(function()
        _sharedHL.DepthMode = S.tracerThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        _sharedHL.FillColor = col
    end)
    local core = Instance.new("Part")
    core.Anchored, core.CanCollide, core.CanTouch, core.CanQuery, core.CastShadow = true, false, false, false, false
    core.Material, core.Color = Enum.Material.Neon, col
    local cth = math.max(th, 0.01)
    core.Size = Vector3.new(cth, cth, dist)
    core.CFrame = CFrame.lookAt((origin + hitPos) / 2, hitPos)
    core.Name = "\0_fh"; core.Parent = (_hlModel and _hlModel.Parent) and _hlModel or Workspace

    pcall(function()
        local mAtt = Instance.new("Attachment", startPart)
        local mLight = Instance.new("PointLight"); mLight.Color, mLight.Brightness, mLight.Range = col, 6, 9
        mLight.Parent = startPart
        local mp = Instance.new("ParticleEmitter")
        mp.Color, mp.LightEmission = ColorSequence.new(col), 1
        mp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, th * 4), NumberSequenceKeypoint.new(1, 0) })
        mp.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
        mp.Speed, mp.Lifetime = NumberRange.new(4, 10), NumberRange.new(0.08, 0.18)
        mp.Rate, mp.SpreadAngle = 0, Vector2.new(35, 35)
        mp.Parent = mAtt; mp:Emit(10)
        task.delay(0.12, function() if mLight.Parent then mLight.Brightness = 0 end end)
    end)
    local sparks
    pcall(function()
        local sAtt = Instance.new("Attachment", endPart)
        sparks = Instance.new("ParticleEmitter")
        sparks.Color, sparks.LightEmission = whiteHot, 1
        sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, th * 2), NumberSequenceKeypoint.new(1, 0) })
        sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
        sparks.Speed, sparks.Lifetime = NumberRange.new(2, 6), NumberRange.new(0.1, 0.25)
        sparks.Rate, sparks.SpreadAngle = 220, Vector2.new(20, 20)
        pcall(function() sparks.Texture = TEX end)
        sparks.Parent = sAtt
    end)

    task.spawn(function()
        for i = 1, 8 do
            task.wait(0.06 / 8)
            if not startPart.Parent then break end
            endPart.CFrame = CFrame.new(origin + dir * (dist * (i / 8)))
        end
        if endPart.Parent then endPart.CFrame = CFrame.new(hitPos) end
        if sparks then pcall(function() sparks.Rate = 0 end) end
        if startPart.Parent then
            local flash = invisAnchor(hitPos)
            flash.Transparency, flash.Material, flash.Color = 0, Enum.Material.Neon, col
            flash.Shape, flash.Size = Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6)
            local light = Instance.new("PointLight"); light.Color, light.Brightness, light.Range = col, 5, 10
            light.Parent = flash
            pcall(function()
                local att = Instance.new("Attachment", flash)
                local pe = Instance.new("ParticleEmitter")
                pe.Color, pe.LightEmission = whiteHot, 1
                pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, th * 3), NumberSequenceKeypoint.new(1, 0) })
                pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
                pe.Speed, pe.Lifetime = NumberRange.new(6, 16), NumberRange.new(0.15, 0.35)
                pe.Rate, pe.SpreadAngle = 0, Vector2.new(180, 180)
                pcall(function() pe.Texture = TEX end)
                pe.Parent = att; pe:Emit(18)
            end)
            task.spawn(function()
                for i = 1, 10 do
                    task.wait(0.22 / 10)
                    if not flash.Parent then return end
                    local p = i / 10; local s = 0.6 + p * 2.6
                    flash.Size, flash.Transparency, light.Brightness = Vector3.new(s, s, s), p, 5 * (1 - p)
                end
                if flash.Parent then flash:Destroy() end
            end)
        end
        for i = 1, 8 do
            task.wait(S.tracerLifetime / 8)
            if not startPart.Parent then break end
            local a = i / 8
            for _, b in ipairs(beams) do if b.Parent then b.Transparency = NumberSequence.new(a) end end
        end
        pcall(function() if startPart.Parent then startPart:Destroy() end end)
        pcall(function() if endPart.Parent then endPart:Destroy() end end)
        pcall(function() if core.Parent then core:Destroy() end end)
    end)
end

-- ---- kill sound (HC asset, played on a confirmed kill) ----
local function playKillSound()
    if not S.killSound or not S.killSoundId or S.killSoundId == 0 then return end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. tostring(S.killSoundId)
    s.Volume = math.clamp(S.soundVolume, 0, 5)
    s.Parent = pg or Workspace
    s:Play()
    task.delay(5, function() if s and s.Parent then s:Destroy() end end)
end

-- ============================================================
--  TARGET HELPERS
-- ============================================================
local function myChar() return LocalPlayer.Character end
-- a valid enemy = DEPLOYED (in the round, not sitting in the lobby) AND alive AND not
-- spawn-protected. The game exposes each player's deploy state as the "Deployed" attribute;
-- lobby players keep a full-HP character but Deployed=false, so HP alone isn't enough --
-- without this gate the silent aim fires at people who never spawned in.
local function aliveEnemy(p)
    if p == LocalPlayer then return nil end
    if p:GetAttribute("Deployed") ~= true then return nil end   -- lobby / not deployed
    local c = p.Character
    if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    if c:FindFirstChild("SpawnProtection") then return nil end
    return c, hum
end
local function aimPart(char)
    if S.headshot then return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
end
local function isPriority(p)
    if #S.priority == 0 then return false end
    local nm, dn = p.Name:lower(), (p.DisplayName or ""):lower()
    for _, frag in ipairs(S.priority) do
        if nm == frag or dn == frag or nm:find(frag, 1, true) or dn:find(frag, 1, true) then return true end
    end
    return false
end

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
    return res == nil or part:IsDescendantOf(res.Instance.Parent) or res.Instance == part
end

-- best engageable enemy; onlyPriority restricts to the priority list. No FOV cap --
-- it always picks SOMEONE in range; the mode only decides WHICH when several qualify:
--   "Closest to mouse"     -> nearest to the crosshair (on-screen first, then off-screen)
--   "Closest to character" -> nearest in world distance to our own body
local function pickClosest(onlyPriority)
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local origin = cam.CFrame.Position
    local mc = myChar()
    local myHRP = mc and mc:FindFirstChild("HumanoidRootPart")
    local myPos = myHRP and myHRP.Position
    local mouse = UserInputService:GetMouseLocation()
    local best, bestPart, bestScore = nil, nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if not onlyPriority or isPriority(p) then
            local char, hum = aliveEnemy(p)
            if char and hum then
                local part = aimPart(char)
                if part then
                    local d = (part.Position - origin).Magnitude   -- range is validated from the shot origin
                    if d <= S.maxDist and (not S.visibleCheck or hasLoS(origin, part)) then
                        local score
                        if S.mode == "Closest to character" then
                            score = myPos and (part.Position - myPos).Magnitude or d
                        else   -- Closest to mouse
                            local sp, on = cam:WorldToViewportPoint(part.Position)
                            score = on and (Vector2.new(sp.X, sp.Y) - mouse).Magnitude or (1e5 + d)
                        end
                        if score < bestScore then bestScore, best, bestPart = score, p, part end
                    end
                end
            end
        end
    end
    return best, bestPart
end
-- priority-first: shoot a DEPLOYED priority target if one exists, else anyone
local function bestTarget()
    if #S.priority > 0 then
        local p, part = pickClosest(true)
        if p then return p, part end
    end
    return pickClosest(false)
end

-- ============================================================
--  SILENT AIM  (auto-shoot the hidden buffer remote at the best target)
-- ============================================================
local function isDeployed()
    return LocalPlayer:GetAttribute("Deployed") == true
        and myChar() ~= nil
        and myChar():FindFirstChildOfClass("Tool") ~= nil
end

local function fireAt(part)
    if not ShootRemote or not part then return end
    local char = part:FindFirstAncestorWhichIsA("Model")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local dir = (part.Position - origin).Unit
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
    -- our own local energy tracer (muzzle -> hit)
    spawnTracer(muzzlePos(), part.Position)
    -- game's replicated tracer/muzzle so OTHER players see a shot along the same ray
    if S.replicateBullet then
        local mw = muzzlePos()
        if mw and FakeBulletRemote then
            local mdir = (part.Position - mw)
            mdir = (mdir.Magnitude > 1e-3) and mdir.Unit or dir
            pcall(function() FakeBulletRemote:FireServer(CFrame.new(mw, part.Position), mdir) end)
        end
        if MuzzleRemote then pcall(function() MuzzleRemote:FireServer() end) end
    end
    -- confirmed-kill watcher: one-shot-kill game, so if the target dies right after
    -- our shot the server accepted it -> play the kill sound (skips rejected shots)
    if S.killSound then
        local hpBefore = hum.Health
        task.spawn(function()
            local t0 = os.clock()
            while os.clock() - t0 < 0.5 do
                if hum.Health <= 0 then playKillSound(); return end
                task.wait()
            end
            if hpBefore > 0 and hum.Health <= 0 then playKillSound() end
        end)
    end
end

local _lastShot = 0
track(RunService.Heartbeat:Connect(function()
    if unloaded or not current() or not S.silent then return end
    if not isDeployed() then return end
    -- hard floor 1.0s no matter the config: server kicks for rapid fire below the reload
    if os.clock() - _lastShot < math.max(S.cooldown, 1.0) then return end
    local plr, part = bestTarget()
    if not plr or not part then return end
    _lastShot = os.clock()
    fireAt(part)
    local g = gv()
    if g and g.WH then g.WH.currentTarget = plr; g.WH.currentTargetT = os.clock() end
end))

-- ============================================================
--  AUTO DEPLOY  (event-driven -> fires the instant we drop out of deployed)
-- ============================================================
local _lastDeploy = 0
local function tryDeploy()
    if unloaded or not current() or not S.autoDeploy or not DeployRemote then return end
    if LocalPlayer:GetAttribute("Deployed") == true then return end
    if LocalPlayer:GetAttribute("Shooter_Client_Loaded") ~= true then return end
    local map = Workspace:FindFirstChild("LoadedMap")
    if map and map:GetAttribute("CanDeploy") == false then return end
    if os.clock() - _lastDeploy < 0.12 then return end   -- tiny anti-double-fire only
    _lastDeploy = os.clock()
    pcall(function() DeployRemote:FireServer() end)
end
-- the instant the game clears our Deployed flag (death / round reset)
track(LocalPlayer:GetAttributeChangedSignal("Deployed"):Connect(tryDeploy))
-- ...and the instant a starting round opens deploying (CanDeploy true while we're out)
do
    local map = Workspace:FindFirstChild("LoadedMap")
    if map then track(map:GetAttributeChangedSignal("CanDeploy"):Connect(tryDeploy)) end
end

-- ============================================================
--  3RD PERSON  (the game continuously re-forces CameraMode=LockFirstPerson while
--  deployed). We win by re-asserting Classic on RenderStepped, which runs BEFORE the
--  PlayerModule's camera update (RenderPriority.Camera=200) each frame -- so the camera
--  is computed from OUR mode. Writes only on change to avoid redundant property sets.
-- ============================================================
local function applyThirdPerson()
    pcall(function()
        if S.thirdPerson then
            if LocalPlayer.CameraMinZoomDistance ~= 0.5 then LocalPlayer.CameraMinZoomDistance = 0.5 end
            if LocalPlayer.CameraMaxZoomDistance ~= S.tpZoom then LocalPlayer.CameraMaxZoomDistance = S.tpZoom end
            if LocalPlayer.CameraMode ~= Enum.CameraMode.Classic then LocalPlayer.CameraMode = Enum.CameraMode.Classic end
        else
            if LocalPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson then
                LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
            end
        end
    end)
end
-- hide/show the on-screen viewmodel (hands + gun). The game animates its Transparency
-- (reload fade) and re-parents a fresh one on equip, so re-hide each frame via
-- LocalTransparencyModifier (client-only, overrides Transparency -> LTM=1 forces invisible).
local _vmHidden = false
local function setViewmodelHidden(hidden)
    local cam = Workspace.CurrentCamera
    local vm = cam and cam:FindFirstChild("Viewmodel")
    if not vm then return end
    local ltm = hidden and 1 or 0
    for _, d in ipairs(vm:GetDescendants()) do
        if d:IsA("BasePart") then
            if d.LocalTransparencyModifier ~= ltm then d.LocalTransparencyModifier = ltm end
        elseif d:IsA("Decal") or d:IsA("Texture") then
            if d.Transparency ~= ltm then d.Transparency = ltm end
        end
    end
    _vmHidden = hidden
end
track(RunService.RenderStepped:Connect(function()
    if unloaded or not current() or not S.thirdPerson then return end
    applyThirdPerson()
    if S.hideVM then setViewmodelHidden(true)
    elseif _vmHidden then setViewmodelHidden(false) end
end))

-- FREE THE MOUSE in 3rd person: the game locks the cursor (MouseBehavior=LockCenter,
-- icon hidden) for FP aiming and re-locks it LATER in the frame than RenderStepped, so
-- re-assert at RenderPriority.Last to win the fight (same trick the nhack menu uses).
RunService:BindToRenderStep("WH_PA_MouseFree", Enum.RenderPriority.Last.Value, function()
    if unloaded or not current() then return end
    if not (S.thirdPerson and S.freeMouse) then return end
    if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
    if not UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = true end
end)

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
    Sec:Dropdown({ Name = "Target", Flag = "PA_Mode", Default = "Closest to mouse", Multi = false,
        Items = { "Closest to mouse", "Closest to character" },
        Callback = function(v) S.mode = (type(v) == "table" and v[1]) or v or "Closest to mouse" end })
    Sec:Slider({ Name = "Max distance", Flag = "PA_MaxDist", Min = 50, Max = 1000, Default = 1000,
        Decimals = 0, Suffix = " studs", Callback = function(v) S.maxDist = v end })
    Sec:Toggle({ Name = "Headshots", Flag = "PA_Head", Default = true,
        Callback = function(v) S.headshot = v end })
    Sec:Toggle({ Name = "Visible check (LoS)", Flag = "PA_Vis", Default = false,
        Callback = function(v) S.visibleCheck = v end })
    Sec:Label({ Name = "no FOV -- always shoots; Target picks who" })

    local Sec2 = Combat:Section({ Name = "Behaviour", Side = 2 })
    Sec2:Slider({ Name = "Fire cooldown", Flag = "PA_Cooldown", Min = 1000, Max = 2000, Default = 1100,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.cooldown = v / 1000 end })
    Sec2:Label({ Name = "server kicks for rapid fire below ~1.1s (no bypass)" })
    Sec2:Toggle({ Name = "Replicate bullet (visual)", Flag = "PA_FakeBullet", Default = true,
        Callback = function(v) S.replicateBullet = v end })

    local SecP = Combat:Section({ Name = "Priority targets", Side = 2 })
    local startNames = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then startNames[#startNames + 1] = p.Name end
    end
    local prioDrop = SecP:Dropdown({ Name = "Priority players", Flag = "PA_Priority", Multi = true, Default = {},
        Items = startNames,
        Callback = function(v)
            local list = {}
            if type(v) == "table" then
                for _, nm in ipairs(v) do list[#list + 1] = tostring(nm):lower() end
            end
            S.priority = list
        end })
    SecP:Label({ Name = "shot first WHILE deployed; else it shoots anyone" })
    -- keep the option list in sync with who's actually in the server (preserves selections)
    track(Players.PlayerAdded:Connect(function(p)
        if p ~= LocalPlayer then pcall(function() prioDrop:Add(p.Name) end) end
    end))
    track(Players.PlayerRemoving:Connect(function(p)
        pcall(function() prioDrop:Remove(p.Name) end)
    end))

    local SecFX = Combat:Section({ Name = "Tracers + Sound", Side = 1 })
    SecFX:Toggle({ Name = "Bullet tracers", Flag = "PA_Tracers", Default = false,
        Callback = function(v) S.tracerEnabled = v; if not v then clearTracerHL() end end })
    SecFX:Dropdown({ Name = "Tracer style", Flag = "PA_TracerStyle", Default = "Standard", Multi = false,
        Items = { "Standard", "Laser", "Thin" },
        Callback = function(v) S.tracerStyle = (type(v) == "table" and v[1]) or v or "Standard" end })
    SecFX:Label({ Name = "Tracer color" }):Colorpicker({ Flag = "PA_TracerColor", Default = Color3.fromRGB(0, 255, 80),
        Callback = function(c) S.tracerColor = c end })
    SecFX:Toggle({ Name = "Through walls", Flag = "PA_TracerWalls", Default = true,
        Callback = function(v) S.tracerThroughWalls = v end })
    SecFX:Slider({ Name = "Size", Flag = "PA_TracerSize", Min = 0.02, Max = 1, Default = 0.12,
        Decimals = 2, Suffix = " studs", Callback = function(v) S.tracerThickness = v end })
    SecFX:Slider({ Name = "Lifetime", Flag = "PA_TracerLife", Min = 0.05, Max = 1, Default = 0.2,
        Decimals = 2, Suffix = " s", Callback = function(v) S.tracerLifetime = v end })
    SecFX:Toggle({ Name = "Kill sound", Flag = "PA_KillSound", Default = false,
        Callback = function(v) S.killSound = v end })
    SecFX:Slider({ Name = "Sound volume", Flag = "PA_SoundVol", Min = 0, Max = 300, Default = 100,
        Decimals = 0, Suffix = " %", Callback = function(v) S.soundVolume = v / 100 end })

    local SecCam = Combat:Section({ Name = "Camera", Side = 2 })
    SecCam:Toggle({ Name = "3rd person", Flag = "PA_ThirdPerson", Default = false,
        Callback = function(v)
            S.thirdPerson = v
            applyThirdPerson()
            if not v and _vmHidden then setViewmodelHidden(false) end   -- back to FP: show the viewmodel
        end })
    SecCam:Slider({ Name = "Zoom out max", Flag = "PA_TpZoom", Min = 5, Max = 40, Default = 15,
        Decimals = 0, Suffix = " studs", Callback = function(v) S.tpZoom = v; if S.thirdPerson then applyThirdPerson() end end })
    SecCam:Toggle({ Name = "Hide hands + gun", Flag = "PA_HideVM", Default = true,
        Callback = function(v) S.hideVM = v; if not v and _vmHidden then setViewmodelHidden(false) end end })
    SecCam:Toggle({ Name = "Free mouse", Flag = "PA_FreeMouse", Default = true,
        Callback = function(v) S.freeMouse = v end })
    SecCam:Label({ Name = "scroll out after enabling" })

    local Sec3 = Combat:Section({ Name = "Deploy", Side = 1 })
    Sec3:Toggle({ Name = "Auto deploy on death", Flag = "PA_AutoDeploy", Default = false,
        Callback = function(v) S.autoDeploy = v; if v then tryDeploy() end end })
    Sec3:Label({ Name = "instant -- re-deploys the frame you can" })
end

-- universal shell AFTER our page (so "Pistol Arena" stays the first tab): ESP +
-- Player movement etc. Movement is higher anti-cheat risk here than the silent aim.
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    unloaded = true
    S.silent, S.autoDeploy, S.tracerEnabled, S.killSound = false, false, false, false
    if _vmHidden then pcall(function() setViewmodelHidden(false) end) end       -- show the viewmodel
    if S.thirdPerson then S.thirdPerson = false; pcall(applyThirdPerson) end   -- restore first person
    pcall(function() RunService:UnbindFromRenderStep("WH_PA_MouseFree") end)
    pcall(clearTracerHL)
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
