-- ============================================================
--  games/90184287580174.lua  --  KILLSTREAK  (Legionary Studio)
--
--  Client-authoritative FPS (early MVP, PlaceVersion ~98). Decoded live
--  2026-07-11. The client raycasts its own hits and hands the server the
--  victim's real BasePart via two C2S remotes under ReplicatedStorage.
--  NetworkObjects (fired raw, NO header wrapper):
--    Network_C2S_Reliable_Weapon:Damage
--        (shotSeq, equipSeq, weaponId, serverTimeMs, hits)
--        each hit = { victimPart, hitPos, origin, nil, penetration, shotId, info }
--        -> server derives victim=part.Parent, bodypart=part.Name (headshot),
--           and the DAMAGE NUMBER from weaponId + part. Client never sends damage.
--    Network_C2S_Reliable_Weapon:Attack
--        (shotSeq, equipSeq, weaponId, serverTimeMs, { {hitPos,normal,tag,userId} })
--    (Damage fires first, then Attack, per shot.)
--
--  shotSeq/equipSeq are game-maintained counters that only advance through the
--  real fire path (getAuthorityMetadata does NOT mint a fresh one). So we do NOT
--  craft shots from scratch (that replays a stale seq -> rejected). Instead we
--  RIDE the game's own fires via a __namecall hook and rewrite WHO got hit:
--    * Damage fire  -> rewrite victim part to the best target's head (silent aim,
--                      wallbang, forced headshot); optional stacked entries for
--                      burst damage (one-shot -- server de-dup unknown, test).
--    * Attack fire  -> if the game did NOT fire a Damage for this shot (missed /
--                      shot a wall), INJECT a Damage at the target using this
--                      shot's header. That is what makes wallbang / hit-anywhere
--                      work. Also rewrite the Attack summary to match.
--
--  OP-gun knobs are all live client fields on the weapon object (found via getgc
--  -> WeaponClient.CurrentWeapon): Ammo/MagSize, RPM/RPMMultiplier, Inaccuracy*
--  (spread), AttackShakeProfile (recoil), NoReload, MeleeRange (melee reach).
--  The server tracks ammo (S2C Weapon:AmmoCorrection) so infinite ammo may be
--  corrected -- live-test.
--
--  MUST LIVE-TEST (server scripts unreadable): stacked-entry one-shot de-dup,
--  server LoS/range re-check (wallbang), ammo correction aggressiveness, rapid-
--  fire throttle ceiling, Attack/Damage consistency cross-check.
--
--  Loads the universal shell (ESP + Player movement) after its page.
-- ============================================================
local ctx     = ({ ... })[1]
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

-- generation guard: a re-exec bumps the token so any loop / hook left from a
-- prior instance goes inert instead of double-firing.
local MYGEN = ((gv() and gv()._WH_KS_gen) or 0) + 1
if gv() then gv()._WH_KS_gen = MYGEN end
local function current() local g = gv(); return (g == nil) or g._WH_KS_gen == MYGEN end

-- ---- executor capability gate ----
local HAS_HOOK = (hookmetamethod ~= nil) and (getnamecallmethod ~= nil) and (getgc ~= nil)

-- ============================================================
--  STATE
-- ============================================================
local KS = {
    -- silent aim
    silent = false, mode = "FOV", fov = 120, hitPart = "Head",
    wallbang = true, teamCheck = false, maxDist = 1000, stack = 1,
    visualizeFov = true,
    -- triggerbot
    trigger = false, triggerHold = true, triggerActive = false,
    -- op gun
    infAmmo = false, rapid = false, rpmMult = 3, noSpread = false, noRecoil = false, instaReload = false,
    -- melee
    meleeReach = false, meleeRange = 40,
}

-- ============================================================
--  REMOTES + WEAPON HANDLE
-- ============================================================
local NO = ReplicatedStorage:FindFirstChild("NetworkObjects")
local DmgRemote = NO and NO:FindFirstChild("Network_C2S_Reliable_Weapon:Damage")
local AtkRemote = NO and NO:FindFirstChild("Network_C2S_Reliable_Weapon:Attack")

-- WeaponClient lives in the game's require env; find it in the GC by its stable
-- methods (independent of whether a weapon is currently equipped). Cached, with
-- a cheap re-find when the cached handle goes stale (rejoin / reload of chunk).
local _wc = nil
local function weaponClient()
    if _wc and rawget(_wc, "getAuthorityMetadata") then return _wc end
    _wc = nil
    if not getgc then return nil end
    for _, o in ipairs(getgc(true)) do
        if type(o) == "table" and rawget(o, "getAuthorityMetadata") ~= nil
           and (rawget(o, "sendReloadStart") ~= nil or rawget(o, "setRPMMultiplier") ~= nil) then
            _wc = o; break
        end
    end
    return _wc
