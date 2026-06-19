-- ============================================================
--  games/70959844973091.lua  --  😈 Split or Steal Brainrot
--
--  Per-game module: loads the universal base first (so movement/etc. still
--  work), then adds a "Brainrot" page with an auto cash collector.
--
--  CollectAll banks all accumulated cash (fires with no args, not rate-limited)
--  -> Events.Player.CollectAll.
-- ============================================================
local ctx = ({ ... })[1]

-- universal base first (keeps the shared pages)
pcall(function() ctx.load("games/universal.lua")(ctx) end)

local Library = ctx.Library
local Window  = ctx.Window

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS         = game:GetService("ReplicatedStorage")

-- resolve the CollectAll remote each time (survives respawns / re-parents)
local function getCollect()
    local node = RS:FindFirstChild("BrainrotsThings")
    for _, name in ipairs({ "Misc", "Events", "Player", "CollectAll" }) do
        if not node then return nil end
        node = node:FindFirstChild(name)
    end
    return node
end

-- ---- auto collect backend ----
local enabled, interval, conn, acc = false, 1, nil, 0
local function stopAuto()
    if conn then conn:Disconnect(); conn = nil end
end
local function startAuto()
    stopAuto()
    acc = 0
    conn = RunService.Heartbeat:Connect(function(dt)
        if not enabled then return end
        acc = acc + dt
        if acc >= interval then
            acc = 0
            local remote = getCollect()
            if remote then pcall(function() remote:FireServer() end) end
        end
    end)
end

-- ---- UI ----
local Page = Window:Page({ Name = "Brainrot" })
local Sub  = Page:SubPage({ Name = "Farm" })
local Sec  = Sub:Section({ Name = "Cash", Side = 1 })

Sec:Toggle({
    Name = "Auto collect cash", Flag = "BR_AutoCollect", Default = false, KeybindName = "Auto collect",
    Callback = function(v)
        enabled = v
        if v then startAuto() else stopAuto() end
    end,
})
Sec:Slider({
    Name = "Interval", Flag = "BR_CollectInterval",
    Min = 1, Max = 30, Default = 1, Decimals = 0, Suffix = "s",
    Callback = function(v) interval = v end,
})
Sec:Button({
    Name = "Collect now",
    Callback = function()
        local remote = getCollect()
        if remote then pcall(function() remote:FireServer() end) end
    end,
})

-- ---- teardown: stop the loop on unload / re-execution ----
-- universal registered its own disableAll/OnExit; wrap them so our loop is
-- torn down too (otherwise the Heartbeat would keep firing CollectAll).
do
    local g = getgenv and getgenv()
    if g and g.WH then
        local prev = g.WH.disableAll
        local function full()
            pcall(stopAuto)
            if prev then pcall(prev) end
        end
        g.WH.disableAll = full
        Library.OnExit = full
    end
end
