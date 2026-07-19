-- ============================================================
--  games/124848751642883.lua  --  MVS Duels (Murderers VS Sheriffs)
--
--  The gun is client-authoritative: the weapon's LocalScript raycasts locally
--  and, on hitting an enemy, fires ReplicatedStorage.Packages.Net["RE/GunKill"]
--  with a hardcoded key + the chosen target. The server trusts the target, so
--  firing that remote at any valid enemy is an instant kill -- no aim needed.
--
--  Enemy = same "Game" player-attribute (match id), different "Team" attribute,
--  alive, with a HumanoidRootPart.
--
--  Builds an "MVS Duels" page on the shared Window: Kill Aura / Silent Aim /
--  Kill All, plus targeting options. Publishes the active target to
--  getgenv().WH.currentTarget so the hub's Target Indicator can render it.
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = workspace
local LocalPlayer       = Players.LocalPlayer

-- Every persistent connection is tracked so the module tears down on re-exec.
local Connections = {}
local function track(c) Connections[#Connections + 1] = c; return c end

-- ---------- config ----------
-- Key is baked plaintext into the gun's client. DefaultGun confirmed; other
-- guns may use a different key (kills silently no-op if the server rejects it).
local GUN_KILL_KEY = "9576996e-66e6-4d56-b791-f3b062eb597c"
local GUN_NAMES    = { "DefaultGun", "AssaultGun" }

local State = {
    KillAura   = false,
    SilentAim  = false,
    RequireGun = true,
    TargetMode = "Crosshair",
    AuraDelay  = 0.15,
    FOV        = 250,
}

-- ---------- remote (guarded) ----------
local GunKill
do
    local pkg = ReplicatedStorage:FindFirstChild("Packages")
    local net = pkg and pkg:FindFirstChild("Net")
    GunKill = net and net:FindFirstChild("RE/GunKill")
end

-- ---------- helpers ----------
local function getGun()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, name in ipairs(GUN_NAMES) do
        local tool = char:FindFirstChild(name)
        if tool and tool:IsA("Tool") then return tool end
    end
    return nil
end

local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if not char:FindFirstChild("HumanoidRootPart") then return false end
    if plr:GetAttribute("Game") ~= LocalPlayer:GetAttribute("Game") then return false end
    if plr:GetAttribute("Team") == LocalPlayer:GetAttribute("Team") then return false end
    return true
end

local function getEnemies()
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) then list[#list + 1] = plr end
    end
    return list
end

local function nearestToCrosshair()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local best, bestDist
    for _, plr in ipairs(getEnemies()) do
        local hrp = plr.Character.HumanoidRootPart
        local screen, onScreen = camera:WorldToViewportPoint(hrp.Position)
        if onScreen and screen.Z > 0 then
            local dist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
            if dist <= State.FOV and (not bestDist or dist < bestDist) then
                best, bestDist = plr, dist
            end
        end
    end
    return best
end

local function nearestToChar()
    local char = LocalPlayer.Character
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not myHrp then return nil end
    local best, bestDist
    for _, plr in ipairs(getEnemies()) do
        local dist = (plr.Character.HumanoidRootPart.Position - myHrp.Position).Magnitude
        if not bestDist or dist < bestDist then
            best, bestDist = plr, dist
        end
    end
    return best
end

local function pickTarget()
    if State.TargetMode == "Crosshair" then
        return nearestToCrosshair()
    end
    return nearestToChar()
end

-- Publish the current target for the hub's shared Target Indicator overlay.
local function publishTarget(plr)
    local g = getgenv and getgenv()
    if g and g.WH then
        g.WH.currentTarget  = plr or nil
        g.WH.currentTargetT = os.clock()
    end
end

local function fireKill(target)
    if not GunKill or not target or not isEnemy(target) then return end
    local char = LocalPlayer.Character
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not myHrp then return end
    local origin = myHrp.Position
    local hitPos = target.Character.HumanoidRootPart.Position
    local look = CFrame.lookAt(origin, hitPos).LookVector
    GunKill:FireServer(GUN_KILL_KEY, target, look, origin, hitPos)
    publishTarget(target)
end

local function killAll()
    for _, plr in ipairs(getEnemies()) do
        fireKill(plr)
    end
end

-- ---------- feature loops ----------
local lastFire = 0
track(RunService.Heartbeat:Connect(function()
    if not State.KillAura then return end
    if State.RequireGun and not getGun() then return end
    if os.clock() - lastFire < State.AuraDelay then return end
    local target = pickTarget()
    if target then
        fireKill(target)
        lastFire = os.clock()
    end
end))

track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not State.SilentAim then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if State.RequireGun and not getGun() then return end
    local target = pickTarget()
    if target then fireKill(target) end
end))

-- ---------- UI ----------
local Page = Window:Page({ Name = "MVS Duels" })
local Sub  = Page:SubPage({ Name = "Combat" })

local Sec = Sub:Section({ Name = "Kill", Side = 1 })
local auraToggle = Sec:Toggle({
    Name = "Kill Aura", Flag = "MVSKillAura", Default = false,
    Callback = function(v) State.KillAura = v end,
})
Sec:Label({ Name = "Kill Aura key" }):Keybind({
    Name = "Kill Aura", Flag = "MVSKillAuraKey", Mode = "Toggle", Default = Enum.KeyCode.K,
    Callback = function(state) auraToggle:Set(state and true or false) end,
})
Sec:Toggle({
    Name = "Silent Aim (click)", Flag = "MVSSilentAim", Default = false,
    Callback = function(v) State.SilentAim = v end,
})
Sec:Button({ Name = "Kill All Now", Callback = killAll })

local Sec2 = Sub:Section({ Name = "Targeting", Side = 2 })
Sec2:Dropdown({
    Name = "Target mode", Flag = "MVSTargetMode", Default = "Crosshair", Multi = false,
    Items = { "Crosshair", "Nearest" },
    Callback = function(v) State.TargetMode = (type(v) == "table" and v[1]) or v or "Crosshair" end,
})
Sec2:Slider({
    Name = "Aura delay", Flag = "MVSAuraDelay", Min = 0, Max = 1000, Default = 150, Decimals = 0, Suffix = "ms",
    Callback = function(v) State.AuraDelay = v / 1000 end,
})
Sec2:Slider({
    Name = "Crosshair FOV", Flag = "MVSFov", Min = 50, Max = 800, Default = 250, Decimals = 0,
    Callback = function(v) State.FOV = v end,
})
Sec2:Toggle({
    Name = "Require gun equipped", Flag = "MVSRequireGun", Default = true,
    Callback = function(v) State.RequireGun = v end,
})

if not GunKill then
    Sec:Label({ Name = "! RE/GunKill missing -- kills disabled" })
    pcall(function() Library:Notification("MVS: GunKill remote not found", 5, Library.Theme["Accent"]) end)
end

-- ---------- teardown ----------
do
    local function full()
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    end
    local g = getgenv and getgenv()
    if g and g.WH then
        local prev = g.WH.disableAll
        g.WH.disableAll = function() pcall(full); if prev then pcall(prev) end end
        Library.OnExit = g.WH.disableAll
    else
        Library.OnExit = full
    end
end
