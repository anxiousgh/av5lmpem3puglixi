-- ============================================================
--  games/103839367350287.lua  --  Zee  (Da Hood-style combat RP)
--
--  Target-lock auto-shoot + target visualizer. Fires the gun's own shoot remote
--    GameRemotes.MainGameEvent:FireServer("ShootGun", Handle, origin, nil,
--        hitPos, hitPart, normal, Range, Damage)
--  at locked targets inside the gun's Range, paced by the gun's ShootingCooldown.
--
--  NO __namecall hook anywhere (the game kicks for "namecallInstance detector") --
--  only normal FireServer calls + GUI/Highlights. Combat is server-validated and the
--  game has active human mods, so this is VISIBLE -- burner only.
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
    auto = false, aura = false, hitPart = "Head", visibleOnly = true,
    fastFire = false, fastFireCD = 0.06,
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
local function partOf(c) return c:FindFirstChild(S.hitPart) or c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart") end
local function equippedGun()
    local char = myChar(); if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("Range") and t:FindFirstChild("Handle") then return t end
    end
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
local function visibleTo(muzzle, part)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { myChar(), part.Parent }
    return workspace:Raycast(muzzle, part.Position - muzzle, params) == nil
end
local function fireAt(gun, part)
    local handle = gun:FindFirstChild("Handle"); if not handle then return end
    local origin = (handle.CFrame * CFrame.new(-1, 0.4, 0)).Position
    local hitPos = part.Position
    MainGameEvent:FireServer("ShootGun", handle, origin, nil, hitPos, part, (origin - hitPos).Unit,
        gun.Range.Value, gun:FindFirstChild("Damage") and gun.Damage.Value or 0)
end
Players.PlayerRemoving:Connect(function(p) locked[p] = nil end)

-- ---- auto shoot ----
local lastShot = 0
track(RunService.Heartbeat:Connect(function()
    if not (S.auto) then return end
    local gun = equippedGun(); if not gun then return end
    if S.fastFire and gun:FindFirstChild("ShootingCooldown") then pcall(function() gun.ShootingCooldown.Value = S.fastFireCD end) end
    local cd = (gun:FindFirstChild("ShootingCooldown") and gun.ShootingCooldown.Value) or 0.2
    if tick() - lastShot < cd then return end
    if gun:FindFirstChild("Ammo") and gun.Ammo.Value < 1 then return end
    local mc = myChar(); local myHRP = mc and mc:FindFirstChild("HumanoidRootPart"); if not myHRP then return end
    local muzzle = (gun.Handle.CFrame * CFrame.new(-1, 0.4, 0)).Position
    local function consider(p)
        if p == LP then return end
        local c = aliveChar(p); local part = c and partOf(c); if not part then return end
        local dist = (part.Position - myHRP.Position).Magnitude
        if dist > gun.Range.Value then return end
        if S.visibleOnly and not visibleTo(muzzle, part) then return end
        return part, dist
    end
    local bestPart, bestD
    local pool = S.aura and Players:GetPlayers() or nil
    if pool then
        for _, p in ipairs(pool) do local part, dist = consider(p); if part and (not bestD or dist < bestD) then bestPart, bestD = part, dist end end
    else
        for p in pairs(locked) do local part, dist = consider(p); if part and (not bestD or dist < bestD) then bestPart, bestD = part, dist end end
    end
    if bestPart then lastShot = tick(); fireAt(gun, bestPart) end
end))

-- ---- target visualizer (outline + tracer on locked players) ----
do
    local gui, vis = nil, {}   -- vis[player] = { hl, line }
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
    -- expose a teardown for cleanup
    S._clearVis = function() for p in pairs(vis) do clear(p) end; if gui then pcall(function() gui:Destroy() end); gui = nil end end
end

