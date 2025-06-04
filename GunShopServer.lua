-- Services
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Modules
local Signal = require(RS.Modules.Signal)
local InventoryServer = require(ServerScriptService.Server.InventoryServer)

-- Item price table (should match client source of truth)
local ItemPrices = {
	["G19 ROLAND SPECIAL"] = 100,
	["TROY DEFENSE AR"] = 350,
	-- Add more items as needed
}

Signal.ListenRemote("GunShop:Purchase", function(player, purchaseCart)
	print("Trying to Buy")
	if typeof(purchaseCart) ~= "table" then return end

	-- Calculate total cost
	local totalCost = 0
	local totalToPurchase = 0
	for _, entry in ipairs(purchaseCart) do
		local itemName = entry.Name
		local count = entry.Count or 1
		local price = ItemPrices[itemName]
		if price then
			totalCost = totalCost + price * count
			totalToPurchase = totalToPurchase + count
		else
			Signal.FireClient(player, "InventoryClient:ErrorMessage", "Invalid item: " .. tostring(itemName))
			return
		end
	end

	-- Get player's money & inventory
	local inv = InventoryServer.AllInventories[player]
	if not inv then
		Signal.FireClient(player, "InventoryClient:ErrorMessage", "Inventory data not loaded.")
		return
	end
	if inv.Money < totalCost then
		Signal.FireClient(player, "InventoryClient:ErrorMessage", "Not enough money!")
		return
	end

	local maxInventory = inv.MaxInventory or 10 -- Adjust as needed for your inventory system
	local currentInventoryCount = 0
	for _, item in ipairs(player.Backpack:GetChildren()) do
		currentInventoryCount = currentInventoryCount + 1
	end

	-- Only allow purchase if all items will fit
	if (currentInventoryCount + totalToPurchase) > maxInventory then
		Signal.FireClient(player, "InventoryClient:ErrorMessage", "Not enough inventory space. Please reduce items in your cart.")
		return
	end

	-- Give items and remove money
	for _, entry in ipairs(purchaseCart) do
		local itemName = entry.Name
		local count = entry.Count or 1
		local itemTemplate = ServerStorage.AllItems:FindFirstChild(itemName)
		if not itemTemplate then
			Signal.FireClient(player, "InventoryClient:ErrorMessage", "Item not found: " .. itemName)
			return
		end
		for i = 1, count do
			local clone = itemTemplate:Clone()
			clone.Parent = player.Backpack
			InventoryServer.RegisterItem(player, clone)
		end
	end

	InventoryServer.RemoveMoney(player, totalCost)
	Signal.FireClient(player, "InventoryClient:ErrorMessage", "Purchase successful!")
end)