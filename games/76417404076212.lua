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
    magic = false,    -- ignore FOV/facing: every throw homes to the nearest enemy anywhere
    wallbang = false, -- spoof the throw origin onto the target so the server's LoS check passes
    noReload = false, spamRate = 0.08, tmpl = nil,  -- replay throws to bypass the cooldown
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
-- silent-aim target: enemy part nearest the crosshair within the FOV circle.
-- Magic mode ignores FOV/facing/screen entirely -> nearest enemy ANYWHERE.
local function pickAim()
    local cam = workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local mouse = UIS:GetMouseLocation()
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum  = p.Character:FindFirstChildOfClass("Humanoid")
            local part = aimPartOf(p.Character)
            if hum and hum.Health > 0 and part then
                if S.magic then
                    -- nearest by world distance, no FOV/facing/LoS
                    local d = (part.Position - origin).Magnitude
                    if not bestD or d < bestD then bestD = d; best = part end
                elseif cam.CFrame.LookVector:Dot((part.Position - origin).Unit) > 0.1 then
                    local sp, on = cam:WorldToViewportPoint(part.Position)
                    if on then
                        local d = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
                        if d <= S.fov and (not bestD or d < bestD) then bestD = d; best = part end
                    end
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
if gv() and not gv()._SHARD_HOOK3 and hookmetamethod and gnm then
    gv()._SHARD_HOOK3 = true
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local st = gv() and gv()._SHARD_S
        if st and st.silent then
            local head = st.head
            if head and head.Parent then
                -- WALLBANG: put the throw origin 2 studs in front of the head (past any
                -- cover between us and them) so the server's origin->hit LoS ray is clear
                local realCam = workspace.CurrentCamera.CFrame.Position
                local aimDir = head.Position - realCam
                aimDir = (aimDir.Magnitude > 0 and aimDir.Unit) or Vector3.new(0, 0, -1)
                local wbOrigin = head.Position - aimDir * 2

                if self == CheckFire or self == CheckShot then
                    if gnm() == "FireServer" then
                        local a = table.pack(...)
                        if self == CheckFire then            -- [2]camPos [3]camLook
                            if typeof(a[2]) == "Vector3" then
                                if st.wallbang then a[2] = wbOrigin end
                                a[3] = (head.Position - a[2]).Unit
                            end
                        else                                  -- [5]camCF [6]hitPos [7]hitPart
                            local origin = st.wallbang and wbOrigin
                                or ((typeof(a[5]) == "CFrame" and a[5].Position) or realCam)
                            a[5] = CFrame.new(origin, head.Position)
                            a[6] = head.Position
                            a[7] = head
                        end
                        return old(self, table.unpack(a, 1, a.n))
                    end
                elseif self == GlobalWeaponFire then
                    -- redirect the ACTUAL thrown knife at the head; flatten + speed it
                    -- (Instant); cache the throw table so No-reload can replay it
                    if gnm() == "Fire" then
                        local params = (...)
                        if type(params) == "table" and typeof(params.Origin) == "Vector3" then
                            if st.wallbang then params.Origin = wbOrigin end
                            params.Direction = (head.Position - params.Origin).Unit
                            if params.Misc then params.Misc.CamCFrame = CFrame.new(params.Origin, head.Position) end
                            if st.instant then
                                params.Gravity = 0
                                params.Force = math.max(tonumber(params.Force) or 0, 350)
                            end
                            st.tmpl = params  -- template for No-reload replay
                        end
                    end
                end
            end
        end
        return old(self, ...)
    end)
end

-- ---- No reload: zero the live weapon config's ThrowCooldown so the throw gate
--      (os.clock()-lastThrow < ThrowCooldown) always passes -> throw as fast as you
--      click. The config is an upvalue of the SignalManager weapon handlers; we reach
--      it via getconnections + debug.getupvalues and re-apply (re-equip rebuilds it). ----
local SignalEvents = game:GetService("ReplicatedStorage"):FindFirstChild("SignalManager")
SignalEvents = SignalEvents and SignalEvents:FindFirstChild("SignalEvents")
local function forEachWeaponConfig(fn)
    if not (SignalEvents and getconnections and debug and debug.getupvalues) then return end
    for _, sig in ipairs(SignalEvents:GetChildren()) do
        if sig:IsA("BindableEvent") then
            local ok, conns = pcall(getconnections, sig.Event)
            if ok and conns then
                for _, c in ipairs(conns) do
                    local f = c.Function
                    if f then
                        local ok2, ups = pcall(debug.getupvalues, f)
                        if ok2 and ups then
                            for _, uv in pairs(ups) do
                                if type(uv) == "table" and rawget(uv, "ThrowCooldown") ~= nil then fn(uv) end
                            end
                        end
                    end
                end
            end
        end
    end
end
do
    local lastApply = 0
    track(RunService.Heartbeat:Connect(function()
        if os.clock() - lastApply < 0.4 then return end
        lastApply = os.clock()
        if S.noReload then
            forEachWeaponConfig(function(cfg)
                if not S._origCD and cfg.ThrowCooldown ~= 0 then S._origCD = cfg.ThrowCooldown end
                cfg.ThrowCooldown = 0
            end)
            S._zeroed = true
        elseif S._zeroed then
            forEachWeaponConfig(function(cfg) cfg.ThrowCooldown = S._origCD or 0.8 end)
            S._zeroed = false
        end
    end))
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

    local Sec2 = Sub:Section({ Name = "Knife mods", Side = 2 })
    Sec2:Toggle({ Name = "Instant (flat + fast knife)", Flag = "SHARD_Instant", Default = true,
        Callback = function(v) S.instant = v end })
    Sec2:Toggle({ Name = "Wallbang (through walls)", Flag = "SHARD_Wallbang", Default = false,
        Callback = function(v) S.wallbang = v end })
    Sec2:Toggle({ Name = "Magic bullets (any target, off-screen)", Flag = "SHARD_Magic", Default = false,
        Callback = function(v) S.magic = v end })
    Sec2:Toggle({ Name = "No reload (no throw cooldown)", Flag = "SHARD_NoReload", Default = false,
        Callback = function(v) S.noReload = v end })
end

-- universal pages after Main so Main stays first
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    unloaded = true
    S.silent, S.noReload, S.wallbang, S.magic = false, false, false, false
    S.head = nil
    if S._zeroed then pcall(function() forEachWeaponConfig(function(cfg) cfg.ThrowCooldown = S._origCD or 0.8 end) end); S._zeroed = false end
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
