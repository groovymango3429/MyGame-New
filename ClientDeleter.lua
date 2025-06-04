-- Place this as a LocalScript in StarterPlayerScripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlaceableObjects = ReplicatedStorage:WaitForChild("PlaceableObjects")
local Events = ReplicatedStorage:WaitForChild("Events")
local tryDelete = Events:WaitForChild("TryDelete")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local camera = workspace.CurrentCamera

local DELETE_HOLD_TIME = 1.2 -- seconds

local rightMouseDown = false
local holdStartTime = 0

-- Highlight setup
local highlight = Instance.new("Highlight")
highlight.FillColor = Color3.fromRGB(255, 80, 80)
highlight.OutlineColor = Color3.new(1, 1, 1)
highlight.Enabled = false
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Parent = workspace
local START_TRANSPARENCY = 0.9
local END_TRANSPARENCY = 0.1
highlight.FillTransparency = START_TRANSPARENCY

-- Utility functions
local function castMouse()
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local raycastParams = RaycastParams.new()
	local localPlayer = game:GetService("Players").LocalPlayer
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {localPlayer.Character}
	return workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
end

local function findRootModel(part)
	if not part then return nil end
	local candidate = part
	while candidate and not candidate:IsA("Model") do
		candidate = candidate.Parent
	end
	return candidate
end

local function isPlaceableModel(model)
	if not model or not model:IsA("Model") then return false end
	if PlaceableObjects:FindFirstChild(model.Name) then
		return true
	end
	return false
end

-- Fade out all parts in the model after deletion
local function fadeAndRemove(model)
	if not model or not model:IsA("Model") then return end

	-- Remove highlight during fade
	highlight.Enabled = false
	highlight.Adornee = nil

	-- Store normal part props
	local tweenInfos = {}
	local descendants = model:GetDescendants()
	for _, part in ipairs(descendants) do
		if part:IsA("BasePart") then
			-- Remove red color and highlight
			-- Make sure to store original color if you want to revert later
			tweenInfos[#tweenInfos+1] = {
				part = part,
				originalTransparency = part.Transparency,
				originalCanCollide = part.CanCollide
			}
			part.CanCollide = false
			-- Set to normal color if you want (remove "redness")
			-- You could store original color before highlight if needed, but here we just leave the color as is.
		end
	end

	-- Tween transparency to 1
	local tweenTime = 0.7
	for _, info in ipairs(tweenInfos) do
		local tween = TweenService:Create(info.part, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad), {Transparency = 1})
		tween:Play()
	end

	-- Remove model after fade
	task.delay(tweenTime + 0.01, function()
		if model and model.Parent then
			model:Destroy()
		end
	end)
end

local function tryDeleteUnderCursor()
	local cast = castMouse()
	local rootModel = cast and findRootModel(cast.Instance)
	if rootModel and isPlaceableModel(rootModel) then
		tryDelete:InvokeServer(rootModel)
		-- Local fade out for feedback
		fadeAndRemove(rootModel)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
		rightMouseDown = true
		holdStartTime = tick()
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouseDown = false
		highlight.Enabled = false
		highlight.Adornee = nil
		highlight.FillTransparency = START_TRANSPARENCY
	end
end)

RunService.RenderStepped:Connect(function()
	if rightMouseDown then
		local cast = castMouse()
		local rootModel = cast and findRootModel(cast.Instance)
		if rootModel and isPlaceableModel(rootModel) then
			highlight.Adornee = rootModel
			highlight.Enabled = true
			-- Fade from START_TRANSPARENCY to END_TRANSPARENCY
			local progress = math.clamp((tick() - holdStartTime) / DELETE_HOLD_TIME, 0, 1)
			highlight.FillTransparency = START_TRANSPARENCY - (START_TRANSPARENCY - END_TRANSPARENCY) * progress
		else
			highlight.Enabled = false
			highlight.Adornee = nil
			highlight.FillTransparency = START_TRANSPARENCY
		end

		if tick() - holdStartTime >= DELETE_HOLD_TIME then
			rightMouseDown = false -- prevent repeated firing
			highlight.Enabled = false
			highlight.Adornee = nil
			highlight.FillTransparency = START_TRANSPARENCY
			tryDeleteUnderCursor()
		end
	else
		highlight.Enabled = false
		highlight.Adornee = nil
		highlight.FillTransparency = START_TRANSPARENCY
	end
end)