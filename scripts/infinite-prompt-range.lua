-- infinite-prompt-range.lua — every ProximityPrompt is usable from anywhere
-- (MaxActivationDistance = inf, RequiresLineOfSight = false).
-- Covers prompts that already exist, prompts added later, and games that
-- try to write the values back (re-set the moment they change).
--
-- RANGE-CHECK BYPASS: the server validates trigger distance against the
-- prompt's REAL range (engine-side, plus whatever the game adds), reading
-- your REPLICATED character position. When you trigger a prompt beyond its
-- real range, this script makes the server see you at the prompt for ~0.2s,
-- re-fires it, then restores. Two modes:
--   "rep" (default) — knife-bot re-root: SetNetworkOwner + PhysicsRepRootPart
--         onto the prompt's parent part. Your local character NEVER moves —
--         no camera jump, no fall, no snap-back. Needs sethiddenproperty.
--   "tp"  — classic teleport-fire-return (fallback when "rep" unavailable).
-- Either way the SERVER sees a position blink; movement anti-cheats may
-- still flag it, and other players see you flicker at the prompt.
--
-- Re-executing tears down the previous instance first.

local BYPASS = true       -- act on out-of-range triggers at all
local MODE = "rep"        -- "rep" | "tp" (auto-falls back to "tp" if rep fails)
local REPL_WAIT = 0.08    -- seconds at the prompt before firing (replication)
local RETURN_WAIT = 0.08  -- seconds after firing before restoring
local STAND_OFF = 2.5     -- studs to stand back from the prompt (tp mode)

local prev = getgenv()._WH_InfPPRange
if prev and prev.unload then
    pcall(prev.unload)
end

local Players = game:GetService("Players")
local PPS = game:GetService("ProximityPromptService")
local lp = Players.LocalPlayer

local state = { conns = {}, busy = false }
-- real (pre-override) range per prompt; weak keys so dead prompts collect
local orig = setmetatable({}, { __mode = "k" })
getgenv()._WH_InfPPRange = state

local function track(c)
    table.insert(state.conns, c)
    return c
end

local function apply(prompt)
    -- pcall: some locked/CoreGui prompts reject writes
    pcall(function()
        if prompt.MaxActivationDistance ~= math.huge then
            orig[prompt] = prompt.MaxActivationDistance
            prompt.MaxActivationDistance = math.huge
        end
        if prompt.RequiresLineOfSight then
            prompt.RequiresLineOfSight = false
        end
    end)
end

local function hook(inst)
    if not inst:IsA("ProximityPrompt") then
        return
    end
    apply(inst)
    -- fire synchronously right after any game write, so our values always
    -- land last; a game write is also the game's real range -> update orig
    track(inst:GetPropertyChangedSignal("MaxActivationDistance"):Connect(function()
        apply(inst)
    end))
    track(inst:GetPropertyChangedSignal("RequiresLineOfSight"):Connect(function()
        apply(inst)
    end))
end

local function promptPos(prompt)
    local p = prompt.Parent
    if not p then return nil end
    if p:IsA("Attachment") then return p.WorldPosition end
    if p:IsA("BasePart") then return p.Position end
    if p:IsA("Model") then return p:GetPivot().Position end
    return nil
end

-- server-side BasePart to root our replication onto (rep mode)
local function promptPart(prompt)
    local p = prompt.Parent
    if not p then return nil end
    if p:IsA("BasePart") then return p end
    if p:IsA("Attachment") then
        local pp = p.Parent
        return (pp and pp:IsA("BasePart")) and pp or nil
    end
    if p:IsA("Model") then
        return p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

-- knife-bot mechanism: replication rooted onto `part`, so the server (and
-- everyone else) sees us there while the local character never moves
local function repBypass(prompt, hrp)
    if not sethiddenproperty then return false end
    local part = promptPart(prompt)
    if not part then return false end
    pcall(function() hrp:SetNetworkOwner(lp) end)
    if not pcall(sethiddenproperty, hrp, "PhysicsRepRootPart", part) then
        return false
    end
    pcall(function()
        task.wait(REPL_WAIT)
        fireproximityprompt(prompt) -- re-fires Triggered; busy flag eats it
        task.wait(RETURN_WAIT)
    end)
    pcall(sethiddenproperty, hrp, "PhysicsRepRootPart", hrp) -- detach: root back onto ourselves
    return true
end

local function tpBypass(prompt, hrp, pos)
    local savedCF = hrp.CFrame
    pcall(function()
        local back = (hrp.Position - pos).Unit
        hrp.CFrame = CFrame.lookAt(pos + back * STAND_OFF, pos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(REPL_WAIT)
        fireproximityprompt(prompt)
        task.wait(RETURN_WAIT)
    end)
    pcall(function()
        hrp.CFrame = savedCF
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
end

local function onTriggered(prompt, player)
    if not BYPASS or state.busy or player ~= lp then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local pos = promptPos(prompt)
    if not hrp or not pos then return end

    local range = orig[prompt] or 10
    local dist = (hrp.Position - pos).Magnitude
    -- within real range: the native trigger already counted server-side
    if dist <= math.max(range - 1, 4) then return end

    state.busy = true
    if MODE ~= "rep" or not repBypass(prompt, hrp) then
        tpBypass(prompt, hrp, pos)
    end
    state.busy = false
end

for _, inst in ipairs(game:GetDescendants()) do
    hook(inst)
end
track(game.DescendantAdded:Connect(hook))
track(PPS.PromptTriggered:Connect(onTriggered))

function state.unload()
    for _, c in ipairs(state.conns) do
        pcall(function() c:Disconnect() end)
    end
    state.conns = {}
    -- if unloaded mid-bypass, make sure replication is rooted back on us
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and sethiddenproperty then
        pcall(sethiddenproperty, hrp, "PhysicsRepRootPart", hrp)
    end
    getgenv()._WH_InfPPRange = nil
end
