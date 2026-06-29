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
local CollectionService = game:GetService("CollectionService")
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
--  PROVISIONAL holder/pass resolution  (revise after live capture)
-- ============================================================
-- getHolder() -> the Player who currently holds the bomb, or nil.
-- Heuristics, best-effort until we know the real marker:
--   1) any player whose character carries a Tool that looks like the bomb
--   2) any player whose Data.Status attribute is set to a non-idle value
--   3) a workspace instance tagged/named like a bomb -> nearest character to it
local IDLE_STATUS = { [""] = true, None = true, Idle = true, Spectating = true, Lobby = true }
local function looksLikeBomb(name)
    name = string.lower(name or "")
    return name:find("bomb") ~= nil or name:find("time") ~= nil
end
local function getHolder()
    -- 1) tool on a character
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        if c then
            for _, d in ipairs(c:GetChildren()) do
                if d:IsA("Tool") and looksLikeBomb(d.Name) then return p, d end
            end
        end
    end
    -- 2) Data.Status marker
    for _, p in ipairs(Players:GetPlayers()) do
        local data = p:FindFirstChild("Data")
        local st = data and data:GetAttribute("Status")
        if type(st) == "string" and not IDLE_STATUS[st] and st:lower():find("bomb") then return p end
    end
    -- 3) tagged bomb part -> nearest character
    for _, tag in ipairs({ "Bomb", "TimeBomb", "Timebomb" }) do
        for _, inst in ipairs(CollectionService:GetTagged(tag)) do
            if inst:IsDescendantOf(workspace) then
                local pos = inst:IsA("BasePart") and inst.Position or (inst:IsA("Model") and inst:GetPivot().Position)
                if pos then
                    local best, bestD
                    for _, p in ipairs(Players:GetPlayers()) do
                        local hrp = charHRP(p)
                        if hrp then
                            local d = (hrp.Position - pos).Magnitude
                            if not bestD or d < bestD then best, bestD = p, d end
                        end
                    end
                    if best then return best end
                end
            end
        end
    end
    return nil
end
-- passBomb(targetHRP): get the bomb onto `target`. Tag here is most likely TOUCH-based,
-- so the reach loop already teleports us onto them (the confirmed client-auth move does
-- the work). If capture shows a dedicated pass remote, fire it from here.
local function passBomb(_targetHRP)
    -- TODO(capture): e.g. ReplicatedStorage.Remotes.<X>:FireServer(target) -- unknown until spy
end

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
    track(RunService.Heartbeat:Connect(function()
        if not autoTag then return end
        if os.clock() - lastTag < (tagCD or 0.5) then return end
        local holder = getHolder()
        if holder ~= LocalPlayer then return end          -- only when WE are it
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
--  UI  (Timebomb subpage -- created before universal so it's the first sub-tab)
-- ============================================================
do
    local Sub = MainPage:SubPage({ Name = "Timebomb" })

    local SecB = Sub:Section({ Name = "Bomb", Side = 1 })
    SecB:Toggle({ Name = "Highlight bomb holder", Flag = "TBD_HolderEsp", Default = false,
        Callback = function(v) holderEsp = v end })
    SecB:Label({ Name = "holder marker is provisional until a live duel is captured" })

    local SecT = Sub:Section({ Name = "Auto-tag", Side = 2 })
    SecT:Toggle({ Name = "Auto-tag (reach nearest)", Flag = "TBD_AutoTag", Default = false,
        Callback = function(v) autoTag = v end })
    SecT:Slider({ Name = "Tag cooldown", Flag = "TBD_TagCD", Min = 100, Max = 2000, Default = 500, Decimals = 0, Suffix = " ms",
        Callback = function(v) tagCD = v / 1000 end })
    SecT:Toggle({ Name = "Return after tag", Flag = "TBD_TagReturn", Default = true,
        Callback = function(v) tagReturn = v end })
    SecT:Label({ Name = "only fires while YOU hold the bomb" })
end

-- universal shell after our page so Timebomb stays the first sub-tab (movement + ESP)
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    holderEsp, autoTag = false, false
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
