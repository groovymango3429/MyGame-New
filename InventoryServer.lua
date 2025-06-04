---Services
local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local DSS = game:GetService("DataStoreService")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
--Modules
local Types = require(RS.Modules.Types)
local Janitor = require(RS.Modules.Janitor)
local Signal = require(RS.Modules.Signal)


--data_stores
local IDS = DSS:GetDataStore("InventoryDataStore")


--Constants
local AUTOSAVE_TIME = 15
local SAVE_KEY = "%i-V.01"
local ARMOR_TAG = "%i-%s-EquippedArmor" --player.UserId, armorType
--Module
local InventoryServer = {}
InventoryServer.AllInventories = {}
InventoryServer.Janitors = {}
InventoryServer.HasLoaded = {}
InventoryServer.Respawning = {}
InventoryServer.ToolCanTouch = {}
InventoryServer.ToolCanCollide = {}

InventoryServer.MaxStackData = {
	Armor = 1;
	Special = 1;
	Consumable = 5;
	Resource = 10;
	Weapon = 1;
}

InventoryServer.MaxStacks = 10



--Start
function InventoryServer.Start()
	
	--Playeradded
	for i, player: Player in Players:GetPlayers() do
		task.spawn(InventoryServer.OnPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(InventoryServer.OnPlayerAdded)
	
	Players.PlayerRemoving:Connect(InventoryServer.OnPlayerRemoving)
	
	--Signal events
	Signal.ListenRemote("InventoryServer:GetInventoryData", InventoryServer.GetInventoryData)
	Signal.ListenRemote("InventoryServer:EquipToHotbar", InventoryServer.EquipToHotbar)
	Signal.ListenRemote("InventoryServer:UnequipFromHotbar", InventoryServer.UnequipFromHotbar)
	Signal.ListenRemote("InventoryServer:HoldItem", InventoryServer.HoldItem)
	Signal.ListenRemote("InventoryServer:UnholdItems", InventoryServer.UnholdItems)
	Signal.ListenRemote("InventoryServer:DropItem", InventoryServer.DropItem)
	Signal.ListenRemote("InventoryServer:EquipArmor", InventoryServer.EquipArmor)
	Signal.ListenRemote("InventoryServer:UnequipArmor", InventoryServer.UnequipArmor)
	Signal.ListenRemote("InventoryServer:AddMoney", InventoryServer.AddMoney)
	Signal.ListenRemote("InventoryServer:RemoveMoney", InventoryServer.RemoveMoney)
	---Game shutdown
	game:BindToClose(function()
		for i, player: Player in Players:GetPlayers() do
			InventoryServer.SaveData(player)
		end
	end)
	
	---Auto-Saving
	task.spawn(function()
		while true do
			task.wait()
			for i, player: Player in Players:GetPlayers() do
				task.wait(AUTOSAVE_TIME / #Players:GetPlayers())
				InventoryServer.SaveData(player)
			end
		end
	end)
	-- Connecting post simulation
	RunService.PostSimulation:Connect(InventoryServer.OnPostSimulation)
end

---Player added
function InventoryServer.OnPlayerAdded(player:Player)
--Waiting for starterpack
	for i, tool in StarterPack:GetChildren() do
		while not player.Backpack:FindFirstChild(tool.Name) do
			task.wait()
		end
	end
	

	--Creating Janitor object
	local janitor = Janitor.new()
	InventoryServer.Janitors[player] = janitor
	janitor:GiveChore(function()
		InventoryServer.Janitors[player] = nil
		InventoryServer.Respawning[player] = nil
	end)
	--Creating inventory
	local inv: Types.Inventory = {
		Inventory = {};
		Hotbar = {};
		Armor = {};
		NextStackId = 0;
		Money = 0;
	}
	InventoryServer.AllInventories[player] = inv
	janitor:GiveChore(function() InventoryServer.AllInventories[player] = nil end)
	--Waiting for character to load in for the first time
	if not player.Character then player.CharacterAdded:Wait() end
	InventoryServer.LoadData(player)
	
	--Character Added
	local function charAdded(char: Model)
		-- Registering items
		for i, tool in player.Backpack:GetChildren() do
			InventoryServer.RegisterItem(player, tool)
		end
		
		-- Connecting events
		char.ChildAdded:Connect(function(child: Instance)
			InventoryServer.RegisterItem(player, child)
		end)
		char.ChildRemoved:Connect(function(child: Instance)
			InventoryServer.UnregisterItem(player, child)
		end)
		player.Backpack.ChildAdded:Connect(function(child: Instance)
			InventoryServer.RegisterItem(player, child)
		end)
		player.Backpack.ChildRemoved:Connect(function(child: Instance)
			InventoryServer.UnregisterItem(player, child)
		end)			
		
		--on character dfeath
		local hum: Humanoid = char:WaitForChild("Humanoid")
		hum.Died:Connect(function()
			--unholding items and starting respawn
			InventoryServer.Respawning[player] = true 
			InventoryServer.UnholdItems(player)
			
			--reparenting all items
			local allItems: {Tool} = player.Backpack:GetChildren()
			for i, item: Tool in allItems do
				item.Parent = script
			end
			
			
				
		--char respawning
			player.CharacterAdded:Wait()
			local backpack = player:WaitForChild("Backpack")
			
			--adding items back
			for i, item: Tool in allItems do
				item.Parent = backpack
			end
			
			InventoryServer.Respawning[player] = nil
			
		end)
	end
	
	---Connecting charactrer added
	task.spawn(charAdded, player.Character)
	janitor:GiveChore(player.CharacterAdded:Connect(charAdded))
end

function InventoryServer.OnPlayerRemoving(player: Player)
	
	--clearing extra data
	InventoryServer.SaveData(player)
	InventoryServer.Janitors[player]:Destroy()
end

--Heartbeat loop
function InventoryServer.OnPostSimulation(dt: number)
	InventoryServer.UpdateDroppedItems()
end

--Checking if inventory is full
function InventoryServer.CheckInventoryFull(player: Player, item: Tool)
	--variables
	local inv = InventoryServer.AllInventories[player]; print(player)
	print(inv)
	
	--Checking stacks
	if #inv.Inventory >= InventoryServer.MaxStacks then
		for i, stackData: Types.StackData in inv.Inventory do
			if stackData.Name == item.Name and #stackData.Items < InventoryServer.MaxStackData[stackData.ItemType] then
				return false
			end
		end
		return true
	end
	return false
end

--Updating dropped items
function InventoryServer.UpdateDroppedItems()
	
	--looping all items
	for i, tool: Tool in CS:GetTagged("ItemTool") do
		if not tool:IsDescendantOf(workspace) then continue end
		
		--Variables
		local handle = tool:FindFirstChild("Handle")
		if not handle then 
			warn(`No handle was found for {tool.Name}`)
			continue
			
		end
		local hum: Humanoid? = tool.Parent:FindFirstChild("Humanoid")
		local prompt: ProximityPrompt = handle:FindFirstChild("DroppedItemsPrompt")
		
		--checking if humanoid
		if hum then --tool is in character
			
			--Reenabling can touch and cancollide
			for i, part: BasePart in tool:GetDescendants() do
				if part:IsA("BasePart") then
					
					--resetting can touch
					local prevValue = InventoryServer.ToolCanTouch[part]
				
					if prevValue then
						part.CanTouch = prevValue
						InventoryServer.ToolCanTouch[part] = nil
					end
					--resetting cancollide
					local prevValue = InventoryServer.ToolCanCollide[part]
					if prevValue then
						part.CanCollide = prevValue
						InventoryServer.ToolCanCollide[part] = nil
						
					end
				end
			end
			
			--clearing prompt
			if prompt then
				prompt:Destroy()
			end
			
			
		else
			if not prompt then
				---disabling can touch and cancollide
				for i, part: BasePart in tool:GetDescendants() do
					if part:IsA("BasePart") then
						InventoryServer.ToolCanTouch[part] = part.CanTouch
						part.CanTouch = false
						InventoryServer.ToolCanCollide[part] = part.CanCollide
						part.CanCollide = true
					end
				end
			
				
				--adding proximity prompt
				prompt = script.DroppedItemsPrompt:Clone()
				prompt.ObjectText = tool.Name
				prompt.Parent = handle
				
				--Connecting triggered event
				prompt.Triggered:Connect(function(player: Player)
					
					-- check max items
					if InventoryServer.CheckInventoryFull(player, tool) then
						warn(`{player.Name}'s Inventory Full`)
						Signal.FireClient(player,"InventoryClient:ErrorMessage", "Your Inventory is Full")
						return
					end
					--Inserting item into player's backpack
					local backpack: Backpack = player:FindFirstChild("Backpack"); if not backpack then return end
					tool.Parent = backpack
					
				end)
			end
			

		
			
		end
	end
	
end
-- Sends the updated money value to the client
function InventoryServer.UpdateMoneyClient(player: Player)
	print("Updating Money")
	local inv = InventoryServer.AllInventories[player]
	if not inv then return end

	Signal.FireClient(player, "InventoryClient:UpdateMoney", inv.Money)
end

function InventoryServer.AddMoney(player: Player, amount: number)
	print("Adding money" .. amount)
	local inv = InventoryServer.AllInventories[player]
	print(inv)
	if not inv then print("nope") return end
	inv.Money = (inv.Money or 0) + amount
	print(inv.Money)
	InventoryServer.UpdateMoneyClient(player)
	print(inv.Money)
end

function InventoryServer.RemoveMoney(player: Player, amount: number)
	local inv = InventoryServer.AllInventories[player]
	if not inv then return end
	inv.Money = math.max((inv.Money or 0) - amount, 0)
	InventoryServer.UpdateMoneyClient(player)
end



--Registering new Items
function InventoryServer.RegisterItem(player: Player, tool: Tool)
	if tool.ClassName ~= "Tool" then return end
	if InventoryServer.Respawning[player] then return end
	
	--Getting Inventory Data
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	
	--Checking if already in inventory
	for i, stackData: Types.StackData in inv.Inventory do
		if table.find(stackData.Items, tool) then
			return
		end
	end
	
	--Looping all stacks
	local foundStack: Types.StackData = nil
	for i, stackData: Types.Stackdata in inv.Inventory do
		if stackData.Name == tool.Name and #stackData.Items < InventoryServer.MaxStackData[stackData.ItemType] then
			table.insert(stackData.Items, tool)
			foundStack = stackData
			break			
		end
	end
	--if no stack was found
	if not foundStack then
		if #inv.Inventory < InventoryServer.MaxStacks then
			--Create new stack
			local stack: Types.StackData = {
				Name = tool.Name;
				Description = tool.ToolTip;
				Image = tool.TextureId;
				ItemType = tool:GetAttribute("ItemType");
				IsDroppable = tool:GetAttribute("IsDroppable");
				Items = {tool};
				StackId = inv.NextStackId;
				
			}
			inv.NextStackId += 1
			table.insert(inv.Inventory, stack)
			
			--Equipping to first open slot
			if stack.ItemType == "Armor" then
				local armorType =stack.Items[1]:GetAttribute("ArmorType")
				if inv.Armor[armorType] == nil then
					InventoryServer.EquipArmor(player, stack.StackId)
				end
			else 
				for slotNum: number = 1,8 do
					if inv.Hotbar["Slot".. slotNum] == nil then
						InventoryServer.EquipToHotbar(player, slotNum, stack.StackId)
						break
					end
				end
			end
		else
			warn("Items were added to Inventory, even though it's full, they wont be displayed in gui")
		end
	end
	
	--Updating Client
	Signal.FireClient(player,"InventoryClient:Update", inv)
	
end

--Unregistering items
function InventoryServer.UnregisterItem(player: Player, tool: Tool)
	if tool.ClassName ~= "Tool" then return end
	if tool.Parent == player.Backpack or (player.Character ~= nil and tool.parent == player.Character) then return end
	if InventoryServer.Respawning[player] then return end
	
	--Getting Inventory
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	
	--Finding tool in inventory
	for i, stackData: Types.StackData in inv.Inventory do
		local found: number = table.find(stackData.Items, tool)
		if found then
			
			--Removing Tool
			table.remove(stackData.Items, found)
			
			--Removing stack if it's empty
			if #stackData.Items == 0 then
				local stackFound: number = table.find(inv.Inventory, stackData)
				if stackFound then
					table.remove(inv.Inventory, stackFound)
					InventoryServer.UnequipFromHotbar(player, stackData.StackId)
					InventoryServer.UnequipArmor(player, stackData.StackId)
				end
			end
		end
	end

	--Updating Client
	Signal.FireClient(player, "InventoryClient:Update", inv)
end

function InventoryServer.RemovePlacedItem(player: Player, itemName: string)
	local inv = InventoryServer.AllInventories[player]
	if not inv then return false end

	-- Find the stack with this name in the hotbar (or entire inventory if allowed)
	for i, stackData in ipairs(inv.Inventory) do
		if stackData.Name == itemName and #stackData.Items > 0 then
			-- Remove the first Tool from the stack
			local tool = table.remove(stackData.Items, 1)
			if tool then
				if tool.Parent == player.Character or tool.Parent == player.Backpack then
					tool:Destroy()
				end
				-- If stack is now empty, remove it
				if #stackData.Items == 0 then
					table.remove(inv.Inventory, i)
					InventoryServer.UnequipFromHotbar(player, stackData.StackId)
					InventoryServer.UnequipArmor(player, stackData.StackId)
				end
				-- Update client
				Signal.FireClient(player, "InventoryClient:Update", inv)
				return true
			end
		end
	end
	return false
end

--Equipping item to hotbar
function InventoryServer.EquipToHotbar(player: Player, equipTo: number, stackId: number)
	if InventoryServer.Respawning[player] then return end
	--Getting inventory
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	---Removing is it exists already
	InventoryServer.UnequipFromHotbar(player, stackId)
	
	--Validating Stack
	local isValid: boolean = false
	for i, stackData: Types.StackData in inv.Inventory do
		if stackData.StackId == stackId and stackData.ItemType ~= "Armor" then
			isValid = true
			
		end
	end
	if isValid == false then return end
	
	--equipping
	inv.Hotbar["Slot" .. equipTo] = stackId
	

	--Updating Client
	Signal.FireClient(player, "InventoryClient:Update", inv)
end

--unequipping item from hotbar
function InventoryServer.UnequipFromHotbar(player: Player, stackId: number)
	if InventoryServer.Respawning[player] then return end
--getting inv
	local inv = InventoryServer.AllInventories[player]
	
	--removing if exists already
	for slotKey: string, equippedId: number in inv.Hotbar do
		if equippedId == stackId then
			inv.Hotbar[slotKey] = nil
		end
	end

	--Updating Client
	Signal.FireClient(player, "InventoryClient:Update", inv)
end

--Equipping Armor
function InventoryServer.EquipArmor(player: Player, stackId: number): boolean?
	if InventoryServer.Respawning[player] then return end
	
	--Finding Stack
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	local stackData: Types.StackData = InventoryServer.FindStackDataFromId(player, stackId)
	if not stackData then return end
	if stackData.ItemType ~= "Armor" then return end
	
	--Character Variables
	local char = player.Character; if not char then return end
	
	--Equipping to armor data
	local armorType = stackData.Items[1]:GetAttribute("ArmorType"); if not armorType then return end
	inv.Armor[armorType] = stackId
	
	--Clearing armor
	InventoryServer.ClearArmor(player, armorType)
	
	--Equipping armor model
	local tag = ARMOR_TAG:format(player.UserId, armorType)
	local armorModel: Model = SS.ArmorModels:FindFirstChild(stackData.Name)
	
	if armorModel then
		
		--Cloning
		local clone = armorModel:Clone(); clone:AddTag(tag)
		clone.Parent = char
		
		--Welding
		for i, partModel: Model in clone:GetChildren() do
			local bodyPart: BasePart = char:FindFirstChild(partModel.Name)
			if bodyPart then
				local weld = Instance.new("Weld")
				weld.Parent = bodyPart
				weld.Part0 = bodyPart
				weld.Part1 = partModel.PrimaryPart
			else
				warn(`The armor model {clone.name} has body part model {partModel.Name}, but no body part was found by that name. `)
			end
			
		end
	end
	--Updating
	Signal.FireClient(player, "InventoryClient:Update", inv)
	InventoryServer.UpdateArmorStats(player)
	return true --successful equip
	
end

--Unequipping Armor
function InventoryServer.UnequipArmor(player: Player, stackId: number)
	if InventoryServer.Respawning[player] then return end
	
	--unequipping
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	for armorType, otherStackId in inv.Armor do
		if stackId == otherStackId then
			inv.Armor[armorType] = nil
			InventoryServer.ClearArmor(player,armorType)
			
		end
	end
	--Updating
	Signal.FireClient(player, "InventoryClient:Update", inv)
	InventoryServer.UpdateArmorStats(player)
end

--Updating armor stats
function InventoryServer.UpdateArmorStats(player: Player)
	--looping through armor and summing buffs
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	local totalHealthBuff: number = 0
	
	for armorType: string, stackId: number in inv.Armor do
		--finding armor stack
		if stackId == nil then continue end
		local stackData: Types.StackData = InventoryServer.FindStackDataFromId(player, stackId)
		if not stackData then continue end
		
		--checking or addding buff
		local healthBuff = stackData.Items[1]:GetAttribute("HealthBuff")
		if healthBuff ~= nil then
			totalHealthBuff += healthBuff
		end
	end
	
	--Character variables
	local char = player.Character; if not char then return end
	local hum = char:FindFirstChild("Humanoid"); if not hum then return end
	
	--Adding buffs
	local currentHealthPerc = hum.Health / hum.MaxHealth
	hum.MaxHealth = 100 + totalHealthBuff
	hum.Health = hum.MaxHealth * currentHealthPerc
end

--Clearing armor models
function InventoryServer.ClearArmor(player: Player, armorType: "Head" | "Chest" | "Feet")
	local tag = ARMOR_TAG:format(player.UserId, armorType)
	for i, obj in CS:GetTagged(tag) do
		obj:Destroy()
	end
end

--Getting inventory data
function InventoryServer.GetInventoryData(player: Player)
	--Waiting for inv
	
	while not InventoryServer.AllInventories[player] do task.wait() end
	return InventoryServer.AllInventories[player]
end

--Finding stack data from ID
function InventoryServer.FindStackDataFromId(player: Player, stackId: number)
	if stackId == nil then return end
	for i, stackData: Types.StackData in InventoryServer.AllInventories[player].Inventory do
		if stackData.StackId == stackId then
			return stackData
		end
	end
end

--dropping items
function InventoryServer.DropItem(player: Player, stackId: number)
	if InventoryServer.Respawning[player] then return end
	
	--finding stack data
	local stackData: Types.StackData = InventoryServer.FindStackDataFromId(player, stackId)
	if not stackData then return end
	if not stackData.IsDroppable then return false end
	
	--Character Variables
	local char: Model = player.Character; if not char then return end
	local root: BasePart = char:FindFirstChild("HumanoidRootPart"); if not root then return end
	
	--Dropping first item in list
	local toolToDrop = stackData.Items[1]
	
	toolToDrop:PivotTo(root.CFrame * CFrame.new(0,0,-3)) --3 studs in front of player
	toolToDrop.Parent = workspace
	return true
end

--Holding item
function InventoryServer.HoldItem(player: Player, slotNum: number)
	if InventoryServer.Respawning[player] then return end
	--Finding Stack
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	local stackData: Types.StackData? = nil
	for slotKey: string, stackId: number in inv.Hotbar do
		if slotKey == "Slot" .. slotNum then
			stackData = InventoryServer.FindStackDataFromId(player, stackId)
			break
		end
	end
	
	--Equipping
	InventoryServer.UnholdItems(player)
	if stackData ~= nil then 
		
		--Equipping first tool in stack
		local tool: Tool = stackData.Items[1]
		if not player.Character then return end
		tool.Parent = player.Character

		--Updating Client
		Signal.FireClient(player, "InventoryClient:Update", inv)
		
	end
end

-- Unholding items
function InventoryServer.UnholdItems(player: Players)
	if InventoryServer.Respawning[player] then return end
	---unequip
	local char: Model = player.Character; if not char then return end 
	local hum: Humanoid = char:FindFirstChild("Humanoid"); if not hum then return end
	hum:UnequipTools()
	
	--Update client
	Signal.FireClient(player, "InventoryClient:Update", InventoryServer.AllInventories[player])
end
--Saving data
function InventoryServer.SaveData(player: Player)
	if InventoryServer.HasLoaded[player] ~= true then return end
	print("[Inventory] Saving the data of " .. player.Name .. "-" .. player.UserId)
	---creating save string
	local inv: Types.Inventory = InventoryServer.AllInventories[player]
	local modifiedInv = {
		Inventory = {};
		Hotbar = inv.Hotbar;
		Armor = inv.Armor;
		NextStackId = inv.NextStackId;
		Money = inv.Money or 0;
	}
	
	for i, stackData in inv.Inventory do
		if stackData.Items and #stackData.Items > 0 then
			table.insert(modifiedInv.Inventory, {
				Name = stackData.Name,
				Count = #stackData.Items,
				StackId = stackData.StackId
			})
		end
	end
	print(modifiedInv)
	
	local saveString = HS:JSONEncode(modifiedInv)
	
	--saving
	local success, result = false, nil
	local timeoutTime = 5
	local startTime = os.clock()
	
	while not success do 
		--timeout checking
		if os.clock() - startTime > timeoutTime then
			print("[Inventory] Unable to save the data of " .. player.Name .. "-" .. player.UserId)
			return
		end
		
		--attempting save
		task.wait()
		success, result = pcall(function()
			IDS:SetAsync(SAVE_KEY:format(player.UserId), saveString)
		end)
		if not success then
			task.wait(1)
		end
	end
	print("[Inventory] Finished saving the data of " .. player.Name .. "-" .. player.UserId)
end

function InventoryServer.LoadData(player: Player)
	print("[Inventory] Loading the data of " .. player.Name .. "-" .. player.UserId)
	
	
	--getting current data
	local saveString = IDS:GetAsync(SAVE_KEY:format(player.UserId))	
	if saveString == nil then
		print("Not data found for player " .. player.Name .. " - " .. player.UserId)
		InventoryServer.HasLoaded[player] = true
	end
	local savedData = HS:JSONDecode(saveString)
	print(savedData)
	
	--loading inventory
	local inv: Types.Inventory = {
		Inventory = {};
		Hotbar = savedData.Hotbar;
		Armor = savedData.Armor;
		NextStackId = savedData.NextStackId;
		Money = savedData.Money or 0;
	}
	local char: Model = player.Character or player.CharacterAdded:Wait()
	local backpack: Backpack = player:WaitForChild("Backpack")
	
	for i, savedStack in savedData.Inventory do
		-- Only add stacks with Count > 0
		if savedStack.Count and savedStack.Count > 0 then
			local sample: Tool = SS.AllItems:FindFirstChild(savedStack.Name)
			if not sample then
				warn("No item sample was found in ServerStorage.AllItems for " .. savedStack.Name)
				continue
			end
			--creating stack
			local stack: Types.StackData = {
				Name = savedStack.Name;
				Description = sample.ToolTip;
				Image = sample.TextureId;
				ItemType = sample:GetAttribute("ItemType");
				IsDroppable = sample:GetAttribute("IsDroppable");
				Items = {};
				StackId = savedStack.StackId;
			}
			--cloning items
			for i = 1, savedStack.Count do
				local clone = sample:Clone()
				clone.Parent = backpack
				table.insert(stack.Items, clone)
			end
			--inserting stack
			table.insert(inv.Inventory, stack)
		else
			print("[InventoryLoader] Skipped loading bugged/empty stack: ", savedStack.Name, savedStack.StackId)
		end
	end
	InventoryServer.AllInventories[player] = inv
	InventoryServer.HasLoaded[player] = true
	InventoryServer.Janitors[player]:GiveChore(function()
	InventoryServer.HasLoaded[player] = nil
	end)
	
	--Adding armor Models
	for armorType, stackId in inv.Armor do
		InventoryServer.EquipArmor(player, stackId)
	end
	
	--Updating client ui
	Signal.FireServer(player, "InventoryClient:Update", InventoryServer.AllInventories[player])
	
	print("[Inventory] Finished loading the data of " .. player.Name .. "-" .. player.UserId)
end


--returning
return InventoryServer