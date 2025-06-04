-- Place this Script in ServerScriptService

--[[
This script removes all default accessories (hair, hats, etc.), face decals, and then adds your own custom accessories and hats from ServerStorage.
HOW TO USE:
1. Place your custom Accessory(ies) and/or Hat(s) in ServerStorage, e.g. "MyHat" and "MyHair".
2. Adjust the clone/accessory names below to match your items in ServerStorage.
]]

local ServerStorage = game:GetService("ServerStorage")
local ac = ServerStorage:WaitForChild("Accessories")
local Players = game:GetService("Players")

-- List the names of your custom accessories/hats here
local CUSTOM_ACCESSORY_NAMES = {
	"Hair",  -- and your custom hair here
	-- Add more as needed
}

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Remove all Accessories (hats, hair, etc.)
		for _, accessory in ipairs(character:GetChildren()) do
			if accessory:IsA("Accessory") then
				accessory:Destroy()
			end
		end
		-- Add custom accessories from ServerStorage
		for _, accessoryName in ipairs(CUSTOM_ACCESSORY_NAMES) do
			local accessoryTemplate = ac:FindFirstChild(accessoryName)
			if accessoryTemplate and accessoryTemplate:IsA("Accessory") then
				local clone = accessoryTemplate:Clone()
				clone.Parent = character
			end
		end
	end)
end)