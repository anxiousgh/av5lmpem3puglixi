-- ============================================================
--  games/70563721061619.lua  --  Zee  (Da Hood-style combat RP)
--
--  Force Hit  : forces YOUR shots onto the locked target nearest your crosshair
--               (replaces require(RS.Modules.GunHandler).Shoot -> returns the
--               target part; the game's own shot then carries it, incl. every
--               shotgun pellet). No __namecall hook (the game kicks for that).
--  Auto shoot : auto-fires ShootGun at the best hittable locked target. The checks
--               (knocked / range / visible) decide what counts as "hittable".
--  No Slowdown: deletes anything added to BodyEffects.Movement and forces
--               BodyEffects.Reload back off (kills move/reload slowdowns).
--  Auto reload: fires the Reload remote when the equipped gun is out of ammo.
--  Shotguns ([Double-Barrel SG] / [TacticalShotgun]) fire 5 pellets, never more.
--
--  FX (ported from Hood Customs): fake BULLET TRACERS (Beam glow + travel + impact
--               flash/light/particles) drawn per real shot. Each tracer ALWAYS gets a
--               solid neon core with a Highlight + BLACK outline; the "Through walls"
--               toggle flips its DepthMode (AlwaysOnTop vs Occluded). Size + lifetime
--               sliders, styles. Drawn only on
--               real shots (auto-shoot fireAt + a single-step Ammo-drop watcher) -- the
--               ammo watcher ignores reload/pickup jumps so no phantom tracers.
--               Plus the HC HIT SOUND (asset 121566025787365) on a target HP drop.
--  View target: swaps Camera.CameraSubject to the current target so you spectate them;
--               auto-restores to yourself when no target is alive.
--
--  !! Server-validated combat + human mods. Very visible -> burner only.
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")
local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera
local MainGameEvent = RS:WaitForChild("GameRemotes"):WaitForChild("MainGameEvent")

local MainPage = Window:Page({ Name = "Main" })
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local S = {
    forceHit = false, autoShoot = false, aura = false, hitPart = "Head",
    checkKnocked = true, checkRange = true, checkVisible = true,
    fastFire = false, fastFireCD = 0.06, autoReload = true, noSlowdown = false,
    outline = true, outlineColor = Color3.fromRGB(255, 60, 60),
    tracer = false, tracerColor = Color3.fromRGB(255, 60, 60), tracerOrigin = "Bottom",
    -- fake bullet tracers + hit sound (HC-style) + view target
    -- (tracers always get a highlighted core + black outline; through-walls toggles its DepthMode)
    btEnabled = false, btColor = Color3.fromRGB(255, 60, 60), btStyle = "Standard",
    btThickness = 0.12, btLifetime = 0.2, btThroughWalls = true,
    hitSoundEnabled = false, hitSoundId = 121566025787365, hitSoundVolume = 1.0,
    viewTarget = false,
}
local locked = {}   -- [player] = true
local FX = {}       -- bullet-tracer / hit-sound helpers (populated below)

-- ---- helpers ----
local wsPlayers = workspace:FindFirstChild("Players")
local function charOf(p) return (wsPlayers and wsPlayers:FindFirstChild(p.Name)) or p.Character end
local function myChar() return charOf(LP) end
local function aliveChar(p)
    local c = charOf(p); if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return nil end
    local be = c:FindFirstChild("BodyEffects"); local dead = be and be:FindFirstChild("Dead")
    if dead and dead.Value == true then return nil end
    return c:FindFirstChild("HumanoidRootPart") and c or nil
end
local function isKnocked(p)   -- HC-style: BodyEffects["K.O"].Value
    local c = charOf(p); local be = c and c:FindFirstChild("BodyEffects")
    local ko = be and be:FindFirstChild("K.O")
    return ko ~= nil and ko.Value == true
end
local function partOf(c) return c:FindFirstChild(S.hitPart) or c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart") end
local function equippedGun()
    local char = myChar(); if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("Range") and t:FindFirstChild("Handle") then return t end
    end
end
local function pelletCount(gun) return gun:FindFirstChild("GunClientShotgun") and 5 or 1 end   -- shotguns = 5
local function visibleTo(muzzle, part)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { myChar(), part.Parent }
    return workspace:Raycast(muzzle, part.Position - muzzle, params) == nil