end
local function curWeapon()
    local wc = weaponClient()
    return wc and rawget(wc, "CurrentWeapon") or nil
end

-- ============================================================
--  TARGETING
-- ============================================================
local function myChar() return LocalPlayer.Character end
local function myHead()
    local c = myChar()
    return c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
end
local function enemyOk(plr)
    if plr == LocalPlayer then return false end
    if KS.teamCheck and plr.Team ~= nil and LocalPlayer.Team ~= nil and plr.Team == LocalPlayer.Team then
        return false
    end
    return true
end
-- pick the aim part on a target character (Head for the headshot multiplier)
local function aimPart(char)
    return char:FindFirstChild(KS.hitPart) or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
end
-- best enemy: FOV (closest to crosshair) or closest-to-me, alive, in range, team-checked
local function bestTarget()
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local origin = cam.CFrame.Position
    local mouse = UserInputService:GetMouseLocation()
    local myPos = (myHead() and myHead().Position) or origin
    local best, bestScore, bestPart
    for _, plr in ipairs(Players:GetPlayers()) do
        if enemyOk(plr) then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local part = char and hum and hum.Health > 0 and aimPart(char)
            if part then
                local d = (part.Position - myPos).Magnitude
                if d <= KS.maxDist then
                    local score
                    if KS.mode == "Closest" then
                        score = d
                    else   -- FOV: screen distance from crosshair, gated by the FOV circle
                        local sp, on = cam:WorldToViewportPoint(part.Position)
                        if not on then score = nil
                        else
                            local sd = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                            score = (sd <= KS.fov) and sd or nil
                        end
                    end
                    if score and (not bestScore or score < bestScore) then
                        best, bestScore, bestPart = char, score, part
                    end
                end
            end
        end
    end
    if best then return best, bestPart, Players:GetPlayerFromCharacter(best) end
    return nil
end

-- ---- FOV visualizer (shared Library.FOV) ----
local fovHandle = Library.FOV and Library.FOV:New()
track(RunService.RenderStepped:Connect(function()
    if not current() or unloaded then return end
    if fovHandle then
        local show = KS.silent and KS.visualizeFov and KS.mode == "FOV"
        fovHandle:Set(KS.fov, show, UserInputService:GetMouseLocation())
    end
end))

-- ============================================================
--  SILENT AIM  (ride the game's fires; rewrite the victim)
--   Damage: rewrite hit entries to the target head (through walls).
--   Attack: if no Damage fired for this shot, inject one at the target.
-- ============================================================
local function craftHit(part, origin)
    -- hit entry shape decoded from Weapon:handleHit: index [6] is the shotId,
    -- [7] the attacker-aim info. Keep it self-consistent.
    local sid = tostring(LocalPlayer.UserId) .. "_" .. tostring(math.floor(os.clock() * 1000)) .. "_1"
    return { part, part.Position, origin, nil, 0, sid, { AttackerWasAiming = true } }
end
local function craftDamageHits(part, origin)
    local hits = {}
    for i = 1, math.max(1, KS.stack) do hits[i] = craftHit(part, origin) end
    return hits
end

-- per-shot state so the Attack hook knows whether Damage already handled the shot
local shotState = { seq = nil, damaged = false }

if HAS_HOOK and DmgRemote and AtkRemote then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local ok, method = pcall(getnamecallmethod)
        if ok and method == "FireServer" and current() and not unloaded and KS.silent
           and not KS._inject and not (checkcaller and checkcaller()) then
            local cam = Workspace.CurrentCamera
            local origin = cam and cam.CFrame.Position or Vector3.zero

            if self == DmgRemote then
                local args = { ... }
                local char, part = bestTarget()
                if part then
                    args[1] = args[1]; -- shotSeq (unchanged)
                    shotState.seq = args[1]; shotState.damaged = true
                    args[5] = craftDamageHits(part, origin)   -- rewrite hits -> target
                    return oldNamecall(self, table.unpack(args, 1, 5))
                end

            elseif self == AtkRemote then
                local args = { ... }
                local char, part, plr = bestTarget()
                if part then
                    -- rewrite the attack summary to match the (re)targeted victim
                    args[5] = { { part.Position, Vector3.yAxis, "Headshot", plr and plr.UserId or 0 } }
                    -- if the game did NOT already fire a Damage for this shot
                    -- (miss / wall), inject one now using this shot's header.
                    -- This is the wallbang / hit-anywhere path.
                    if KS.wallbang and shotState.seq ~= args[1] then
                        local shotSeq, equipSeq, weaponId, timeMs = args[1], args[2], args[3], args[4]
                        KS._inject = true   -- so this injected fire skips the hook body
                        pcall(function()
                            DmgRemote:FireServer(shotSeq, equipSeq, weaponId, timeMs,
                                craftDamageHits(part, origin))
                        end)
                        KS._inject = false
                    end
                    shotState.seq, shotState.damaged = nil, false
                    return oldNamecall(self, table.unpack(args, 1, 5))
                end
                shotState.seq, shotState.damaged = nil, false
            end
        end
        return oldNamecall(self, ...)
    end)
