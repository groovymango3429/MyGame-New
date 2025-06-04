-- Place this LocalScript in StarterPlayerScripts

--[[
    Improved 3rd Person Camera Controller:
    - Hold C: Camera moves in front of your character's face, always facing you.
    - Release C: Camera snaps to player's forward-facing direction for one frame before restoring default camera.
    - Handles character respawn and reliably restores camera following the player.
    - Avoids camera "locking" bug by ensuring proper reset and waiting for character load.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local KEYBIND = Enum.KeyCode.C
local CAMERA_DISTANCE = 9
local CAMERA_HEIGHT = 1.5

local holdingKey = false
local camConn, transparencyConn, orientationRestoreConn = nil, nil, nil

local LOCK_ACTION = "FrontViewLockTurn"

local originalCameraType = nil
local originalSubject = nil
local originalFOV = nil
local originalMode = nil
local savedTransparency = {}
local savedRootY = nil

local function setCharacterVisibleEveryFrame()
	if transparencyConn then transparencyConn:Disconnect() end
	transparencyConn = RunService.RenderStepped:Connect(function()
		local character = player.Character
		if not character then return end
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("Decal") then
				if savedTransparency[part] == nil then
					savedTransparency[part] = part.LocalTransparencyModifier
				end
				part.LocalTransparencyModifier = 0
			end
		end
	end)
end

local function restoreCharacterTransparency()
	if transparencyConn then transparencyConn:Disconnect() transparencyConn = nil end
	local character = player.Character
	if not character then return end
	for _, part in ipairs(character:GetDescendants()) do
		if (part:IsA("BasePart") or part:IsA("Decal")) and savedTransparency[part] ~= nil then
			part.LocalTransparencyModifier = savedTransparency[part]
		end
	end
	savedTransparency = {}
end

local function lockCharacterRotation()
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end
end

local function unlockCharacterRotation()
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function blockTurning(actionName, inputState, inputObject)
	return Enum.ContextActionResult.Sink
end

local function updateCameraFront()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	player.CameraMode = Enum.CameraMode.Classic

	local rootCF = root.CFrame
	local lookAt = rootCF.Position + Vector3.new(0, CAMERA_HEIGHT, 0)
	local camPos = lookAt + (rootCF.LookVector * CAMERA_DISTANCE)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(camPos, lookAt)
end

local function getYOrientation(cf)
	if not cf then return nil end
	local _, y, _ = cf:ToEulerAnglesYXZ()
	return y
end

local function setRootOrientationY(root, y)
	if not root or not y then return end
	local pos = root.Position
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, y, 0)
end

local function enableFrontCam()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		savedRootY = getYOrientation(root.CFrame)
	else
		savedRootY = nil
	end

	originalCameraType = camera.CameraType
	originalSubject = camera.CameraSubject
	originalFOV = camera.FieldOfView
	originalMode = player.CameraMode

	holdingKey = true
	lockCharacterRotation()
	ContextActionService:BindAction(LOCK_ACTION, blockTurning, false,
		Enum.UserInputType.MouseMovement,
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.A,
		Enum.KeyCode.D
	)

	setCharacterVisibleEveryFrame()

	if camConn then camConn:Disconnect() end
	camConn = RunService.RenderStepped:Connect(updateCameraFront)
end

local function snapCameraToPlayerFacing()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- Place camera just behind head, looking forward, so the "sync" is invisible to player
	local forward = root.CFrame.LookVector
	local up = root.CFrame.UpVector
	local at = root.Position + Vector3.new(0, CAMERA_HEIGHT, 0)
	local camPos = at - forward * 0.5 + up * 1.5
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(camPos, at + forward * 10)
	RunService.RenderStepped:Wait()
end

local function restoreRootOrientationForAWhile()
	if orientationRestoreConn then orientationRestoreConn:Disconnect() end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (savedRootY and root) then return end

	local frames = 0
	orientationRestoreConn = RunService.RenderStepped:Connect(function()
		if frames > 3 then
			orientationRestoreConn:Disconnect()
			orientationRestoreConn = nil
			return
		end
		setRootOrientationY(root, savedRootY)
		frames = frames + 1
	end)
end

local function forceCameraFollow()
	-- Always restore camera to default follow mode
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	camera.CameraType = Enum.CameraType.Custom
	player.CameraMode = Enum.CameraMode.Classic
end

local function disableFrontCam()
	holdingKey = false
	unlockCharacterRotation()
	ContextActionService:UnbindAction(LOCK_ACTION)
	restoreCharacterTransparency()

	if camConn then camConn:Disconnect() camConn = nil end

	snapCameraToPlayerFacing()

	-- Restore camera to original settings
	if originalCameraType then camera.CameraType = originalCameraType end
	if originalSubject then camera.CameraSubject = originalSubject end
	if originalFOV then camera.FieldOfView = originalFOV end
	if originalMode then player.CameraMode = originalMode end

	RunService.RenderStepped:Wait()
	restoreRootOrientationForAWhile()

	-- Ensure camera follows player reliably
	forceCameraFollow()

	originalCameraType = nil
	originalSubject = nil
	originalFOV = nil
	originalMode = nil
	savedRootY = nil
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == KEYBIND and not holdingKey then
		enableFrontCam()
	end
end)

UIS.InputEnded:Connect(function(input, processed)
	if input.KeyCode == KEYBIND and holdingKey then
		disableFrontCam()
	end
end)

-- On character added, wait for root and humanoid, then enforce default camera follow
player.CharacterAdded:Connect(function(char)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	local humanoid = char:WaitForChild("Humanoid", 5)
	if not (root and humanoid) then return end

	RunService.RenderStepped:Wait()

	if holdingKey then
		enableFrontCam()
	else
		disableFrontCam()
	end

	forceCameraFollow()
end)

-- On script startup, force camera to follow player
if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
	forceCameraFollow()
end