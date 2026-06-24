-- ============================================================
--  games/7871169780.lua  --  bLockerman's Minesweeper
--  Mine ESP + solver. Reads every revealed tile's NumberGui, runs a
--  minesweeper constraint solver (basic rules + subset reduction +
--  brute-force "tank" for the hard patterns), and colours covered tiles
--  red (mine) / green (safe) via per-tile SurfaceGuis (client-side).
--
--  PERF: the grid + neighbour graph is cached and only rebuilt when tiles
--  are added/removed; the solver only RUNS when the board actually changes
--  (a NumberGui / flag Model appears), so idle frames cost nothing. The
--  brute-force tank is capped + budgeted so a big component can't hitch.
--  Builds its "Minesweeper" tab first, then loads the universal shell.
-- ============================================================
local ctx     = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local MS = {
    espOn = false, showMines = true, showSafe = true,
    mineColor = Color3.fromRGB(255, 40, 40),
    safeColor = Color3.fromRGB(40, 220, 80),
    rate = 0.15, fill = 0.45,
}

-- ---------- board reading ----------
local function getParts()
    local flag = workspace:FindFirstChild("Flag")
    return flag and flag:FindFirstChild("Parts")
end
-- flagged = has a Model child (the flag); revealed = has a NumberGui; else covered.
-- FindFirstChild* (no GetChildren) so this allocates nothing per call.
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

-- ---------- cached grid + neighbour graph + dirty flags ----------
-- The board is a flat 5-stud grid so neighbours are exact. We cache the grid
-- and precomputed neighbour lists, rebuilding only when tiles are added/removed.
local _grid, _coord, _neighbors, _tileList
local _gridDirty, _boardDirty = true, true
local _watchedFolder
local function watchParts(parts)
    if _watchedFolder == parts then return end
    _watchedFolder = parts                       -- folder changed (new round) -> rewire
    _gridDirty, _boardDirty = true, true
    parts.ChildAdded:Connect(function() _gridDirty = true; _boardDirty = true end)
    parts.ChildRemoved:Connect(function() _gridDirty = true; _boardDirty = true end)
    -- a reveal adds a NumberGui; a flag adds a Model -> only those mark the board dirty
    -- (our own "_MS_ESP" SurfaceGui is neither, so painting never re-triggers a solve)
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
            grid[gx .. "_" .. gz] = t
            coord[t] = { gx, gz }
            list[#list + 1] = t
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
                        elseif safes[nb] then                                  -- known safe -> drop
                        elseif state[nb] == "covered" or state[nb] == "flagged" then
                            if not set[nb] then set[nb] = true; list[#list + 1] = nb end  -- don't trust user flags
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
-- brute-force connected components. Capped at TANK_MAX unknowns and a per-call
-- enumeration budget so a big blob can never freeze the frame.
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
    for _ = 1, 6 do                       -- basic+subset to fixed point, then ONE tank, repeat
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

-- ---------- ESP (SurfaceGui per tile, no Highlight cap) ----------
local _surfaces = {}
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
-- wipe any ESP surfaces left over from a previous load (so reloads don't stack)
do
    local parts = getParts()
    if parts then
        for _, t in ipairs(parts:GetChildren()) do
            local sg = t:FindFirstChild("_MS_ESP")
            if sg then pcall(function() sg:Destroy() end) end
        end
    end
end

local _statLbl
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
    _boardDirty = true               -- force a first solve
    _espThread = task.spawn(function()
        while MS.espOn do
            if _boardDirty then       -- only do real work when the board actually changed
                _boardDirty = false
                pcall(solveAndRender)
            end
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

-- universal shell (movement utilities, Settings, Hide watermark/notifications)
pcall(function() ctx.load("games/universal.lua")(ctx) end)
