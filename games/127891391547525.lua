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
--  A zone's SectionId ("ProduceSmallWedge/Fixture_10/Shelf1/1") indexes the
--  physical shelf model: Shelves.<first>/<second> -- used for the finder
--  highlight. ReplicatedStorage.Shared.SectionIndex (shared module) answers
--  canPlace(itemName, resolveZone(zone)) client-side, so we can pre-filter.
--  Server feedback: LocalCorrectPlacement (accepted) / PlaceRejected (reason).
--  Held stack mirrors via Remotes.UpdateHeld. Capacity / reach are player
--  attributes: CartCapacity, PickupRange (both upgradeable in-game).
--  Item -> category comes from ReplicatedStorage.GroceryItems.<Category>.<Name>
--  template folders (21 categories; every floor item name maps to exactly one).
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
local function uiParent() return (gethui and gethui()) or game:GetService("CoreGui") end
-- GUI theme accent so world visuals match the menu (live: themes can change)
local function accent()
    return (Library.Theme and Library.Theme["Accent"]) or Color3.fromRGB(200, 183, 247)
end

-- ============================================================
--  CATEGORIES  -- item name -> category from the GroceryItems template
--  folders; each category gets a stable distinct hue (golden-ratio walk).
-- ============================================================
local catOf, catList, catColor = {}, {}, {}
do
    local gi = ReplicatedStorage:FindFirstChild("GroceryItems")
    if gi then
        for _, folder in ipairs(gi:GetChildren()) do
            catList[#catList + 1] = folder.Name
            for _, tpl in ipairs(folder:GetChildren()) do catOf[tpl.Name] = folder.Name end
        end
    end
    table.sort(catList)
    -- distinct hue per category, nudged toward the GUI accent so it fits the theme
    local acc = Color3.fromRGB(200, 183, 247)
    for i, name in ipairs(catList) do
        catColor[name] = Color3.fromHSV((i * 0.618034) % 1, 0.6, 1):Lerp(acc, 0.2)
    end
end
local selectedCats = {}                    -- [categoryName] = true
local function catSelected(itemName)
    local c = catOf[itemName]
    return c ~= nil and selectedCats[c] == true
end
local function anyCatSelected() return next(selectedCats) ~= nil end

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
-- a different product already physically on the shelf zone: placed items get
-- parented INTO the zone box, named exactly the product. More reliable than
-- the ClaimedProduct attribute, which we've seen go stale client-side.
local function occupiedByOther(z, name)
    for _, k in ipairs(z:GetChildren()) do
        if (k:IsA("BasePart") or k:IsA("Model")) and k.Name ~= name then
            return true
        end
    end
    return false
end
local function candidateZones()
    if not SectionIndex then return {} end
    local sig = heldSig()
    if candCache.sig == sig and os.clock() - candCache.t < 0.4 then return candCache.list end
    local list = {}
    local okZ, folder = pcall(SectionIndex.getZonesFolder)
    if okZ and folder then
        -- distinct held names, ACTIVE item first (= LAST in the stack: it's
        -- what the UI shows, what the ghost previews, and what the server
        -- places; CycleHeld rotates the stack to change it)
        local names, seen = {}, {}
        for i = #held, 1, -1 do
            local n = held[i].name
            if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
        end
        for _, z in ipairs(folder:GetChildren()) do
            if z:IsA("BasePart") and z:GetAttribute("SectionId") then
                for pri, n in ipairs(names) do
                    if not occupiedByOther(z, n) then
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
    end
    candCache.sig, candCache.t, candCache.list = sig, os.clock(), list
    return list
end
-- random spot on the zone's shelf surface (SurfaceY is absolute world Y).
-- LIFT the point into the box: real client placements land ~0.6 above
-- SurfaceY (raycast on the shelf/stacked items); a point exactly on the
-- SurfaceY plane sits on the box's bottom boundary and the server resolves
-- it into the NEIGHBOURING box -> bogus wrongType/claimed rejections
-- (confirmed by comparing spied real placements against ours).
local function surfacePoint(z)
    local sy = z:GetAttribute("SurfaceY") or (z.Position.Y + z.Size.Y / 2)
    local p = z.CFrame:PointToWorldSpace(Vector3.new(
        (math.random() - 0.5) * z.Size.X * 0.4, 0,
        (math.random() - 0.5) * z.Size.Z * 0.4))
    local y = math.min(sy + 0.55, z.Position.Y + z.Size.Y / 2 - 0.1)
    return Vector3.new(p.X, y, p.Z)
end
-- the actual shelf a zone belongs to: SectionId "A/B/C/..." ->
-- Shelves.A.B.C (e.g. ProduceSmallWedge/Fixture_10/Shelf1); falls back to the
-- fixture model when the shelf part is missing
local function shelfFor(z)
    local id = z:GetAttribute("SectionId")
    local a, b, c = id and id:match("^([^/]+)/([^/]+)/([^/]+)")
    if not a then return nil end
    local store = workspace:FindFirstChild("StoreMaps")
    store = store and store:FindFirstChild("HardStore")
    local shelves = store and store:FindFirstChild("Shelves")
    local sub = shelves and shelves:FindFirstChild(a)
    local fix = sub and sub:FindFirstChild(b)
    return fix and ((c and fix:FindFirstChild(c)) or fix) or nil
end

-- ============================================================
--  AUTO CLEAN  -- pickup + shelve, jittered pacing, real reach only.
--  Pickup optionally restricted to the selected categories.
-- ============================================================
local pickupOn, pickupDelay, autoRange = false, 0.05, 12
local placeOn, placeDelay = false, 0.06
local catFilterOn = false                  -- pickup only selected categories
local nextPick, nextPlace = 0, 0
local itemCD = {}                          -- [item] = retry-not-before (server ignored us)
local lastTriedZone = nil

track(Remotes.PlaceRejected.OnClientEvent:Connect(function()
    if lastTriedZone then zoneCD[lastTriedZone] = os.clock() + 3; lastTriedZone = nil end
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
        local filtering = catFilterOn and anyCatSelected()
        local best, bestD
        for _, it in ipairs(CollectionService:GetTagged("FloorItem")) do
            if it.Parent and (not itemCD[it] or now >= itemCD[it])
                and (not filtering or catSelected(it.Name)) then
                local p = itemPos(it)
                local d = p and (p - hrp.Position).Magnitude
                if d and d <= reach and (not bestD or d < bestD) then best, bestD = it, d end
            end
        end
        if best then
            itemCD[best] = now + 0.5
            Remotes.PickupItem:FireServer(best)
        end
    end

    -- shelve: the server only places the ACTIVE (last-held) item, so if the
    -- nearest valid shelf is for a different held item, rotate the stack with
    -- CycleHeld (what the in-game switch button fires) until it's active
    if placeOn and now >= nextPlace and #held > 0 then
        nextPlace = now + jitter(placeDelay)
        local activeName = held[#held] and held[#held].name
        local best, bestD
        for _, c in ipairs(candidateZones()) do
            local z = c.zone
            if z.Parent and (not zoneCD[z] or now >= zoneCD[z]) then
                local d = (z.Position - hrp.Position).Magnitude
                if d <= reach and (not bestD or d < bestD) then best, bestD = c, d end
            end
        end
        if best then
            if best.name == activeName or #held < 2 then
                lastTriedZone = best.zone
                zoneCD[best.zone] = now + 0.25 -- brief self-cooldown; rejection extends it
                Remotes.PlaceItem:FireServer(best.zone, surfacePoint(best.zone))
            else
                Remotes.CycleHeld:FireServer("forward")
                nextPlace = now + 0.12         -- give UpdateHeld a beat to mirror back
            end
        end
    end
end))

-- ============================================================
--  SHELF FINDER  -- straight tracer-style beam (same look as the Hood Customs
--  fake bullet tracers: glow halo + white-hot core + scrolling energy texture)
--  from you to the nearest valid shelf for the held stack, pulsing highlight
--  on the target zone and one on the actual shelf it maps to. Client visuals.
-- ============================================================
local finderOn = false
local beamPart, beams, a0char, a1
local corePart, coreHl
local zoneHl, fixHl
do
    beamPart = Instance.new("Part")
    beamPart.Anchored = true; beamPart.CanCollide = false; beamPart.CanQuery = false
    beamPart.CanTouch = false; beamPart.Transparency = 1; beamPart.Size = Vector3.new(0.2, 0.2, 0.2)
    a1 = Instance.new("Attachment"); a1.Parent = beamPart

    local col = accent()
    local whiteHot = ColorSequence.new({
        ColorSequenceKeypoint.new(0, col), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, col) })
    local TEX = "rbxassetid://446111271"   -- soft energy streak (same as tracers)
    beams = {}
    local function mkBeam(width, transp, textured, colSeq)
        local b = Instance.new("Beam")
        b.Attachment1 = a1
        b.LightEmission, b.LightInfluence, b.FaceCamera, b.Segments = 1, 0, true, 4
        b.Width0, b.Width1 = width, width
        b.Color = colSeq or ColorSequence.new(col)
        b.Transparency = NumberSequence.new(transp or 0)
        if textured then pcall(function()
            b.Texture, b.TextureMode = TEX, Enum.TextureMode.Wrap
            b.TextureLength, b.TextureSpeed = 4, 12   -- fast scroll = energy flow
        end) end
        b.Enabled = false; b.Parent = beamPart
        beams[#beams + 1] = b
        return b
    end
    -- HC "Standard" tracer: halo + mid glow + white-hot textured core
    local th = 0.35
    local outer = mkBeam(th * 5, nil)
    outer.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0.35),
        NumberSequenceKeypoint.new(1, 0.6) })
    mkBeam(th * 2.6, 0.25)                 -- mid glow
    mkBeam(th * 1.1, 0.02, true, whiteHot) -- white-hot textured core
    beamPart.Parent = workspace

    -- the HC signature: a solid neon core line under a black-outline Highlight
    -- (reads through walls, hairline stays visible)
    corePart = Instance.new("Part")
    corePart.Anchored = true; corePart.CanCollide = false; corePart.CanQuery = false
    corePart.CanTouch = false; corePart.CastShadow = false
    corePart.Material = Enum.Material.Neon; corePart.Color = col
    corePart.Transparency = 1; corePart.Size = Vector3.new(0.12, 0.12, 0.12)
    corePart.Parent = workspace
    coreHl = Instance.new("Highlight")
    coreHl.Adornee = corePart
    coreHl.FillColor = col; coreHl.FillTransparency = 0.2
    coreHl.OutlineColor = Color3.new(0, 0, 0); coreHl.OutlineTransparency = 0
    coreHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; coreHl.Enabled = false
    pcall(function() coreHl.Parent = uiParent() end)

    zoneHl = Instance.new("Highlight")     -- highlights render even on invisible parts
    zoneHl.FillColor = accent(); zoneHl.OutlineColor = Color3.new(1, 1, 1)
    zoneHl.FillTransparency = 0.15; zoneHl.OutlineTransparency = 0
    zoneHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; zoneHl.Enabled = false
    pcall(function() zoneHl.Parent = uiParent() end)

    fixHl = Instance.new("Highlight")
    fixHl.FillColor = accent(); fixHl.OutlineColor = Color3.new(0, 0, 0)
    fixHl.FillTransparency = 0.3; fixHl.OutlineTransparency = 0
    fixHl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; fixHl.Enabled = false
    pcall(function() fixHl.Parent = uiParent() end)

    local acc, target = 0, nil
    track(RunService.Heartbeat:Connect(function(dt)
        local hrp = myHRP()
        local active = finderOn and hrp and #held > 0

        -- retarget on a fast tick; animate every frame
        acc += dt
        if acc >= 0.05 then
            acc = 0
            target = nil
            if active then
                local now, bestD = os.clock(), nil
                for _, c in ipairs(candidateZones()) do
                    local z = c.zone
                    if z.Parent and (not zoneCD[z] or now >= zoneCD[z]) then
                        local d = (z.Position - hrp.Position).Magnitude
                        if not bestD or d < bestD then target, bestD = z, d end
                    end
                end
            end
        end

        if not (active and target) then
            if beams[1].Enabled then
                for _, b in ipairs(beams) do b.Enabled = false end
            end
            if coreHl.Enabled then
                coreHl.Enabled = false; corePart.Transparency = 1
            end
            if zoneHl.Enabled then zoneHl.Enabled = false; zoneHl.Adornee = nil end
            if fixHl.Enabled then fixHl.Enabled = false; fixHl.Adornee = nil end
            return
        end

        if not a0char or a0char.Parent ~= hrp then
            if a0char then a0char:Destroy() end
            a0char = Instance.new("Attachment"); a0char.Parent = hrp
            for _, b in ipairs(beams) do b.Attachment0 = a0char end
        end

        local tpos = Vector3.new(target.Position.X,
            target:GetAttribute("SurfaceY") or target.Position.Y, target.Position.Z)
        beamPart.Position = tpos
        for _, b in ipairs(beams) do
            if not b.Enabled then b.Enabled = true end
        end

        -- stretch the neon core line from chest to shelf
        local from = hrp.Position
        local dist = (tpos - from).Magnitude
        if dist > 0.5 then
            corePart.Size = Vector3.new(0.12, 0.12, dist)
            corePart.CFrame = CFrame.lookAt((from + tpos) / 2, tpos)
            corePart.Transparency = 0
            coreHl.Enabled = true
        end

        local s = 0.5 + 0.5 * math.sin(os.clock() * 4)
        zoneHl.FillTransparency = 0.1 + 0.35 * s
        if zoneHl.Adornee ~= target then zoneHl.Adornee = target end
        zoneHl.Enabled = true

        local shelf = shelfFor(target)
        if fixHl.Adornee ~= shelf then fixHl.Adornee = shelf end
        fixHl.Enabled = shelf ~= nil
    end))
