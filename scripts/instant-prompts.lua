-- instant-prompts.lua — every ProximityPrompt activates instantly (HoldDuration = 0)
-- Covers prompts that already exist, prompts added later, and games that
-- try to write the value back (re-zeroed the moment they change it).
-- Re-executing tears down the previous instance first.

local prev = getgenv()._WH_InstantPP
if prev and prev.unload then
    pcall(prev.unload)
end

local state = { conns = {} }
getgenv()._WH_InstantPP = state

local function track(c)
    table.insert(state.conns, c)
    return c
end

local function zero(prompt)
    -- pcall: some locked/CoreGui prompts reject writes
    pcall(function()
        if prompt.HoldDuration ~= 0 then
            prompt.HoldDuration = 0
        end
    end)
end

local function hook(inst)
    if not inst:IsA("ProximityPrompt") then
        return
    end
    zero(inst)
    -- fires synchronously right after any game write, so our 0 always lands last
    track(inst:GetPropertyChangedSignal("HoldDuration"):Connect(function()
        zero(inst)
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
    getgenv()._WH_InstantPP = nil
end
