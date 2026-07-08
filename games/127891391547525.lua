-- ============================================================
--  games/127891391547525.lua  --  Clean  the Supermarket! [HARD]
--
--  Restocking game: floor items (CollectionService tag "FloorItem", ~3300 in
--  HARD) get picked up and placed on the correct shelf zone. Everything is
--  remote-driven and validated server-side:
--    Remotes.PickupItem:FireServer(item)        -- item = the tagged instance
--    Remotes.PlaceItem:FireServer(zone, point)  -- zone = SectionZones box,
--                                                  point = spot on its surface
--  Zones live in workspace.StoreMaps.HardStore.SectionZones (BaseParts with
--  SectionId / ShelfType / SurfaceY / FrontDir / ClaimedProduct attributes).
--  ReplicatedStorage.Shared.SectionIndex (shared module) answers
--  canPlace(itemName, resolveZone(zone)) client-side, so we can pre-filter.
--  Server feedback: LocalCorrectPlacement (accepted) / PlaceRejected (reason).
--  Held stack mirrors via Remotes.UpdateHeld. Capacity / reach are player
--  attributes: CartCapacity, PickupRange (both upgradeable in-game).
--
--  DELIBERATELY SUBTLE: no teleports, no reach extension. Auto-pickup and
--  auto-shelve only act within the player's REAL PickupRange with randomized
--  delays -- you still walk everywhere yourself; the script just does the
--  clicking. Server-side placement semantics (which held item, claim-check
--  order) were only partially confirmed, so auto-shelve tries the nearest
--  canPlace-valid zone for ANY held item and cools a zone off when the server
--  rejects it -- converges regardless of the exact rules.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SectionIndex; pcall(function() SectionIndex = require(ReplicatedStorage.Shared.SectionIndex) end)
local GameConfig;   pcall(function() GameConfig   = require(ReplicatedStorage.Shared.GameConfig) end)
GameConfig = GameConfig or { MaxHeld = 4, PickupRange = 18 }

local MainPage = Window:Page({ Name = "Main" })

