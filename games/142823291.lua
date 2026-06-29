-- ============================================================
--  games/142823291.lua  --  Murder Mystery 2 (MM2)
--
--  Adds a "Main" tab FIRST (so it's the leading tab), then loads the
--  universal base (Combat/Player/Visuals/etc. come after Main).
--
--  Identity: a Tool named "Gun" -> Sheriff, "Knife" -> Murderer
--  (checked in the Character AND the Backpack).
--    * Sheriff shoot : Gun.Shoot:FireServer(originCF, targetCF)  -- origin FIRST
--      (origin = our real GunRaycastAttachment; target = murderer's head)
--    * Murderer knife: Knife.Events.KnifeStabbed:FireServer() (swing) then
--                      Knife.Events.HandleTouched:FireServer(victimPart) per kill
--    * Gun pickup    : briefly teleport HRP onto a "GunDrop" BasePart
-- ============================================================
local ctx = ({ ... })[1]

local Library = ctx.Library
local Window  = ctx.Window

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local Workspace   = workspace
local LocalPlayer = Players.LocalPlayer

local hasDrawing = (Drawing ~= nil and Drawing.new ~= nil)

-- "Main" must be created before the universal pages so it's the first tab.
local MainPage = Window:Page({ Name = "Main" })

-- ---- teardown bookkeeping (wrapped into the hub's disableAll at the bottom) ----
local unloaded = false
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

-- ============================================================
--  Identity (Gun -> Sheriff, Knife -> Murderer)
-- ============================================================
local IDENTITY = { Gun = "Sheriff", Knife = "Murderer" }
local COLORS = {
    Sheriff  = Color3.fromRGB(80, 160, 255),
    Murderer = Color3.fromRGB(255, 80, 80),
}
local function getIdentity(plr)
    if not plr then return nil end
    local function scan(parent)
        if not parent then return nil end
        for _, t in ipairs(parent:GetChildren()) do
            if t:IsA("Tool") and IDENTITY[t.Name] then return IDENTITY[t.Name] end
        end
        return nil
    end
    return scan(plr.Character) or scan(plr:FindFirstChild("Backpack"))
end

-- ============================================================
--  Sheriff -- shoot the murderer
--  The Gun's "Shoot" remote works whether the Gun is equipped
--  (in Character) or just held in the Backpack.
-- ============================================================
local function findGunShoot()
    local function pull(parent)
        local gun = parent and parent:FindFirstChild("Gun")
        return gun and gun:FindFirstChild("Shoot")
    end
    return pull(LocalPlayer.Character) or pull(LocalPlayer:FindFirstChild("Backpack"))
end

-- hit part: Head first (head shots register the same), then HRP / torso, then any
-- BasePart so a shot always fires even on weird rigs.
local function targetHitPart(char)
    if not char then return nil end
    return char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        or char:FindFirstChildWhichIsA("BasePart")
end
local function targetHitCF(char)
    local p = targetHitPart(char)
    return p and p.CFrame or nil
end

local function findMurderer()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and getIdentity(plr) == "Murderer" then return plr end
    end
    return nil
end

local SHOOT_ERR = {
    no_gun      = "You don't have the Gun -- only the Sheriff can shoot.",
    no_murderer = "No player is holding the Knife right now.",
    no_victim   = "The murderer's character isn't loaded.",
    no_my_hrp   = "Your character isn't loaded yet.",
}
local function shootMurderer()
    local remote = findGunShoot()
    if not remote then return false, "no_gun" end
    local victim = findMurderer()
    if not victim then return false, "no_murderer" end
    local part = targetHitPart(victim.Character)
    if not part then return false, "no_victim" end
    local theirCF = part.CFrame
    -- origin = our REAL gun-muzzle POSITION (passes the server's origin check) but AIMED
    -- at the murderer. The server fires along the origin's look direction, so without
    -- re-aiming it shoots wherever the gun happens to face -> misses. Correct arg order.
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local att = hrp and hrp:FindFirstChild("GunRaycastAttachment")
    local muzzle = (att and att.WorldPosition) or (hrp and hrp.Position) or part.Position
    local origin = CFrame.new(muzzle, part.Position)
    pcall(function() remote:FireServer(origin, theirCF) end)
    return true
end
local function tryShoot()
    local ok, reason = shootMurderer()
    if not ok then
        Library:Notification(SHOOT_ERR[reason] or "Shoot failed", 3, Color3.fromRGB(255, 80, 80))
    end
end

-- ============================================================
--  Murderer -- knife kill (your Knife's own remotes)
--  KnifeStabbed = the swing, HandleTouched = register a hit on a part.
-- ============================================================
-- the Knife's remotes live in the tool whether it's equipped (Character) or just held
-- in the Backpack -- so kill-all works WITHOUT having to hold/equip the knife.
local function knifeEvents()
    local function pull(parent)
        local knife = parent and parent:FindFirstChild("Knife")
        local ev = knife and knife:FindFirstChild("Events")
        if ev then return ev:FindFirstChild("KnifeStabbed"), ev:FindFirstChild("HandleTouched") end
    end
    local s, t = pull(LocalPlayer.Character)
    if s and t then return s, t end
    return pull(LocalPlayer:FindFirstChild("Backpack"))
end
local function victimPart(plr)
    local ch = plr and plr.Character
    if not ch then return nil end
    return ch:FindFirstChild("LowerTorso") or ch:FindFirstChild("Torso")
        or ch:FindFirstChild("HumanoidRootPart")
end
local function isAlive(plr)
    local ch = plr and plr.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end
-- swing once, then register a hit on every living player (optionally in range)
local function knifeKillAll(range, silent)
    local stab, touch = knifeEvents()
    if not (stab and touch) then
        if not silent then
            Library:Notification("You're not the Murderer (no Knife)", 3, Color3.fromRGB(255, 180, 60))
        end
        return false
    end
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    pcall(function() stab:FireServer() end)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) then
            local part = victimPart(p)
            if part and (not range or not root or (part.Position - root.Position).Magnitude <= range) then
                pcall(function() touch:FireServer(part) end)
            end
        end
    end
    return true
end

-- ============================================================
--  Gun pickup -- teleport onto a "GunDrop" BasePart for a moment
--  GunDrop set is kept live via DescendantAdded/Removing (MM2 maps
--  have thousands of parts, so a full scan per pickup is wasteful).
-- ============================================================
local gunDropCache = {}
for _, d in ipairs(Workspace:GetDescendants()) do
    if d:IsA("BasePart") and d.Name == "GunDrop" then gunDropCache[d] = true end
end
track(Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("BasePart") and d.Name == "GunDrop" then gunDropCache[d] = true end
end))
track(Workspace.DescendantRemoving:Connect(function(d)
    if gunDropCache[d] then gunDropCache[d] = nil end
end))
local function findGunDrop()
    for d in pairs(gunDropCache) do
        if d.Parent then return d end
        gunDropCache[d] = nil
    end
    return nil
end

local PICKUP_ERR = {
    no_drop = "Can't pick up yet -- the Sheriff hasn't dropped the gun.",
    no_hrp  = "Your character isn't loaded.",
}
local pickupActive = false
local function pickupGun()
    if pickupActive then return false, "active" end
    local drop = findGunDrop()
    if not drop then return false, "no_drop" end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no_hrp" end
    pickupActive = true
    local realCF = hrp.CFrame
    pcall(function() hrp.CFrame = drop.CFrame end)
    task.delay(0.1, function()
        if hrp.Parent then pcall(function() hrp.CFrame = realCF end) end
        pickupActive = false
    end)
    return true
end
local function tryPickup()
    local ok, reason = pickupGun()
    if not ok and PICKUP_ERR[reason] then
        Library:Notification(PICKUP_ERR[reason], 3, Color3.fromRGB(255, 180, 60))
    end
end

-- ============================================================
--  ESP draws (Drawing.Text labels) -- identity labels + dropped gun
-- ============================================================
local state = { idEsp = false, dropEsp = false, knifeAura = false, knifeRange = 30, autoPickup = false }

local idDraws = {}    -- [player] = Drawing.Text
local dropDraws = {}  -- [drop part] = { hl, draw }

local function mkText(color)
    local t = Drawing.new("Text")
    t.Visible, t.Center, t.Outline = false, true, true
    t.OutlineColor = Color3.new(0, 0, 0)
    t.Color = color or Color3.fromRGB(255, 255, 255)
    t.Size = 13
    t.Text = ""
    return t
end
local function clearIdDraws()
    for plr, d in pairs(idDraws) do pcall(function() d:Remove() end); idDraws[plr] = nil end
end
local function clearDropDraws()
    for part, m in pairs(dropDraws) do
        if m.hl then pcall(function() m.hl:Destroy() end) end
        if m.draw then pcall(function() m.draw:Remove() end) end
        dropDraws[part] = nil
    end
end

if hasDrawing then
    -- single render loop projects every label from world -> screen
    track(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        if not cam then return end

        -- drop a gun-drop label the instant its part is gone (picked up / round ended);
        -- the text isn't a child of the part, so it would otherwise linger on screen.
        for part, m in pairs(dropDraws) do
            if not (part and part.Parent and gunDropCache[part]) then
                if m.hl then pcall(function() m.hl:Destroy() end) end
                if m.draw then pcall(function() m.draw:Remove() end) end
                dropDraws[part] = nil
            end
        end

        if state.idEsp then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local id = getIdentity(plr)
                    local char = plr.Character
                    local head = char and char:FindFirstChild("Head")
                    if id and head then
                        local d = idDraws[plr]
                        if not d then d = mkText(); idDraws[plr] = d end
                        local sp, on = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 2.6, 0))
                        if on then
                            d.Position = Vector2.new(sp.X, sp.Y)
                            d.Text = id
                            d.Color = COLORS[id] or Color3.fromRGB(255, 255, 255)
                            d.Visible = true
                        else
                            d.Visible = false
                        end
                    elseif idDraws[plr] then
                        pcall(function() idDraws[plr]:Remove() end); idDraws[plr] = nil
                    end
                end
            end
        end

        if state.dropEsp then
            for d in pairs(gunDropCache) do
                if d.Parent then
                    local m = dropDraws[d]
                    if not m then
                        local hl = Instance.new("Highlight")
                        hl.FillColor = Color3.fromRGB(255, 215, 60)
                        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                        hl.FillTransparency = 0.45
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Adornee = d; hl.Parent = d
                        local draw = mkText(Color3.fromRGB(255, 215, 60)); draw.Text = "GUN"
                        m = { hl = hl, draw = draw }; dropDraws[d] = m
                    end
                    local sp, on = cam:WorldToViewportPoint(d.Position + Vector3.new(0, 1.5, 0))
                    if on then m.draw.Position = Vector2.new(sp.X, sp.Y); m.draw.Visible = true
                    else m.draw.Visible = false end
                end
            end
        end
    end))
