-- ============================================================
--  games/93978595733734.lua  --  [CURE] Violence District
--
--  Dead-by-Daylight-style asym horror: Survivors repair 7 generators while a
--  Killer (Cure/Veil/Stalker/Jason/...) hunts, hooks, and breaks things.
--
--  Decoded live 2026-07-03:
--    * Teams: "Survivors" / "Killer" / "Spectator" -- role = player.Team.Name.
--    * Generators: models under a "Generators" folder in workspace.Map with
--      attributes RepairProgress (0-100), Completed, Regressing, ProgressPaused,
--      PlayersRepairingCount. Map layout varies per map -> folders are found by
--      NAME anywhere under workspace.Map (Pallets/Vaults/Hooks may be absent).
--    * Killer character carries live attrs: Speed, IsChasing, ChaseTargetUserId,
--      TerrorRadius, SuspenseRadius, BloodLust, HookCount, breakspeed -- free
--      intel for the survivor side.
--    * Skill checks are CLIENT-decided: on fail the client itself fires
--      RepairEvent:FireServer(gen, false, 1.5) (SurvivorAnimationsController
--      _onSkillCheckFail). The minigame UI is PlayerGui.SkillCheckPromptGui
--      (and -con for console): Frame "Check" > rotating "Line", success zone
--      "Goal", "Space" prompt. Auto skill check watches Line's angular velocity
--      and presses Space exactly when it reaches the Goal zone -- no remote
--      spoofing at all, so there is nothing for the server to validate against.
--
--  Re-verified 2026-08-01 against place version 10329, both roles in one round:
--    * Everything above still holds. New gen attrs since July: kickcount,
--      KingsScourgeTriggered, Abyss50Triggered.
--    * Killer perks are child scripts of the killer character named
--      "<Perk> <tier>" ("King's Scourge 3"); nothing else there ends in a digit.
--    * Basic attack is a Legacy (server) Script at
--      Character.Weapon["Right Arm"].Weapon.Main.BasicAttack -- hit detection is
--      server side, so reach cannot be read and cannot be widened from here.
--      The rings below are measured from hits that actually land.
--    * Veil's two throws: spearmode says a throw is being AIMED, not which kind.
--      The charged (wall-piercing) one wears an "Aura att" attachment with live
--      ParticleEmitters while held -- the same particles ProjectileHandler
--      switches on for speed > 150 -- so the mode is readable before release.
--      Veil's perks are Piercing Reverie / Blood Between Worlds / Echo Of The
--      Void, and Remotes.Killers.Veil carries Spearthrow, vfx, updatewep and a
--      PiercingReverie folder.
--    * Only the KILLER uploads aim, via Remotes.getlookvector, and it is never
--      mirrored back to survivors -- a pre-throw spear line has to use the
--      killer's replicated HRP facing and only becomes exact once the throw
--      goes out over Remotes.Mechanics.visualize.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end
local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
--  ROLES / MAP LOOKUP
-- ============================================================
local function teamName(p) return (p.Team and p.Team.Name) or "" end
local function isKiller(p) return teamName(p) == "Killer" end
local function isSurvivor(p) return teamName(p) == "Survivors" end

local function getKillerPlayer()
    for _, p in ipairs(Players:GetPlayers()) do
        if isKiller(p) then return p end
    end
    return nil
end

-- Map folders (Generators/Pallets/Vaults/Hooks) move around per map; rescan
-- lazily instead of caching paths.
local mapFolders, lastScan = {}, 0
local function getMapFolder(name)
    local now = os.clock()
    if now - lastScan > 3 then
        lastScan = now
        mapFolders = {}
        local map = workspace:FindFirstChild("Map")
        if map then
            for _, d in ipairs(map:GetDescendants()) do
                if d:IsA("Folder") and not mapFolders[d.Name] then
                    mapFolders[d.Name] = d
                end
            end
        end
    end
    local f = mapFolders[name]
    return (f and f.Parent) and f or nil
end

local function genProgress(gen)
    return gen:GetAttribute("RepairProgress") or 0,
        gen:GetAttribute("Completed") == true,
        gen:GetAttribute("Regressing") == true
end

-- ============================================================
--  THEME
-- ============================================================
-- ---------- GUI-matched theme ----------
-- Colors + font come straight from the menu library so the ESP reads as part
-- of the same UI: lavender accent, muted purple, "Risky" red, mono Code font.
local T = (Library and Library.Theme) or {}
local PAL = {
    killer  = T["Risky"] or Color3.fromRGB(255, 70, 80),
    accent  = T["Accent"] or Color3.fromRGB(248, 212, 255),
    muted   = T["Inactive Text"] or Color3.fromRGB(131, 120, 162),
    text    = T["Text"] or Color3.fromRGB(240, 240, 242),
    bg      = T["Background"] or Color3.fromRGB(22, 22, 25),
    outline = T["Outline"] or Color3.fromRGB(62, 57, 77),
    border  = T["Border"] or Color3.fromRGB(10, 10, 12),
}

local S = {
    killerEsp     = false,
    survEsp       = false,
    genEsp        = false,
    genHideDone   = true,
    hookEsp       = false,
    palletEsp     = false,
    vaultEsp      = false,   -- windows
    autoSkill     = false,
    skillMode     = "Legit", -- "Legit" rides the needle, "Instant" snaps it
    humanizeMin   = 10,      -- Legit: random extra reaction delay range (ms)
    humanizeMax   = 40,
    missChance    = 5,       -- Legit: % of checks pressed JUST before the zone (fail)
    reactMs       = 150,     -- Legit: never press within this long of a check appearing
    chaseWarn     = false,
    antiChase     = false,   -- while chased: keep resetting the killer's BloodLust
    autoUnhook    = false,   -- hooked: rescue-spoof our own hook + self-unhook rolls
    repairAlert   = false,   -- killer side: notify when a gen starts being repaired
    fastVault     = false,   -- every vault counts as a running (fast) vault
    hitRing       = false,   -- ground ring at the measured basic-attack reach
    lungeRing     = false,   -- ground ring at the measured lunge reach
    ringScale     = 100,     -- % applied to both rings, for a safety margin
    ringOnSelf    = false,   -- draw the rings around us instead of the killer
    spearLine     = false,   -- Veil: predicted arc while spearmode is on
    spearLive     = false,   -- Veil: exact arc of a spear already in flight
    spearAlways   = false,   -- draw the predicted arc even outside spearmode
    blindMeter    = false,   -- flashlight blind progress + fuel
    powerHud      = false,   -- live power attrs + recent power remotes for ANY killer
    aimMarker     = false,   -- draw the intercept + where the crosshair must go
    aimLock       = false,   -- steer the camera onto the solution while held
    aimLead       = true,    -- lead a moving target
    aimFov        = 400,     -- target search radius around the crosshair, px
    lockSmooth    = 0.30,    -- per-1/60s retention; lower = snappier
    lockSnap      = 1.2,     -- inside this angle, apply the full correction
    blindCone     = 20,      -- half-angle (deg) the beam counts as "on target"
    blindRange    = 60,      -- studs
    espBox        = true,    -- draw the 2D bounding box
    espName       = true,
    espDist       = true,    -- distance line under every tracked thing
    espHealth     = true,    -- health bar on the left edge of the box
    espState      = true,    -- KNOCKED / HOOKED / REPAIRING / ...
    espTracer     = false,   -- line from the bottom of the screen
}

-- ============================================================
--  MOUSE POLICY
--
--  The menu can be opened in the lobby and closed mid-round, which makes the
--  mouse state the library captured at open-time stale. This game locks the
--  cursor once on spawn and never rewrites MouseBehavior, so it cannot repair a
--  wrong restore by itself -- tell the library what it should be right now.
-- ============================================================
pcall(function()
    Library.MouseRestoreHook = function()
        local t = teamName(LocalPlayer)
        if LocalPlayer.Character and (t == "Killer" or t == "Survivors") then
            return Enum.MouseBehavior.LockCenter
        end
        return Enum.MouseBehavior.Default
    end
    -- Reinjecting mid-round should also REPAIR a cursor an earlier instance
    -- left loose, not merely avoid making it worse.
    task.defer(function()
        local UIS_ = game:GetService("UserInputService")
        local want = Library.MouseRestoreHook and Library.MouseRestoreHook()
        if want == Enum.MouseBehavior.LockCenter and UIS_.MouseBehavior ~= want then
            UIS_.MouseBehavior = want
            UIS_.MouseIconEnabled = false
        end
    end)
end)

local frameId = 0   -- bumped each frame; used to memoise per-frame work

-- ============================================================
--  DRAW LAYER
--
--  Every visual in this module is a Drawing object -- no Highlight, no
--  BillboardGui. Drawings are 2D screen overlays, so they are always visible
--  through geometry, which is what ESP wants anyway.
--
--  One pool per Drawing class, handed out in frame order: frameBegin() resets
--  the cursors, each helper takes the next free object, frameEnd() hides
--  whatever this frame did not claim. Nothing is per-instance, so objects that
--  vanish mid-round (a broken pallet) need no bookkeeping.
-- ============================================================
local hasDrawing = (Drawing ~= nil and Drawing.new ~= nil)
local DPOOL = { Line = {}, Text = {}, Square = {} }
local DUSED = { Line = 0, Text = 0, Square = 0 }

local function grab(class)
    if not hasDrawing then return nil end
    local n = DUSED[class] + 1
    local o = DPOOL[class][n]
    if not o then
        local ok, made = pcall(Drawing.new, class)
        if not ok then return nil end
        if class == "Text" then
            made.Font, made.Outline = 2, true
        end
        DPOOL[class][n] = made
        o = made
    end
    DUSED[class] = n
    return o
end
local function frameBegin()
    frameId = frameId + 1
    DUSED.Line, DUSED.Text, DUSED.Square = 0, 0, 0
end
local function frameEnd()
    for class, list in pairs(DPOOL) do
        for i = DUSED[class] + 1, #list do list[i].Visible = false end
    end
end

local cam = workspace.CurrentCamera
track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    cam = workspace.CurrentCamera
end))

local function toScreen(v3)
    if not cam then return nil end
    local sp, on = cam:WorldToViewportPoint(v3)
    if not on then return nil end
    return Vector2.new(sp.X, sp.Y), sp.Z
end

local function dLine(a, b, col, alpha, thick)
    local l = grab("Line")
    if not l then return end
    l.From, l.To, l.Color = a, b, col
    l.Transparency, l.Thickness, l.Visible = alpha or 1, thick or 1, true
end

local function dText(pos, str, col, size, centered)
    local t = grab("Text")
    if not t then return end
    t.Position, t.Text, t.Color = pos, str, col
    t.Size, t.Center = size or 13, centered ~= false
    t.Transparency, t.Visible = 1, true
end

