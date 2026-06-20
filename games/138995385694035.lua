-- ============================================================
--  games/138995385694035.lua  --  Hood Customs
--
--  "Main" tab first, then the universal base. Subpages:
--    Combat   : Target, Force Hit, Auto Reload, Auto Stomp, Auto Stomp Targets
--    Ragebot  : Auto Shoot, Auto Equip, Voidshoot
--    Knife Bot: knife aura (attach/orbit) + auto-equip knife
--    Checks   : visible(+origin)/knocked/grabbed/forcefield/loaded -- global
--               target-validity filters respected by all targeting + shooting
--    Misc     : Anti-AFK badge, Force-AFK badge
--    Util     : Target Line, Target Outline
--
--  HC Shoot payload (witherhook, no-kick form -- origin==aim is a degenerate
--  ray so HC SKIPS its spread PRNG check; a real aim makes it kick for
--  "spoofing spread pattern"):
--    MainEvent:FireServer("Shoot", { hits, targets, origin, origin, stamp })
--    hits[i]    = { Normal = pos, Instance = part, Position = pos }
--    targets[i] = { thePart = part, theOffset = Vector3.zero }
--  Force Hit fires that synth at the current TARGET on each shoot-click, plus a
--  fake bullet tracer + hit sound. Auto Shoot fires the same synth automatically.
-- ============================================================
local ctx = ({ ... })[1]

local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS               = game:GetService("UserInputService")
local VIM               = game:GetService("VirtualInputManager")
local Workspace         = workspace
local LocalPlayer       = Players.LocalPlayer

local function gv() return (getgenv and getgenv()) or nil end

-- "Main" must come before the universal pages so it's the first tab.
local MainPage = Window:Page({ Name = "Main" })

local unloaded = false
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local function getMainEvent() return ReplicatedStorage:FindFirstChild("MainEvent") end

-- ============================================================
--  HC state (BodyEffects under workspace.Players.Characters.<name>)
-- ============================================================
local function hcModel(plr)
    local wsp = Workspace:FindFirstChild("Players")
    local chars = wsp and wsp:FindFirstChild("Characters")
    return (chars and chars:FindFirstChild(plr.Name)) or plr.Character
end
local function isKnocked(plr)
    local m = hcModel(plr)
    local fx = m and m:FindFirstChild("BodyEffects")
    local ko = fx and fx:FindFirstChild("K.O")
    return ko ~= nil and ko.Value == true
end
local function isDead(plr)
    local m = hcModel(plr)
    local fx = m and m:FindFirstChild("BodyEffects")
    local d = fx and fx:FindFirstChild("Dead")
    return d ~= nil and d.Value == true
end
local function isAlive(plr)
    local ch = plr and plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local HC = {
    -- target (multi-target lock list)
    autoSwitch = false, priority = "Closest to mouse",
    -- checks (Checks tab) -- respected by all targeting + shooting
    checkVisible = false, visibleOrigin = "Tool Handle",
    checkKnocked = false, checkGrabbed = false, checkFF = false, checkLoaded = false,
    -- force hit (fire the witherhook no-kick synth at the target on click) + FX
    forceHit = false, hitPart = "Head", forceHitCooldown = 0.18, wallbang = false, wallbangOffset = 12,
    tracerEnabled = true, tracerColor = Color3.fromRGB(0, 255, 80),
    tracerStyle = "Standard", tracerLifetime = 0.2, tracerThickness = 0.12,
    hitSoundEnabled = true, hitSoundId = 121566025787365, hitSoundVolume = 1.0,
    ammoHud = false,
    autoShoot = false, autoShootDist = 250, autoShootCooldown = 0.15, autoShootVis = true,
    autoEquip = false, autoEquipTool = "",
    voidshoot = false,
    -- stomp / reload
    stomp = false, stompTargets = false, stompRadius = 5,
    reload = false, reloadKey = Enum.KeyCode.R, reloadThreshold = 0,
    -- knife bot
    knifeAura = false, knifeDist = 3, knifeInterval = 0.6, knifeOrbit = false, knifeOrbitSpeed = 180,
    knifeEquip = false,
    -- afk
    antiAfk = false, forceAfk = false,
    -- visuals
    targetLine = false, lineOrigin = "Bottom", lineColor = Color3.fromRGB(255, 60, 60),
    targetOutline = false, outlineColor = Color3.fromRGB(255, 80, 80),
}

-- ============================================================
--  Target system  (MULTI-target lock list -- Lock adds the priority pick to the
--  list, Unlock clears it. getTarget() picks the best valid entry from the list
--  by priority; with an empty list it only auto-acquires if Auto switch is on.)
-- ============================================================
local RageTargets = {}

local function targetParts(char)
    return char:FindFirstChild(HC.hitPart) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end
-- ---- per-player CHECKS (Checks tab) -- respected by all targeting + shooting ----
local function isGrabbed(plr)
    local m = hcModel(plr)
    local fx = m and m:FindFirstChild("BodyEffects")
    local g = fx and fx:FindFirstChild("Grabbed")
    return g ~= nil and g.Value ~= nil
end
local function hasForceField(plr)
    local ch = plr.Character
    if ch and ch:FindFirstChildOfClass("ForceField") then return true end
    local m = hcModel(plr)
    return m ~= nil and m:FindFirstChildOfClass("ForceField") ~= nil
end
local function isLoadedIn(plr)
    local ch, m = plr.Character, hcModel(plr)
    return (ch ~= nil and ch:FindFirstChild("FULLY_LOADED_CHAR") ~= nil)
        or (m ~= nil and m:FindFirstChild("FULLY_LOADED_CHAR") ~= nil)
