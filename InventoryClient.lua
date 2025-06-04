--Services
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local SG = game:GetService("StarterGui")
local TS = game:GetService("TweenService")

--Modules
local Janitor = require(RS.Modules.Janitor)
local Signal = require(RS.Modules.Signal)
local Types = require(RS.Modules.Types)

--Player Variables
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

--Gui Variables
local gui = playerGui:WaitForChild("Inventory")
local hotbarF = gui:WaitForChild("Hotbar")
local invF = gui:WaitForChild("Inventory"); invF.Visible = false
local invB = hotbarF:WaitForChild("Open")
local errorT = gui:WaitForChild("Error"); errorT.Visible = false
local moneyCountLabel = hotbarF:WaitForChild("Money"):WaitForChild("MoneyCount")

local infoF = invF:WaitForChild("ItemInfo")
local itemNameT = infoF:WaitForChild("ItemName")
local itemDescT = infoF:WaitForChild("ItemDesc")
local equipB = infoF:WaitForChild("Equip")
local dropB = infoF:WaitForChild("Drop")
local instructT = infoF:WaitForChild("Instructions"); instructT.Visible = false

local itemsSF = invF:WaitForChild("ItemsScroll")
local itemSample = itemsSF:WaitForChild("Sample"); itemSample.Visible = false

local armorF = invF:WaitForChild("Armor")
local armorInnerF = armorF:WaitForChild("Inner")
local mouse = player:GetMouse()

local stackCountLabel = invF:WaitForChild("Decoration"):WaitForChild("StackCount")

local hotbarSlots = {
	hotbarF.Slot1,
	hotbarF.Slot2,
	hotbarF.Slot3,
	hotbarF.Slot4,
	hotbarF.Slot5,
	hotbarF.Slot6,
	hotbarF.Slot7,
	hotbarF.Slot8
}

local keysToSlots = {
	[Enum.KeyCode.One] = hotbarF.Slot1;
	[Enum.KeyCode.Two] = hotbarF.Slot2;
	[Enum.KeyCode.Three] = hotbarF.Slot3;
	[Enum.KeyCode.Four] = hotbarF.Slot4;
	[Enum.KeyCode.Five] = hotbarF.Slot5;
	[Enum.KeyCode.Six] = hotbarF.Slot6;
	[Enum.KeyCode.Seven] = hotbarF.Slot7;
	[Enum.KeyCode.Eight] = hotbarF.Slot8;
}

local armorSlots = {
	Head = armorInnerF.Head;
	Chest = armorInnerF.Chest;
	Feet = armorInnerF.Boots;
}

--Module
local InventoryClient = {}
InventoryClient.OpenPosition = invF.Position
InventoryClient.ClosePosition = invF.Position + UDim2.fromScale(0,1)
InventoryClient.OpenCloseDb = false
InventoryClient.IsOpen = false

InventoryClient.InvData = nil
InventoryClient.SelectedStackId = nil
InventoryClient.UpdatingDb = false

InventoryClient.EquipInstructText = instructT.Text
InventoryClient.HeldSlotNum = nil

InventoryClient.ErrorDb = false
InventoryClient.ErrorPosition = errorT.Position
InventoryClient.ErrorTime = 2

function InventoryClient.Start()
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	InventoryClient.UpdateInventoryData()
	InventoryClient.UpdateDisplay()
	InventoryClient.UpdateHeldItem()

	Signal.ListenRemote("InventoryClient:Update", function(newInvData: Types.Inventory)
		InventoryClient.InvData = newInvData
		InventoryClient.UpdateDisplay()
		InventoryClient.UpdateHeldItem()
		moneyCountLabel.Text = "$" .. tostring(newInvData.Money or 0)
	end)
	Signal.ListenRemote("InventoryClient:ErrorMessage", InventoryClient.ErrorMessage)
	Signal.ListenRemote("InventoryClient:UpdateMoney", function(money: number)
		moneyCountLabel.Text = tostring(money)
	end)

	UIS.InputBegan:Connect(InventoryClient.OnInputBegan)
	invB.MouseButton1Click:Connect(function()
		InventoryClient.SetWindowOpen(not InventoryClient.IsOpen)
	end)

	equipB.MouseButton1Up:Connect(InventoryClient.OnEquipButton)
	dropB.MouseButton1Up:Connect(InventoryClient.OnDropButton)

	for i, slotF: TextButton in hotbarSlots do
		slotF.MouseButton1Click:Connect(function()
			InventoryClient.ToggleHold(i)
		end)
	end