end

-- ============================================================
--  FIND CATEGORY ITEMS  -- pick categories, floor items from them get
--  highlighted in that category's colour (pooled: nearest 20 in radius;
--  Roblox caps ~31 enabled Highlights). No categories selected = show all.
-- ============================================================
local catEspOn, catEspRadius = false, 60
local catPool = {}
for i = 1, 20 do
    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.3; hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Enabled = false
    pcall(function() hl.Parent = uiParent() end)
    catPool[i] = hl
end
do
    local acc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        acc += dt; if acc < 0.08 then return end
        acc = 0
        local hrp = myHRP()
        if not (catEspOn and hrp) then
            for _, hl in ipairs(catPool) do
                if hl.Enabled then hl.Enabled = false; hl.Adornee = nil end
            end
            return
        end
        local filtering = anyCatSelected()
        local near = {}
        for _, it in ipairs(CollectionService:GetTagged("FloorItem")) do
            if it.Parent and (not filtering or catSelected(it.Name)) then
                local p = itemPos(it)
                local d = p and (p - hrp.Position).Magnitude
                if d and d <= catEspRadius then near[#near + 1] = { it = it, d = d } end
            end
        end
        table.sort(near, function(a, b) return a.d < b.d end)
        for i, hl in ipairs(catPool) do
            local e = near[i]
            if e then
                local col = catColor[catOf[e.it.Name]] or accent()
                hl.FillColor = col
                hl.OutlineColor = col:Lerp(Color3.new(1, 1, 1), 0.5)
                hl.Adornee = e.it; hl.Enabled = true
            else
                hl.Adornee = nil; hl.Enabled = false
            end
        end
    end))