end

-- ============================================================
--  Background loops (knife aura, auto pickup) -- gated on state flags
-- ============================================================
task.spawn(function()
    while not unloaded do
        if state.knifeAura then pcall(knifeKillAll, state.knifeRange, true) end
        task.wait(0.3)
    end
end)
task.spawn(function()
    while not unloaded do
        if state.autoPickup then
            local drop = findGunDrop()
            if drop and getIdentity(LocalPlayer) ~= "Murderer" then
                pickupGun(); task.wait(2)
            else
                task.wait(0.5)
            end
        else
            task.wait(0.5)
        end
    end
end)

-- ============================================================
--  UI  (Main tab)
-- ============================================================
local Sub = MainPage:SubPage({ Name = "MM2" })

local SheriffSec = Sub:Section({ Name = "Sheriff", Side = 1 })
SheriffSec:Button({ Name = "Shoot murderer", Callback = tryShoot })
SheriffSec:Label({ Name = "Shoot key" }):Keybind({
    Name = "Shoot murderer", Flag = "MM2_ShootKey", Mode = "Hold", Default = Enum.KeyCode.K,
    Callback = function(state2) if state2 then tryShoot() end end })

local KnifeSec = Sub:Section({ Name = "Murderer knife", Side = 1 })
KnifeSec:Button({ Name = "Kill all", Callback = function() knifeKillAll(nil) end })
KnifeSec:Label({ Name = "Kill all key" }):Keybind({
    Name = "Knife kill all", Flag = "MM2_KnifeKey", Mode = "Hold", Default = Enum.KeyCode.J,
    Callback = function(state2) if state2 then knifeKillAll(nil) end end })
