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
--    Gun Aimbot -- bullet system reports its own hits client-side; redirect the Fire
--                  direction + the matching Hit (keyed by Id) onto the target so the
--                  reported hit sits on the server's known trajectory and validates.
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

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UIS              = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer      = Players.LocalPlayer
local function gv() return (getgenv and getgenv()) or nil end

local MainPage = Window:Page({ Name = "Main" })

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

-- settings live in getgenv so state + the (one-time) gear hooks survive a re-exec
local S = (gv() and gv()._CMG_S) or {
    push = false, pushRange = 5, pushCD = 0.35,
    pushEquip = false, pushEnemyOnly = false,
    showRange = false, rangeColor = Color3.fromRGB(255, 80, 80),
    sword = false, swordRange = 14, swordCD = 0.2, swordEnemyOnly = false,
    swordLunge = true, swordLungeCD = 0.6,
    swordShowRange = false, swordRangeColor = Color3.fromRGB(120, 170, 255),
    gunSilent = false, gunFov = 200, gunHitPart = "Head", gunPriority = "Crosshair",
    gunMagic = false, gunTeamCheck = false, gunWallCheck = true, gunShowFov = true, gunFovColor = Color3.fromRGB(255, 255, 255),
    phys = false, sendRate = 240,
}
-- backfill fields added in later versions onto a persisted (re-exec'd) table
if S.showRange == nil then S.showRange = false end
if S.rangeColor == nil then S.rangeColor = Color3.fromRGB(255, 80, 80) end
if S.pushEquip == nil then S.pushEquip = false end
if S.pushEnemyOnly == nil then S.pushEnemyOnly = false end
if S.gunSilent == nil then S.gunSilent = false end
if S.gunFov == nil then S.gunFov = 200 end
if S.gunHitPart == nil then S.gunHitPart = "Head" end
if S.gunPriority == nil then S.gunPriority = "Crosshair" end
if S.gunMagic == nil then S.gunMagic = false end
if S.gunTeamCheck == nil then S.gunTeamCheck = false end
if S.gunWallCheck == nil then S.gunWallCheck = true end
if S.gunShowFov == nil then S.gunShowFov = true end
if S.gunFovColor == nil then S.gunFovColor = Color3.fromRGB(255, 255, 255) end
if S.swordLunge == nil then S.swordLunge = true end
if S.swordLungeCD == nil then S.swordLungeCD = 0.6 end
if S.swordEnemyOnly == nil then S.swordEnemyOnly = false end
if S.swordShowRange == nil then S.swordShowRange = false end
if S.swordRangeColor == nil then S.swordRangeColor = Color3.fromRGB(120, 170, 255) end
if gv() then gv()._CMG_S = S end

-- ---- shared target helpers ----
local function myHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
-- range visualizer: a transparent disc at your feet drawn by a Highlight outline.
-- Only renders while `on`; when off the highlight is disabled so nothing shows.
local function makeRangeViz()
    local self, disc, hl = {}, nil, nil
    function self.update(on, radius, color)
        if not on then
            if hl then hl.Enabled = false end
            return
        end
        local hrp = myHRP(); if not hrp then return end
        if not (disc and disc.Parent) then
            disc = Instance.new("Part")
            disc.Shape = Enum.PartType.Cylinder
            disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.Massless = true, false, false, false, true
            disc.Transparency = 1            -- invisible part; the Highlight does the drawing
            disc.Name = "\0"
            pcall(function() disc.Parent = workspace end)
            hl = Instance.new("Highlight")
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.FillTransparency = 0.8
            hl.Adornee = disc
            pcall(function() hl.Parent = disc end)
        end
        local dia = radius * 2
        disc.Size = Vector3.new(0.2, dia, dia)
        -- lay the cylinder flat (axis up) so the circular face sits on the ground at your feet
        disc.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
        local c = color or Color3.fromRGB(255, 80, 80)
        hl.FillColor, hl.OutlineColor, hl.Enabled = c, c, true
    end
    function self.destroy()
        if hl then pcall(function() hl:Destroy() end); hl = nil end
        if disc then pcall(function() disc:Destroy() end); disc = nil end
    end
    return self
end
-- iterate every living enemy body part within `range` studs, respecting a
-- per-target cooldown table; calls fn(part) for each one that is due to fire.
-- a real team mode only if players occupy more than 2 distinct teams (e.g. Red/Blue/
-- Neutral). With <=2 (Playing/Neutral = FFA) the team filter is ignored so it doesn't
-- skip every living player (everyone shares the "Playing" team in FFA).
local function multiTeam()
    local seen, n = {}, 0
    for _, p in ipairs(Players:GetPlayers()) do
        local t = p.Team
        if t and not seen[t] then seen[t] = true; n = n + 1 end
    end
    return n > 2
end
local function forEnemiesInRange(range, cdTable, cd, fn, enemyOnly)
    local hrp = myHRP(); if not hrp then return end
    local doTeam = enemyOnly and multiTeam()
    local now = os.clock()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character
           and not (doTeam and p.Team and LocalPlayer.Team and p.Team == LocalPlayer.Team) then
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
    local lastPush, lastEquip = {}, 0
    -- equipped tool with a Hit RemoteEvent; optionally auto-equip one from the backpack
    -- (infection Maul / similar tools start unequipped)
    local function pushRemote()
        local char = LocalPlayer.Character
        if not char then return nil end
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then
                local h = t:FindFirstChild("Hit")
                if h and h:IsA("RemoteEvent") then return h end
            end
        end
        if S.pushEquip and os.clock() - lastEquip > 0.5 then
            local bp, hum = LocalPlayer:FindFirstChild("Backpack"), char:FindFirstChildOfClass("Humanoid")
            if bp and hum then
                for _, t in ipairs(bp:GetChildren()) do
                    if t:IsA("Tool") and t:FindFirstChild("Hit") and t.Hit:IsA("RemoteEvent") then
                        lastEquip = os.clock()
                        pcall(function() hum:EquipTool(t) end)
                        break
                    end
                end
            end
        end
        return nil
    end
    track(RunService.Heartbeat:Connect(function()
        if not S.push then return end
        local hit = pushRemote()
        if not hit then return end
        forEnemiesInRange(S.pushRange, lastPush, S.pushCD, function(part)
            hit:FireServer("Hit", part)
        end, S.pushEnemyOnly)
    end))
end

-- ---- Auto Push range visualizer ----
do
    local viz = makeRangeViz()
    S._discDestroy = viz.destroy
    track(RunService.RenderStepped:Connect(function()
        viz.update(S.showRange, S.pushRange, S.rangeColor)
    end))
end

-- ============================================================
--  GUN SILENT AIM  -- the bullet system reports its own hits via
--  Remotes.Bullet.Hit:FireServer(Id, hitPart, pos, objCF, normal, t0, tFlight).
--  We hook that report and swap the hit target onto the chosen enemy, so any
--  shot landing on ANY surface is redirected onto them. Hook installed once.
-- ============================================================
do
    local function aimPartOf(char)
        return char:FindFirstChild(S.gunHitPart) or char:FindFirstChild("Head")
            or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
    end
    local function pickGunAim()
        local cam = workspace.CurrentCamera
        local origin = cam.CFrame.Position
        local mouse = UIS:GetMouseLocation()
        local doTeam = S.gunTeamCheck and multiTeam()
        -- wall check: raycast camera->target excluding all characters; any hit = blocked
        local rp
        if S.gunWallCheck then
            local ignore = { LocalPlayer.Character }
            for _, p in ipairs(Players:GetPlayers()) do if p.Character then ignore[#ignore + 1] = p.Character end end
            rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = ignore
        end
        local function visible(part)
            if not rp then return true end
            return workspace:Raycast(origin, part.Position - origin, rp) == nil
        end
        local best, bestScore
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character
               and not (doTeam and p.Team and LocalPlayer.Team and p.Team == LocalPlayer.Team) then
                local hum  = p.Character:FindFirstChildOfClass("Humanoid")
                local part = aimPartOf(p.Character)
                if hum and hum.Health > 0 and part then
                    local pass = S.gunMagic
                    if not pass then
                        local sp, on = cam:WorldToViewportPoint(part.Position)
                        if on and (mouse - Vector2.new(sp.X, sp.Y)).Magnitude <= S.gunFov then pass = true end
                    end
                    if pass and visible(part) then
                        local score
                        if S.gunPriority == "Lowest HP" then score = hum.Health
                        elseif S.gunPriority == "Closest" then score = (part.Position - origin).Magnitude
                        else
                            local sp = cam:WorldToViewportPoint(part.Position)
                            score = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
                        end
                        if not bestScore or score < bestScore then bestScore = score; best = part end
                    end
                end
            end
        end
        return best
    end
    -- FOV ring
    local fovGui = Instance.new("ScreenGui")
    fovGui.Name = "\0"; fovGui.ResetOnSpawn = false
    fovGui.IgnoreGuiInset = true   -- align with GetMouseLocation (no topbar offset)
    if not pcall(function() fovGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) or not fovGui.Parent then
        fovGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    local ring = Instance.new("Frame")
    ring.AnchorPoint = Vector2.new(0.5, 0.5); ring.BackgroundTransparency = 1
    ring.BorderSizePixel = 0; ring.Visible = false; ring.Parent = fovGui
    Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
    local stroke = Instance.new("UIStroke", ring); stroke.Thickness = 1.5; stroke.Transparency = 0.3
    S._gunFovDestroy = function() pcall(function() fovGui:Destroy() end) end

    -- pick target + refresh the hit-remote ref each frame (the hook reads these caches;
    -- it must do NO instance namecalls of its own, so we stage everything here)
    track(RunService.RenderStepped:Connect(function()
        local rem = ReplicatedStorage:FindFirstChild("Remotes")
        local b = rem and rem:FindFirstChild("Bullet")
        if gv() then gv()._CMG_HitRemote = b and b:FindFirstChild("Hit") end
        if S.gunSilent then
            local part = pickGunAim()
            S.gunTarget = part
            S.gunTargetPos = part and part.Position or nil
            S.gunTargetCF  = part and part.CFrame or nil
        else
            S.gunTarget = nil
        end
        if S.gunSilent and S.gunShowFov then
            local m = UIS:GetMouseLocation()
            ring.Position = UDim2.fromOffset(m.X, m.Y)
            ring.Size = UDim2.fromOffset(S.gunFov * 2, S.gunFov * 2)
            stroke.Color = S.gunFovColor
            ring.Visible = true
        else
            ring.Visible = false
        end
    end))

    -- A metamethod hook can't be reinstalled in-session, so we install a thin dispatcher
    -- ONCE and keep the real logic in gv()._CMG_gunHookFn, reassigned on every load -- that
    -- way hook fixes actually take effect on re-exec instead of being shadowed by a stale
    -- closure. The logic fn does NO instance namecalls (self is always an Instance here;
    -- .Name is a property read; CFrame math is on a separate metatable).
    local gnm = getnamecallmethod
    if gv() and not gv()._CMG_GUNDISPATCH and hookmetamethod and gnm then
        gv()._CMG_GUNDISPATCH = true
        local old
        old = hookmetamethod(game, "__namecall", function(self, ...)
            local fn = gv() and gv()._CMG_gunHookFn
            if fn then
                local na = fn(self, gnm(), ...)        -- returns packed override args, or nil
                if na then return old(self, table.unpack(na, 1, na.n)) end
            end
            return old(self, ...)
        end)
    end
    if gv() then
        gv()._CMG_gunPending = gv()._CMG_gunPending or {}
        gv()._CMG_gunPendN = gv()._CMG_gunPendN or 0
        gv()._CMG_diag = gv()._CMG_diag or {}     -- live diagnostics (invisible)
        -- The client sends the bullet Id + origin + direction in Fire:FireServer, so the
        -- server validates Hit against that ray. Redirect the FIRE direction onto the target
        -- AND the matching Hit (keyed by Id) onto them, so the reported hit lies on the
        -- server's known trajectory. Bullet speed is derived from the shot's own pos/tFlight.
        gv()._CMG_gunHookFn = function(self, method, ...)
            local st = gv()._CMG_S
            if not (st and st.gunSilent and method == "FireServer") then return nil end
            local a = table.pack(...)
            local pend, diag = gv()._CMG_gunPending, gv()._CMG_diag
            local function bump(k) if diag then diag[k] = (diag[k] or 0) + 1 end end
            -- Fire:(origin V3, dir V3, Id string, t num) -> aim the bullet at the target
            if self.Name == "Fire" then
                if typeof(a[1]) == "Vector3" and typeof(a[2]) == "Vector3" and typeof(a[3]) == "string" then
                    bump("fireSeen")
                    local tgt, tpos, tcf = st.gunTarget, st.gunTargetPos, st.gunTargetCF
                    if tgt and tpos then
                        local origin = a[1]
                        local d = tpos - origin
                        a[2] = (d.Magnitude > 0 and d.Unit) or a[2]
                        if gv()._CMG_gunPendN > 64 then table.clear(pend); gv()._CMG_gunPendN = 0 end
                        pend[a[3]] = { part = tgt, pos = tpos, partCF = tcf, origin = origin }
                        gv()._CMG_gunPendN = gv()._CMG_gunPendN + 1
                        bump("fireRedir"); if diag then diag.lastTarget = tgt.Name end
                        return a
                    else
                        bump("fireNoTarget")
                    end
                else
                    bump("fireSigMismatch")
                end
            -- Hit:(Id string, part, pos V3, objCF CFrame, normal, t0, tFlight) -> land it on them
            elseif typeof(a[1]) == "string" then
                bump("hitSeen")
                if pend[a[1]] then
                    local pe = pend[a[1]]; pend[a[1]] = nil; gv()._CMG_gunPendN = gv()._CMG_gunPendN - 1
                    local origPos, origT = a[3], a[7]
                    a[2] = pe.part
                    a[3] = pe.pos
                    if pe.partCF then a[4] = pe.partCF:ToObjectSpace(CFrame.new(pe.pos)) end
                    if typeof(origPos) == "Vector3" and typeof(origT) == "number" and origT > 0 then
                        local speed = (origPos - pe.origin).Magnitude / origT
                        if speed > 0 then a[7] = (pe.pos - pe.origin).Magnitude / speed end
                    end
                    bump("hitRedir")
                    return a
                else
                    bump("hitNoPend")
                end
            end
            return nil
        end
    end
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
        local doTeam = S.swordEnemyOnly and multiTeam()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character
               and not (doTeam and p.Team and LocalPlayer.Team and p.Team == LocalPlayer.Team) then
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
        end, S.swordEnemyOnly)
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
            end, S.swordEnemyOnly)
        end
    end))
