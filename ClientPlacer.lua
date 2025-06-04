-- Place as a ModuleScript in the same location as PlacementManager.lua
-- Updated: X key binding and TryDeleteBlock method removed

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local boxOutlineTemplate = ReplicatedStorage:WaitForChild("BoxOutline")
local placeableObjects = ReplicatedStorage:WaitForChild("PlaceableObjects")
local Events = ReplicatedStorage:WaitForChild("Events")
local tryPlace = Events:WaitForChild("TryPlace")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local camera = workspace.CurrentCamera
local PlacementValidator = require(ReplicatedStorage:WaitForChild("PlacementValidator"))

local PREVIEW_RENDER = "RenderPreview"
local PLACE_ACTION = "Place"
local ROTATE_ACTION = "Rotate"
local SNAP_ACTION = "Snap"

local function snapToGrid(pos, gridSize)
	return Vector3.new(
		math.round(pos.X / gridSize) * gridSize,
		pos.Y,
		math.round(pos.Z / gridSize) * gridSize
	)
end

local function castMouse()
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	local localPlayer = game:GetService("Players").LocalPlayer
	raycastParams.FilterDescendantsInstances = {localPlayer.Character}
	return workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
end

local ClientPlacer = {}
ClientPlacer.__index = ClientPlacer

function ClientPlacer.new(plot, placeableName)
	local self = setmetatable({
		Plot = plot,
		Preview = nil,
		PlaceableName = placeableName,
		GridSize = 0,
		Rotation = 0,
	}, ClientPlacer)

	self:InitiateRenderPreview()
	ContextActionService:BindAction(PLACE_ACTION, function(...) self:TryPlaceBlock(...) end, false, Enum.UserInputType.MouseButton1)
	ContextActionService:BindAction(ROTATE_ACTION, function(...) self:RotateBlock(...) end, false, Enum.KeyCode.R)
	ContextActionService:BindAction(SNAP_ACTION, function(...) self:ToggleGrid(...) end, false, Enum.KeyCode.G)
	return self
end

function ClientPlacer:InitiateRenderPreview()
	pcall(function()
		RunService:UnbindFromRenderStep(PREVIEW_RENDER)
	end)
	local model = placeableObjects:FindFirstChild(self.PlaceableName)
	self:PreparePreviewModel(model)
	RunService:BindToRenderStep(PREVIEW_RENDER, Enum.RenderPriority.Camera.Value, function(...) self:RenderPreview(...) end)
end

function ClientPlacer:PreparePreviewModel(model)
	if self.Preview then
		self.Preview:Destroy()
		self.Preview = nil
	end
	if not model then return end

	self.Preview = model:Clone()
	local boxOutline = boxOutlineTemplate:Clone()
	boxOutline.Adornee = self.Preview
	boxOutline.Parent = self.Preview

	for _, part in self.Preview:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.Transparency = 0.5
		end
	end

	self.Preview.Parent = workspace
end

function ClientPlacer:RenderPreview()
	local cast = castMouse()
	if cast and cast.Position then
		local position = self.GridSize > 0 and snapToGrid(cast.Position, self.GridSize) or cast.Position
		local cf = CFrame.new(position) * CFrame.Angles(0, self.Rotation, 0)
		self.Preview:PivotTo(cf)

		local size = self.Preview:GetExtentsSize()
		local valid = PlacementValidator.WithinBounds(self.Plot, size, cf)
			and PlacementValidator.NotIntersectingObjects(self.Plot, size, cf)
		self.Preview.BoxOutline.Color3 = valid and Color3.new(0, 0.666667, 1) or Color3.new(1, 0, 0)
	end
end

function ClientPlacer:TryPlaceBlock(_, state, _)
	if state ~= Enum.UserInputState.Begin then
		return
	end
	if not self.Preview then return end
	tryPlace:InvokeServer(self.PlaceableName, self.Preview:GetPivot())
end

function ClientPlacer:RotateBlock(_, state, _)
	if state == Enum.UserInputState.Begin then
		self.Rotation += math.pi / 2
	end
end

function ClientPlacer:ToggleGrid(_, state, _)
	if state == Enum.UserInputState.Begin then
		self.GridSize = self.GridSize == 0 and 4 or 0
	end
end

function ClientPlacer:Destroy()
	if self.Preview then
		self.Preview:Destroy()
		self.Preview = nil
	end
	pcall(function()
		RunService:UnbindFromRenderStep(PREVIEW_RENDER)
	end)
	ContextActionService:UnbindAction(PLACE_ACTION)
	ContextActionService:UnbindAction(ROTATE_ACTION)
	ContextActionService:UnbindAction(SNAP_ACTION)
end

return ClientPlacer