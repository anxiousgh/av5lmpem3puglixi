-- ============================================================
--  games/138995385694035.lua  --  Hood Customs
--
--  "Main" tab first, then the universal base. Ports the HC-specific
--  features from witherhook (the universal aimbot/triggerbot/ESP/movement
--  already cover the rest):
--    * Auto stomp  -- MainEvent:FireServer("Stomp") while standing over a
--                     knocked (BodyEffects["K.O"]) player who isn't Dead yet
--    * Knife reach -- grow [Knife].Handle.HITBOX_PART (cap 13, above = anticheat)
--    * Auto reload -- press the reload key when Tool.Script.Ammo hits the threshold
-- ============================================================
local ctx = ({ ... })[1]

local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM               = game:GetService("VirtualInputManager")
local Workspace         = workspace
local LocalPlayer       = Players.LocalPlayer

-- "Main" must come before the universal pages so it's the first tab.
local MainPage = Window:Page({ Name = "Main" })

local unloaded = false
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

-- ============================================================
--  HC state detection (BodyEffects under workspace.Players.Characters.<name>)
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

local hc = {
    stomp = false, stompRadius = 5,
    knifeReach = false, knifeSize = 13,
    reload = false, reloadKey = Enum.KeyCode.R, reloadThreshold = 0,
}

-- ============================================================
--  Auto stomp -- finish knocked players you're standing over
-- ============================================================
local function getMainEvent() return ReplicatedStorage:FindFirstChild("MainEvent") end
local function someoneBelow()
    local lc = LocalPlayer.Character
    local lhrp = lc and lc:FindFirstChild("HumanoidRootPart")
    if not lhrp then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 and isKnocked(p) and not isDead(p) then
                local d = lhrp.Position - hrp.Position
                local horiz = Vector2.new(d.X, d.Z).Magnitude
                if horiz <= hc.stompRadius and d.Y <= 7 and d.Y >= -1 then return true end
            end
        end
    end
    return false
end
local stompLast = 0
track(RunService.Heartbeat:Connect(function()
    if not hc.stomp then return end
    if tick() - stompLast < 0.1 then return end
    local me = getMainEvent(); if not me then return end
    if not someoneBelow() then return end
    stompLast = tick()
    pcall(function() me:FireServer("Stomp") end)
end))

-- ============================================================
--  Knife reach -- grow the melee hitbox (HC caps usable size ~13)
-- ============================================================
local KNIFE_DEFAULT = Vector3.new(2.5, 1, 1)
local function getKnifeHitbox()
    local function find(p)
        local k = p and p:FindFirstChild("[Knife]")
        local h = k and k:FindFirstChild("Handle")
        return h and h:FindFirstChild("HITBOX_PART")
    end
    return find(LocalPlayer:FindFirstChildOfClass("Backpack")) or find(LocalPlayer.Character)
end
track(RunService.Heartbeat:Connect(function()
    if not hc.knifeReach then return end
    local hb = getKnifeHitbox(); if not hb then return end
    local target = Vector3.new(hc.knifeSize, hc.knifeSize, hc.knifeSize)
    if hb.Size ~= target then pcall(function() hb.Size = target end) end
    if hb.Transparency ~= 0.9999 then pcall(function() hb.Transparency = 0.9999 end) end
end))
local function restoreKnife()
    local hb = getKnifeHitbox()
    if hb then pcall(function() hb.Size = KNIFE_DEFAULT; hb.Transparency = 1 end) end
end

-- ============================================================
--  Auto reload -- reads Character.<Tool>.Script.Ammo, presses reload when low
-- ============================================================
local function getAmmo()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local script = tool and tool:FindFirstChild("Script")
    local ammo = script and script:FindFirstChild("Ammo")
    if ammo and (ammo:IsA("IntValue") or ammo:IsA("NumberValue")) then return ammo end
    return nil
end
local reloadLast = 0
track(RunService.Heartbeat:Connect(function()
    if not hc.reload then return end
    if tick() - reloadLast < 1.5 then return end
    local ammo = getAmmo(); if not ammo then return end
    if ammo.Value > hc.reloadThreshold then return end
    reloadLast = tick()
    pcall(function()
        VIM:SendKeyEvent(true, hc.reloadKey, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, hc.reloadKey, false, game)
    end)
end))

-- ============================================================
--  UI  (Main tab)
-- ============================================================
local Sub = MainPage:SubPage({ Name = "Hood Customs" })

local CombatSec = Sub:Section({ Name = "Combat", Side = 1 })
CombatSec:Toggle({ Name = "Auto stomp", Flag = "HC_Stomp", Default = false,
    Callback = function(v) hc.stomp = v end })
CombatSec:Slider({ Name = "Stomp radius", Flag = "HC_StompRadius", Min = 1, Max = 30, Default = 5, Decimals = 0,
    Callback = function(v) hc.stompRadius = v end })
CombatSec:Toggle({ Name = "Knife reach", Flag = "HC_KnifeReach", Default = false,
    Callback = function(v) hc.knifeReach = v; if not v then restoreKnife() end end })
CombatSec:Slider({ Name = "Knife reach size", Flag = "HC_KnifeSize", Min = 1, Max = 13, Default = 13, Decimals = 0, Suffix = " studs",
    Callback = function(v) hc.knifeSize = v end })

local UtilSec = Sub:Section({ Name = "Utility", Side = 2 })
UtilSec:Toggle({ Name = "Auto reload (low ammo)", Flag = "HC_Reload", Default = false,
    Callback = function(v) hc.reload = v end })
UtilSec:Slider({ Name = "Reload at ammo <=", Flag = "HC_ReloadThreshold", Min = 0, Max = 30, Default = 0, Decimals = 0,
    Callback = function(v) hc.reloadThreshold = v end })

-- ============================================================
--  Universal base AFTER Main, so Main stays the first tab.
-- ============================================================
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown: stop loops + restore the knife hitbox. Wrap the
--  universal-registered disableAll/OnExit.
-- ============================================================
local function hcCleanup()
    unloaded = true
    hc.stomp, hc.knifeReach, hc.reload = false, false, false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(restoreKnife)
end
do
    local g = getgenv and getgenv()
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