local conns = {}
local function track(c) conns[#conns + 1] = c; return c end
local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function capacity()    return LocalPlayer:GetAttribute("CartCapacity") or GameConfig.MaxHeld end
local function serverRange() return LocalPlayer:GetAttribute("PickupRange") or GameConfig.PickupRange end
local function itemPos(it)
    local ok, p = pcall(function()
        if it:IsA("Model") then return it:GetPivot().Position end
        return it.Position
    end)
    return ok and p or nil
end

-- ============================================================
--  Held-stack mirror (server pushes the full list on every change)
-- ============================================================
local held = {}
track(Remotes.UpdateHeld.OnClientEvent:Connect(function(list) held = list or {} end))

-- ============================================================
--  Candidate shelf zones for what we hold. canPlace() is cheap but 478 zones
--  x held items adds up, so cache per held-set for a short window; a zone the
--  server rejects goes on cooldown so we walk the candidate list instead of
--  hammering one shelf.
-- ============================================================
local zoneCD = {}                          -- [zonePart] = os.clock() cooldown expiry
local candCache = { sig = nil, t = 0, list = {} }
local function heldSig()
    local t = {}
    for _, e in ipairs(held) do t[#t + 1] = tostring(e.name) end
    return table.concat(t, "|")
end
local function candidateZones()
    if not SectionIndex then return {} end
    local sig = heldSig()
    if candCache.sig == sig and os.clock() - candCache.t < 2 then return candCache.list end
    local list = {}
    local okZ, folder = pcall(SectionIndex.getZonesFolder)
    if okZ and folder then
        -- distinct held names, held[1] first (server appears to shelve FIFO)
        local names, seen = {}, {}
        for _, e in ipairs(held) do
            local n = e.name
            if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
        end
        for _, z in ipairs(folder:GetChildren()) do
            if z:IsA("BasePart") and z:GetAttribute("SectionId") then
                for pri, n in ipairs(names) do
                    local ok, can = pcall(function()
                        local zi = SectionIndex.resolveZone(z)
                        return zi and SectionIndex.canPlace(n, zi)
                    end)
                    if ok and can then
                        list[#list + 1] = { zone = z, name = n, pri = pri }
                        break
                    end
                end
            end
        end
    end
    candCache.sig, candCache.t, candCache.list = sig, os.clock(), list
    return list
end
-- random spot on the zone's shelf surface (SurfaceY is absolute world Y)
local function surfacePoint(z)
    local sy = z:GetAttribute("SurfaceY") or (z.Position.Y + z.Size.Y / 2)
    local p = z.CFrame:PointToWorldSpace(Vector3.new(
        (math.random() - 0.5) * z.Size.X * 0.4, 0,
        (math.random() - 0.5) * z.Size.Z * 0.4))
    return Vector3.new(p.X, sy, p.Z)
end

-- ============================================================
--  AUTO PICKUP  -- nearest floor item inside your real reach, jittered pacing
-- ============================================================
local pickupOn, pickupDelay, autoRange = false, 0.4, 12
local placeOn, placeDelay = false, 0.55
local nextPick, nextPlace = 0, 0
local itemCD = {}                          -- [item] = retry-not-before (server ignored us)
local lastTriedZone = nil

track(Remotes.PlaceRejected.OnClientEvent:Connect(function()
    if lastTriedZone then zoneCD[lastTriedZone] = os.clock() + 12; lastTriedZone = nil end
    candCache.sig = nil                    -- claim state was stale; recompute
end))

local function jitter(base) return base * (0.7 + math.random() * 0.6) end

track(RunService.Heartbeat:Connect(function()
    local now = os.clock()
    local hrp = myHRP(); if not hrp then return end
    local reach = math.min(autoRange, serverRange())

    -- pickup
    if pickupOn and now >= nextPick and #held < capacity() then
        nextPick = now + jitter(pickupDelay)
        local best, bestD
        for _, it in ipairs(CollectionService:GetTagged("FloorItem")) do
            if it.Parent and (not itemCD[it] or now >= itemCD[it]) then
                local p = itemPos(it)
                local d = p and (p - hrp.Position).Magnitude
                if d and d <= reach and (not bestD or d < bestD) then best, bestD = it, d end
            end
        end
        if best then
            itemCD[best] = now + 3
            Remotes.PickupItem:FireServer(best)
        end
    end

    -- shelve
    if placeOn and now >= nextPlace and #held > 0 then
        nextPlace = now + jitter(placeDelay)
        local best, bestD
        for _, c in ipairs(candidateZones()) do
            local z = c.zone
            if z.Parent and (not zoneCD[z] or now >= zoneCD[z]) then
                local d = (z.Position - hrp.Position).Magnitude
                -- prefer zones for the bottom-of-stack item on ties (pri already
                -- ordered); nearest wins otherwise
                if d <= reach and (not bestD or d < bestD) then best, bestD = z, d end
            end
        end
        if best then
            lastTriedZone = best
            zoneCD[best] = now + 1.5       -- brief self-cooldown; rejection extends it
            Remotes.PlaceItem:FireServer(best, surfacePoint(best))
        end
    end
end))

-- ============================================================
--  SHELF FINDER  -- beam from you to the nearest valid shelf for the held
--  stack (any distance). Pure client visual: it shows WHERE to walk; the
--  auto-shelve fires once you're actually there.
-- ============================================================
local finderOn = false
local beamPart, beam, a0char
do
    beamPart = Instance.new("Part")
    beamPart.Anchored = true; beamPart.CanCollide = false; beamPart.CanQuery = false
    beamPart.CanTouch = false; beamPart.Transparency = 1; beamPart.Size = Vector3.new(0.2, 0.2, 0.2)
    local a1 = Instance.new("Attachment"); a1.Parent = beamPart
    beam = Instance.new("Beam")
    beam.Attachment1 = a1; beam.Width0 = 0.15; beam.Width1 = 0.4
    beam.FaceCamera = true; beam.Transparency = NumberSequence.new(0.35)
    beam.Color = ColorSequence.new(Color3.fromRGB(170, 140, 255))
    beam.Enabled = false; beam.Parent = beamPart
    beamPart.Parent = workspace

    local acc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        acc += dt; if acc < 0.25 then return end
        acc = 0
        local hrp = myHRP()
        if not (finderOn and hrp and #held > 0) then
            if beam.Enabled then beam.Enabled = false end
            return
        end
        if not a0char or a0char.Parent ~= hrp then
            if a0char then a0char:Destroy() end
            a0char = Instance.new("Attachment"); a0char.Parent = hrp
            beam.Attachment0 = a0char
        end
        local now, best, bestD = os.clock(), nil, nil
        for _, c in ipairs(candidateZones()) do
            local z = c.zone
            if z.Parent and (not zoneCD[z] or now >= zoneCD[z]) then
                local d = (z.Position - hrp.Position).Magnitude
                if not bestD or d < bestD then best, bestD = z, d end
            end
        end
        if best then
            beamPart.Position = Vector3.new(best.Position.X,
                best:GetAttribute("SurfaceY") or best.Position.Y, best.Position.Z)
            beam.Enabled = true
        else
            beam.Enabled = false
        end
    end))
end

-- ============================================================
--  FLOOR ITEM HIGHLIGHTS  -- pooled (Roblox caps ~31 Highlights), nearest N
-- ============================================================
local espOn, espRadius = false, 60
local pool = {}
for i = 1, 10 do
    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.75; hl.OutlineTransparency = 0.1
    hl.FillColor = Color3.fromRGB(140, 110, 255); hl.OutlineColor = Color3.fromRGB(200, 180, 255)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Enabled = false
    pcall(function() hl.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    pool[i] = hl
end
do
    local acc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        acc += dt; if acc < 0.35 then return end
        acc = 0
        local hrp = myHRP()
        if not (espOn and hrp) then
            for _, hl in ipairs(pool) do
                if hl.Enabled then hl.Enabled = false; hl.Adornee = nil end
            end
            return
        end
        local near = {}
        for _, it in ipairs(CollectionService:GetTagged("FloorItem")) do
            if it.Parent then
                local p = itemPos(it)
                local d = p and (p - hrp.Position).Magnitude
                if d and d <= espRadius then near[#near + 1] = { it = it, d = d } end
            end
        end
        table.sort(near, function(a, b) return a.d < b.d end)
        for i, hl in ipairs(pool) do
            local e = near[i]
            if e then hl.Adornee = e.it; hl.Enabled = true
            else hl.Adornee = nil; hl.Enabled = false end
        end
    end))
end

-- ============================================================
--  UI  (Supermarket subpage)
-- ============================================================
do
    local Sub = MainPage:SubPage({ Name = "Supermarket" })

    local SecA = Sub:Section({ Name = "Auto clean", Side = 1 })
    local pickToggle = SecA:Toggle({ Name = "Auto pickup nearby", Flag = "SM_AutoPickup", Default = false,
        Callback = function(v) pickupOn = v end })
    pickToggle:Keybind({ Name = "Toggle auto pickup", Flag = "SM_AutoPickupKey", Mode = "Toggle",
        Default = Enum.KeyCode.V, Callback = function() pickToggle:Set(not pickToggle.Value) end })
    SecA:Slider({ Name = "Pickup delay", Flag = "SM_PickDelay", Min = 200, Max = 1500, Default = 400, Decimals = 0, Suffix = " ms",
        Callback = function(v) pickupDelay = v / 1000 end })
    local placeToggle = SecA:Toggle({ Name = "Auto shelve held items", Flag = "SM_AutoPlace", Default = false,
        Callback = function(v) placeOn = v end })
    placeToggle:Keybind({ Name = "Toggle auto shelve", Flag = "SM_AutoPlaceKey", Mode = "Toggle",
        Default = Enum.KeyCode.B, Callback = function() placeToggle:Set(not placeToggle.Value) end })
    SecA:Slider({ Name = "Shelve delay", Flag = "SM_PlaceDelay", Min = 250, Max = 1500, Default = 550, Decimals = 0, Suffix = " ms",
        Callback = function(v) placeDelay = v / 1000 end })
    SecA:Slider({ Name = "Act range", Flag = "SM_Range", Min = 4, Max = 18, Default = 12, Decimals = 0, Suffix = " studs",
        Callback = function(v) autoRange = v end })
    SecA:Label({ Name = "capped to your real reach -- you still walk" })

    local SecV = Sub:Section({ Name = "Visuals", Side = 2 })
    SecV:Toggle({ Name = "Shelf finder beam", Flag = "SM_Finder", Default = false,
        Callback = function(v) finderOn = v end })
    SecV:Toggle({ Name = "Highlight floor items", Flag = "SM_Esp", Default = false,
        Callback = function(v) espOn = v end })
    SecV:Slider({ Name = "Highlight radius", Flag = "SM_EspRadius", Min = 20, Max = 150, Default = 60, Decimals = 0, Suffix = " studs",
        Callback = function(v) espRadius = v end })
    SecV:Label({ Name = "beam points at a valid shelf for your stack" })
end

-- universal shell after our page so Supermarket stays the first sub-tab
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    pickupOn, placeOn, finderOn, espOn = false, false, false, false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, hl in ipairs(pool) do pcall(function() hl:Destroy() end) end
    if a0char then pcall(function() a0char:Destroy() end) end
    if beamPart then pcall(function() beamPart:Destroy() end) end
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
