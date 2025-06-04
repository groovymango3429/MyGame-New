-- Place as a LocalScript in StarterPlayerScripts or wherever you manage local state

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Adjusted event and module paths per your layout:
local Events = ReplicatedStorage:WaitForChild("Events")
local GetPlot = Events:WaitForChild("GetPlot")

-- ClientPlacer is in script.Parent (if this script is in StarterPlayerScripts, you might want to put ClientPlacer as a ModuleScript in StarterPlayerScripts or require as script.Parent.ClientPlacer)
local ClientPlacer = require(script.Parent:WaitForChild("ClientPlacer"))

local currentPlacer = nil

local function tryActivatePlacement(tool)
	-- Always destroy the old placer if it exists
	if currentPlacer then
		currentPlacer:Destroy()
		currentPlacer = nil
	end
	-- If held tool is placeable, create a placer for that tool's name
	if tool and tool:GetAttribute("IsPlaceable") == true then
		local plot = GetPlot:InvokeServer()
		currentPlacer = ClientPlacer.new(plot, tool.Name)
	end
end

local function getHeldPlaceableTool(char)
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") and t:GetAttribute("IsPlaceable") == true then
			return t
		end
	end
	return nil
end

local function onCharacterAdded(char)
	-- Listen for tool equipped/unequipped
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			tryActivatePlacement(getHeldPlaceableTool(char))
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			tryActivatePlacement(getHeldPlaceableTool(char))
		end
	end)
	-- Initial state (if tool is already equipped)
	tryActivatePlacement(getHeldPlaceableTool(char))
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)