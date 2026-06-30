-- ============================================================
--  games/11379739543.lua  --  Timebomb Duels [Alpha]
--
--  Bomb-tag duels. Movement is CLIENT-AUTHORITATIVE here: ReplicationTestEnabled
--  is true and CharacterReplicatorController streams LocalPlayer's own CFrame to
--  the server every frame (CharacterReplicator.UpdateCFrame:FireServer). So the
--  universal shell's fly / speed / noclip / teleport all replicate and stick --
--  we just load universal and let it drive movement + ESP.
--
--  Game-specific additions (Timebomb page):
--    Bomb holder ESP -- highlight whoever currently holds the bomb + a label.
--    Auto-tag        -- when WE hold the bomb, reach the nearest enemy (teleport
--                       via the client-auth CFrame) to pass it before it blows.
--
--  PROVISIONAL: the exact "who holds the bomb" marker and the pass action are not
--  yet captured from a live duel. getHolder() / passBomb() below use best-guess
--  heuristics and are the ONLY two things to revise once the remote-spy capture is
--  in -- everything else (UI, highlight, reach loop) is final and no-ops safely
--  until a holder resolves.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local MainPage = Window:Page({ Name = "Main" })

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end
local function charHRP(plr)
    local c = plr and plr.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function myHRP() return charHRP(LocalPlayer) end

-- ============================================================
--  Holder resolution  (CONFIRMED live 2026-06-30)
-- ============================================================
-- The bomb is a Tool literally named "Bomb" parented to the holder's character
-- (characters live under Workspace.Characters.<name>, and player.Character resolves
-- to them). It re-parents to whoever currently holds it, so this tracks passes.
local function getHolder()
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p.Character
        local bomb = ch and ch:FindFirstChild("Bomb")
        if bomb and bomb:IsA("Tool") then return p, bomb end
    end
    return nil
end
local function iHaveBomb()
    local ch = LocalPlayer.Character
    local bomb = ch and ch:FindFirstChild("Bomb")
    return bomb ~= nil and bomb:IsA("Tool")
end
-- nearest living enemy's HRP (used by look / jiggle / auto-tag)
local function nearestEnemyHRP()
    local me = myHRP(); if not me then return nil end
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local hrp = charHRP(p)
            local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (hrp.Position - me.Position).Magnitude
                if not bestD or d < bestD then best, bestD = hrp, d end
            end
        end
    end
    return best
end
-- passBomb(targetHRP): pass is TOUCH-based (the bomb Tool re-parents on contact), so
-- the auto-tag reach loop teleporting onto the target does the work. No remote needed.
local function passBomb(_targetHRP) end