KnifeSec:Toggle({ Name = "Knife aura (auto)", Flag = "MM2_KnifeAura", Default = false,
    Callback = function(v) state.knifeAura = v end })
KnifeSec:Slider({ Name = "Aura range", Flag = "MM2_KnifeAuraRange", Min = 5, Max = 200, Default = 30, Decimals = 0,
    Callback = function(v) state.knifeRange = v end })

local EspSec = Sub:Section({ Name = "ESP", Side = 2 })
if not hasDrawing then
    EspSec:Label({ Name = "ESP needs a Drawing-capable executor." })
end
EspSec:Toggle({ Name = "Sheriff / Murderer labels", Flag = "MM2_IdentityEsp", Default = false,
    Callback = function(v) state.idEsp = v; if not v then clearIdDraws() end end })
EspSec:Toggle({ Name = "Dropped gun ESP", Flag = "MM2_DropEsp", Default = false,
    Callback = function(v) state.dropEsp = v; if not v then clearDropDraws() end end })

local PickupSec = Sub:Section({ Name = "Gun pickup", Side = 2 })
PickupSec:Button({ Name = "Pickup gun now", Callback = tryPickup })
PickupSec:Label({ Name = "Pickup key" }):Keybind({
    Name = "Pickup gun", Flag = "MM2_PickupKey", Mode = "Hold", Default = Enum.KeyCode.H,
    Callback = function(state2) if state2 then tryPickup() end end })
PickupSec:Toggle({ Name = "Auto pickup gun", Flag = "MM2_AutoPickup", Default = false,
    Callback = function(v) state.autoPickup = v end })

-- ============================================================
--  Universal base AFTER Main, so Main stays the first tab.
-- ============================================================
pcall(function() ctx.load("games/combat.lua")(ctx) end)
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown: stop our loops/draws on unload / re-execution. Wrap the
--  universal-registered disableAll/OnExit so ours runs too.
-- ============================================================
local function mm2Cleanup()
    unloaded = true
    state.idEsp, state.dropEsp, state.knifeAura, state.autoPickup = false, false, false, false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    clearIdDraws()
    clearDropDraws()
end
do
    local g = getgenv and getgenv()
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full()
            pcall(mm2Cleanup)
            if prev then pcall(prev) end
        end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
