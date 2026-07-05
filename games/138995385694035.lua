-- ============================================================
--  games/138995385694035.lua  --  Hood Customs
--
--  "Main" tab first, then the universal base. Subpages:
--    Combat   : Target, Force Hit, Auto Reload, Auto Stomp, Auto Stomp Targets
--    Ragebot  : Auto Shoot, Auto Equip
--    Knife Bot: knife aura (attach/orbit) + auto-equip knife + knife reach (+visualizer)
--    Checks   : visible(+origin)/knocked/grabbed/forcefield/loaded -- global
--               target-validity filters respected by all targeting + shooting
--    FX       : Hit Chams, Target Line, Tracers, Hit Sound, Target Outline
--    HUD      : Radar (sweep + pings), Damage Numbers, Killfeed,
--               Kill Effect (neon dissolve + shockwave) + kill sound
--    Misc     : Anti-AFK badge, Force-AFK badge, Godmode
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
-- consolidated perf caches -- ONE main-chunk local (this file rides Luau's
-- 200-locals-per-scope limit; add future cache state as fields, not new locals)
local PC = {
    hcm = {},                      -- hcModel memo
    vis = {},                      -- isVisible memo
    visParams = nil, visParamsT = 0,
    tgt = {}, tgtT = 0,            -- getTarget frame cache
    wbVizT = 0, wbVizOrigin = nil, -- wallbang visualizer throttle
    wbVizPart = nil, wbVizReal = nil, -- ...the part it was computed FOR + our root at compute time
}
-- memoized: this gets hammered every frame from targeting/radar/checks, and the raw
-- folder scan + FindFirstChild-by-name is expensive at 40 players. 0.3s TTL + a
-- Parent check (a destroyed model on respawn recomputes immediately).
local function hcModel(plr)
    local c = PC.hcm[plr]
    local now = os.clock()
    if c and now - c.t < 0.3 and c.m and c.m.Parent then return c.m end
    local m
    local wsp = Workspace:FindFirstChild("Players")
    if wsp then
        for _, folder in ipairs(wsp:GetChildren()) do
            local f = folder:FindFirstChild(plr.Name)
            if f and f:IsA("Model") then m = f; break end
        end
    end
    m = m or plr.Character
    PC.hcm[plr] = { t = now, m = m }
    return m
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
    forceHit = false, hitPart = "Head", forceHitCooldown = 0.18, wallbang = false, wallbangOffset = 10,
    wbVisualize = false,  -- marker at the spot the wallbang would spoof the origin to
    tracerEnabled = true, tracerColor = Color3.fromRGB(0, 255, 80),
    tracerStyle = "Standard", tracerLifetime = 0.2, tracerThickness = 0.12,
    tracerThroughWalls = true,
    hitSoundEnabled = true, hitSoundId = 121566025787365, hitSoundVolume = 1.0,
    ammoHud = false,
    autoShoot = false, autoShootDist = 250, autoShootCooldown = 0.15, autoShootVis = true,
    autoEquip = false, autoEquipTool = "",
    voidshoot = false,
    fakePos = false,   -- replication re-rooted onto the target: others see us AT them
    -- tp shoot (keybind: teleport to an advantage on the target, shoot, return)
    tpShootMethod = "Wallbang",
    -- stomp / reload
    stomp = false, stompTargets = false, stompRadius = 5, stompTeleport = false,
    reload = false, reloadKey = Enum.KeyCode.R, reloadThreshold = 0,
    -- knife bot
    knifeAura = false, knifeDist = 3, knifeInterval = 0.6, knifeOrbit = false, knifeOrbitSpeed = 180,
    knifeEquip = false,
    knifeReach = false, knifeReachSize = 10, knifeReachVis = false,
    -- afk + protection
    antiAfk = false, forceAfk = false, godmode = false, forceJump = false,
    -- visuals
    targetLine = false, lineOrigin = "Bottom", lineColor = Color3.fromRGB(255, 60, 60),
    targetOutline = false, outlineColor = Color3.fromRGB(255, 80, 80),
    -- hit chams (frozen ghost clone of the target on every confirmed hit)
    hitChams = false, hitChamsDuration = 2, hitChamsTransparency = 0.5,
    hitChamsMaterial = "ForceField", hitChamsColor = Color3.fromRGB(255, 60, 60),
    hitChamsOutline = false, hitChamsOutlineColor = Color3.fromRGB(255, 255, 255),
    -- HUD + kill fx
    radar = false, radarSize = 180, radarRange = 300,
    dmgNumbers = false, dmgNumScale = 1.0,
    killSound = false, killSoundId = 102740241606246,
    killfeed = false, killfeedTime = 5,
    killEffect = false,
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
-- ignore ALL players' bodies (incl. the target -- ray runs to the aim position, so a
-- clear ray == visible; bodies in between never block). Excluding the target too lets
-- one shared exclude list / RaycastParams serve every player, rebuilt at 4 Hz instead
-- of per call (the old per-call rebuild was O(players) allocs, dozens of times a frame).
function PC.getVisParams()
    local now = os.clock()
    if PC.visParams and now - PC.visParamsT < 0.25 then return PC.visParams end
    local ignore = {}
    local lc = LocalPlayer.Character; if lc then ignore[#ignore + 1] = lc end
    local ig = Workspace:FindFirstChild("Ignored"); if ig then ignore[#ignore + 1] = ig end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local pm = hcModel(p)
            if pm then ignore[#ignore + 1] = pm end
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    PC.visParams, PC.visParamsT = params, now
    return params
end
local function isVisible(plr)
    -- ~2-frame memo: collapses the 5 per-frame callers into one raycast without making
    -- the engage gate laggy. The earlier 0.1s TTL quantized visibility into 100ms
    -- blocks -- targets blinked in/out of "engageable" and auto shoot fired in stutters.
    -- The real perf win is the shared params in getVisParams, not a long result cache.
    local now = os.clock()
    local c = PC.vis[plr]
    if c and now - c.t < 0.03 then return c.v end
    local v
    local m = hcModel(plr)
    local aim = m and (m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head"))
    if not aim then
        v = false
    else
        local origin = visOrigin()
        if not origin then
            v = true
        else
            v = Workspace:Raycast(origin, aim.Position - origin, PC.getVisParams()) == nil
        end
    end
    PC.vis[plr] = { t = now, v = v }
    return v
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
-- Frame-cached (~1-2 frames): radar / visuals / auto-shoot / watchers all call this
-- every frame -- without the cache each call re-scans the pool (checks + raycasts).
local function getTarget(ignoreChecks)
    local key = (type(ignoreChecks) == "function") and ignoreChecks
        or (ignoreChecks == true and "t") or "d"
    local now = os.clock()
    if now - PC.tgtT > 0.02 then table.clear(PC.tgt); PC.tgtT = now end
    local hit = PC.tgt[key]
    if hit ~= nil then return hit or nil end   -- false = cached "no target"
    local function compute()
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
    local best = compute()
    PC.tgt[key] = best or false
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
-- Wallbang ("if possible"): the server only lets us spoof our shot origin by ~10 studs
-- before "origin mismatch", and it raycasts origin -> hit (blocked LoS = "wallbang" error,
-- and an origin INSIDE a wall also errors). So a valid spoof origin must be (a) within
-- budget, (b) in OPEN AIR -- not embedded in a wall -- and (c) have clear LoS to the target.
-- We gather candidates (straight through the wall, UP into the sky to shoot someone below,
-- and peeks around cover) and pick the CLOSEST valid one. nil = skip the shot (no error).
-- HARD CAP 10: the server kicks for origin mismatch past this (11 still errored) -- never exceed it.
local WB_HARD_CAP = 10
-- The server rejects a shot whose ORIGIN is farther than this from the hit ("range too long").
-- The origin-spoof (<=WB_HARD_CAP studs) can therefore extend our effective reach: sit up to
-- WB_HARD_CAP studs past this, and pull the spoofed origin back inside it. 2-stud safety margin.
local MAX_SHOT_RANGE = 200

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
    local function inRange(pos)            -- within the gun's max shot range (else "range too long")
        return (targetPos - pos).Magnitude <= MAX_SHOT_RANGE - 2
    end
    if clearFrom(realOrigin) and inRange(realOrigin) then return realOrigin end   -- clear & in range, no spoof
    -- No wall-count limit: any number of walls is fine as long as SOME candidate origin
    -- within the stud budget sits in open air with clear LoS to the target -- those are
    -- the checks the server actually runs on the spoofed origin.
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
        -- inRange (pure math) first, then the raycast (cheap, rejects most), then the
        -- overlap query (priciest) -- order matters, this loop can run 200+ candidates
        if inRange(origin) and clearFrom(origin) and inAir(origin) then return origin end   -- open air, shootable, in range
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
    -- a NEGATIVE result means the full candidate search ran dry (the worst case, ~500
    -- spatial queries) -- cache those 3x longer than positives so a fully-enclosed
    -- target doesn't re-burn the whole search 5x a second. But the cache is only valid
    -- while BOTH ends stand still: if either of us moved >2 studs the old answer is
    -- garbage (a 0.6s "can't bang" verdict on a moving fight made targets undroppable
    -- for over half a second after they became bangable = choppy auto shoot). Static
    -- standoffs -- the case the cache exists for -- still hit it.
    if c and now - c.t < (c.v and 0.2 or 0.6)
        and (root.Position - c.rp).Magnitude < 2
        and (aim.Position - c.ap).Magnitude < 2 then return c.v end
    local v = wallbangOrigin(root.Position, aim) ~= nil
    _wbCache[plr] = { t = now, v = v, rp = root.Position, ap = aim.Position }
    return v
end
-- drop per-player cache entries when they leave (all keyed by Player instance)
track(Players.PlayerRemoving:Connect(function(p)
    _wbCache[p] = nil; PC.vis[p] = nil; PC.hcm[p] = nil
end))

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
    local realOrigin = (sent and sent.Position) or root.Position
    local origin = realOrigin
    local spoofed = (sent ~= nil)   -- voidshoot is always a real displacement
    -- Wallbang: spoof the origin just enough to clear the wall (within the server's
    -- ~10-stud tolerance). Skipped while voidshooting (origin is already on the target).
    if (HC.wallbang or _tpsWallbang) and not sent then
        origin = wallbangOrigin(origin, part)
        if not origin then return false end   -- no clear origin within budget -> skip, no error
        if (origin - realOrigin).Magnitude > 0.5 then spoofed = true end   -- only if actually moved
    end
    -- remember the spoofed origin so the tracer FX draws from it. ONLY when the origin was
    -- actually displaced (voidshoot / a real wallbang). A clear-LoS wallbang returns our root
    -- position, which would otherwise make the tracer start from the body instead of the muzzle.
    if spoofed then _fhSpoofOrigin, _fhSpoofAt = origin, tick() else _fhSpoofOrigin = nil end
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
--  FORCE-HIT FX  -- fake bullet tracers + hit sound. Tracers are the Zee
--  version (ported back 2026-07-02): Beam glow + travel + muzzle flash +
--  spark trail + impact flash/light/particle burst, with a solid neon core
--  under ONE shared Highlight (black outline) for the through-walls line.
--  All local-only, with anti-freeze caps.
-- ============================================================
local _activeTracers, MAX_TRACERS = 0, 12
local _lastTracerAt, MIN_TRACER_GAP = 0, 0.04

-- ONE shared, persistent Highlight for every tracer core. Per-tracer highlights hit
-- Roblox's simultaneous-Highlight cap during rapid fire (older ones stop rendering while
-- their beams live on) AND fading a highlight looks like it "dies" before the glowing beam.
-- Instead: all cores live under one Model highlighted once; a core is un-highlighted only
-- when it's DESTROYED -- at the exact instant its beam is destroyed. No highlight fade.
local _hlModel, _sharedHL
local function ensureTracerHL()
    if _hlModel and _hlModel.Parent and _sharedHL and _sharedHL.Parent then return end
    if _hlModel then pcall(function() _hlModel:Destroy() end) end
    _hlModel = Instance.new("Model"); _hlModel.Name = "\0_fh"; _hlModel.Parent = Workspace
    _sharedHL = Instance.new("Highlight")
    _sharedHL.FillTransparency = 0.2
    _sharedHL.OutlineColor, _sharedHL.OutlineTransparency = Color3.new(0, 0, 0), 0   -- black outline
    pcall(function() _sharedHL.Adornee = _hlModel end)
    _sharedHL.Parent = _hlModel
end
local function clearTracerHL()
    if _hlModel then pcall(function() _hlModel:Destroy() end); _hlModel = nil; _sharedHL = nil end
end
-- the gun's muzzle (barrel tip), not the handle centre (which sits in the hand by the chest).
-- The muzzle is a FIXED point on the gun, independent of where we shoot: it's the gun's own
-- attachment furthest from our body (the barrel sticks out front). Picking by shoot direction
-- was wrong -- it flipped to the rear of the gun when the target was behind us. Falls back to
-- the front of the handle's longest axis, then the head.
local function muzzlePos()
    local c = LocalPlayer.Character
    local tool = c and c:FindFirstChildOfClass("Tool")
    if not tool then local h = c and c:FindFirstChild("Head"); return h and h.Position end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    local ref = (hrp and hrp.Position) or (c:FindFirstChild("Head") and c.Head.Position)
    if ref then
        local best, bestD
        for _, d in ipairs(tool:GetDescendants()) do
            if d:IsA("Attachment") then
                local dd = (d.WorldPosition - ref).Magnitude
                if not bestD or dd > bestD then bestD, best = dd, d.WorldPosition end   -- furthest = barrel tip
            end
        end
        if best then return best end
    end
    local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
    if handle then
        -- front along the handle's longest axis (the barrel), in the handle's own orientation
        local sz = handle.Size
        local axis = (sz.Z >= sz.X and sz.Z >= sz.Y) and Vector3.new(0, 0, -1)
            or (sz.X >= sz.Y) and Vector3.new(-1, 0, 0) or Vector3.new(0, -1, 0)
        return (handle.CFrame * CFrame.new(axis * (math.max(sz.X, sz.Y, sz.Z) / 2))).Position
    end
    local h = c and c:FindFirstChild("Head")
    return h and h.Position
end
local function invisAnchor(pos)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
    p.Size, p.Transparency, p.CFrame = Vector3.new(0.05, 0.05, 0.05), 1, CFrame.new(pos)
    p.Name = "\0_fh"; p.Parent = Workspace
    return p
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
    local col, th = HC.tracerColor, HC.tracerThickness
    local TEX = "rbxassetid://446111271"   -- soft energy streak
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
            b.TextureLength, b.TextureSpeed = 4, 12   -- fast scroll = energy flow
        end) end
        b.Parent = startPart; beams[#beams + 1] = b; return b
    end
    local whiteHot = ColorSequence.new({
        ColorSequenceKeypoint.new(0, col), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, col) })
    if HC.tracerStyle == "Laser" then
        mkBeam(th * 3.5, 0.6)                 -- soft glow halo
        mkBeam(th * 1.2, 0, false, whiteHot)  -- solid hot core
        mkBeam(th * 0.5, 0, true)             -- scrolling energy line
    elseif HC.tracerStyle == "Thin" then
        mkBeam(th * 1.4, 0.7)                 -- faint glow
        mkBeam(th * 0.55, 0.05, true)         -- thin textured line
    else  -- Standard: halo + mid glow + white-hot textured core
        local outer = mkBeam(th * 5, nil)
        outer.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0.35),
            NumberSequenceKeypoint.new(1, 0.6) })
        mkBeam(th * 2.6, 0.25)                 -- mid glow
        mkBeam(th * 1.1, 0.02, true, whiteHot) -- white-hot textured core
    end

    -- Solid neon core = the highlighted silhouette (black outline). It's parented under the
    -- ONE shared Highlight model, so no per-tracer Highlight and no cap issues. The through-
    -- walls toggle + tracer color are applied to the shared Highlight. The screen-space black
    -- outline keeps even a hairline core readable, so it can be as thin as the Size slider.
    ensureTracerHL()
    pcall(function()
        _sharedHL.DepthMode = HC.tracerThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        _sharedHL.FillColor = col
    end)
    local core = Instance.new("Part")
    core.Anchored, core.CanCollide, core.CanTouch, core.CanQuery, core.CastShadow = true, false, false, false, false
    core.Material, core.Color = Enum.Material.Neon, col
    local cth = math.max(th, 0.01)
    core.Size = Vector3.new(cth, cth, dist)
    core.CFrame = CFrame.lookAt((origin + hitPos) / 2, hitPos)
    core.Name = "\0_fh"; core.Parent = (_hlModel and _hlModel.Parent) and _hlModel or Workspace

    -- muzzle flash at the origin + a spark trail that follows the bullet head
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
        for i = 1, 8 do  -- travel: extend the end attachment origin -> hit
            task.wait(0.06 / 8)
            if not startPart.Parent then break end
            endPart.CFrame = CFrame.new(origin + dir * (dist * (i / 8)))
        end
        if endPart.Parent then endPart.CFrame = CFrame.new(hitPos) end
        if sparks then pcall(function() sparks.Rate = 0 end) end   -- stop the trail on impact
        -- impact VFX: neon flash ball + point light + particle burst
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
        -- Fade only the BEAMS over the lifetime. The core + its (shared) highlight are kept
        -- fully solid the whole time and only vanish when the core is DESTROYED below -- at
        -- the exact instant the beams are destroyed. So the highlight lasts the full tracer
        -- lifetime and disappears WITH the beam, never before it.
        for i = 1, 8 do
            task.wait(HC.tracerLifetime / 8)
            if not startPart.Parent then break end
            local a = i / 8
            for _, b in ipairs(beams) do if b.Parent then b.Transparency = NumberSequence.new(a) end end
        end
        pcall(function() if startPart.Parent then startPart:Destroy() end end)
        pcall(function() if endPart.Parent then endPart:Destroy() end end)
        pcall(function() if core.Parent then core:Destroy() end end)
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
-- ============================================================
--  HIT CHAMS  -- on every confirmed hit (same trigger as the hit sound), freeze
--  a ghost clone of the target where they stood, then remove it. Same
--  clone-and-strip treatment as universal's Server Pos clone, but whitelisted to
--  the REAL R6/R15 bodyparts + accessory Handles -- HC hangs fake/special parts
--  off characters and those must never render.
-- ============================================================
local CHAM_PARTS = {   -- canonical rig part names (HumanoidRootPart deliberately absent)
    Head = true, Torso = true, ["Left Arm"] = true, ["Right Arm"] = true,
    ["Left Leg"] = true, ["Right Leg"] = true,
    UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}