end

function InventoryClient.OnInputBegan(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then return end
	if input.KeyCode == Enum.KeyCode.B then
		InventoryClient.SetWindowOpen(not InventoryClient.IsOpen)
	end

	for key: Enum.KeyCode, slotF: TextButton in keysToSlots do
		if input.KeyCode == key then
			InventoryClient.ToggleHold(table.find(hotbarSlots, slotF))
			break
		end
	end
end

function InventoryClient.SetWindowOpen(toSet: boolean)
	if InventoryClient.OpenCloseDb then return end
	InventoryClient.OpenCloseDb = true

	if toSet == true then
		-- Close Storage GUI if open
		local playerGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
		if playerGui then
			local storageScreen = playerGui:FindFirstChild("Storage")
			if storageScreen then
				local storageGui = storageScreen:FindFirstChild("Storage")
				if storageGui and storageGui.Visible then
					storageGui.Visible = false
				end
			end
		end

		UIS.MouseIconEnabled = true
		invF.Position = InventoryClient.ClosePosition
		invF.Visible = true
		invF:TweenPosition(InventoryClient.OpenPosition, Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.5)
		task.wait(.5)
		InventoryClient.IsOpen = true
	else
		UIS.MouseIconEnabled = false
		invF:TweenPosition(InventoryClient.ClosePosition, Enum.EasingDirection.In, Enum.EasingStyle.Quart, 0.5)
		task.wait(0.5)
		invF.Visible = false
		InventoryClient.IsOpen = false
	end

	InventoryClient.OpenCloseDb = false
end

function InventoryClient.OnEquipButton()
	local stackData = InventoryClient.FindStackDataFromID(InventoryClient.SelectedStackId)
	if equipB.Text == "Equip" and stackData ~= nil then
		local tempJanitor = Janitor.new()
		instructT.Visible = true; tempJanitor:GiveChore(function() instructT.Visible = false end)
		equipB.Text = "<-->"; tempJanitor:GiveChore(function() equipB.Text = "Equip" end)

		if stackData.ItemType == "Armor" then
			tempJanitor:Clean()
			local success = Signal.InvokeServer("InventoryServer:EquipArmor", stackData.StackId)
			if not success then
				InventoryClient.ErrorMessage("Something went wrong while equipping armor!")
				return 
			end
		else
			local chosenSlot: TextButton = nil
			local slotNum: number = nil
			tempJanitor:GiveChore(UIS.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
				if gameProcessedEvent then return end 
				if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
				for key: Enum.KeyCode, slotF: TextButton in keysToSlots do
					if input.KeyCode == key then 
						chosenSlot = slotF
						tempJanitor:Clean()
						return
					end
				end
				instructT.Text = "Error: Not a valid key"; tempJanitor:GiveChore(function() instructT.Text = InventoryClient.EquipInstructText end)
				task.wait(2)
				tempJanitor:Clean()
			end))
			for i, slotF: TextButton in hotbarSlots do
				tempJanitor:GiveChore(slotF.MouseButton1Click:Connect(function()
					chosenSlot = slotF
					slotNum = i
					tempJanitor:Clean()
				end))
			end
			while chosenSlot == nil do task.wait() end
			if slotNum == nil then
				slotNum = table.find(hotbarSlots, chosenSlot)
			end
			Signal.FireServer("InventoryServer:EquipToHotbar", slotNum, stackData.StackId)
		end
	elseif equipB.Text == "Unequip" and stackData ~= nil then
		if stackData.ItemType == "Armor" then
			Signal.FireServer("InventoryServer:UnequipArmor", InventoryClient.SelectedStackId)
		else
			Signal.FireServer("InventoryServer:UnequipFromHotbar", InventoryClient.SelectedStackId)
		end
	end
end

