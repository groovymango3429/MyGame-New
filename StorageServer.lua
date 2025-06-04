local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Types = require(ReplicatedStorage.Modules.Types)
local Signal = require(ReplicatedStorage.Modules.Signal)
local ServerScriptService = game:GetService("ServerScriptService")
local InventoryServer = require(ServerScriptService.Server.InventoryServer)

local ShelfData = {}

local function getPlayerPlot(player)
	local plotName = player.Name .. "'s" ..  " Plot"
	local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(plotName)
	return plot
end

local function getShelfByStorageId(player, storageId)
	local plot = getPlayerPlot(player)
	if not plot then return nil end
	local objects = plot:FindFirstChild("Objects")
	if not objects then return nil end
	for _, shelf in ipairs(objects:GetChildren()) do
		local shelfStorageId = shelf:GetAttribute("StorageId")
		if shelfStorageId == storageId then
			return shelf
		end
	end
	return nil
end

Signal.ListenRemote("Storage:Open", function(player, storageId)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf then return end
	if not ShelfData[storageId] then
		ShelfData[storageId] = {
			Items = {},
			MaxStacks = 8,
			Owner = player,
			ShelfInstance = shelf,
		}
	end
	if ShelfData[storageId].Owner ~= player then return end
	Signal.FireClient(player, "Storage:Open", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
end)

-- Deposit N tools from inventory to shelf
Signal.ListenRemote("Storage:Deposit", function(player, storageId, stackId, amount)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf or not ShelfData[storageId] or ShelfData[storageId].Owner ~= player then return end
	local inv = InventoryServer.AllInventories[player]
	if not inv then return end

	local stackIdx, stackData
	for i, stack in ipairs(inv.Inventory) do
		if stack.StackId == stackId then
			stackIdx = i
			stackData = stack
			break
		end
	end
	if not stackIdx or not stackData then return end

	local stackCount = #stackData.Items
	local transferAmount = tonumber(amount) or stackCount
	if transferAmount < 1 then return end
	if transferAmount > stackCount then transferAmount = stackCount end

	local maxPerStack = InventoryServer.MaxStackData[stackData.ItemType] or 1
	local itemsToDeposit = {}
	for i = 1, transferAmount do
		itemsToDeposit[i] = stackData.Items[i]
	end
	local remaining = #itemsToDeposit
	local deposited = 0

	-- Merge into shelf stacks where possible
	for _, shelfStack in ipairs(ShelfData[storageId].Items) do
		if remaining <= 0 then break end
		if shelfStack.Name == stackData.Name and shelfStack.ItemType == stackData.ItemType then
			local shelfMax = InventoryServer.MaxStackData[shelfStack.ItemType] or 1
			local canAdd = shelfMax - (#shelfStack.Items or 0)
			for i = 1, math.min(canAdd, remaining) do
				local tool = table.remove(itemsToDeposit, 1)
				table.insert(shelfStack.Items, tool)
				-- Remove from Backpack/Character
				if tool and tool.Parent and (tool.Parent == player.Backpack or tool.Parent == player.Character) then
					tool.Parent = nil
				end
				deposited += 1
			end
			shelfStack.Count = #shelfStack.Items
			remaining = #itemsToDeposit
		end
	end

	-- Leftovers go in new stack(s)
	while remaining > 0 do
		if #ShelfData[storageId].Items >= ShelfData[storageId].MaxStacks then break end
		local take = math.min(maxPerStack, remaining)
		local newStack = {
			Name = stackData.Name,
			Description = stackData.Description,
			Image = stackData.Image,
			ItemType = stackData.ItemType,
			IsDroppable = stackData.IsDroppable,
			Items = {},
			StackId = inv.NextStackId or 0,
		}
		inv.NextStackId = (inv.NextStackId or 0) + 1
		for i = 1, take do
			local tool = table.remove(itemsToDeposit, 1)
			table.insert(newStack.Items, tool)
			if tool and tool.Parent and (tool.Parent == player.Backpack or tool.Parent == player.Character) then
				tool.Parent = nil
			end
			deposited += 1
		end
		newStack.Count = #newStack.Items
		table.insert(ShelfData[storageId].Items, newStack)
		remaining = #itemsToDeposit
	end

	-- Only remove deposited items from inventory stackData
	if deposited > 0 then
		for i = 1, deposited do
			table.remove(stackData.Items, 1)
		end
		if #stackData.Items == 0 then
			table.remove(inv.Inventory, stackIdx)
		end
	end

	if deposited == 0 then
		Signal.FireClient(player, "Storage:Error", "Shelf is full!")
		return
	end

	Signal.FireClient(player, "Storage:Update", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
	Signal.FireClient(player, "InventoryClient:Update", inv)
end)

-- Withdraw N tools from shelf to inventory
Signal.ListenRemote("Storage:Withdraw", function(player, storageId, stackId, amount)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf or not ShelfData[storageId] or ShelfData[storageId].Owner ~= player then return end
	local inv = InventoryServer.AllInventories[player]
	if not inv then return end

	local stackIdx, stackData
	for i, stack in ipairs(ShelfData[storageId].Items) do
		if stack.StackId == stackId then
			stackIdx = i
			stackData = stack
			break
		end
	end
	if not stackIdx or not stackData then return end

	local stackCount = #stackData.Items
	local transferAmount = tonumber(amount) or stackCount
	if transferAmount < 1 then return end
	if transferAmount > stackCount then transferAmount = stackCount end

	local maxPerStack = InventoryServer.MaxStackData[stackData.ItemType] or 1
	local itemsToWithdraw = {}
	for i = 1, transferAmount do
		itemsToWithdraw[i] = stackData.Items[i]
	end
	local remaining = #itemsToWithdraw
	local actuallyWithdrawn = 0

	-- Merge into inventory stacks where possible
	for _, invStack in ipairs(inv.Inventory) do
		if remaining <= 0 then break end
		if invStack.Name == stackData.Name and invStack.ItemType == stackData.ItemType then
			local invMax = InventoryServer.MaxStackData[invStack.ItemType] or 1
			local canAdd = invMax - (#invStack.Items or 0)
			for i = 1, math.min(canAdd, remaining) do
				local item = table.remove(itemsToWithdraw, 1)
				-- If item is a placeholder, clone from template
				if typeof(item) ~= "Instance" or not item:IsA("Tool") then
					local template = ServerStorage:FindFirstChild("AllItems"):FindFirstChild(stackData.Name)
					if template then
						item = template:Clone()
					end
				end
				table.insert(invStack.Items, item)
				if item then item.Parent = player.Backpack end
				actuallyWithdrawn += 1
			end
			invStack.Count = #invStack.Items
			remaining = #itemsToWithdraw
		end
	end

	-- Leftovers go in new stack(s)
	while remaining > 0 do
		if #inv.Inventory >= InventoryServer.MaxStacks then break end
		local take = math.min(maxPerStack, remaining)
		local newStack = {
			Name = stackData.Name,
			Description = stackData.Description,
			Image = stackData.Image,
			ItemType = stackData.ItemType,
			IsDroppable = stackData.IsDroppable,
			Items = {},
			StackId = inv.NextStackId or 0,
		}
		inv.NextStackId = (inv.NextStackId or 0) + 1
		for i = 1, take do
			local item = table.remove(itemsToWithdraw, 1)
			if typeof(item) ~= "Instance" or not item:IsA("Tool") then
				local template = ServerStorage:FindFirstChild("AllItems"):FindFirstChild(stackData.Name)
				if template then
					item = template:Clone()
				end
			end
			table.insert(newStack.Items, item)
			if item then item.Parent = player.Backpack end
			actuallyWithdrawn += 1
		end
		newStack.Count = #newStack.Items
		table.insert(inv.Inventory, newStack)
		remaining = #itemsToWithdraw
	end

	if actuallyWithdrawn == 0 then
		Signal.FireClient(player, "Storage:Error", "Inventory is full!")
		return
	end

	-- Remove withdrawn items from shelf stack
	for i = 1, actuallyWithdrawn do
		table.remove(stackData.Items, 1)
	end
	stackData.Count = #stackData.Items
	if #stackData.Items == 0 then
		table.remove(ShelfData[storageId].Items, stackIdx)
	end

	Signal.FireClient(player, "Storage:Update", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
	Signal.FireClient(player, "InventoryClient:Update", inv)
end)

Players.PlayerRemoving:Connect(function(player)
	for storageId, data in pairs(ShelfData) do
		if data.Owner == player then
			ShelfData[storageId] = nil
		end
	end
end)

return ShelfData