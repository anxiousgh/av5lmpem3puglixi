-- ============================================================
--  games/13772394625.lua  --  Blade Ball  (Wiggity.)
--
--  Ball-tag game: a ball ("realBall") locks onto a player and flies at them;
--  the target must PARRY in a timing window or die, deflecting it to someone else.
--
--  Mechanic (decoded live 2026-06-30):
--    * The real ball is a BasePart in workspace.Balls with attribute realBall=true
--      and attribute target = the targeted player's *Name* (e.g. "MK2nttt").
--    * Parrying is a single argless remote:
--          ReplicatedStorage.Remotes.ParryAttempt:FireServer()
--      (confirmed in Controllers.SwordsController -- ParryButtonPress.Event just
--       calls ParryAttempt:FireServer(); the input path f4()->f12 only adds the
--       swing animation. Firing the remote is the whole parry.)
--    * No-arg; the server validates the ball is ours + in range at fire time.
--
--  NOTE: the character carries an AntiExploitLoaded=true attribute -- this game
--  ships an anti-cheat. Auto-parry fires the EXACT native remote and is tightly
--  gated (only when a real ball is targeting us AND within a predicted window,
--  with a retry cooldown) so it never machine-guns parries with no ball in range
--  (which is what trips the failed-parry lockout / heuristics). Movement exploits
--  from the universal shell are higher-risk here -- use at your own discretion.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end
local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local ParryRemote do
    local R = ReplicatedStorage:FindFirstChild("Remotes")
    ParryRemote = R and R:FindFirstChild("ParryAttempt")
end
local function fireParry()
    if ParryRemote then pcall(function() ParryRemote:FireServer() end) end
end

-- ============================================================
--  BALL HELPERS
-- ============================================================
-- The real ball lives in workspace.Balls (matches) or workspace.TrainingBalls
-- (practice). Abilities can spawn decoy balls with realBall=false -> we ignore them.
local function getRealBall()
    for _, name in ipairs({ "Balls", "TrainingBalls" }) do
        local f = workspace:FindFirstChild(name)
        if f then
            for _, b in ipairs(f:GetChildren()) do
                if b:IsA("BasePart") and b:GetAttribute("realBall") then return b end
            end
        end
    end
    return nil
end
local function ballTargetName(ball)
    return ball:GetAttribute("target")
end
local function targetsMe(ball)
    local t = ballTargetName(ball)
    return t ~= nil and (t == LocalPlayer.Name or t == LocalPlayer.DisplayName)
end
-- speed: prefer physics velocity, fall back to per-frame position delta (in case a
-- ball is ever CFrame-driven and reports ~0 AssemblyLinearVelocity).
local lastPos, lastT
local function ballSpeed(ball)
    local v   = ball.AssemblyLinearVelocity.Magnitude
    local now = os.clock()
    if v > 1 then lastPos, lastT = ball.Position, now; return v end
    local d = v
    if lastPos and lastT and now > lastT + 1e-4 then
        d = math.max(v, (ball.Position - lastPos).Magnitude / (now - lastT))
    end
    lastPos, lastT = ball.Position, now
    return d
end
local function ping()
    local ok, p = pcall(function() return LocalPlayer:GetNetworkPing() end)  -- seconds
    return (ok and type(p) == "number") and p or 0
end

-- ============================================================
--  AUTO PARRY
--  Fire when the targeting ball is within max(minDist, speed * (ping + buffer)) --
--  i.e. parry roughly `buffer` seconds (plus network latency) before impact, which
--  lands inside the server window without firing absurdly early.
-- ============================================================
local autoParry  = false
local pingBuffer = 0.05   -- s  (lead time beyond raw ping)
local minDist    = 16     -- studs floor (slow / early-round balls)
local retryCD    = 0.12   -- s  between attempts (lets a missed parry retry, no spam)
local hitChance  = 100    -- %  (drop parries to look human; 100 = always)

do
    local lastParry = 0
    track(RunService.Heartbeat:Connect(function()
        if not autoParry then return end
        local ball = getRealBall()
        if not ball or not targetsMe(ball) then return end
        local hrp = myHRP(); if not hrp then return end
        local now = os.clock()
        if now - lastParry < retryCD then return end

        local toMe = hrp.Position - ball.Position
        local dist = toMe.Magnitude
        local vel  = ball.AssemblyLinearVelocity
        -- if the ball is clearly moving AWAY (already deflected), don't waste a parry
        if vel.Magnitude > 5 and vel:Dot(toMe) <= 0 then return end

        local lead      = ping() + pingBuffer
        local threshold = math.max(minDist, ballSpeed(ball) * lead)
        if dist <= threshold then
            lastParry = now
            if hitChance < 100 and math.random(1, 100) > hitChance then return end
            fireParry()
        end
    end))
