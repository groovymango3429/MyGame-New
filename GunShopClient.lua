-- GunShopClient.lua

-- Services
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")

-- Modules
local Signal = require(RS.Modules.Signal)

-- Player Variables
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Money GUI Variable (adjust path as needed)
local moneyLabel = playerGui:FindFirstChild("MoneyLabel")

-- Shop GUI Variables
local shopGui = playerGui:WaitForChild("GunShop")
local Shop = shopGui:WaitForChild("Shop")
local Background = Shop:WaitForChild("Background")
local itemsScroll = Background:WaitForChild("ItemsScroll")
local itemSample = itemsScroll:WaitForChild("Sample") -- Invisible template

-- Cart GUI
local cartFrame = Shop:WaitForChild("Background"):WaitForChild("Background")
local cartScroll = cartFrame:WaitForChild("ItemsScroll")
local cartSample = cartScroll:WaitForChild("Sample") -- Invisible template
local cartTotalCost = cartFrame:WaitForChild("Total")
local purchaseButton = cartFrame:WaitForChild("Purchase")

-- Cart storage: array of {Name, Cost, Count}
local cartItems = {}

-- Inventory tracking (for max inventory logic)
local maxInventory = 10 -- Default, can be updated from server
local currentInventoryCount = 0

-- Error label (must exist in PlayerGui and be set up as overlay)
local errorLabel = playerGui:FindFirstChild("ErrorLabel")

local function showError(msg)
	if errorLabel then
		errorLabel.Text = msg
		errorLabel.Visible = true
		task.spawn(function()
			local thisMsg = msg
			wait(3)
			if errorLabel.Text == thisMsg then
				errorLabel.Visible = false
			end
		end)
	end
end

-- Helper: update cart total cost label
local function updateCartTotal()
	local total = 0
	for _, data in ipairs(cartItems) do
		total = total + (data.Count * data.Cost)
	end
	cartTotalCost.Text = "Total: $" .. tostring(total)
end

-- Helper: refresh cart GUI
local function refreshCartDisplay()
	for _, obj in ipairs(cartScroll:GetChildren()) do
		if obj:IsA("Frame") and obj ~= cartSample then
			obj:Destroy()
		end
	end

	for i, data in ipairs(cartItems) do
		local frame = cartSample:Clone()
		frame.Name = "CartItem_" .. data.Name
		frame.Visible = true
		frame.Parent = cartScroll

		local cartItemName = frame:FindFirstChild("CartItemName")
		local cartItemTotalCost = frame:FindFirstChild("CartItemTotalCost")
		local cartItemRemove = frame:FindFirstChild("CartItemRemove")

		if cartItemName then cartItemName.Text = data.Name end
		if cartItemTotalCost then
			cartItemTotalCost.RichText = true
			local amountText = '<font color="#339CFF">' .. tostring(data.Count) .. 'x</font>'
			local priceText = '<font color="#22FF22">$' .. (data.Cost * data.Count) .. '</font>'
			cartItemTotalCost.Text = amountText .. "  " .. priceText
		end

		if cartItemRemove then
			cartItemRemove.MouseButton1Click:Connect(function()
				table.remove(cartItems, i)
				refreshCartDisplay()
				updateCartTotal()
			end)
		end
	end

	updateCartTotal()
end

-- Helper: get total items in cart
local function getCartCount()
	local count = 0
	for _, data in ipairs(cartItems) do
		count = count + data.Count
	end
	return count
end