local _chams = {}        -- live cham models, oldest-first
local CHAM_MAX = 10      -- spray-fire flood guard
local function killCham(m)
    for i, mm in ipairs(_chams) do
        if mm == m then table.remove(_chams, i); break end
    end
    pcall(function() m:Destroy() end)
end
-- killMode (kill effect): full-bright neon flash of the body that dissolves fast and high,
-- regardless of the Hit Chams toggle -- gated by HC.killEffect at the call site.
local function spawnHitCham(model, killMode)
    if not model then return end
    if not killMode and not HC.hitChams then return end
    local m = Instance.new("Model"); m.Name = "\0"
    local mat = killMode and Enum.Material.Neon or (Enum.Material[HC.hitChamsMaterial] or Enum.Material.ForceField)
    local baseT = killMode and 0.05 or math.clamp(HC.hitChamsTransparency, 0, 1)
    local popT = killMode and 0 or math.max(0, baseT - 0.35)   -- pop-in: brighter than configured, settles to baseT
    local parts, torso = {}, nil
    local function add(part)
        local ok, p = pcall(function() return part:Clone() end)
        if not (ok and p) then return end
        -- bare mesh shape, NO textures, so the cham color/material shows
        for _, ch in ipairs(p:GetChildren()) do
            if ch:IsA("Decal") or ch:IsA("Texture") then
                pcall(function() ch:Destroy() end)
            elseif ch:IsA("DataModelMesh") then
                if ch:IsA("SpecialMesh") then pcall(function() ch.TextureId = "" end) end
            else
                pcall(function() ch:Destroy() end)   -- welds / attachments / scripts / particles
            end
        end
        if p:IsA("MeshPart") then pcall(function() p.TextureID = "" end) end
        p.Name = "Part"
        p.Anchored = true; p.CanCollide = false; p.CanQuery = false
        p.CanTouch = false; p.Massless = true
        p.CFrame = part.CFrame   -- frozen where they stood at the moment of the hit
        pcall(function()
            p.Color = HC.hitChamsColor; p.Transparency = popT; p.Material = mat
        end)
        p.Parent = m; parts[#parts + 1] = p
        if part.Name == "UpperTorso" or part.Name == "Torso" then torso = p end
    end
    for _, ch in ipairs(model:GetChildren()) do
        if ch:IsA("BasePart") and CHAM_PARTS[ch.Name] then
            add(ch)
        elseif ch:IsA("Accessory") then
            local handle = ch:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then add(handle) end
        end
    end
    if #parts == 0 then m:Destroy(); return end
    torso = torso or parts[1]
    local hl
    if HC.hitChamsOutline or killMode then
        hl = Instance.new("Highlight")
        hl.FillTransparency = 1
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.OutlineColor = killMode and HC.hitChamsColor or HC.hitChamsOutlineColor
        hl.Adornee = m; hl.Parent = m
    end
    m.Parent = Workspace   -- client-created instance: stays local, never replicates
    _chams[#_chams + 1] = m
    while #_chams > CHAM_MAX do killCham(_chams[1]) end

    -- spawn VFX: light pulse inside the torso + a shimmer burst of rising motes
    local shimmer, light
    pcall(function()
        light = Instance.new("PointLight")
        light.Color, light.Brightness, light.Range = HC.hitChamsColor, 4, 12
        light.Parent = torso
        local att = Instance.new("Attachment", torso)
        shimmer = Instance.new("ParticleEmitter")
        shimmer.Color, shimmer.LightEmission = ColorSequence.new(HC.hitChamsColor), 1
        shimmer.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
        shimmer.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
        shimmer.Speed, shimmer.Lifetime = NumberRange.new(2, 5), NumberRange.new(0.3, 0.7)
        shimmer.Rate, shimmer.SpreadAngle = 0, Vector2.new(180, 180)
        shimmer.Acceleration = Vector3.new(0, 4, 0)   -- motes drift upward
        shimmer.Parent = att
        shimmer:Emit(14)
    end)

    -- lifecycle: pop-in settle -> hold -> rising dissolve (never a hard despawn)
    task.spawn(function()
        for i = 1, 4 do   -- settle the pop-in brightness back to the configured transparency
            task.wait(0.05)
            if not m.Parent then return end
            local a = i / 4
            local t = math.max(0, baseT - 0.35 * (1 - a))
            for _, p in ipairs(parts) do if p.Parent then p.Transparency = t end end
            if light and light.Parent then light.Brightness = 4 * (1 - a) end
        end
        local hold, t0 = killMode and 0.05 or math.max(0.1, HC.hitChamsDuration), tick()
        while tick() - t0 < hold do
            task.wait(0.1)
            if not m.Parent then return end
        end
        if shimmer then pcall(function() shimmer.Rate = killMode and 60 or 26 end) end   -- dissolve motes while fading
        local FADE, RISE, STEPS = killMode and 0.55 or 0.7, killMode and 3.5 or 1.8, 21
        local prev = 0
        for i = 1, STEPS do
            task.wait(FADE / STEPS)
            if not m.Parent then return end
            local a = i / STEPS
            local e = a * a * (3 - 2 * a)   -- smoothstep: slow start, fast middle, soft end
            local dy = (e - prev) * RISE; prev = e
            for _, p in ipairs(parts) do
                if p.Parent then
                    p.CFrame = p.CFrame + Vector3.new(0, dy, 0)   -- ghost rises as it dissolves
                    p.Transparency = baseT + (1 - baseT) * e
                end
            end
            if hl then pcall(function() hl.OutlineTransparency = e end) end
        end
        if shimmer then pcall(function() shimmer.Rate = 0 end) end
        task.wait(0.15)   -- let the last motes die before their emitter vanishes
        killCham(m)
    end)
end
local function clearChams()
    for _, m in ipairs(_chams) do pcall(function() m:Destroy() end) end
    _chams = {}
end

-- ============================================================
--  KILL FX + HUD  -- kill effect (neon dissolve + shockwave), damage numbers,
--  kill sound, radar, killfeed. All client-side visuals
--  driven off the same confirmed-hit watcher as the hit sound.
--  Scoped in a do-block (ONE exported local) -- the main chunk was about to
--  blow Luau's 200-locals-per-scope limit.
-- ============================================================
local HUD = {}
do
-- nhack theme plumbing: read the live Library palette (falls back to the preset) so
-- the radar/killfeed panels look native next to the watermark/keybind widgets.
local function themeC(key, fallback)
    local t = Library and Library.Theme
    local c = t and t[key]
    return (typeof(c) == "Color3") and c or fallback
end
local function themeFont()
    local f = Library and Library.Font
    return (typeof(f) == "Font") and f or Font.fromEnum(Enum.Font.Code)
end
local function themeFontSize()
    local n = Library and Library.FontSize
    return (type(n) == "number") and n or 9
end
-- the watermark-style panel dressing: Miter outline stroke + the 1px accent
-- gradient liner over a dark liner across the top
local function nhackPanel(frame)
    frame.BackgroundColor3 = themeC("Background", Color3.fromRGB(22, 22, 25))
    frame.BorderSizePixel = 0
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.LineJoinMode = Enum.LineJoinMode.Miter
    s.Color = themeC("Outline", Color3.fromRGB(62, 57, 77))
    s.Parent = frame
    local dark = Instance.new("Frame")
    dark.BorderSizePixel = 0
    dark.Position = UDim2.new(0, 0, 0, 1)
    dark.Size = UDim2.new(1, 0, 0, 1)
    dark.BackgroundColor3 = themeC("Light Border", Color3.fromRGB(16, 16, 19))
    dark.Parent = frame
    local acc = Instance.new("Frame")
    acc.BorderSizePixel = 0
    acc.Position = UDim2.new(0, 0, 0, 0)
    acc.Size = UDim2.new(1, 0, 0, 1)
    acc.BackgroundColor3 = themeC("Accent", Color3.fromRGB(200, 183, 247))
    acc.Parent = frame
    local grad = Instance.new("UIGradient")
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1),
        NumberSequenceKeypoint.new(1, 0) })
    grad.Parent = acc
    return s, dark, acc
