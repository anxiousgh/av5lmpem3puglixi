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
    instant = true,   -- flatten + speed up the knife so it arrives almost instantly
    showFov = true, fovColor = Color3.fromRGB(255, 255, 255),
    head = nil,
}
if gv() then gv()._SHARD_S = S end

local CR        = LocalPlayer:WaitForChild("ClientRemotes", 10)
local CheckShot = CR and CR:FindFirstChild("CheckShot")
local CheckFire = CR and CR:FindFirstChild("CheckFire")
-- BindableEvent that drives the thrown knife (visual + hit ray); we redirect it
local GlobalWeaponFire = game:GetService("ReplicatedStorage"):FindFirstChild("GlobalWeaponFire")

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
-- ---- FOV circle (a rounded GUI ring, centered on the crosshair) ----
local fovGui = Instance.new("ScreenGui")
fovGui.Name = "_shard_fov"; fovGui.ResetOnSpawn = false; fovGui.IgnoreGuiInset = false
if not pcall(function() fovGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) or not fovGui.Parent then
    fovGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end
local fovRing = Instance.new("Frame")
fovRing.AnchorPoint = Vector2.new(0.5, 0.5)
fovRing.BackgroundTransparency = 1
fovRing.BorderSizePixel = 0
fovRing.Visible = false
fovRing.Parent = fovGui
local fovCorner = Instance.new("UICorner"); fovCorner.CornerRadius = UDim.new(1, 0); fovCorner.Parent = fovRing
local fovStroke = Instance.new("UIStroke"); fovStroke.Thickness = 1.5; fovStroke.Transparency = 0.35; fovStroke.Parent = fovRing

track(RunService.RenderStepped:Connect(function()
    S.head = (S.silent and pickAim()) or nil
    -- FOV circle
    if S.silent and S.showFov then
        local m = UIS:GetMouseLocation()
        fovRing.Position = UDim2.fromOffset(m.X, m.Y)
        fovRing.Size = UDim2.fromOffset(S.fov * 2, S.fov * 2)
        fovStroke.Color = S.fovColor
        fovRing.Visible = true
    else
        fovRing.Visible = false
    end
end))

-- ---- the __namecall hook (installed once, survives re-exec). Hook body does NO
--      namecalls -- it only reads the cached target + edits args + calls old. ----
local gnm = getnamecallmethod
if gv() and not gv()._SHARD_HOOK2 and hookmetamethod and gnm then
    gv()._SHARD_HOOK2 = true
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local st = gv() and gv()._SHARD_S
        if st and st.silent then
            local head = st.head
            if head and head.Parent then
                if self == CheckFire or self == CheckShot then
                    if gnm() == "FireServer" then
                        local a = table.pack(...)
                        if self == CheckFire then
                            -- [2]camPos [3]camLook -> aim the server's recorded throw at the head
                            if typeof(a[2]) == "Vector3" then a[3] = (head.Position - a[2]).Unit end
                        else
                            -- [5]camCF [6]hitPos [7]hitPart -> report the headshot
                            local camPos = (typeof(a[5]) == "CFrame" and a[5].Position) or workspace.CurrentCamera.CFrame.Position
                            a[5] = CFrame.new(camPos, head.Position)
                            a[6] = head.Position
                            a[7] = head
                        end
                        return old(self, table.unpack(a, 1, a.n))
                    end
                elseif self == GlobalWeaponFire then
                    -- redirect the ACTUAL thrown knife at the head; optionally flatten +
                    -- speed it so it arrives almost instantly (a real shot the server accepts)
                    if gnm() == "Fire" then
                        local params = (...)
                        if type(params) == "table" and typeof(params.Origin) == "Vector3" then
                            params.Direction = (head.Position - params.Origin).Unit
                            if params.Misc then params.Misc.CamCFrame = CFrame.new(params.Origin, head.Position) end
                            if st.instant then
                                params.Gravity = 0
                                params.Force = math.max(tonumber(params.Force) or 0, 350)
                            end
                        end
                    end
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
    Sec:Toggle({ Name = "Show FOV circle", Flag = "SHARD_ShowFov", Default = true,
        Callback = function(v) S.showFov = v end })
    Sec:Label({ Name = "FOV color" }):Colorpicker({ Flag = "SHARD_FovColor", Default = Color3.fromRGB(255, 255, 255),
        Callback = function(c) S.fovColor = c end })

    local Sec2 = Sub:Section({ Name = "Knife path", Side = 2 })
    Sec2:Toggle({ Name = "Instant (flat + fast knife)", Flag = "SHARD_Instant", Default = true,
        Callback = function(v) S.instant = v end })
end

-- universal pages after Main so Main stays first
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    unloaded = true
    S.silent = false
    S.head = nil
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() fovGui:Destroy() end)
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
