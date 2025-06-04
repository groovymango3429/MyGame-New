local Settings = {

	canAim = true;
	aimSmooth = .15;

	fireAnim = "rbxassetid://104505248877433";
	emptyfireAnim = "rbxassetid://114869422003526";
	fireSound = game.ReplicatedStorage.Sounds.G19ROLANDSPECIAL.Fire;

	equipAnim = "rbxassetid://72238376120244";
	equipSound = game.ReplicatedStorage.Sounds.G19ROLANDSPECIAL.Fire;

	deequipAnim = "rbxassetid://132244562429566";
	deequipSound = game.ReplicatedStorage.Sounds.G19ROLANDSPECIAL.Fire;

	reloadAnim = "rbxassetid://114869422003526";
	reloadSound = game.ReplicatedStorage.Sounds.G19ROLANDSPECIAL.Fire;

	emptyReloadAnim = "rbxassetid://114869422003526";
	emptyReloadSound = game.ReplicatedStorage.Sounds.G19ROLANDSPECIAL.Fire;

	InspectAnim = "rbxassetid://114869422003526";
	InspectSound = game.ReplicatedStorage.Sounds.G19ROLANDSPECIAL.Fire;

	idleAnim = "rbxassetid://99472563516824";

	sprintCF = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90/5), math.rad(0), math.rad(0));

	canSemi = true;
	canFullAuto = false;

	ammo = 19;
	maxAmmo = 19;

	damage = 20;
	headshot = 50;

	debounce = .05;

	reloadTime = 3;

	fireMode = "Semi";

	fireRate = .25;
}

return Settings

--104505248877433

--	fireAnim = "rbxassetid://104505248877433";