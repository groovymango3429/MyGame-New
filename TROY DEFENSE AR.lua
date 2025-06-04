local Settings = {

	canAim = true;
	aimSmooth = .1;

	fireAnim = "rbxassetid://98181014406813";
	emptyfireAnim = "rbxassetid://110477417157284";  ----Dont forget
	fireSound = game.ReplicatedStorage.Sounds.TROYDEFENSEAR.Fire;

	equipAnim = "rbxassetid://85432170503594";
	equipSound = game.ReplicatedStorage.Sounds.TROYDEFENSEAR.Fire;

	deequipAnim = "rbxassetid://140721346793339";
	deequipSound = game.ReplicatedStorage.Sounds.TROYDEFENSEAR.Fire;

	reloadAnim = "rbxassetid://133964102940845";
	reloadSound = game.ReplicatedStorage.Sounds.TROYDEFENSEAR.Fire;

	emptyReloadAnim = "rbxassetid://133964102940845";
	emptyReloadSound = game.ReplicatedStorage.Sounds.TROYDEFENSEAR.Fire;

	InspectAnim = "rbxassetid://132666339353500";
	InspectSound = game.ReplicatedStorage.Sounds.TROYDEFENSEAR.Fire;

	idleAnim = "rbxassetid://95611810622931";

	sprintCF = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90/5), math.rad(45/5), math.rad(75/5));

	canSemi = true;
	canFullAuto = true;

	ammo = 30;
	maxAmmo = 30;

	damage = 25;
	headshot = 100;

	debounce = .05;

	reloadTime = 3;

	fireMode = "Full Auto";

	fireRate = .08;
}

return Settings

--	fireAnim = "rbxassetid://98181014406813";