end
local function visOrigin()
    local mode = HC.visibleOrigin
    if mode == "Camera" then return Workspace.CurrentCamera.CFrame.Position end
    local c = LocalPlayer.Character
    if mode == "Tool Handle" then
        -- check LoS from where the gun actually is; falls through to Head if unequipped
        local tool = c and c:FindFirstChildOfClass("Tool")
        local handle = tool and (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart"))
        if handle then return handle.Position end
    end
    if mode == "Root" then local r = c and c:FindFirstChild("HumanoidRootPart"); return r and r.Position end
    local h = c and c:FindFirstChild("Head"); return h and h.Position  -- "Head" (default + Tool-Handle fallback)
end
local function isVisible(plr)
    local m = hcModel(plr)
    local aim = m and (m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head"))
    if not aim then return false end
    local origin = visOrigin(); if not origin then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    local lc = LocalPlayer.Character; if lc then ignore[#ignore + 1] = lc end
    local ig = Workspace:FindFirstChild("Ignored"); if ig then ignore[#ignore + 1] = ig end
    params.FilterDescendantsInstances = ignore
    local res = Workspace:Raycast(origin, aim.Position - origin, params)
    if not res then return true end          -- nothing in the way
    return res.Instance:IsDescendantOf(m)     -- first hit is the target = visible
end
-- persistent state checks (used for validity + lock-list membership)
local function passesChecks(plr)
    if HC.checkKnocked and isKnocked(plr) then return false end
    if HC.checkGrabbed and isGrabbed(plr) then return false end
    if HC.checkFF and hasForceField(plr) then return false end
    if HC.checkLoaded and not isLoadedIn(plr) then return false end
    return true
end

-- base validity (alive, not dead). Deliberately does NOT apply the checks, so a
-- locked target stays in the list even while knocked/occluded/etc. -- otherwise
-- the knocked check would yank stomp targets out of the list the moment they go down.
local function validTarget(plr)
    if not plr or plr == LocalPlayer or not plr.Parent then return false end
    if not isAlive(plr) then return false end
    if isDead(plr) then return false end
    return plr.Character ~= nil and plr.Character:FindFirstChild("HumanoidRootPart") ~= nil
end
-- engageable right now = valid AND passes every enabled check (state + visibility).
-- This is what all targeting/shooting selects on.
local function canEngage(plr)
    if not validTarget(plr) then return false end
    if not passesChecks(plr) then return false end
    if HC.checkVisible and not isVisible(plr) then return false end
    return true
end

-- screen-space distance from the mouse to a player (math.huge if off-screen)
local function mouseDist(plr)
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return math.huge end
    local sp, on = Workspace.CurrentCamera:WorldToViewportPoint(hrp.Position)
    if not on then return math.huge end
    return (UIS:GetMouseLocation() - Vector2.new(sp.X, sp.Y)).Magnitude
end

-- score a LOCKED target by the chosen priority (lower = preferred)
local function scorePlayer(plr)
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return math.huge end
    local mode = HC.priority
    if mode == "Lowest HP" then
        local hum = char:FindFirstChildOfClass("Humanoid")
        return hum and hum.Health or math.huge
    elseif mode == "Closest to me" then
        local lc = LocalPlayer.Character
        local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
        return lhrp and (lhrp.Position - hrp.Position).Magnitude or math.huge
    end
    -- "Closest to mouse" (default)
    return mouseDist(plr)
end

-- multi-target lock list
local function isLocked(plr)
    for _, p in ipairs(RageTargets) do if p == plr then return true end end
    return false
end
-- Lock ALWAYS adds the player nearest the mouse. Uses base validity only (NOT the
-- checks) -- you can lock a knocked / occluded player; the checks only decide who
-- gets CHOSEN to shoot, never who's allowed in the list.
local function lockTarget()
    local best, bestD = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if validTarget(plr) and not isLocked(plr) then
            local d = mouseDist(plr)
            if d < bestD then bestD = d; best = plr end
        end
    end
    if best then RageTargets[#RageTargets + 1] = best end
end
local function clearTargets() table.clear(RageTargets) end
-- ONLY drop players who actually left the game. Knocked / dead / respawning /
-- occluded targets stay locked -- canEngage() decides whether to shoot them, so a
-- target you down (or the knocked check skips) is never yanked out of the list.
local function liveTargets()
    local i = 1
    while i <= #RageTargets do
        local p = RageTargets[i]
        if p and p.Parent then i = i + 1 else table.remove(RageTargets, i) end
    end
    return RageTargets
end

-- current engageable target: best by priority among the locked list (or everyone
-- if Auto switch is on), filtered by ALL checks incl. visibility.
-- ignoreChecks=true skips the checks (validity only) -- used by the target visualizer
-- so the line/outline keep showing the locked target even when it fails the checks.
local function getTarget(ignoreChecks)
    local locked = liveTargets()
    local pool
    if #locked > 0 then pool = locked
    elseif HC.autoSwitch then pool = Players:GetPlayers()
    else return nil end
    local filter = ignoreChecks and validTarget or canEngage
    local best, bestScore = nil, math.huge
    for _, plr in ipairs(pool) do
        if filter(plr) then
            local s = scorePlayer(plr)
            if s < bestScore then bestScore = s; best = plr end
        end
    end
    return best
end

-- publish to the shared Target Indicator widget
local function publishTarget(plr)
    local g = gv()
    if g and g.WH then g.WH.currentTarget = plr; g.WH.currentTargetT = os.clock() end
end

-- ============================================================
--  Synthetic Shoot payload (no spread by construction)
-- ============================================================
local function isShotgun()
    local t = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not t then return false end
    local n = t.Name:lower()
    return n:find("shotgun", 1, true) ~= nil or n:find("barrel", 1, true) ~= nil
end
-- Canonical witherhook HC Shoot payload. pelletCount IDENTICAL entries all on
-- the SAME part, origin == aim (both = HRP, or the spoofed spot during a
-- voidshoot desync). The degenerate origin==aim ray makes HC SKIP its per-shot
-- spread PRNG check -- sending a non-degenerate aim (real bulletOrigin->target)
-- makes the server validate spread and KICK for "spoofing spread pattern".
-- Normal is set to the hit position (not a unit vector) to match exactly.
local function fireShootAt(part)
    if not part then return false end
    local me = getMainEvent(); if not me then return false end
    local c = LocalPlayer.Character
    local root = c and c:FindFirstChild("HumanoidRootPart"); if not root then return false end
    local pellets = isShotgun() and 5 or 1
    -- origin = where the server thinks we are (spoofed point-blank during voidshoot).
    -- It MUST equal our replicated position or the server throws "origin mismatch".
    local g = gv()
    local sent = g and g._WH_HC_SENT
    local origin = (sent and sent.Position) or root.Position
    -- WALLBANG: the server raycasts origin -> the hit on the part, and a blocked
    -- LoS = "wallbang". The hit must stay on the part (faking the Position errors),
    -- so instead we NUDGE origin a few studs toward the target -- enough to clear
    -- thin cover / a corner without moving far enough to trip "origin mismatch".
    -- Tune HC.wallbangOffset until it lands without an error. Skipped while
    -- voidshooting (origin is already point-blank on the target).
    if HC.wallbang and not sent then
        local toTarget = part.Position - origin
        local d = toTarget.Magnitude
        if d > 0 then
            origin = origin + toTarget.Unit * math.min(HC.wallbangOffset, math.max(0, d - 2))
        end
    end
    local hitPos = part.Position
    local hits, targets = table.create(pellets), table.create(pellets)
    for i = 1, pellets do
        hits[i]    = { Normal = hitPos, Instance = part, Position = hitPos }
        targets[i] = { thePart = part, theOffset = part.CFrame:PointToObjectSpace(hitPos) }
    end
    -- aim == origin keeps the spread PRNG check happy (degenerate ray).
    local payload = { hits, targets, origin, origin, Workspace:GetServerTimeNow() }
    return pcall(function() me:FireServer("Shoot", payload) end)
end

-- ============================================================
--  FORCE-HIT FX  -- fake bullet tracers + hit sound (ported from witherhook).
--  The synth Shoot never touches the gun script, so it renders no bullet
--  visuals -- we fake them locally. All local-only, with anti-freeze caps.
-- ============================================================
local _activeTracers, MAX_TRACERS = 0, 10
local _lastTracerAt, MIN_TRACER_GAP = 0, 0.05
local function muzzlePos()
    local c = LocalPlayer.Character
    local tool = c and c:FindFirstChildOfClass("Tool")
    local handle = tool and (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart"))
    if handle then return handle.Position end
    local h = c and c:FindFirstChild("Head")
    return h and h.Position
end
local function spawnTracer(origin, hitPos)
    if not (HC.tracerEnabled and origin and hitPos) then return end
    local dist = (hitPos - origin).Magnitude
    if dist < 0.5 then return end
    local nowT = tick()
    if nowT - _lastTracerAt < MIN_TRACER_GAP then return end
    if _activeTracers >= MAX_TRACERS then return end
    _lastTracerAt, _activeTracers = nowT, _activeTracers + 1
    task.delay(math.max(1.5, HC.tracerLifetime + 1), function()
        _activeTracers = math.max(0, _activeTracers - 1)
    end)
    local dir = (hitPos - origin).Unit
    local col = HC.tracerColor
    local function invisAnchor(pos)
        local p = Instance.new("Part")
        p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
        p.Size, p.Transparency, p.CFrame = Vector3.new(0.05, 0.05, 0.05), 1, CFrame.new(pos)
        p.Parent = Workspace
        return p
    end
    local startPart = invisAnchor(origin); startPart.Name = "_fh_tracer"
    local endPart = invisAnchor(origin); endPart.Name = "_fh_tracer"
    local att0 = Instance.new("Attachment", startPart)
    local att1 = Instance.new("Attachment", endPart)
    local beams = {}
    local function mkBeam()
        local b = Instance.new("Beam")
        b.Attachment0, b.Attachment1 = att0, att1
        b.LightEmission, b.LightInfluence, b.FaceCamera, b.Segments = 1, 0, true, 1
        b.Parent = startPart; beams[#beams + 1] = b; return b
    end
    local th = HC.tracerThickness
    if HC.tracerStyle == "Laser" then
        local b = mkBeam(); b.Width0, b.Width1 = th * 1.2, th * 1.2
        b.Color, b.Transparency = ColorSequence.new(col), NumberSequence.new(0)
    elseif HC.tracerStyle == "Thin" then
        local b = mkBeam(); b.Width0, b.Width1 = th * 0.6, th * 0.6
        b.Color, b.Transparency = ColorSequence.new(col), NumberSequence.new(0.1)
    else  -- Standard: outer halo + white-hot inner core
        local outer = mkBeam(); outer.Width0, outer.Width1 = th * 5, th * 4
        outer.Color = ColorSequence.new(col)
        outer.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0.35),
            NumberSequenceKeypoint.new(1, 0.55) })
        local inner = mkBeam(); inner.Width0, inner.Width1 = th * 1.8, th * 1.2
        inner.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, col), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, col) })
        inner.Transparency = NumberSequence.new(0.05)
        pcall(function()
            inner.Texture, inner.TextureMode = "rbxassetid://446111271", Enum.TextureMode.Wrap
            inner.TextureLength, inner.TextureSpeed = 6, 8
        end)
    end
    task.spawn(function()
        for i = 1, 8 do  -- travel: extend end attachment origin -> hit
            task.wait(0.06 / 8)
            if not startPart.Parent then return end
            endPart.CFrame = CFrame.new(origin + dir * (dist * (i / 8)))
        end
        if not startPart.Parent then return end
        endPart.CFrame = CFrame.new(hitPos)
        -- impact: neon ball + light, expand & fade
        local flash = invisAnchor(hitPos)
        flash.Transparency, flash.Material, flash.Color = 0, Enum.Material.Neon, col
        flash.Shape, flash.Size = Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6)
        local light = Instance.new("PointLight"); light.Color, light.Brightness, light.Range = col, 5, 10
        light.Parent = flash
        task.spawn(function()
            for i = 1, 10 do
                task.wait(0.22 / 10)
                if not flash.Parent then return end
                local p = i / 10; local s = 0.6 + p * 2.6
                flash.Size, flash.Transparency, light.Brightness = Vector3.new(s, s, s), p, 5 * (1 - p)
            end
            if flash.Parent then flash:Destroy() end
        end)
        for i = 1, 8 do  -- fade beams
            task.wait(HC.tracerLifetime / 8)
            if not startPart.Parent then return end
            for _, b in ipairs(beams) do if b.Parent then b.Transparency = NumberSequence.new(i / 8) end end
        end
        if startPart.Parent then startPart:Destroy() end
        if endPart.Parent then endPart:Destroy() end
    end)