end

-- ============================================================
--  BALL ESP  -- highlight the real ball + a label (target name / speed),
--  red when it is coming for US.
-- ============================================================
local ballEsp = false
local hl, billboard, label
do
    hl = Instance.new("Highlight")
    hl.Name = "\0"; hl.FillTransparency = 0.4; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Enabled = false
    pcall(function() hl.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

    billboard = Instance.new("BillboardGui")
    billboard.Name = "\0"; billboard.Size = UDim2.fromOffset(200, 30)
    billboard.AlwaysOnTop = true; billboard.StudsOffset = Vector3.new(0, 2.6, 0); billboard.Enabled = false
    label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold; label.TextSize = 14
    label.TextStrokeTransparency = 0.3; label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Text = ""; label.Parent = billboard
    pcall(function() billboard.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

    local RED, WHITE = Color3.fromRGB(255, 60, 60), Color3.fromRGB(120, 200, 255)
    track(RunService.RenderStepped:Connect(function()
        if not ballEsp then
            if hl.Enabled then hl.Enabled = false; hl.Adornee = nil end
            if billboard.Enabled then billboard.Enabled = false; billboard.Adornee = nil end
            return
        end
        local ball = getRealBall()
        if ball then
            local mine = targetsMe(ball)
            local col = mine and RED or WHITE
            hl.Adornee = ball; hl.Enabled = true
            hl.FillColor = col; hl.OutlineColor = col
            billboard.Adornee = ball; billboard.Enabled = true
            label.TextColor3 = col
            local spd = math.floor(ballSpeed(ball) + 0.5)
            local tgt = ballTargetName(ball) or "?"
            label.Text = mine and ("INCOMING  |  " .. spd .. " s/s")
                or ("> " .. tostring(tgt) .. "  |  " .. spd .. " s/s")
        else
            hl.Enabled = false; hl.Adornee = nil
            billboard.Enabled = false; billboard.Adornee = nil
        end
    end))
end

-- ============================================================
--  UI  (Blade Ball page first -> it's the first tab; universal loads after)
-- ============================================================
do
    local Page = Window:Page({ Name = "Blade Ball" })

    local AP = Page:SubPage({ Name = "Auto Parry" })

    local Sec = AP:Section({ Name = "Auto Parry", Side = 1 })
    local apToggle = Sec:Toggle({ Name = "Auto Parry", Flag = "BB_AutoParry", Default = false,
        Callback = function(v) autoParry = v end })
    apToggle:Keybind({ Name = "Toggle key", Flag = "BB_AutoParryKey", Mode = "Toggle",
        Default = Enum.KeyCode.T, Callback = function() apToggle:Set(not apToggle.Value) end })
    Sec:Slider({ Name = "Ping buffer", Flag = "BB_PingBuffer", Min = 0, Max = 200, Default = 50,
        Decimals = 0, Suffix = " ms", Callback = function(v) pingBuffer = v / 1000 end })
    Sec:Slider({ Name = "Min distance", Flag = "BB_MinDist", Min = 6, Max = 60, Default = 16,
        Decimals = 0, Suffix = " studs", Callback = function(v) minDist = v end })
    Sec:Label({ Name = "fires only when a real ball targets YOU and is in range" })

    local Tune = AP:Section({ Name = "Tuning", Side = 2 })
    Tune:Slider({ Name = "Retry cooldown", Flag = "BB_RetryCD", Min = 50, Max = 400, Default = 120,
        Decimals = 0, Suffix = " ms", Callback = function(v) retryCD = v / 1000 end })
    Tune:Slider({ Name = "Hit chance", Flag = "BB_HitChance", Min = 50, Max = 100, Default = 100,
        Decimals = 0, Suffix = " %", Callback = function(v) hitChance = v end })
    Tune:Label({ Name = "lower buffer = parry later (riskier, harder to flag)" })
    Tune:Label({ Name = "AntiExploitLoaded is present -- keep it subtle" })

    local Vis = Page:SubPage({ Name = "Visuals" })
    local VSec = Vis:Section({ Name = "Ball ESP", Side = 1 })
    VSec:Toggle({ Name = "Ball ESP (highlight + label)", Flag = "BB_BallEsp", Default = false,
        Callback = function(v) ballEsp = v end })
    VSec:Label({ Name = "red = the ball is coming for you" })
end

-- universal shell after our page (movement + generic ESP). Higher anti-cheat risk
-- here than in other games -- the parry tools above are the safe core.
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    autoParry, ballEsp = false, false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() if hl then hl:Destroy() end end)
    pcall(function() if billboard then billboard:Destroy() end end)
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
