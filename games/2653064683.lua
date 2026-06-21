-- ============================================================
--  games/2653064683.lua  --  Word Bomb
--
--  Auto-answer. The game validates words SERVER-side (no client dictionary), so we
--  just feed it a REAL word containing the current syllable, fetched from an English
--  word list. The syllable + whose turn it is are read from the game Data (found via
--  getgc): Data.Prompt = clean syllable, Data.Players[Data.PossessorIndex] = current
--  UserId. Blatant submit = GameEvent:FireServer(GameID,"TypingEvent",word,true) (the
--  game's own final-submit). Legit submit = real keystrokes via VirtualInputManager.
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
-- pick a word containing `syl`, not already tried. empty syllable = any word.
-- flex = longest/rarest (the flashy play). normal = a RANDOM word, preferring a natural
-- length (4-9) via reservoir sampling, so it isn't always the shortest possible.
local function findWord(syl, tried, flex)
    syl = syl:lower()
    local minLen = math.max(#syl, 3)
    if flex then
        local best, bestScore
        for _, w in ipairs(words) do
            if #w >= minLen and not tried[w] and (syl == "" or w:find(syl, 1, true)) then
                local sc = flexScore(w)
                if not bestScore or sc > bestScore then bestScore, best = sc, w end
            end
        end
        return best
    end
    local bandLo = math.max(minLen, 4)
    local pick, count, fallback, fcount = nil, 0, nil, 0
    for _, w in ipairs(words) do
        if #w >= minLen and not tried[w] and (syl == "" or w:find(syl, 1, true)) then
            fcount = fcount + 1
            if math.random(fcount) == 1 then fallback = w end       -- any-length reservoir
            if #w >= bandLo and #w <= 9 then
                count = count + 1
                if math.random(count) == 1 then pick = w end        -- natural-length reservoir
            end
        end
    end
    return pick or fallback
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
-- QWERTY neighbours -> believable typos
local ADJ = {
    q = "wa", w = "qeas", e = "wsdr", r = "edft", t = "rfgy", y = "tghu", u = "yhji",
    i = "ujko", o = "iklp", p = "ol", a = "qwsz", s = "awedxz", d = "serfcx", f = "drtgvc",
    g = "ftyhbv", h = "gyujnb", j = "huikmn", k = "jiolm", l = "kop", z = "asx", x = "zsdc",
    c = "xdfv", v = "cfgb", b = "vghn", n = "bhjm", m = "njk",
}
local function press(name)
    local kc = (name == "bs" and Enum.KeyCode.Backspace)
        or (name == "enter" and Enum.KeyCode.Return) or KEY[name]
    if not kc then return end
    pcall(function() VIM:SendKeyEvent(true, kc, false, game) end)
    task.wait(0.02)
    pcall(function() VIM:SendKeyEvent(false, kc, false, game) end)
end
local function submitBlatant(word)
    fire("TypingEvent", word:upper(), true)
end
local function submitLegit(word)
    word = word:lower()
    task.wait(0.2 + math.random() * 0.4)              -- "reading" pause
    -- clear anything left in the bar (e.g. a previously rejected word) so it can't garble
    local tb = getTypebox()
    if tb then for _ = 1, #(tb.Text or "") + 1 do press("bs"); task.wait(0.015) end end
    local hesitateAt = (math.random() < 0.18) and math.random(2, math.max(2, #word)) or -1  -- sometimes
    local misspellAt = (math.random() < 0.05) and math.random(1, #word) or -1               -- very rarely
    for i = 1, #word do
        if i == hesitateAt then task.wait(0.45 + math.random() * 0.7) end   -- pause to "think"
        if i == misspellAt then
            local nb = ADJ[word:sub(i, i)]
            if nb and #nb > 0 then
                local j = math.random(#nb)
                press(nb:sub(j, j))                       -- fat-finger a neighbour key
                task.wait(0.13 + math.random() * 0.22)    -- notice the mistake
                press("bs")                               -- backspace it
                task.wait(0.08 + math.random() * 0.12)
            end
        end
        press(word:sub(i, i))
        task.wait(0.06 + math.random() * 0.11)            -- per-keystroke delay
    end
    task.wait(0.1 + math.random() * 0.18)
    press("enter")                                        -- submit
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
