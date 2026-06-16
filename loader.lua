-- ============================================================
--  loader.lua  --  entry point
--
--  Boots our VENDORED copy of the Mentality UI library (lib/Mentality.lua,
--  which lives in this same repo so we can modify it) and builds a small
--  test GUI to prove the pipeline works end to end.
--
--  Public repo: fetched with plain game:HttpGet, no key needed.
--    loadstring(game:HttpGet("https://raw.githubusercontent.com/anxiousgh/av5lmpem3puglixi/main/loader.lua"))()
--
--  This is the FOUNDATION only -- no feature backend yet. We grow from here:
--  core engine, shared UI pages and per-game UI modes get added later.
-- ============================================================

-- ---------- single-instance guard ----------
-- Refuse a second execution while a live instance exists, so we never stack
-- duplicate GUIs. Re-execution is allowed again once unloaded.
if getgenv then
    local g = getgenv()
    local prev = g.WH
    if prev and prev.lib and not prev.lib.Unloaded then
        warn("[wh] already loaded - ignoring duplicate execution")
        return
    end
    g.WH = { lib = false }
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
local Library = load("lib/Mentality.lua")()
if getgenv then getgenv().WH.lib = Library end

-- ============================================================
--  TEST GUI
--  Minimal window exercising the core Mentality widgets so we can confirm
--  the vendored library loads and renders. Replace with real per-game UI later.
-- ============================================================
local Window = Library:Window({
    Name    = "av5lmpem3puglixi",
    SubName = "foundation test",
    Logo    = "120959262762131",
})

local KeybindList = Library:KeybindList("Keybinds")

Window:Category("Test")

local MainPage = Window:Page({ Name = "Main", Icon = "138827881557940" })

local Section = MainPage:Section({
    Name        = "Sanity check",
    Description = "Confirms the vendored library works",
    Side        = 1,
})

Section:Toggle({
    Name     = "Test toggle",
    Flag     = "TestToggle",
    Default  = false,
    Callback = function(value)
        print("[wh] test toggle:", value)
    end,
})

Section:Slider({
    Name     = "Test slider",
    Flag     = "TestSlider",
    Min      = 0,
    Max      = 100,
    Default  = 25,
    Decimals = 0,
    Suffix   = "%",
    Callback = function(value)
        print("[wh] test slider:", value)
    end,
})

Section:Dropdown({
    Name     = "Test dropdown",
    Flag     = "TestDropdown",
    Default  = { "First" },
    Items    = { "First", "Second", "Third" },
    Multi    = false,
    Callback = function(value)
        print("[wh] test dropdown:", value)
    end,
})

Section:Keybind({
    Name     = "Test keybind",
    Flag     = "TestKeybind",
    Default  = Enum.KeyCode.RightShift,
    Callback = function(value)
        print("[wh] test keybind:", value)
    end,
})

Section:Label("If you can read this, the vendored library loaded.")

-- Settings page (config save/load + keybind list) provided by the library.
Library:CreateSettingsPage(Window, KeybindList)

Library:Notification({
    Title       = "av5lmpem3puglixi",
    Description = "Foundation loaded - vendored Mentality is working.",
    Duration    = 5,
    Icon        = "73789337996373",
})

Window:Init()

print("[wh] foundation test GUI loaded")
