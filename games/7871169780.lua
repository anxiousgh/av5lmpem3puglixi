-- ============================================================
--  games/7871169780.lua  --  bLockerman's Minesweeper
--  Mine ESP + solver, auto-flag (Legit / Blatant) and a flag triggerbot.
--
--  Solver: reads each revealed tile's NumberGui, runs basic rules + subset
--  reduction + brute-force "tank" on the exact 5-stud grid, paints covered
--  tiles red (mine) / green (safe) via per-tile SurfaceGuis (client-side).
--  PERF: grid + neighbour graph cached; solver only RUNS on board change
--  (a NumberGui/flag Model appears); tank capped + budgeted.
--
--  Flags: PlaceFlag:FireServer(tile, token, true). The token is the per-session
--  workspace.Salasana.Value, which the game reads then destroys, so we capture
--  it with a read-only __namecall hook the first time ANY PlaceFlag fires.
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local RS          = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local MS = {
    espOn = false, showMines = true, showSafe = true,
    mineColor = Color3.fromRGB(255, 40, 40),
    safeColor = Color3.fromRGB(40, 220, 80),
    rate = 0.15, fill = 0.45,
    -- flagging
    flagOn = false, flagMode = "Legit", flagRange = 0,
    flagDelayMin = 0.4, flagDelayMax = 0.9, flagTrigger = false,
}

-- generation guard so old instances stop when the hub reloads
getgenv()._BMS_GEN = (getgenv()._BMS_GEN or 0) + 1
local _gen = getgenv()._BMS_GEN
local function active() return getgenv()._BMS_GEN == _gen end

-- ---------- board reading ----------
local function getParts()
    local flag = workspace:FindFirstChild("Flag")
    return flag and flag:FindFirstChild("Parts")
end
local function tileState(tile)
    if tile:FindFirstChildOfClass("Model") then return "flagged" end
    if tile:FindFirstChild("NumberGui") then return "revealed" end
    return "covered"
end
local function tileNumber(tile)
    local g = tile:FindFirstChild("NumberGui")
    if not g then return 0 end
    local lbl = g:FindFirstChildWhichIsA("TextLabel", true)
    return (lbl and tonumber(lbl.Text)) or 0   -- blank label = a 0-tile
end

-- ---------- flag placement (token-gated PlaceFlag) ----------
local PlaceFlag
pcall(function() PlaceFlag = RS:WaitForChild("Events", 9):WaitForChild("FlagEvents", 9):WaitForChild("PlaceFlag", 9) end)
-- read-only __namecall hook: grab the per-session token whenever a PlaceFlag fires (your
-- first manual flag arms it). Persisted on getgenv so it survives reloads / re-installs once.
if PlaceFlag and hookmetamethod and getnamecallmethod and not getgenv()._BMS_FLAGHOOK then
    getgenv()._BMS_FLAGHOOK = true
    local old
    local function hook(self, ...)
        if self == PlaceFlag and getnamecallmethod() == "FireServer" then
            local _, tok = ...
            if type(tok) == "string" and #tok >= 8 then getgenv()._BMS_TOKEN = tok end
        end
        return old(self, ...)
    end
    old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(hook) or hook)
end
local function fireFlag(tile)
    local tok = getgenv()._BMS_TOKEN
    if tok and PlaceFlag and tile then pcall(function() PlaceFlag:FireServer(tile, tok, true) end) end
end
local function myPos()
    local c = LocalPlayer.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
end

-- ---------- cached grid + neighbour graph + dirty flags ----------
local _grid, _coord, _neighbors, _tileList
local _gridDirty, _boardDirty = true, true
local _watchedFolder
local function watchParts(parts)
    if _watchedFolder == parts then return end
    _watchedFolder = parts
    _gridDirty, _boardDirty = true, true
    parts.ChildAdded:Connect(function() _gridDirty = true; _boardDirty = true end)
    parts.ChildRemoved:Connect(function() _gridDirty = true; _boardDirty = true end)
    parts.DescendantAdded:Connect(function(d)
        if d.Name == "NumberGui" or d:IsA("Model") then _boardDirty = true end
    end)
    parts.DescendantRemoving:Connect(function(d)
        if d.Name == "NumberGui" or d:IsA("Model") then _boardDirty = true end
    end)
