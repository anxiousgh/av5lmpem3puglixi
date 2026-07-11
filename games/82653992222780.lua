-- ============================================================
--  games/82653992222780.lua  --  Tap for Aura  (Decent Enough Games)
--
--  Tapping / clicker sim. You tap to earn Aura (PerTap x TapMulti x Combo);
--  Tappers auto-generate PerSecond passively. Spend on upgrades / rebirths /
--  prestige / plots / boxes.
--
--  Networking is an INDEXED lib -- ~80 BLANK-named RemoteEvents under
--  ReplicatedStorage.Communication.Events (no name map found in the GC). Decoded
--  live 2026-07-11 via a __namecall capture + synthetic clicks:
--    * TAP = Communication.Events child #41, fired as `remote:FireServer(nil)`
--      (one nil arg). A synthetic click fired ONLY that remote, so it's cleanly
--      identifiable by re-capturing a tap.
--    * The server RATE-LIMITS taps to ~the CPS stat (~8/s here): 25 fires @33/s
--      only banked ~7 taps of Aura. Over-firing isn't punished (no kick/flag),
--      the server just ignores the excess -- so we fire a bit above CPS to
--      saturate it and stop.
--
--  Index #41 is position-based (could shift on a game update), so the module
--  re-CALIBRATES the tap remote at load by hooking Communication fires and
--  emitting one synthetic click; falls back to #41 if the executor can't hook.
--
--  Only auto-tap is built (the core loop). Buy / rebirth / collect need their
--  own remotes captured (each is one blank remote fired on that action).
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer

local conns = {}
local unloaded = false
local function track(c) conns[#conns + 1] = c; return c end
local function gv() return (getgenv and getgenv()) or nil end

local MYGEN = ((gv() and gv()._WH_TFA_gen) or 0) + 1
if gv() then gv()._WH_TFA_gen = MYGEN end
local function current() local g = gv(); return (g == nil) or g._WH_TFA_gen == MYGEN end

-- ============================================================
--  STATE
-- ============================================================
local TFA = { autoTap = false, rate = 20 }

local Comm  = ReplicatedStorage:FindFirstChild("Communication")
local Events = Comm and Comm:FindFirstChild("Events")

-- ---- tap remote resolution (position-based, self-calibrating) ----
local TAP_INDEX = 41
local function remoteByIndex(i)
    if not Events then return nil end
    local kids = Events:GetChildren()
    return kids[i]
end
local TapRemote = remoteByIndex(TAP_INDEX)

-- Re-find the tap remote by hooking Communication fires and emitting one
-- synthetic click; whichever Events child fires is the tap. Falls back silently.
local function calibrate()
    if not (Events and getrawmetatable and setreadonly and newcclosure and getnamecallmethod) then return end
    local isEvent = {}
    for _, c in ipairs(Events:GetChildren()) do isEvent[c] = true end
    local found
    local ok = pcall(function()
        local mt = getrawmetatable(game)
        local old = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if not found then
                local ok2, m = pcall(getnamecallmethod)
                if ok2 and m == "FireServer" and isEvent[self] then found = self end
            end
            return old(self, ...)
        end)
        setreadonly(mt, true)
        local VIM = game:GetService("VirtualInputManager")
        local vp = Workspace.CurrentCamera.ViewportSize
        VIM:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 0)
        VIM:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 0)
        task.wait(0.2)
        setreadonly(mt, false); mt.__namecall = old; setreadonly(mt, true)
    end)
    if ok and found then TapRemote = found end
end
task.spawn(calibrate)

local function auraValue()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local a = ls and ls:FindFirstChild("Aura")
    return a and a.Value or nil
end

-- ============================================================
--  AUTO-TAP LOOP
-- ============================================================
task.spawn(function()
    while current() and not unloaded do
        if TFA.autoTap and TapRemote then
            pcall(function() TapRemote:FireServer(nil) end)
            task.wait(1 / math.max(1, TFA.rate))
        else
            task.wait(0.1)
        end
    end
end)

-- ============================================================
--  UI
-- ============================================================
local Page = Window:Page({ Name = "Tap for Aura" })
do
    local Sub = Page:SubPage({ Name = "Farm" })
    local S1 = Sub:Section({ Name = "Auto Tap", Side = 1 })
    if not TapRemote then
        S1:Label({ Name = "Tap remote not found (Communication.Events)." })
    end
    S1:Toggle({ Name = "Auto tap", Flag = "TFA_AutoTap", Default = false,
        Callback = function(v) TFA.autoTap = v end })
    S1:Slider({ Name = "Taps / second", Flag = "TFA_Rate", Min = 1, Max = 50, Default = 20, Decimals = 0, Suffix = "/s",
        Callback = function(v) TFA.rate = v end })
    S1:Label({ Name = "Server caps taps ~CPS/s; extra fires are ignored, not punished." })
    S1:Button({ Name = "Recalibrate tap remote", Callback = function() task.spawn(calibrate) end })

    local S2 = Sub:Section({ Name = "Stats", Side = 2 })
    local auraLbl = S2:Label({ Name = "Aura: --" })
    local rateLbl = S2:Label({ Name = "Aura/sec: --" })
    local lastA, lastT = auraValue(), os.clock()
    track(RunService.Heartbeat:Connect(function()
        if not current() or unloaded then return end
        local now = os.clock()
        if now - lastT < 1 then return end
        local a = auraValue()
        if a and lastA then
            pcall(function() auraLbl:SetText("Aura: " .. tostring(math.floor(a))) end)
            pcall(function() rateLbl:SetText("Aura/sec: " .. tostring(math.floor((a - lastA) / (now - lastT)))) end)
        end
        lastA, lastT = a, now
    end))
end

-- ============================================================
--  UNLOAD  (loops go inert via the generation guard on re-exec)
-- ============================================================
local function unload()
    if unloaded then return end
    unloaded = true
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
end
if gv() then gv()._WH_TFA_unload = unload end
do
    local prev = Library.OnExit
    Library.OnExit = function() pcall(unload); if prev then pcall(prev) end end
end

-- clicker has no combat/ESP use, but keep the shell for movement + settings parity
pcall(function() ctx.load("games/universal.lua")(ctx) end)
