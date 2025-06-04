-- You can place this in StarterPlayerScripts or merge with existing StorageClient.lua logic

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Modules.Signal)

local function connectPrompt(prompt)
	-- Prevent duplicate connections (optional, but good for safety)
	if prompt:GetAttribute("StoragePromptConnected") then return end
	prompt:SetAttribute("StoragePromptConnected", true)
	print("[DEBUG] Connecting ProximityPrompt:", prompt, "Parent:", prompt.Parent)
	prompt.Triggered:Connect(function()
		print("[DEBUG] ProximityPrompt triggered:", prompt)
		local model = prompt:FindFirstAncestorWhichIsA("Model")
		if not model then
			warn("[DEBUG] No ancestor model found for prompt:", prompt)
			return
		end
		print("[DEBUG] Found ancestor model:", model, "Name:", model.Name)
		local storageId = model:GetAttribute("StorageId")
		print("[DEBUG] StorageId on model:", storageId)
		if storageId then
			print("[DEBUG] Firing Storage:Open to server with StorageId:", storageId)
			Signal.FireServer("Storage:Open", storageId)
		else
			warn("[DEBUG] StorageId not found on model:", model, "Model attributes:", model:GetAttributes())
		end
	end)
end

local function scanPlot()
	print("[DEBUG] scanPlot() called for player:", player.Name)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then
		warn("[DEBUG] Plots folder not found in workspace")
		return
	end
	print("[DEBUG] Plots folder found")
	local plotName = player.Name .. "'s" .. " Plot"
	local plot = plotsFolder:WaitForChild(plotName)
	if not plot then
		warn("[DEBUG] Plot not found:", plotName, "in Plots folder:", plotsFolder:GetChildren())
		return
	end
	print("[DEBUG] Plot found:", plot)
	local objects = plot:WaitForChild("Objects")
	if not objects then
		warn("[DEBUG] Objects folder not found in plot:", plot)
		return
	end
	print("[DEBUG] Objects folder found in plot")

	-- Connect to all existing shelves/bins
	for _, shelf in ipairs(objects:GetChildren()) do
		print("[DEBUG] Checking shelf/object:", shelf, "Name:", shelf.Name)
		for _, descendant in ipairs(shelf:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") then
				print("[DEBUG] Found ProximityPrompt in shelf:", shelf, "Descendant:", descendant, "Parent:", descendant.Parent)
				connectPrompt(descendant)
			end
		end
	end

	-- Listen for any new shelves/bins added in the future
	objects.ChildAdded:Connect(function(newShelf)
		print("[DEBUG] New shelf/object added:", newShelf, "Name:", newShelf.Name)
		for _, descendant in ipairs(newShelf:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") then
				print("[DEBUG] Found ProximityPrompt in new shelf:", newShelf, "Descendant:", descendant, "Parent:", descendant.Parent)
				connectPrompt(descendant)
			end
		end
	end)
end

print("[DEBUG] Starting StorageClientProximity.lua for player:", player.Name)
scanPlot()
workspace.ChildAdded:Connect(function(child)
	print("[DEBUG] workspace.ChildAdded:", child, "Name:", child.Name)
	local expectedPlotName = player.Name .. "'s" .. " Plot"
	if child.Name == expectedPlotName then
		print("[DEBUG] New plot for player added:", child)
		child:WaitForChild("Objects")
		scanPlot()
	end
end)