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
local Library = load("lib/nhack.lua")()
_G.Library = Library
getgenv().Library = Library
if getgenv then getgenv().WH.lib = Library end

-- ============================================================
--  TEST GUI
--  Minimal nhack layout exercising the core widgets so we can confirm the
--  vendored library loads and renders. Replace with real per-game UI later.
-- ============================================================
local Watermark = Library:Watermark({
    Name = "wrath.cc"
})

Watermark:SetDynamicTextProvider(function(Fps)
    return string.format("wrath.cc | %dfps | %s", Fps, os.date("%X"))
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
    Title = "Landryhaxx",
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

local Page = Window:Page({ Name = "Main" })
local SubPage = Page:SubPage({ Name = "Combat" })

local LeftSection = SubPage:Section({ Name = "Aimbot", Side = 1 })
local RightSection = SubPage:Section({ Name = "Visuals", Side = 2 })

LeftSection:Toggle({
    Name = "Enable Aimbot",
    Flag = "AimbotEnabled",
    Default = false,
    Callback = function(Value)
    end
})

LeftSection:Slider({
    Name = "FOV",
    Flag = "AimbotFOV",
    Default = 90,
    Min = 1,
    Max = 360,
    Decimals = 0,
    Suffix = "",
    Callback = function(Value)
    end
})

RightSection:Toggle({
    Name = "ESP",
    Flag = "ESPEnabled",
    Default = false,
    Callback = function(Value)
    end
})

Library:Notification("Landryhaxx Loaded", 3, Library.Theme["Accent"])

Window:CreateSettingsPage()

print("[wh] foundation test GUI loaded")