function InventoryClient.OnDropButton()
	if InventoryClient.SelectedStackId == nil then return end
	local success: boolean = Signal.InvokeServer("InventoryServer:DropItem", InventoryClient.SelectedStackId)
	if success == nil then
		InventoryClient.ErrorMessage("Something went wrong")
	elseif success == false then
		InventoryClient.ErrorMessage("You can't drop that item")
	end
end

function InventoryClient.SetEquipButton(toSet: boolean)
	if toSet == true then
		equipB.Text = "Equip"
		equipB.BackgroundColor3 = equipB:GetAttribute("EquipColor")
	else
		equipB.Text = "Unequip"
		equipB.BackgroundColor3 = equipB:GetAttribute("UnequipColor")
	end
end

function InventoryClient.ToggleHold(slotNum: number)
	if slotNum == nil then return end
	if InventoryClient.HeldSlotNum == slotNum then
		Signal.FireServer("InventoryServer:UnholdItems")
	else
		Signal.FireServer("InventoryServer:HoldItem", slotNum)
	end
end

function InventoryClient.UpdateHeldItem()
	local char: Model = player.Character; if not char then return end
	local tool: Tool = char:FindFirstChildOfClass("Tool")
	if tool then
		local slotNum: number = nil
		for i = 1,8 do
			local stackId: number? = InventoryClient.InvData.Hotbar["Slot" .. i]
			local stackData: Types.StackData = InventoryClient.FindStackDataFromID(stackId)
			if stackData ~= nil and table.find(stackData.Items, tool) then
				slotNum = i
				break
			end
		end
		if slotNum ~= nil then
			InventoryClient.HeldSlotNum = slotNum
			local slotF: TextButton = hotbarSlots[slotNum]
			for i, otherSlotF: TextButton in hotbarSlots do
				if otherSlotF == slotF then
					otherSlotF.BackgroundColor3 = otherSlotF:GetAttribute("SelectedColor")
				else
					otherSlotF.BackgroundColor3 = otherSlotF:GetAttribute("NormalColor")
				end
			end
		else
			InventoryClient.HeldSlotNum = nil
			Signal.FireServer("InventoryServer:UnholdItems")
		end
	else
		for i, slotF: TextButton in hotbarSlots do
			slotF.BackgroundColor3 = slotF:GetAttribute("NormalColor")
		end
		InventoryClient.HeldSlotNum = nil
	end
end

function InventoryClient.CheckItemEquipped(stackData: Types.StackData): boolean
	if stackData.ItemType == "Armor" then
		for armorType: string, stackId: number in InventoryClient.InvData.Armor do
			if stackId == stackData.StackId then
				return true
			end
		end
		return false
	else
		for slotKey: string, stackId: number in InventoryClient.InvData.Hotbar do
			if stackId == stackData.StackId then
				return true
			end
		end
		return false
	end
end

function InventoryClient.UpdateInventoryData()
	InventoryClient.InvData = Signal.InvokeServer("InventoryServer:GetInventoryData")
end