end

-- ============================================================
--  THIRD PERSON  -- the game locks first person via CameraMode/MaxZoom, so we
--  override them every frame (it re-locks). Restores the originals when off.
-- ============================================================
local thirdPerson, tpDist = false, 14
local _origMode, _origMaxZoom = nil, nil
track(RunService.RenderStepped:Connect(function()
    if thirdPerson then
        if _origMode == nil then
            _origMode = LocalPlayer.CameraMode
            _origMaxZoom = LocalPlayer.CameraMaxZoomDistance
        end
        if LocalPlayer.CameraMode ~= Enum.CameraMode.Classic then LocalPlayer.CameraMode = Enum.CameraMode.Classic end
        if LocalPlayer.CameraMaxZoomDistance ~= tpDist then LocalPlayer.CameraMaxZoomDistance = tpDist end
    elseif _origMode ~= nil then
        LocalPlayer.CameraMode = _origMode
        LocalPlayer.CameraMaxZoomDistance = _origMaxZoom
        _origMode, _origMaxZoom = nil, nil
    end
end))

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
    SecA:Toggle({ Name = "Selected categories only", Flag = "SM_CatFilter", Default = false,
        Callback = function(v) catFilterOn = v end })
    SecA:Slider({ Name = "Pickup delay", Flag = "SM_PickDelay", Min = 10, Max = 500, Default = 50, Decimals = 0, Suffix = " ms",
        Callback = function(v) pickupDelay = v / 1000 end })
    local placeToggle = SecA:Toggle({ Name = "Auto shelve held items", Flag = "SM_AutoPlace", Default = false,
        Callback = function(v) placeOn = v end })
    placeToggle:Keybind({ Name = "Toggle auto shelve", Flag = "SM_AutoPlaceKey", Mode = "Toggle",
        Default = Enum.KeyCode.B, Callback = function() placeToggle:Set(not placeToggle.Value) end })
    SecA:Slider({ Name = "Shelve delay", Flag = "SM_PlaceDelay", Min = 10, Max = 500, Default = 60, Decimals = 0, Suffix = " ms",
        Callback = function(v) placeDelay = v / 1000 end })
    SecA:Slider({ Name = "Act range", Flag = "SM_Range", Min = 4, Max = 18, Default = 12, Decimals = 0, Suffix = " studs",
        Callback = function(v) autoRange = v end })
    SecA:Label({ Name = "capped to your real reach -- you still walk" })

    local SecF = Sub:Section({ Name = "Shelf finder", Side = 2 })
    SecF:Toggle({ Name = "Shelf finder", Flag = "SM_Finder", Default = false,
        Callback = function(v) finderOn = v end })
    SecF:Label({ Name = "beam + glow on the shelf your item belongs to" })

    local SecCam = Sub:Section({ Name = "Camera", Side = 1 })
    SecCam:Toggle({ Name = "Third person", Flag = "SM_ThirdPerson", Default = false,
        Callback = function(v) thirdPerson = v end })
    SecCam:Slider({ Name = "Max zoom", Flag = "SM_TPDist", Min = 6, Max = 30, Default = 14, Decimals = 0, Suffix = " studs",
        Callback = function(v) tpDist = v end })

    local SecC = Sub:Section({ Name = "Find category items", Side = 2 })
    SecC:Toggle({ Name = "Highlight category items", Flag = "SM_CatEsp", Default = false,
        Callback = function(v) catEspOn = v end })
    SecC:Dropdown({ Name = "Categories", Flag = "SM_Categories", Items = catList, Multi = true,
        Callback = function(v)
            selectedCats = {}
            for _, name in ipairs(v or {}) do selectedCats[name] = true end
        end })
    SecC:Slider({ Name = "Highlight radius", Flag = "SM_CatEspRadius", Min = 20, Max = 200, Default = 60, Decimals = 0, Suffix = " studs",
        Callback = function(v) catEspRadius = v end })
    SecC:Label({ Name = "no selection = all; colour-coded per category" })
end

-- universal shell after our page so Supermarket stays the first sub-tab
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- ============================================================
--  Teardown
-- ============================================================
local function cleanup()
    pickupOn, placeOn, finderOn, catEspOn = false, false, false, false
    if _origMode ~= nil then
        pcall(function()
            LocalPlayer.CameraMode = _origMode
            LocalPlayer.CameraMaxZoomDistance = _origMaxZoom
        end)
        _origMode, _origMaxZoom = nil, nil
    end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, hl in ipairs(catPool) do pcall(function() hl:Destroy() end) end
    for _, inst in ipairs({ zoneHl, fixHl, a0char, beamPart, corePart, coreHl }) do
        pcall(function() inst:Destroy() end)
    end
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
