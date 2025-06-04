local playersRemaining = Instance.new("NumberValue")
local PlotManager = require(script.Parent.PlotManager)
local PlotSpawnPool = require(script.Parent.PlotSpawnPool)
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotStore = DataStoreService:GetDataStore("PlotStore")
local placeableObjects = ReplicatedStorage.PlaceableObjects

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ToolTemplates = ServerStorage:WaitForChild("AllItems")
local ShelfData = require(ServerScriptService.StorageServer)
local InventoryServer = require(ServerScriptService.Server.InventoryServer)

type ObjectInfo = {
	Name: string,
	Cf: {number},
	StorageId: string?,
	StorageItems: table?,
}

local STACK_SAVE_FIELDS = {
	"Name", "StackId", "Count", "Type", "ItemType", "IsDroppable",
	"Image", "Description", "Items"
}

local function deepSanitize(value)
	local t = type(value)
	if t == "string" or t == "number" or t == "boolean" or t == "nil" then
		return value
	elseif t == "table" then
		local out = {}
		for k, v in pairs(value) do
			if type(k) == "string" or type(k) == "number" then
				out[k] = deepSanitize(v)
			end
		end
		return out
	else
		return nil
	end
end

local function sanitizeStack(stack)
	local out = {}
	for _, field in ipairs(STACK_SAVE_FIELDS) do
		local value = stack[field]
		if type(value) == "table" then
			local copy = {}
			for k, v in pairs(value) do
				if typeof(v) ~= "Instance" and typeof(v) ~= "function" then
					copy[k] = v
				end
			end
			out[field] = copy
		elseif typeof(value) ~= "Instance" and typeof(value) ~= "function" then
			out[field] = value
		end
	end
	out.Count = stack.Items and #stack.Items or stack.Count or 1
	return out
end

local function sanitizeShelfItems(items)
	local sanitized = {}
	for i, stack in ipairs(items) do
		sanitized[i] = sanitizeStack(stack)
	end
	return sanitized
end

local function serializePlot(plot: Model)
	local data = {}
	for _, object in plot.Objects:GetChildren() do
		local objectCF = plot:GetPivot():ToObjectSpace(object:GetPivot())
		local info: ObjectInfo = {
			Name = object.Name,
			Cf = table.pack(objectCF:GetComponents())
		}
		local storageId = object:GetAttribute("StorageId")
		if storageId then
			info.StorageId = storageId
			local storageData = ShelfData and ShelfData[storageId]
			if storageData and storageData.Items then
				info.StorageItems = sanitizeShelfItems(storageData.Items)
			end
		end
		table.insert(data, info)
	end
	return data
end

local PlotStorage = {}

function PlotStorage.Load(player: Player) 
	local success, data: {ObjectInfo} = pcall(function()
		return PlotStore:GetAsync(player.UserId)
	end)

	if not success then 
		warn(data)
		playersRemaining.Value += 1
		return 
	end
	if not Players:GetPlayerByUserId(player.UserId) then 
		return
	end

	local plot = PlotManager.SpawnPlot(player)
	if data then 
		for _, objectInfo in data do 
			local object = placeableObjects[objectInfo.Name]:Clone()
			local relativeCf = CFrame.new(table.unpack(objectInfo.Cf))
			object:PivotTo(plot:GetPivot():ToWorldSpace(relativeCf))
			if objectInfo.StorageId then
				object:SetAttribute("StorageId", objectInfo.StorageId)
				local restoredItems = {}
				if objectInfo.StorageItems then
					for i, savedStack in ipairs(objectInfo.StorageItems) do
						local stack = {}
						for _, field in ipairs(STACK_SAVE_FIELDS) do
							stack[field] = savedStack[field]
						end
						stack.Items = stack.Items or {}
						-- Placeholders for storage only - never for player inventory!
						if (#stack.Items == 0) and stack.Count and stack.Name then
							for j = 1, stack.Count do
								stack.Items[j] = true
							end
						end
						restoredItems[i] = stack
					end
				end
				ShelfData[objectInfo.StorageId] = {
					Items = restoredItems,
					MaxStacks = 8,
					Owner = player,
					ShelfInstance = object,
				}
			end
			object.Parent = plot.Objects 
		end
	end

	playersRemaining.Value += 1
end

function PlotStorage.Save(player: Player)
	local plot = PlotManager.GetPlot(player)
	if not plot or not plot:IsDescendantOf(workspace) then 
		playersRemaining.Value -= 1
		return 
	end

	local data = serializePlot(plot)

	-- Debug: Test serializability before saving
	local HttpService = game:GetService("HttpService")
	local ok, jsonOrErr = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if not ok then
		warn("[PlotStorage][Serialization ERROR]", jsonOrErr)
		warn("[PlotStorage][DATA]", data)
		playersRemaining.Value -= 1
		return
	end

	plot:Destroy()
	PlotSpawnPool.Return(player)

	local success, errMsg = pcall(function()
		PlotStore:SetAsync(player.UserId, data)
	end)

	if not success then 
		warn(errMsg)
	end

	playersRemaining.Value -= 1
end

function PlotStorage.WaitForSave()
	while playersRemaining.Value > 0 do
		playersRemaining.Changed:Wait()
	end
end

-- Withdraw one item from storage bin and put real Tool in Backpack & inventory
function PlotStorage.WithdrawItem(player, storageId, stackIndex)
	local shelf = ShelfData[storageId]
	if not shelf or not shelf.Items or not shelf.Items[stackIndex] then return end

	local stack = shelf.Items[stackIndex]
	local toolName = stack.Name
	if not toolName then return end

	-- Remove one item from the shelf stack (either a bool placeholder or a Tool instance)
	local item
	if stack.Items and type(stack.Items) == "table" and #stack.Items > 0 then
		item = table.remove(stack.Items, 1)
		stack.Count = #stack.Items
	elseif stack.Count and stack.Count > 0 then
		stack.Count -= 1
	end
	if (stack.Items and #stack.Items == 0) or (stack.Count and stack.Count <= 0) then
		table.remove(shelf.Items, stackIndex)
	end

	-- If the withdrawn item is not an instance, clone it from template
	local tool
	if typeof(item) == "Instance" and item:IsA("Tool") then
		tool = item
	else
		local toolTemplate = ToolTemplates and ToolTemplates:FindFirstChild(toolName)
		if not toolTemplate then
			warn("No tool template found for", toolName)
			return
		end
		tool = toolTemplate:Clone()
	end
	tool.Parent = player.Backpack

	-- Add tool to player's inventory stack (always as Tool instance)
	local inv = InventoryServer.AllInventories[player]
	if inv then
		local foundStack
		for _, s in ipairs(inv.Inventory) do
			if s.Name == toolName and s.ItemType == (stack.ItemType or tool:GetAttribute("ItemType")) then
				foundStack = s
				break
			end
		end
		if not foundStack then
			foundStack = {
				Name = toolName,
				Description = tool.ToolTip,
				Image = tool.TextureId,
				ItemType = tool:GetAttribute("ItemType"),
				IsDroppable = tool:GetAttribute("IsDroppable"),
				Items = {},
				StackId = inv.NextStackId or 0,
			}
			inv.NextStackId = (inv.NextStackId or 0) + 1
			table.insert(inv.Inventory, foundStack)
		end
		table.insert(foundStack.Items, tool)
	end
end

return PlotStorage