-- Setup logic for Add to Cart button
local function setupShopItemButton(sampleFrame)
	local addButton = sampleFrame:FindFirstChild("AddToCart")
	if not addButton then return end
	addButton.MouseButton1Click:Connect(function()
		local itemName = sampleFrame:FindFirstChild("ItemName") and sampleFrame.ItemName.Text or "Unknown"
		local itemCostText = sampleFrame:FindFirstChild("ItemCost") and sampleFrame.ItemCost.Text or ""
		local itemCost = tonumber(itemCostText:match("[0-9%.]+")) or 0

		if itemName == "Unknown" or itemCost == 0 then
			warn("Shop item missing name or cost. Check sampleFrame children and their names!")
			return
		end

		local cartCount = getCartCount()

		-- Only allow adding if cart+inventory < max, i.e. stop at max (can't add to reach or exceed max)
		if (currentInventoryCount + cartCount) >= maxInventory then
			showError("You cannot add more items. Inventory will be full.")
			return
		end

		-- Add to cart logic
		local found = false
		for _, item in ipairs(cartItems) do
			if item.Name == itemName then
				item.Count = item.Count + 1
				found = true
				break
			end
		end
		if not found then
			table.insert(cartItems, {Name = itemName, Cost = itemCost, Count = 1})
		end

		refreshCartDisplay()
		updateCartTotal()
	end)
end

-- Example shop items
local ShopItems = {
	{Name = "G19 ROLAND SPECIAL", Cost = 100, Image = "rbxassetid://87139658712879"},
	{Name = "TROY DEFENSE AR", Cost = 350, Image = "rbxassetid://72757692405214"},
}

for _, obj in ipairs(itemsScroll:GetChildren()) do
	if obj:IsA("Frame") and obj ~= itemSample then
		obj:Destroy()
	end
end

for _, item in ipairs(ShopItems) do
	local sample = itemSample:Clone()
	sample.Visible = true
	sample.Parent = itemsScroll
	local nameObj = sample:FindFirstChild("ItemName")
	local costObj = sample:FindFirstChild("ItemCost")
	local imageObj = sample:FindFirstChild("Image")
	if nameObj then nameObj.Text = item.Name end
	if costObj then costObj.Text = "$" .. tostring(item.Cost) end
	if imageObj and imageObj:IsA("ImageLabel") then imageObj.Image = item.Image or "" end
	setupShopItemButton(sample)
end

-- Purchase logic
purchaseButton.MouseButton1Click:Connect(function()
	local purchaseCart = {}
	for _, data in ipairs(cartItems) do
		table.insert(purchaseCart, {
			Name = data.Name,
			Count = data.Count
		})
	end

	Signal.FireServer("GunShop:Purchase", purchaseCart)

	table.clear(cartItems)
	refreshCartDisplay()
	updateCartTotal()
end)

-- ProximityPrompt logic to open/close GUI
local promptPath = Workspace:WaitForChild("GunShop"):WaitForChild("Table"):WaitForChild("Table"):WaitForChild("ProximityPrompt")
local proximityPrompt = promptPath

local function setShopOpen(isOpen)
	shopGui.Enabled = isOpen
	if isOpen then
		refreshCartDisplay()
		UIS.MouseIconEnabled = true
		UIS.MouseBehavior = Enum.MouseBehavior.Default
	end
end

setShopOpen(false)

proximityPrompt.Triggered:Connect(function(triggeringPlayer)
	if triggeringPlayer == player then
		setShopOpen(true)
	end
end)

local closeButton = Shop:WaitForChild("Close")
if closeButton and closeButton:IsA("TextButton") then
	closeButton.MouseButton1Click:Connect(function()
		shopGui.Enabled = false
		UIS.MouseIconEnabled = false
	end)
end

-- Money update handling
if moneyLabel then
	moneyLabel.Text = "$0"
end

Signal.Listen("MoneyClient:Update", function(newMoney)
	if moneyLabel then
		moneyLabel.Text = "$" .. tostring(newMoney)
	end
end)

-- Listen for inventory updates from server and update local counts
Signal.Listen("InventoryClient:Update", function(data)
	print("UPDATED")
	if typeof(data) == "table" then
		currentInventoryCount = data.Count or 0
		maxInventory = data.Max or maxInventory
	end
end)

return {
	ShopGui = shopGui,
	ItemsScroll = itemsScroll,
	ItemSample = itemSample,
	CartFrame = cartFrame,
	CartScroll = cartScroll,
	CartSample = cartSample,
	CartTotalCost = cartTotalCost,
	PurchaseButton = purchaseButton,
	CartItems = cartItems
}