end
local function nearestMousePlayer()
    local mouse = UIS:GetMouseLocation()
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local c = aliveChar(p)
            local part = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
            if part then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                    if not bestD or d < bestD then bestD, best = d, p end
                end
            end
        end
    end
    return best
end
local function activePool() return S.aura and Players:GetPlayers() or nil end   -- nil => iterate `locked`
Players.PlayerRemoving:Connect(function(p) locked[p] = nil end)

-- ---- bullet-tracer + hit-sound FX (ported from Hood Customs) ----
--  The forced/synth shots render no bullet visuals, so we fake them: a Beam glow
--  from the muzzle that travels to the hit + an impact flash/light/particle burst.
--  Optional "through walls" adds a solid neon core with an AlwaysOnTop Highlight.
do
    local _active, MAX = 0, 12
    local _lastAt, MIN_GAP = 0, 0.04
    local _lastDirect = 0
    local FX_WINDOW = 0.6
    local _shotT = 0

    -- muzzle = the gun attachment furthest from the body (barrel tip); falls back to
    -- the same handle offset the real shots use, then the head.
    local function muzzlePos()
        local gun = equippedGun()
        local c = myChar()
        if gun then
            local ref = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
            if ref then
                local best, bestD
                for _, d in ipairs(gun:GetDescendants()) do
                    if d:IsA("Attachment") then
                        local dd = (d.WorldPosition - ref.Position).Magnitude
                        if not bestD or dd > bestD then bestD, best = dd, d.WorldPosition end
                    end
                end
                if best then return best end
            end
            local h = gun:FindFirstChild("Handle")
            if h then return (h.CFrame * CFrame.new(-1, 0.4, 0)).Position end
        end
        local head = c and c:FindFirstChild("Head")
        return head and head.Position
    end
    FX.muzzlePos = muzzlePos

    local function anchor(pos)
        local p = Instance.new("Part")
        p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
        p.Size, p.Transparency, p.CFrame = Vector3.new(0.05, 0.05, 0.05), 1, CFrame.new(pos)
        p.Name = "\0_zt"; p.Parent = workspace
        return p
    end

    local function spawnTracer(origin, hitPos)
        if not (S.btEnabled and origin and hitPos) then return end
        local dist = (hitPos - origin).Magnitude
        if dist < 0.5 then return end
        local nowT = tick()
        if nowT - _lastAt < MIN_GAP then return end
        if _active >= MAX then return end
        _lastAt, _active = nowT, _active + 1
        task.delay(math.max(1.5, S.btLifetime + 1), function() _active = math.max(0, _active - 1) end)

        local dir = (hitPos - origin).Unit
        local col, th = S.btColor, S.btThickness
        local startPart, endPart = anchor(origin), anchor(origin)
        local att0 = Instance.new("Attachment", startPart)
        local att1 = Instance.new("Attachment", endPart)
        local beams = {}
        local function mkBeam()
            local b = Instance.new("Beam")
            b.Attachment0, b.Attachment1 = att0, att1
            b.LightEmission, b.LightInfluence, b.FaceCamera, b.Segments = 1, 0, true, 1
            b.Parent = startPart; beams[#beams + 1] = b; return b
        end
        if S.btStyle == "Laser" then
            local b = mkBeam(); b.Width0, b.Width1 = th * 1.2, th * 1.2
            b.Color, b.Transparency = ColorSequence.new(col), NumberSequence.new(0)
        elseif S.btStyle == "Thin" then
            local b = mkBeam(); b.Width0, b.Width1 = th * 0.6, th * 0.6
            b.Color, b.Transparency = ColorSequence.new(col), NumberSequence.new(0.1)
        else  -- Standard: outer halo + white-hot textured core
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

        -- ALWAYS add a solid neon core with a highlighted (+ black outline) silhouette. The
        -- through-walls toggle just picks the Highlight DepthMode: AlwaysOnTop (seen through
        -- geometry) vs Occluded (hidden behind walls). Core is kept thick enough that the
        -- silhouette + screen-space black outline read clearly at distance (0.06 was invisible).
        local core = Instance.new("Part")
        core.Anchored, core.CanCollide, core.CanTouch, core.CanQuery, core.CastShadow = true, false, false, false, false
        core.Material, core.Color = Enum.Material.Neon, col
        -- tiny floor only to avoid a degenerate 0-size part; the screen-space black outline
        -- keeps even a hairline core visible through walls, so thin is fine now.
        local cth = math.max(th, 0.01)
        core.Size = Vector3.new(cth, cth, dist)
        core.CFrame = CFrame.lookAt((origin + hitPos) / 2, hitPos)
        core.Name = "\0_zt"; core.Parent = workspace
        local coreHL = Instance.new("Highlight")
        coreHL.DepthMode = S.btThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        coreHL.FillColor, coreHL.FillTransparency = col, 0.2
        coreHL.OutlineColor, coreHL.OutlineTransparency = Color3.new(0, 0, 0), 0   -- black outline
        pcall(function() coreHL.Adornee = core end)
        coreHL.Parent = core

        task.spawn(function()
            for i = 1, 8 do  -- travel: extend the end attachment origin -> hit
                task.wait(0.06 / 8)
                if not startPart.Parent then return end
                endPart.CFrame = CFrame.new(origin + dir * (dist * (i / 8)))
            end
            if not startPart.Parent then return end
            endPart.CFrame = CFrame.new(hitPos)
            -- impact VFX: neon flash ball + point light + particle burst
            local flash = anchor(hitPos)
            flash.Transparency, flash.Material, flash.Color = 0, Enum.Material.Neon, col
            flash.Shape, flash.Size = Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6)
            local light = Instance.new("PointLight"); light.Color, light.Brightness, light.Range = col, 5, 10
            light.Parent = flash
            pcall(function()
                local att = Instance.new("Attachment", flash)
                local pe = Instance.new("ParticleEmitter")
                pe.Color, pe.LightEmission = ColorSequence.new(col), 1
                pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, th * 3), NumberSequenceKeypoint.new(1, 0) })
                pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
                pe.Speed, pe.Lifetime = NumberRange.new(6, 14), NumberRange.new(0.15, 0.35)
                pe.Rate, pe.SpreadAngle = 0, Vector2.new(180, 180)
                pe.Parent = att; pe:Emit(14)
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
            for i = 1, 8 do  -- fade beams + core over the lifetime
                task.wait(S.btLifetime / 8)
                if not startPart.Parent then return end
                for _, b in ipairs(beams) do if b.Parent then b.Transparency = NumberSequence.new(i / 8) end end
                if core and core.Parent then core.Transparency = i / 8 end
                -- keep the highlight SOLID for most of the lifetime, then fade only over the last
                -- ~3 steps -- otherwise the beam's glow lingers and the highlight looks like it
                -- died first. This way the highlight lasts at least as long as the tracer.
                if coreHL and coreHL.Parent then pcall(function()
                    local f = math.max(0, (i - 5) / 3)   -- 0 until i=5, ramps 0->1 by i=8
                    coreHL.FillTransparency = 0.2 + f * 0.8
                    coreHL.OutlineTransparency = f
                end) end
            end
            if startPart.Parent then startPart:Destroy() end
            if endPart.Parent then endPart:Destroy() end
            if core and core.Parent then core:Destroy() end
        end)
    end
    FX.spawnTracer = spawnTracer

    local function playHitSound()
        if not S.hitSoundEnabled or not S.hitSoundId or S.hitSoundId == 0 then return end
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://" .. tostring(S.hitSoundId)
        s.Volume = math.clamp(S.hitSoundVolume, 0, 5)
        s.Parent = pg or workspace
        s:Play()
        task.delay(5, function() if s and s.Parent then s:Destroy() end end)
    end
    FX.playHitSound = playHitSound

    -- current best target (nearest crosshair among the active set, alive only)
    local function bestTargetPlayer()
        local mouse = UIS:GetMouseLocation()
        local best, bestD
        local function tryP(p)
            if p == LP then return end
            local c = aliveChar(p); local part = c and partOf(c); if not part then return end
            local sp, on = Camera:WorldToViewportPoint(part.Position)
            if on and sp.Z > 0 then
                local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                if not bestD or d < bestD then bestD, best = d, p end
            end
        end
        local pool = activePool()
        if pool then for _, p in ipairs(pool) do tryP(p) end else for p in pairs(locked) do tryP(p) end end
        return best
    end
    FX.bestTargetPlayer = bestTargetPlayer

    -- one real shot fired: stamp time (for hit sound) + draw a tracer. direct=true
    -- for our own force/auto shots (so the ammo watcher won't double-draw).
    function FX.onShot(origin, hitPos, direct)
        _shotT = tick()
        if direct then _lastDirect = tick() end
        if S.btEnabled and origin and hitPos then spawnTracer(origin, hitPos) end
    end
    FX.lastDirect = function() return _lastDirect end
    FX.shotT = function() return _shotT end
    FX.FX_WINDOW = FX_WINDOW
end

-- ---- Force Hit: aim-target cache (nearest crosshair among the active set) ----
local aimCache = { part = nil, pos = nil }
track(RunService.RenderStepped:Connect(function()
    if not S.forceHit then aimCache.part, aimCache.pos = nil, nil; return end
    local mouse = UIS:GetMouseLocation()
    local bestPart, bestD
    local function tryP(p)
        if p == LP then return end
        local c = aliveChar(p); local part = c and partOf(c); if not part then return end
        local sp, on = Camera:WorldToViewportPoint(part.Position)
        if on and sp.Z > 0 then
            local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
            if not bestD or d < bestD then bestD, bestPart = d, part end
        end
    end
    local pool = activePool()
    if pool then for _, p in ipairs(pool) do tryP(p) end else for p in pairs(locked) do tryP(p) end end
    aimCache.part = bestPart
    aimCache.pos  = bestPart and bestPart.Position or nil
end))

-- Force Hit: replace GunHandler.Shoot so your manual shots (every pellet) land on the target
local okGH, GH = pcall(function() return require(RS.Modules.GunHandler) end)
if okGH and type(GH) == "table" and type(GH.Shoot) == "function" then
    local oldShoot = GH.Shoot
    GH.Shoot = function(params, ...)
        if S.forceHit and aimCache.part and aimCache.pos then
            local origin = (type(params) == "table" and params.ForcedOrigin) or aimCache.pos
            pcall(function() FX.onShot(FX.muzzlePos(), aimCache.pos, true) end)
            return aimCache.pos, aimCache.part, (origin - aimCache.pos).Unit   -- hitPos, hitPart, normal
        end
        return oldShoot(params, ...)
    end
else
    warn("[zee] Force Hit unavailable: couldn't hook GunHandler.Shoot")
end

-- ---- Auto shoot (+ auto reload) ----
local function fireAt(gun, part)
    local handle = gun:FindFirstChild("Handle"); if not handle then return end
    local origin = (handle.CFrame * CFrame.new(-1, 0.4, 0)).Position
    local hitPos = part.Position
    local normal = (origin - hitPos).Unit
    local range  = gun.Range.Value   -- ALWAYS the real range (server kicks for "range manipulation")
    local dmg    = gun:FindFirstChild("Damage") and gun.Damage.Value or 0
    if gun:FindFirstChild("GunClientShotgun") then
        -- shotgun: ONE ShootGun whose arg4 is a table of 5 pellets, all forced onto the target
        local pellets = {}
        for i = 1, 5 do
            pellets[i] = { Result1 = hitPos, Result2 = part, Result3 = normal, AimPosition = hitPos }
        end
        MainGameEvent:FireServer("ShootGun", handle, origin, pellets, nil, nil, nil, range, dmg)
    else
        MainGameEvent:FireServer("ShootGun", handle, origin, nil, hitPos, part, normal, range, dmg)
    end
end
local lastShot, lastReload = 0, 0
track(RunService.Heartbeat:Connect(function()
    local gun = equippedGun()
    if S.autoReload and gun and gun:FindFirstChild("Ammo") and gun.Ammo.Value < 1 and tick() - lastReload > 1.5 then
        lastReload = tick()
        pcall(function() MainGameEvent:FireServer("Reload", gun) end)
    end
    if not S.autoShoot or not gun then return end
    if S.fastFire and gun:FindFirstChild("ShootingCooldown") then pcall(function() gun.ShootingCooldown.Value = S.fastFireCD end) end
    local cd = (gun:FindFirstChild("ShootingCooldown") and gun.ShootingCooldown.Value) or 0.2
    if tick() - lastShot < cd then return end
    if gun:FindFirstChild("Ammo") and gun.Ammo.Value < 1 then return end
    local mc = myChar(); local myHRP = mc and mc:FindFirstChild("HumanoidRootPart"); if not myHRP then return end
    local muzzle = (gun.Handle.CFrame * CFrame.new(-1, 0.4, 0)).Position
    local function hittable(p)
        if p == LP then return end
        local c = aliveChar(p); if not c then return end
        if S.checkKnocked and isKnocked(p) then return end
        local part = partOf(c); if not part then return end
        local dist = (part.Position - myHRP.Position).Magnitude
        if S.checkRange and dist > gun.Range.Value then return end
        if S.checkVisible and not visibleTo(muzzle, part) then return end
        return part, dist
    end
    local bestPart, bestD
    local pool = activePool()
    if pool then for _, p in ipairs(pool) do local pt, d = hittable(p); if pt and (not bestD or d < bestD) then bestPart, bestD = pt, d end end
    else for p in pairs(locked) do local pt, d = hittable(p); if pt and (not bestD or d < bestD) then bestPart, bestD = pt, d end end end
    if bestPart then
        lastShot = tick(); fireAt(gun, bestPart)
        pcall(function() FX.onShot(FX.muzzlePos(), bestPart.Position, true) end)
    end
end))

-- ---- No Slowdown ----
--  The game slows you two ways, both feeding an EVENT-DRIVEN WalkSpeed recompute
--  (verified live: clearing the source restores speed INSTANTLY, no tween):
--    * shooting -> a `ReduceWalk` NumberValue parented into BodyEffects.Movement
--    * reloading -> BodyEffects.Reload set true
--  We must NEVER write Humanoid.WalkSpeed directly -- the game kicks for that
--  ("Humanoid tampering detected. Method 0x1"). So we only clear the BodyEffects
--  the game itself reads. A per-frame SWEEP (not a ChildAdded connection) is used so
--  it survives respawns and can't lose the re-add race during rapid fire -- which is
--  why the old connection-based version still slowed you while shooting.
do
    local function sweep()
        if not S.noSlowdown then return end
        local c = myChar(); local be = c and c:FindFirstChild("BodyEffects"); if not be then return end
        local mv = be:FindFirstChild("Movement")
        if mv then for _, ch in ipairs(mv:GetChildren()) do pcall(function() ch:Destroy() end) end end
        local rl = be:FindFirstChild("Reload")
        if rl and rl.Value == true then pcall(function() rl.Value = false end) end
    end
    track(RunService.Heartbeat:Connect(sweep))
    -- kept for the toggle callback's API; the Heartbeat sweep does the real work
    S._setupNS = function() pcall(sweep) end
    S._clearNS = function() end
end

-- ---- target visualizer (outline + tracer on locked players) ----
do
    local gui, vis = nil, {}
    local function ensureGui()
        if gui and gui.Parent then return end
        gui = Instance.new("ScreenGui"); gui.Name = "\0"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
        pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
        if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
    end
    local function clear(p)
        local v = vis[p]; if not v then return end
        if v.hl then pcall(function() v.hl:Destroy() end) end
        if v.line then pcall(function() v.line:Destroy() end) end
        vis[p] = nil
    end
    track(RunService.RenderStepped:Connect(function()
        for p in pairs(vis) do if not locked[p] or not aliveChar(p) then clear(p) end end
        if not (S.outline or S.tracer) then for p in pairs(vis) do clear(p) end; return end
        for p in pairs(locked) do
            local c = aliveChar(p); local part = c and partOf(c)
            if c and part then
                local v = vis[p] or {}; vis[p] = v
                if S.outline then
                    if not (v.hl and v.hl.Parent) then
                        ensureGui()
                        v.hl = Instance.new("Highlight"); v.hl.FillTransparency = 1
                        v.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; v.hl.Parent = gui
                    end
                    v.hl.Adornee = c; v.hl.OutlineColor = S.outlineColor
                elseif v.hl then pcall(function() v.hl:Destroy() end); v.hl = nil end
                if S.tracer then
                    ensureGui()
                    if not (v.line and v.line.Parent) then
                        v.line = Instance.new("Frame"); v.line.BorderSizePixel = 0
                        v.line.AnchorPoint = Vector2.new(0.5, 0.5); v.line.Parent = gui
                    end
                    local sp = Camera:WorldToViewportPoint(part.Position)
                    if sp.Z > 0 then
                        local vp = Camera.ViewportSize
                        local a
                        if S.tracerOrigin == "Top" then a = Vector2.new(vp.X / 2, 0)
                        elseif S.tracerOrigin == "Mouse" then a = UIS:GetMouseLocation()
                        else a = Vector2.new(vp.X / 2, vp.Y) end
                        local b = Vector2.new(sp.X, sp.Y)
                        local mid, d = (a + b) / 2, (b - a)
                        v.line.Size = UDim2.fromOffset(2, d.Magnitude)
                        v.line.Position = UDim2.fromOffset(mid.X, mid.Y)
                        v.line.Rotation = math.deg(math.atan2(d.Y, d.X)) - 90
                        v.line.BackgroundColor3 = S.tracerColor; v.line.Visible = true
                    elseif v.line then v.line.Visible = false end
                elseif v.line then pcall(function() v.line:Destroy() end); v.line = nil end
            end
        end
    end))
    S._clearVis = function() for p in pairs(vis) do clear(p) end; if gui then pcall(function() gui:Destroy() end); gui = nil end end
end

-- ---- FX drivers: ammo-drop -> manual tracer, target HP-drop -> hit sound, view target ----
do
    -- manual shots draw off the gun's Ammo dropping (our own force/auto shots draw
    -- directly and stamp _lastDirect so we don't double up here).
    local _wAmmo, _wAmmoConn, _wAmmoLast
    local function ensureAmmoWatch()
        local gun = equippedGun()
        local av = gun and gun:FindFirstChild("Ammo")
        if av == _wAmmo then return end
        if _wAmmoConn then pcall(function() _wAmmoConn:Disconnect() end); _wAmmoConn = nil end
        _wAmmo = av
        if not av then return end
        _wAmmoLast = av.Value
        _wAmmoConn = av:GetPropertyChangedSignal("Value"):Connect(function()
            local newV, old = av.Value, _wAmmoLast
            _wAmmoLast = newV
            -- a shot drops ammo by ONE. Ignore increases (pickup), the reload reset (e.g. 6->0),
            -- and any change while reloading -- those were drawing phantom tracers.
            if not old or (old - newV) ~= 1 then return end
            local be = myChar() and myChar():FindFirstChild("BodyEffects")
            if be and be:FindFirstChild("Reload") and be.Reload.Value == true then return end
            if tick() - FX.lastDirect() < 0.12 then return end         -- force/auto already drew
            local hitPos
            local p = FX.bestTargetPlayer()
            local c = p and aliveChar(p); local part = c and partOf(c)
            if part then hitPos = part.Position end
            if not hitPos then
                local m = UIS:GetMouseLocation()
                local ray = Camera:ViewportPointToRay(m.X, m.Y)
                local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { myChar() }
                local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
                hitPos = (res and res.Position) or (ray.Origin + ray.Direction * 300)
            end
            FX.onShot(FX.muzzlePos(), hitPos, false)
        end)
    end

    -- hit sound: the current target's Humanoid losing HP shortly after a shot
    local _wHum, _wHumConn, _wHumLast
    local function ensureHumWatch()
        local p = FX.bestTargetPlayer()
        local c = p and aliveChar(p)
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if hum == _wHum then return end
        if _wHumConn then pcall(function() _wHumConn:Disconnect() end); _wHumConn = nil end
        _wHum = hum
        if not hum then return end
        _wHumLast = hum.Health
        _wHumConn = hum.HealthChanged:Connect(function(newHP)
            local old = _wHumLast; _wHumLast = newHP
            if old and newHP < old - 0.01 and (tick() - FX.shotT() < FX.FX_WINDOW) then FX.playHitSound() end
        end)
    end

    -- view target: spectate the current target via Camera.CameraSubject; restore when none alive
    local function myHum() local c = myChar(); return c and c:FindFirstChildOfClass("Humanoid") end
    local _viewing = false
    local function restoreView()
        if not _viewing then return end
        _viewing = false
        local h = myHum(); if h then pcall(function() Camera.CameraSubject = h end) end
    end
    S._restoreView = restoreView

    track(RunService.Heartbeat:Connect(function()
        if S.btEnabled or S.hitSoundEnabled then ensureAmmoWatch() end
        if S.hitSoundEnabled then ensureHumWatch() end
        if S.viewTarget then
            local p = FX.bestTargetPlayer()
            local c = p and aliveChar(p)
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            if hum then
                _viewing = true
                if Camera.CameraSubject ~= hum then pcall(function() Camera.CameraSubject = hum end) end
            else
                restoreView()
            end
        else
            restoreView()
        end
    end))

    S._clearFX = function()
        if _wAmmoConn then pcall(function() _wAmmoConn:Disconnect() end) end
        if _wHumConn then pcall(function() _wHumConn:Disconnect() end) end
        restoreView()
        for _, o in ipairs(workspace:GetChildren()) do
            if o.Name == "\0_zt" then pcall(function() o:Destroy() end) end
        end
    end
end

-- ============================================================
--  UI  (Target subpage first)
-- ============================================================
do
    local TSub = MainPage:SubPage({ Name = "Target" })
    local TSec = TSub:Section({ Name = "Targeting", Side = 1 })
    TSec:Label({ Name = "Target player (nearest mouse)" }):Keybind({ Name = "Target", Flag = "ZeeTargetKey", Mode = "Hold", Default = Enum.KeyCode.E,
        Callback = function(state) if state then local p = nearestMousePlayer(); if p then locked[p] = true end end end })
    TSec:Label({ Name = "Untarget all" }):Keybind({ Name = "Untarget", Flag = "ZeeUntargetKey", Mode = "Hold", Default = Enum.KeyCode.T,
        Callback = function(state) if state then for p in pairs(locked) do locked[p] = nil end end end })
    TSec:Button({ Name = "Clear all targets", Callback = function() for p in pairs(locked) do locked[p] = nil end end })
    TSec:Toggle({ Name = "View target (spectate current)", Flag = "ZeeViewTarget", Default = false,
        Callback = function(v) S.viewTarget = v; if not v and S._restoreView then S._restoreView() end end })
    local lockLbl = TSec:Label({ Name = "Locked: 0" })
    track(RunService.Heartbeat:Connect(function()
        local n = 0; for _ in pairs(locked) do n = n + 1 end
        pcall(function() lockLbl:SetText("Locked: " .. n) end)
    end))

    local VSec = TSub:Section({ Name = "Visualizer", Side = 2 })
    VSec:Toggle({ Name = "Outline", Flag = "ZeeOutline", Default = true, Callback = function(v) S.outline = v end })
    VSec:Label({ Name = "Outline color" }):Colorpicker({ Flag = "ZeeOutlineColor", Default = S.outlineColor, Callback = function(c) S.outlineColor = c end })
    VSec:Toggle({ Name = "Tracer", Flag = "ZeeTracer", Default = false, Callback = function(v) S.tracer = v end })
    VSec:Dropdown({ Name = "Tracer origin", Flag = "ZeeTracerOrigin", Default = "Bottom", Multi = false, Items = { "Bottom", "Top", "Mouse" },
        Callback = function(v) S.tracerOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    VSec:Label({ Name = "Tracer color" }):Colorpicker({ Flag = "ZeeTracerColor", Default = S.tracerColor, Callback = function(c) S.tracerColor = c end })

    -- Bullet FX (fake tracers + hit sound)
    local XSub = MainPage:SubPage({ Name = "FX" })
    local BSec = XSub:Section({ Name = "Bullet Tracers", Side = 1 })
    BSec:Toggle({ Name = "Bullet tracers", Flag = "ZeeBT", Default = false, Callback = function(v) S.btEnabled = v end })
    BSec:Dropdown({ Name = "Style", Flag = "ZeeBTStyle", Default = "Standard", Multi = false, Items = { "Standard", "Laser", "Thin" },
        Callback = function(v) S.btStyle = (type(v) == "table" and v[1]) or v or "Standard" end })
    BSec:Label({ Name = "Tracer color" }):Colorpicker({ Flag = "ZeeBTColor", Default = S.btColor, Callback = function(c) S.btColor = c end })
    BSec:Toggle({ Name = "Through walls", Flag = "ZeeBTWalls", Default = true, Callback = function(v) S.btThroughWalls = v end })
    BSec:Slider({ Name = "Size", Flag = "ZeeBTSize", Min = 0.005, Max = 1, Default = 0.12, Decimals = 3, Callback = function(v) S.btThickness = v end })
    BSec:Slider({ Name = "Lifetime", Flag = "ZeeBTLife", Min = 0.1, Max = 3, Default = 0.2, Decimals = 2, Suffix = "s", Callback = function(v) S.btLifetime = v end })

    local HSec = XSub:Section({ Name = "Hit Sound", Side = 2 })
    HSec:Toggle({ Name = "Hit sound", Flag = "ZeeHitSnd", Default = false, Callback = function(v) S.hitSoundEnabled = v end })
    HSec:Slider({ Name = "Volume", Flag = "ZeeHitVol", Min = 0, Max = 500, Default = 100, Decimals = 0, Suffix = "%",
        Callback = function(v) S.hitSoundVolume = v / 100 end })

    -- Force Hit
    local FSub = MainPage:SubPage({ Name = "Force Hit" })
    local FSec = FSub:Section({ Name = "Force Hit", Side = 1 })
    local fhToggle = FSec:Toggle({ Name = "Force Hit", Flag = "ZeeForceHit", Default = false, Callback = function(v) S.forceHit = v end })
    FSec:Label({ Name = "Force Hit key" }):Keybind({ Name = "Force Hit", Flag = "ZeeForceHitKey", Mode = "Toggle",
        Callback = function(state) fhToggle:Set(state and true or false) end })
    local asToggle = FSec:Toggle({ Name = "Auto shoot", Flag = "ZeeAuto", Default = false, Callback = function(v) S.autoShoot = v end })
    FSec:Label({ Name = "Auto shoot key" }):Keybind({ Name = "Auto shoot", Flag = "ZeeAutoKey", Mode = "Toggle",
        Callback = function(state) asToggle:Set(state and true or false) end })
    FSec:Toggle({ Name = "Aura (any player, not just locked)", Flag = "ZeeAura", Default = false, Callback = function(v) S.aura = v end })
    FSec:Dropdown({ Name = "Hit part", Flag = "ZeeHitPart", Default = "Head", Multi = false, Items = { "Head", "Torso", "HumanoidRootPart" },
        Callback = function(v) S.hitPart = (type(v) == "table" and v[1]) or v or "Head" end })
    FSec:Toggle({ Name = "Fast fire (override cooldown)", Flag = "ZeeFast", Default = false, Callback = function(v) S.fastFire = v end })
    FSec:Slider({ Name = "Fast fire cooldown", Flag = "ZeeFastCD", Min = 0.02, Max = 0.5, Default = 0.06, Decimals = 2, Suffix = "s",
        Callback = function(v) S.fastFireCD = v end })

    local CSec = FSub:Section({ Name = "Auto shoot checks", Side = 2 })
    CSec:Toggle({ Name = "Knocked check", Flag = "ZeeChkKnock", Default = true, Callback = function(v) S.checkKnocked = v end })
    CSec:Toggle({ Name = "Range check", Flag = "ZeeChkRange", Default = true, Callback = function(v) S.checkRange = v end })
    CSec:Toggle({ Name = "Visible check", Flag = "ZeeChkVis", Default = true, Callback = function(v) S.checkVisible = v end })

    -- Misc
    local MSub = MainPage:SubPage({ Name = "Misc" })
    local MSec = MSub:Section({ Name = "Utility", Side = 1 })
    MSec:Toggle({ Name = "No Slowdown", Flag = "ZeeNoSlow", Default = false,
        Callback = function(v) S.noSlowdown = v; if v then S._setupNS() else S._clearNS() end end })
    MSec:Toggle({ Name = "Auto reload", Flag = "ZeeAutoReload", Default = true, Callback = function(v) S.autoReload = v end })
end

-- universal pages after Main
pcall(function() ctx.load("games/combat.lua")(ctx) end)
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- teardown
local function cleanup()
    S.forceHit, S.autoShoot, S.noSlowdown = false, false, false
    S.btEnabled, S.hitSoundEnabled, S.viewTarget = false, false, false
    if S._clearVis then pcall(S._clearVis) end
    if S._clearNS then pcall(S._clearNS) end
    if S._clearFX then pcall(S._clearFX) end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
end
do
    local g = (getgenv and getgenv()) or nil
    if g and g.WH then
        local prev = g.WH.disableAll
        g.WH.disableAll = function() pcall(cleanup); if prev then pcall(prev) end end
        Library.OnExit = g.WH.disableAll
    end
end
