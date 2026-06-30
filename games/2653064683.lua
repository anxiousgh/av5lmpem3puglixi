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

local S = {
    on = false, flex = false, mode = "Legit", join = false, notify = false,
    startMin = 0.12, startMax = 0.28,   -- pause before typing starts (seconds)
    keyMin = 0.035, keyMax = 0.095,     -- per-keystroke delay (seconds)
}
local function randRange(a, b)          -- random in [a,b]; tolerant of min>max
    if b < a then a, b = b, a end
    return a + math.random() * (b - a)
end
-- hub notification (falls back to the Roblox core toast if the lib call fails)
local function notify(text, color)
    local ok = pcall(function() Library:Notification(text, 3, color or Color3.fromRGB(0, 200, 255)) end)
    if not ok then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification",
                { Title = "Word Bomb", Text = text, Duration = 3 })
        end)
    end
end

-- ---- word lists (fetched once) ----
-- words_alpha (~370k) = valid spellings + full syllable coverage, BUT it's stuffed
-- with obscure/junk tokens the game's "English" dictionary rejects (and they read as
-- garbage). So we also load a frequency list and PREFER the most common word for a
-- syllable -- common words are almost always accepted.
local words, wordsReady = {}, false
local freqRank = {}     -- word -> rank (lower = more common); absent = uncommon/junk
task.spawn(function()
    -- frequency ranks first (non-fatal if it fails -- we just fall back to short words)
    pcall(function()
        local fb = game:HttpGet("https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2016/en/en_50k.txt")
        if fb then
            local rank = 0
            for w in fb:gmatch("(%a+)%s+%d+") do
                w = w:lower(); rank = rank + 1
                if freqRank[w] == nil then freqRank[w] = rank end
            end
        end
    end)
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
-- flex = longest/rarest (flashy). normal = the MOST COMMON word containing the
-- syllable (by frequency rank) so the game accepts it; if no ranked word matches a
-- rare syllable, fall back to the shortest words_alpha match (short ~ more common).
local function findWord(syl, tried, flex)
    syl = syl:lower()
    local minLen = math.max(#syl, 3)
    if flex then
        -- flashiest word that is STILL a common (dictionary-valid) word -- restrict to
        -- the frequency list, else flex always picks an obscure junk word and gets
        -- rejected. Falls through to the common pick if a rare syllable has no match.
        local best, bestScore
        for _, w in ipairs(words) do
            if freqRank[w] and #w >= minLen and not tried[w] and (syl == "" or w:find(syl, 1, true)) then
                local sc = flexScore(w)
                if not bestScore or sc > bestScore then bestScore, best = sc, w end
            end
        end
        if best then return best end
    end
    local bestCommon, bestRank
    local shortFallback, shortLen
    for _, w in ipairs(words) do
        if #w >= minLen and #w <= 14 and not tried[w] and (syl == "" or w:find(syl, 1, true)) then
            local r = freqRank[w]
            if r then
                if not bestRank or r < bestRank then bestRank, bestCommon = r, w end
            elseif not shortLen or #w < shortLen then
                shortLen, shortFallback = #w, w
            end
        end
    end
    return bestCommon or shortFallback
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
-- Re-scan on a throttle and ALWAYS adopt the live game's Data table -- never cache
-- one forever. Old/finished rounds leave stale tables in the GC (and there's a
-- template with FuseStart=1), so the live one is the match with the greatest
-- FuseStart (most recently started game). This is what makes re-entering / new
-- rounds keep working instead of reading a dead table.
local dataObj, lastScan = nil, 0
local function refreshData()
    if type(getgc) ~= "function" then return end
    if tick() - lastScan < 1 then return end   -- throttle the (heavy) GC walk
    lastScan = tick()
    pcall(function()
        local best, bestStart
        for _, o in ipairs(getgc(true)) do
            if type(o) == "table" and rawget(o, "Prompt") ~= nil
                and rawget(o, "PossessorIndex") ~= nil and type(rawget(o, "Players")) == "table"
                and #rawget(o, "Players") > 0 then
                local start = tonumber(rawget(o, "FuseStart")) or 0
                if not bestStart or start > bestStart then bestStart, best = start, o end
            end
        end
        if best then dataObj = best end
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
local function pressKey(name)
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
    task.wait(randRange(S.startMin, S.startMax))      -- pause before starting to type
    for i = 1, #word do
        pressKey(word:sub(i, i))
        task.wait(randRange(S.keyMin, S.keyMax))      -- per-keystroke delay
    end
    task.wait(0.08)
    pressKey("enter")                                 -- submit
end

-- ---- main loop ----
local tried, prevData = {}, nil
local busy = false
local lastSeen = nil   -- last syllable announced by the "notify" toggle (debounce)
if startGame then track(startGame.OnClientEvent:Connect(function() tried = {} end)) end   -- new game = words reusable
-- generation guard: each reload starts a fresh loop and retires the previous one
local gg = (getgenv and getgenv()) or {}
gg.WB_GEN = (gg.WB_GEN or 0) + 1
local myGen = gg.WB_GEN
task.spawn(function()
    while myGen == gg.WB_GEN do
        if S.on or S.notify then
            refreshData()
            if dataObj ~= prevData then tried = {}; prevData = dataObj end   -- new game Data = reset used words
            local mine = dataObj and isMyTurn()
            -- "Notify detected syllable": show the syllable we read, once per turn
            if S.notify then
                if mine then
                    local syl = getSyllable()
                    local shown = (syl == "" and "(any word)") or syl
                    if shown ~= lastSeen then
                        lastSeen = shown
                        notify("Sees: '" .. shown .. "'", Color3.fromRGB(0, 255, 120))
                    end
                else
                    lastSeen = nil
                end
            end
            if S.on and wordsReady and dataObj and not busy and mine then
                local word = findWord(getSyllable(), tried, S.flex)
                if word then
                    tried[word] = true
                    busy = true
                    task.spawn(function()
                        pcall(function()   -- never let an error strand `busy` (was killing the loop)
                            if S.mode == "Blatant" then submitBlatant(word) else submitLegit(word) end
                        end)
                        task.wait(0.6)   -- give the server a beat (retries another word if rejected/still our turn)
                        busy = false
                    end)
                end
            end
        end
        task.wait(0.12)
    end
end)

-- ---- auto join: click the Join button whenever a round is open to join ----
-- (the button responds to a real positioned click, not a fired signal; its label
-- reads "Click to join" until you're in, then "You're in!")
do
    local GuiService = game:GetService("GuiService")
    local lastJoin = 0
    task.spawn(function()
        while myGen == gg.WB_GEN do
            if S.join then
                local ok, jb = pcall(function()
                    return LocalPlayer.PlayerGui.GameUI.Container.GameSpace.DefaultUI.DesktopFrame.JoinButton
                end)
                if ok and jb and jb.Visible and jb.Active and (tick() - lastJoin) > 1 then
                    local lbl = jb:FindFirstChild("JoinLabel")
                    if lbl and lbl.Text:lower():find("join") then   -- not already "You're in!"
                        lastJoin = tick()
                        local cx = jb.AbsolutePosition.X + jb.AbsoluteSize.X / 2
                        local cy = jb.AbsolutePosition.Y + jb.AbsoluteSize.Y / 2 + GuiService:GetGuiInset().Y
                        pcall(function()
                            VIM:SendMouseButtonEvent(cx, cy, 0, true, game, 0)
                            task.wait(0.05)
                            VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 0)
                        end)
                    end
                end
            end
            task.wait(0.6)
        end
    end)
end

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
    Sec:Toggle({ Name = "Auto join", Flag = "WB_Join", Default = false,
        Callback = function(v) S.join = v end })
    Sec:Toggle({ Name = "Notify detected syllable", Flag = "WB_Notify", Default = false,
        Callback = function(v) S.notify = v end })
    local status = Sec:Label({ Name = "Loading word list..." })
    task.spawn(function()
        while not wordsReady do task.wait(0.25) end
        pcall(function() status:SetText(("Ready -- %d words"):format(#words)) end)
    end)

    -- typing speed: each delay has its own randomized min/max (ms)
    local Spd = Sub:Section({ Name = "Typing speed (Legit)", Side = 2 })
    Spd:Slider({ Name = "Start delay min", Flag = "WB_StartMin", Min = 0, Max = 1500, Default = 120, Decimals = 0, Suffix = "ms",
        Callback = function(v) S.startMin = v / 1000 end })
    Spd:Slider({ Name = "Start delay max", Flag = "WB_StartMax", Min = 0, Max = 1500, Default = 280, Decimals = 0, Suffix = "ms",
        Callback = function(v) S.startMax = v / 1000 end })
    Spd:Slider({ Name = "Key delay min", Flag = "WB_KeyMin", Min = 0, Max = 500, Default = 35, Decimals = 0, Suffix = "ms",
        Callback = function(v) S.keyMin = v / 1000 end })
    Spd:Slider({ Name = "Key delay max", Flag = "WB_KeyMax", Min = 0, Max = 500, Default = 95, Decimals = 0, Suffix = "ms",
        Callback = function(v) S.keyMax = v / 1000 end })
end

-- universal pages after Main
pcall(function() ctx.load("games/universal.lua")(ctx) end)

-- teardown
local function cleanup()
    S.on = false; S.notify = false
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