end

-- kill effect: the body flashes solid neon and dissolves fast + high (spawnHitCham
-- killMode) while a shockwave disc blows out along the ground with a light burst.
local function spawnKillEffect(model)
    spawnHitCham(model, true)
    local torso = model and (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
        or model:FindFirstChild("HumanoidRootPart"))
    if not torso then return end
    local col = HC.hitChamsColor
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder
    ring.Anchored, ring.CanCollide, ring.CanTouch, ring.CanQuery, ring.CastShadow = true, false, false, false, false
    ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, col, 0.15
    ring.Size = Vector3.new(0.25, 2, 2)
    -- cylinder axis is X; roll it 90 deg so the disc lies flat at their feet
    ring.CFrame = CFrame.new(torso.Position - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
    ring.Name = "\0_fh"; ring.Parent = Workspace
    local light = Instance.new("PointLight")
    light.Color, light.Brightness, light.Range = col, 8, 18
    light.Parent = ring
    task.spawn(function()
        for i = 1, 14 do
            task.wait(0.5 / 14)
            if not ring.Parent then return end
            local a = i / 14
            local d = 2 + a * 24
            ring.Size = Vector3.new(0.25, d, d)
            ring.Transparency = 0.15 + a * 0.85
            light.Brightness = 8 * (1 - a)
        end
        if ring.Parent then ring:Destroy() end
    end)
end

-- kill sound: its own asset, at the hit-sound volume
local function playKillSound()
    if not HC.killSoundId or HC.killSoundId == 0 then return end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. tostring(HC.killSoundId)
    s.Volume = math.clamp(HC.hitSoundVolume, 0, 5)
    s.Parent = pg or Workspace
    s:Play()
    task.delay(5, function() if s and s.Parent then s:Destroy() end end)
end

-- ---- damage numbers: floating "-N" popping off the target on every confirmed hit ----
local _dmgActive = 0
local function spawnDmgNumber(model, dmg)
    if _dmgActive >= 24 then return end
    local ref = model and (model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("HumanoidRootPart"))
    if not ref then return end
    _dmgActive = _dmgActive + 1
    local holder = invisAnchor(ref.Position
        + Vector3.new(math.random(-12, 12) / 10, 1.2, math.random(-12, 12) / 10))
    local bb = Instance.new("BillboardGui")
    bb.AlwaysOnTop, bb.Size = true, UDim2.fromOffset(140, 44)
    bb.StudsOffset = Vector3.new(0, 0.4, 0)
    bb.Parent = holder
    local d = math.max(1, math.floor(dmg + 0.5))
    local hot = math.clamp(d / 60, 0, 1)   -- 60+ damage caps the (subtle) size growth
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency, lbl.Size = 1, UDim2.fromScale(1, 1)
    -- thin: theme family at Light weight (fall back to the plain theme font)
    local face = themeFont()
    pcall(function() face = Font.new(face.Family, Enum.FontWeight.Light, Enum.FontStyle.Normal) end)
    lbl.FontFace = face
    lbl.Text = "-" .. d
    lbl.TextColor3 = themeC("Text", Color3.fromRGB(240, 240, 242))   -- always white
    local size = (11 + hot * 4) * math.clamp(HC.dmgNumScale, 0.5, 2)
    lbl.TextSize = math.max(1, size * 0.4)   -- pop-in: grow past full, settle
    lbl.TextStrokeColor3 = themeC("Border", Color3.fromRGB(10, 10, 12))
    lbl.TextStrokeTransparency = 0.5
    lbl.Parent = bb
    task.spawn(function()
        local POP = { 0.75, 1.18, 1.06, 1 }   -- overshoot curve over the first 4 steps
        for i = 1, 14 do   -- pop, drift up, fade over the back half
            task.wait(0.05)
            if not holder.Parent then break end
            local a = i / 14
            lbl.TextSize = size * (POP[i] or 1)
            bb.StudsOffset = Vector3.new(0, 0.4 + a * 2.4, 0)
            lbl.TextTransparency = a < 0.5 and 0 or (a - 0.5) * 2
            lbl.TextStrokeTransparency = 0.15 + a * 0.85
        end
        pcall(function() holder:Destroy() end)
        _dmgActive = math.max(0, _dmgActive - 1)
    end)
end

-- ---- radar: camera-relative top-down dot map (white / red = target / grey = knocked) ----
local radarGui, radarFrame, radarDots, radarSweep, radarAccGrad
local function destroyRadar()
    if radarGui then pcall(function() radarGui:Destroy() end) end
    radarGui, radarFrame, radarDots, radarSweep, radarAccGrad = nil, nil, nil, nil, nil
end
-- expanding hollow square where a dot just appeared (nhack is all miter squares)
local function radarPing(x, y, col)
    if not (radarFrame and radarFrame.Parent) then return end
    local ring = Instance.new("Frame")
    ring.BackgroundTransparency = 1
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.fromOffset(x, y)
    ring.Size = UDim2.fromOffset(5, 5)
    local rs = Instance.new("UIStroke")
    rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    rs.LineJoinMode = Enum.LineJoinMode.Miter
    rs.Color = col
    rs.Parent = ring
    ring.Parent = radarFrame
    task.spawn(function()
        for i = 1, 8 do
            task.wait(0.03)
            if not ring.Parent then return end
            local a = i / 8
            local d = 5 + a * 14
            ring.Size = UDim2.fromOffset(d, d)
            rs.Transparency = a
        end
        pcall(function() ring:Destroy() end)
    end)
end
local function ensureRadar()
    if radarGui and radarGui.Parent and radarFrame and radarFrame.Parent then return end
    destroyRadar()
    radarDots = {}
    radarGui = Instance.new("ScreenGui")
    radarGui.Name = "\0_radar"; radarGui.IgnoreGuiInset = true; radarGui.ResetOnSpawn = false
    local ok = pcall(function() radarGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not radarGui.Parent then radarGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    radarFrame = Instance.new("Frame")
    radarFrame.Size = UDim2.fromOffset(HC.radarSize, HC.radarSize)
    radarFrame.Position = UDim2.new(0, 20, 0.5, -HC.radarSize / 2)
    radarFrame.BackgroundTransparency = 0.1
    radarFrame.Active = true
    radarFrame.ClipsDescendants = true
    radarFrame.Parent = radarGui
    local pStroke, _, pAcc = nhackPanel(radarFrame)
    radarAccGrad = pAcc:FindFirstChildOfClass("UIGradient")
    -- pop-in: scale up from 92% while the panel fades to its resting look
    do
        local scale = Instance.new("UIScale")
        scale.Scale = 0.92
        scale.Parent = radarFrame
        radarFrame.BackgroundTransparency = 1
        pStroke.Transparency = 1
        task.spawn(function()
            for i = 1, 6 do
                task.wait(0.025)
                if not (radarFrame and radarFrame.Parent) then return end
                local a = i / 6
                scale.Scale = 0.92 + 0.08 * (1 - (1 - a) * (1 - a))   -- ease-out
                radarFrame.BackgroundTransparency = 1 - a * 0.9
                pStroke.Transparency = 1 - a
            end
            pcall(function() scale:Destroy() end)
        end)
    end
    -- rotating sweep arm, accent-colored, bright at center fading to the tip
    radarSweep = Instance.new("Frame")
    radarSweep.BackgroundTransparency = 1
    radarSweep.AnchorPoint = Vector2.new(0.5, 0.5)
    radarSweep.Position = UDim2.fromScale(0.5, 0.5)
    radarSweep.Size = UDim2.new(1, -8, 1, -8)
    radarSweep.Parent = radarFrame
    local arm = Instance.new("Frame")
    arm.BorderSizePixel = 0
    arm.AnchorPoint = Vector2.new(0, 0.5)
    arm.Position = UDim2.fromScale(0.5, 0.5)
    arm.Size = UDim2.new(0.5, 0, 0, 1)
    arm.BackgroundColor3 = themeC("Accent", Color3.fromRGB(200, 183, 247))
    arm.Parent = radarSweep
    local ag = Instance.new("UIGradient")
    ag.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
    ag.Parent = arm
    for _, horiz in ipairs({ true, false }) do   -- faint crosshair through the middle
        local ln = Instance.new("Frame")
        ln.BorderSizePixel = 0
        ln.BackgroundColor3 = themeC("Outline", Color3.fromRGB(62, 57, 77))
        ln.BackgroundTransparency = 0.45
        ln.AnchorPoint = Vector2.new(0.5, 0.5)
        ln.Position = UDim2.fromScale(0.5, 0.5)
        ln.Size = horiz and UDim2.new(1, -8, 0, 1) or UDim2.new(0, 1, 1, -8)
        ln.Parent = radarFrame
    end
    local title = Instance.new("TextLabel")   -- tiny corner tag, watermark-style
    title.BackgroundTransparency = 1
    title.FontFace, title.TextSize = themeFont(), themeFontSize()
    title.TextColor3 = themeC("Inactive Text", Color3.fromRGB(131, 120, 162))
    title.Text = "radar"
    title.AnchorPoint = Vector2.new(0, 1)
    title.Position = UDim2.new(0, 5, 1, -3)
    title.Size = UDim2.fromOffset(0, 10)
    title.AutomaticSize = Enum.AutomaticSize.X
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = radarFrame
    local me = Instance.new("Frame")   -- you, dead center: accent square, nhack-indicator style
    me.AnchorPoint = Vector2.new(0.5, 0.5)
    me.Position = UDim2.fromScale(0.5, 0.5)
    me.Size = UDim2.fromOffset(6, 6)
    me.BackgroundColor3 = themeC("Accent", Color3.fromRGB(200, 183, 247))
    me.BorderSizePixel = 0
    me.Parent = radarFrame
    local ms = Instance.new("UIStroke")
    ms.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    ms.LineJoinMode = Enum.LineJoinMode.Miter
    ms.Color = themeC("Border", Color3.fromRGB(10, 10, 12))
    ms.Parent = me
    -- drag to move
    local dragging, dragStart, startPos = false, nil, nil
    radarFrame.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, io.Position, radarFrame.Position
        end
    end)
    radarFrame.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    track(UIS.InputChanged:Connect(function(io)
        if dragging and io.UserInputType == Enum.UserInputType.MouseMovement and radarFrame and radarFrame.Parent then
            local delta = io.Position - dragStart
            radarFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end
track(RunService.RenderStepped:Connect(function()
    if not HC.radar then if radarGui then destroyRadar() end return end
    ensureRadar()
    radarFrame.Size = UDim2.fromOffset(HC.radarSize, HC.radarSize)
    if radarSweep then radarSweep.Rotation = (tick() * 70) % 360 end
    if radarAccGrad then   -- slow sheen drifting across the accent liner
        radarAccGrad.Offset = Vector2.new((tick() * 0.2) % 2 - 1, 0)
    end
    local cam = Workspace.CurrentCamera
    local myM = hcModel(LocalPlayer)
    local myHrp = myM and myM:FindFirstChild("HumanoidRootPart")
    if not (cam and myHrp) then return end
    local look = cam.CFrame.LookVector
    local fwd = Vector3.new(look.X, 0, look.Z)
    fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
    local right = Vector3.new(-fwd.Z, 0, fwd.X)
    local half = HC.radarSize / 2
    local tgt = getTarget()
    local seen = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local m = hcModel(plr)
            local hrp = m and m:FindFirstChild("HumanoidRootPart")
            if hrp then
                seen[plr] = true
                local dot = radarDots[plr]
                local isNew = not (dot and dot.Parent)
                if isNew then
                    dot = Instance.new("Frame")   -- square + miter border, like nhack's toggle indicator
                    dot.AnchorPoint = Vector2.new(0.5, 0.5)
                    dot.Size = UDim2.fromOffset(5, 5)
                    dot.BorderSizePixel = 0
                    local ds = Instance.new("UIStroke")
                    ds.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    ds.LineJoinMode = Enum.LineJoinMode.Miter
                    ds.Color = themeC("Border", Color3.fromRGB(10, 10, 12))
                    ds.Parent = dot
                    dot.Parent = radarFrame
                    radarDots[plr] = dot
                end
                local rel = hrp.Position - myHrp.Position
                local x = rel:Dot(right) / HC.radarRange * half
                local y = -rel:Dot(fwd) / HC.radarRange * half
                local mag = math.sqrt(x * x + y * y)
                local edge = half - 6
                local clamped = mag > edge
                if clamped then x, y = x / mag * edge, y / mag * edge end
                local isTgt = (plr == tgt)
                dot.Position = UDim2.fromOffset(half + x, half + y)
                -- target dot breathes; everyone else stays 5px
                dot.Size = isTgt and UDim2.fromOffset(5 + (math.sin(tick() * 8) * 0.5 + 0.5) * 3,
                    5 + (math.sin(tick() * 8) * 0.5 + 0.5) * 3) or UDim2.fromOffset(5, 5)
                dot.BackgroundColor3 = isTgt and themeC("Risky", Color3.fromRGB(255, 70, 80))
                    or (isKnocked(plr) and themeC("Inactive Text", Color3.fromRGB(131, 120, 162)))
                    or themeC("Text", Color3.fromRGB(240, 240, 242))
                dot.BackgroundTransparency = clamped and 0.55 or 0   -- rim = out of range, that way
                if isNew then pcall(radarPing, half + x, half + y, dot.BackgroundColor3) end
            end
        end
    end
    for plr, dot in pairs(radarDots) do
        if not seen[plr] then pcall(function() dot:Destroy() end); radarDots[plr] = nil end
    end
end))

-- ---- killfeed: your kills, top-right -- weapon + name + distance ----
local kfGui, kfList
local _kfN = 0
local function destroyKillfeed()
    if kfGui then pcall(function() kfGui:Destroy() end); kfGui, kfList = nil, nil end
end
local function ensureKillfeed()
    if kfGui and kfGui.Parent and kfList and kfList.Parent then return end
    destroyKillfeed()
    kfGui = Instance.new("ScreenGui")
    kfGui.Name = "\0_kf"; kfGui.IgnoreGuiInset = true; kfGui.ResetOnSpawn = false
    local ok = pcall(function() kfGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not kfGui.Parent then kfGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    kfList = Instance.new("Frame")
    kfList.AnchorPoint = Vector2.new(1, 0)
    kfList.Position = UDim2.new(1, -16, 0, 170)
    kfList.Size = UDim2.fromOffset(280, 220)
    kfList.BackgroundTransparency = 1
    kfList.Parent = kfGui
    local ll = Instance.new("UIListLayout")
    ll.FillDirection = Enum.FillDirection.Vertical
    ll.HorizontalAlignment = Enum.HorizontalAlignment.Right
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    ll.Padding = UDim.new(0, 4)
    ll.Parent = kfList
end
local function killfeedAdd(plr, model)
    ensureKillfeed()
    _kfN = _kfN + 1
    local dist = 0
    pcall(function()
        local myM = hcModel(LocalPlayer)
        local a = myM and myM:FindFirstChild("HumanoidRootPart")
        local b = model and model:FindFirstChild("HumanoidRootPart")
        if a and b then dist = math.floor((a.Position - b.Position).Magnitude + 0.5) end
    end)
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    local gun = tool and tool.Name:gsub("[%[%]]", "") or "Fists"
    local e = Instance.new("Frame")
    e.LayoutOrder = _kfN
    e.AutomaticSize = Enum.AutomaticSize.X
    e.Size = UDim2.fromOffset(0, 0)   -- unfolds to 19px tall
    e.BackgroundTransparency = 1
    e.ClipsDescendants = true
    e.Parent = kfList
    local stroke, liner1, liner2 = nhackPanel(e)
    stroke.Transparency = 1
    liner1.BackgroundTransparency = 1
    liner2.BackgroundTransparency = 1
    local sheen = liner2:FindFirstChildOfClass("UIGradient")
    local row = Instance.new("Frame")   -- label row (name accent-coloured => separate labels)
    row.BackgroundTransparency = 1
    row.AutomaticSize = Enum.AutomaticSize.X
    row.Size = UDim2.new(0, 0, 0, 19)
    row.Parent = e
    local rl = Instance.new("UIListLayout")
    rl.FillDirection = Enum.FillDirection.Horizontal
    rl.VerticalAlignment = Enum.VerticalAlignment.Center
    rl.SortOrder = Enum.SortOrder.LayoutOrder
    rl.Parent = row
    local labels = {}
    local function seg(text, colorKey, fallback)
        local lbl = Instance.new("TextLabel")
        lbl.LayoutOrder = #labels + 1
        lbl.AutomaticSize = Enum.AutomaticSize.X
        lbl.Size = UDim2.new(0, 0, 1, 0)
        lbl.BackgroundTransparency, lbl.TextTransparency = 1, 1
        lbl.FontFace, lbl.TextSize = themeFont(), themeFontSize() + 1
        lbl.TextColor3 = themeC(colorKey, fallback)
        lbl.Text = text
        lbl.Parent = row
        labels[#labels + 1] = lbl
        return lbl
    end
    -- plain text, no glyphs: "name  gun  distance"
    seg("  " .. plr.Name, "Accent", Color3.fromRGB(200, 183, 247))
    seg(("  %s  %dm  "):format(gun, dist), "Text", Color3.fromRGB(240, 240, 242))
    -- cap the feed at 6 entries: kill the oldest
    local entries = {}
    for _, c in ipairs(kfList:GetChildren()) do
        if c:IsA("Frame") then entries[#entries + 1] = c end
    end
    table.sort(entries, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
    for i = 1, #entries - 6 do pcall(function() entries[i]:Destroy() end) end
    local function setFade(a)   -- a: 0 = fully shown, 1 = invisible
        e.BackgroundTransparency = 0.05 + a * 0.95
        stroke.Transparency = a
        liner1.BackgroundTransparency = a
        liner2.BackgroundTransparency = a
        for _, l in ipairs(labels) do l.TextTransparency = a end
    end
    task.spawn(function()
        for i = 1, 6 do   -- unfold open + fade in (list reflows as it grows)
            task.wait(0.025)
            if not e.Parent then return end
            local a = i / 6
            e.Size = UDim2.fromOffset(0, math.floor(19 * (1 - (1 - a) * (1 - a)) + 0.5))
            setFade(1 - a)
        end
        if sheen then   -- one accent sheen sweeping the top liner
            task.spawn(function()
                for i = 0, 8 do
                    if not liner2.Parent then return end
                    sheen.Offset = Vector2.new(-1 + i / 4, 0)
                    task.wait(0.035)
                end
                if sheen.Parent then sheen.Offset = Vector2.new(0, 0) end
            end)
        end
        local t0 = tick()
        while tick() - t0 < math.max(1, HC.killfeedTime) do
            task.wait(0.1)
            if not e.Parent then return end
        end
        for i = 1, 8 do   -- fade out + collapse shut
            task.wait(0.045)
            if not e.Parent then return end
            setFade(i / 8)
            e.Size = UDim2.fromOffset(0, math.floor(19 * (1 - i / 8) + 0.5))
        end
        pcall(function() e:Destroy() end)
    end)
end

-- one confirmed hit (same trigger as the hit sound): fan out to every enabled FX
local _killT = {}
local function onConfirmedHit(plr, hum, oldHP, newHP)
    local model = hum.Parent
    local isKill = newHP <= 0.5 and (tick() - (_killT[plr] or 0) > 2)
    if isKill then _killT[plr] = tick() end
    if HC.dmgNumbers then pcall(spawnDmgNumber, model, oldHP - newHP) end
    if isKill and HC.killSound then pcall(playKillSound) end
    if isKill and HC.killEffect then
        pcall(spawnKillEffect, model)   -- kill effect replaces the plain hit cham on the killing blow
    elseif HC.hitChams then
        pcall(spawnHitCham, model)
    end
    if isKill and HC.killfeed then pcall(killfeedAdd, plr, model) end
end
HUD.onConfirmedHit = onConfirmedHit
HUD.destroyRadar = destroyRadar
HUD.destroyKillfeed = destroyKillfeed
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

-- a real shot landed (server ammo dropped): tracer to the engaged target, else crosshair.
-- Fast guns: the server's decrements for the tail of a spray can arrive AFTER the target
-- died/unlocked -- draw those to the body we were just shooting, not wherever the camera
-- drifted (that's the SMG "tracer at my crosshair" phantom).
local _lastShotPart, _lastShotPartT = nil, 0
local function onAmmoShot()
    local hitPos
    local plr = getTarget()
    local part = plr and plr.Character and forceShotPart(plr.Character)
    if part then
        _lastShotPart, _lastShotPartT = part, tick()
    elseif _lastShotPart and _lastShotPart.Parent and (tick() - _lastShotPartT < FX_WINDOW) then
        part = _lastShotPart
    end
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

-- ammo watcher: re-attaches when the equipped gun changes. SOLE trigger: a shot
-- drops Ammo by exactly ONE (same guard as Zee). Ignore increases (pickup), the
-- reload reset / multi-step value dances, and any change while reloading --
-- otherwise a reload after the target dies keeps "firing" phantom tracers at
-- whatever the crosshair points at.
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
        if not old or (old - newV) ~= 1 then return end
        -- HC's reload flags are "Reloading"/"Reloading_CLIENT" (Zee's game calls it "Reload")
        local mdl = hcModel(LocalPlayer)
        local be = mdl and mdl:FindFirstChild("BodyEffects")
        if be then
            for _, nm in ipairs({ "Reloading", "Reloading_CLIENT", "Reload" }) do
                local r = be:FindFirstChild(nm)
                if r and r.Value == true then return end
            end
        end
        onAmmoShot()
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
            HUD.onConfirmedHit(plr, hum, old, newHP)   -- chams/kill fx/dmg numbers/killfeed, each own-gated
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
local _asLastTarget, _asWasEngaged = nil, false
local AS_FRESH_GAP = 0.05   -- minimum gap for a FRESH engagement (new target / just entered range)
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
    local plr = getTarget()
    if not plr then voidUnglue(); _asWasEngaged, _asLastTarget = false, nil; return end
    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return end
    -- Effective reach is the gun's max shot range; Wallbang extends it by the origin-spoof budget
    -- (fireShootAt pulls the shot origin back within range so it validates). Never exceed the reach
    -- or the server errors "range too long"; also honor a tighter user cap.
    local reach = MAX_SHOT_RANGE + ((HC.wallbang and math.min(HC.wallbangOffset, WB_HARD_CAP)) or 0)
    local maxDist = math.min(HC.autoShootDist, reach)
    if (lhrp.Position - hrp.Position).Magnitude > maxDist then _asWasEngaged = false; return end
    if HC.autoShootVis and char:FindFirstChildOfClass("ForceField") then _asWasEngaged = false; return end
    -- React INSTANTLY the moment a target becomes engageable (new target, or one that just
    -- rushed/teleported into range) so we get the first shot off; only then fall back to the
    -- configured cooldown for sustained fire. A tiny floor prevents same-burst double-firing.
    local fresh = (plr ~= _asLastTarget) or (not _asWasEngaged)
    local gap = fresh and math.min(AS_FRESH_GAP, HC.autoShootCooldown) or HC.autoShootCooldown
    if tick() - _asLast < gap then return end
    _asLastTarget, _asWasEngaged = plr, true
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
    if not HC.stomp or _tpsActive then return end
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
    if _tpsActive then return end   -- don't glue / capture a return point while TP-shooting
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
    if _stomping and _stompSavedCF and not HC.stompTeleport and not _tpsActive then
        local lc = LocalPlayer.Character
        local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
        if lhrp then pcall(function() lhrp.CFrame = _stompSavedCF end) end
    end
end)

-- ============================================================
--  TP SHOOT  (keybind: teleport to an advantage on the target, shoot, teleport back)
--    Wallbang -- TP to cover the target can't shoot through; we still hit via the
--                origin-spoof (wallbangOrigin), so "they can't hit me, I can hit him".
--    Max Range-- TP high above the target (200 studs + wallbang range) and shoot down; if a
--                roof/wall is overhead, TP just ABOVE it and wallbang straight down through it.
--    Glue     -- glue 50 studs above the target: settle 0.2s, shoot, linger ~1s, return.
--    Inside   -- like Glue but glued right inside the target.
--  We actually move (the CFrame is re-asserted each Heartbeat so the server registers the
--  pose) -> the shot origin == our real position and validates -> then we restore.
-- ============================================================
local TPS_GLUE_Y = 50
local TPS_WALL_RANGE = 90   -- wallbang: max distance to look for cover (prefer nearby buildings)
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
-- a WALL/building cover spot the target can't shoot us from, but from which a VALID <=11-stud
-- origin-spoof still reaches them. Every candidate is validated with wallbangOrigin itself, so
-- we only teleport somewhere the shot will actually land. Returns nil if no nearby wall works
-- (the caller then tries under-the-street, then inside the target).
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

    -- ring out from the target; hide just behind the first wall in each direction. Prefer the
    -- CLOSEST wall (small nearby buildings) within TPS_WALL_RANGE -- never teleport miles away.
    local walls = {}
    for a = 0, 345, 15 do
        local rad = math.rad(a)
        local dir = Vector3.new(math.cos(rad), 0, math.sin(rad))
        local res = Workspace:Raycast(tpos + Vector3.new(0, 1, 0), dir * TPS_WALL_RANGE, params)
        if res and res.Distance > 3 then
            walls[#walls + 1] = { pos = res.Position + dir * 2.5 + Vector3.new(0, 0.5, 0), d = res.Distance }
        end
    end
    table.sort(walls, function(a, b) return a.d < b.d end)   -- nearest small walls first
    for _, w in ipairs(walls) do
        if inAir(w.pos) and hasCover(w.pos) and wallbangOrigin(w.pos, part) then return CFrame.new(w.pos) end
    end
    return nil   -- no wall cover -> caller falls back to under-street, then inside
end
-- guaranteed fallback: drop just under the street/ground beneath the target. The road is
-- the cover (they can't shoot down through it); the origin-spoof peeks straight up through
-- the thin slab to the target. Works even if our body ends up inside the slab -- only the
-- spoofed origin needs clear air, and that's a short hop up.
local function tpsBelowStreet(targetModel, thrp)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = tpsIgnoreList(targetModel)
    local down = Workspace:Raycast(thrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, -200, 0), params)
    local top = (down and down.Position) or (thrp.Position - Vector3.new(0, 3, 0))
    return CFrame.new(top - Vector3.new(0, 4.5, 0))   -- fully under the road so we're never visible (velocity is zeroed so we don't float up)
end
-- clear line of fire from `from` to `toPos`? ignores our body + every OTHER player (so a
-- teammate in the way doesn't count) but KEEPS the target model, so "first hit is the target"
-- still reads as clear. nil hit (open air) also counts as clear.
local function tpsLosClear(from, toPos, targetModel)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ig = {}
    local lc = LocalPlayer.Character; if lc then ig[#ig + 1] = lc end
    local x = Workspace:FindFirstChild("Ignored"); if x then ig[#ig + 1] = x end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local m = hcModel(p); if m and m ~= targetModel then ig[#ig + 1] = m end
        end
    end
    params.FilterDescendantsInstances = ig
    local res = Workspace:Raycast(from, toPos - from, params)
    if not res then return true end
    return targetModel ~= nil and res.Instance:IsDescendantOf(targetModel)
end
-- Max Range helper: a roof/wall sits between the target and the apex above them. Cast straight
-- UP from the target through the obstruction and drop us just under its underside (directly over
-- the target) so the shot straight down is clear. Returns nil if nothing overhead within `height`.
local function tpsUnderRoof(targetModel, thrp, height)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = tpsIgnoreList(targetModel)   -- ignores target + all players + us + Ignored
    local res = Workspace:Raycast(thrp.Position + Vector3.new(0, 2, 0), Vector3.new(0, height, 0), params)
    if not res then return nil end
    local y = math.max(res.Position.Y - 3, thrp.Position.Y + 3)      -- 3 studs under the roof, but never below the target
    return Vector3.new(thrp.Position.X, y, thrp.Position.Z)
end
-- Max Range helper: cast DOWN from the apex to the roof/wall covering the target and drop us
-- just ABOVE its top surface (over the target) -- close enough that the <=11-stud origin-spoof
-- can punch DOWN through the roof to the target. Returns nil if nothing is overhead.
local function tpsAboveRoof(targetModel, thrp, apexY)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = tpsIgnoreList(targetModel)   -- ignores target + all players + us + Ignored
    local from = Vector3.new(thrp.Position.X, apexY, thrp.Position.Z)
    local res = Workspace:Raycast(from, Vector3.new(0, -(apexY - thrp.Position.Y), 0), params)
    if not res then return nil end
    return Vector3.new(thrp.Position.X, res.Position.Y + 2, thrp.Position.Z)   -- 2 studs above the roof top
end
-- closest LOCKED target that passes the checks (minus visible). Ranked by world distance,
-- NOT the crosshair -- so TP-shoot works on a locked target without looking at them.
local function tpsPickTarget()
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    local best, bestD
    for _, plr in ipairs(liveTargets()) do
        if canEngageNoVis(plr) then
            local m = hcModel(plr)
            local hrp = m and m:FindFirstChild("HumanoidRootPart")
            local d = (hrp and lhrp) and (hrp.Position - lhrp.Position).Magnitude or math.huge
            if not bestD or d < bestD then bestD, best = d, plr end
        end
    end
    return best
end
local function tpShoot()
    if _tpsActive then return end
    local plr = tpsPickTarget()           -- locked target, checks minus visible, no crosshair needed
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
    local method = HC.tpShootMethod
    local g = gv()
    -- pause desync for the burst so it can't spoof our root into the sky mid-teleport
    -- (which flings / kills the real character). Use the desync's captured real CFrame
    -- as our return point, since right now our root may be at the spoofed position.
    local SHARED = g and g._WH_DESYNC
    if SHARED then SHARED.pause = true end
    local saved = (SHARED and SHARED.realCF) or lhrp.CFrame
    local savedWbOffset = HC.wallbangOffset
    if method == "Wallbang" or method == "Max Range" then HC.wallbangOffset = 9 end   -- tighter origin-spoof budget for TP-shoot (stay well under the 10-stud mismatch cap)
    local function curHRP()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end
    local function place(cf)
        local h = curHRP()
        -- zero velocity each frame so gluing inside / above a colliding target doesn't build
        -- up momentum that flings us back toward them the instant we restore our real CFrame
        if h then pcall(function() h.CFrame = cf; h.AssemblyLinearVelocity = Vector3.zero end) end
        if g and g.WH and g.WH.markServerCF then pcall(function() g.WH.markServerCF(cf) end) end
    end
    local function fire()
        local m = plr.Character or hcModel(plr)
        local part = m and forceShotPart(m); if not part then return false end
        if HC.autoEquip and HC.autoEquipTool ~= "" then tryEquipNamed(HC.autoEquipTool) end
        local ok = false
        pcall(function() ok = fireShootAt(part) end)
        return ok   -- false if no valid origin (e.g. wallbang couldn't find a clear spoof)
    end

    task.spawn(function()
        local lh0 = curHRP()
        -- NOTE: do NOT anchor the HRP here. Anchoring stops the character's movement
        -- replication, so the server never sees the teleport and every shot's origin
        -- mismatches our last replicated position -> "too many origin mismatches" kick.
        -- We set the CFrame on the UNANCHORED root (like void/stomp) so it replicates.
        if SHARED and lh0 then pcall(function() lh0.CFrame = saved end) end   -- snap to real if desync had us spoofed
        pcall(function()
            if method == "Glue" or method == "Inside" then
                -- follow the target (glued 50 above, or right inside it), settle briefly,
                -- shoot, then stay for ~0.5s
                local yoff = (method == "Glue") and TPS_GLUE_Y or 0
                local start, firedAt = tick(), nil
                while true do
                    local th = plr.Character or hcModel(plr)
                    th = th and th:FindFirstChild("HumanoidRootPart")
                    if not th then break end
                    place(CFrame.new(th.Position + Vector3.new(0, yoff, 0)))
                    if not firedAt and tick() - start >= 0.06 and fire() then firedAt = tick() end   -- retry until it lands
                    if firedAt and tick() - firedAt >= 0.2 then break end      -- stay 0.2s after the shot
                    if not firedAt and tick() - start >= 1.2 then break end   -- safety if it can't fire
                    RunService.Heartbeat:Wait()
                end
                return
            end
            local cf
            if method == "Max Range" then
                for _ = 1, 3 do RunService.Heartbeat:Wait() end   -- let the gun finish equipping
                local th = plr.Character or hcModel(plr)
                th = th and th:FindFirstChild("HumanoidRootPart")
                if not th then return end
                local part = forceShotPart(plr.Character or hcModel(plr))
                local budget = math.min(HC.wallbangOffset, WB_HARD_CAP)   -- forced to 9 for this burst
                -- Sit near the gun's max range + the spoof budget (hard to shoot back). The origin
                -- ALWAYS gets spoofed toward the target so origin->hit lands back inside MAX_SHOT_RANGE
                -- (a raw shot from up here errors "range too long"). Keep a couple studs of headroom.
                local apex = th.Position + Vector3.new(0, MAX_SHOT_RANGE + budget - 4, 0)
                if not part then
                    cf, _tpsWallbang = CFrame.new(apex), false
                elseif tpsLosClear(apex, part.Position, tmodel) then
                    cf, _tpsWallbang = CFrame.new(apex), true         -- clear sky: spoof the far origin back into range
                else
                    -- a roof/wall is overhead: TP just ABOVE it and wallbang straight down through it
                    local above = tpsAboveRoof(tmodel, th, apex.Y)
                    if above and wallbangOrigin(above, part) then
                        cf, _tpsWallbang = CFrame.new(above), true    -- punch the origin-spoof down through the roof
                    elseif above and tpsLosClear(above, part.Position, tmodel) then
                        cf, _tpsWallbang = CFrame.new(above), true    -- clear from just above (spoof handles range)
                    else
                        -- roof too thick to wallbang from above -> drop UNDER it for a clear downward shot
                        local under = tpsUnderRoof(tmodel, th, MAX_SHOT_RANGE + budget)
                        if under and tpsLosClear(under, part.Position, tmodel) then
                            cf, _tpsWallbang = CFrame.new(under), true
                        elseif under and wallbangOrigin(under, part) then
                            cf, _tpsWallbang = CFrame.new(under), true
                        else
                            cf, _tpsWallbang = CFrame.new(th.Position), false   -- last resort: point-blank inside
                        end
                    end
                end
            else                                    -- Wallbang
                for _ = 1, 3 do RunService.Heartbeat:Wait() end   -- let the gun finish equipping
                local th = plr.Character or hcModel(plr)
                th = th and th:FindFirstChild("HumanoidRootPart")
                if not th then return end
                local part = forceShotPart(plr.Character or hcModel(plr))
                -- 1) nearby wall / building cover
                cf = part and tpsCoverSpot(tmodel, th, part)
                _tpsWallbang = cf ~= nil
                -- 2) fallback: under the street (only if a valid up-spoof actually reaches them)
                if not cf and part then
                    local us = tpsBelowStreet(tmodel, th)
                    if us and wallbangOrigin(us.Position, part) then cf, _tpsWallbang = us, true end
                end
                -- 3) last resort: inside the target -- point-blank, clear LoS, so no origin spoof
                if not cf then cf, _tpsWallbang = CFrame.new(th.Position), false end
            end
            local s = tick()
            while tick() - s < 0.06 do place(cf); RunService.Heartbeat:Wait() end   -- brief settle before shooting
            -- keep trying until the shot actually goes out -- the target may move or the
            -- spoof origin may need a fresh spot; for wallbang, re-pick cover on each miss
            local fired, ftry = false, tick()
            while not fired and tick() - ftry < 0.4 do
                fired = fire()
                if not fired and _tpsWallbang and method ~= "Max Range" then   -- Max Range stays up high; just retry from its spot
                    local th2 = plr.Character or hcModel(plr)
                    th2 = th2 and th2:FindFirstChild("HumanoidRootPart")
                    local part2 = forceShotPart(plr.Character or hcModel(plr))
                    local ncf = (th2 and part2) and (tpsCoverSpot(tmodel, th2, part2) or tpsBelowStreet(tmodel, th2))
                    if ncf then cf = ncf end
                end
                place(cf); RunService.Heartbeat:Wait()
            end
            local ls = tick()
            while tick() - ls < 0.15 do place(cf); RunService.Heartbeat:Wait() end   -- linger before teleporting back
        end)
        _tpsWallbang = false
        HC.wallbangOffset = savedWbOffset
        local h = curHRP()
        if h then pcall(function()
            h.CFrame = saved
            h.AssemblyLinearVelocity = Vector3.zero    -- kill glue momentum so we stay at our real spot
            h.AssemblyAngularVelocity = Vector3.zero
        end) end
        if g and g.WH and g.WH.markServerCF then pcall(function() g.WH.markServerCF(saved) end) end
        if SHARED then SHARED.pause = false end   -- resume desync from our restored real position
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

-- ---- Force Allow Jump (witherhook method): the game caps you at 3 jumps by zeroing
--      Humanoid.JumpPower. React the INSTANT it changes JumpPower (GetPropertyChangedSignal,
--      no polling lag) and re-enable the Jumping state; on Space re-enforce + request a jump.
--      hum.Jump only fires when grounded, so the cap is lifted without an infinite air-jump. ----
local _fjConns, _fjReal = {}, 50
local function _fjClear()
    for _, c in ipairs(_fjConns) do pcall(function() c:Disconnect() end) end
    _fjConns = {}
end
local function _fjEnforce(hum)
    if not hum then return end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
    pcall(function()
        if hum.JumpPower > 0 then _fjReal = hum.JumpPower        -- learn the normal value
        elseif hum.UseJumpPower then hum.JumpPower = _fjReal      -- game zeroed it -> restore now
        elseif hum.JumpHeight <= 0 then hum.JumpHeight = 7.2 end
    end)
end
local function _fjHookChar(char)
    _fjClear()
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    if not hum then return end
    _fjEnforce(hum)
    table.insert(_fjConns, hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
        if HC.forceJump then _fjEnforce(hum) end
    end))
end
local _fjCharConn
local function setForceJump(on)
    HC.forceJump = on
    if on then
        if not _fjCharConn then
            _fjCharConn = LocalPlayer.CharacterAdded:Connect(function(c) if HC.forceJump then _fjHookChar(c) end end)
            track(_fjCharConn)
        end
        if LocalPlayer.Character then _fjHookChar(LocalPlayer.Character) end
    else
        _fjClear()
    end
end
track(UIS.InputBegan:Connect(function(input, gp)
    if gp or not HC.forceJump then return end
    if input.KeyCode ~= Enum.KeyCode.Space then return end
    local c = LocalPlayer.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if hum then _fjEnforce(hum); pcall(function() hum.Jump = true end) end   -- grounded-only jump request
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

-- ============================================================
--  FAKE POS -- the knife bot's PhysicsRepRootPart re-root as a standalone toggle:
--  replication is rooted onto the target's HRP, so the server (and everyone else)
--  sees us AT the target while the local character walks around freely. Follows the
--  same target resolution as the knife bot (checks minus visibility). _WH_HC_SENT
--  keeps fireShootAt's origin at the fake spot (voidshoot's contract), so force hit /
--  auto shoot validate point-blank instead of tripping "origin mismatch".
--  State/detach live on PC -- this chunk rides the 200-locals limit, no new locals.
-- ============================================================
PC.fpAttached = false
function PC.fakePosDetach()
    if not PC.fpAttached then return end
    PC.fpAttached = false
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if lhrp and sethiddenproperty then pcall(function() sethiddenproperty(lhrp, "PhysicsRepRootPart", lhrp) end) end
    local g = gv(); if g then g._WH_HC_SENT = nil end
end
track(RunService.Heartbeat:Connect(function()
    -- knife aura already runs this exact re-root itself; stomp / TP shoot need the REAL
    -- position replicating for their own spoofs to validate -- stand down for all three
    if not HC.fakePos or HC.knifeAura or _stomping or _tpsActive then PC.fakePosDetach(); return end
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    local tHrp = knifeTargetHrp()
    if not lhrp or not tHrp then PC.fakePosDetach(); return end
    local tPos = tHrp.Position
    if tPos ~= tPos or tPos.Magnitude > 1e6 then return end
    pcall(function() lhrp:SetNetworkOwner(LocalPlayer) end)
    if sethiddenproperty then pcall(function() sethiddenproperty(lhrp, "PhysicsRepRootPart", tHrp) end) end
    PC.fpAttached = true
    local fakeCF = CFrame.new(tPos)
    local g = gv()
    if g then g._WH_HC_SENT = fakeCF end
    if g and g.WH and g.WH.markServerCF then g.WH.markServerCF(fakeCF) end   -- Server Pos clone follows
end))

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
            local to = Vector2.new(sp.X, sp.Y)
            if sp.Z <= 0 then
                -- target is BEHIND the camera: WorldToViewportPoint mirrors the point, so the
                -- raw coord points the wrong way (old code just hid the line here). Reflect it
                -- across screen centre and extend well past the edge so the line keeps pointing
                -- toward the off-screen target instead of disappearing.
                local center = Vector2.new(vs.X * 0.5, vs.Y * 0.5)
                local d = center - to
                if d.Magnitude < 1e-3 then d = Vector2.new(0, 1) end
                to = center + d.Unit * (vs.Magnitude)
            end
            rbLine.To = to
            rbLine.Color = HC.lineColor
            rbLine.Visible = true
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
        -- the candidate search is way too heavy to run per frame -- 10 Hz, cached between.
        -- The "is it a real spoof?" check must compare against the root position AT COMPUTE
        -- TIME (PC.wbVizReal): with clear LoS the search returns that root position, and
        -- comparing it to the CURRENT root while running made the stale point trail >0.5
        -- studs behind -- the marker drew ON our own character. Target switch: hide until
        -- the next tick rather than recomputing (a flapping target would re-run the full
        -- search per frame again).
        local origin, real
        if root and part then
            if part ~= PC.wbVizPart then PC.wbVizOrigin = nil end
            if os.clock() - PC.wbVizT >= 0.1 then
                PC.wbVizT = os.clock()
                PC.wbVizPart = part
                PC.wbVizReal = root.Position
                PC.wbVizOrigin = wallbangOrigin(root.Position, part)
            end
            origin, real = PC.wbVizOrigin, PC.wbVizReal
        else
            PC.wbVizOrigin, PC.wbVizPart = nil, nil
        end
        if origin and real and (origin - real).Magnitude > 0.5 then
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
    Sec2:Slider({ Name = "Max origin offset", Flag = "HC_WallbangOffset", Min = 0, Max = 10, Default = 10, Decimals = 0, Suffix = " studs",
        Callback = function(v) HC.wallbangOffset = v end })
    Sec2:Toggle({ Name = "Visualize wallbang spot", Flag = "HC_WbVisualize", Default = false,
        Callback = function(v) HC.wbVisualize = v end })
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

    local SecFP = RageSub:Section({ Name = "Fake Pos", Side = 1 })
    SecFP:Toggle({ Name = "Fake pos (appear on target)", Flag = "HC_FakePos", Default = false,
        Callback = function(v) HC.fakePos = v end })

    local Sec2 = RageSub:Section({ Name = "Auto Equip", Side = 2 })
    Sec2:Toggle({ Name = "Auto equip on shoot", Flag = "HC_AutoEquip", Default = false,
        Callback = function(v) HC.autoEquip = v end })
    Sec2:Textbox({ Name = "Tool name", Flag = "HC_AutoEquipTool", Placeholder = "exact tool name",
        Callback = function(v) HC.autoEquipTool = v or "" end })

    local Sec3 = RageSub:Section({ Name = "TP Shoot", Side = 2 })
    Sec3:Dropdown({ Name = "Method", Flag = "HC_TpShootMethod", Default = "Wallbang", Multi = false,
        Items = { "Wallbang", "Max Range", "Glue", "Inside" },
        Callback = function(v) HC.tpShootMethod = (type(v) == "table" and v[1]) or v or "Wallbang" end })
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

-- 5) FX  -- all hit feedback + target visuals in one place
local FxSub = MainPage:SubPage({ Name = "FX" })
do
    local Sec = FxSub:Section({ Name = "Hit Chams", Side = 1 })
    Sec:Toggle({ Name = "Hit chams", Flag = "HC_HitChams", Default = false,
        Callback = function(v) HC.hitChams = v; if not v then clearChams() end end })
    Sec:Slider({ Name = "Duration", Flag = "HC_HitChamsDur", Min = 0.5, Max = 5, Default = 2, Decimals = 1, Suffix = " s",
        Callback = function(v) HC.hitChamsDuration = v end })
    Sec:Slider({ Name = "Transparency", Flag = "HC_HitChamsTrans", Min = 0, Max = 1, Default = 0.5, Decimals = 2,
        Callback = function(v) HC.hitChamsTransparency = v end })
    Sec:Dropdown({ Name = "Material", Flag = "HC_HitChamsMat", Default = "ForceField", Multi = false,
        Items = { "ForceField", "Neon", "Plastic", "SmoothPlastic", "Glass", "Metal" },
        Callback = function(v) HC.hitChamsMaterial = (type(v) == "table" and v[1]) or v or "ForceField" end })
    Sec:Label({ Name = "Cham color" }):Colorpicker({ Flag = "HC_HitChamsColor", Default = Color3.fromRGB(255, 60, 60),
        Callback = function(c) HC.hitChamsColor = c end })
    Sec:Toggle({ Name = "Outline", Flag = "HC_HitChamsOutline", Default = false,
        Callback = function(v) HC.hitChamsOutline = v end })
    Sec:Label({ Name = "Outline color" }):Colorpicker({ Flag = "HC_HitChamsOutlineColor", Default = Color3.fromRGB(255, 255, 255),
        Callback = function(c) HC.hitChamsOutlineColor = c end })

    local Sec2 = FxSub:Section({ Name = "Target Line", Side = 1 })
    if not hasDrawing then Sec2:Label({ Name = "Needs a Drawing-capable executor." }) end
    Sec2:Toggle({ Name = "Target line", Flag = "HC_TargetLine", Default = false,
        Callback = function(v) HC.targetLine = v end })
    Sec2:Dropdown({ Name = "Line origin", Flag = "HC_LineOrigin", Default = "Bottom", Multi = false,
        Items = { "Bottom", "Top", "Center", "Mouse" },
        Callback = function(v) HC.lineOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    Sec2:Label({ Name = "Line color" }):Colorpicker({ Flag = "HC_LineColor", Default = Color3.fromRGB(255, 60, 60),
        Callback = function(c) HC.lineColor = c end })

    -- fake bullet tracer + hit sound (the synth never renders gun visuals)
    local Sec3 = FxSub:Section({ Name = "Tracers", Side = 2 })
    Sec3:Toggle({ Name = "Bullet tracers", Flag = "HC_Tracer", Default = true,
        Callback = function(v) HC.tracerEnabled = v end })
    Sec3:Dropdown({ Name = "Tracer style", Flag = "HC_TracerStyle", Default = "Standard", Multi = false,
        Items = { "Standard", "Laser", "Thin" },
        Callback = function(v) HC.tracerStyle = (type(v) == "table" and v[1]) or v or "Standard" end })
    Sec3:Label({ Name = "Tracer color" }):Colorpicker({ Flag = "HC_TracerColor", Default = Color3.fromRGB(0, 255, 80),
        Callback = function(c) HC.tracerColor = c end })
    Sec3:Toggle({ Name = "Through walls", Flag = "HC_TracerWalls", Default = true,
        Callback = function(v) HC.tracerThroughWalls = v end })
    Sec3:Slider({ Name = "Size", Flag = "HC_TracerSize", Min = 0.005, Max = 1, Default = 0.12, Decimals = 3,
        Callback = function(v) HC.tracerThickness = v end })
    Sec3:Slider({ Name = "Lifetime", Flag = "HC_TracerLife", Min = 0.1, Max = 3, Default = 0.2, Decimals = 2, Suffix = "s",
        Callback = function(v) HC.tracerLifetime = v end })

    local Sec4 = FxSub:Section({ Name = "Hit Sound", Side = 2 })
    Sec4:Toggle({ Name = "Hit sound", Flag = "HC_HitSound", Default = true,
        Callback = function(v) HC.hitSoundEnabled = v end })
    Sec4:Slider({ Name = "Hit sound volume", Flag = "HC_HitSoundVol", Min = 0, Max = 500, Default = 100, Decimals = 0, Suffix = "%",
        Callback = function(v) HC.hitSoundVolume = v / 100 end })

    local Sec5 = FxSub:Section({ Name = "Target Outline", Side = 2 })
    Sec5:Toggle({ Name = "Target outline", Flag = "HC_TargetOutline", Default = false,
        Callback = function(v) HC.targetOutline = v end })
    Sec5:Label({ Name = "Outline color" }):Colorpicker({ Flag = "HC_OutlineColor", Default = Color3.fromRGB(255, 80, 80),
        Callback = function(c) HC.outlineColor = c end })
end

-- 6) HUD  -- radar, damage numbers, killfeed, kill effect
local HudSub = MainPage:SubPage({ Name = "HUD" })
do
    local Sec = HudSub:Section({ Name = "Radar", Side = 1 })
    Sec:Toggle({ Name = "Radar", Flag = "HC_Radar", Default = false,
        Callback = function(v) HC.radar = v end })
    Sec:Slider({ Name = "Size", Flag = "HC_RadarSize", Min = 120, Max = 300, Default = 180, Decimals = 0, Suffix = " px",
        Callback = function(v) HC.radarSize = v end })
    Sec:Slider({ Name = "Range", Flag = "HC_RadarRange", Min = 50, Max = 1000, Default = 300, Decimals = 0, Suffix = " studs",
        Callback = function(v) HC.radarRange = v end })
    Sec:Label({ Name = "Drag the panel to move it." })

    local Sec2 = HudSub:Section({ Name = "Damage Numbers", Side = 1 })
    Sec2:Toggle({ Name = "Damage numbers", Flag = "HC_DmgNum", Default = false,
        Callback = function(v) HC.dmgNumbers = v end })
    Sec2:Slider({ Name = "Scale", Flag = "HC_DmgNumScale", Min = 0.5, Max = 2, Default = 1, Decimals = 2,
        Callback = function(v) HC.dmgNumScale = v end })

    local Sec3 = HudSub:Section({ Name = "Killfeed", Side = 2 })
    Sec3:Toggle({ Name = "Killfeed", Flag = "HC_Killfeed", Default = false,
        Callback = function(v) HC.killfeed = v end })
    Sec3:Slider({ Name = "Entry lifetime", Flag = "HC_KillfeedTime", Min = 2, Max = 12, Default = 5, Decimals = 0, Suffix = " s",
        Callback = function(v) HC.killfeedTime = v end })

    local Sec4 = HudSub:Section({ Name = "Kill Effect", Side = 2 })
    Sec4:Toggle({ Name = "Kill effect (dissolve + shockwave)", Flag = "HC_KillFx", Default = false,
        Callback = function(v) HC.killEffect = v end })
    Sec4:Toggle({ Name = "Kill sound", Flag = "HC_KillSound", Default = false,
        Callback = function(v) HC.killSound = v end })
    Sec4:Label({ Name = "Uses the Hit Chams color." })
end

-- 7) Misc
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
    Sec2:Toggle({ Name = "Force Allow Jump", Flag = "HC_ForceJump", Default = false,
        Callback = function(v) setForceJump(v) end })
end

-- ============================================================
--  8) Server Sniper  -- find which FFA/Anarchy server a player is in and join it.
--
--  The game's own FFA menu (CustomCoreGUI.FFA.ServerList) is populated from
--  ReplicatedStorage.MainFunction:InvokeServer("GetFFAServerList"), which returns
--  every listed public server as { JobId, PlayerIDs (FULL userId list), Players,
--  Location, RegionName, ACCESS_CODE, ... }. We query that directly, scan
--  PlayerIDs for the target's userId, and join with the game's own remote
--  MainEvent:FireServer("JOIN_FFA_SERVER", JobId) -- the exact call the Join
--  button fires. A Mode dropdown swaps to the Anarchy list/join remotes
--  (GetAnarchyServerList / JOIN_ANARCHY_SERVER). Enter a username OR a userId;
--  the avatar preview confirms who.
-- ============================================================
local SniperSub = MainPage:SubPage({ Name = "Server Sniper" })
do
    local HttpService = game:GetService("HttpService")
    local reqfn = (syn and syn.request) or (http and http.request)
        or (type(http_request) == "function" and http_request)
        or (type(request) == "function" and request)
        or (fluxus and fluxus.request)

    local lastFoundJob = nil   -- JobId of the last successful find (for the Join button)
    local scanning = false
    local mode = "FFA"         -- "FFA" | "Anarchy" -- which server list to scan + which join remote
    local function listRemote() return mode == "Anarchy" and "GetAnarchyServerList" or "GetFFAServerList" end
    local function joinRemote() return mode == "Anarchy" and "JOIN_ANARCHY_SERVER" or "JOIN_FFA_SERVER" end

    -- ---- UI ----
    local Sec = SniperSub:Section({ Name = "Target", Side = 1 })

    -- avatar preview: a raw ImageLabel dropped into the section's content frame
    -- (nhack has no image element). rbxthumb renders natively -- no web request.
    local avatarImg
    pcall(function()
        local content = Sec.Items["Content"].Instance
        local holder = Instance.new("Frame")
        holder.Name = "\0"
        holder.BackgroundTransparency = 1
        holder.Size = UDim2.new(1, 0, 0, 96)
        holder.Parent = content
        avatarImg = Instance.new("ImageLabel")
        avatarImg.AnchorPoint = Vector2.new(0.5, 0)
        avatarImg.Position = UDim2.new(0.5, 0, 0, 2)
        avatarImg.Size = UDim2.fromOffset(90, 90)
        avatarImg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        avatarImg.BackgroundTransparency = 0.25
        avatarImg.ScaleType = Enum.ScaleType.Fit
        avatarImg.Image = ""
        avatarImg.Parent = holder
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = avatarImg
        local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(90, 90, 90); stroke.Transparency = 0.3; stroke.Parent = avatarImg
    end)
    local function setAvatar(uid)
        if avatarImg then
            avatarImg.Image = uid and ("rbxthumb://type=AvatarHeadShot&id=" .. uid .. "&w=150&h=150") or ""
        end
    end

    local nameLbl = Sec:Label({ Name = "No target" })
    local box = Sec:Textbox({ Name = "Username or UserID", Flag = "HC_SniperInput",
        Placeholder = "e.g. builderman or 156" })
    Sec:Dropdown({ Name = "Mode", Flag = "HC_SniperMode", Default = "FFA", Multi = false,
        Items = { "FFA", "Anarchy" },
        Callback = function(v) mode = (type(v) == "table" and v[1]) or v or "FFA" end })

    local Sec2 = SniperSub:Section({ Name = "Result", Side = 2 })
    local statusLbl  = Sec2:Label({ Name = "Idle" })
    local serverLbl  = Sec2:Label({ Name = "Server: --" })
    local playersLbl = Sec2:Label({ Name = "Players: --" })
    local locLbl     = Sec2:Label({ Name = "Location: --" })

    -- ---- http helpers (only used to resolve a username / show a name) ----
    local function httpPost(url, tbl)
        if not reqfn then return nil end
        local ok, r = pcall(function()
            return reqfn({ Url = url, Method = "POST",
                Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(tbl) })
        end)
        if not ok or not r then return nil end
        local body = r.Body or r.body
        if not body then return nil end
        local ok2, dec = pcall(function() return HttpService:JSONDecode(body) end)
        return ok2 and dec or nil
    end
    local function httpGetJson(url)
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if not ok then return nil end
        local ok2, dec = pcall(function() return HttpService:JSONDecode(body) end)
        return ok2 and dec or nil
    end

    -- resolve the textbox input to (userId, displayName, err). All-digits = a userId.
    local function resolveTarget(input)
        input = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if input == "" then return nil, nil, "enter a username or userId" end
        if input:match("^%d+$") then
            local uid = tonumber(input)
            local d = httpGetJson("https://users.roblox.com/v1/users/" .. uid)
            return uid, (d and (d.name or d.displayName)) or ("User " .. uid)
        end
        local d = httpPost("https://users.roblox.com/v1/usernames/users",
            { usernames = { input }, excludeBannedUsers = false })
        if d and d.data and d.data[1] and d.data[1].id then
            return d.data[1].id, d.data[1].name
        end
        if not reqfn then return nil, nil, "no HTTP -- enter a numeric userId instead" end
        return nil, nil, "no user named '" .. input .. "'"
    end

    -- scan the live server list (FFA or Anarchy) for a userId. Returns {serverNum, jobId, players, location, region} | nil, err
    local function findServer(uid)
        local ok, list = pcall(function() return ReplicatedStorage.MainFunction:InvokeServer(listRemote()) end)
        if not ok or type(list) ~= "table" then return nil, "server list unavailable" end
        local idx = 0
        for _, s in pairs(list) do
            idx = idx + 1
            local ids = s.PlayerIDs
            if type(ids) == "table" then
                for _, id in pairs(ids) do
                    if tonumber(id) == tonumber(uid) then
                        return { serverNum = idx, jobId = s.JobId, players = s.Players,
                                 location = s.Location, region = s.RegionName }
                    end
                end
            end
        end
        return nil
    end

    local function joinJob(jobId)
        pcall(function() ReplicatedStorage.MainEvent:FireServer(joinRemote(), jobId) end)
    end

    local function clearResult()
        lastFoundJob = nil
        serverLbl:SetText("Server: --"); playersLbl:SetText("Players: --"); locLbl:SetText("Location: --")
    end

    -- full flow: resolve -> avatar -> scan -> (optionally) join
    local function snipe(autoJoin)
        if scanning then return end
        scanning = true
        clearResult()
        statusLbl:SetText("Resolving...")
        task.spawn(function()
            local uid, name, err = resolveTarget(box.Value)
            if not uid then
                statusLbl:SetText("x " .. (err or "could not resolve"))
                nameLbl:SetText("No target"); setAvatar(nil)
                scanning = false; return
            end
            setAvatar(uid)
            nameLbl:SetText((name or ("User " .. uid)) .. "  (" .. uid .. ")")
            statusLbl:SetText("Scanning " .. mode .. " servers...")
            local found, ferr = findServer(uid)
            if not found then
                if ferr then statusLbl:SetText("x " .. ferr)
                elseif uid == LocalPlayer.UserId and mode == "FFA" then statusLbl:SetText("That's you -- you're already here.")
                else statusLbl:SetText("Not in any listed " .. mode .. " server.") end
                scanning = false; return
            end
            lastFoundJob = found.jobId
            serverLbl:SetText("Server: #" .. found.serverNum)
            playersLbl:SetText("Players: " .. tostring(found.players or "?"))
            -- the list often returns literal "N/A" strings for Location/RegionName
            local function realStr(s) s = tostring(s or ""); return (s ~= "" and s ~= "N/A") and s or nil end
            local loc, reg = realStr(found.location), realStr(found.region)
            locLbl:SetText("Location: " .. ((loc and reg) and (loc .. ", " .. reg) or loc or reg or "unknown"))
            if found.jobId == game.JobId then
                statusLbl:SetText("Found -- they're in YOUR server!")
            elseif autoJoin then
                statusLbl:SetText("Found -- joining server #" .. found.serverNum .. "...")
                task.wait(0.3)
                joinJob(found.jobId)
            else
                statusLbl:SetText("Found in server #" .. found.serverNum .. " -- press Join.")
            end
            scanning = false
        end)
    end

    Sec:Button({ Name = "Find server", Callback = function() snipe(false) end })
    Sec:Button({ Name = "Find & Join", Callback = function() snipe(true) end })
    Sec2:Button({ Name = "Join found server", Callback = function()
        if not lastFoundJob then statusLbl:SetText("Nothing found yet -- Find first."); return end
        if lastFoundJob == game.JobId then statusLbl:SetText("Already in that server."); return end
        statusLbl:SetText("Joining...")
        joinJob(lastFoundJob)
    end })
end

-- ============================================================
--  Universal base AFTER Main, so Main stays the first tab.
-- ============================================================
pcall(function() ctx.load("games/combat.lua")(ctx) end)
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function hcCleanup()
    unloaded = true
    setForceHit(false)
    HC.autoShoot, HC.voidshoot, HC.stomp, HC.stompTargets, HC.reload = false, false, false, false, false
    HC.fakePos = false
    pcall(PC.fakePosDetach)    -- undo the fake-pos physics-rep desync
    HC.knifeAura, HC.knifeEquip, HC.antiAfk, HC.forceAfk, HC.godmode = false, false, false, false, false
    HC.knifeReach, HC.knifeReachVis = false, false
    HC.targetLine, HC.targetOutline, HC.ammoHud, HC.wbVisualize = false, false, false, false
    HC.hitChams = false
    HC.radar, HC.dmgNumbers, HC.killfeed, HC.killEffect, HC.killSound = false, false, false, false, false
    pcall(clearChams)
    pcall(clearTracerHL)
    pcall(HUD.destroyRadar)
    pcall(HUD.destroyKillfeed)
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
