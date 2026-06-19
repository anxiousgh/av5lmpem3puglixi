-- ============================================================
--  games/universal.lua  --  the base "main" UI every game gets
--
--  Pages built on the Window passed in via ctx:
--    Combat   -- Aimbot (camera lock) + Triggerbot subpages (working)
--    Player   -- working movement (walkspeed/jump/cframe/fly/noclip/inf-jump)
--    Visuals  -- ESP (box / name / distance / health, working)
--
--  Settings (config + themes) is added by the loader after this runs.
--  ctx = { Library, Window, Watermark, KeybindList, fetch, load, base, placeId }
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

-- ---------- services / helpers ----------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = workspace
local LocalPlayer      = Players.LocalPlayer

local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- shared combat helpers
local function aliveChar(plr)
    local c = plr.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if h and h.Health > 0 then return c, h end
    return nil
end
local function teamOk(plr, teamCheck)
    if not teamCheck then return true end
    return plr.Team == nil or plr.Team ~= LocalPlayer.Team
end
-- line-of-sight: nothing solid between the camera and `part`.
local function visibleTo(part)
    if not part then return false end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    local lc = getChar(); if lc then ignore[#ignore + 1] = lc end
    if part.Parent then ignore[#ignore + 1] = part.Parent end
    params.FilterDescendantsInstances = ignore
    local res = Workspace:Raycast(origin, part.Position - origin, params)
    return res == nil
end
-- guarded Drawing factory (nil if the executor has no Drawing API)
local hasDrawing = (Drawing ~= nil and Drawing.new ~= nil)
local function mkDraw(class, props)
    if not hasDrawing then return nil end
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    for k, v in pairs(props) do pcall(function() d[k] = v end) end
    return d
end

-- Every persistent feature connection is tracked here so the whole module can
-- be torn down on unload / re-execution (see disableAll at the bottom).
local Connections = {}
local function track(c) Connections[#Connections + 1] = c; return c end

-- ============================================================
--  MOVEMENT BACKEND  (enforced per-frame, survives respawn)
-- ============================================================
local Movement = {}

do  -- WalkSpeed
    local active, value, conn = false, 50, nil
    local function enforce()
        if not active then return end
        local hum = getHum()
        if hum and hum.WalkSpeed ~= value then pcall(function() hum.WalkSpeed = value end) end
    end
    function Movement.setWalkSpeedValue(v) value = v; enforce() end
    function Movement.setWalkSpeed(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then conn = RunService.Heartbeat:Connect(enforce)
        else local hum = getHum(); if hum then pcall(function() hum.WalkSpeed = 16 end) end end
    end
end

do  -- JumpPower / JumpHeight
    local active, value, conn = false, 50, nil
    local function enforce()
        if not active then return end
        local hum = getHum(); if not hum then return end
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
        pcall(function()
            if hum.UseJumpPower then
                if hum.JumpPower ~= value then hum.JumpPower = value end
            else
                local h = value / 7
                if math.abs(hum.JumpHeight - h) > 0.05 then hum.JumpHeight = h end
            end
        end)
    end
    function Movement.setJumpValue(v) value = v; enforce() end
    function Movement.setJump(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then conn = RunService.Heartbeat:Connect(enforce)
        else local hum = getHum(); if hum then pcall(function()
            if hum.UseJumpPower then hum.JumpPower = 50 else hum.JumpHeight = 7.2 end
        end) end end
    end
end

do  -- CFrame speed
    local active, mult, conn = false, 2, nil
    function Movement.setCFrameValue(v) mult = v end
    function Movement.setCFrame(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then
            conn = RunService.Heartbeat:Connect(function(dt)
                if not active or UserInputService:GetFocusedTextBox() then return end
                local hrp = getHRP(); if not hrp then return end
                local cam = Workspace.CurrentCamera
                local dir = Vector3.zero
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
                dir = Vector3.new(dir.X, 0, dir.Z)
                if dir.Magnitude > 0 then hrp.CFrame = hrp.CFrame + dir.Unit * (16 * (mult - 1)) * dt end
            end)
        end
    end
end

do  -- Fly
    local active, speed, conn = false, 60, nil
    function Movement.setFlyValue(v) speed = v end
    function Movement.setFly(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then
            conn = RunService.Heartbeat:Connect(function(dt)
                if not active then return end
                local hrp = getHRP(); if not hrp then return end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                if UserInputService:GetFocusedTextBox() then return end
                local cam = Workspace.CurrentCamera
                local dir = Vector3.zero
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.new(0, 1, 0) end
                if dir.Magnitude > 0 then hrp.CFrame = hrp.CFrame + dir.Unit * speed * dt end
            end)
        end
    end
end

do  -- Noclip
    local active = false
    local PARTS = { "HumanoidRootPart", "UpperTorso", "Torso", "Head", "LowerTorso" }
    function Movement.setNoclip(on)
        active = on
        pcall(function() RunService:UnbindFromRenderStep("WH_Noclip") end)
        if on then
            RunService:BindToRenderStep("WH_Noclip", Enum.RenderPriority.First.Value, function()
                if not active then return end
                local c = getChar(); if not c then return end
                for _, name in ipairs(PARTS) do
                    local p = c:FindFirstChild(name); if p then p.CanCollide = false end
                end
            end)
        else
            local c = getChar()
            if c then for _, name in ipairs(PARTS) do
                local p = c:FindFirstChild(name)
                if p and p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
            end end
        end
    end
end

do  -- Infinite jump
    local active, conn = false, nil
    function Movement.setInfJump(on)
        active = on
        if conn then conn:Disconnect(); conn = nil end
        if on then
            conn = UserInputService.JumpRequest:Connect(function()
                if not active then return end
                local hum = getHum()
                if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
            end)
        end
    end
end

-- ============================================================
--  CAMLOCK  (camera lock to the nearest target inside the FOV)
-- ============================================================
local CamLock = {
    enabled = false, fov = 120, smoothing = 0.5, sticky = false,
    teamCheck = true, hitPart = "Head", visibleCheck = false, showFov = false,
}
do
    local fovCircle = mkDraw("Circle", {
        Thickness = 1, NumSides = 64, Filled = false, Visible = false,
        Transparency = 1, Color = Color3.fromRGB(200, 183, 247),
    })
    local stickyTarget = nil   -- Player held while sticky is on

    local function resolvePart(plr)
        local char = aliveChar(plr); if not char then return nil end
        return char:FindFirstChild(CamLock.hitPart) or char:FindFirstChild("HumanoidRootPart")
    end

    -- A held sticky target stays valid while alive + team-ok + (visible if
    -- checked). Returns its part when still valid, otherwise nil.
    local function stickyPart(plr)
        if not plr or plr == LocalPlayer or not plr.Parent then return nil end
        if not teamOk(plr, CamLock.teamCheck) then return nil end
        local part = resolvePart(plr); if not part then return nil end
        if CamLock.visibleCheck and not visibleTo(part) then return nil end
        return part
    end

    -- Nearest valid target to the crosshair within the FOV radius.
    local function findClosest()
        local cam = Workspace.CurrentCamera
        local mouse = UserInputService:GetMouseLocation()
        local bestPlr, bestPart, bestDist
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == LocalPlayer then continue end
            if not teamOk(plr, CamLock.teamCheck) then continue end
            local part = resolvePart(plr); if not part then continue end
            if CamLock.visibleCheck and not visibleTo(part) then continue end
            local sp, on = cam:WorldToViewportPoint(part.Position)
            if not on then continue end
            local d = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
            if d <= CamLock.fov and (not bestDist or d < bestDist) then
                bestPlr, bestPart, bestDist = plr, part, d
            end
        end
        return bestPlr, bestPart
    end

    track(RunService.RenderStepped:Connect(function(dt)
        if fovCircle then
            fovCircle.Visible = CamLock.showFov
            if CamLock.showFov then
                fovCircle.Radius = CamLock.fov
                fovCircle.Position = UserInputService:GetMouseLocation()
            end
        end
        if not CamLock.enabled then stickyTarget = nil; return end
        if Library.WindowOpenState then return end   -- don't fight you while in the menu

        local part
        if CamLock.sticky then
            -- keep the current target while valid; only re-acquire when it drops
            part = stickyPart(stickyTarget)
            if not part then
                stickyTarget, part = findClosest()
            end
        else
            stickyTarget = nil
            local _, p = findClosest()
            part = p
        end
        if not part then return end

        local cam = Workspace.CurrentCamera
        local alpha = math.clamp(1 - (CamLock.smoothing ^ (dt * 60)), 0, 1)
        cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, part.Position), alpha)
    end))
end

-- ============================================================
--  TRIGGERBOT  (fire when the crosshair is on an enemy)
-- ============================================================
local Trig = { enabled = false, delay = 0, teamCheck = true }
do
    local VIM; pcall(function() VIM = VirtualInputManager end)
    local lastShot = 0
    local function fire()
        if not VIM then return end
        task.spawn(function()
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0) end)
            task.wait()
            pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
        end)
    end

    track(RunService.Heartbeat:Connect(function()
        if not Trig.enabled then return end
        if Library.WindowOpenState then return end   -- don't fire while clicking the menu
        local cam = Workspace.CurrentCamera
        local mouse = UserInputService:GetMouseLocation()
        local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignore = {}; local lc = getChar(); if lc then ignore[1] = lc end
        params.FilterDescendantsInstances = ignore
        local res = Workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
        if not res or not res.Instance then return end
        local model = res.Instance:FindFirstAncestorOfClass("Model")
        local plr = model and Players:GetPlayerFromCharacter(model)
        if not plr or plr == LocalPlayer then return end
        if not teamOk(plr, Trig.teamCheck) then return end
        if not aliveChar(plr) then return end
        if (tick() - lastShot) * 1000 < Trig.delay then return end
        lastShot = tick()
        fire()
    end))
end

-- ============================================================
--  ESP  (box / name / distance / health via Drawing)
-- ============================================================
local Esp = {
    enabled = false, box = true, names = false, distance = false, health = false,
    teamCheck = false, color = Color3.fromRGB(200, 183, 247),
    boxType = "Full",                 -- "Full" | "Corner" | "Solid"
    fillOpacity = 0.4,                -- Drawing alpha for the "Solid" filled box
    tracer = false, tracerOrigin = "Bottom",   -- "Bottom" | "Top" | "Mouse"
    chams = false,                    -- in-game Highlight
    chamsFill = Color3.fromRGB(200, 183, 247),
    chamsOutline = Color3.fromRGB(255, 255, 255),
    chamsTransparency = 0.6,          -- Highlight FillTransparency (0 = solid)
    skeleton = false,
}
-- expose for the ESP Preview widget (it reads these to draw a live preview box)
if getgenv then
    local g = getgenv()
    if g.WH then g.WH.espPreview = Esp end
end
do
    local objs = {}   -- plr -> { box, solid, name, dist, health, tracer, corners?, skel?, chams? }

    -- skeleton bone pairs (R15 first, then R6; missing parts are skipped)
    local BONES = {
        { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
        { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    }

    -- Drawing.Line and Drawing.Triangle flicker on some executors, while
    -- Drawing.Square / Text and in-game GUI frames are rock-steady. So the
    -- lines (tracer / corner brackets / skeleton) are drawn as thin rotated
    -- GUI frames on our own ScreenGui, and the body fill is a filled Square.
    local espGui = Instance.new("ScreenGui")
    espGui.Name = "\0"
    espGui.ResetOnSpawn = false
    espGui.IgnoreGuiInset = true    -- (0,0) at the very top, matching the 3D
                                    -- viewport that WorldToViewportPoint/Drawing use
                                    -- (false would push every line down by the 36px
                                    -- topbar inset -> lines land below the player)
    espGui.DisplayOrder = 5
    pcall(function() espGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not espGui.Parent then
        pcall(function() espGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
    end

    local function lineFrame()
        local f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BorderSizePixel = 0
        f.BackgroundColor3 = Esp.color
        f.Visible = false
        f.Parent = espGui
        return f
    end
    -- aim a thin frame from screen-point a to screen-point b (a rotated 1px bar).
    -- Center it on a pixel (floor + 0.5) so the 1px bar renders crisp instead of
    -- smearing across two rows -- a half-pixel-straddled line reads as a fat ~2px
    -- blur, so snapping it makes the tracer look properly thin.
    local function setLine(f, a, b, color, thickness)
        local d = b - a
        f.Size = UDim2.fromOffset(math.max(d.Magnitude, 1), thickness or 1)
        f.Position = UDim2.fromOffset(
            math.floor((a.X + b.X) / 2) + 0.5, math.floor((a.Y + b.Y) / 2) + 0.5)
        f.Rotation = math.deg(math.atan2(d.Y, d.X))
        f.BackgroundColor3 = color
        f.Visible = true
    end

    local function add(plr)
        if plr == LocalPlayer or objs[plr] or not hasDrawing then return end
        objs[plr] = {
            box    = mkDraw("Square", { Thickness = 1, Filled = false, Visible = false, Transparency = 1 }),
            solid  = mkDraw("Square", { Thickness = 0, Filled = true, Visible = false }),
            name   = mkDraw("Text",   { Size = 13, Center = true, Outline = true, Visible = false }),
            dist   = mkDraw("Text",   { Size = 12, Center = true, Outline = true, Visible = false }),
            health = mkDraw("Square", { Thickness = 1, Filled = true, Visible = false }),
            tracer = lineFrame(),
            corners = nil, skel = nil, chams = nil, glowMats = nil,   -- created lazily when used
        }
    end
    local function remove(plr)
        local o = objs[plr]; if not o then return end
        for _, k in ipairs({ "box", "solid", "name", "dist", "health" }) do
            if o[k] then pcall(function() o[k]:Remove() end) end   -- Drawing objects
        end
        if o.tracer then pcall(function() o.tracer:Destroy() end) end
        if o.corners then for _, d in ipairs(o.corners) do pcall(function() d:Destroy() end) end end
        if o.skel then for _, d in ipairs(o.skel) do pcall(function() d:Destroy() end) end end
        if o.chams then pcall(function() o.chams:Destroy() end) end
        if o.glowMats then   -- restore any glow material overrides
            for p, mat in pairs(o.glowMats) do
                pcall(function() if p.Parent then p.Material = mat end end)
            end
            o.glowMats = nil
        end
        objs[plr] = nil
    end

    local function ensureCorners(o)
        if o.corners then return o.corners end
        local c = {}; for i = 1, 8 do c[i] = lineFrame() end
        o.corners = c; return c
    end
    local function ensureSkel(o)
        if o.skel then return o.skel end
        local s = {}; for i = 1, #BONES do s[i] = lineFrame() end
        o.skel = s; return s
    end
    local function ensureChams(o, char)   -- in-game Highlight
        -- key off the CURRENT character: on respawn the old char (and its
        -- Highlight) may linger, so checking Parent alone would keep adorning the
        -- dead body. Rebuild whenever the adornee no longer matches this char.
        if o.chams and o.chams.Adornee == char and o.chams.Parent then return o.chams end
        if o.chams then pcall(function() o.chams:Destroy() end) end
        local h = Instance.new("Highlight")
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Adornee = char
        h.Parent = char
        o.chams = h; return h
    end
    -- glow: make the CHARACTER glow so it conforms to the body, instead of a flat
    -- shape floating around them. Override each part's Material locally with
    -- ForceField (a soft energy glow on the real geometry) and remember the
    -- original material so it can be restored when chams turns off / the player
    -- leaves the closest-N set / on unload. Local-only -- not replicated.
    local GLOW_MATERIAL = Enum.Material.ForceField
    local function applyGlow(o, char)
        local mats = o.glowMats
        if not mats then mats = {}; o.glowMats = mats end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and mats[p] == nil then
                mats[p] = p.Material
                p.Material = GLOW_MATERIAL
            end
        end
    end
    local function clearGlow(o)
        if not o.glowMats then return end
        for p, mat in pairs(o.glowMats) do
            pcall(function() if p.Parent then p.Material = mat end end)
        end
        o.glowMats = nil
    end

    for _, p in ipairs(Players:GetPlayers()) do add(p) end
    track(Players.PlayerAdded:Connect(add))
    track(Players.PlayerRemoving:Connect(remove))

    function Esp.clear()   -- remove all ESP objects (used on unload)
        for plr in pairs(objs) do remove(plr) end
        pcall(function() espGui:Destroy() end)
    end

    local CHAMS_LIMIT = 32   -- the engine only renders ~32 Highlights at once

    track(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        local vp = cam.ViewportSize
        local mouse = UserInputService:GetMouseLocation()
        local myHRP = getHRP()

        -- chams render budget: Roblox only draws ~32 Highlights, so each frame
        -- pick the CHAMS_LIMIT players closest to us and only those get one (the
        -- rest are disabled). Without this, far/extra players silently fail to
        -- highlight -- which also looked like "respawned/joined players don't get
        -- chams" once the cap was already used up by everyone else.
        local chamsTop = nil
        if Esp.enabled and Esp.chams then
            chamsTop = {}
            local list = {}
            local myPos = myHRP and myHRP.Position
            for plr2 in pairs(objs) do
                if teamOk(plr2, Esp.teamCheck) then
                    local ch = aliveChar(plr2)
                    local h2 = ch and ch:FindFirstChild("HumanoidRootPart")
                    if h2 then
                        list[#list + 1] = { plr2, myPos and (h2.Position - myPos).Magnitude or 0 }
                    end
                end
            end
            table.sort(list, function(a, b) return a[2] < b[2] end)
            for i = 1, math.min(#list, CHAMS_LIMIT) do chamsTop[list[i][1]] = true end
        end

        for plr, o in pairs(objs) do
            if not o.box then continue end
            -- hide everything first
            o.box.Visible = false; o.solid.Visible = false; o.name.Visible = false
            o.dist.Visible = false; o.health.Visible = false; o.tracer.Visible = false
            if o.corners then for _, d in ipairs(o.corners) do d.Visible = false end end
            if o.skel then for _, d in ipairs(o.skel) do d.Visible = false end end

            local active = Esp.enabled and teamOk(plr, Esp.teamCheck)
            local char, hum = nil, nil
            if active then char, hum = aliveChar(plr) end
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            -- chams: closest 32 get an AlwaysOnTop Highlight + a soft glow aura
            if active and char and Esp.chams and chamsTop and chamsTop[plr] then
                local h = ensureChams(o, char)
                h.Enabled = true
                h.FillColor = Esp.chamsFill
                h.OutlineColor = Esp.chamsOutline
                h.FillTransparency = Esp.chamsTransparency
                h.OutlineTransparency = 0
                applyGlow(o, char)
            else
                if o.chams then o.chams.Enabled = false end
                clearGlow(o)
            end

            if active and hrp then
                local center, on = cam:WorldToViewportPoint(hrp.Position)
                local top = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                local bot = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                local height = math.max(math.abs(top.Y - bot.Y), 1)
                local width  = height * 0.55
                local x, y = center.X - width / 2, center.Y - height / 2

                -- tracer: drawn for EVERY target in front of the camera, including
                -- ones off-screen / not in view (the line just runs off the screen
                -- edge toward them). center.Z > 0 == in front; behind-camera points
                -- project inverted, so we skip those. 1px is the GUI floor (sub-1px
                -- frames render nothing), so this is as thin as a GUI line goes.
                if Esp.tracer and center.Z > 0 then
                    local origin
                    if Esp.tracerOrigin == "Top" then origin = Vector2.new(vp.X / 2, 0)
                    elseif Esp.tracerOrigin == "Mouse" then origin = mouse
                    else origin = Vector2.new(vp.X / 2, vp.Y) end
                    setLine(o.tracer, origin, Vector2.new(center.X, y + height), Esp.color, 1)
                end

                if on then
                    -- box: full outline / corner brackets / solid filled box
                    if not Esp.box then
                        -- box disabled; leave it hidden
                    elseif Esp.boxType == "Corner" then
                        local c = ensureCorners(o)
                        local cl = math.min(width, height) * 0.3
                        local pts = {
                            { x, y, x + cl, y }, { x, y, x, y + cl },                              -- TL
                            { x + width, y, x + width - cl, y }, { x + width, y, x + width, y + cl }, -- TR
                            { x, y + height, x + cl, y + height }, { x, y + height, x, y + height - cl }, -- BL
                            { x + width, y + height, x + width - cl, y + height }, { x + width, y + height, x + width, y + height - cl }, -- BR
                        }
                        for i, p in ipairs(pts) do
                            setLine(c[i], Vector2.new(p[1], p[2]), Vector2.new(p[3], p[4]), Esp.color)
                        end
                    elseif Esp.boxType == "Solid" then
                        -- filled translucent box (a Drawing.Square -- no flicker,
                        -- unlike the triangle-fan silhouette)
                        o.solid.Color = Esp.color
                        o.solid.Size = Vector2.new(width, height)
                        o.solid.Position = Vector2.new(x, y)
                        o.solid.Transparency = Esp.fillOpacity
                        o.solid.Visible = true
                    else
                        o.box.Color = Esp.color
                        o.box.Size = Vector2.new(width, height)
                        o.box.Position = Vector2.new(x, y)
                        o.box.Visible = true
                    end

                    if Esp.names then
                        o.name.Text = plr.Name; o.name.Color = Esp.color
                        o.name.Position = Vector2.new(center.X, y - 14); o.name.Visible = true
                    end
                    if Esp.distance then
                        local d = myHRP and math.floor((myHRP.Position - hrp.Position).Magnitude) or 0
                        o.dist.Text = tostring(d) .. "m"; o.dist.Color = Esp.color
                        o.dist.Position = Vector2.new(center.X, y + height + 2); o.dist.Visible = true
                    end
                    if Esp.health then
                        local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        o.health.Size = Vector2.new(2, height * hp)
                        o.health.Position = Vector2.new(x - 4, y + height * (1 - hp))
                        o.health.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(80, 255, 80), hp)
                        o.health.Visible = true
                    end
                end

                -- skeleton (per-part on-screen)
                if Esp.skeleton and char then
                    local s = ensureSkel(o)
                    for i, bone in ipairs(BONES) do
                        local p1, p2 = char:FindFirstChild(bone[1]), char:FindFirstChild(bone[2])
                        local line = s[i]
                        if p1 and p2 and line then
                            local a, aOn = cam:WorldToViewportPoint(p1.Position)
                            local b, bOn = cam:WorldToViewportPoint(p2.Position)
                            if aOn and bOn then
                                setLine(line, Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y), Esp.color)
                            end
                        end
                    end
                end
            end
        end
    end))
end

-- ============================================================
--  COMBAT  (Aimbot = camlock, Triggerbot)
-- ============================================================
local CombatPage = Window:Page({ Name = "Combat" })

local AimSub = CombatPage:SubPage({ Name = "Aimbot" })
do
    local Sec = AimSub:Section({ Name = "Camera lock", Side = 1 })
    local Enabled = Sec:Toggle({
        Name = "Enabled", Flag = "CamLockEnabled", Default = false,
        Callback = function(v) CamLock.enabled = v end,
    })
    Sec:Label({ Name = "Toggle key" }):Keybind({
        Name = "Aimlock",
        Flag = "CamLockKey", Mode = "Toggle", Default = Enum.KeyCode.E,
        Callback = function(state) Enabled:Set(state and true or false) end,
    })
    Sec:Slider({
        Name = "FOV", Flag = "CamLockFov", Min = 10, Max = 600, Default = 120, Decimals = 0,
        Callback = function(v) CamLock.fov = v end,
    })
    Sec:Slider({
        Name = "Smoothing", Flag = "CamLockSmoothing", Min = 0, Max = 95, Default = 50, Decimals = 0, Suffix = "%",
        Callback = function(v) CamLock.smoothing = v / 100 end,
    })
    Sec:Dropdown({
        Name = "Hit part", Flag = "CamLockPart", Default = "Head", Multi = false,
        Items = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
        Callback = function(v) CamLock.hitPart = (type(v) == "table" and v[1]) or v or "Head" end,
    })

    local Sec2 = AimSub:Section({ Name = "Checks", Side = 2 })
    Sec2:Toggle({ Name = "Sticky target", Flag = "CamLockSticky", Default = false,
        Callback = function(v) CamLock.sticky = v end })
    Sec2:Toggle({ Name = "Team check", Flag = "CamLockTeam", Default = true,
        Callback = function(v) CamLock.teamCheck = v end })
    Sec2:Toggle({ Name = "Visible check (walls)", Flag = "CamLockVisible", Default = false,
        Callback = function(v) CamLock.visibleCheck = v end })
    Sec2:Toggle({ Name = "Show FOV", Flag = "CamLockShowFov", Default = false,
        Callback = function(v) CamLock.showFov = v end })
end

local TrigSub = CombatPage:SubPage({ Name = "Triggerbot" })
do
    local Sec = TrigSub:Section({ Name = "Triggerbot", Side = 1 })
    local Enabled = Sec:Toggle({
        Name = "Enabled", Flag = "TrigEnabled", Default = false,
        Callback = function(v) Trig.enabled = v end,
    })
    Sec:Label({ Name = "Toggle key" }):Keybind({
        Name = "Triggerbot",
        Flag = "TrigKey", Mode = "Toggle", Default = Enum.KeyCode.G,
        Callback = function(state) Enabled:Set(state and true or false) end,
    })
    Sec:Slider({
        Name = "Click delay", Flag = "TrigDelay", Min = 0, Max = 1000, Default = 0, Decimals = 0, Suffix = "ms",
        Callback = function(v) Trig.delay = v end,
    })
    Sec:Toggle({ Name = "Team check", Flag = "TrigTeam", Default = true,
        Callback = function(v) Trig.teamCheck = v end })
end

-- ============================================================
--  DESYNC  (server sees a fake position; you stay put locally)
--   void / spin / velocity / custom -> spoof the HRP on Heartbeat (this is
--     what replicates), then restore your real CFrame each RenderStep so YOU
--     still see yourself correctly.
--   freeze -> RakNet: block the outbound physics packet (0x1B) so the server
--     stops getting position updates. Needs an executor with a `raknet` API.
-- ============================================================
local Desync = {
    enabled = false, method = "Void",
    voidMin = 5000, voidMax = 20000,
    spinSpeed = 2, velMag = 16384,
    customX = 0, customY = 0, customZ = 0,
}
do
    local RESTORE = "WH_DesyncRestore"
    local realCF, realLV, realAV
    local spinAngle = 0

    -- raknet state lives on getgenv so the hook closure survives reloads
    getgenv()._WH_DESYNC = getgenv()._WH_DESYNC or {}
    local SHARED = getgenv()._WH_DESYNC

    local function randVoid()
        local function axis()
            local mag = Desync.voidMin + math.random() * math.max(Desync.voidMax - Desync.voidMin, 0)
            return (math.random() < 0.5) and -mag or mag
        end
        return Vector3.new(axis(), axis(), axis())
    end

    local function applySpoof(hrp)
        local m = Desync.method
        if m == "Void" then
            hrp.CFrame = CFrame.new(randVoid())
        elseif m == "Spin" then
            spinAngle = (spinAngle + Desync.spinSpeed) % 360
            hrp.CFrame = hrp.CFrame * CFrame.Angles(
                math.rad(spinAngle), math.rad(spinAngle * 2), math.rad(spinAngle * 0.5))
        elseif m == "Velocity" then
            hrp.AssemblyLinearVelocity = Vector3.one * Desync.velMag
        elseif m == "Custom" then
            local rot = hrp.CFrame - hrp.CFrame.Position
            hrp.CFrame = CFrame.new(Desync.customX, Desync.customY, Desync.customZ) * rot
        end
    end

    -- ---- RakNet freeze ----
    local function findRaknet()
        local r = rawget(getgenv(), "raknet")
        if r then return r end
        local ok, v = pcall(function() return raknet end)
        if ok then return v end
        return nil
    end
    local function ensureRaknetHook()
        if SHARED.hookInstalled then return true end
        local r = findRaknet()
        if not r or not r.add_send_hook then return false end
        SHARED.hookFn = function(packet)
            if not SHARED.freeze then return end
            local id; pcall(function() id = packet.PacketId end)
            if id == 0x1B then     -- outbound physics replication
                pcall(function() packet:SetCanBeSent(false) end)
                pcall(function() packet:Drop() end)
                return false
            end
        end
        local ok = pcall(function() r.add_send_hook(SHARED.hookFn) end)
        if ok then SHARED.hookInstalled = true end
        return ok
    end

    -- ---- heartbeat spoof + renderstep restore (non-freeze methods) ----
    track(RunService.Heartbeat:Connect(function()
        if not Desync.enabled or Desync.method == "Freeze" then return end
        local hrp = getHRP(); if not hrp then return end
        realCF, realLV, realAV = hrp.CFrame, hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity
        pcall(applySpoof, hrp)
    end))

    RunService:BindToRenderStep(RESTORE, Enum.RenderPriority.First.Value, function()
        if not Desync.enabled or Desync.method == "Freeze" then return end
        local hrp = getHRP(); if not hrp or not realCF then return end
        pcall(function()
            if Desync.method ~= "Velocity" then hrp.CFrame = realCF end
            if realLV then hrp.AssemblyLinearVelocity = realLV end
            if realAV then hrp.AssemblyAngularVelocity = realAV end
        end)
    end)

    local function removeRaknetHook()
        if SHARED.hookInstalled and SHARED.hookFn then
            local r = findRaknet()
            if r and r.remove_send_hook then pcall(function() r.remove_send_hook(SHARED.hookFn) end) end
        end
        SHARED.hookInstalled = false
        SHARED.hookFn = nil
    end

    -- restore your REAL position (fixes being left at the fake spot on disable)
    local function restoreReal()
        local hrp = getHRP()
        if hrp and realCF then
            pcall(function()
                hrp.CFrame = realCF
                if realLV then hrp.AssemblyLinearVelocity = realLV end
                if realAV then hrp.AssemblyAngularVelocity = realAV end
            end)
        end
    end

    -- Enabled drives the heartbeat-spoof methods ONLY (void/spin/velocity/custom);
    -- it never touches raknet.
    function Desync.setEnabled(on)
        Desync.enabled = on and true or false
        if not Desync.enabled then restoreReal() end
    end
    function Desync.setMethod(m) Desync.method = m end

    -- Freeze is the ONLY raknet mode, behind its own explicit toggle. RakNet can
    -- get accounts terminated, so the hook is only installed while this is on and
    -- removed the moment it's turned off. Returns false if raknet is unavailable
    -- so the UI can flip the toggle back off.
    function Desync.setFreeze(on)
        if on then
            if not ensureRaknetHook() then SHARED.freeze = false; return false end
            SHARED.freeze = true
            return true
        end
        SHARED.freeze = false
        removeRaknetHook()
        return true
    end

    function Desync.stop()
        Desync.setEnabled(false)   -- restores real position
        SHARED.freeze = false
        removeRaknetHook()
        pcall(function() RunService:UnbindFromRenderStep(RESTORE) end)
    end
end

-- ============================================================
--  PLAYER  (working universal movement)
-- ============================================================
local PlayerPage = Window:Page({ Name = "Player" })
local Move = PlayerPage:SubPage({ Name = "Movement" })

local SpeedSec = Move:Section({ Name = "Speed", Side = 1 })
SpeedSec:Toggle({ Name = "WalkSpeed", Flag = "WalkSpeedEnabled", Default = false,
    Callback = function(v) Movement.setWalkSpeed(v) end })
SpeedSec:Slider({ Name = "WalkSpeed amount", Flag = "WalkSpeedValue", Min = 16, Max = 500, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setWalkSpeedValue(v) end })
SpeedSec:Toggle({ Name = "CFrame speed", Flag = "CFrameEnabled", Default = false,
    Callback = function(v) Movement.setCFrame(v) end })
SpeedSec:Slider({ Name = "CFrame multiplier", Flag = "CFrameValue", Min = 1, Max = 10, Default = 2, Decimals = 1, Suffix = "x",
    Callback = function(v) Movement.setCFrameValue(v) end })

local JumpSec = Move:Section({ Name = "Jump", Side = 1 })
JumpSec:Toggle({ Name = "JumpPower", Flag = "JumpEnabled", Default = false,
    Callback = function(v) Movement.setJump(v) end })
JumpSec:Slider({ Name = "JumpPower amount", Flag = "JumpValue", Min = 50, Max = 500, Default = 50, Decimals = 0,
    Callback = function(v) Movement.setJumpValue(v) end })
JumpSec:Toggle({ Name = "Infinite jump", Flag = "InfJumpEnabled", Default = false,
    Callback = function(v) Movement.setInfJump(v) end })

local FlySec = Move:Section({ Name = "Fly", Side = 2 })
local FlyToggle = FlySec:Toggle({ Name = "Fly", Flag = "FlyEnabled", Default = false,
    Callback = function(v) Movement.setFly(v) end })
FlySec:Slider({ Name = "Fly speed", Flag = "FlyValue", Min = 10, Max = 300, Default = 60, Decimals = 0,
    Callback = function(v) Movement.setFlyValue(v) end })
FlySec:Label({ Name = "Fly toggle key" }):Keybind({
    Name = "Fly",
    Flag = "FlyKey", Mode = "Toggle", Default = Enum.KeyCode.F,
    Callback = function(state) FlyToggle:Set(state and true or false) end })

local UtilSec = Move:Section({ Name = "Utility", Side = 2 })
UtilSec:Toggle({ Name = "Noclip", Flag = "NoclipEnabled", Default = false,
    Callback = function(v) Movement.setNoclip(v) end })

-- ---- Player > Desync subpage ----
local DesyncSub = PlayerPage:SubPage({ Name = "Desync" })
do
    local Sec = DesyncSub:Section({ Name = "Desync", Side = 1 })
    local showFor, enabledToggle, freezeToggle, freezeWarn  -- forward-declared

    Sec:Dropdown({
        Name = "Method", Flag = "DesyncMethod", Default = "Void", Multi = false,
        Items = { "Void", "Spin", "Velocity", "Freeze", "Custom" },
        Callback = function(v)
            local m = (type(v) == "table" and v[1]) or v or "Void"
            -- switching method = clean slate: turn both toggles off so a spoof
            -- (or raknet) never keeps running across a method change
            pcall(function() enabledToggle:Set(false) end)
            pcall(function() freezeToggle:Set(false) end)
            Desync.setMethod(m)
            if showFor then showFor(m) end
        end,
    })

    -- Enabled = heartbeat-spoof methods (void/spin/velocity/custom). No raknet.
    enabledToggle = Sec:Toggle({ Name = "Enabled", Flag = "DesyncEnabled", Default = false,
        Callback = function(v) Desync.setEnabled(v) end })

    -- RakNet freeze = the ONLY raknet path, behind its own explicit toggle.
    freezeToggle = Sec:Toggle({ Name = "RakNet freeze", Flag = "DesyncFreeze", Default = false,
        Callback = function(v)
            local ok = Desync.setFreeze(v)
            if v and not ok then
                Library:Notification("RakNet not available in this executor", 3, Library.Theme["Risky"])
                pcall(function() freezeToggle:Set(false) end)
            end
        end })
    freezeWarn = Sec:Label({ Name = "RakNet -- detection/ban risk." })

    -- value controls (shown only for their method)
    local voidMin = Sec:Slider({ Name = "Void min", Flag = "DesyncVoidMin",
        Min = 500, Max = 1000000, Default = 5000, Decimals = 0, Suffix = " studs",
        Callback = function(v) Desync.voidMin = v end })
    local voidMax = Sec:Slider({ Name = "Void max", Flag = "DesyncVoidMax",
        Min = 500, Max = 1000000, Default = 20000, Decimals = 0, Suffix = " studs",
        Callback = function(v) Desync.voidMax = v end })
    local spin = Sec:Slider({ Name = "Spin speed", Flag = "DesyncSpin",
        Min = 1, Max = 90, Default = 2, Decimals = 0,
        Callback = function(v) Desync.spinSpeed = v end })
    local vel = Sec:Slider({ Name = "Velocity magnitude", Flag = "DesyncVel",
        Min = 50, Max = 16384, Default = 16384, Decimals = 0,
        Callback = function(v) Desync.velMag = v end })
    local cx = Sec:Textbox({ Name = "Custom X", Flag = "DesyncX", Default = "0",
        Numeric = true, Placeholder = "X", Callback = function(v) Desync.customX = tonumber(v) or 0 end })
    local cy = Sec:Textbox({ Name = "Custom Y", Flag = "DesyncY", Default = "0",
        Numeric = true, Placeholder = "Y", Callback = function(v) Desync.customY = tonumber(v) or 0 end })
    local cz = Sec:Textbox({ Name = "Custom Z", Flag = "DesyncZ", Default = "0",
        Numeric = true, Placeholder = "Z", Callback = function(v) Desync.customZ = tonumber(v) or 0 end })

    local VALUE_CONTROLS = {
        Void = { voidMin, voidMax }, Spin = { spin }, Velocity = { vel }, Custom = { cx, cy, cz },
    }
    function showFor(method)
        local isFreeze = (method == "Freeze")
        pcall(function() enabledToggle:SetVisibility(not isFreeze) end)
        pcall(function() freezeToggle:SetVisibility(isFreeze) end)
        pcall(function() freezeWarn:SetVisibility(isFreeze) end)
        for name, list in pairs(VALUE_CONTROLS) do
            for _, el in ipairs(list) do
                pcall(function() el:SetVisibility(name == method) end)
            end
        end
    end

    showFor("Void")   -- initial visibility matches the default method
end

-- ============================================================
--  VISUALS  (ESP)
-- ============================================================
local VisualsPage = Window:Page({ Name = "Visuals" })
local EspSub = VisualsPage:SubPage({ Name = "ESP" })
do
    local Sec = EspSub:Section({ Name = "Player ESP", Side = 1 })
    if not hasDrawing then
        Sec:Label({ Name = "ESP needs a Drawing-capable executor." })
    end
    Sec:Toggle({ Name = "Enabled", Flag = "EspEnabled", Default = false,
        Callback = function(v) Esp.enabled = v end })
    Sec:Toggle({ Name = "Box", Flag = "EspBox", Default = true,
        Callback = function(v) Esp.box = v end })
    Sec:Dropdown({ Name = "Box style", Flag = "EspBoxType", Default = "Full", Multi = false,
        Items = { "Full", "Corner", "Solid" },
        Callback = function(v) Esp.boxType = (type(v) == "table" and v[1]) or v or "Full" end })
    Sec:Toggle({ Name = "Names", Flag = "EspNames", Default = false,
        Callback = function(v) Esp.names = v end })
    Sec:Toggle({ Name = "Distance", Flag = "EspDistance", Default = false,
        Callback = function(v) Esp.distance = v end })
    Sec:Toggle({ Name = "Health bar", Flag = "EspHealth", Default = false,
        Callback = function(v) Esp.health = v end })
    Sec:Toggle({ Name = "Tracer", Flag = "EspTracer", Default = false,
        Callback = function(v) Esp.tracer = v end })
    Sec:Toggle({ Name = "Skeleton", Flag = "EspSkeleton", Default = false,
        Callback = function(v) Esp.skeleton = v end })
    Sec:Toggle({ Name = "Chams", Flag = "EspChams", Default = false,
        Callback = function(v) Esp.chams = v end })

    local Sec2 = EspSub:Section({ Name = "Options", Side = 2 })
    Sec2:Toggle({ Name = "Team check", Flag = "EspTeam", Default = false,
        Callback = function(v) Esp.teamCheck = v end })
    Sec2:Dropdown({ Name = "Tracer origin", Flag = "EspTracerOrigin", Default = "Bottom", Multi = false,
        Items = { "Bottom", "Top", "Mouse" },
        Callback = function(v) Esp.tracerOrigin = (type(v) == "table" and v[1]) or v or "Bottom" end })
    Sec2:Label({ Name = "ESP color" }):Colorpicker({
        Flag = "EspColor", Default = Color3.fromRGB(200, 183, 247),
        Callback = function(c) Esp.color = c end })
    Sec2:Slider({ Name = "Solid box opacity", Flag = "EspFillOp",
        Min = 0, Max = 100, Default = 40, Decimals = 0, Suffix = "%",
        Callback = function(v) Esp.fillOpacity = v / 100 end })
    Sec2:Label({ Name = "Chams fill" }):Colorpicker({
        Flag = "EspChamsFill", Default = Color3.fromRGB(200, 183, 247),
        Callback = function(c) Esp.chamsFill = c end })
    Sec2:Label({ Name = "Chams outline" }):Colorpicker({
        Flag = "EspChamsOutline", Default = Color3.fromRGB(255, 255, 255),
        Callback = function(c) Esp.chamsOutline = c end })
    Sec2:Slider({ Name = "Chams opacity", Flag = "EspChamsOp",
        Min = 0, Max = 100, Default = 40, Decimals = 0, Suffix = "%",
        Callback = function(v) Esp.chamsTransparency = 1 - (v / 100) end })
end

-- ============================================================
--  PLAYER TARGET ACTIONS  (operate on the player selected in the
--  floating Players widget): Goto / Fling / View / Follow.
-- ============================================================
local PlayerActions = {}

function PlayerActions.gotoPlayer(plr)
    local tc = plr.Character; local th = tc and tc:FindFirstChild("HumanoidRootPart")
    local h = getHRP()
    if th and h then h.CFrame = th.CFrame * CFrame.new(0, 0, 3) end
end

-- velocity-glue touch fling: snap behind the target with huge velocity for ~1.5s
function PlayerActions.fling(plr)
    task.spawn(function()
        local conn
        conn = RunService.Heartbeat:Connect(function()
            local h = getHRP()
            local tc = plr.Character; local th = tc and tc:FindFirstChild("HumanoidRootPart")
            if not h or not th then return end
            h.CFrame = th.CFrame * CFrame.new(0, 0, 1)
            h.AssemblyLinearVelocity = Vector3.one * 9e4
        end)
        local deadline = tick() + 1.5
        while tick() < deadline do
            if not plr.Character or not getChar() then break end
            task.wait()
        end
        if conn then conn:Disconnect() end
        local h = getHRP()
        if h then h.AssemblyLinearVelocity = Vector3.zero; h.AssemblyAngularVelocity = Vector3.zero end
    end)
end

do  -- View (spectate) -- toggles on the same target
    local viewing, prevSubject, charConn = nil, nil, nil
    function PlayerActions.view(plr)
        local cam = Workspace.CurrentCamera
        if charConn then charConn:Disconnect(); charConn = nil end
        if viewing == plr then
            cam.CameraSubject = getHum() or prevSubject
            viewing = nil
            return
        end
        if not viewing then prevSubject = cam.CameraSubject end
        viewing = plr
        local function apply()
            local tc = plr.Character; local hum = tc and tc:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum end
        end
        apply()
        charConn = plr.CharacterAdded:Connect(function()
            task.wait(0.2); if viewing == plr then apply() end
        end)
    end
    function PlayerActions.stopView()
        if charConn then charConn:Disconnect(); charConn = nil end
        if viewing then
            Workspace.CurrentCamera.CameraSubject = getHum() or prevSubject
            viewing = nil
        end
    end
end

do  -- Follow (pathfinding) -- toggles on the same target
    local PathfindingService = game:GetService("PathfindingService")
    local target, path = nil, nil
    function PlayerActions.stopFollow() target = nil end
    function PlayerActions.follow(plr)
        if target == plr then target = nil; return end
        target = plr
        path = PathfindingService:CreatePath({
            AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
            AgentJumpHeight = 7.2, AgentMaxSlope = 45,
        })
        task.spawn(function()
            local t = plr
            while target == t do
                local hum, hrp = getHum(), getHRP()
                local tc = t.Character; local thrp = tc and tc:FindFirstChild("HumanoidRootPart")
                if not (hum and hrp and thrp) then task.wait(0.2); continue end
                if (hrp.Position - thrp.Position).Magnitude < 8 then
                    pcall(function() hum:MoveTo(thrp.Position) end); task.wait(0.1); continue
                end
                local ok = pcall(function() path:ComputeAsync(hrp.Position, thrp.Position) end)
                if ok and path.Status == Enum.PathStatus.Success then
                    local wp = path:GetWaypoints()[2]
                    if wp then
                        if wp.Action == Enum.PathWaypointAction.Jump then pcall(function() hum.Jump = true end) end
                        pcall(function() hum:MoveTo(wp.Position) end)
                    end
                    task.wait(0.1)
                else
                    pcall(function() hum:MoveTo(thrp.Position) end); task.wait(0.1)
                end
            end
        end)
    end
end

-- wire the buttons onto the floating Players widget
do
    local PL = ctx.Playerlist
    if PL and PL.AddAction then
        local function needTarget(fn)
            return function(plr)
                if not plr then
                    Library:Notification("Select a player first", 2, Library.Theme["Accent"])
                    return
                end
                fn(plr)
            end
        end
        PL:AddAction("Goto",   needTarget(PlayerActions.gotoPlayer))
        PL:AddAction("Fling",  needTarget(PlayerActions.fling))
        PL:AddAction("View",   needTarget(PlayerActions.view))
        PL:AddAction("Follow", needTarget(PlayerActions.follow))
    end
end

-- ============================================================
--  TEARDOWN
--  Turn EVERYTHING off and disconnect every feature connection. Runs when the
--  GUI unloads (hooked to Library.OnExit, fired by Library:Exit / the Unload
--  button) and when the loader re-executes (it calls the previous instance's
--  disableAll). This is what stops you being stuck in cframe/camlock/etc. after
--  a reload.
-- ============================================================
local function disableAll()
    -- reset state-changing toggles (walkspeed->16, collide->true, velocity 0, ...)
    pcall(Movement.setWalkSpeed, false)
    pcall(Movement.setJump, false)
    pcall(Movement.setCFrame, false)
    pcall(Movement.setFly, false)
    pcall(Movement.setNoclip, false)
    pcall(Movement.setInfJump, false)
    -- combat / visuals: flag off (their connections are disconnected below)
    CamLock.enabled = false
    Trig.enabled = false
    Esp.enabled, Esp.names, Esp.distance, Esp.health = false, false, false, false
    pcall(function() if Desync.stop then Desync.stop() end end)
    -- player actions
    pcall(function() if PlayerActions.stopFollow then PlayerActions.stopFollow() end end)
    pcall(function() if PlayerActions.stopView then PlayerActions.stopView() end end)
    pcall(function() if Esp.clear then Esp.clear() end end)
    -- disconnect every tracked connection
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}
end

-- Fire teardown on unload (Library:Exit calls Library.OnExit) and expose it so
-- the loader can tear this instance down before re-executing.
Library.OnExit = disableAll
if getgenv then
    local g = getgenv()
    if g.WH then g.WH.disableAll = disableAll end
end
