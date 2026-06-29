-- ============================================================
--  games/103839367350287.lua  --  Zee  (Da Hood-style combat RP)
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
}
local locked = {}   -- [player] = true

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
    if bestPart then lastShot = tick(); fireAt(gun, bestPart) end
end))

-- ---- No Slowdown ----
do
    local nsConns = {}
    local function clearNS() for _, c in ipairs(nsConns) do pcall(function() c:Disconnect() end) end; nsConns = {} end
    local function setupNS()
        clearNS()
        if not S.noSlowdown then return end
        local be = myChar() and myChar():FindFirstChild("BodyEffects"); if not be then return end
        local mv = be:FindFirstChild("Movement")
        if mv then
            for _, c in ipairs(mv:GetChildren()) do pcall(function() c:Destroy() end) end
            nsConns[#nsConns + 1] = mv.ChildAdded:Connect(function(ch) pcall(function() ch:Destroy() end) end)
        end
        local rl = be:FindFirstChild("Reload")
        if rl then
            if rl.Value == true then pcall(function() rl.Value = false end) end
            nsConns[#nsConns + 1] = rl:GetPropertyChangedSignal("Value"):Connect(function()
                if rl.Value == true then pcall(function() rl.Value = false end) end
            end)
        end
    end
    S._setupNS = setupNS
    S._clearNS = clearNS
    track(LP.CharacterAdded:Connect(function() if S.noSlowdown then task.wait(0.6); setupNS() end end))
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
    if S._clearVis then pcall(S._clearVis) end
    if S._clearNS then pcall(S._clearNS) end
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