end
local function ensureGrid(parts)
    watchParts(parts)
    if _grid and not _gridDirty then return end
    _gridDirty = false
    local tiles = parts:GetChildren()
    local size
    for _, t in ipairs(tiles) do if t:IsA("BasePart") then size = t.Size.X; break end end
    if not size then _grid = nil; _tileList = nil; return end
    local grid, coord, list = {}, {}, {}
    for _, t in ipairs(tiles) do
        if t:IsA("BasePart") then
            local gx = math.floor(t.Position.X / size + 0.5)
            local gz = math.floor(t.Position.Z / size + 0.5)
            grid[gx .. "_" .. gz] = t; coord[t] = { gx, gz }; list[#list + 1] = t
        end
    end
    local neighbors = {}
    for _, t in ipairs(list) do
        local c, o = coord[t], {}
        for dx = -1, 1 do for dz = -1, 1 do
            if not (dx == 0 and dz == 0) then
                local n = grid[(c[1] + dx) .. "_" .. (c[2] + dz)]
                if n then o[#o + 1] = n end
            end
        end end
        neighbors[t] = o
    end
    _grid, _coord, _neighbors, _tileList = grid, coord, neighbors, list
end

-- ---------- solver ----------
local function buildConstraints(tiles, neighbors, state, number, mines, safes)
    local cons = {}
    for _, t in ipairs(tiles) do
        if state[t] == "revealed" then
            local n = number[t]
            if n and n > 0 then
                local minesIn, set, list = 0, {}, {}
                local nbrs = neighbors[t]
                if nbrs then
                    for _, nb in ipairs(nbrs) do
                        if mines[nb] then minesIn = minesIn + 1
                        elseif safes[nb] then
                        elseif state[nb] == "covered" or state[nb] == "flagged" then
                            if not set[nb] then set[nb] = true; list[#list + 1] = nb end
                        end
                    end
                end
                if #list > 0 then cons[#cons + 1] = { set = set, list = list, rem = n - minesIn, count = #list } end
            end
        end
    end
    return cons
end
local function basicPass(cons, mines, safes)
    local changed = false
    for _, c in ipairs(cons) do
        if c.rem == c.count then
            for _, u in ipairs(c.list) do if not mines[u] then mines[u] = true; changed = true end end
        elseif c.rem == 0 then
            for _, u in ipairs(c.list) do if not safes[u] then safes[u] = true; changed = true end end
        end
    end
    return changed
end
local function subsetPass(cons, mines, safes)
    if #cons < 2 then return false end
    local changed = false
    local varToCs = {}
    for i, c in ipairs(cons) do
        for u in pairs(c.set) do
            local l = varToCs[u]; if not l then l = {}; varToCs[u] = l end
            l[#l + 1] = i
        end
    end
    for i = 1, #cons do
        local A = cons[i]
        local cand = {}
        for u in pairs(A.set) do
            for _, j in ipairs(varToCs[u]) do if j ~= i then cand[j] = true end end
        end
        for j in pairs(cand) do
            local B = cons[j]
            if A.count < B.count then
                local subset = true
                for u in pairs(A.set) do if not B.set[u] then subset = false; break end end
                if subset then
                    local extras = {}
                    for u in pairs(B.set) do if not A.set[u] then extras[#extras + 1] = u end end
                    local em = B.rem - A.rem
                    if em == #extras and em > 0 then
                        for _, u in ipairs(extras) do if not mines[u] then mines[u] = true; changed = true end end
                    elseif em == 0 then
                        for _, u in ipairs(extras) do if not safes[u] then safes[u] = true; changed = true end end
                    end
                end
            end
        end
    end
    return changed
end
local TANK_MAX, TANK_BUDGET = 14, 300000
local function tankPass(cons, mines, safes)
    if #cons == 0 then return false end
    local parent = {}
    local function find(x) while parent[x] ~= x do x = parent[x] end return x end
    local function union(a, b) a = find(a); b = find(b); if a ~= b then parent[a] = b end end
    local allUnk, seen = {}, {}
    for _, c in ipairs(cons) do
        for u in pairs(c.set) do if not seen[u] then seen[u] = true; parent[u] = u; allUnk[#allUnk + 1] = u end end
    end
    for _, c in ipairs(cons) do local prev; for u in pairs(c.set) do if prev then union(prev, u) end; prev = u end end
    local gUnk, gCons = {}, {}
    for _, u in ipairs(allUnk) do local r = find(u); gUnk[r] = gUnk[r] or {}; table.insert(gUnk[r], u) end
    for _, c in ipairs(cons) do
        local a; for u in pairs(c.set) do a = u; break end
        if a then local r = find(a); gCons[r] = gCons[r] or {}; table.insert(gCons[r], c) end
    end
    local changed, budget = false, TANK_BUDGET
    for root, unknowns in pairs(gUnk) do
        local n = #unknowns
        local twoN = 2 ^ n
        if n > 0 and n <= TANK_MAX and twoN <= budget then
            budget = budget - twoN
            local gcs = gCons[root] or {}
            local idx = {}; for i = 1, n do idx[unknowns[i]] = i end
            local cIdx, cRem = {}, {}
            for ci, c in ipairs(gcs) do
                local l = {}; for u in pairs(c.set) do l[#l + 1] = idx[u] end
                cIdx[ci] = l; cRem[ci] = c.rem
            end
            local yes, no, total, assign = {}, {}, 0, {}
            for i = 1, n do yes[i] = 0; no[i] = 0 end
            for mask = 0, twoN - 1 do
                local m = mask
                for i = 1, n do local b = m % 2; assign[i] = b; m = (m - b) / 2 end
                local valid = true
                for ci = 1, #gcs do
                    local l, mc = cIdx[ci], 0
                    for k = 1, #l do mc = mc + assign[l[k]] end
                    if mc ~= cRem[ci] then valid = false; break end
                end
                if valid then
                    total = total + 1
                    for i = 1, n do if assign[i] == 1 then yes[i] = yes[i] + 1 else no[i] = no[i] + 1 end end
                end
            end
            if total > 0 then
                for i = 1, n do
                    local u = unknowns[i]
                    if yes[i] == total and not mines[u] then mines[u] = true; changed = true
                    elseif no[i] == total and not safes[u] then safes[u] = true; changed = true end
                end
            end
        end
    end
    return changed
end
local function deduce(tiles, neighbors, state, number)
    local mines, safes = {}, {}
    for _ = 1, 6 do
        while true do
            local cons = buildConstraints(tiles, neighbors, state, number, mines, safes)
            local c1 = basicPass(cons, mines, safes)
            local c2 = subsetPass(cons, mines, safes)
            if not (c1 or c2) then break end
        end
        local cons = buildConstraints(tiles, neighbors, state, number, mines, safes)
        if not tankPass(cons, mines, safes) then break end
    end
    return mines, safes
end

-- ---------- ESP ----------
local _surfaces = {}
local _lastMines = {}   -- latest deduced mine set (consumed by auto-flag / triggerbot)
local function ensureSurface(tile)
    local sg = _surfaces[tile]
    if sg and sg.Parent then return sg end
    sg = Instance.new("SurfaceGui")
    sg.Name, sg.Face, sg.AlwaysOnTop, sg.LightInfluence = "_MS_ESP", Enum.NormalId.Top, false, 0
    sg.Adornee, sg.Parent = tile, tile
    local fr = Instance.new("Frame")
    fr.Name, fr.Size, fr.BorderSizePixel = "Fill", UDim2.fromScale(1, 1), 0
    fr.Parent = sg
    local st = Instance.new("UIStroke"); st.Thickness = 4; st.Parent = fr
    _surfaces[tile] = sg
    return sg
end
local function paint(tile, color)
    local sg = ensureSurface(tile)
    local fr = sg:FindFirstChild("Fill")
    if fr then
        fr.BackgroundColor3 = color
        fr.BackgroundTransparency = MS.fill
        local st = fr:FindFirstChildOfClass("UIStroke"); if st then st.Color = color end
    end
    sg.Enabled = true
end
local function clearSurfaces()
    for _, sg in pairs(_surfaces) do pcall(function() sg:Destroy() end) end
    _surfaces = {}
end
do  -- wipe stray ESP surfaces from a previous load
    local parts = getParts()
    if parts then for _, t in ipairs(parts:GetChildren()) do
        local sg = t:FindFirstChild("_MS_ESP"); if sg then pcall(function() sg:Destroy() end) end
    end end
end

local _statLbl, _tokLbl
local function solveAndRender()
    local parts = getParts(); if not parts then return end
    ensureGrid(parts)
    if not _tileList then return end
    local state, number = {}, {}
    for _, t in ipairs(_tileList) do
        if t.Parent then
            local s = tileState(t); state[t] = s
            if s == "revealed" then number[t] = tileNumber(t) end
        end
    end
    local mines, safes = deduce(_tileList, _neighbors, state, number)
    _lastMines = mines
    local seen, nm, ns = {}, 0, 0
    if MS.showMines then for t in pairs(mines) do seen[t] = true; nm = nm + 1; paint(t, MS.mineColor) end end
    if MS.showSafe then for t in pairs(safes) do if not seen[t] then seen[t] = true; ns = ns + 1; paint(t, MS.safeColor) end end end
    for t, sg in pairs(_surfaces) do
        if not t.Parent then pcall(function() sg:Destroy() end); _surfaces[t] = nil
        elseif not seen[t] then sg.Enabled = false end
    end
    if _statLbl then pcall(function() _statLbl:SetText(("Mines: %d  |  Safe: %d"):format(nm, ns)) end) end
end
local _espThread
local function espStart()
    if _espThread then return end
    _boardDirty = true
    _espThread = task.spawn(function()
        while MS.espOn and active() do
            if _boardDirty then _boardDirty = false; pcall(solveAndRender) end
            task.wait(MS.rate)
        end
        _espThread = nil
    end)
end
local function espStop()
    MS.espOn = false
    clearSurfaces()
    if _statLbl then pcall(function() _statLbl:SetText("Mines: 0  |  Safe: 0") end) end
end

-- ---------- auto flag + flag triggerbot ----------
local _flagged = {}   -- tile -> tick() we flagged it (re-firing a flagged tile UN-flags it)
local function handled(tile)
    if tileState(tile) == "flagged" then return true end
    local t = _flagged[tile]; return t ~= nil and (tick() - t < 2)
end
local function flagTargets()
    local out, mp = {}, myPos()
    for tile in pairs(_lastMines) do
        if tile.Parent and not handled(tile) then
            if MS.flagRange <= 0 or not mp or (tile.Position - mp).Magnitude <= MS.flagRange then
                out[#out + 1] = tile
            end
        end
    end
    if mp then table.sort(out, function(a, b) return (a.Position - mp).Magnitude < (b.Position - mp).Magnitude end) end
    return out
end
local _flagThread
local function flagStart()
    if _flagThread then return end
    _flagThread = task.spawn(function()
        while MS.flagOn and active() do
            if getgenv()._BMS_TOKEN then
                local targets = flagTargets()
                if MS.flagMode == "Blatant" then
                    for _, t in ipairs(targets) do _flagged[t] = tick(); fireFlag(t) end   -- all around me, fast
                    task.wait(0.05)
                else
                    local t = targets[1]                                                   -- Legit: closest, one at a time
                    if t then
                        _flagged[t] = tick(); fireFlag(t)
                        task.wait(MS.flagDelayMin + math.random() * math.max(MS.flagDelayMax - MS.flagDelayMin, 0))
                    else task.wait(0.15) end
                end
            else task.wait(0.3) end
        end
        _flagThread = nil
    end)
end
-- flag triggerbot: hover a deduced-mine tile -> flag it
local _mouse = LocalPlayer:GetMouse()
if getgenv()._BMS_TRIGCONN then pcall(function() getgenv()._BMS_TRIGCONN:Disconnect() end) end
getgenv()._BMS_TRIGCONN = RunService.RenderStepped:Connect(function()
    if not (MS.flagTrigger and active() and getgenv()._BMS_TOKEN) then return end
    local tgt = _mouse.Target
    if tgt and _lastMines[tgt] and not handled(tgt) then
        _flagged[tgt] = tick(); fireFlag(tgt)
    end
end)

-- ---------- UI ----------
local MainPage = Window:Page({ Name = "Minesweeper" })
local Sub = MainPage:SubPage({ Name = "Solver" })
do
    local Sec = Sub:Section({ Name = "Mine ESP", Side = 1 })
    Sec:Toggle({ Name = "Enabled", Flag = "MS_Esp", Default = false,
        Callback = function(v) MS.espOn = v; if v then espStart() else espStop() end end })
    Sec:Toggle({ Name = "Show mines", Flag = "MS_Mines", Default = true,
        Callback = function(v) MS.showMines = v; _boardDirty = true end })
    Sec:Toggle({ Name = "Show safe tiles", Flag = "MS_Safe", Default = true,
        Callback = function(v) MS.showSafe = v; _boardDirty = true end })
    Sec:Slider({ Name = "Update rate", Flag = "MS_Rate", Min = 50, Max = 1000, Default = 150, Decimals = 0, Suffix = " ms",
        Callback = function(v) MS.rate = v / 1000 end })
    Sec:Slider({ Name = "Fill transparency", Flag = "MS_Fill", Min = 0, Max = 100, Default = 45, Decimals = 0, Suffix = "%",
        Callback = function(v) MS.fill = v / 100; _boardDirty = true end })

    local Sec2 = Sub:Section({ Name = "Colors", Side = 2 })
    Sec2:Label({ Name = "Mine color" }):Colorpicker({ Flag = "MS_MineCol", Default = MS.mineColor,
        Callback = function(c) MS.mineColor = c; _boardDirty = true end })
    Sec2:Label({ Name = "Safe color" }):Colorpicker({ Flag = "MS_SafeCol", Default = MS.safeColor,
        Callback = function(c) MS.safeColor = c; _boardDirty = true end })

    local Sec3 = Sub:Section({ Name = "Stats", Side = 2 })
    _statLbl = Sec3:Label({ Name = "Mines: 0  |  Safe: 0" })
end

local FlagSub = MainPage:SubPage({ Name = "Auto Flag" })
do
    local Sec = FlagSub:Section({ Name = "Auto Flag", Side = 1 })
    Sec:Toggle({ Name = "Enabled", Flag = "MS_Flag", Default = false,
        Callback = function(v) MS.flagOn = v; if v then flagStart() end end })
    Sec:Dropdown({ Name = "Mode", Flag = "MS_FlagMode", Default = "Legit", Multi = false,
        Items = { "Legit", "Blatant" },
        Callback = function(v) MS.flagMode = (type(v) == "table" and v[1]) or v or "Legit" end })
    Sec:Slider({ Name = "Range (0 = whole board)", Flag = "MS_FlagRange", Min = 0, Max = 400, Default = 0, Decimals = 0, Suffix = " studs",
        Callback = function(v) MS.flagRange = v end })
    Sec:Slider({ Name = "Legit delay min", Flag = "MS_FlagDMin", Min = 0, Max = 3000, Default = 400, Decimals = 0, Suffix = " ms",
        Callback = function(v) MS.flagDelayMin = v / 1000 end })
    Sec:Slider({ Name = "Legit delay max", Flag = "MS_FlagDMax", Min = 0, Max = 3000, Default = 900, Decimals = 0, Suffix = " ms",
        Callback = function(v) MS.flagDelayMax = v / 1000 end })

    local Sec2 = FlagSub:Section({ Name = "Flag triggerbot", Side = 2 })
    Sec2:Toggle({ Name = "Flag on hover", Flag = "MS_FlagTrig", Default = false,
        Callback = function(v) MS.flagTrigger = v end })
    Sec2:Label({ Name = "Hover a red (mine) tile to flag it" })

    local Sec3 = FlagSub:Section({ Name = "Token", Side = 2 })
    _tokLbl = Sec3:Label({ Name = "Token: place 1 flag to arm" })
end
task.spawn(function()
    while active() do
        if _tokLbl then pcall(function() _tokLbl:SetText(getgenv()._BMS_TOKEN and "Token: ARMED" or "Token: place 1 flag to arm") end) end
        task.wait(1)
    end
end)

-- universal shell (movement utilities, Settings, Hide watermark/notifications)
pcall(function() ctx.load("games/universal.lua")(ctx) end)