end

-- ---- Sword Aura range visualizer ----
do
    local viz = makeRangeViz()
    S._swordDiscDestroy = viz.destroy
    track(RunService.RenderStepped:Connect(function()
        viz.update(S.swordShowRange, S.swordRange, S.swordRangeColor)
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
    Sec:Slider({ Name = "Cooldown", Flag = "CMG_PushCD", Min = 0, Max = 1000, Default = 350, Decimals = 0, Suffix = " ms",
        Callback = function(v) S.pushCD = v / 1000 end })
    Sec:Label({ Name = "Toggle key" }):Keybind({ Name = "AutoPush", Flag = "CMG_PushKey", Mode = "Toggle",
        Callback = function(state) pushTog:Set(state and true or false) end })
    Sec:Toggle({ Name = "Show range", Flag = "CMG_PushViz", Default = false,
        Callback = function(v) S.showRange = v end })
    Sec:Label({ Name = "Range color" }):Colorpicker({ Flag = "CMG_PushVizColor", Default = Color3.fromRGB(255, 80, 80),
        Callback = function(c) S.rangeColor = c end })
    Sec:Toggle({ Name = "Auto-equip Hit tool", Flag = "CMG_PushEquip", Default = false,
        Callback = function(v) S.pushEquip = v end })
    Sec:Toggle({ Name = "Enemies only (team)", Flag = "CMG_PushEnemyOnly", Default = false,
        Callback = function(v) S.pushEnemyOnly = v end })

    local Sec4 = Combat:Section({ Name = "Gun Silent Aim", Side = 2 })
    local gunTog = Sec4:Toggle({ Name = "Silent aim", Flag = "CMG_GunSilent", Default = false,
        Callback = function(v) S.gunSilent = v end })
    Sec4:Label({ Name = "Toggle key" }):Keybind({ Name = "GunSilent", Flag = "CMG_GunKey", Mode = "Toggle",
        Callback = function(state) gunTog:Set(state and true or false) end })
    Sec4:Slider({ Name = "FOV", Flag = "CMG_GunFov", Min = 20, Max = 1000, Default = 200, Decimals = 0, Suffix = " px",
        Callback = function(v) S.gunFov = v end })
    Sec4:Dropdown({ Name = "Hit part", Flag = "CMG_GunHitPart", Default = "Head", Multi = false,
        Items = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
        Callback = function(v) S.gunHitPart = (type(v) == "table" and v[1]) or v or "Head" end })
    Sec4:Dropdown({ Name = "Priority", Flag = "CMG_GunPriority", Default = "Crosshair", Multi = false,
        Items = { "Crosshair", "Closest", "Lowest HP" },
        Callback = function(v) S.gunPriority = (type(v) == "table" and v[1]) or v or "Crosshair" end })
    Sec4:Toggle({ Name = "Magic (ignore FOV)", Flag = "CMG_GunMagic", Default = false,
        Callback = function(v) S.gunMagic = v end })
    Sec4:Toggle({ Name = "Team check", Flag = "CMG_GunTeam", Default = false,
        Callback = function(v) S.gunTeamCheck = v end })
    Sec4:Toggle({ Name = "Wall check (no wallbang)", Flag = "CMG_GunWallCheck", Default = true,
        Callback = function(v) S.gunWallCheck = v end })
    Sec4:Toggle({ Name = "Show FOV", Flag = "CMG_GunShowFov", Default = true,
        Callback = function(v) S.gunShowFov = v end })
    Sec4:Label({ Name = "FOV color" }):Colorpicker({ Flag = "CMG_GunFovColor", Default = Color3.fromRGB(255, 255, 255),
        Callback = function(c) S.gunFovColor = c end })

    local Sec3 = Combat:Section({ Name = "Sword Aura", Side = 1 })
    Sec3:Label({ Name = "ClassicSword -- experimental" })
    local swordTog = Sec3:Toggle({ Name = "Enabled", Flag = "CMG_Sword", Default = false,
        Callback = function(v) S.sword = v end })
    Sec3:Slider({ Name = "Range", Flag = "CMG_SwordRange", Min = 5, Max = 30, Default = 14, Decimals = 0, Suffix = " studs",
        Callback = function(v) S.swordRange = v end })
    Sec3:Toggle({ Name = "Lunge (super) damage", Flag = "CMG_SwordLunge", Default = true,
        Callback = function(v) S.swordLunge = v end })
    Sec3:Slider({ Name = "Lunge cooldown", Flag = "CMG_SwordLungeCD", Min = 0, Max = 1500, Default = 600, Decimals = 0, Suffix = " ms",
        Callback = function(v) S.swordLungeCD = v / 1000 end })
    Sec3:Toggle({ Name = "Enemies only (team)", Flag = "CMG_SwordEnemyOnly", Default = false,
        Callback = function(v) S.swordEnemyOnly = v end })
    Sec3:Toggle({ Name = "Show range", Flag = "CMG_SwordViz", Default = false,
        Callback = function(v) S.swordShowRange = v end })
    Sec3:Label({ Name = "Range color" }):Colorpicker({ Flag = "CMG_SwordVizColor", Default = Color3.fromRGB(120, 170, 255),
        Callback = function(c) S.swordRangeColor = c end })
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
    S.push, S.sword, S.showRange, S.swordShowRange, S.gunSilent = false, false, false, false, false
    if S._discDestroy then pcall(S._discDestroy) end
    if S._swordDiscDestroy then pcall(S._swordDiscDestroy) end
    if S._gunFovDestroy then pcall(S._gunFovDestroy) end
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