-- ============================================================
--  UI
-- ============================================================
do
    local Sub = MainPage:SubPage({ Name = "Auto Shoot" })
    local Sec = Sub:Section({ Name = "Auto shoot", Side = 1 })
    local autoToggle = Sec:Toggle({ Name = "Auto shoot", Flag = "ZeeAuto", Default = false,
        Callback = function(v) S.auto = v end })
    Sec:Label({ Name = "Toggle key" }):Keybind({ Name = "Auto shoot", Flag = "ZeeAutoKey", Mode = "Toggle", Default = Enum.KeyCode.RightShift,
        Callback = function(state) autoToggle:Set(state and true or false) end })
    Sec:Toggle({ Name = "Aura (shoot anyone in range)", Flag = "ZeeAura", Default = false,
        Callback = function(v) S.aura = v end })
    Sec:Toggle({ Name = "Visible only", Flag = "ZeeVis", Default = true,
        Callback = function(v) S.visibleOnly = v end })
    Sec:Dropdown({ Name = "Hit part", Flag = "ZeeHitPart", Default = "Head", Multi = false,
        Items = { "Head", "Torso", "HumanoidRootPart" },
        Callback = function(v) S.hitPart = (type(v) == "table" and v[1]) or v or "Head" end })
    local Sec2 = Sub:Section({ Name = "Fire rate", Side = 2 })
    Sec2:Toggle({ Name = "Fast fire (override cooldown)", Flag = "ZeeFast", Default = false,
        Callback = function(v) S.fastFire = v end })
    Sec2:Slider({ Name = "Fast fire cooldown", Flag = "ZeeFastCD", Min = 0.02, Max = 0.5, Default = 0.06, Decimals = 2, Suffix = "s",
        Callback = function(v) S.fastFireCD = v end })

    local TSub = MainPage:SubPage({ Name = "Target" })
    local TSec = TSub:Section({ Name = "Targeting", Side = 1 })
    TSec:Label({ Name = "Target player (nearest mouse)" }):Keybind({ Name = "Target", Flag = "ZeeTargetKey", Mode = "Hold", Default = Enum.KeyCode.E,
        Callback = function(state) if state then local p = nearestMousePlayer(); if p then locked[p] = true end end end })
    TSec:Label({ Name = "Untarget player (nearest mouse)" }):Keybind({ Name = "Untarget", Flag = "ZeeUntargetKey", Mode = "Hold", Default = Enum.KeyCode.T,
        Callback = function(state) if state then local p = nearestMousePlayer(); if p then locked[p] = nil end end end })
    TSec:Button({ Name = "Clear all targets", Callback = function() for p in pairs(locked) do locked[p] = nil end end })
    local lockLbl = TSec:Label({ Name = "Locked: 0" })
    track(RunService.Heartbeat:Connect(function()
        local n = 0; for _ in pairs(locked) do n = n + 1 end
        pcall(function() lockLbl:SetText("Locked: " .. n) end)
    end))

    local VSec = TSub:Section({ Name = "Visualizer", Side = 2 })
    VSec:Toggle({ Name = "Outline", Flag = "ZeeOutline", Default = true,
        Callback = function(v) S.outline = v end })
    VSec:Label({ Name = "Outline color" }):Colorpicker({ Flag = "ZeeOutlineColor", Default = S.outlineColor,
        Callback = function(c) S.outlineColor = c end })
    VSec:Toggle({ Name = "Tracer", Flag = "ZeeTracer", Default = false,
        Callback = function(v) S.tracer = v end })
    VSec:Dropdown({ Name = "Tracer origin", Flag = "ZeeTracerOrigin", Default = "Bottom", Multi = false,
        Items = { "Bottom", "Top", "Mouse" },
        Callback = function(v) S.tracerOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    VSec:Label({ Name = "Tracer color" }):Colorpicker({ Flag = "ZeeTracerColor", Default = S.tracerColor,
        Callback = function(c) S.tracerColor = c end })
end

-- universal pages after Main
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- teardown
local function cleanup()
    S.auto = false
    if S._clearVis then pcall(S._clearVis) end
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