function InventoryClient.UpdateDisplay()
	while InventoryClient.UpdatingDb do task.wait() end
	InventoryClient.UpdatingDb = true

	-- Update stack count label
	local stackCount = #InventoryClient.InvData.Inventory
	local maxStacks = InventoryClient.InvData.MaxStacks or 10
	stackCountLabel.Text = ("%d/%d Stacks"):format(stackCount, maxStacks)

	-- clearing items
	for i, itemF: Frame in itemsSF:GetChildren() do
		if itemF.ClassName == "TextButton" and itemF ~= itemSample then
			itemF:Destroy()
		end
	end

	local inv: Types.Inventory = InventoryClient.InvData
	for i, stackData: Types.StackData in inv.Inventory do
		local itemF = itemSample:Clone()
		itemF.Name = "Stack-" .. stackData.StackId
		itemF.Image.Image = stackData.Image
		itemF.ItemCount.Text = #stackData.Items .. "x"
		itemF.Equipped.Visible = InventoryClient.CheckItemEquipped(stackData)
		itemF.Parent = itemSample.Parent
		itemF.Visible = true

		itemF.MouseButton1Click:Connect(function()
			if InventoryClient.SelectedStackId == stackData.StackId then
				InventoryClient.SelectItem()
			else	
				InventoryClient.SelectItem(stackData)
			end
		end)
	end

	for slotNum = 1, 8 do
		local slotF: TextButton = hotbarSlots[slotNum]
		local stackId: number? = InventoryClient.InvData.Hotbar["Slot" .. slotNum]
		if stackId == nil then
			slotF.ItemCount.Visible = false
			slotF.Image.Image = ""
		else
			local foundStack: Types.StackData = InventoryClient.FindStackDataFromID(stackId)
			if foundStack ~= nil then
				slotF.ItemCount.Visible = true
				slotF.ItemCount.Text = #foundStack.Items .. "x"
				slotF.Image.Image = foundStack.Image
			else
				slotF.ItemCount.Visible = false
				slotF.Image.Image = ""
			end
		end
	end

	for i, armorType: string in {"Head", "Chest", "Feet"} do
		local slotF: TextButton = armorSlots[armorType]
		local stackId: number? = InventoryClient.InvData.Armor[armorType]
		local stackData: Types.StackData = InventoryClient.FindStackDataFromID(stackId)
		if stackData == nil then
			slotF.Image.Image = ""
		else
			slotF.Image.Image = stackData.Image
		end
	end

	local selectedStack: Types.StackData? = InventoryClient.FindStackDataFromID(InventoryClient.SelectedStackId)
	InventoryClient.SelectItem(selectedStack)

	InventoryClient.UpdatingDb = false
end

function InventoryClient.SelectItem(stackData: Types.StackData)
	InventoryClient.SelectedStackId = if stackData ~= nil then stackData.StackId else nil
	local itemF: TextButton? = if stackData ~= nil then itemsSF:FindFirstChild("Stack-" .. stackData.StackId) else nil
	for i, otherItemF: TextButton in itemsSF:GetChildren() do
		if otherItemF.ClassName == "TextButton" and otherItemF ~= itemSample then
			if otherItemF == itemF then 
				otherItemF.BackgroundColor3 = otherItemF:GetAttribute("SelectedColor")
			else
				otherItemF.BackgroundColor3 = otherItemF:GetAttribute("NormalColor")
			end
		end
	end 
	if stackData ~= nil then
		infoF.Visible = true
		itemNameT.Text = stackData.Name
		itemDescT.Text = stackData.Description
		local isEquipped = InventoryClient.CheckItemEquipped(stackData)
		InventoryClient.SetEquipButton(not isEquipped)
	else
		infoF.Visible = false
		InventoryClient.SetEquipButton(true)
	end	
end

function InventoryClient.ErrorMessage(message: string)
	if InventoryClient.ErrorDb then return end
	local errorJanitor = Janitor.new()
	InventoryClient.ErrorDb = true; errorJanitor:GiveChore(function() InventoryClient.ErrorDb = false end)
	errorT.Text = message
	errorT.Position = InventoryClient.ErrorPosition + UDim2.fromScale(0, -0.4)
	errorT.UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	errorT.Visible = true; errorJanitor:GiveChore(function()
		errorT.Visible = false
	end)
	local tweenOut = TS:Create(errorT, TweenInfo.new(InventoryClient.ErrorTime/4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = InventoryClient.ErrorPosition;
	}); errorJanitor:GiveChore(tweenOut)
	tweenOut:Play()
	tweenOut.Completed:Wait()
	task.wait(InventoryClient.ErrorTime/2)
	local tweenAway = TS:Create(errorT, TweenInfo.new( InventoryClient.ErrorTime/4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		TextTransparency = 1;
		TextStrokeTransparency = 1;
	}); errorJanitor:GiveChore(tweenAway)
	errorJanitor:GiveChore(function()
		errorT.TextTransparency = 0
	end)
	tweenAway:Play()
	tweenAway.Completed:Wait()
	errorJanitor:Clean()
end

function InventoryClient.FindStackDataFromID(stackId: number): Types.StackData?
	if stackId == nil then return end
	for i, stackData: Types.StackData in InventoryClient.InvData.Inventory do
		if stackData.StackId == stackId then
			return stackData
		end
	end
end

return InventoryClient