-- ============================================================
--  games/138995385694035.lua  --  Hood Customs
--
--  "Main" tab first, then the universal base. Subpages:
--    Combat   : Target, Force Hit, Auto Reload, Auto Stomp, Auto Stomp Targets
--    Ragebot  : Auto Shoot, Auto Equip
--    Knife Bot: knife aura (attach/orbit) + auto-equip knife + knife reach (+visualizer)
--    Checks   : visible(+origin)/knocked/grabbed/forcefield/loaded -- global
--               target-validity filters respected by all targeting + shooting
--    Misc     : Anti-AFK badge, Force-AFK badge, Godmode
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
-- HC parks character models under workspace.Players.Characters normally, but moves
-- players who are in a 1v1 into workspace.Players.InBox. Scan every subfolder so the
-- knocked/dead checks find the model wherever the game put it.
local function hcModel(plr)
    local wsp = Workspace:FindFirstChild("Players")
    if wsp then
        for _, folder in ipairs(wsp:GetChildren()) do
            local m = folder:FindFirstChild(plr.Name)
            if m and m:IsA("Model") then return m end
        end
    end
    return plr.Character
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
    forceHit = false, hitPart = "Head", forceHitCooldown = 0.18, wallbang = false, wallbangOffset = 11,
    wbVisualize = false,  -- marker at the spot the wallbang would spoof the origin to
    tracerEnabled = true, tracerColor = Color3.fromRGB(0, 255, 80),
    tracerStyle = "Standard", tracerLifetime = 0.2, tracerThickness = 0.12,
    hitSoundEnabled = true, hitSoundId = 121566025787365, hitSoundVolume = 1.0,
    ammoHud = false,
    autoShoot = false, autoShootDist = 250, autoShootCooldown = 0.15, autoShootVis = true,
    autoEquip = false, autoEquipTool = "",
    voidshoot = false,
    -- tp shoot (keybind: teleport to an advantage on the target, shoot, return)
    tpShootMethod = "Wallbang", tpShootDist = 30,
    -- stomp / reload
    stomp = false, stompTargets = false, stompRadius = 5, stompTeleport = false,
    reload = false, reloadKey = Enum.KeyCode.R, reloadThreshold = 0,
    -- knife bot
    knifeAura = false, knifeDist = 3, knifeInterval = 0.6, knifeOrbit = false, knifeOrbitSpeed = 180,
    knifeEquip = false,
    knifeReach = false, knifeReachSize = 10, knifeReachVis = false,
    -- afk + protection
    antiAfk = false, forceAfk = false, godmode = false,
    -- visuals
    targetLine = false, lineOrigin = "Bottom", lineColor = Color3.fromRGB(255, 60, 60),
    targetOutline = false, outlineColor = Color3.fromRGB(255, 80, 80),
}

-- true while Auto stomp Targets is desynced onto a victim. While set, every other action
-- (force hit, auto shoot, knife) is suppressed -- shooting/stabbing cancels the stomp.
local _stomping = false
local _tpsActive = false   -- TP-shoot burst in progress (suppresses the auto-shoot loop)

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
-- resolve whatever a Grabbed ObjectValue points at (Player / character model / body
-- part / name string) down to the victim Player.
local function resolveGrabVictim(val)
    if typeof(val) == "Instance" then
        if val:IsA("Player") then return val end
        local p = Players:GetPlayerFromCharacter(val)
        if p then return p end
        local model = val:IsA("Model") and val or val:FindFirstAncestorWhichIsA("Model")
        if model then
            return Players:GetPlayerFromCharacter(model) or Players:FindFirstChild(model.Name)
        end
        return Players:FindFirstChild(val.Name)
    elseif type(val) == "string" then
        return Players:FindFirstChild(val)
    end
    return nil
