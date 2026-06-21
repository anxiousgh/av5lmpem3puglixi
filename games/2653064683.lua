-- ============================================================
--  games/2653064683.lua  --  Word Bomb
--
--  Auto-answer. The game validates words SERVER-side (no client dictionary), so we
--  just feed it a REAL word containing the current syllable, fetched from an English
--  word list. Submit = Network.Games.GameEvent:FireServer(GameID, "TypingEvent", word, true)
--  (the game's own final-submit call). The syllable is the InfoFrame.TextFrame letters;
--  it's our turn when the Typebar.Typebox goes Active. GameID is captured off GameEvent.
-- ============================================================
local ctx = ({ ... })[1]
local Library = ctx.Library
local Window  = ctx.Window

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local MainPage = Window:Page({ Name = "Main" })
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local S = { on = false, flex = false, mode = "Legit" }

-- ---- word list (fetched once; ~370k words) ----
local words, wordsReady = {}, false
task.spawn(function()
    local ok, body = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt")
    end)
    if ok and body then
        for w in body:gmatch("[%a]+") do words[#words + 1] = w end
        wordsReady = #words > 1000
    end
end)

-- rarity weighting for "hard-mode flex" (rarer letters = flashier word)
local RARE = { q = 12, j = 10, x = 9, z = 9, w = 5, v = 5, k = 5, f = 4, y = 3, b = 3, h = 3, p = 2 }
local function flexScore(w)
    local s = #w * 2
    for ch in w:gmatch("%a") do s = s + (RARE[ch] or 0) end
    return s
end
-- best word containing `syl`, not already tried. flex = longest/rarest, else shortest.
-- empty syllable = any word (just needs to be a valid word of decent length).
local function findWord(syl, tried, flex)
    syl = syl:lower()
    local minLen = math.max(#syl, 3)
    local best, bestScore
    for _, w in ipairs(words) do
        if #w >= minLen and not tried[w] and (syl == "" or w:find(syl, 1, true)) then
            local sc = flex and flexScore(w) or -#w   -- flex: max score; normal: shortest
            if not bestScore or sc > bestScore then bestScore, best = sc, w end
        end
    end
    return best
end

-- ---- remote + GameID ----
local gameEvent = game:GetService("ReplicatedStorage").Network.Games.GameEvent
local gameId
track(gameEvent.OnClientEvent:Connect(function(id) gameId = id end))   -- latest WordBomb game
local startGame = game:GetService("ReplicatedStorage").Network.Games:FindFirstChild("StartGame")
local function fire(...)
    if not gameId then return end
    local args = table.pack(...)
    pcall(function() gameEvent:FireServer(gameId, table.unpack(args, 1, args.n)) end)
end

-- ---- game Data via getgc: Prompt = clean syllable ('' = any word), and
--      Players[PossessorIndex] = the current player's UserId (so my turn = it's mine).
--      Far more reliable than scraping the UI letters (which keep stale ghosts). ----
local dataObj, lastScan = nil, 0
local function validData(o)
    if type(o) ~= "table" then return false end
    local ok, players = pcall(function() return o.Players end)
    return ok and type(players) == "table" and #players > 0
end
local function refreshData()
    if validData(dataObj) then return end
    if tick() - lastScan < 1.5 or type(getgc) ~= "function" then return end
    lastScan = tick()
    pcall(function()
        for _, o in ipairs(getgc(true)) do
            if type(o) == "table" and rawget(o, "Prompt") ~= nil
                and rawget(o, "PossessorIndex") ~= nil and type(rawget(o, "Players")) == "table" then
                dataObj = o; return
            end
        end
    end)
end
local function isMyTurn()
    if not dataObj then return false end
    local ok, who = pcall(function() return dataObj.Players[dataObj.PossessorIndex] end)
    return ok and who == LocalPlayer.UserId
end
local function getSyllable()
    if not dataObj then return "" end
    local ok, p = pcall(function() return dataObj.Prompt end)
    return (ok and type(p) == "string") and p or ""
end
-- the type bar label (TextLabel) -- only used to show the word locally in legit mode
local function getTypebox()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local ok, tb = pcall(function()
        return pg.GameUI.Container.GameSpace.DefaultUI.GameContainer.DesktopContainer.Typebar.Typebox
    end)
    return ok and tb or nil
end

-- ---- submit ----
-- Blatant: fire the finished word straight to the server (instant).
-- Legit: send REAL key presses via VirtualInputManager so the GAME'S OWN input types it
-- (the game listens to UserInputService.InputBegan -> builds the word + broadcasts each
-- keystroke), then Enter. The type bar, your nameplate and everyone else see real typing.
local VIM = game:GetService("VirtualInputManager")
local KEY = {}
for _, kc in ipairs(Enum.KeyCode:GetEnumItems()) do
    local n = kc.Name
    if #n == 1 and n:match("%a") then KEY[n:lower()] = kc end
end
local function submitBlatant(word)
    fire("TypingEvent", word:upper(), true)
end
local function submitLegit(word)
    task.wait(0.2 + math.random() * 0.35)             -- "reading" pause
    for c in word:lower():gmatch(".") do
        local kc = KEY[c]
        if kc then
            pcall(function() VIM:SendKeyEvent(true, kc, false, game) end)
            task.wait(0.02)
            pcall(function() VIM:SendKeyEvent(false, kc, false, game) end)
        end
        task.wait(0.06 + math.random() * 0.1)         -- per-keystroke delay
    end
    task.wait(0.08)
    pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.Return, false, game) end)   -- enter = submit
    task.wait(0.02)
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game) end)
end

-- ---- main loop ----
local tried, prevData = {}, nil
local busy = false
if startGame then track(startGame.OnClientEvent:Connect(function() tried = {} end)) end   -- new game = words reusable
task.spawn(function()
    while true do
        if S.on and wordsReady then
            refreshData()
            if dataObj ~= prevData then tried = {}; prevData = dataObj end   -- new game Data = reset used words
            if dataObj and not busy and isMyTurn() then
                local word = findWord(getSyllable(), tried, S.flex)
                if word then
                    tried[word] = true
                    busy = true
                    task.spawn(function()
                        if S.mode == "Blatant" then submitBlatant(word) else submitLegit(word) end
                        task.wait(0.6)   -- give the server a beat (retries another word if rejected/still our turn)
                        busy = false
                    end)
                end
            end
        end
        task.wait(0.12)
    end
end)

-- ============================================================
--  UI
-- ============================================================
do
    local Sub = MainPage:SubPage({ Name = "Word Bomb" })
    local Sec = Sub:Section({ Name = "Auto answer", Side = 1 })
    Sec:Toggle({ Name = "Auto answer", Flag = "WB_Auto", Default = false,
        Callback = function(v) S.on = v end })
    Sec:Dropdown({ Name = "Mode", Flag = "WB_Mode", Default = "Legit", Multi = false,
        Items = { "Legit", "Blatant" },
        Callback = function(v) S.mode = (type(v) == "table" and v[1]) or v or "Legit" end })
    Sec:Toggle({ Name = "Hard-mode flex (longest / rarest)", Flag = "WB_Flex", Default = false,
        Callback = function(v) S.flex = v end })
    local status = Sec:Label({ Name = "Loading word list..." })
    task.spawn(function()
        while not wordsReady do task.wait(0.25) end
        pcall(function() status:SetText(("Ready -- %d words"):format(#words)) end)
    end)
end

-- universal pages after Main
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- teardown
local function cleanup()
    S.on = false
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
