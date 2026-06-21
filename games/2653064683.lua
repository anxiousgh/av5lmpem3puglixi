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
local function findWord(syl, tried, flex)
    syl = syl:lower()
    if syl == "" then return nil end
    local best, bestScore
    for _, w in ipairs(words) do
        if #w >= #syl and not tried[w] and w:find(syl, 1, true) then
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
    if gameId then pcall(function() gameEvent:FireServer(gameId, ...) end) end
end

-- ---- UI reads: my turn + the syllable ----
local function deskContainer()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local ok, d = pcall(function() return pg.GameUI.Container.GameSpace.DefaultUI.GameContainer.DesktopContainer end)
    return ok and d or nil
end
local function getTypebox()
    local d = deskContainer()
    local tb = d and d:FindFirstChild("Typebar")
    return tb and tb:FindFirstChild("Typebox")
end
local function myTurn()
    local tb = getTypebox()
    return tb ~= nil and (tb.Active == true or tb.Visible == true)
end
local function readSyllable()
    local d = deskContainer(); if not d then return "" end
    local tf = d:FindFirstChild("InfoFrameContainer")
    tf = tf and tf:FindFirstChild("InfoFrame"); tf = tf and tf:FindFirstChild("TextFrame")
    if not tf then return "" end
    local fr = {}
    for _, c in ipairs(tf:GetChildren()) do
        local letter = c:FindFirstChild("Letter")
        local lbl = letter and letter:FindFirstChild("TextLabel")
        if lbl and #lbl.Text == 1 and lbl.Text:match("%a") then
            fr[#fr + 1] = { x = c.AbsolutePosition.X, ch = lbl.Text }
        end
    end
    table.sort(fr, function(a, b) return a.x < b.x end)   -- left-to-right
    local s = ""; for _, f in ipairs(fr) do s = s .. f.ch end
    return s
end

-- ---- submit (blatant = instant; legit = type it out char-by-char) ----
local function submitBlatant(word)
    fire("TypingEvent", word:upper(), true)
end
local function submitLegit(word)
    local tb = getTypebox()
    task.wait(0.25 + math.random() * 0.45)            -- "reading" pause
    local built = ""
    for i = 1, #word do
        built = built .. word:sub(i, i)
        if tb then pcall(function() tb.Text = built:upper() end) end
        fire("TypingEvent", built:upper(), false)     -- live typing replicates to others
        task.wait(0.045 + math.random() * 0.075)      -- per-keystroke delay
    end
    fire("TypingEvent", word:upper(), true)           -- enter
    if tb then pcall(function() tb.Text = "" end) end
end

-- ---- main loop ----
local tried = {}
local busy = false
if startGame then track(startGame.OnClientEvent:Connect(function() tried = {} end)) end   -- new game = words reusable
task.spawn(function()
    while true do
        if S.on and wordsReady and not busy and myTurn() then
            local syl = readSyllable()
            local word = (syl ~= "") and findWord(syl, tried, S.flex) or nil
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