end

-- ============================================================
--  TRIGGERBOT  (auto-fire the game's own attack when a target is in FOV)
-- ============================================================
track(RunService.Heartbeat:Connect(function()
    if not current() or unloaded then return end
    if not (KS.silent and KS.trigger) then return end
    if KS.triggerHold and not KS.triggerActive then return end
    local char, part = bestTarget()
    if not part then return end
    local w = curWeapon()
    -- weapon:attack() runs the game's full fire (advances seq, fires Attack +
    -- Damage) and self-throttles via its own SwingRate debounce; the namecall
    -- hook above redirects the hit to the target.
    if w then pcall(function() w:attack() end) end
end))

-- ============================================================
--  OP GUN  (live client-field pokes on the equipped weapon)
-- ============================================================
track(RunService.Heartbeat:Connect(function()
    if not current() or unloaded then return end
    local w = curWeapon()
    if not w then return end

    if KS.infAmmo then
        local mag = rawget(w, "MagSize")
        if mag and rawget(w, "Ammo") and rawget(w, "Ammo") < mag then
            pcall(function() if w.setAmmo then w:setAmmo(mag) else w.Ammo = mag end end)
        end
        pcall(function() w.NoReload = true end)
    end
    if KS.instaReload then
        pcall(function() w.ReloadMultiplier = 10 end)   -- ~instant
    end
    if KS.rapid then
        pcall(function() w.RPMMultiplier = KS.rpmMult end)
    elseif rawget(w, "RPMMultiplier") ~= 1 and not KS.rapid then
        -- leave user/game value alone unless we set it; only reset what we own
    end
    if KS.noSpread then
        pcall(function()
            if rawget(w, "InaccuracyRange") then w.InaccuracyRange = 0 end
            if rawget(w, "InaccuracyIncrement") then w.InaccuracyIncrement = 0 end
            if rawget(w, "Accuracy") ~= nil then w.Accuracy = 1 end
        end)
    end
    if KS.noRecoil then
        pcall(function() if rawget(w, "AttackShakeProfile") ~= nil then w.AttackShakeProfile = nil end end)
    end
    if KS.meleeReach and tostring(rawget(w, "AttackType")) == "Slash" then
        pcall(function() w.MeleeRange = KS.meleeRange end)
    end
end))

-- ============================================================
--  UI
-- ============================================================
local Page = Window:Page({ Name = "KILLSTREAK" })

