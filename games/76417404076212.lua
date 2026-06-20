-- ============================================================
--  games/76417404076212.lua  --  [FPS] SHARD (knife-throwing FFA)
--
--  Hit reg is client-authoritative: the client raycasts a thrown knife and
--  reports the hit to the server.
--    CheckFire:FireServer(clock, camPos, camLook, true)         -- on throw
--    CheckShot:FireServer(ammo,spread,maxAmmo,reload, camCF, hitPos, hitPart, seed, clock) -- on land
--    MeleeEvent:FireServer(hitPart)                              -- on melee swing
--  Silent aim = retarget those calls' hit data onto the chosen enemy. (Firing
--  the shot INSTANTLY on throw gets rejected -- the server wants the projectile
--  to actually travel -- so we retarget the real on-land shot; it lands the kill
--  when the knife arrives.)
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local function gv() return (getgenv and getgenv()) or nil end

local MainPage = Window:Page({ Name = "Main" })

local unloaded = false
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

-- settings live in getgenv so the (one-time) hook always reads the latest copy
-- even after a hub re-execute
local S = (gv() and gv()._SHARD_S) or {
    silent = false, fov = 220, hitPart = "Head",
    melee = false, meleeRange = 28,
    head = nil, meleePart = nil,
}
if gv() then gv()._SHARD_S = S end

local CR        = LocalPlayer:WaitForChild("ClientRemotes", 10)
local CheckShot = CR and CR:FindFirstChild("CheckShot")
local CheckFire = CR and CR:FindFirstChild("CheckFire")
local Melee     = CR and CR:FindFirstChild("MeleeEvent")

-- ---- target pickers (run in RenderStepped, OUTSIDE the hook, so namecalls here
--      can't trip __namecall re-entrancy) ----
local function aimPartOf(char)
    return char:FindFirstChild(S.hitPart) or char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end
-- silent-aim target: enemy part nearest the crosshair, within the FOV (px) circle
local function pickAim()
    local cam = workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local mouse = UIS:GetMouseLocation()
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum  = p.Character:FindFirstChildOfClass("Humanoid")
            local part = aimPartOf(p.Character)
            if hum and hum.Health > 0 and part
                and cam.CFrame.LookVector:Dot((part.Position - origin).Unit) > 0.1 then
                local sp, on = cam:WorldToViewportPoint(part.Position)
                if on then
                    local d = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
                    if d <= S.fov and (not bestD or d < bestD) then bestD = d; best = part end
                end
            end
        end
    end
    return best
end
-- melee target: nearest enemy part within melee range
local function pickMelee()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum  = p.Character:FindFirstChildOfClass("Humanoid")
            local part = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("UpperTorso")
                or p.Character:FindFirstChild("Torso")
            if hum and hum.Health > 0 and part then
                local d = (part.Position - hrp.Position).Magnitude
                if d <= S.meleeRange and (not bestD or d < bestD) then bestD = d; best = part end
            end
        end
    end
    return best
end
track(RunService.RenderStepped:Connect(function()
    S.head      = (S.silent and pickAim()) or nil
    S.meleePart = (S.melee and pickMelee()) or nil
end))

-- ---- the __namecall hook (installed once, survives re-exec). Hook body does NO
--      namecalls -- it only reads the cached target + edits args + calls old. ----
local gnm = getnamecallmethod
if gv() and not gv()._SHARD_HOOK and hookmetamethod and gnm then
    gv()._SHARD_HOOK = true
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local st = gv() and gv()._SHARD_S
        if st then
            if self == CheckFire or self == CheckShot then
                if st.silent and gnm() == "FireServer" then
                    local head = st.head
                    if head and head.Parent then
                        local a = table.pack(...)
                        if self == CheckFire then
                            if typeof(a[2]) == "Vector3" then a[3] = (head.Position - a[2]).Unit end
                        else
                            local camPos = (typeof(a[5]) == "CFrame" and a[5].Position) or workspace.CurrentCamera.CFrame.Position
                            a[5] = CFrame.new(camPos, head.Position)
                            a[6] = head.Position
                            a[7] = head
                        end
                        return old(self, table.unpack(a, 1, a.n))
                    end
                end
            elseif self == Melee then
                if st.melee and gnm() == "FireServer" then
                    local m = st.meleePart
                    if m and m.Parent then return old(self, m) end
                end
            end
        end
        return old(self, ...)
    end)
end

-- ============================================================
--  UI
-- ============================================================
local Sub = MainPage:SubPage({ Name = "Combat" })
do
    local Sec = Sub:Section({ Name = "Silent Aim", Side = 1 })
    Sec:Toggle({ Name = "Silent aim", Flag = "SHARD_Silent", Default = false,
        Callback = function(v) S.silent = v end })
    Sec:Slider({ Name = "FOV", Flag = "SHARD_FOV", Min = 20, Max = 1000, Default = 220, Decimals = 0, Suffix = " px",
        Callback = function(v) S.fov = v end })
    Sec:Dropdown({ Name = "Hit part", Flag = "SHARD_HitPart", Default = "Head", Multi = false,
        Items = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
        Callback = function(v) S.hitPart = (type(v) == "table" and v[1]) or v or "Head" end })

    local Sec2 = Sub:Section({ Name = "Melee", Side = 2 })
    Sec2:Toggle({ Name = "Melee auto-hit", Flag = "SHARD_Melee", Default = false,
        Callback = function(v) S.melee = v end })
    Sec2:Slider({ Name = "Melee range", Flag = "SHARD_MeleeRange", Min = 5, Max = 60, Default = 28, Decimals = 0, Suffix = " studs",
        Callback = function(v) S.meleeRange = v end })
end

-- universal pages after Main so Main stays first
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    unloaded = true
    S.silent, S.melee = false, false
    S.head, S.meleePart = nil, nil
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
