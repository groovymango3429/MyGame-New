local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")
local ContextActionService = game:GetService("ContextActionService")
local GetPlot = Events:WaitForChild("GetPlot")
local ClientPlacer = require(script.Parent:WaitForChild("ClientPlacer"))

local placer = nil

local function setPlacementActive(_, state, _)
	print("trying")
	if state ~= Enum.UserInputState.Begin then 
		print("test")
		return
	end
	
	if not placer then 
		local plot = GetPlot:InvokeServer()
		placer = ClientPlacer.new(plot)
	else 
		placer:Destroy()
		placer = nil
	end
end