local function dBox(x, y, w, h, col, alpha, thick)
    local q = grab("Square")
    if not q then return end
    q.Position, q.Size, q.Color = Vector2.new(x, y), Vector2.new(w, h), col
    q.Thickness, q.Transparency = thick or 1, alpha or 1
    q.Filled, q.Visible = false, true
end

local function dFill(x, y, w, h, col, alpha)
    local q = grab("Square")
    if not q then return end
    q.Position, q.Size, q.Color = Vector2.new(x, y), Vector2.new(w, h), col
    q.Transparency, q.Filled, q.Visible = alpha or 1, true, true
end

-- Flat ring on the ground, emitted as a line loop.
local RING_SEGS = 48
local function dRing(center, radius, col, alpha)
    if radius <= 0 then return end
    local prev, first
    for i = 0, RING_SEGS do
        local a = (i / RING_SEGS) * math.pi * 2
        local pt = toScreen(center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
        if i == 0 then first = pt end
        if prev and pt then dLine(prev, pt, col, alpha, 2) end
        prev = pt
    end
    if prev and first and prev ~= first then dLine(prev, first, col, alpha, 2) end
end

-- Polyline through world points. split = first index drawn in the secondary
-- style; used by the spear arc to show the through-wall leg differently.
local function dPath(pts, split, colA, aA, colB, aB)
    local prev
    for i = 1, #pts do
        local pt = toScreen(pts[i])
        if prev and pt then
            local past = split and (i - 1) >= split
            dLine(prev, pt, past and colB or colA, past and aB or aA, past and 1 or 2)
        end
        prev = pt
    end
end

-- Screen-space box around a character, from its bounding box corners so the
-- rectangle stays tight when the model is rotated or partly off-axis.
local function charBox(model)
    local ok, cf, size = pcall(function()
        local a, b = model:GetBoundingBox()
        return a, b
    end)
    if not ok or not cf then return nil end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local any = false
    for _, c in ipairs({
        Vector3.new( 1,  1,  1), Vector3.new( 1,  1, -1),
        Vector3.new( 1, -1,  1), Vector3.new( 1, -1, -1),
        Vector3.new(-1,  1,  1), Vector3.new(-1,  1, -1),
        Vector3.new(-1, -1,  1), Vector3.new(-1, -1, -1),
    }) do
        local pt = toScreen((cf * CFrame.new(size * c * 0.5)).Position)
        if pt then
            any = true
            minX, minY = math.min(minX, pt.X), math.min(minY, pt.Y)
            maxX, maxY = math.max(maxX, pt.X), math.max(maxY, pt.Y)
        end
    end
    if not any then return nil end
    return minX, minY, maxX - minX, maxY - minY
end

-- ============================================================
--  ESP RENDERERS
-- ============================================================
-- Text stacked under a box, one line per call, so callers do not track offsets.
local function textStack(cx, yTop, lines)
    local y = yTop
    for _, ln in ipairs(lines) do
        if ln[1] ~= "" then
            dText(Vector2.new(cx, y), ln[1], ln[2], 13, true)
            y = y + 14
        end
    end
end

local function stepPlayerEsp(hrp)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local killer = isKiller(p)
            if (killer and S.killerEsp) or (isSurvivor(p) and S.survEsp) then
                local c = p.Character
                local root = c and c:FindFirstChild("HumanoidRootPart")
                local x, y, w, h = nil, nil, nil, nil
                if root then x, y, w, h = charBox(c) end
                if x then
                    local col = killer and PAL.killer or PAL.accent
                    local dist = hrp and math.floor((root.Position - hrp.Position).Magnitude + 0.5) or 0

                    if S.espBox then dBox(x, y, w, h, col, 1, 1) end

                    if S.espHealth then
                        local hum = c:FindFirstChildOfClass("Humanoid")
                        if hum and hum.MaxHealth > 0 then
                            local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                            dFill(x - 5, y, 2, h, PAL.border, 0.7)
                            dFill(x - 5, y + h * (1 - frac), 2, h * frac,
                                frac > 0.5 and PAL.accent or PAL.killer, 1)
                        end
                    end

                    if S.espTracer then
                        local vp = cam and cam.ViewportSize
                        if vp then
                            dLine(Vector2.new(vp.X / 2, vp.Y), Vector2.new(x + w / 2, y + h), col, 0.6, 1)
                        end
                    end

                    local cx = x + w / 2
                    if S.espName then
                        local top = killer
                            and ("%s  %s"):format(tostring(p:GetAttribute("SelectedKiller") or "KILLER"):upper(), p.Name)
                            or p.Name
                        dText(Vector2.new(cx, y - 15), top, col, 13, true)
                    end

                    local lines = {}
                    if S.espState and not killer then
                        local hookProg = c:GetAttribute("HookedProgress")
                        if c:GetAttribute("Knocked") then
                            lines[#lines + 1] = { "KNOCKED", PAL.killer }
                        elseif hookProg and hookProg < 100 then
                            lines[#lines + 1] = { ("HOOKED %d%%"):format(hookProg), PAL.killer }
                        elseif (c:GetAttribute("repairing") or 0) > 0 then
                            lines[#lines + 1] = { "REPAIRING", PAL.accent }
                        elseif (c:GetAttribute("healing") or 0) > 0 then
                            lines[#lines + 1] = { "HEALING", PAL.accent }
                        elseif c:GetAttribute("IsRunning") then
                            lines[#lines + 1] = { "RUNNING", PAL.muted }
                        end
                        local hooks = c:GetAttribute("HookCount") or 0
                        if hooks > 0 then lines[#lines + 1] = { ("%dx hooked"):format(hooks), PAL.muted } end
                    end
                    if S.espDist then lines[#lines + 1] = { ("%dm"):format(dist), PAL.muted } end
                    textStack(cx, y + h + 3, lines)
                end
            end
        end
    end
end

local function stepGenEsp(hrp)
    if not S.genEsp then return end
    local gens = getMapFolder("Generators") or getMapFolder("Gens")
    if not gens then return end
    for _, gen in ipairs(gens:GetChildren()) do
        local root = gen:FindFirstChild("RootPart") or gen:FindFirstChildWhichIsA("BasePart")
        if root then
            local prog, done, regress = genProgress(gen)
            if not (done and S.genHideDone) then
                local pt = toScreen(root.Position)
                if pt then
                    local col = done and PAL.muted or (regress and PAL.killer or PAL.accent)
                    local lines = {}
                    if done then
                        lines[#lines + 1] = { "GEN DONE", PAL.muted }
                    else
                        lines[#lines + 1] = { ("GEN %d%%"):format(math.floor(prog + 0.5)), col }
                        if regress then lines[#lines + 1] = { "REGRESSING", PAL.killer } end
                        local nrep = gen:GetAttribute("PlayersRepairingCount") or 0
                        if nrep > 0 then lines[#lines + 1] = { ("%d repairing"):format(nrep), PAL.killer } end
                    end
                    if S.espDist and hrp then
                        lines[#lines + 1] =
                            { ("%dm"):format(math.floor((root.Position - hrp.Position).Magnitude + 0.5)), PAL.muted }
                    end
                    textStack(pt.X, pt.Y, lines)
                end
            end
        end
    end
end

-- ---------- hooks / pallets / vaults ----------
-- Map layouts differ per map: some group objects in folders (Pallets/Vaults/
-- Hooks), others scatter named models around the map (Palletwrong +
-- PrimaryPartPallet, Window + VaultTrigger, Hook + HookPoint). Scan for BOTH,
-- cached and rescanned every 3s so a map change re-detects everything.
local OBJ_COL = { HOOK = "killer", PALLET = "accent", VAULT = "muted" }
local FOLDER_KIND = { Hooks = "HOOK", Pallets = "PALLET", Vaults = "VAULT", Windows = "VAULT" }
local function classify(name)
    local n = name:lower()
    if n:find("pallet") then return "PALLET" end
    if n:find("window") or n:find("vault") then return "VAULT" end
    if n:find("hook") then return "HOOK" end
    return nil
end
local objCache, lastObjScan = {}, -10
local function getObjects()
    local now = os.clock()
    if now - lastObjScan < 3 then return objCache end
    lastObjScan = now
    objCache = {}
    local seen = {}
    local function add(kind, obj)
        if seen[obj] then return end
        seen[obj] = true
        local root = obj:IsA("BasePart") and obj
            or obj:FindFirstChild("HookPoint")
            or obj:FindFirstChild("PrimaryPartPallet")
            or obj:FindFirstChild("VaultTrigger", true)
            or obj:FindFirstChild("RootPart")
            or obj:FindFirstChildWhichIsA("BasePart", true)
        if root then objCache[#objCache + 1] = { kind = kind, obj = obj, root = root } end
    end
    local map = workspace:FindFirstChild("Map")
    if not map then return objCache end
    for _, d in ipairs(map:GetDescendants()) do
        if d:IsA("Folder") and FOLDER_KIND[d.Name] then
            for _, obj in ipairs(d:GetChildren()) do add(FOLDER_KIND[d.Name], obj) end
        elseif d:IsA("Model") then
            local kind = classify(d.Name)
            if kind then add(kind, d) end
        end
    end
    return objCache
end

local function stepObjEsp(hrp)
    if not (S.hookEsp or S.palletEsp or S.vaultEsp) then return end
    local on = { HOOK = S.hookEsp, PALLET = S.palletEsp, VAULT = S.vaultEsp }
    for _, it in ipairs(getObjects()) do
        if on[it.kind] and it.obj.Parent and it.root.Parent then   -- broken pallets vanish mid-cache
            local pt = toScreen(it.root.Position)
            if pt then
                local col = PAL[OBJ_COL[it.kind]]
                local lines = { { it.kind, col } }
                if S.espDist and hrp then
                    lines[#lines + 1] =
                        { ("%dm"):format(math.floor((it.root.Position - hrp.Position).Magnitude + 0.5)), PAL.muted }
                end
                textStack(pt.X, pt.Y, lines)
            end
        end
    end
end

-- ============================================================
--  AUTO SKILL CHECK
--  The minigame is pure client UI: "Line" sweeps around the circle, "Goal"
--  marks the success zone. We measure Line's angular velocity each frame and
--  press Space when the time-to-goal drops under the lead time. One press per
--  check; re-arms when the check hides or the goal jumps to a new angle.
-- ============================================================
local VIM = game:GetService("VirtualInputManager")
local function pressSpace()
    local ok = pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.02)
        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    if not ok and keypress then
        pcall(function() keypress(0x20); task.wait(0.02); keyrelease(0x20) end)
    end
end

local function findCheck()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, name in ipairs({ "SkillCheckPromptGui", "SkillCheckPromptGui-con" }) do
        local g = pg:FindFirstChild(name)
        if g and g.Enabled then
            local c = g:FindFirstChild("Check", true)
            if c and c.Visible then
                local line, goal = c:FindFirstChild("Line"), c:FindFirstChild("Goal")
                if line and goal then return c, line, goal end
            end
        end
    end
    return nil
end

do
    -- deactivate any lingering standalone vd-autoskill.lua instance (it snaps
    -- the needle and finishes every check instantly) -- this page owns it now
    if getgenv then getgenv().__VD_AUTOSKILL = (getgenv().__VD_AUTOSKILL or 0) + 1 end

    -- success zone (decoded from the game's Skillcheck script): a press lands
    -- when (Line.Rotation - Goal.Rotation) % 360 is inside [102, 116]
    local ZONE_LO, ZONE_HI = 102, 116

    local lastRot, lastT, vel = nil, nil, 0
    local armed, armedGoal, targetRel = true, nil, nil
    local checkSeenAt, willMiss, lastWasMiss = nil, false, false
    local lastInstant = 0

    track(RunService.RenderStepped:Connect(function()
        if not S.autoSkill then return end
        local check, line, goal = findCheck()
        if not check then
            lastRot, lastT, vel, armed, armedGoal, targetRel = nil, nil, 0, true, nil, nil
            checkSeenAt, willMiss = nil, false
            return
        end
        local now = os.clock()
        checkSeenAt = checkSeenAt or now
        -- goal jumped -> a fresh check inside the same visible session
        if armedGoal ~= nil and math.abs(goal.Rotation - armedGoal) > 5 then
            armed, targetRel, willMiss, checkSeenAt = true, nil, false, now
        end
        armedGoal = goal.Rotation

        if S.skillMode == "Instant" then
            if now - lastInstant < 0.1 then return end
            lastInstant = now
            pcall(function() line.Rotation = goal.Rotation + 109 end)   -- mid-zone
            pressSpace()
            return
        end

        -- ---- Legit: ride the game's own needle, press inside the zone ----
        if lastRot ~= nil and lastT ~= nil and now > lastT then
            local d = (line.Rotation - lastRot + 540) % 360 - 180   -- signed shortest delta
            local v = d / (now - lastT)
            vel = vel == 0 and v or (vel * 0.7 + v * 0.3)
        end
        lastRot, lastT = line.Rotation, now

        if not armed or math.abs(vel) < 20 then return end
        local dir = vel >= 0 and 1 or -1

        -- per-check roll: miss this one? (never twice in a row unless 100%)
        -- a miss = press a few degrees BEFORE the zone, like a rushed human
        if not targetRel then
            willMiss = (S.missChance >= 100 or not lastWasMiss)
                and math.random(100) <= S.missChance
            if willMiss then
                targetRel = dir == 1 and (ZONE_LO - math.random(2, 7))
                    or (ZONE_HI + math.random(2, 7))
            else
                -- random spot in the early half of the zone (travel direction),
                -- re-rolled per check so timing never looks scripted
                targetRel = dir == 1 and math.random(ZONE_LO + 2, ZONE_LO + 8)
                    or math.random(ZONE_HI - 8, ZONE_HI - 2)
            end
        end

        -- human reaction gate: never press within reactMs of the check appearing
        if (now - checkSeenAt) < (S.reactMs / 1000) then return end

        local rel = (line.Rotation - goal.Rotation) % 360
        local inZone = rel >= ZONE_LO and rel <= ZONE_HI

        if willMiss then
            -- press in the [target, zone edge) window just before the zone;
            -- no humanize delay here or the press could slip INTO the zone
            local preZone = dir == 1 and (rel >= targetRel and rel < ZONE_LO)
                or (rel <= targetRel and rel > ZONE_HI)
            if preZone or inZone then   -- inZone = frame skipped past the window; press anyway (turns into a hit)
                armed, lastWasMiss = false, not inZone
                pressSpace()
            end
            return
        end

        if not inZone then return end
        local passed = (dir == 1 and rel >= targetRel) or (dir == -1 and rel <= targetRel)
        if not passed then return end
        armed, lastWasMiss = false, false

        -- humanized reaction: random extra delay in [min, max], capped so the
        -- needle can't leave the zone before the press lands
        local hMin = math.max(math.min(S.humanizeMin, S.humanizeMax), 0)
        local hMax = math.max(S.humanizeMin, S.humanizeMax, 0)
        local remain = (dir == 1 and (ZONE_HI - rel) or (rel - ZONE_LO)) / math.abs(vel)
        local delay = math.min(math.random(hMin, hMax) / 1000, math.max(remain - 0.03, 0))
        if delay > 0.001 then
            task.delay(delay, function()
                if S.autoSkill then pressSpace() end
            end)
        else
            pressSpace()
        end
    end))
end

-- ============================================================
--  ALWAYS FAST VAULT
--  A fast vault normally needs, at the moment of the vault: the sprint flag
--  (SurvivorActions.startVault reads getSprintFlag/"Sprinting"), facing the
--  window within 40 deg, and velocity > 15.25 (both checked in
--  SurvivorAnimationsController._onVaultAnimation). All three are CLIENT
--  decided -- the client then just informs the server via
--  fastvault:FireServer. So hook the two survivor modules:
--   - startVault: shadow getSprintFlag with `true` for the duration of the call
--   - _isFacingStraightEnough: return true + backdate characterspeed
--  Hook originals are kept in getgenv so re-executing never stacks wrappers.
-- ============================================================
pcall(function()
    local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules", 5)
    local SA = require(Modules.Survivors.SurvivorActions)
    local AC = require(Modules.Survivors.SurvivorAnimationsController)

    local g = (getgenv and getgenv()) or {}
    g.__VD_VAULT_ORIG = g.__VD_VAULT_ORIG or {}
    local H = g.__VD_VAULT_ORIG
    H.startVault = H.startVault or SA.startVault
    H.facing = H.facing or AC._isFacingStraightEnough

    SA.startVault = function(p1, p2)
        if not S.fastVault then return H.startVault(p1, p2) end
        local prev = rawget(p1, "getSprintFlag")
        p1.getSprintFlag = function() return true end
        local ok, err = pcall(H.startVault, p1, p2)
        p1.getSprintFlag = prev   -- nil removes the shadow again
        if not ok then error(err, 0) end
    end

    AC._isFacingStraightEnough = function(self, ...)
        if S.fastVault then
            self.characterspeed = 100   -- pass the > 15.25 speed gate
            return true                 -- pass the 40-degree facing gate
        end
        return H.facing(self, ...)
    end
end)

-- ============================================================
--  KILLER INTEL  -- live readout of the killer's attributes + chase warning
-- ============================================================

-- ---------- mouse-lock handoff ----------
-- This game's look scripts lock the mouse and do NOT re-assert the lock after
-- the menu frees the cursor, so closing the menu left the camera dead. Sample
-- whatever MouseBehavior the game runs while the menu is CLOSED, and hand that
-- exact mode back the moment it closes again (self-calibrating: lobby/spectate
-- naturally record Default and get Default back).
do
    local UIS = game:GetService("UserInputService")
    local lastGameMouseMode = UIS.MouseBehavior
    track(RunService.Heartbeat:Connect(function()
        if not Library.WindowOpenState then
            lastGameMouseMode = UIS.MouseBehavior
        end
    end))
    pcall(function()
        Library:BindToWindowVisibility(function(open)
            if open then return end
            local restore = lastGameMouseMode
            task.defer(function()
                pcall(function() UIS.MouseBehavior = restore end)
            end)
        end)
    end)
end

-- ---------- killer side: gen repair alerts ----------
-- Notify the moment a gen's PlayersRepairingCount goes 0 -> N, with distance,
-- so a killer knows exactly which gen to pressure. Polled on the intel tick.
local repairCounts = {}   -- [gen] = last seen count
local function stepRepairAlert()
    if not S.repairAlert then return end
    local gens = getMapFolder("Generators") or getMapFolder("Gens")
    if not gens then return end
    local hrp = myHRP()
    for _, gen in ipairs(gens:GetChildren()) do
        local n = gen:GetAttribute("PlayersRepairingCount") or 0
        if n > 0 and (repairCounts[gen] or 0) == 0 and not gen:GetAttribute("Completed") then
            local root = gen:FindFirstChild("RootPart") or gen:FindFirstChildWhichIsA("BasePart")
            local dist = (hrp and root) and (math.floor((root.Position - hrp.Position).Magnitude + 0.5) .. "m") or "?"
            pcall(function()
                Library:Notification(("Gen being repaired -- %s away (%d on it)"):format(dist, n), 4, PAL.accent)
            end)
        end
        repairCounts[gen] = n
    end
end

-- anti-chase: BloodLust makes the killer faster the longer a chase lasts; the
-- game ships a resetbloodlustremote -- keep firing it while WE are the chase
-- target so the stacks never build
local lastBlReset = 0
local function stepAntiChase(kc)
    if not S.antiChase then return end
    if os.clock() - lastBlReset < 0.5 then return end
    lastBlReset = os.clock()
    if (kc:GetAttribute("BloodLust") or 0) > 0 then
        pcall(function()
            game:GetService("ReplicatedStorage").Remotes.Mechanics.resetbloodlustremote:FireServer()
        end)
    end
end

-- auto free from hook: the rescue path (UnHookEvent fired at a hook's tagged
-- "UnhookPoint") is what teammates use and has no chance roll -- fire it at
-- OUR OWN hook the moment we're hooked. If the server rejects self-rescue,
-- fall back to SelfUnHookEvent attempts (the "free yourself" roll) as well.
local lastHookTry, hookTries = 0, 0
local function stepAutoUnhook()
    local c = LocalPlayer.Character
    if not (S.autoUnhook and c and c:GetAttribute("IsHooked")) then
        hookTries = 0
        return
    end
    if os.clock() - lastHookTry < 0.35 then return end
    lastHookTry = os.clock()
    hookTries = hookTries + 1
    local Carry = game:GetService("ReplicatedStorage").Remotes.Carry
    local hrp = c:FindFirstChild("HumanoidRootPart")
    local best, bd = nil, nil
    if hrp then
        for _, pt in ipairs(game:GetService("CollectionService"):GetTagged("UnhookPoint")) do
            if pt:IsA("BasePart") and pt:IsDescendantOf(workspace) then
                local d = (pt.Position - hrp.Position).Magnitude
                if not bd or d < bd then best, bd = pt, d end
            end
        end
    end
    if best and bd < 20 then
        pcall(function() Carry.UnHookEvent:FireServer(best) end)
    end
    if hookTries > 3 then   -- rescue path didn't take within ~1s; add roll attempts
        pcall(function() Carry.SelfUnHookEvent:FireServer() end)
    end
end

-- ============================================================
--  RANGE RINGS / SPEAR ARC / BLIND METER
--
--  Decoded live 2026-08-01, from both sides of one round (Veil):
--    * Spear physics: PlayerScripts.Mechanics.Veil.ProjectileHandler, driven by
--      Remotes.Mechanics.visualize(char, dir, speed, gmult, id):
--          origin = HRP.Position + HRP.LookVector*3 + (0, 1.5, 0)
--          v = dir.Unit * speed
--          every Heartbeat:  v += (0, -Gravity*dt*gmult, 0) ;  p += v*dt
--          MaxLife = 4s.   workspace.Gravity = 196.2.
--      speed/gmult only exist on the wire once a throw goes out, so they are
--      learned from the first observed throw and reused for the pre-throw line.
--    * Killer char attrs: spearmode (aiming), Spears (ammo), IsStunned,
--      IsCarrying, BloodLust, Speed, TerrorRadius, SuspenseRadius.
--    * Basic-attack hit detection is a Legacy (server) Script at
--      Character.Weapon["Right Arm"].Weapon.Main.BasicAttack. The hitbox is
--      computed server side and is not readable, so both ranges are MEASURED
--      from real hits rather than read out of config.
-- ============================================================
local RS_ = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- ---------- drawn ground rings ----------

-- ---------- measured attack ranges ----------
-- Keyed by killer name (Veil/Jason/...) because reach differs per killer, and
-- kept as a running max: a hit that lands at 11 studs proves reach >= 11.
local RANGE_FILE = "wh_vd_ranges.json"
local ranges = {}
local DEF_HIT, DEF_LUNGE = 9, 15   -- placeholders only, shown as "est" until measured
do
    local ok, raw = pcall(function()
        if isfile and isfile(RANGE_FILE) then return readfile(RANGE_FILE) end
    end)
    if ok and raw then
        local ok2, t = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok2 and type(t) == "table" then ranges = t end
    end
end
local function saveRanges()
    if not writefile then return end
    pcall(function() writefile(RANGE_FILE, HttpService:JSONEncode(ranges)) end)
end
local function killerKey(kp)
    if not kp then return nil end
    return tostring(kp:GetAttribute("SelectedKiller") or kp.Name)
end
local function rangeFor(kp)
    local r = ranges[killerKey(kp) or ""] or {}
    return (r.hit and r.hit > 0) and r.hit or DEF_HIT,
           (r.lunge and r.lunge > 0) and r.lunge or DEF_LUNGE,
           r.n or 0
end

-- A lunge announces itself on Remotes.Attacks.Lunge; anything landing inside
-- that window is credited to lunge reach, everything else to the basic swing.
local lungeUntil = 0
pcall(function()
    track(RS_.Remotes.Attacks.Lunge.OnClientEvent:Connect(function()
        lungeUntil = os.clock() + 0.7
    end))
end)

local function recordHit()
    local kp = getKillerPlayer()
    local kc = kp and kp.Character
    local root = kc and kc:FindFirstChild("HumanoidRootPart")
    local hrp = myHRP()
    if not (root and hrp) then return end
    local d = (root.Position - hrp.Position).Magnitude
    if d <= 0 or d > 60 then return end   -- teleport/mori, not a swing
    local key = killerKey(kp)
    local r = ranges[key] or { hit = 0, lunge = 0, n = 0 }
    if os.clock() < lungeUntil then
        r.lunge = math.max(r.lunge or 0, d)
    else
        r.hit = math.max(r.hit or 0, d)
    end
    r.n = (r.n or 0) + 1
    ranges[key] = r
    saveRanges()
end

local function watchSelf(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        local last = hum.Health
        track(hum.HealthChanged:Connect(function(h)
            if h < last then recordHit() end
            last = h
        end))
    end
    track(char:GetAttributeChangedSignal("Knocked"):Connect(function()
        if char:GetAttribute("Knocked") then recordHit() end
    end))
end
watchSelf(LocalPlayer.Character)
track(LocalPlayer.CharacterAdded:Connect(watchSelf))

-- ---------- Veil spear ----------
-- Two throws, learned separately. ProjectileHandler turns the aura particles on
-- when speed > 150, so that threshold splits the charged throw from the normal
-- one; each keeps its own observed speed/gravity for prediction.
local spearNorm    = { speed = 150, gmult = 1, seen = false }
local spearCharged = { speed = 220, gmult = 1, seen = false }

-- Persisted next to the measured attack ranges, so a speed only has to be
-- observed once ever rather than once per session.
-- Object-space launch offsets. NOTE THE SIGN: a CFrame's LookVector is -Z, so
-- "in front" is NEGATIVE Z. Positive Z here put the arc behind the killer,
-- normally inside a wall, where it terminated on the first raycast and drew
-- nothing at all.
local learned = {
    Veil        = { origin = Vector3.new(0, 1.5, -3), seen = false },
    Cure        = { speed = 95, gmult = 1, origin = Vector3.new(0, 1.5, -2), seen = false },
    Abysswalker = { speed = 120, gmult = 0, origin = Vector3.new(0, 1.5, -2), seen = false },
}

local PROJ_FILE = "wh_vd_proj.json"
do
    local ok, raw = pcall(function()
        if isfile and isfile(PROJ_FILE) then return readfile(PROJ_FILE) end
    end)
    if ok and raw then
        local ok2, t = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok2 and type(t) == "table" then
            for key, prof in pairs({ norm = spearNorm, charged = spearCharged }) do
                local v = t[key]
                if type(v) == "table" and tonumber(v.speed) then
                    prof.speed = tonumber(v.speed)
                    prof.gmult = tonumber(v.gmult) or 1
                    prof.seen = v.seen == true
                end
            end
            -- Origins saved before the sign fix are behind the killer; ignore
            -- them so a bad value cannot persist across the update.
            if type(t.learned) == "table" and t.originSign == "front-negative-z" then
                for name, rec in pairs(t.learned) do
                    if learned[name] and tonumber(rec.x) then
                        learned[name].origin = Vector3.new(rec.x, rec.y, rec.z)
                        learned[name].seen = rec.seen == true
                        if tonumber(rec.speed) then learned[name].speed = tonumber(rec.speed) end
                        if tonumber(rec.gmult) then learned[name].gmult = tonumber(rec.gmult) end
                    end
                end
            end
        end
    end
end
local function saveProj()
    if not writefile then return end
    pcall(function()
        local origins = {}
        for name, rec in pairs(learned) do
            origins[name] = { x = rec.origin.X, y = rec.origin.Y, z = rec.origin.Z,
                speed = rec.speed, gmult = rec.gmult, seen = rec.seen }
        end
        writefile(PROJ_FILE, HttpService:JSONEncode({
            originSign = "front-negative-z",
            norm    = { speed = spearNorm.speed,    gmult = spearNorm.gmult,    seen = spearNorm.seen },
            charged = { speed = spearCharged.speed, gmult = spearCharged.gmult, seen = spearCharged.seen },
            learned = origins,
        }))
    end)
end
local liveProj = {}   -- { kind, origin, dir, speed, gmult, life, t0 }

-- Measured live 2026-08-01 on a charged hold: the aura is the "Hitbox" emitter
-- set (0 / Fire29 / Shining Ripple / Soft Fireflies) -- the same emitters
-- ProjectileHandler switches on for speed > 150 -- and it goes live about 4s
-- into the hold, staying on until release. In first person it rides the
-- VIEWMODEL (workspace.CurrentCamera.VM), not the character.
--
-- The emitters are found once and cached: rescanning ~490 descendants on every
-- call, from three call sites, was costing more per frame than everything else
-- in the module put together.
local auraCache, auraStamp = {}, -10
local function auraEmitters()
    if os.clock() - auraStamp < 1 then return auraCache end
    auraStamp = os.clock()
    auraCache = {}
    local function collect(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ParticleEmitter") and d.Parent and d.Parent.Name == "Hitbox" then
                auraCache[#auraCache + 1] = d
            end
        end
    end
    local cv = workspace.CurrentCamera
    collect(cv and cv:FindFirstChild("VM"))
    local kp = getKillerPlayer()
    if kp and kp ~= LocalPlayer then collect(kp.Character) end
    return auraCache
end

local chargeFrame, chargeVal = -1, false
local function isCharged()
    if chargeFrame == frameId then return chargeVal end
    chargeFrame = frameId
    chargeVal = false
    for _, e in ipairs(auraEmitters()) do
        if e.Parent and e.Enabled then
            chargeVal = true
            break
        end
    end
    return chargeVal
end

-- ============================================================
--  PROJECTILE PROFILES
--
--  Each projectile killer ships its own client handler, and the three differ
--  enough that one shared guess would be wrong for two of them. Decoded from
--  those handlers directly:
--
--    Veil   PlayerScripts.Mechanics.Veil.ProjectileHandler
--           Remotes.Mechanics.visualize(char, dir, speed, gmult, id)
--           ballistic, gravity * gmult, speed learned per charge mode
--    Cure   PlayerScripts.Mechanics.Cure.Flaskhandler
--           Remotes.Killers.Cure.VisualizeFlask(origin, target, dir, skin)
--           ballistic at a FIXED speed 95, full gravity, and the launch vector
--           is biased upward before normalising: (dir + (0,0.35,0)).Unit
--    Abyss  PlayerScripts.Mechanics.Abyss.ProjectileHandler
--           Remotes.Killers.Abysswalker.visualize(originCF, dir, speed)
--           LINEAR -- no gravity at all -- 3.5s lifetime
--
--  Launch origin is not knowable before a throw, so it is learned: every
--  observed throw reports its true origin, which is stored as an offset in the
--  thrower's own frame and reused for prediction.
-- ============================================================
local PROJ = {
    Veil = {
        kind = "ballistic", life = 4,
        profile = function(kc)
            local ch = isCharged()
            local m = ch and spearCharged or spearNorm
            return m.speed, m.gmult, ch
        end,
        launch = function(aim) return aim end,
    },
    Cure = {
        kind = "ballistic", life = 3.2,
        profile = function() return learned.Cure.speed, learned.Cure.gmult, false end,
        launch = function(aim) return (aim + Vector3.new(0, 0.35, 0)).Unit end,
    },
    Abysswalker = {
        kind = "linear", life = 3.5,
        profile = function() return learned.Abysswalker.speed, 0, true end,   -- waves pass terrain
        launch = function(aim) return aim end,
    },
}

local function killerKind(kp)
    return kp and tostring(kp:GetAttribute("SelectedKiller")) or ""
end
local function activeProj(kp)
    return PROJ[killerKind(kp)]
end

-- Store an observed launch origin as an offset in the thrower's own frame, so
-- it stays correct whichever way they are facing next time.
local function learnOrigin(name, root, worldOrigin)
    if not (root and worldOrigin and learned[name]) then return end
    local rel = root.CFrame:PointToObjectSpace(worldOrigin)
    learned[name].origin = rel
    learned[name].seen = true
end
local function originFor(name, root)
    local rec = learned[name]
    local rel = (rec and rec.origin) or Vector3.new(0, 1.5, 2)
    return root.CFrame:PointToWorldSpace(rel)
end

-- Steps at the game's own 1/60 so the path matches ProjectileHandler, but only
-- emits every DECIMATE'th point: 4s of flight is 240 steps and the curve reads
-- identically at a third of that. gmult 0 means no gravity term at all, which
-- is how Abysswalker's wave travels.
local DECIMATE = 3
local function simulateArc(origin, dir, speed, gmult, maxT)
    local pts = { origin }
    local p, v = origin, dir.Unit * speed
    local dt, t, i = 1 / 60, 0, 0
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { LocalPlayer.Character }
    local kp = getKillerPlayer()
    if kp and kp.Character then ignore[#ignore + 1] = kp.Character end
    rp.FilterDescendantsInstances = ignore
    local wallHit, wallIdx, wallT
    while t < (maxT or 4) do
        v = v + Vector3.new(0, -(workspace.Gravity * dt) * gmult, 0)
        local np = p + v * dt
        if not wallHit then
            local hit = workspace:Raycast(p, np - p, rp)
            if hit then
                wallHit = hit.Position
                pts[#pts + 1] = hit.Position
                wallIdx, wallT = #pts, t
            end
        end
        p = np
        i = i + 1
        if i % DECIMATE == 0 then pts[#pts + 1] = p end
        t = t + dt
    end
    pts[#pts + 1] = p
    return pts, wallHit, wallIdx, p, wallT, t
end

pcall(function()
    track(RS_.Remotes.Mechanics.visualize.OnClientEvent:Connect(function(char, dir, speed, gmult, id)
        if typeof(dir) ~= "Vector3" or type(speed) ~= "number" then return end
        local bucket = (speed > 150) and spearCharged or spearNorm
        local changed = (bucket.speed ~= speed) or (bucket.gmult ~= (gmult or 1)) or not bucket.seen
        bucket.speed, bucket.gmult, bucket.seen = speed, gmult or 1, true
        if changed then saveProj() end
        local origin
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            origin = root.Position + root.CFrame.LookVector * 3 + Vector3.new(0, 1.5, 0)
        end
        if origin then
            learnOrigin("Veil", root, origin)
            liveProj[#liveProj + 1] = {
                kind = "Veil", origin = origin, dir = dir.Unit, speed = speed,
                gmult = gmult or 1, life = 4, t0 = os.clock(), id = id,
            }
        end
    end))
end)

-- Cure and Abysswalker announce their own projectiles; learn each one's real
-- speed and launch origin from the first throw seen, then reuse them.
pcall(function()
    local C = RS_.Remotes.Killers.Cure
    track(C.VisualizeFlask.OnClientEvent:Connect(function(origin, target, dir, _skin)
        if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then return end
        local kp = getKillerPlayer()
        local root = kp and kp.Character and kp.Character:FindFirstChild("HumanoidRootPart")
        learnOrigin("Cure", root, origin)
        saveProj()
        liveProj[#liveProj + 1] = {
            kind = "Cure", origin = origin, dir = (dir + Vector3.new(0, 0.35, 0)).Unit,
            speed = 95, gmult = 1, life = 3.2, t0 = os.clock(), target = target,
        }
    end))
end)
pcall(function()
    local A = RS_.Remotes.Killers.Abysswalker
    track(A.visualize.OnClientEvent:Connect(function(cf, dir, speed)
        if typeof(dir) ~= "Vector3" or type(speed) ~= "number" then return end
        local origin = (typeof(cf) == "CFrame") and cf.Position or cf
        if typeof(origin) ~= "Vector3" then return end
        local kp = getKillerPlayer()
        local root = kp and kp.Character and kp.Character:FindFirstChild("HumanoidRootPart")
        learnOrigin("Abysswalker", root, origin)
        learned.Abysswalker.speed, learned.Abysswalker.seen = speed, true
        saveProj()
        liveProj[#liveProj + 1] = {
            kind = "Abysswalker", origin = origin, dir = dir.Unit,
            speed = speed, gmult = 0, life = 3.5, t0 = os.clock(),
        }
    end))
end)

-- ---------- flashlight blind ----------
-- The blind itself is resolved server side; all that is visible from here is
-- how long our beam has been on the killer. The threshold is therefore learned:
-- whenever GotBlinded lands, the beam time at that instant becomes the target.
local blindHold, blindNeed, blindSamples = 0, 1.1, 0
local blindDot, blindDist = -1, 0
pcall(function()
    track(RS_.Remotes.Items.Flashlight.GotBlinded.OnClientEvent:Connect(function()
        if blindHold > 0.05 then
            blindNeed = (blindNeed * blindSamples + blindHold) / (blindSamples + 1)
            blindSamples = blindSamples + 1
        end
        blindHold = 0
    end))
end)

local function findFlashlightPart()
    local c = LocalPlayer.Character
    if not c then return nil end
    -- the flashlight is a MODEL child of the character carrying "remaining"
    -- (fuel) and "loc" -- do not assume a class, only the attribute
    for _, d in ipairs(c:GetDescendants()) do
        if d:GetAttribute("remaining") ~= nil then return d end
    end
    return nil
end

-- Whether the beam is actually on. UserInputService:IsMouseButtonPressed never
-- reported the hold in this game (measured: 0 hits over 114 samples while the
-- light was in use), so read the light itself -- FlashlightClient enables the
-- SpotLight/Beam when it activates, which is the state we actually care about.
local function beamOn(fl)
    if not fl then return false end
    for _, d in ipairs(fl:GetDescendants()) do
        if (d:IsA("SpotLight") or d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("Beam"))
        and d.Enabled then
            return true
        end
    end
    return false
end

-- ---------- per-frame ----------

local function stepRings(hrp, kp, kroot)
    local anchor = S.ringOnSelf and hrp or kroot
    if not (anchor and (S.hitRing or S.lungeRing)) then return end
    local hitR, lungeR = rangeFor(kp)
    local k = S.ringScale / 100
    local base = anchor.Position - Vector3.new(0, anchor.Size.Y / 2 + 2.4, 0)
    if S.hitRing then dRing(base, hitR * k, PAL.killer, 0.9) end
    if S.lungeRing then dRing(base, lungeR * k, PAL.accent, 0.75) end
end

-- A landing point needs to read as a place on the ground, not a floating word:
-- a reticle ring where it lands, a stalk connecting it to the arc so the height
-- is unambiguous, and the label above that.
local function landingMark(pos, label, col, alpha)
    dRing(pos, 2.2, col, alpha)
    dRing(pos, 0.7, col, alpha)
    local a, b = toScreen(pos + Vector3.new(0, 4, 0)), toScreen(pos)
    if a and b then dLine(a, b, col, alpha, 1) end
    local t = toScreen(pos + Vector3.new(0, 5.4, 0))
    if t then dText(t, label, col, 15, true) end
end

local function stepSpear(hrp, kp, kc, kroot)
    -- a spear already in flight wins over the predicted line
    if S.spearLive then
        for i = #liveProj, 1, -1 do
            local sp = liveProj[i]
            if os.clock() - sp.t0 > (sp.life or 4) then
                table.remove(liveProj, i)
            else
                -- in-flight spears have declared their mode: the aura
                -- (speed > 150) phases through walls, anything slower stops
                local phasing = sp.speed > 150
                local pts, wall, wallIdx, tail, wallT = simulateArc(sp.origin, sp.dir, sp.speed, sp.gmult, 4)
                dPath(pts, (not phasing) and wallIdx or nil, PAL.killer, 1, PAL.muted, 0.35)
                local land = (not phasing) and wall or tail
                if land then
                    landingMark(land, wallT and ("impact  %.2fs"):format(wallT) or "impact", PAL.killer, 1)
                end
                return
            end
        end
    end
    if not (S.spearLine and kc and kroot and kp) then return end
    local pr = activeProj(kp)
    if not pr then return end            -- this killer throws nothing
    local isVeil = killerKind(kp) == "Veil"
    -- Only Veil advertises an aim state (spearmode) and an ammo count; the
    -- others give no pre-throw tell, so their line is simply always drawn.
    local aiming = (not isVeil) or (kc:GetAttribute("spearmode") == true)
    if isVeil then
        local ammo = tonumber(kc:GetAttribute("Spears")) or 0
        if not ((aiming or S.spearAlways) and ammo > 0) then return end
    end

    -- Origin always tracks HRP facing (that is what ProjectileHandler uses),
    -- but the throw direction is the thrower's camera. Ours is exact; another
    -- killer's is only their replicated body facing.
    local origin = originFor(killerKind(kp), kroot)
    local aim = kroot.CFrame.LookVector
    if kp == LocalPlayer and cam then aim = cam.CFrame.LookVector end

    local speed, gmult, charged = pr.profile(kc)
    local pts, wall, wallIdx, tail, wallT, tailT =
        simulateArc(origin, pr.launch(aim), speed, gmult, pr.life)

    local col = charged and PAL.accent or PAL.killer
    local live = aiming and 1 or 0.6
    local function away(v)
        return hrp and math.floor((v - hrp.Position).Magnitude + 0.5) or 0
    end

    if charged then
        -- pierces walls: one unbroken path, and the wall it goes through is
        -- only worth marking as a landmark, not as a stopping point
        dPath(pts, nil, col, live, col, live)
        landingMark(tail, ("PIERCE  %dm  %.2fs"):format(away(tail), tailT or 0), col, live)
        if wall then
            local pt = toScreen(wall)
            if pt then dText(pt, "through here", PAL.muted, 12, true) end
        end
    else
        dPath(pts, wallIdx, aiming and col or PAL.muted, live, PAL.muted, 0.3)
        local land = wall or tail
        landingMark(land, ("LANDS  %dm  %.2fs"):format(away(land), (wall and wallT or tailT) or 0), col, live)
    end
end

-- ============================================================
--  AIM SOLVER + SOFT LOCK
--
--  Rebuilt against MEASURED physics. The first attempt aimed high on every shot
--  because it ran before any throw had been observed, so it assumed gmult 1 --
--  the spear actually falls at 0.5 gravity, which makes the real drop half of
--  what it was solving for. Nothing here runs until the projectile has been
--  seen at least once; it says so instead of guessing.
--
--  Drop: for a fixed launch speed the elevation is closed form,
--      tan(theta) = (v^2 - sqrt(v^4 - g*(g*x^2 + 2*y*v^2))) / (g*x)
--  with g = workspace.Gravity * gmult, x the horizontal distance and y the
--  height difference. The minus root is the flatter arc. Negative discriminant
--  means genuinely out of range.
--
--  Movement: the target's own velocity, differenced from its position (the
--  replicated AssemblyLinearVelocity reads zero for remote characters), then
--  iterated to a fixed point -- aim, read the flight time, re-aim where they
--  will be by then -- because the flight time itself depends on the lead.
-- ============================================================
local function ballisticDir(origin, target, speed, gmult)
    if speed <= 0 then return nil end
    local g = workspace.Gravity * (gmult or 1)
    local d = target - origin
    if g <= 0 then                                  -- linear projectile
        local dist = d.Magnitude
        if dist < 1e-3 then return nil end
        return d.Unit, dist / speed
    end
    local flat = Vector3.new(d.X, 0, d.Z)
    local x = flat.Magnitude
    if x < 1e-3 then return nil end
    local v2 = speed * speed
    local disc = v2 * v2 - g * (g * x * x + 2 * d.Y * v2)
    if disc < 0 then return nil end
    local tanT = (v2 - math.sqrt(disc)) / (g * x)
    return (flat.Unit + Vector3.new(0, tanT, 0)).Unit,
        x / (speed * math.cos(math.atan(tanT)))
end

local velTrack = setmetatable({}, { __mode = "k" })
local function targetVelocity(part)
    local now, pos = os.clock(), part.Position
    local rec = velTrack[part]
    if not rec then
        velTrack[part] = { pos = pos, t = now, vel = Vector3.zero }
        return Vector3.zero
    end
    local dt = now - rec.t
    if dt >= 0.03 then
        local raw = (pos - rec.pos) / dt
        rec.vel = rec.vel:Lerp(Vector3.new(raw.X, 0, raw.Z), 0.4)
        rec.pos, rec.t = pos, now
    end
    return rec.vel
end

-- Fixed-point intercept: flight time sets the lead, and the lead sets the
-- flight time, so iterate until the aim point stops moving.
local function solveIntercept(origin, part, speed, gmult)
    local vel = S.aimLead and targetVelocity(part) or Vector3.zero
    local aimAt = part.Position
    local dir, flight
    for _ = 1, 6 do
        local nd, nf = ballisticDir(origin, aimAt, speed, gmult)
        if not nd then return nil end
        dir, flight = nd, nf
        local nextAim = part.Position + vel * nf
        local moved = (nextAim - aimAt).Magnitude
        aimAt = nextAim
        if moved < 0.05 then break end
    end
    return dir, flight, aimAt
end

-- Integrate the solved shot and report how close it really passes. If the
-- solver and the simulation disagree the number says so, instead of the lock
-- quietly pointing somewhere wrong.
local function missDistance(origin, dir, speed, gmult, aimAt, life)
    local p, v = origin, dir * speed
    local dt, t, best = 1 / 60, 0, math.huge
    while t < (life or 4) do
        v = v + Vector3.new(0, -(workspace.Gravity * dt) * gmult, 0)
        p = p + v * dt
        local m = (p - aimAt).Magnitude
        if m < best then best = m end
        t = t + dt
    end
    return best
end

local function pickTarget()
    if not cam then return nil end
    local centre = cam.ViewportSize / 2
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isSurvivor(p) then
            local c = p.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local root = c and c:FindFirstChild("HumanoidRootPart")
            if root and hum and hum.Health > 0 and not c:GetAttribute("Knocked") then
                local sp, on = cam:WorldToViewportPoint(root.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - centre).Magnitude
                    if d <= S.aimFov and (not bestD or d < bestD) then best, bestD = root, d end
                end
            end
        end
    end
    return best
end

-- nil when there is nothing to shoot; .calibrating when the physics is unknown
local function aimSolution(kp, kc, kroot)
    if not (cam and kp and kc and kroot) then return nil end
    local pr = activeProj(kp)
    if not pr then return nil end
    local kind = killerKind(kp)
    if kind == "Veil" and (tonumber(kc:GetAttribute("Spears")) or 0) <= 0 then return nil end
    local speed, gmult, charged = pr.profile(kc)
    local measured = (kind == "Veil")
        and (charged and spearCharged.seen or spearNorm.seen)
        or (learned[kind] and learned[kind].seen)
    if not measured then return { calibrating = true, charged = charged } end
    local target = pickTarget()
    if not target then return nil end
    local origin = originFor(kind, kroot)
    local dir, flight, aimAt = solveIntercept(origin, target, speed, gmult)
    if not dir then return { outOfRange = true } end
    return {
        dir = dir, flight = flight, aimAt = aimAt, origin = origin,
        charged = charged, speed = speed, gmult = gmult, life = pr.life,
        miss = missDistance(origin, dir, speed, gmult, aimAt, pr.life),
    }
end

local LOCK_BIND = "wh_vd_aimlock"
local lockHeld = false

-- CameraType is Custom, so Roblox's camera module owns the CFrame and rebuilds
-- it every frame from its own yaw/pitch. Writing cam.CFrame is overwritten on
-- the next frame, every frame, which is what made the first version shudder.
-- Steering the mouse feeds the same path the player uses, so the camera module
-- does the turning and there is nothing to fight. Pixels-per-radian varies with
-- sensitivity and FOV, so it is calibrated from the loop: compare the turn
-- asked for last frame with the turn actually delivered.
local pxPerRad, lastAsk = 900, nil
local lockState = "idle"

local function stepAimLock(dt)
    if not (S.aimLock and lockHeld and cam) then
        lastAsk, lockState = nil, "idle"
        return
    end
    local kp = getKillerPlayer()
    if kp ~= LocalPlayer then
        lastAsk = nil
        return
    end
    local kc = kp.Character
    local kroot = kc and kc:FindFirstChild("HumanoidRootPart")
    local sol = aimSolution(kp, kc, kroot)
    if not sol then
        lastAsk, lockState = nil, "no target"
        return
    end
    if sol.calibrating then
        lastAsk, lockState = nil, "calibrating"
        return
    end
    if sol.outOfRange then
        lastAsk, lockState = nil, "out of range"
        return
    end
    lockState = ("locked  miss %.1fm"):format(sol.miss or 0)

    local rel = cam.CFrame:VectorToObjectSpace(sol.dir)
    local yaw = math.atan2(rel.X, -rel.Z)
    local pitch = math.asin(math.clamp(rel.Y / math.max(rel.Magnitude, 1e-6), -1, 1))

    if lastAsk and math.abs(lastAsk.dx) > 2 then
        local turned = lastAsk.yaw - yaw
        if math.abs(turned) > 1e-4 then
            local est = math.abs(lastAsk.dx / turned)
            if est > 40 and est < 6000 then pxPerRad = pxPerRad * 0.85 + est * 0.15 end
        end
    end

    local err = math.max(math.abs(yaw), math.abs(pitch))
    local frac = (err <= math.rad(S.lockSnap)) and 1
        or math.clamp(1 - (S.lockSmooth ^ (dt * 60)), 0, 1)
    local cap = 220
    local dx = math.clamp(yaw * frac * pxPerRad, -cap, cap)
    local dy = math.clamp(-pitch * frac * pxPerRad, -cap, cap)

    if mousemoverel then
        pcall(mousemoverel, dx, dy)
        lastAsk = { dx = dx, dy = dy, yaw = yaw, pitch = pitch }
    else
        local pos = cam.CFrame.Position
        cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(pos, pos + sol.dir), frac)
        lastAsk = nil
    end
end
pcall(function()
    RunService:BindToRenderStep(LOCK_BIND, Enum.RenderPriority.Camera.Value + 1, stepAimLock)
end)

local function stepAimMarker(kp, kc, kroot)
    if not (S.aimMarker and kp == LocalPlayer and cam) then return end
    local sol = aimSolution(kp, kc, kroot)
    if not sol then return end
    local centre = cam.ViewportSize / 2
    if sol.calibrating then
        dText(Vector2.new(centre.X, centre.Y + 34),
            "aim: calibrating -- throw one " .. (sol.charged and "charged" or "normal") .. " shot",
            PAL.muted, 13, true)
        return
    end
    if sol.outOfRange then
        dText(Vector2.new(centre.X, centre.Y + 34), "aim: out of range", PAL.muted, 13, true)
        return
    end
    local col = sol.charged and PAL.accent or PAL.killer
    landingMark(sol.aimAt, ("INTERCEPT  %.2fs  miss %.1fm"):format(sol.flight, sol.miss), col, 1)
    local mp, on = cam:WorldToViewportPoint(cam.CFrame.Position + sol.dir * 60)
    if on then
        local at = Vector2.new(mp.X, mp.Y)
        dLine(centre, at, col, 0.45, 1)
        local r = 7
        dLine(at - Vector2.new(r, 0), at + Vector2.new(r, 0), col, 1, 2)
        dLine(at - Vector2.new(0, r), at + Vector2.new(0, r), col, 1, 2)
    end
end

-- ============================================================
--  KILLER POWER READOUT
--
--  Stalker, Masked, Hidden, Slasher, Jason and the base Killer have no
--  projectile to predict; what is worth seeing is their power state. Rather
--  than hardcode six killers, this reads whatever the ACTIVE killer puts on its
--  own character: every attribute that is not part of the shared baseline is by
--  definition power-specific (that is exactly how Veil's Spears / spearmode
--  showed up), so new killers and reworks are picked up for free.
--
--  Power remotes are watched the same way -- everything under
--  Remotes.Killers.<killer> -- and the most recent firing is timestamped, which
--  is what turns a cooldown into something you can actually read.
-- ============================================================
local BASE_ATTRS = {
    Speed = true, IsChasing = true, ChaseTargetUserId = true, TerrorRadius = true,
    SuspenseRadius = true, BloodLust = true, HookCount = true, HookedProgress = true,
    Knocked = true, breakspeed = true, speedboost = true, Chasemusic = true,
    Suspense = true, IsCarrying = true, IsCarried = true, IsStunned = true,
    Immobile = true, overridelookscript = true, swift = true, special = true,
    anticamp = true, IsHooked = true, HookProgressDepleting = true,
}

local powerEvents, powerConns, powerWatched = {}, {}, nil
local function watchPower(kind)
    if powerWatched == kind then return end
    powerWatched = kind
    for _, c in ipairs(powerConns) do pcall(function() c:Disconnect() end) end
    powerConns, powerEvents = {}, {}
    local folder = RS_.Remotes:FindFirstChild("Killers")
    folder = folder and folder:FindFirstChild(kind)
    if not folder then return end
    for _, r in ipairs(folder:GetDescendants()) do
        if r:IsA("RemoteEvent") then
            local ok, c = pcall(function()
                return r.OnClientEvent:Connect(function()
                    powerEvents[r.Name] = os.clock()
                end)
            end)
            if ok and c then powerConns[#powerConns + 1] = c end
        end
    end
end

local function powerLines(kc)
    local attrs, events = {}, {}
    if kc then
        for k, v in pairs(kc:GetAttributes()) do
            if not BASE_ATTRS[k] then
                attrs[#attrs + 1] = ("%s=%s"):format(k, tostring(v))
            end
        end
        table.sort(attrs)
    end
    for name, t in pairs(powerEvents) do
        events[#events + 1] = { name, os.clock() - t }
    end
    table.sort(events, function(a, b) return a[2] < b[2] end)
    return attrs, events
end

local function stepPowerHud(kp, kc)
    if not (S.powerHud and cam and kc) then return end
    local attrs, events = powerLines(kc)
    if #attrs == 0 and #events == 0 then return end
    local vp = cam.ViewportSize
    local x, y = 14, vp.Y * 0.32
    dText(Vector2.new(x, y), ("%s"):format(killerKind(kp) ~= "" and killerKind(kp) or "killer"),
        PAL.killer, 14, false)
    y = y + 16
    for i = 1, math.min(#attrs, 10) do
        dText(Vector2.new(x, y), attrs[i], PAL.text, 12, false)
        y = y + 13
    end
    for i = 1, math.min(#events, 4) do
        dText(Vector2.new(x, y), ("%s  %.1fs ago"):format(events[i][1], events[i][2]), PAL.accent, 12, false)
        y = y + 13
    end
end

local function stepBlind(dt, hrp, kc, kroot)
    if not S.blindMeter then
        blindHold = 0
        return
    end
    local fl = findFlashlightPart()
    local beaming = beamOn(fl)
    local onKiller = false
    if beaming and kc and hrp and cam then
        local head = kc:FindFirstChild("Head") or kroot
        if head then
            local to = head.Position - cam.CFrame.Position
            local aimDot = cam.CFrame.LookVector:Dot(to.Unit)
            blindDot, blindDist = aimDot, to.Magnitude
            if to.Magnitude < S.blindRange and aimDot > math.cos(math.rad(S.blindCone)) then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { LocalPlayer.Character, kc }
                onKiller = workspace:Raycast(cam.CFrame.Position, to, rp) == nil
            end
        end
    end
    blindHold = onKiller and (blindHold + dt) or math.max(0, blindHold - dt * 2)
    -- Shown whenever the flashlight is held, not just while beaming: a bar that
    -- only exists mid-blind is a bar you never catch sight of.
    if not (fl and cam) then return end

    local vp = cam.ViewportSize
    local w, h = 220, 10
    local x, y = vp.X / 2 - w / 2, 96
    local pct = math.clamp(blindHold / math.max(blindNeed, 0.05), 0, 1)
    dFill(x, y, w, h, PAL.bg, 0.75)
    dFill(x, y, w * pct, h, onKiller and PAL.accent or PAL.muted, 1)
    dBox(x, y, w, h, PAL.outline, 1, 1)
    local fuel = fl and math.floor((fl:GetAttribute("remaining") or 0) + 0.5) or 0
    dText(Vector2.new(vp.X / 2, y - 16),
        ("blind %d%%   fuel %d   %s%s"):format(math.floor(pct * 100 + 0.5), fuel,
            blindSamples > 0 and ("%.2fs"):format(blindNeed) or "est",
            onKiller and "   ON TARGET"
                or (beaming and ("   off by %ddeg @ %dm"):format(
                        math.deg(math.acos(math.clamp(blindDot, -1, 1))), blindDist)
                    or "   light off")),
        onKiller and PAL.accent or PAL.muted, 13, true)
end

local chaseFlash = false
local function stepChaseWarn()
    if not (chaseFlash and cam) then return end
    local vp = cam.ViewportSize
    local a = 0.5 + 0.5 * math.sin(os.clock() * 7)
    dText(Vector2.new(vp.X / 2, vp.Y * 0.22), "KILLER IS CHASING YOU", PAL.killer, 20, true)
    dFill(0, 0, vp.X, 3, PAL.killer, a)
    dFill(0, vp.Y - 3, vp.X, 3, PAL.killer, a)
end

-- Single frame driver: every visual in the module is emitted here, between
-- frameBegin and frameEnd, so unused Drawings are hidden in one place.
track(RunService.RenderStepped:Connect(function(dt)
    frameBegin()
    local hrp = myHRP()
    local kp = getKillerPlayer()
    local kc = kp and kp.Character
    local kroot = kc and kc:FindFirstChild("HumanoidRootPart")

    if S.killerEsp or S.survEsp then stepPlayerEsp(hrp) end
    stepGenEsp(hrp)
    stepObjEsp(hrp)
    stepRings(hrp, kp, kroot)
    stepSpear(hrp, kp, kc, kroot)
    stepAimMarker(kp, kc, kroot)
    if kp then watchPower(killerKind(kp)) end
    stepPowerHud(kp, kc)
    stepBlind(dt, hrp, kc, kroot)
    stepChaseWarn()
    frameEnd()
end))

local intelLabels = {}   -- filled in the UI block below
local wasChased = false
local lastIntel = 0
track(RunService.Heartbeat:Connect(function()
    local kp = getKillerPlayer()
    local kc = kp and kp.Character
    local chased = false
    if kc then
        local target = kc:GetAttribute("ChaseTargetUserId")
        chased = (target == LocalPlayer.UserId) and kc:GetAttribute("IsChasing") == true
    end
    if S.chaseWarn and chased then
        chaseFlash = true
        if not wasChased then
            pcall(function() Library:Notification("The killer is chasing YOU", 3, PAL.killer) end)
        end
    else
        chaseFlash = false
    end
    if chased and kc then stepAntiChase(kc) end
    wasChased = chased
    stepAutoUnhook()

    -- labels only need a few updates a second; SetText at 60 Hz is wasted work
    if os.clock() - lastIntel < 0.25 then return end
    lastIntel = os.clock()

    stepRepairAlert()

    if intelLabels.killer then
        local hrp = myHRP()
        if kp and kc then
            local root = kc:FindFirstChild("HumanoidRootPart")
            local dist = (hrp and root) and (math.floor((root.Position - hrp.Position).Magnitude + 0.5) .. "m") or "?"
            intelLabels.killer:SetText("Killer: " .. tostring(kp:GetAttribute("SelectedKiller") or "?") .. " (" .. kp.Name .. ")")
            intelLabels.dist:SetText("Distance: " .. dist .. "   Speed: " .. tostring(kc:GetAttribute("Speed") or "?"))
            local tgt = "-"
            local tid = kc:GetAttribute("ChaseTargetUserId")
            if tid then
                local tp = Players:GetPlayerByUserId(tid)
                tgt = tp and tp.Name or tostring(tid)
            end
            intelLabels.chase:SetText("Chasing: " .. (kc:GetAttribute("IsChasing") and tgt or "-")
                .. "   BloodLust: " .. tostring(kc:GetAttribute("BloodLust") or 0))
        else
            intelLabels.killer:SetText("Killer: -")
            intelLabels.dist:SetText("Distance: -")
            intelLabels.chase:SetText("Chasing: -")
        end
        local gens = getMapFolder("Generators") or getMapFolder("Gens")
        if gens then
            local done, total = 0, 0
            for _, gen in ipairs(gens:GetChildren()) do
                total = total + 1
                if gen:GetAttribute("Completed") then done = done + 1 end
            end
            intelLabels.gens:SetText("Generators: " .. done .. "/" .. total .. " done")
        end

        -- Perks ride along as child scripts named "<Perk> <tier>", e.g.
        -- "Brutal Strength 3" -- system scripts never end in a digit.
        if intelLabels.perks then
            local found = {}
            if kc then
                for _, d in ipairs(kc:GetChildren()) do
                    if (d:IsA("Script") or d:IsA("LocalScript")) and d.Name:match("%s%d$") then
                        found[#found + 1] = d.Name
                    end
                end
            end
            intelLabels.perks:SetText("Perks: " .. (#found > 0 and table.concat(found, ", ") or "-"))
        end

        if intelLabels.ranges then
            local hitR, lungeR, n = rangeFor(kp)
            intelLabels.ranges:SetText(n > 0
                and ("Measured: hit %.1f  lunge %.1f  (%d hits)"):format(hitR, lungeR, n)
                or ("Measured: none yet -- showing est %d / %d"):format(DEF_HIT, DEF_LUNGE))
        end

        if intelLabels.lock then intelLabels.lock:SetText("Lock: " .. lockState) end

        if intelLabels.power then
            local attrs = powerLines(kc)
            intelLabels.power:SetText(("Power: %s"):format(
                #attrs > 0 and table.concat(attrs, "  ", 1, math.min(#attrs, 4)) or "-"))
        end

        if intelLabels.spear then
            if kc and kc:GetAttribute("Spears") ~= nil then
                intelLabels.spear:SetText(("Spear: %s ammo   %s   speed %s")
                    :format(tostring(kc:GetAttribute("Spears")),
                        kc:GetAttribute("spearmode") and "AIMING" or "idle",
                        (function()
                            local ch = isCharged()
                            local prof = ch and spearCharged or spearNorm
                            return ("%s %s%.0f"):format(ch and "CHARGED" or "normal",
                                prof.seen and "" or "~", prof.speed)
                        end)()))
            else
                intelLabels.spear:SetText(("Projectile: %s"):format(
                    activeProj(kp) and (killerKind(kp) .. " (predicted)") or "none for this killer"))
            end
        end
    end

    -- killer-side summary: what every survivor is doing right now
    if intelLabels.survs then
        local total, knocked, hooked, repairing = 0, 0, 0, 0
        for _, p in ipairs(Players:GetPlayers()) do
            local c = isSurvivor(p) and p.Character
            if c then
                total = total + 1
                if c:GetAttribute("Knocked") then knocked = knocked + 1 end
                local hprog = c:GetAttribute("HookedProgress")
                if hprog and hprog < 100 then hooked = hooked + 1 end
                if (c:GetAttribute("repairing") or 0) > 0 then repairing = repairing + 1 end
            end
        end
        intelLabels.survs:SetText(("Survivors: %d   down: %d   hooked: %d   repairing: %d")
            :format(total, knocked, hooked, repairing))
    end
end))

-- ============================================================
--  UI  (Violence District page first -> first tab; universal loads after)
-- ============================================================
do
    local Page = Window:Page({ Name = "Violence District" })

    -- ---------- ESP ----------
    local Vis = Page:SubPage({ Name = "ESP" })

    local PSec = Vis:Section({ Name = "Players", Side = 1 })
    PSec:Toggle({ Name = "Killer", Flag = "VD_KillerEsp", Default = false,
        Callback = function(v) S.killerEsp = v end })
    PSec:Toggle({ Name = "Survivors", Flag = "VD_SurvEsp", Default = false,
        Callback = function(v) S.survEsp = v end })

    local StSec = Vis:Section({ Name = "Style", Side = 1 })
    StSec:Toggle({ Name = "Box", Flag = "VD_EspBox", Default = true,
        Callback = function(v) S.espBox = v end })
    StSec:Toggle({ Name = "Name", Flag = "VD_EspName", Default = true,
        Callback = function(v) S.espName = v end })
    StSec:Toggle({ Name = "Distance", Flag = "VD_EspDist", Default = true,
        Callback = function(v) S.espDist = v end })
    StSec:Toggle({ Name = "Health bar", Flag = "VD_EspHealth", Default = true,
        Callback = function(v) S.espHealth = v end })
    StSec:Toggle({ Name = "State text", Flag = "VD_EspState", Default = true,
        Callback = function(v) S.espState = v end })
    StSec:Toggle({ Name = "Tracer", Flag = "VD_EspTracer", Default = false,
        Callback = function(v) S.espTracer = v end })

    local OSec = Vis:Section({ Name = "Objectives", Side = 2 })
    OSec:Toggle({ Name = "Generators (live %)", Flag = "VD_GenEsp", Default = false,
        Callback = function(v) S.genEsp = v end })
    OSec:Toggle({ Name = "Hide completed gens", Flag = "VD_GenHideDone", Default = true,
        Callback = function(v) S.genHideDone = v end })
    OSec:Toggle({ Name = "Hooks", Flag = "VD_HookEsp", Default = false,
        Callback = function(v) S.hookEsp = v end })
    OSec:Toggle({ Name = "Pallets", Flag = "VD_PalletEsp", Default = false,
        Callback = function(v) S.palletEsp = v end })
    OSec:Toggle({ Name = "Windows", Flag = "VD_VaultEsp", Default = false,
        Callback = function(v) S.vaultEsp = v end })

    -- ---------- survivor ----------
    local Surv = Page:SubPage({ Name = "Survivor" })

    local SSec = Surv:Section({ Name = "Skill checks", Side = 1 })
    SSec:Toggle({ Name = "Auto skill check", Flag = "VD_AutoSkill", Default = false,
        Callback = function(v) S.autoSkill = v end })
    SSec:Dropdown({ Name = "Mode", Flag = "VD_SkillMode", Default = "Legit", Multi = false,
        Items = { "Legit", "Instant" },
        Callback = function(v) S.skillMode = (type(v) == "table" and v[1]) or v or "Legit" end })
    SSec:Slider({ Name = "Humanize min", Flag = "VD_HumanizeMin", Min = 0, Max = 100, Default = 10,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.humanizeMin = v end })
    SSec:Slider({ Name = "Humanize max", Flag = "VD_HumanizeMax", Min = 0, Max = 150, Default = 40,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.humanizeMax = v end })
    SSec:Slider({ Name = "Miss chance", Flag = "VD_MissChance", Min = 0, Max = 100, Default = 5,
        Decimals = 0, Suffix = " %", Callback = function(v) S.missChance = v end })
    SSec:Slider({ Name = "Reaction time", Flag = "VD_ReactMs", Min = 0, Max = 300, Default = 150,
        Decimals = 0, Suffix = " ms", Callback = function(v) S.reactMs = v end })

    local MSec = Surv:Section({ Name = "Movement", Side = 2 })
    MSec:Toggle({ Name = "Always fast vault", Flag = "VD_FastVault", Default = false,
        Callback = function(v) S.fastVault = v end })
    MSec:Toggle({ Name = "Auto free from hook", Flag = "VD_AutoUnhook", Default = false,
        Callback = function(v) S.autoUnhook = v end })

    local FSec = Surv:Section({ Name = "Flashlight", Side = 2 })
    FSec:Toggle({ Name = "Blind progress bar", Flag = "VD_BlindMeter", Default = false,
        Callback = function(v) S.blindMeter = v end })
    FSec:Slider({ Name = "Beam cone", Flag = "VD_BlindCone", Min = 5, Max = 60, Default = 20,
        Decimals = 0, Suffix = " deg", Callback = function(v) S.blindCone = v end })
    FSec:Slider({ Name = "Beam range", Flag = "VD_BlindRange", Min = 15, Max = 120, Default = 60,
        Decimals = 0, Suffix = " studs", Callback = function(v) S.blindRange = v end })

    -- ---------- killer read ----------
    local Read = Page:SubPage({ Name = "Killer" })

    local RSec = Read:Section({ Name = "Attack ranges", Side = 1 })
    RSec:Toggle({ Name = "Hit range ring", Flag = "VD_HitRing", Default = false,
        Callback = function(v) S.hitRing = v end })
    RSec:Toggle({ Name = "Lunge range ring", Flag = "VD_LungeRing", Default = false,
        Callback = function(v) S.lungeRing = v end })
    RSec:Toggle({ Name = "Draw around me instead", Flag = "VD_RingSelf", Default = false,
        Callback = function(v) S.ringOnSelf = v end })
    RSec:Slider({ Name = "Ring scale", Flag = "VD_RingScale", Min = 50, Max = 200, Default = 100,
        Decimals = 0, Suffix = " %", Callback = function(v) S.ringScale = v end })
    intelLabels.ranges = RSec:Label({ Name = "Measured: -" })
    RSec:Button({ Name = "Reset measurements", Callback = function()
        ranges = {}
        saveRanges()
        spearNorm.speed, spearNorm.gmult, spearNorm.seen = 150, 1, false
        spearCharged.speed, spearCharged.gmult, spearCharged.seen = 220, 1, false
        saveProj()
        pcall(function() Library:Notification("Measured ranges + spear speeds cleared", 3, PAL.accent) end)
    end })

    local SpSec = Read:Section({ Name = "Veil spear", Side = 2 })
    SpSec:Toggle({ Name = "Predicted throw line", Flag = "VD_SpearLine", Default = false,
        Callback = function(v) S.spearLine = v end })
    SpSec:Toggle({ Name = "Show even when not aiming", Flag = "VD_SpearAlways", Default = false,
        Callback = function(v) S.spearAlways = v end })
    SpSec:Toggle({ Name = "Live spear arc", Flag = "VD_SpearLive", Default = false,
        Callback = function(v) S.spearLive = v end })
    intelLabels.spear = SpSec:Label({ Name = "Spear: -" })

    local PwSec = Read:Section({ Name = "Power readout", Side = 1 })
    PwSec:Toggle({ Name = "Killer power HUD", Flag = "VD_PowerHud", Default = false,
        Callback = function(v) S.powerHud = v end })
    intelLabels.power = PwSec:Label({ Name = "Power: -" })

    local ASec = Read:Section({ Name = "Aim", Side = 2 })
    ASec:Toggle({ Name = "Intercept marker", Flag = "VD_AimMarker", Default = false,
        Callback = function(v) S.aimMarker = v end })
    ASec:Toggle({ Name = "Soft aim lock", Flag = "VD_AimLock", Default = false,
        Callback = function(v) S.aimLock = v end })
    ASec:Label({ Name = "Aim lock key" }):Keybind({ Name = "Soft aim lock", Flag = "VD_AimLockKey",
        Mode = "Hold", Callback = function(st) lockHeld = st and true or false end })
    ASec:Toggle({ Name = "Lead moving targets", Flag = "VD_AimLead", Default = true,
        Callback = function(v) S.aimLead = v end })
    ASec:Slider({ Name = "Target FOV", Flag = "VD_AimFov", Min = 80, Max = 1200, Default = 400,
        Decimals = 0, Suffix = " px", Callback = function(v) S.aimFov = v end })
    ASec:Slider({ Name = "Smoothing", Flag = "VD_LockSmooth", Min = 0, Max = 90, Default = 30,
        Decimals = 0, Suffix = " %", Callback = function(v) S.lockSmooth = v / 100 end })
    ASec:Slider({ Name = "Snap within", Flag = "VD_LockSnap", Min = 0, Max = 6, Default = 1.2,
        Decimals = 1, Suffix = " deg", Callback = function(v) S.lockSnap = v end })
    intelLabels.lock = ASec:Label({ Name = "Lock: idle" })

    -- ---------- intel ----------
    local Intel = Page:SubPage({ Name = "Intel" })

    local KSec = Intel:Section({ Name = "Killer", Side = 1 })
    KSec:Toggle({ Name = "Chase warning", Flag = "VD_ChaseWarn", Default = false,
        Callback = function(v) S.chaseWarn = v end })
    KSec:Toggle({ Name = "Anti-chase (reset bloodlust)", Flag = "VD_AntiChase", Default = false,
        Callback = function(v) S.antiChase = v end })
    intelLabels.killer = KSec:Label({ Name = "Killer: -" })
    intelLabels.dist   = KSec:Label({ Name = "Distance: -" })
    intelLabels.chase  = KSec:Label({ Name = "Chasing: -" })
    intelLabels.perks  = KSec:Label({ Name = "Perks: -" })

    local RdSec = Intel:Section({ Name = "Round", Side = 2 })
    RdSec:Toggle({ Name = "Gen repair alerts (as killer)", Flag = "VD_RepairAlert", Default = false,
        Callback = function(v) S.repairAlert = v end })
    intelLabels.gens  = RdSec:Label({ Name = "Generators: -" })
    intelLabels.survs = RdSec:Label({ Name = "Survivors: -" })

    -- Manual escape hatch: whatever leaves the cursor wrong -- this menu, the
    -- game, or a bug of mine -- one press puts it back to what this team and
    -- round state should have.
    local FxSec = Intel:Section({ Name = "Session", Side = 1 })
    local function applyMousePolicy()
        local UIS_ = game:GetService("UserInputService")
        local want = (Library.MouseRestoreHook and Library.MouseRestoreHook())
            or Enum.MouseBehavior.Default
        UIS_.MouseBehavior = want
        UIS_.MouseIconEnabled = (want ~= Enum.MouseBehavior.LockCenter)
    end
    FxSec:Button({ Name = "Fix cursor", Callback = applyMousePolicy })
    FxSec:Label({ Name = "Fix cursor key" }):Keybind({ Name = "Fix cursor", Flag = "VD_FixCursorKey",
        Mode = "Toggle", Callback = applyMousePolicy })
end

-- universal shell after our page (movement + generic player ESP). No combat
-- module -- there is nothing to aimbot here.
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    S.killerEsp, S.survEsp, S.genEsp, S.hookEsp, S.palletEsp, S.vaultEsp = false, false, false, false, false, false
    S.autoSkill, S.chaseWarn, S.antiChase, S.autoUnhook, S.repairAlert, S.fastVault =
        false, false, false, false, false, false
    S.hitRing, S.lungeRing, S.spearLine, S.spearLive, S.spearAlways, S.blindMeter =
        false, false, false, false, false, false
    S.powerHud, S.aimMarker, S.aimLock, lockHeld = false, false, false, false
    pcall(function() RunService:UnbindFromRenderStep(LOCK_BIND) end)
    for _, c in ipairs(powerConns) do pcall(function() c:Disconnect() end) end
    chaseFlash = false
    pcall(function() Library.MouseRestoreHook = nil end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, list in pairs(DPOOL) do
        for _, d in ipairs(list) do pcall(function() d:Remove() end) end
    end
    DPOOL = { Line = {}, Text = {}, Square = {} }
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