end
-- Build the set of everyone currently grabbed: scan EVERY player's BodyEffects.Grabbed
-- (the grabber's value points at their victim) and flag each referenced player. Then
-- isGrabbed is just a membership test, so it applies to everyone, not only the target.
-- Cached ~0.1s since canEngage calls it per target every frame.
local _grabbedSet, _grabbedAt = {}, 0
local function grabbedSet()
    local now = os.clock()
    if now - _grabbedAt < 0.1 then return _grabbedSet end
    _grabbedAt = now
    local set = {}
    for _, grabber in ipairs(Players:GetPlayers()) do
        local m = hcModel(grabber)
        local fx = m and m:FindFirstChild("BodyEffects")
        local g = fx and fx:FindFirstChild("Grabbed")
        local val = g and g.Value
        if val ~= nil then
            local victim = resolveGrabVictim(val)
            if victim then set[victim] = true end
        end
    end
    _grabbedSet = set
    return set
end
local function isGrabbed(plr)
    return grabbedSet()[plr] == true
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
    -- ignore OTHER players' bodies so someone standing between us doesn't block the
    -- LoS check (keep the target m, so "first hit is the target = visible" still holds).
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local pm = hcModel(p)
            if pm and pm ~= m then ignore[#ignore + 1] = pm end
        end
    end
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
-- forward decls (defined below near the shoot logic) so the visible check can fall
-- back to "is a wallbang possible?" when Wallbang is on.
local wallbangOrigin, canWallbangPlr

-- engageable right now = valid AND passes every enabled check (state + visibility).
-- This is what all targeting/shooting selects on.
local function canEngage(plr)
    if not validTarget(plr) then return false end
    if not passesChecks(plr) then return false end
    if HC.checkVisible and not isVisible(plr) then
        -- with Wallbang on, a target we can punch a wall through still counts as engageable
        if not (HC.wallbang and canWallbangPlr and canWallbangPlr(plr)) then return false end
    end
    return true
end
-- like canEngage but WITHOUT the visible check (knife bot: respects knocked / grabbed /
-- forcefield / loaded-in, but ignores line of sight).
local function canEngageNoVis(plr)
    return validTarget(plr) and passesChecks(plr)
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
    local filter = (type(ignoreChecks) == "function") and ignoreChecks   -- custom filter (knife bot)
        or (ignoreChecks == true and validTarget)                        -- ignore all checks
        or canEngage                                                     -- all checks (default)
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
-- Wallbang ("if possible"): the server only lets us spoof our shot origin by ~10-11 studs
-- before "origin mismatch", and it raycasts origin -> hit (blocked LoS = "wallbang" error,
-- and an origin INSIDE a wall also errors). So a valid spoof origin must be (a) within
-- budget, (b) in OPEN AIR -- not embedded in a wall -- and (c) have clear LoS to the target.
-- We gather candidates (straight through the wall, UP into the sky to shoot someone below,
-- and peeks around cover) and pick the CLOSEST valid one. nil = skip the shot (no error).
-- HARD CAP 11: the server kicks for origin mismatch past this -- never exceed it.
local WB_HARD_CAP = 11
function wallbangOrigin(realOrigin, part)
    local targetPos = part.Position
    local toT = targetPos - realOrigin
    local dist = toT.Magnitude
    if dist < 1e-3 then return realOrigin end
    local fwd = toT.Unit
    local ignore = {}
    local lc = LocalPlayer.Character; if lc then ignore[#ignore + 1] = lc end
    local ig = Workspace:FindFirstChild("Ignored"); if ig then ignore[#ignore + 1] = ig end
    local tchar = part:FindFirstAncestorWhichIsA("Model"); if tchar then ignore[#ignore + 1] = tchar end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = ignore
    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Exclude
    op.FilterDescendantsInstances = ignore
    local function clearFrom(from)        -- clear LoS to the target? (walls block)
        return Workspace:Raycast(from, targetPos - from, rp) == nil
    end
    local function inAir(pos)             -- NOT embedded in a solid wall?
        local ok, parts = pcall(function() return Workspace:GetPartBoundsInRadius(pos, 0.6, op) end)
        if not ok then return true end
        for _, p in ipairs(parts) do if p.CanCollide then return false end end
        return true
    end
    if clearFrom(realOrigin) then return realOrigin end       -- already clear, no spoof
    local budget = math.min(HC.wallbangOffset, WB_HARD_CAP)
    -- basis for sideways peeks
    local up0 = math.abs(fwd.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
    local right = fwd:Cross(up0); right = (right.Magnitude > 0 and right.Unit) or Vector3.new(1, 0, 0)
    local up = right:Cross(fwd).Unit
    local worldUp = Vector3.new(0, 1, 0)
    local cands = {}
    local function add(off) if off.Magnitude <= budget then cands[#cands + 1] = off end end
    for f = 1, budget, 1 do add(fwd * f) end                  -- straight through the wall
    for u = 1, budget, 1 do                                   -- up into the air (hit someone below us)
        add(worldUp * u)
        add(fwd * math.min(3, budget) + worldUp * u)
    end
    for f = 0, budget, 2 do                                   -- peek around cover (every side)
        for l = 2, budget, 2 do
            for a = 0, 315, 45 do
                local rad = math.rad(a)
                add(fwd * f + (right * math.cos(rad) + up * math.sin(rad)) * l)
            end
        end
    end
    table.sort(cands, function(a, b) return a.Magnitude < b.Magnitude end)  -- closest first
    for _, off in ipairs(cands) do
        local origin = realOrigin + off
        if inAir(origin) and clearFrom(origin) then return origin end       -- in open air AND shootable
    end
    return nil                                                -- nothing valid within budget
end

-- can we wallbang this player at all? (origin-spoof check, cached briefly since the
-- targeting gate calls it every frame). Lets the visible check pass wallbang-able targets.
local _wbCache = {}
function canWallbangPlr(plr)
    local lc = LocalPlayer.Character
    local root = lc and lc:FindFirstChild("HumanoidRootPart"); if not root then return false end
    local m = hcModel(plr)
    local aim = m and (m:FindFirstChild(HC.hitPart) or m:FindFirstChild("Head") or m:FindFirstChild("HumanoidRootPart"))
    if not aim then return false end
    local now = os.clock()
    local c = _wbCache[plr]
    if c and now - c.t < 0.2 then return c.v end
    local v = wallbangOrigin(root.Position, aim) ~= nil
    _wbCache[plr] = { t = now, v = v }
    return v
end

-- spoofed shot origin (wallbang / voidshoot) so the tracer FX can start from it, not the muzzle
local _fhSpoofOrigin, _fhSpoofAt = nil, 0
local _tpsWallbang = false   -- TP-shoot "Wallbang" mode: force the origin-spoof for this shot
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
    -- Wallbang: spoof the origin just enough to clear the wall (within the server's
    -- ~10-stud tolerance). Skipped while voidshooting (origin is already on the target).
    if (HC.wallbang or _tpsWallbang) and not sent then
        origin = wallbangOrigin(origin, part)
        if not origin then return false end   -- no clear origin within budget -> skip, no error
    end
    -- remember the spoofed origin so the tracer FX draws from it (not the on-screen muzzle).
    -- only when we actually spoofed (voidshoot / wallbang); a normal shot keeps the usual muzzle.
    if sent or HC.wallbang or _tpsWallbang then _fhSpoofOrigin, _fhSpoofAt = origin, tick() else _fhSpoofOrigin = nil end
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
    -- start from the spoofed origin if we just wallbanged / voidshot, else the usual muzzle
    local origin
    if _fhSpoofOrigin and (tick() - _fhSpoofAt) < FX_WINDOW then origin = _fhSpoofOrigin else origin = muzzlePos() end
    if not origin then return end
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
    if gpe or not HC.forceHit or _stomping then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local lc = LocalPlayer.Character
    if not lc or not lc:FindFirstChildOfClass("Tool") then return end   -- holding a gun
    if tick() - _fhLast < HC.forceHitCooldown then return end
    local plr = getTarget(); if not plr then return end
    local char = plr.Character; if not char then return end
    local part = forceShotPart(char); if not part then return end
    _fhLast = tick()
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
    if g and g.WH and g.WH.markServerCF then g.WH.markServerCF(onTop) end   -- Server Pos clone follows the voidshoot
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
    if _stomping or _tpsActive or not (HC.autoShoot or HC.voidshoot) then return end
    if tick() - _asLast < HC.autoShootCooldown then return end
    local plr = getTarget()
    if not plr then voidUnglue(); return end
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
    if not HC.stomp then return end
    if tick() - _stompLast < 0.1 then return end
    local me = getMainEvent(); if not me then return end
    if not someoneBelow(false) then return end
    _stompLast = tick()
    pcall(function() me:FireServer("Stomp") end)
end))

-- ---- Auto stomp Targets (witherhook method): glue our physics-rep root onto the knocked
--      victim and spoof our pose 3 studs ABOVE them each Heartbeat (server sees us standing
--      on them), but restore our REAL pose each RenderStep (First) so we stay put locally.
--      The fake pose is set in Heartbeat and restored in RenderStep -- this ordering is what
--      makes the server actually see us on the target (Heartbeat-set survives to replication).
--      While glued, _stomping suppresses shooting/knifing so nothing cancels the stomp. ----
local STOMP_Y = 3
local _stompTarget, _stompSavedCF = nil, nil
local function stompGlue(hrp)
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not (lhrp and hrp) then return end
    local stompCF = CFrame.new(hrp.Position + Vector3.new(0, STOMP_Y, 0))
    if HC.stompTeleport then
        -- TELEPORT mode: actually move on top of the victim (no desync). Capture our
        -- origin ONCE so we teleport back to it when we're done (the RenderStep restore
        -- is disabled in this mode so it doesn't yank us off the victim mid-stomp).
        if not _stompSavedCF then _stompSavedCF = lhrp.CFrame end
        pcall(function() lhrp.CFrame = stompCF end)
    else
        -- SPOOF mode: desync our physics-rep root onto the victim, keep our real pose locally
        pcall(function() lhrp:SetNetworkOwner(LocalPlayer) end)
        pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)
        if sethiddenproperty then pcall(function() sethiddenproperty(lhrp, "PhysicsRepRootPart", hrp) end) end
        _stompSavedCF = lhrp.CFrame                   -- our real spot (restored each RenderStep)
        pcall(function() lhrp.CFrame = stompCF end)
    end
    local g = gv(); if g and g.WH and g.WH.markServerCF then g.WH.markServerCF(stompCF) end   -- Server Pos clone follows the stomp
end
local function stompUnglue()
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if lhrp then
        if sethiddenproperty then pcall(function() sethiddenproperty(lhrp, "PhysicsRepRootPart", lhrp) end) end
        if _stompSavedCF then pcall(function() lhrp.CFrame = _stompSavedCF end) end
    end
    _stompSavedCF, _stompTarget, _stomping = nil, nil, false
end
track(RunService.Heartbeat:Connect(function()
    if not HC.stompTargets then
        if _stomping then stompUnglue() end
        return
    end
    local me = getMainEvent(); if not me then return end
    -- finishing the current victim?
    if _stompTarget then
        local stillKnocked = isKnocked(_stompTarget) and not isDead(_stompTarget)
        if not (_stompTarget.Parent and _stompTarget.Character) or not stillKnocked then
            stompUnglue()                             -- stomped / gone / up -> drop
        else
            local hrp = _stompTarget.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                stompGlue(hrp)                        -- stay glued on top + stomp
                pcall(function() me:FireServer("Stomp") end)
            end
            return
        end
    end
    -- pick a new knocked, not-yet-dead locked target and glue onto it
    for _, plr in ipairs(liveTargets()) do
        if isKnocked(plr) and not isDead(plr) then
            local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                _stompTarget, _stomping = plr, true
                stompGlue(hrp)
                pcall(function() me:FireServer("Stomp") end)
                return
            end
        end
    end
end))
-- restore our real pose each render frame so the desync stays put locally
pcall(function() RunService:UnbindFromRenderStep("WH_HC_STOMP_RESTORE") end)
RunService:BindToRenderStep("WH_HC_STOMP_RESTORE", Enum.RenderPriority.First.Value, function()
    if _stomping and _stompSavedCF and not HC.stompTeleport then
        local lc = LocalPlayer.Character
        local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
        if lhrp then pcall(function() lhrp.CFrame = _stompSavedCF end) end
    end
end)

-- ============================================================
--  TP SHOOT  (keybind: teleport to an advantage on the target, shoot, teleport back)
--    Wallbang -- TP to cover the target can't shoot through; we still hit via the
--                origin-spoof (wallbangOrigin), so "they can't hit me, I can hit him".
--    Above    -- TP straight above the target.
--    Below    -- TP straight below the target.
--    Glue     -- glue 50 studs above the target: settle 0.2s, shoot, linger ~1s, return.
--    Inside   -- like Glue but glued right inside the target.
--  We actually move (the CFrame is re-asserted each Heartbeat so the server registers the
--  pose) -> the shot origin == our real position and validates -> then we restore.
-- ============================================================
local TPS_GLUE_Y = 50
local function tpsIgnoreList(targetModel)
    local ig = {}
    local lc = LocalPlayer.Character; if lc then ig[#ig + 1] = lc end
    local x = Workspace:FindFirstChild("Ignored"); if x then ig[#ig + 1] = x end
    if targetModel then ig[#ig + 1] = targetModel end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local m = hcModel(p); if m and m ~= targetModel then ig[#ig + 1] = m end
        end
    end
    return ig
end
-- a spot the target can't shoot us from, but from which a VALID <=11-stud origin-spoof
-- still reaches them. We validate every candidate with wallbangOrigin itself, so we only
-- teleport somewhere the shot will actually land (no "wallbang"/origin-mismatch errors,
-- no silently-skipped shots). Under-the-floor spots are listed first -- the spoof there is
-- a short, reliable straight-up peek (the classic "the ground" cover).
local function tpsCoverSpot(targetModel, thrp, part)
    local tpos = thrp.Position
    local ignore = tpsIgnoreList(targetModel)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Exclude
    op.FilterDescendantsInstances = ignore
    local function inAir(pos)                  -- a spot we can stand in (not buried in a wall)
        local ok, parts = pcall(function() return Workspace:GetPartBoundsInRadius(pos, 1.5, op) end)
        if not ok then return true end
        for _, p in ipairs(parts) do if p.CanCollide then return false end end
        return true
    end
    local function hasCover(pos)               -- the target's shots are blocked (can't hit us)
        return Workspace:Raycast(pos, tpos - pos, params) ~= nil
    end

    local cands = {}
    for _, d in ipairs({ 4, 5, 6, 7, 9 }) do cands[#cands + 1] = tpos - Vector3.new(0, d, 0) end  -- under the floor
    for a = 0, 330, 30 do                       -- behind walls: just past the first wall, near its edge
        local rad = math.rad(a)
        local dir = Vector3.new(math.cos(rad), 0, math.sin(rad))
        local res = Workspace:Raycast(tpos + Vector3.new(0, 1, 0), dir * 50, params)
        if res then cands[#cands + 1] = res.Position + dir * 2 + Vector3.new(0, 0.5, 0) end
    end

    for _, pos in ipairs(cands) do              -- best: in air, covered, AND a valid spoof exists
        if inAir(pos) and hasCover(pos) and wallbangOrigin(pos, part) then return CFrame.new(pos) end
    end
    for _, pos in ipairs(cands) do              -- relax cover before giving up (still needs a spoof)
        if inAir(pos) and wallbangOrigin(pos, part) then return CFrame.new(pos) end
    end
    return nil
end
local function tpShoot()
    if _tpsActive then return end
    local plr = getTarget(canEngageNoVis) -- locked targets, all Checks EXCEPT the visible check
    if not plr then return end
    local tmodel = plr.Character or hcModel(plr)
    local thrp = tmodel and tmodel:FindFirstChild("HumanoidRootPart")
    if not thrp then return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return end
    -- need a gun out -- default to the double barrel
    if not lc:FindFirstChildOfClass("Tool") then tryEquipNamed("[DoubleBarrel]") end

    _tpsActive = true
    local saved = lhrp.CFrame
    local method = HC.tpShootMethod
    local g = gv()
    local savedWbOffset = HC.wallbangOffset
    if method == "Wallbang" then HC.wallbangOffset = 11 end   -- use the full origin-spoof budget
    local function curHRP()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end
    local function place(cf)
        local h = curHRP(); if h then pcall(function() h.CFrame = cf end) end
        if g and g.WH and g.WH.markServerCF then pcall(function() g.WH.markServerCF(cf) end) end
    end
    local function fire()
        local m = plr.Character or hcModel(plr)
        local part = m and forceShotPart(m); if not part then return end
        if HC.autoEquip and HC.autoEquipTool ~= "" then tryEquipNamed(HC.autoEquipTool) end
        pcall(function() fireShootAt(part) end)
    end

    task.spawn(function()
        pcall(function()
            if method == "Glue" or method == "Inside" then
                local yoff = (method == "Glue") and TPS_GLUE_Y or 0
                local start, fired = tick(), false
                while tick() - start < 1.2 do          -- settle 0.2s -> shoot -> linger ~1s
                    local th = plr.Character or hcModel(plr)
                    th = th and th:FindFirstChild("HumanoidRootPart")
                    if not th then break end
                    place(CFrame.new(th.Position + Vector3.new(0, yoff, 0)))
                    if not fired and tick() - start >= 0.2 then fired = true; fire() end
                    RunService.Heartbeat:Wait()
                end
            else
                local cf
                if method == "Above" then
                    cf = CFrame.new(thrp.Position + Vector3.new(0, HC.tpShootDist, 0))
                elseif method == "Below" then
                    cf = CFrame.new(thrp.Position - Vector3.new(0, HC.tpShootDist, 0))
                else                                    -- Wallbang
                    for _ = 1, 3 do RunService.Heartbeat:Wait() end   -- let the gun finish equipping
                    local th = plr.Character or hcModel(plr)
                    th = th and th:FindFirstChild("HumanoidRootPart")
                    local part = th and forceShotPart(plr.Character or hcModel(plr))
                    cf = (th and part) and tpsCoverSpot(tmodel, th, part)
                    if not cf then return end           -- no safe + shootable spot -> bail, no error
                    _tpsWallbang = true
                end
                local s = tick()
                while tick() - s < 0.1 do place(cf); RunService.Heartbeat:Wait() end   -- settle so the server registers us
                fire()
                s = tick()
                while tick() - s < 0.12 do place(cf); RunService.Heartbeat:Wait() end   -- linger ~0.12s before returning
            end
        end)
        _tpsWallbang = false
        HC.wallbangOffset = savedWbOffset
        local h = curHRP(); if h then pcall(function() h.CFrame = saved end) end
        if g and g.WH and g.WH.markServerCF then pcall(function() g.WH.markServerCF(saved) end) end
        _tpsActive = false
    end)
end

-- ---- Godmode (HC emote): play the hitbox-displacing emote, FREEZE it at its godmode
--      frame (TimePosition 0.1265, speed 0) every Heartbeat, and re-assert it whenever the
--      game plays another animation so the pose can't be overridden. Re-applied on respawn. ----
local GOD_EMOTE = "rbxassetid://70883871260184"
local GOD_FREEZE = 0.1265
local _godTrack, _godHB, _godAnimConn
local function godCleanup()
    if _godTrack then pcall(function() _godTrack:Stop(); _godTrack:Destroy() end); _godTrack = nil end
    if _godHB then _godHB:Disconnect(); _godHB = nil end
    if _godAnimConn then _godAnimConn:Disconnect(); _godAnimConn = nil end
end
local godApply
godApply = function()
    if not HC.godmode then return end
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    godCleanup()
    local anim = Instance.new("Animation"); anim.AnimationId = GOD_EMOTE
    local animator = hum:FindFirstChildOfClass("Animator")
    local ok, t = pcall(function()
        return (animator and animator:LoadAnimation(anim)) or hum:LoadAnimation(anim)
    end)
    if not ok or not t then return end
    _godTrack = t
    pcall(function() _godTrack:Play(0, 1, 1) end)
    _godHB = RunService.Heartbeat:Connect(function()
        if _godTrack and HC.godmode then
            pcall(function()
                _godTrack.TimePosition = GOD_FREEZE   -- hold the godmode pose
                _godTrack:AdjustSpeed(0)
            end)
        end
    end)
    _godAnimConn = hum.AnimationPlayed:Connect(function(newtrack)
        if HC.godmode and _godTrack and newtrack ~= _godTrack then
            task.delay(0.02 + math.random() * 0.03, godApply)  -- re-assert over the game's anim
        end
    end)
end
local function godSet(on)
    HC.godmode = on
    if on then godApply() else godCleanup() end
end
track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.25)
    if HC.godmode then godApply() end
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
    -- knife bot respects knocked/grabbed/forcefield/loaded-in but ignores the visible check
    local plr = getTarget(canEngageNoVis)
    local char = plr and plr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
-- fake pos resolver: re-root our physics replication onto the target (network ownership +
-- PhysicsRepRootPart) so the orbit position sticks server-side instead of rubber-banding.
local _knifeAttached = false
local function knifeDetach()
    if not _knifeAttached then return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if lhrp and sethiddenproperty then pcall(function() sethiddenproperty(lhrp, "PhysicsRepRootPart", lhrp) end) end
    _knifeAttached = false
end
track(RunService.Heartbeat:Connect(function(dt)
    if not HC.knifeAura or _stomping then knifeDetach(); return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    local tHrp = knifeTargetHrp()
    if not lhrp or not tHrp then knifeDetach(); return end
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
    if pos == pos then
        local faceTo = ((pos - tPos).Magnitude > 0.5) and tPos or (pos - tHrp.CFrame.LookVector)
        pcall(function() lhrp:SetNetworkOwner(LocalPlayer) end)
        pcall(function() tHrp:SetNetworkOwner(LocalPlayer) end)
        if sethiddenproperty then pcall(function() sethiddenproperty(lhrp, "PhysicsRepRootPart", tHrp) end) end
        _knifeAttached = true
        pcall(function()
            lhrp.CFrame = CFrame.new(pos, faceTo)
            lhrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            lhrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)
    end
end))
-- knife swing clicker
task.spawn(function()
    while not unloaded do
        if HC.knifeAura and not _stomping and knifeTargetHrp() then
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

-- ---- KNIFE REACH: resize [Knife]/Handle/HITBOX_PART (max 13 -- above trips HC's
--      anti-cheat). Re-applied on Heartbeat so it survives respawn/re-equip. The
--      visualizer puts a Highlight on the (resized) hitbox so you see the real reach. ----
local KR_DEFAULT = Vector3.new(2.5, 1, 1)
local KR_MAX = 13
local function knifeHitbox()
    local function find(p)
        local k = p and p:FindFirstChild(KNIFE_NAME)
        local h = k and k:FindFirstChild("Handle")
        return h and h:FindFirstChild("HITBOX_PART")
    end
    return find(LocalPlayer.Character) or find(LocalPlayer:FindFirstChild("Backpack"))
end
local function knifeReachRestore()
    local hb = knifeHitbox()
    if hb then
        pcall(function() hb.Size = KR_DEFAULT; hb.Transparency = 1 end)
        local hl = hb:FindFirstChild("_kr_hl"); if hl then hl:Destroy() end
    end
end
track(RunService.Heartbeat:Connect(function()
    local hb = knifeHitbox(); if not hb then return end
    if HC.knifeReach then
        local s = math.clamp(HC.knifeReachSize or 10, 1, KR_MAX)
        local target = Vector3.new(s, s, s)
        if hb.Size ~= target then pcall(function() hb.Size = target end) end
        if hb.Transparency ~= 0.9999 then pcall(function() hb.Transparency = 0.9999 end) end
        local hl = hb:FindFirstChild("_kr_hl")
        if HC.knifeReachVis then
            if not hl then
                hl = Instance.new("Highlight")
                hl.Name = "_kr_hl"
                hl.Adornee = hb
                hl.FillColor = Color3.fromRGB(255, 90, 90)
                hl.FillTransparency = 0.75
                hl.OutlineColor = Color3.fromRGB(255, 90, 90)
                hl.OutlineTransparency = 0
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = hb
            end
        elseif hl then hl:Destroy() end
    else
        if hb.Size ~= KR_DEFAULT then knifeReachRestore() end
    end
end))

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
-- small white marker at the spoofed wallbang origin. A BillboardGui (AlwaysOnTop)
-- renders the dot over geometry so it's visible through walls.
local wbMarker, wbBG
local function ensureWbMarker()
    if wbMarker and wbMarker.Parent then return wbMarker end
    wbMarker = Instance.new("Part")
    wbMarker.Name = "_wb_spot"
    wbMarker.Shape = Enum.PartType.Ball
    wbMarker.Size = Vector3.new(0.6, 0.6, 0.6)
    wbMarker.Anchored, wbMarker.CanCollide, wbMarker.CanQuery, wbMarker.CanTouch = true, false, false, false
    wbMarker.Material = Enum.Material.Neon
    wbMarker.Color = Color3.fromRGB(255, 255, 255)
    wbMarker.Transparency = 1
    wbMarker.Parent = Workspace:FindFirstChild("Ignored") or Workspace
    wbBG = Instance.new("BillboardGui")
    wbBG.Name = "_wb_bg"
    wbBG.AlwaysOnTop = true                 -- draw over walls
    wbBG.Size = UDim2.fromOffset(10, 10)
    wbBG.Adornee = wbMarker
    wbBG.Enabled = false
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromScale(1, 1)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel = 0
    dot.Parent = wbBG
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = dot
    pcall(function() wbBG.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not wbBG.Parent then wbBG.Parent = wbMarker end
    return wbMarker
end
track(RunService.RenderStepped:Connect(function()
    -- show who we'll ACTUALLY attack (all checks). If nobody is engageable, fall back
    -- to the no-checks pick so the visual stays on the locked target (e.g. a knocked
    -- person we can't hit) instead of vanishing.
    local g = gv()
    local indicatorOn = g and g.WH and g.WH.targetIndicatorOn
    local plr = nil
    if HC.targetLine or HC.targetOutline or indicatorOn or HC.wbVisualize then plr = getTarget(false) or getTarget(true) end
    publishTarget(plr)  -- target GUI follows the SAME ignore-checks pick as the visuals
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
    -- wallbang spot: where the origin gets spoofed to punch through to the target. Only
    -- shows when there's an actual spoof (target behind cover, reachable within budget);
    -- hidden when LoS is already clear (origin == us) or no spot fits the budget.
    local mk = ensureWbMarker()
    if HC.wbVisualize and char then
        local lc = LocalPlayer.Character
        local root = lc and lc:FindFirstChild("HumanoidRootPart")
        local part = forceShotPart(char)
        local origin = (root and part) and wallbangOrigin(root.Position, part) or nil
        if origin and (origin - root.Position).Magnitude > 0.5 then
            mk.Position = origin
            mk.Transparency = 0.3
            if wbBG then wbBG.Enabled = true end
        else
            mk.Transparency = 1
            if wbBG then wbBG.Enabled = false end
        end
    else
        mk.Transparency = 1
        if wbBG then wbBG.Enabled = false end
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
    Sec2:Toggle({ Name = "Wallbang if possible", Flag = "HC_Wallbang", Default = false,
        Callback = function(v) HC.wallbang = v end })
    Sec2:Slider({ Name = "Max origin offset", Flag = "HC_WallbangOffset", Min = 0, Max = 11, Default = 11, Decimals = 0, Suffix = " studs",
        Callback = function(v) HC.wallbangOffset = v end })
    Sec2:Toggle({ Name = "Visualize wallbang spot", Flag = "HC_WbVisualize", Default = false,
        Callback = function(v) HC.wbVisualize = v end })
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
    Sec4:Toggle({ Name = "Auto stomp Targets", Flag = "HC_StompTargets", Default = false,
        Callback = function(v) HC.stompTargets = v end })
    Sec4:Dropdown({ Name = "Stomp Targets mode", Flag = "HC_StompMode", Default = "Spoof", Multi = false,
        Items = { "Spoof", "Teleport" },
        Callback = function(v) HC.stompTeleport = (((type(v) == "table" and v[1]) or v) == "Teleport") end })
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

    local Sec3 = RageSub:Section({ Name = "TP Shoot", Side = 2 })
    Sec3:Dropdown({ Name = "Method", Flag = "HC_TpShootMethod", Default = "Wallbang", Multi = false,
        Items = { "Wallbang", "Above", "Below", "Glue", "Inside" },
        Callback = function(v) HC.tpShootMethod = (type(v) == "table" and v[1]) or v or "Wallbang" end })
    Sec3:Slider({ Name = "Above/Below distance", Flag = "HC_TpShootDist", Min = 3, Max = 100, Default = 30, Decimals = 0, Suffix = " studs",
        Callback = function(v) HC.tpShootDist = v end })
    Sec3:Label({ Name = "TP shoot" }):Keybind({
        Name = "TP shoot", Flag = "HC_TpShootKey", Mode = "Hold", Default = Enum.KeyCode.F,
        Callback = function(state) if state then tpShoot() end end })
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

    local Sec3 = KnifeSub:Section({ Name = "Knife reach", Side = 2 })
    Sec3:Toggle({ Name = "Knife reach", Flag = "HC_KnifeReach", Default = false,
        Callback = function(v) HC.knifeReach = v end })
    Sec3:Slider({ Name = "Reach", Flag = "HC_KnifeReachSize", Min = 2, Max = 13, Default = 10, Decimals = 0, Suffix = " studs",
        Callback = function(v) HC.knifeReachSize = v end })
    Sec3:Toggle({ Name = "Reach visualizer", Flag = "HC_KnifeReachVis", Default = false,
        Callback = function(v) HC.knifeReachVis = v end })
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

    local Sec2 = MiscSub:Section({ Name = "Protection", Side = 2 })
    Sec2:Toggle({ Name = "Godmode", Flag = "HC_Godmode", Default = false,
        Callback = function(v) godSet(v) end })
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
    HC.knifeAura, HC.knifeEquip, HC.antiAfk, HC.forceAfk, HC.godmode = false, false, false, false, false
    HC.knifeReach, HC.knifeReachVis = false, false
    HC.targetLine, HC.targetOutline, HC.ammoHud, HC.wbVisualize = false, false, false, false
    voidUnglue()
    pcall(function() RunService:UnbindFromRenderStep("WH_HC_STOMP_RESTORE") end)
    pcall(stompUnglue)         -- stop any stomp desync
    pcall(knifeDetach)         -- undo knife-bot physics-rep desync
    pcall(godCleanup)          -- stop godmode emote
    pcall(knifeReachRestore)   -- put the knife hitbox back to normal size
    destroyAmmoHud()
    pcall(function() RunService:UnbindFromRenderStep("WH_HC_VS_RESTORE") end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if rbLine then pcall(function() rbLine:Remove() end) end
    if rbHL then pcall(function() rbHL:Destroy() end) end
    if wbMarker then pcall(function() wbMarker:Destroy() end) end
    if wbBG then pcall(function() wbBG:Destroy() end) end
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