end
local function playHitSound()
    if not HC.hitSoundEnabled or not HC.hitSoundId or HC.hitSoundId == 0 then return end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. tostring(HC.hitSoundId)
    s.Volume = math.clamp(HC.hitSoundVolume, 0, 5)
    s.Parent = pg or Workspace
    s:Play()
    task.delay(5, function() if s and s.Parent then s:Destroy() end end)
end
-- shared synth fire + FX. For shotguns, retarget to the torso (largest flat
-- area, and head shots trip HC's per-shot damage cap) like witherhook.
local function forceShotPart(char)
    if isShotgun() then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("LowerTorso") or char:FindFirstChild("HumanoidRootPart")
            or targetParts(char)
    end
    return targetParts(char)
end
-- ============================================================
--  EVENT-DRIVEN FX  -- the synth never renders gun visuals, so we fake the
--  tracer + hit sound off the gun's SERVER ammo (Script.Ammo) dropping. The
--  server decrements that on EVERY shot it accepts -- manual AND our synth -- so
--  one ammo-drop == one real shot. Hit sound only when the engaged target loses
--  HP within a short window of that drop.
-- ============================================================
local FX_WINDOW = 0.6
local _shotT = 0  -- tick() of the last real shot (server ammo decrement)

local function equippedGunScript()
    local c = LocalPlayer.Character
    local tool = c and c:FindFirstChildOfClass("Tool")
    return tool and tool:FindFirstChild("Script")
end
-- the SERVER ammo value (Script.Ammo) -- drops once per server-accepted shot
local function findServerAmmo()
    local scr = equippedGunScript()
    local ammo = scr and scr:FindFirstChild("Ammo")
    if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then return ammo end
    return nil
end

-- stamp a shot (so the hit-sound watcher fires) and draw a tracer to hitPos
local function fxShotFired(hitPos)
    _shotT = tick()
    if not HC.tracerEnabled or not hitPos then return end
    local origin = muzzlePos(); if not origin then return end
    spawnTracer(origin, hitPos)
end

-- a real shot landed (server ammo dropped): tracer to the engaged target, else crosshair
local function onAmmoShot()
    local hitPos
    local plr = getTarget()
    local part = plr and plr.Character and forceShotPart(plr.Character)
    if part then hitPos = part.Position end
    if not hitPos then
        local cam = Workspace.CurrentCamera
        local mp = UIS:GetMouseLocation()
        local ray = cam:ViewportPointToRay(mp.X, mp.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignore = {}
        local lc = LocalPlayer.Character; if lc then ignore[#ignore + 1] = lc end
        local ig = Workspace:FindFirstChild("Ignored"); if ig then ignore[#ignore + 1] = ig end
        params.FilterDescendantsInstances = ignore
        local res = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
        hitPos = (res and res.Position) or (ray.Origin + ray.Direction * 300)
    end
    fxShotFired(hitPos)
end

-- ammo watcher: re-attaches when the equipped gun changes; each decrease = one shot
local _watchedAmmo, _watchedAmmoConn, _watchedAmmoLast
local function ensureAmmoWatch()
    local av = findServerAmmo()
    if av == _watchedAmmo then return end
    if _watchedAmmoConn then _watchedAmmoConn:Disconnect(); _watchedAmmoConn = nil end
    _watchedAmmo = av
    if not av then return end
    _watchedAmmoLast = av.Value
    _watchedAmmoConn = av:GetPropertyChangedSignal("Value"):Connect(function()
        local newV, old = av.Value, _watchedAmmoLast
        _watchedAmmoLast = newV
        if old and newV < old then onAmmoShot() end
    end)
end

-- target-humanoid watcher: HP drop within FX_WINDOW of a shot = a confirmed hit
local _watchedHum, _watchedHumConn, _watchedHumLast
local function ensureHumWatch()
    local plr = getTarget()
    local hum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
    if hum == _watchedHum then return end
    if _watchedHumConn then _watchedHumConn:Disconnect(); _watchedHumConn = nil end
    _watchedHum = hum
    if not hum then return end
    _watchedHumLast = hum.Health
    _watchedHumConn = hum.HealthChanged:Connect(function(newHP)
        local old = _watchedHumLast
        _watchedHumLast = newHP
        if old and newHP < old - 0.01 and (tick() - _shotT < FX_WINDOW) then
            playHitSound()
        end
    end)
end

-- ============================================================
--  FAKE AMMO HUD  -- Force Hit / Auto Shoot spend SERVER ammo (Script.Ammo) but
--  never the client counter the game's own HUD shows, so your real count is
--  hidden. This panel shows the REAL (server) ammo, with the client value too.
-- ============================================================
local ammoGui, ammoMainLbl, ammoSubLbl
local function destroyAmmoHud()
    if ammoGui then pcall(function() ammoGui:Destroy() end); ammoGui = nil end
end
local function ensureAmmoHud()
    if ammoGui and ammoGui.Parent then return end
    ammoGui = Instance.new("ScreenGui")
    ammoGui.Name = "_wh_ammo_hud"
    ammoGui.ResetOnSpawn = false
    ammoGui.IgnoreGuiInset = true
    local ok = pcall(function() ammoGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not ammoGui.Parent then ammoGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    local frame = Instance.new("Frame")
    frame.Size, frame.AnchorPoint = UDim2.fromOffset(150, 56), Vector2.new(1, 1)
    frame.Position = UDim2.new(1, -20, 1, -120)
    frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = Color3.fromRGB(15,15,15), 0.35, 0
    frame.Parent = ammoGui
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = frame
    local stroke = Instance.new("UIStroke"); stroke.Color, stroke.Transparency = Color3.fromRGB(80,80,80), 0.4; stroke.Parent = frame
    ammoMainLbl = Instance.new("TextLabel")
    ammoMainLbl.Size, ammoMainLbl.Position = UDim2.new(1,-8,0,30), UDim2.new(0,4,0,4)
    ammoMainLbl.BackgroundTransparency, ammoMainLbl.TextColor3 = 1, Color3.fromRGB(255,255,255)
    ammoMainLbl.TextStrokeTransparency, ammoMainLbl.TextSize, ammoMainLbl.Font = 0.5, 22, Enum.Font.GothamBold
    ammoMainLbl.Text, ammoMainLbl.Parent = "-", frame
    ammoSubLbl = Instance.new("TextLabel")
    ammoSubLbl.Size, ammoSubLbl.Position = UDim2.new(1,-8,0,16), UDim2.new(0,4,0,36)
    ammoSubLbl.BackgroundTransparency, ammoSubLbl.TextColor3 = 1, Color3.fromRGB(180,180,180)
    ammoSubLbl.TextSize, ammoSubLbl.Font = 12, Enum.Font.Gotham
    ammoSubLbl.Text, ammoSubLbl.Parent = "real ammo", frame
end
local function updateAmmoHud()
    if not HC.ammoHud then if ammoGui then destroyAmmoHud() end return end
    ensureAmmoHud()
    local scr = equippedGunScript()
    local ammo = scr and scr:FindFirstChild("Ammo")
    if not (ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue"))) then
        ammoMainLbl.Text = "—"; ammoSubLbl.Text = "no gun equipped"; return
    end
    local maxV    = scr:FindFirstChild("MaxAmmo")
    local clientV = ammo:FindFirstChild("CLIENT")
    ammoMainLbl.Text = tostring(ammo.Value) .. ((maxV and maxV.Value) and (" / " .. tostring(maxV.Value)) or "")
    ammoSubLbl.Text  = "real ammo  (client " .. (clientV and tostring(clientV.Value) or "?") .. ")"
end

-- keep watchers + ammo HUD attached to the current gun / target (cheap when idle)
local _fxEnsureLast = 0
track(RunService.Heartbeat:Connect(function()
    if tick() - _fxEnsureLast < 0.15 then return end
    _fxEnsureLast = tick()
    ensureAmmoWatch()
    ensureHumWatch()
    updateAmmoHud()
end))

-- ============================================================
--  FORCE HIT  -- on each shoot-click while holding a gun, fire the witherhook
--  no-kick synth Shoot at the CURRENT TARGET (target system) + tracer + hit
--  sound. origin==aim makes HC skip its spread check so it never kicks. The
--  natural shot still plays its own visuals; this guarantees the hit on target.
-- ============================================================
local function setForceHit(on) HC.forceHit = on end
local _fhLast = 0
track(UIS.InputBegan:Connect(function(input, gpe)
    if gpe or not HC.forceHit then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local lc = LocalPlayer.Character
    if not lc or not lc:FindFirstChildOfClass("Tool") then return end   -- holding a gun
    if tick() - _fhLast < HC.forceHitCooldown then return end
    local plr = getTarget(); if not plr then return end
    local char = plr.Character; if not char then return end
    local part = forceShotPart(char); if not part then return end
    _fhLast = tick()
    publishTarget(plr)
    fireShootAt(part)
end))

-- ============================================================
--  AUTO SHOOT  -- fire the no-spread payload at the target whenever it's
--  hittable. Independent of Force Hit (which only de-spreads).
-- ============================================================
local _asLast = 0
local function tryEquipNamed(name)
    if name == "" then return end
    local lc = LocalPlayer.Character
    local hum = lc and lc:FindFirstChildOfClass("Humanoid")
    local held = lc and lc:FindFirstChildOfClass("Tool")
    if held and held.Name == name then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local tool = bp and bp:FindFirstChild(name)
    if tool and hum then pcall(function() hum:EquipTool(tool) end) end
end

-- ============================================================
--  VOIDSHOOT  -- desync our replicated root onto the target so shots
--  validate point-blank, then auto-fire. Restores our real pose each
--  RenderStep so we don't actually move locally.
-- ============================================================
local _vsSaved = nil
local function voidGlue(targetHrp)
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp or not targetHrp then return end
    _vsSaved = lhrp.CFrame
    local onTop = CFrame.new(targetHrp.Position)
    pcall(function() lhrp.CFrame = onTop end)
    local g = gv(); if g then g._WH_HC_SENT = onTop end
end
local function voidUnglue()
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if lhrp and _vsSaved then pcall(function() lhrp.CFrame = _vsSaved end) end
    local g = gv(); if g then g._WH_HC_SENT = nil end
    _vsSaved = nil
end
-- restore our real pose every frame so voidshoot stays put locally
RunService:BindToRenderStep("WH_HC_VS_RESTORE", Enum.RenderPriority.First.Value, function()
    if HC.voidshoot and _vsSaved then
        local lc = LocalPlayer.Character
        local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
        if lhrp then pcall(function() lhrp.CFrame = _vsSaved end) end
    end
end)

-- main shoot loop (auto shoot + voidshoot)
track(RunService.Heartbeat:Connect(function()
    if not (HC.autoShoot or HC.voidshoot) then return end
    if tick() - _asLast < HC.autoShootCooldown then return end
    local plr = getTarget()
    if not plr then voidUnglue(); return end
    publishTarget(plr)
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return end
    if (lhrp.Position - hrp.Position).Magnitude > HC.autoShootDist then return end
    if HC.autoShootVis and char:FindFirstChildOfClass("ForceField") then return end
    if HC.autoEquip and HC.autoEquipTool ~= "" then tryEquipNamed(HC.autoEquipTool) end
    local part = forceShotPart(char); if not part then return end
    _asLast = tick()
    if HC.voidshoot then
        voidGlue(hrp)
        fireShootAt(part)
        task.delay(0.05, function() if HC.voidshoot then voidUnglue() end end)
    else
        fireShootAt(part)
    end
    -- FX (tracer + hit sound) are NOT triggered here -- they fire off the SERVER
    -- ammo dropping (one per accepted shot), so auto shoot no longer spams tracers.
end))

-- ============================================================
--  AUTO STOMP  (+ targets mode = only stomp the ragebot target list)
-- ============================================================
local function someoneBelow(onlyTarget)
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and (not onlyTarget or isLocked(p)) then
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and isKnocked(p) and not isDead(p) then
                local d = lhrp.Position - hrp.Position
                if Vector2.new(d.X, d.Z).Magnitude <= HC.stompRadius and d.Y <= 7 and d.Y >= -1 then
                    return true
                end
            end
        end
    end
    return false
end
local _stompLast = 0
track(RunService.Heartbeat:Connect(function()
    if not (HC.stomp or HC.stompTargets) then return end
    if tick() - _stompLast < 0.1 then return end
    local me = getMainEvent(); if not me then return end
    if not someoneBelow(HC.stompTargets and not HC.stomp) then return end
    _stompLast = tick()
    pcall(function() me:FireServer("Stomp") end)
end))

-- ============================================================
--  AUTO RELOAD
-- ============================================================
local function getAmmo()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local script = tool and tool:FindFirstChild("Script")
    local ammo = script and script:FindFirstChild("Ammo")
    if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then return ammo end
    return nil
end
local _reloadLast = 0
track(RunService.Heartbeat:Connect(function()
    if not HC.reload then return end
    if tick() - _reloadLast < 1.5 then return end
    local ammo = getAmmo(); if not ammo then return end
    if ammo.Value > HC.reloadThreshold then return end
    _reloadLast = tick()
    pcall(function()
        VIM:SendKeyEvent(true, HC.reloadKey, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, HC.reloadKey, false, game)
    end)
end))

-- ============================================================
--  KNIFE BOT  -- attach/orbit the target + auto-click; auto-equip knife
-- ============================================================
local KNIFE_NAME = "[Knife]"
local _knifeOrbitAngle = 0
local function knifeTargetHrp()
    local plr = getTarget()
    local char = plr and plr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
track(RunService.Heartbeat:Connect(function(dt)
    if not HC.knifeAura then return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    local tHrp = knifeTargetHrp()
    if not lhrp or not tHrp then return end
    local tPos = tHrp.Position
    if tPos ~= tPos or tPos.Magnitude > 1e6 then return end
    local pos
    if HC.knifeOrbit then
        _knifeOrbitAngle = (_knifeOrbitAngle + HC.knifeOrbitSpeed * dt) % 360
        local rad = math.rad(_knifeOrbitAngle)
        pos = tPos + Vector3.new(math.cos(rad), 0, math.sin(rad)) * HC.knifeDist
    else
        pos = tPos - tHrp.CFrame.LookVector * HC.knifeDist
    end
    local move = pos - lhrp.Position
    if move.Magnitude > 60 then pos = lhrp.Position + move.Unit * 60 end
    if pos == pos and (pos - tPos).Magnitude >= 0.5 then
        pcall(function() lhrp.CFrame = CFrame.new(pos, tPos) end)
    end
end))
-- knife swing clicker
task.spawn(function()
    while not unloaded do
        if HC.knifeAura and knifeTargetHrp() then
            pcall(function()
                VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
            end)
            task.wait(HC.knifeInterval)
        else
            task.wait(0.1)
        end
    end
end)
local function tryEquipKnife()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or char:FindFirstChild(KNIFE_NAME) then return end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local tool = bp and bp:FindFirstChild(KNIFE_NAME)
    if tool then pcall(function() hum:EquipTool(tool) end) end
end
task.spawn(function()
    while not unloaded do
        if HC.knifeEquip then tryEquipKnife() end
        task.wait(0.25)
    end
end)

-- ============================================================
--  AFK BADGES  (MainEvent RequestAFKDisplay + watch HRP.CharacterAFK)
-- ============================================================
local function setAfkDisplay(state)
    local me = getMainEvent()
    if me then pcall(function() me:FireServer("RequestAFKDisplay", state) end) end
end
track(RunService.Heartbeat:Connect(function()
    if not (HC.antiAfk or HC.forceAfk) then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local gui = hrp and hrp:FindFirstChild("CharacterAFK")
    local shown = gui and gui.Enabled
    if HC.forceAfk and not shown then setAfkDisplay(true)
    elseif HC.antiAfk and shown then setAfkDisplay(false) end
end))

-- ============================================================
--  TARGET VISUALS  (Drawing.Line + Highlight on the ragebot target)
-- ============================================================
local hasDrawing = (Drawing ~= nil and Drawing.new ~= nil)
local rbLine, rbHL
if hasDrawing then
    rbLine = Drawing.new("Line")
    rbLine.Visible, rbLine.Thickness, rbLine.Transparency = false, 2, 1
end
local function ensureHL()
    if rbHL and rbHL.Parent then return rbHL end
    rbHL = Instance.new("Highlight")
    rbHL.FillTransparency = 1
    rbHL.OutlineTransparency = 0
    rbHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    rbHL.Enabled = false
    pcall(function() rbHL.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not rbHL.Parent then rbHL.Parent = Workspace end
    return rbHL
end
track(RunService.RenderStepped:Connect(function()
    local plr = (HC.targetLine or HC.targetOutline) and getTarget(true) or nil  -- visuals ignore checks
    local char = plr and plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    -- line
    if rbLine then
        if HC.targetLine and hrp then
            local cam = Workspace.CurrentCamera
            local sp = cam:WorldToViewportPoint(hrp.Position)
            local vs = cam.ViewportSize
            local from
            local o = HC.lineOrigin
            if o == "Top" then from = Vector2.new(vs.X * 0.5, 0)
            elseif o == "Center" then from = Vector2.new(vs.X * 0.5, vs.Y * 0.5)
            elseif o == "Mouse" then from = UIS:GetMouseLocation()
            else from = Vector2.new(vs.X * 0.5, vs.Y) end
            rbLine.From = from
            rbLine.To = Vector2.new(sp.X, sp.Y)
            rbLine.Color = HC.lineColor
            rbLine.Visible = sp.Z > 0
        else
            rbLine.Visible = false
        end
    end
    -- outline
    if HC.targetOutline and char then
        local hl = ensureHL()
        if hl.Adornee ~= char then hl.Adornee = char end
        hl.OutlineColor = HC.outlineColor
        hl.Enabled = true
    elseif rbHL then
        rbHL.Enabled = false
    end
end))

-- ============================================================
--  UI  (Main tab -- 5 subpages)
-- ============================================================

-- 1) Combat
local CombatSub = MainPage:SubPage({ Name = "Combat" })
do
    local Sec = CombatSub:Section({ Name = "Target", Side = 1 })
    Sec:Label({ Name = "Lock targets" }):Keybind({ Name = "Lock targets", Flag = "HC_LockKey", Mode = "Hold", Default = Enum.KeyCode.C,
        Callback = function(state) if state then lockTarget() end end })
    Sec:Label({ Name = "Unlock targets" }):Keybind({ Name = "Unlock targets", Flag = "HC_UnlockKey", Mode = "Hold", Default = Enum.KeyCode.X,
        Callback = function(state) if state then clearTargets() end end })
    Sec:Button({ Name = "Unlock targets", Callback = function() clearTargets() end })
    Sec:Toggle({ Name = "Auto switch", Flag = "HC_AutoSwitch", Default = false,
        Callback = function(v) HC.autoSwitch = v end })
    Sec:Dropdown({ Name = "Priority (which locked target)", Flag = "HC_Priority", Default = "Closest to mouse", Multi = false,
        Items = { "Closest to mouse", "Closest to me", "Lowest HP" },
        Callback = function(v) HC.priority = (type(v) == "table" and v[1]) or v or "Closest to mouse" end })

    local Sec2 = CombatSub:Section({ Name = "Force Hit", Side = 1 })
    Sec2:Toggle({ Name = "Force Hit (click target)", Flag = "HC_ForceHit", Default = false,
        Callback = function(v) setForceHit(v) end })
    Sec2:Dropdown({ Name = "Hit part", Flag = "HC_HitPart", Default = "Head", Multi = false,
        Items = { "Head", "UpperTorso", "HumanoidRootPart" },
        Callback = function(v) HC.hitPart = (type(v) == "table" and v[1]) or v or "Head" end })
    Sec2:Slider({ Name = "Cooldown", Flag = "HC_ForceHitCd", Min = 0, Max = 1000, Default = 180, Decimals = 0, Suffix = " ms",
        Callback = function(v) HC.forceHitCooldown = v / 1000 end })
    Sec2:Toggle({ Name = "Wallbang (nudge origin)", Flag = "HC_Wallbang", Default = false,
        Callback = function(v) HC.wallbang = v end })
    Sec2:Slider({ Name = "Wallbang origin offset", Flag = "HC_WallbangOffset", Min = 0, Max = 60, Default = 12, Decimals = 0, Suffix = " studs",
        Callback = function(v) HC.wallbangOffset = v end })
    -- fake bullet tracer + hit sound (the synth never renders gun visuals)
    Sec2:Toggle({ Name = "Bullet tracers", Flag = "HC_Tracer", Default = true,
        Callback = function(v) HC.tracerEnabled = v end })
    Sec2:Dropdown({ Name = "Tracer style", Flag = "HC_TracerStyle", Default = "Standard", Multi = false,
        Items = { "Standard", "Laser", "Thin" },
        Callback = function(v) HC.tracerStyle = (type(v) == "table" and v[1]) or v or "Standard" end })
    Sec2:Label({ Name = "Tracer color" }):Colorpicker({ Flag = "HC_TracerColor", Default = Color3.fromRGB(0, 255, 80),
        Callback = function(c) HC.tracerColor = c end })
    Sec2:Toggle({ Name = "Hit sound", Flag = "HC_HitSound", Default = true,
        Callback = function(v) HC.hitSoundEnabled = v end })
    Sec2:Slider({ Name = "Hit sound volume", Flag = "HC_HitSoundVol", Min = 0, Max = 500, Default = 100, Decimals = 0, Suffix = "%",
        Callback = function(v) HC.hitSoundVolume = v / 100 end })
    Sec2:Toggle({ Name = "Fake ammo HUD (real ammo)", Flag = "HC_AmmoHud", Default = false,
        Callback = function(v) HC.ammoHud = v end })

    local Sec3 = CombatSub:Section({ Name = "Auto Reload", Side = 2 })
    Sec3:Toggle({ Name = "Auto reload (low ammo)", Flag = "HC_Reload", Default = false,
        Callback = function(v) HC.reload = v end })
    Sec3:Slider({ Name = "Reload at ammo <=", Flag = "HC_ReloadThreshold", Min = 0, Max = 30, Default = 0, Decimals = 0,
        Callback = function(v) HC.reloadThreshold = v end })

    local Sec4 = CombatSub:Section({ Name = "Auto Stomp", Side = 2 })
    Sec4:Toggle({ Name = "Auto stomp", Flag = "HC_Stomp", Default = false,
        Callback = function(v) HC.stomp = v end })
    Sec4:Toggle({ Name = "Auto stomp targets only", Flag = "HC_StompTargets", Default = false,
        Callback = function(v) HC.stompTargets = v end })
    Sec4:Slider({ Name = "Stomp radius", Flag = "HC_StompRadius", Min = 1, Max = 30, Default = 5, Decimals = 0,
        Callback = function(v) HC.stompRadius = v end })
end

-- 2) Ragebot
local RageSub = MainPage:SubPage({ Name = "Ragebot" })
do
    local Sec = RageSub:Section({ Name = "Auto Shoot", Side = 1 })
    Sec:Toggle({ Name = "Auto shoot", Flag = "HC_AutoShoot", Default = false,
        Callback = function(v) HC.autoShoot = v end })
    Sec:Slider({ Name = "Max distance", Flag = "HC_AutoShootDist", Min = 10, Max = 1000, Default = 250, Decimals = 0,
        Callback = function(v) HC.autoShootDist = v end })
    Sec:Slider({ Name = "Cooldown", Flag = "HC_AutoShootCd", Min = 0, Max = 1000, Default = 150, Decimals = 0, Suffix = " ms",
        Callback = function(v) HC.autoShootCooldown = v / 1000 end })
    Sec:Toggle({ Name = "Skip force-fielded", Flag = "HC_AutoShootVis", Default = true,
        Callback = function(v) HC.autoShootVis = v end })

    local Sec2 = RageSub:Section({ Name = "Auto Equip", Side = 2 })
    Sec2:Toggle({ Name = "Auto equip on shoot", Flag = "HC_AutoEquip", Default = false,
        Callback = function(v) HC.autoEquip = v end })
    Sec2:Textbox({ Name = "Tool name", Flag = "HC_AutoEquipTool", Placeholder = "exact tool name",
        Callback = function(v) HC.autoEquipTool = v or "" end })

    local Sec3 = RageSub:Section({ Name = "Voidshoot", Side = 2 })
    Sec3:Toggle({ Name = "Voidshoot (desync to target)", Flag = "HC_Voidshoot", Default = false,
        Callback = function(v) HC.voidshoot = v; if not v then voidUnglue() end end })
end

-- 3) Knife Bot
local KnifeSub = MainPage:SubPage({ Name = "Knife Bot" })
do
    local Sec = KnifeSub:Section({ Name = "Knife aura", Side = 1 })
    Sec:Toggle({ Name = "Knife aura (attach + swing)", Flag = "HC_KnifeAura", Default = false,
        Callback = function(v) HC.knifeAura = v end })
    Sec:Slider({ Name = "Distance", Flag = "HC_KnifeDist", Min = 0, Max = 50, Default = 3, Decimals = 0,
        Callback = function(v) HC.knifeDist = v end })
    Sec:Slider({ Name = "Swing interval", Flag = "HC_KnifeInterval", Min = 5, Max = 200, Default = 60, Decimals = 0, Suffix = "0ms",
        Callback = function(v) HC.knifeInterval = v / 100 end })
    Sec:Toggle({ Name = "Orbit target", Flag = "HC_KnifeOrbit", Default = false,
        Callback = function(v) HC.knifeOrbit = v end })
    Sec:Slider({ Name = "Orbit speed", Flag = "HC_KnifeOrbitSpeed", Min = 0, Max = 720, Default = 180, Decimals = 0,
        Callback = function(v) HC.knifeOrbitSpeed = v end })

    local Sec2 = KnifeSub:Section({ Name = "Knife", Side = 2 })
    Sec2:Toggle({ Name = "Auto equip knife", Flag = "HC_KnifeEquip", Default = false,
        Callback = function(v) HC.knifeEquip = v end })
end

-- 4) Checks  -- global target-validity filters; everything that targets/shoots
--    people (Force Hit, Auto Shoot, Voidshoot, Knife Bot, Auto Stomp targets)
--    only engages players that pass every enabled check.
local ChecksSub = MainPage:SubPage({ Name = "Checks" })
do
    local Sec = ChecksSub:Section({ Name = "Visibility", Side = 1 })
    Sec:Toggle({ Name = "Visible check", Flag = "HC_CheckVisible", Default = false,
        Callback = function(v) HC.checkVisible = v end })
    Sec:Dropdown({ Name = "Visible origin", Flag = "HC_VisibleOrigin", Default = "Tool Handle", Multi = false,
        Items = { "Tool Handle", "Head", "Camera", "Root" },
        Callback = function(v) HC.visibleOrigin = (type(v) == "table" and v[1]) or v or "Tool Handle" end })

    local Sec2 = ChecksSub:Section({ Name = "State", Side = 2 })
    Sec2:Toggle({ Name = "Knocked check", Flag = "HC_CheckKnocked", Default = false,
        Callback = function(v) HC.checkKnocked = v end })
    Sec2:Toggle({ Name = "Grabbed check", Flag = "HC_CheckGrabbed", Default = false,
        Callback = function(v) HC.checkGrabbed = v end })
    Sec2:Toggle({ Name = "Forcefield check", Flag = "HC_CheckFF", Default = false,
        Callback = function(v) HC.checkFF = v end })
    Sec2:Toggle({ Name = "Loaded in check", Flag = "HC_CheckLoaded", Default = false,
        Callback = function(v) HC.checkLoaded = v end })
end

-- 5) Misc
local MiscSub = MainPage:SubPage({ Name = "Misc" })
do
    local Sec = MiscSub:Section({ Name = "AFK badge", Side = 1 })
    Sec:Toggle({ Name = "Anti-AFK badge", Flag = "HC_AntiAfk", Default = false,
        Callback = function(v) HC.antiAfk = v; if v then HC.forceAfk = false end end })
    Sec:Toggle({ Name = "Force-AFK badge", Flag = "HC_ForceAfk", Default = false,
        Callback = function(v) HC.forceAfk = v; if v then HC.antiAfk = false end end })
end

-- 6) Util
local UtilSub = MainPage:SubPage({ Name = "Util" })
do
    local Sec = UtilSub:Section({ Name = "Target Line", Side = 1 })
    if not hasDrawing then Sec:Label({ Name = "Needs a Drawing-capable executor." }) end
    Sec:Toggle({ Name = "Target line", Flag = "HC_TargetLine", Default = false,
        Callback = function(v) HC.targetLine = v end })
    Sec:Dropdown({ Name = "Line origin", Flag = "HC_LineOrigin", Default = "Bottom", Multi = false,
        Items = { "Bottom", "Top", "Center", "Mouse" },
        Callback = function(v) HC.lineOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    Sec:Label({ Name = "Line color" }):Colorpicker({ Flag = "HC_LineColor", Default = Color3.fromRGB(255, 60, 60),
        Callback = function(c) HC.lineColor = c end })

    local Sec2 = UtilSub:Section({ Name = "Target Outline", Side = 2 })
    Sec2:Toggle({ Name = "Target outline", Flag = "HC_TargetOutline", Default = false,
        Callback = function(v) HC.targetOutline = v end })
    Sec2:Label({ Name = "Outline color" }):Colorpicker({ Flag = "HC_OutlineColor", Default = Color3.fromRGB(255, 80, 80),
        Callback = function(c) HC.outlineColor = c end })
end

-- ============================================================
--  Universal base AFTER Main, so Main stays the first tab.
-- ============================================================
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function hcCleanup()
    unloaded = true
    setForceHit(false)
    HC.autoShoot, HC.voidshoot, HC.stomp, HC.stompTargets, HC.reload = false, false, false, false, false
    HC.knifeAura, HC.knifeEquip, HC.antiAfk, HC.forceAfk = false, false, false, false
    HC.targetLine, HC.targetOutline, HC.ammoHud = false, false, false
    voidUnglue()
    destroyAmmoHud()
    pcall(function() RunService:UnbindFromRenderStep("WH_HC_VS_RESTORE") end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if rbLine then pcall(function() rbLine:Remove() end) end
    if rbHL then pcall(function() rbHL:Destroy() end) end
end
do
    local g = gv()
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full()
            pcall(hcCleanup)
            if prev then pcall(prev) end
        end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
