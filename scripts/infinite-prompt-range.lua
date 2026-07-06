-- infinite-prompt-range.lua — every ProximityPrompt is usable from anywhere
-- (MaxActivationDistance = inf, RequiresLineOfSight = false).
-- Covers prompts that already exist, prompts added later, and games that
-- try to write the values back (re-set the moment they change).
-- Re-executing tears down the previous instance first.

local prev = getgenv()._WH_InfPPRange
if prev and prev.unload then
    pcall(prev.unload)
end

local state = { conns = {} }
getgenv()._WH_InfPPRange = state

local function track(c)
    table.insert(state.conns, c)
    return c
end

local function apply(prompt)
    -- pcall: some locked/CoreGui prompts reject writes
    pcall(function()
        if prompt.MaxActivationDistance ~= math.huge then
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
    -- fire synchronously right after any game write, so our values always land last
    track(inst:GetPropertyChangedSignal("MaxActivationDistance"):Connect(function()
        apply(inst)
    end))
    track(inst:GetPropertyChangedSignal("RequiresLineOfSight"):Connect(function()
        apply(inst)
    end))
end

for _, inst in ipairs(game:GetDescendants()) do
    hook(inst)
end
track(game.DescendantAdded:Connect(hook))

function state.unload()
    for _, c in ipairs(state.conns) do
        pcall(function() c:Disconnect() end)
    end
    state.conns = {}
    getgenv()._WH_InfPPRange = nil
end