-- ============================================================
--  BOMB HOLDER ESP  -- highlight the current holder + a floating label
-- ============================================================
local holderEsp = false
do
    local hl = Instance.new("Highlight")
    hl.Name = "\0"; hl.FillTransparency = 0.5; hl.OutlineTransparency = 0
    hl.FillColor = Color3.fromRGB(255, 70, 70); hl.OutlineColor = Color3.fromRGB(255, 200, 60)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Enabled = false
    pcall(function() hl.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "\0"; billboard.Size = UDim2.fromOffset(180, 28)
    billboard.AlwaysOnTop = true; billboard.StudsOffset = Vector3.new(0, 3.2, 0); billboard.Enabled = false
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold; label.TextSize = 14
    label.TextColor3 = Color3.fromRGB(255, 90, 90); label.TextStrokeTransparency = 0.3
    label.Text = "BOMB"; label.Parent = billboard
    pcall(function() billboard.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

    track(RunService.RenderStepped:Connect(function()
        if not holderEsp then
            if hl.Enabled then hl.Enabled = false; hl.Adornee = nil end
            if billboard.Enabled then billboard.Enabled = false; billboard.Adornee = nil end
            return
        end
        local holder = getHolder()
        local char = holder and holder.Character
        if char then
            hl.Adornee = char; hl.Enabled = true
            local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
            billboard.Adornee = head; billboard.Enabled = head ~= nil
            label.Text = (holder == LocalPlayer) and "YOU HAVE THE BOMB" or ("BOMB: " .. holder.Name)
        else
            hl.Enabled = false; hl.Adornee = nil
            billboard.Enabled = false; billboard.Adornee = nil
        end
    end))
end

-- ============================================================
--  AUTO-TAG  -- when WE hold the bomb, reach the nearest enemy to pass it.
--  Uses the client-authoritative CFrame: teleport adjacent to the target (which
--  passes a touch-based bomb), then optionally snap back so we don't strand.
-- ============================================================
local autoTag, tagCD, tagReturn = false, 0.5, true
do
    local lastTag = 0
    track(RunService.Heartbeat:Connect(function()
        if not autoTag then return end
        if os.clock() - lastTag < (tagCD or 0.5) then return end
        if not iHaveBomb() then return end                -- only when WE are it
        local me = myHRP(); if not me then return end
        local target = nearestEnemyHRP(); if not target then return end
        lastTag = os.clock()
        local home = me.CFrame
        local rot = me.CFrame - me.CFrame.Position
        me.CFrame = CFrame.new(target.Position) * rot * CFrame.new(0, 0, 2.5)  -- press up against them
        passBomb(target)
        if tagReturn then
            task.delay(0.12, function()
                local h = myHRP()
                if h and autoTag then h.CFrame = home end
            end)
        end
    end))
end

-- ============================================================
--  SPEED BOOST  -- subtle CFrame-based speed multiplier. Movement is client-auth
--  (we stream our own CFrame), so nudging the HRP forward along its current
--  horizontal velocity each frame makes us move `mult` times faster and replicates.
-- ============================================================
local speedOn, speedMult = false, 1.05

-- ============================================================
--  BOMB JUKE  -- when WE hold the bomb: face AWAY from the nearest enemy (back
--  turned); while the aim key is held, face them instead; and optionally jiggle
--  left/right relative to them with randomized amplitude + speed (human-ish juke).
-- ============================================================
local lookAway, aimHeld, jiggleOn = false, false, false
local lookSmooth = 12                    -- rotation easing rate (higher = snappier)
local predictTime = 0.08                 -- s of target-velocity lead (server pos lags)
local jAmpMin, jAmpMax = 2, 5            -- studs
local jSpdMin, jSpdMax = 6, 12           -- oscillation rate (rad/s)
local jPhase, jAmp, jSpd, jLast = 0, 3.5, 9, 0
local function rerollJiggle()
    jAmp = jAmpMin + math.random() * math.max(0, jAmpMax - jAmpMin)
    jSpd = jSpdMin + math.random() * math.max(0, jSpdMax - jSpdMin)
    jPhase, jLast = 0, 0
end
-- robust target velocity: replicated AssemblyLinearVelocity, or a position-delta if
-- that reads ~0 (other chars are CFrame-streamed, so physics velocity can be stale).
local _tvLast, _tvPos, _tvT
local function targetVel(tgt)
    local v = tgt.AssemblyLinearVelocity
    local now = os.clock()
    if _tvLast == tgt and _tvT and now > _tvT + 1e-3 then
        local dv = (tgt.Position - _tvPos) / (now - _tvT)
        if dv.Magnitude > v.Magnitude then v = dv end
    end
    _tvLast, _tvPos, _tvT = tgt, tgt.Position, now
    return v
end

track(RunService.Heartbeat:Connect(function(dt)
    local hrp = myHRP(); if not hrp then return end
    local newCF = hrp.CFrame

    -- subtle speed boost (always while on)
    if speedOn and speedMult > 1.0001 then
        local v = hrp.AssemblyLinearVelocity
        newCF = newCF + Vector3.new(v.X, 0, v.Z) * (speedMult - 1) * dt
    end

    -- bomb juke (only while WE hold the bomb)
    if (lookAway or aimHeld or jiggleOn) and iHaveBomb() then
        local tgt = nearestEnemyHRP()
        if tgt then
            local pos = newCF.Position
            -- lead the aim by the target's velocity -- their replicated pos lags their
            -- real (server) pos, so predicting forward lands the facing/pass correctly
            local pred = tgt.Position + targetVel(tgt) * predictTime
            local flat = Vector3.new(pred.X, pos.Y, pred.Z)
            local dir = flat - pos
            dir = (dir.Magnitude > 0.05) and dir.Unit or newCF.LookVector

            if jiggleOn then
                jPhase = jPhase + jSpd * dt
                if jPhase >= math.pi * 2 then rerollJiggle() end
                local right = Vector3.new(dir.Z, 0, -dir.X)   -- horizontal perpendicular
                local L = jAmp * math.sin(jPhase)
                pos = pos + right * (L - jLast); jLast = L
            end

            local lookDir = aimHeld and dir or (lookAway and -dir or nil)
            if lookDir then
                -- ease rotation toward the look direction instead of snapping each frame
                local alpha = 1 - math.exp(-dt * lookSmooth)
                newCF = newCF.Rotation:Lerp(CFrame.lookAt(Vector3.zero, lookDir), alpha) + pos
            else
                newCF = newCF.Rotation + pos                   -- keep facing, apply jiggle
            end
        end
    end

    if newCF ~= hrp.CFrame then hrp.CFrame = newCF end
end))

-- ============================================================
--  UI  (Timebomb subpage -- created before universal so it's the first sub-tab)
-- ============================================================
do
    local Sub = MainPage:SubPage({ Name = "Timebomb" })

    local SecB = Sub:Section({ Name = "Bomb", Side = 1 })
    SecB:Toggle({ Name = "Highlight bomb holder", Flag = "TBD_HolderEsp", Default = false,
        Callback = function(v) holderEsp = v end })

    local SecM = Sub:Section({ Name = "Movement", Side = 1 })
    SecM:Toggle({ Name = "Speed boost (CFrame)", Flag = "TBD_SpeedOn", Default = false,
        Callback = function(v) speedOn = v end })
    SecM:Slider({ Name = "Speed", Flag = "TBD_SpeedMult", Min = 102, Max = 110, Default = 105, Decimals = 0, Suffix = " %",
        Callback = function(v) speedMult = v / 100 end })
    SecM:Label({ Name = "very slight -- 102-110% of normal, replicates" })

    local SecT = Sub:Section({ Name = "Auto-tag", Side = 2 })
    SecT:Toggle({ Name = "Auto-tag (reach nearest)", Flag = "TBD_AutoTag", Default = false,
        Callback = function(v) autoTag = v end })
    SecT:Slider({ Name = "Tag cooldown", Flag = "TBD_TagCD", Min = 100, Max = 2000, Default = 500, Decimals = 0, Suffix = " ms",
        Callback = function(v) tagCD = v / 1000 end })
    SecT:Toggle({ Name = "Return after tag", Flag = "TBD_TagReturn", Default = true,
        Callback = function(v) tagReturn = v end })

    local SecJ = Sub:Section({ Name = "Bomb juke (while holding)", Side = 2 })
    SecJ:Toggle({ Name = "Look away from nearest", Flag = "TBD_LookAway", Default = false,
        Callback = function(v) lookAway = v end })
    SecJ:Label({ Name = "Aim-at key (hold)" }):Keybind({
        Name = "Look at nearest", Flag = "TBD_AimKey", Mode = "Hold", Default = Enum.KeyCode.E,
        Callback = function(state) aimHeld = state end })
    SecJ:Slider({ Name = "Smoothness", Flag = "TBD_Smooth", Min = 3, Max = 30, Default = 12, Decimals = 0,
        Callback = function(v) lookSmooth = v end })
    SecJ:Slider({ Name = "Prediction", Flag = "TBD_Predict", Min = 0, Max = 300, Default = 80, Decimals = 0, Suffix = " ms",
        Callback = function(v) predictTime = v / 1000 end })
    SecJ:Toggle({ Name = "Jiggle left/right", Flag = "TBD_Jiggle", Default = false,
        Callback = function(v) jiggleOn = v; if v then rerollJiggle() end end })
    SecJ:Slider({ Name = "Jiggle min", Flag = "TBD_JigAmpMin", Min = 1, Max = 15, Default = 2, Decimals = 1, Suffix = " studs",
        Callback = function(v) jAmpMin = v end })
    SecJ:Slider({ Name = "Jiggle max", Flag = "TBD_JigAmpMax", Min = 1, Max = 15, Default = 5, Decimals = 1, Suffix = " studs",
        Callback = function(v) jAmpMax = v end })
    SecJ:Slider({ Name = "Jiggle speed min", Flag = "TBD_JigSpdMin", Min = 2, Max = 25, Default = 6, Decimals = 0,
        Callback = function(v) jSpdMin = v end })
    SecJ:Slider({ Name = "Jiggle speed max", Flag = "TBD_JigSpdMax", Min = 2, Max = 25, Default = 12, Decimals = 0,
        Callback = function(v) jSpdMax = v end })
    SecJ:Label({ Name = "only active while YOU hold the bomb" })
end

-- universal shell after our page so Timebomb stays the first sub-tab (movement + ESP)
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    holderEsp, autoTag = false, false
    speedOn, lookAway, aimHeld, jiggleOn = false, false, false, false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
end
do
    local g = (getgenv and getgenv()) or nil
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full() pcall(cleanup); if prev then pcall(prev) end end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
