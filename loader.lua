-- ============================================================
--  loader.lua  --  entry point
--
--  Boots our VENDORED copy of the nhack UI library (lib/nhack.lua, which
--  lives in this same repo so we can modify it) and builds a small test GUI
--  to prove the pipeline works end to end.
--
--  Public repo: fetched with plain game:HttpGet, no key needed.
--    loadstring(game:HttpGet("https://raw.githubusercontent.com/anxiousgh/av5lmpem3puglixi/main/loader.lua"))()
--
--  This is the FOUNDATION only -- no feature backend yet. We grow from here:
--  core engine, shared UI pages and per-game UI modes get added later.
-- ============================================================

-- ---------- single-instance guard ----------
-- On re-execution, tear the PREVIOUS instance down first: turn off every
-- feature/exploit (disableAll) and destroy the old GUI (lib:Exit). Otherwise
-- the old instance's loops (cframe speed, camlock, ...) keep running and you
-- get stuck. Then we continue and build a fresh instance.
if getgenv then
    local g = getgenv()
    local prev = g.WH
    if prev then
        pcall(function() if prev.disableAll then prev.disableAll() end end)
        pcall(function() if prev.lib and prev.lib.Exit then prev.lib:Exit() end end)
    end
    g.WH = { lib = false, disableAll = false }
end

-- ---------- config ----------
local OWNER  = "anxiousgh"
local REPO   = "av5lmpem3puglixi"
local BRANCH = "main"

-- raw.githubusercontent AND most executor HttpGet caches ignore query strings,
-- so pin the URL to the latest commit SHA (a unique path the cache can't
-- stale). Fall back to the branch if the API call fails.
local BASE
do
    local okSha, body = pcall(game.HttpGet, game,
        ("https://api.github.com/repos/%s/%s/commits/%s"):format(OWNER, REPO, BRANCH))
    local sha = okSha and type(body) == "string" and body:match('"sha"%s*:%s*"(%x+)"')
    if sha then
        BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, sha)
        print("[wh] pinned to commit " .. sha:sub(1, 12))
    else
        BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(OWNER, REPO, BRANCH)
        warn("[wh] commit pin failed - using branch (may be cached)")
    end
end

-- ---------- raw fetch helpers ----------
local function fetch(path)
    return game:HttpGet(BASE .. path)
end
local function load(path)
    local fn, err = loadstring(fetch(path))
    if not fn then
        error(("[wh] %s failed to compile: %s"):format(path, tostring(err)), 0)
    end
    return fn
end

-- ---------- load the vendored UI library ----------
local Library = load("lib/nhack.lua")()
_G.Library = Library
getgenv().Library = Library
if getgenv then getgenv().WH.lib = Library end

-- ============================================================
--  PERSISTENT WIDGETS  (overlays that live outside the main window)
-- ============================================================
local Watermark = Library:Watermark({
    Name = "wrath.cc"
})

-- The brand "wrath.cc" (with ".cc" in accent) is drawn by the watermark itself
-- from the Name above, as separate labels. This provider returns only the
-- dynamic suffix that follows it.
Watermark:SetDynamicTextProvider(function(Fps)
    return string.format(" | %dfps | %s", Fps, os.date("%X"))
end)

local KeybindList = Library:KeybindList({
    Name = "Keybinds"
})

local ESPPreview = Library:ESPPreview({
    Name = "ESP Preview"
})

local TargetIndicator = Library:TargetIndicator()

local Logger = Library:ConsoleLogger({
    Name = "Console",
    Callback = function(Text, Log)
        Log:AddOutput(Text)
    end
})

local Inventory = Library:InventoryViewer({
    Name = "Inventory"
})

local Playerlist = Library:Playerlist({
    Name = "Players"
})

local Window = Library:Window({
    Title = "wrath.cc",
    ButtonName = "Main UI"
})

Library:RegisterSettingsWidget({
    Name = "Watermark",
    Default = true,
    Callback = function(Value)
        Watermark:SetVisibility(Value)
    end
})

Library:RegisterSettingsWidget({
    Name = "Keybind List",
    Default = true,
    Callback = function(Value)
        KeybindList:SetVisibility(Value)
    end
})

Library:RegisterSettingsWidget({
    Name = "ESP Preview",
    Default = false,
    Callback = function(Value)
        ESPPreview:SetVisibility(Value)
    end
})

Library:RegisterSettingsWidget({
    Name = "Target Indicator",
    Default = false,
    Callback = function(Value)
        TargetIndicator:SetVisibility(Value)
    end
})

Library:RegisterSettingsWidget({
    Name = "Console",
    Default = false,
    Callback = function(Value)
        Logger:SetVisibility(Value)
    end
})

Library:RegisterSettingsWidget({
    Name = "Inventory",
    Default = false,
    Callback = function(Value)
        Inventory:SetVisibility(Value)
    end
})

Library:RegisterSettingsWidget({
    Name = "Player List",
    Default = false,
    Callback = function(Value)
        Playerlist:SetVisibility(Value)
    end
})

-- ============================================================
--  GAME DISPATCH
--  Run a per-game module (games/<PlaceId>.lua) if one exists, otherwise the
--  universal shell. Each module builds its pages on the shared Window via ctx.
-- ============================================================
local ctx = {
    Library     = Library,
    Window      = Window,
    Watermark   = Watermark,
    KeybindList = KeybindList,
    Playerlist  = Playerlist,
    fetch       = fetch,
    load        = load,
    base        = BASE,
    placeId     = tostring(game.PlaceId),
}

-- A fetched body counts as "missing" if it's empty or GitHub's 404 text
-- (some executors return ""/"404: Not Found" instead of erroring on 404).
local function bodyIsMissing(body)
    if type(body) ~= "string" then return true end
    if #(body:gsub("%s+", "")) == 0 then return true end
    if body:find("404: Not Found", 1, true) then return true end
    return false
end

local function tryGameModule(key)
    local okFetch, body = pcall(game.HttpGet, game, BASE .. "games/" .. key .. ".lua")
    if not okFetch or bodyIsMissing(body) then return false end
    local fn, compileErr = loadstring(body)
    if not fn then
        warn("[wh] games/" .. key .. ".lua compile error: " .. tostring(compileErr))
        return false
    end
    local okRun, runErr = pcall(fn, ctx)
    if not okRun then
        warn("[wh] games/" .. key .. ".lua runtime error: " .. tostring(runErr))
        return false
    end
    print("[wh] loaded per-game module: games/" .. key .. ".lua")
    return true
end

if not tryGameModule(ctx.placeId) then
    local okU, errU = pcall(function() load("games/universal.lua")(ctx) end)
    if okU then
        print("[wh] loaded universal shell")
    else
        warn("[wh] universal shell failed: " .. tostring(errU))
    end
end

-- Settings page (config + themes) -- added last so it's the final tab.
Window:CreateSettingsPage()

Library:Notification("wrath.cc Loaded", 3, Library.Theme["Accent"])

print("[wh] loaded")
