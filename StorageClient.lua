-- Place in StarterPlayerScripts

--[[ 
  StorageClient.lua
  Handles:
    - Inventory GUI (left)
    - Storage GUI (right)
    - True drag & drop inventory <-> storage (quantity drag, centered on mouse, no flicker)
    - Shift-click for instant full-stack transfer
    - Opening storage shelves via ProximityPrompt (using StorageId attribute)
    - Syncing with server for all storage actions
    - Inventory and storage GUI updates
    - Visual feedback for dragging
    - Close inventory button and ESC/Tab support
    - Inventory stack count label under DecorationLeft.StackCount
    - Storage stack count label under Storage.StackLabel
    - Error message display with tweening under Storage.Error
    - Closes Inventory when Storage opens, and vice versa
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Signal = require(ReplicatedStorage.Modules.Signal)
local player = Players.LocalPlayer

-- GUI references (adjust as needed for your hierarchy)
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("Storage")
local invF = screenGui:WaitForChild("Inventory")
local itemsSF = invF:WaitForChild("ItemsScroll")
local itemSample = itemsSF:WaitForChild("Sample")

local storageGui = screenGui:WaitForChild("Storage")
local storageSF = storageGui:WaitForChild("ItemsScroll")
local storageSample = storageSF:WaitForChild("Sample")
local storageStackLabel = invF:WaitForChild("Decoration"):WaitForChild("StackCount")
local inventoryStackLabel = invF:WaitForChild("DecorationLeft"):WaitForChild("StackCount")
local errorT = screenGui:WaitForChild("Error")

local closeButton = storageGui:WaitForChild("Done")
local FALLBACK_IMAGE = "rbxassetid://6031068438"

local currentShelfId = nil
local currentShelfItems = {}
local currentShelfMax = 8
local inventoryData = nil
local inventoryMaxStacks = 10 -- Adjust if your max stack count changes

-- Error message state
local StorageClient = {}
StorageClient.ErrorDb = false
StorageClient.ErrorTime = 1.5 -- seconds error message is visible
StorageClient.ErrorPosition = errorT.Position

function StorageClient.ErrorMessage(message)
	if StorageClient.ErrorDb then return end
	StorageClient.ErrorDb = true

	errorT.Text = message
	errorT.Position = StorageClient.ErrorPosition + UDim2.fromScale(0, -0.2)
	errorT.TextTransparency = 0
	errorT.TextStrokeTransparency = 0
	errorT.Visible = true

	-- Tween in
	local tweenIn = TweenService:Create(
		errorT,
		TweenInfo.new(StorageClient.ErrorTime/4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = StorageClient.ErrorPosition }
	)
	tweenIn:Play()
	tweenIn.Completed:Wait()

	-- Stay visible
	task.wait(StorageClient.ErrorTime/2)

	-- Tween out (fade)
	local tweenAway = TweenService:Create(
		errorT,
		TweenInfo.new(StorageClient.ErrorTime/4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	tweenAway:Play()
	tweenAway.Completed:Wait()

	errorT.Visible = false
	errorT.TextTransparency = 0
	errorT.TextStrokeTransparency = 0
	StorageClient.ErrorDb = false
end

-- =========================
-- Utility: Is Mouse Over Gui
-- =========================
local function isMouseOverGui(gui)
	local mousePos = UIS:GetMouseLocation()
	local guiPos = gui.AbsolutePosition
	local guiSize = gui.AbsoluteSize
	return mousePos.X >= guiPos.X and mousePos.X <= guiPos.X + guiSize.X
		and mousePos.Y >= guiPos.Y and mousePos.Y <= guiPos.Y + guiSize.Y
end

-- =========================
-- Inventory GUI (Left Side)
-- =========================

function updateInventoryDisplay(invData)
	for _, child in ipairs(itemsSF:GetChildren()) do
		if child:IsA("TextButton") and child ~= itemSample then
			child:Destroy()
		end
	end

	-- Update inventory stack count label (left)
	local stackCount = #invData.Inventory
	inventoryStackLabel.Text = ("%d/%d Stacks"):format(stackCount, inventoryMaxStacks)

	for _, stackData in ipairs(invData.Inventory) do
		local itemF = itemSample:Clone()
		itemF.Name = "Stack-" .. stackData.StackId
		itemF.Visible = true
		itemF.Parent = itemsSF
		itemF.Image.Image = stackData.Image or FALLBACK_IMAGE
		itemF.ItemCount.Text = tostring(#stackData.Items) .. "x"

		-- Shift-click for instant full-stack transfer
		itemF.MouseButton1Click:Connect(function()
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) then
				if currentShelfId and storageGui.Visible then
					Signal.FireServer("Storage:Deposit", currentShelfId, stackData.StackId, #stackData.Items)
				end
			end
		end)

		itemF.MouseButton1Down:Connect(function()
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) then return end

			local absSize = itemF.AbsoluteSize
			local dragFrame = itemF:Clone()
			dragFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			dragFrame.Size = UDim2.fromOffset(absSize.X, absSize.Y)
			dragFrame.Parent = screenGui
			local pos = UIS:GetMouseLocation()
			dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
			dragFrame.Visible = true
			dragFrame.ZIndex = 10
			dragFrame.BackgroundTransparency = 0.25

			local maxAmount = #stackData.Items
			local transferAmount = 1
			dragFrame.ItemCount.Text = tostring(transferAmount) .. "x"

			local dragging = true

			local moveConn, upConn, wheelConn
			moveConn = RunService.RenderStepped:Connect(function()
				if not dragging then return end
				local pos = UIS:GetMouseLocation()
				dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
			end)

			wheelConn = UIS.InputChanged:Connect(function(input)
				if not dragging then return end
				if input.UserInputType == Enum.UserInputType.MouseWheel then
					transferAmount = math.clamp(transferAmount + input.Position.Z, 1, maxAmount)
					dragFrame.ItemCount.Text = tostring(transferAmount) ..  "x"
				end
			end)

			upConn = UIS.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
					dragging = false
					if moveConn then moveConn:Disconnect() end
					if upConn then upConn:Disconnect() end
					if wheelConn then wheelConn:Disconnect() end
					dragFrame:Destroy()

					if isMouseOverGui(storageGui) and currentShelfId and storageGui.Visible then
						local amountToSend = transferAmount
						Signal.FireServer("Storage:Deposit", currentShelfId, stackData.StackId, amountToSend)
					end
				end
			end)
		end)
	end
end

-- =========================
-- Storage GUI (Right Side)
-- =========================

function updateStorageDisplay()
	for _, child in ipairs(storageSF:GetChildren()) do
		if child:IsA("TextButton") and child ~= storageSample then
			child:Destroy()
		end
	end

	-- Update storage stack count label (right)
	storageStackLabel.Text = ("%d/%d stacks"):format(#currentShelfItems, currentShelfMax or 8)

	for _, stackData in ipairs(currentShelfItems) do
		local itemF = storageSample:Clone()
		itemF.Name = "Stack-" .. stackData.StackId
		itemF.Image.Image = stackData.Image or FALLBACK_IMAGE
		if stackData.Items then
			itemF.ItemCount.Text = tostring(#stackData.Items) .. "x"
		elseif stackData.Count then
			itemF.ItemCount.Text = tostring(stackData.Count) .. "x"
		else
			itemF.ItemCount.Text = "?"
		end
		itemF.Visible = true
		itemF.Parent = storageSF

		-- Shift-click: instantly withdraw full stack
		itemF.MouseButton1Click:Connect(function()
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) then
				if currentShelfId and storageGui.Visible then
					local stackCount = (stackData.Items and #stackData.Items) or (stackData.Count or 1)
					Signal.FireServer("Storage:Withdraw", currentShelfId, stackData.StackId, stackCount)
				end
			end
		end)

		itemF.MouseButton1Down:Connect(function()
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) then return end

			local absSize = itemF.AbsoluteSize
			local dragFrame = itemF:Clone()
			dragFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			dragFrame.Size = UDim2.fromOffset(absSize.X, absSize.Y)
			dragFrame.Parent = screenGui
			local pos = UIS:GetMouseLocation()
			dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
			dragFrame.Visible = true
			dragFrame.ZIndex = 10
			dragFrame.BackgroundTransparency = 0.25

			local maxAmount = (stackData.Items and #stackData.Items) or (stackData.Count or 1)
			local transferAmount = 1
			dragFrame.ItemCount.Text = tostring(transferAmount) .. "x"

			local dragging = true

			local moveConn, upConn, wheelConn
			moveConn = RunService.RenderStepped:Connect(function()
				if not dragging then return end
				local pos = UIS:GetMouseLocation()
				dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
			end)

			wheelConn = UIS.InputChanged:Connect(function(input)
				if not dragging then return end
				if input.UserInputType == Enum.UserInputType.MouseWheel then
					transferAmount = math.clamp(transferAmount + input.Position.Z, 1, maxAmount)
					dragFrame.ItemCount.Text = tostring(transferAmount) ..  "x"
				end
			end)

			upConn = UIS.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
					dragging = false
					if moveConn then moveConn:Disconnect() end
					if upConn then upConn:Disconnect() end
					if wheelConn then wheelConn:Disconnect() end
					dragFrame:Destroy()

					if isMouseOverGui(invF) and currentShelfId and storageGui.Visible then
						local amountToSend = transferAmount
						Signal.FireServer("Storage:Withdraw", currentShelfId, stackData.StackId, amountToSend)
					end
				end
			end)
		end)
	end
end

-- =========================
-- Signal (Remote Event) Handlers
-- =========================

Signal.ListenRemote("Storage:Open", function(storageId, shelfItems, maxStacks)
	-- Close inventory if open
	local playerGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui then
		local inventoryScreen = playerGui:FindFirstChild("Inventory")
		if inventoryScreen and inventoryScreen:FindFirstChild("Inventory") then
			local invF2 = inventoryScreen:FindFirstChild("Inventory")
			if invF2.Visible then
				invF2.Visible = false
			end
		end
	end

	currentShelfId = storageId
	currentShelfItems = shelfItems
	currentShelfMax = maxStacks
	storageGui.Visible = true
	invF.Visible = true
	UIS.MouseIconEnabled = true
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	updateStorageDisplay()
end)

Signal.ListenRemote("Storage:Update", function(storageId, shelfItems, maxStacks)
	if storageId ~= currentShelfId then
		return
	end
	currentShelfItems = shelfItems
	currentShelfMax = maxStacks
	updateStorageDisplay()
end)

Signal.ListenRemote("InventoryClient:Update", function(newInvData)
	inventoryData = newInvData
	updateInventoryDisplay(inventoryData)
end)

Signal.ListenRemote("Storage:Error", function(msg)
	StorageClient.ErrorMessage(msg)
end)

-- ================ ProximityPrompt Handler (Open shelf by StorageId) ================

local function setupProximityPromptListeners()
	local function connectPrompt(prompt, shelf)
		prompt.Triggered:Connect(function()
			local storageId = shelf:GetAttribute("StorageId")
			if storageId then
				Signal.FireServer("Storage:Open", storageId)
			end
		end)
	end

	local function scanPlot()
		local plotsFolder = workspace:FindFirstChild("Plots")
		if not plotsFolder then
			return
		end
		local plot = plotsFolder:FindFirstChild(player.Name .. "'s Plot")
		if not plot then
			return
		end
		local objects = plot:FindFirstChild("Objects")
		if not objects then
			return
		end

		for _, shelf in ipairs(objects:GetChildren()) do
			local prompt = shelf:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt and shelf:GetAttribute("StorageId") then
				connectPrompt(prompt, shelf)
			end
		end
	end

	scanPlot()
	workspace.ChildAdded:Connect(function(child)
		if child.Name == player.Name .. " Plot" then
			child:WaitForChild("Objects")
			scanPlot()
		end
	end)
end

setupProximityPromptListeners()

-- =========================
-- CLOSE INVENTORY FUNCTIONALITY
-- =========================

local function closeInventory()
	storageGui.Visible = false
	invF.Visible = false
	UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
	UIS.MouseIconEnabled = false
	currentShelfId = nil
end

closeButton.MouseButton1Click:Connect(closeInventory)

UIS.InputBegan:Connect(function(input, processed)
	if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Tab) then
		if storageGui.Visible or invF.Visible then
			closeInventory()
		end
	end
end)

return StorageClient