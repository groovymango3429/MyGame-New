-- Secure Server Framework for Gun System
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local WeaponModules = {
	["TROY DEFENSE AR"] = require(ReplicatedStorage.Modules["TROY DEFENSE AR"]),
	["G19 ROLAND SPECIAL"] = require(ReplicatedStorage.Modules["G19 ROLAND SPECIAL"]),
}

local PlayerWeaponState = {}

local function getEquippedWeaponName(player)
	local char = player.Character
	if not char then return nil end
	for _, tool in ipairs(char:GetChildren()) do
		if tool:IsA("Tool") and WeaponModules[tool.Name] then
			return tool.Name
		end
	end
	return nil
end

local function getWeaponState(player, weaponName)
	if not PlayerWeaponState[player] then PlayerWeaponState[player] = {} end
	local state = PlayerWeaponState[player][weaponName]
	if not state then
		local config = WeaponModules[weaponName]
		state = {
			ammo = config and config.ammo or 0,
			lastFire = 0,
			reloading = false,
		}
		PlayerWeaponState[player][weaponName] = state
	end
	return state
end

Players.PlayerAdded:Connect(function(player)
	PlayerWeaponState[player] = {}
	player.CharacterAdded:Connect(function()
		PlayerWeaponState[player] = {}
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerWeaponState[player] = nil
end)

ReplicatedStorage.Events.Shoot.OnServerEvent:Connect(function(player, muzzlePos, aimPos)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local weaponName = getEquippedWeaponName(player)
	if not weaponName then return end
	local config = WeaponModules[weaponName]
	if not config then return end

	local state = getWeaponState(player, weaponName)
	if state.reloading then return end

	local now = tick()
	if now - state.lastFire < config.fireRate then return end
	if state.ammo <= 0 then return end

	if typeof(muzzlePos) ~= "Vector3" then return end
	if (muzzlePos - root.Position).Magnitude > 10 then return end
	if typeof(aimPos) ~= "Vector3" then return end
	if (aimPos - muzzlePos).Magnitude > 1000 then return end

	local direction = (aimPos - muzzlePos).Unit * 500
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {char}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	local result = workspace:Raycast(muzzlePos, direction, rayParams)

	if result and result.Instance and result.Instance.Parent then
		local humanoid = result.Instance.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid ~= char:FindFirstChildOfClass("Humanoid") then
			local isHeadshot = (result.Instance.Name == "Head")
			humanoid:TakeDamage(isHeadshot and config.headshot or config.damage)
		end
	end

	-- Play gun sound for other players (but NOT the shooter)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			ReplicatedStorage.Events.PlayGunSound:FireClient(
				otherPlayer,
				weaponName,
				root.Position
			)
		end
	end

	state.ammo = state.ammo - 1
	state.lastFire = now
end)

ReplicatedStorage.Events.Reload.OnServerEvent:Connect(function(player)
	local weaponName = getEquippedWeaponName(player)
	if not weaponName then return end
	local config = WeaponModules[weaponName]
	if not config then return end

	local state = getWeaponState(player, weaponName)
	if state.reloading then return end
	state.reloading = true

	task.spawn(function()
		task.wait(config.reloadTime)
		state.ammo = config.maxAmmo
		state.reloading = false
	end)
end)

ReplicatedStorage.Events.QueryAmmo.OnServerInvoke = function(player)
	local weaponName = getEquippedWeaponName(player)
	if not weaponName then return 0, 0 end
	local config = WeaponModules[weaponName]
	local state = getWeaponState(player, weaponName)
	return state.ammo, config.maxAmmo
end

ReplicatedStorage.Events.CanShoot.OnServerInvoke = function(player)
	local weaponName = getEquippedWeaponName(player)
	if not weaponName then return false end
	local config = WeaponModules[weaponName]
	if not config then return false end
	local state = getWeaponState(player, weaponName)
	if state.reloading then return false end
	local now = tick()
	if now - state.lastFire < config.fireRate then return false end
	if state.ammo <= 0 then return false end
	return true
end