do  -- Combat
    local Sub = Page:SubPage({ Name = "Combat" })
    local S1 = Sub:Section({ Name = "Silent Aim", Side = 1 })
    if not HAS_HOOK then
        S1:Label({ Name = "Silent aim needs a hook-capable executor." })
    end
    S1:Toggle({ Name = "Silent aim", Flag = "KS_Silent", Default = false,
        Callback = function(v) KS.silent = v end })
    S1:Dropdown({ Name = "Target mode", Flag = "KS_Mode", Default = "FOV", Multi = false,
        Items = { "FOV", "Closest" },
        Callback = function(v) KS.mode = (type(v) == "table" and v[1]) or v or "FOV" end })
    S1:Dropdown({ Name = "Hit part", Flag = "KS_HitPart", Default = "Head", Multi = false,
        Items = { "Head", "UpperTorso", "HumanoidRootPart" },
        Callback = function(v) KS.hitPart = (type(v) == "table" and v[1]) or v or "Head" end })
    S1:Slider({ Name = "FOV", Flag = "KS_Fov", Min = 20, Max = 600, Default = 120, Decimals = 0, Suffix = " px",
        Callback = function(v) KS.fov = v end })
    S1:Slider({ Name = "Max distance", Flag = "KS_MaxDist", Min = 50, Max = 2000, Default = 1000, Decimals = 0, Suffix = " studs",
        Callback = function(v) KS.maxDist = v end })
    S1:Slider({ Name = "Stack hits (one-shot)", Flag = "KS_Stack", Min = 1, Max = 8, Default = 1, Decimals = 0,
        Callback = function(v) KS.stack = v end })

    local S2 = Sub:Section({ Name = "Options", Side = 2 })
    S2:Toggle({ Name = "Wallbang (hit through walls)", Flag = "KS_Wallbang", Default = true,
        Callback = function(v) KS.wallbang = v end })
    S2:Toggle({ Name = "Team check", Flag = "KS_TeamCheck", Default = false,
        Callback = function(v) KS.teamCheck = v end })
    S2:Toggle({ Name = "Show FOV circle", Flag = "KS_FovViz", Default = true,
        Callback = function(v) KS.visualizeFov = v end })
    S2:Toggle({ Name = "Triggerbot (auto-fire)", Flag = "KS_Trigger", Default = false,
        Callback = function(v) KS.trigger = v end })
    S2:Toggle({ Name = "Trigger: hold key", Flag = "KS_TriggerHold", Default = true,
        Callback = function(v) KS.triggerHold = v end })
    S2:Label({ Name = "Trigger key" }):Keybind({ Name = "Trigger", Flag = "KS_TriggerKey", Mode = "Hold",
        Default = Enum.KeyCode.E,
        Callback = function(state) KS.triggerActive = state and true or false end })

    local S3 = Sub:Section({ Name = "Melee", Side = 1 })
    S3:Toggle({ Name = "Melee reach", Flag = "KS_MeleeReach", Default = false,
        Callback = function(v) KS.meleeReach = v end })
    S3:Slider({ Name = "Reach", Flag = "KS_MeleeRange", Min = 10, Max = 150, Default = 40, Decimals = 0, Suffix = " studs",
        Callback = function(v) KS.meleeRange = v end })
end

do  -- OP Gun
    local Sub = Page:SubPage({ Name = "OP Gun" })
    local S1 = Sub:Section({ Name = "Weapon", Side = 1 })
    S1:Toggle({ Name = "Infinite ammo", Flag = "KS_InfAmmo", Default = false,
        Callback = function(v) KS.infAmmo = v end })
    S1:Toggle({ Name = "Instant reload", Flag = "KS_InstaReload", Default = false,
        Callback = function(v) KS.instaReload = v end })
    S1:Toggle({ Name = "Rapid fire", Flag = "KS_Rapid", Default = false,
        Callback = function(v)
            KS.rapid = v
            if not v then local w = curWeapon(); if w then pcall(function() w.RPMMultiplier = 1 end) end end
        end })
    S1:Slider({ Name = "Fire-rate multiplier", Flag = "KS_RpmMult", Min = 1, Max = 10, Default = 3, Decimals = 0, Suffix = "x",
        Callback = function(v) KS.rpmMult = v end })

    local S2 = Sub:Section({ Name = "Accuracy", Side = 2 })
    S2:Toggle({ Name = "No spread", Flag = "KS_NoSpread", Default = false,
        Callback = function(v) KS.noSpread = v end })
    S2:Toggle({ Name = "No recoil", Flag = "KS_NoRecoil", Default = false,
        Callback = function(v) KS.noRecoil = v end })
    S2:Label({ Name = "Server tracks ammo -- if inf ammo gets corrected, it's server-side." })
end

-- ============================================================
--  UNLOAD
-- ============================================================
local function unload()
    if unloaded then return end
    unloaded = true
    -- restore any weapon field we own
    local w = curWeapon()
    if w then pcall(function() w.RPMMultiplier = 1 end) end
    if fovHandle then pcall(function() fovHandle:Destroy() end) end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    -- the __namecall hook stays installed but goes inert via `unloaded`/`current()`
end
if gv() then gv()._WH_KS_unload = unload end
-- also turn features off on the UI Unload button (Library:Exit calls OnExit); chain
-- so we don't clobber a hook set elsewhere.
do
    local prev = Library.OnExit
    Library.OnExit = function() pcall(unload); if prev then pcall(prev) end end
end

-- ============================================================
--  UNIVERSAL SHELL  (ESP + Player movement) after our page
-- ============================================================
pcall(function() ctx.load("games/universal.lua")(ctx) end)
