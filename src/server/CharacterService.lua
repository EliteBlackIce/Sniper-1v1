--[[
	CharacterService.lua  (ServerScriptService.Server.CharacterService)

	Spawning and styling characters:
	  * Characters do NOT auto-respawn; the lobby and matches call Spawn().
	  * Every character is restyled to the flat look (single solid colour,
	    SmoothPlastic, no face/accessories) and gets a simple third-person
	    sniper so the enemy can see where your gun is.
	  * Freeze / unfreeze (used during countdowns and the pick screen).
	  * Temporary invisibility (Phantom Step).
	  * Falling into the void kills you.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GunModel = require(ReplicatedStorage.Shared.GunModel)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Util = require(ReplicatedStorage.Shared.Util)

local Palette = Config.Palette
local CharacterService = {}

local gunPowerUps = setmetatable({}, { __mode = "k" }) -- [character] = the power-ups its rifle was built with

-- The skin a player has equipped for "Rifle" / "Knife" (player attributes
-- RifleSkin / KnifeSkin, set by CrateService), or nil.
local function skinFor(character, weapon)
	local player = Players:GetPlayerFromCharacter(character)
	return player and Skins.Get(player:GetAttribute(weapon .. "Skin"))
end

-- Called with (player, character) when a character dies. Set by MatchService.
CharacterService.OnDied = nil

-- Bots (BotService) aren't in Players, so the void check tracks them here.
CharacterService.Bots = {} -- [bot] = true

----------------------------------------------------------------------------
-- Styling
----------------------------------------------------------------------------
-- An invisible part the weapon hangs off. Its Motor6D "WeaponGrip" joins it
-- to the right hand; BodyAnimator (on every client) animates that joint so
-- the weapon goes exactly where the animation says, and your real arms
-- reach for it.
local function weaponRoot(model, hand, cf)
	local root = Instance.new("Part")
	root.Name = "WeaponRoot"
	root.Size = Vector3.one * 0.1
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.CastShadow = false
	root.CFrame = cf
	root.Parent = model
	local grip = Instance.new("Motor6D")
	grip.Name = "WeaponGrip"
	grip.Part0 = hand
	grip.Part1 = root
	grip.C0 = hand.CFrame:Inverse() * cf -- (the rest pose, before any animation)
	grip.C1 = CFrame.new()
	grip.Parent = root
	return root
end

local function weldTo(root, part)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- The rifle in your hands (the same model and power-up attachments for
-- you and everyone else). The bolt hangs off its own joint so it can be
-- worked when you chamber a round.
-- powerUps ({ [id] = stacks }) adds each power-up's attachment + effects.
local function addWorldGun(character, powerUps)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand then
		return
	end
	local old = character:FindFirstChild("WorldGun")
	if old then
		old:Destroy()
	end
	local scale = Config.Body.GunScale
	local gun = Instance.new("Model")
	gun.Name = "WorldGun"
	local built = Skins.Build("Rifle", gun, skinFor(character, "Rifle"), { Scale = scale, CastShadow = true, PowerUps = powerUps })
	gunPowerUps[character] = powerUps

	local grip = hand.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	GunModel.Place(built, grip, scale)
	local root = weaponRoot(gun, hand, grip)
	root:SetAttribute("Profile", built.UsesMesh and "Mesh" or "Parts")

	-- the bolt: its own little root on a joint at the bolt pivot
	local pivot = grip * CFrame.new(built.Profile.BoltPivot.Position * scale)
	local boltRoot
	for name in pairs(built.Bolt) do
		if not boltRoot then
			boltRoot = Instance.new("Part")
			boltRoot.Name = "BoltRoot"
			boltRoot.Size = Vector3.one * 0.05
			boltRoot.Transparency = 1
			boltRoot.CanCollide = false
			boltRoot.CanQuery = false
			boltRoot.CanTouch = false
			boltRoot.Massless = true
			boltRoot.CFrame = pivot
			boltRoot.Parent = gun
			local joint = Instance.new("Motor6D")
			joint.Name = "BoltJoint"
			joint.Part0 = root
			joint.Part1 = boltRoot
			joint.C0 = root.CFrame:Inverse() * pivot
			joint.C1 = CFrame.new()
			joint.Parent = root
		end
		weldTo(boltRoot, built.Parts[name])
	end
	for name, part in pairs(built.Parts) do
		if not built.Bolt[name] then
			weldTo(root, part)
		end
	end

	-- tracers seen by other players start here (WorldGun.Barrel.Muzzle)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = built.Parts.Barrel
	muzzle.WorldCFrame = grip * CFrame.new(built.Profile.Muzzle.Position * scale)

	for _, part in ipairs(gun:GetDescendants()) do
		if part:IsA("BasePart") then
			part:SetAttribute("BaseTransparency", part.Transparency)
		end
	end
	gun.Parent = character
	CharacterService.ShowWeapon(character)
end

-- The knife (hidden until you switch to it), jointed to the hand the same
-- way so it can be flipped, tossed and caught.
local function addWorldKnife(character)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not Config.Knife.Enabled then
		return
	end
	local old = character:FindFirstChild("WorldKnife")
	if old then
		old:Destroy()
	end
	local knife = Instance.new("Model")
	knife.Name = "WorldKnife"
	local scale = Config.Knife.WorldScale
	local built = Skins.Build("Knife", knife, skinFor(character, "Knife"), { Scale = scale, CastShadow = true })
	local grip = hand.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	local origin = grip * CFrame.new(KnifeModel.Grip.Position * -scale)
	KnifeModel.Place(built, origin)
	local root = weaponRoot(knife, hand, origin) -- the knife's origin: the middle of the handle
	for _, part in pairs(built.Parts) do
		weldTo(root, part)
	end
	for _, part in ipairs(knife:GetDescendants()) do
		if part:IsA("BasePart") then
			part:SetAttribute("BaseTransparency", part.Transparency)
		end
	end
	knife.Parent = character
	CharacterService.ShowWeapon(character)
end

----------------------------------------------------------------------------
-- Hitboxes: three fixed boxes, the same size for every avatar. Bullets and
-- the knife only hit these (head = headshot, body, legs); the real body
-- parts, arms and accessories are ignored, so swinging arms and bulky
-- avatar meshes never eat or steal a shot.
----------------------------------------------------------------------------
local HITBOXES = {
	{ Name = "HitboxHead", Parts = { "Head" }, Size = Vector3.new(1.3, 1.3, 1.3), Offset = CFrame.new(0, 0, 0) },
	{ Name = "HitboxTorso", Parts = { "UpperTorso", "Torso" }, Size = Vector3.new(2.1, 2.3, 1.2), Offset = CFrame.new(0, -0.35, 0) },
	{ Name = "HitboxLegs", Parts = { "LowerTorso", "Torso" }, Size = Vector3.new(2.0, 2.3, 1.1), Offset = CFrame.new(0, -1.35, 0) },
}

local function addHitboxes(character)
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") and not item:FindFirstAncestor("WorldGun") and not item:FindFirstAncestor("WorldKnife") then
			item.CanQuery = false
		end
	end
	for _, info in ipairs(HITBOXES) do
		local attach
		for _, name in ipairs(info.Parts) do
			attach = attach or character:FindFirstChild(name)
		end
		if attach and not character:FindFirstChild(info.Name) then
			local box = Instance.new("Part")
			box.Name = info.Name
			box.Size = info.Size
			box.Transparency = 1
			box.CanCollide = false
			box.CanTouch = false
			box.CanQuery = true
			box.Massless = true
			box.CastShadow = false
			box.CFrame = attach.CFrame * info.Offset
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = attach
			weld.Part1 = box
			weld.Parent = box
			box.Parent = character
		end
	end
end

-- Shows the weapon in the "Weapon" attribute ("Sniper" or "Knife") and hides
-- the other one. Everyone sees what you're holding.
function CharacterService.ShowWeapon(character)
	if not character or character:GetAttribute("Invisible") then
		return -- MakeInvisible calls this again when it ends
	end
	local knifeOut = character:GetAttribute("Weapon") == "Knife"
	for name, shown in pairs({ WorldGun = not knifeOut, WorldKnife = knifeOut }) do
		local model = character:FindFirstChild(name)
		for _, item in ipairs(model and model:GetDescendants() or {}) do
			if item:IsA("BasePart") then
				item.Transparency = shown and (item:GetAttribute("BaseTransparency") or 0) or 1
			elseif item:IsA("ParticleEmitter") or item:IsA("PointLight") then
				item.Enabled = shown
			end
		end
	end
end

-- Switches what a player holds (the client asks; MeleeService/CombatService
-- check the "Weapon" attribute before allowing an attack).
function CharacterService.SetWeapon(player, weapon)
	local character = player.Character
	if not character or (weapon ~= "Sniper" and weapon ~= "Knife") then
		return
	end
	if weapon == "Knife" and not Config.Knife.Enabled then
		return
	end
	if character:GetAttribute("Weapon") == weapon then
		return
	end
	character:SetAttribute("Weapon", weapon)
	character:SetAttribute("WeaponSince", workspace:GetServerTimeNow())
	CharacterService.ShowWeapon(character)
end

-- AVATAR LOOK (Config.Player.UseAvatars): you play as your own Roblox
-- avatar. Hats and hair don't stop bullets (only the body counts), and a
-- coloured outline shows which side you're on in a match.
local function styleAvatar(character, color)
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") and item:FindFirstAncestorOfClass("Accessory") then
			item.CanQuery = false
			item.CanCollide = false
			item.CanTouch = false
			item.Massless = true
		end
	end
	local outline = character:FindFirstChild("TeamOutline") or Instance.new("Highlight")
	outline.Name = "TeamOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = color
	outline.OutlineTransparency = color == Palette.LobbyPlayer and 1 or 0.15
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = character
end

function CharacterService.Style(character, color, player)
	if Config.Player.UseAvatars and not Util.isBot(player) then
		styleAvatar(character, color)
		return
	end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("Accessory") or item:IsA("Clothing") or item:IsA("ShirtGraphic") or item:IsA("BodyColors") then
			item:Destroy()
		elseif item:IsA("Decal") and item.Parent and item.Parent.Name == "Head" then
			item:Destroy() -- remove the face for the flat look
		end
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part:FindFirstAncestor("WorldGun") then
			part.Material = Enum.Material.SmoothPlastic
			part.Color = color
		end
	end
	-- Head a touch lighter so it reads clearly as the headshot target
	local head = character:FindFirstChild("Head")
	if head then
		head.Color = color:Lerp(Color3.new(1, 1, 1), 0.25)
	end
end

----------------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------------

-- Everyone's avatar is loaded at the same standard body size (no tiny or
-- giant hitboxes), keeping their look: skin, clothes, hair, face.
local descriptions = {} -- [player] = HumanoidDescription
local function standardDescription(player)
	if descriptions[player] then
		return descriptions[player]:Clone()
	end
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(math.max(player.UserId, 1))
	end)
	if not ok or not description then
		return nil
	end
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	descriptions[player] = description
	return description:Clone()
end

function CharacterService.LoadCharacter(player)
	if Util.isBot(player) or not Config.Player.UseAvatars then
		player:LoadCharacter()
		return
	end
	local description = player.UserId > 0 and standardDescription(player) or nil
	local ok = description and pcall(function()
		player:LoadCharacterWithHumanoidDescription(description)
	end)
	if not ok then
		player:LoadCharacter() -- (Studio test players have no avatar to fetch)
	end
end

--[[
	Spawns (or respawns) `player` at `cframe`.
	options:
		Color      body colour
		MaxHealth  starting max health
		Frozen     anchor the character in place
		KillY      falling below this Y kills you
		PowerUps   { [id] = stacks } shown as attachments on the rifle
]]
function CharacterService.Spawn(player, cframe, options)
	options = options or {}
	if not player.Parent then
		return nil
	end

	CharacterService.LoadCharacter(player)
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root then
		return nil
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(("[CharacterService] %s spawned as %s; the game is built for R15 (Game Settings > Avatar > R15)"):format(
			tostring(player.Name),
			humanoid.RigType.Name
		))
	end
	CharacterService.Style(character, options.Color or Palette.LobbyPlayer, player)
	CharacterService.RefreshTag(player)
	character:SetAttribute("Weapon", "Sniper") -- every life starts with the rifle out
	addHitboxes(character)
	addWorldGun(character, options.PowerUps)
	addWorldKnife(character)

	humanoid.MaxHealth = options.MaxHealth or Config.Player.MaxHealth
	humanoid.Health = humanoid.MaxHealth
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Movement.JumpPower
	humanoid.BreakJointsOnDeath = true

	character:PivotTo(cframe)
	character:SetAttribute("KillY", options.KillY or -100)
	CharacterService.SetFrozen(player, options.Frozen == true)

	humanoid.Died:Connect(function()
		if CharacterService.OnDied then
			CharacterService.OnDied(player, character)
		end
	end)

	return character
end

-- Anchors/unanchors the root part. The client's movement script also reads
-- the "Frozen" attribute so it stops applying velocity.
function CharacterService.SetFrozen(player, frozen)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	character:SetAttribute("Frozen", frozen)
	root.Anchored = frozen
	if not frozen then
		root.AssemblyLinearVelocity = Vector3.zero
		pcall(function()
			-- bots are simulated by the server
			root:SetNetworkOwner(if Util.isBot(player) then nil else player)
		end)
	end
end

-- Rebuilds the rifle in a player's hands (e.g. after trying power-ups in the lab).
function CharacterService.RefreshWorldGun(player, powerUps)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		addWorldGun(character, powerUps)
	end
end

-- The tag over a player's head: their title (Locker) and a gold VIP badge.
function CharacterService.RefreshTag(player)
	if Util.isBot(player) then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("PlayerTag")
	if old then
		old:Destroy()
	end
	local title = Cosmetics.Worn(player, "Title")
	local vip = player:GetAttribute("VIP") == true
	if (not title or title.Text == "") and not vip then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "PlayerTag"
	tag.Size = UDim2.fromOffset(220, 26)
	tag.StudsOffset = Vector3.new(0, 2.4, 0)
	tag.MaxDistance = 80
	tag.Adornee = head
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = tag
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	local function chip(text, background, color)
		local label = Instance.new("TextLabel")
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 22)
		label.BackgroundColor3 = background
		label.BackgroundTransparency = 0.15
		label.Text = " " .. text .. " "
		label.TextSize = 15
		label.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Heavy)
		label.TextColor3 = color
		label.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = label
	end
	if vip then
		chip("VIP", Color3.fromRGB(255, 196, 60), Color3.fromRGB(30, 24, 10))
	end
	if title and title.Text ~= "" then
		chip(title.Text, Color3.fromRGB(18, 20, 26), title.Color or Color3.new(1, 1, 1))
	end
	tag.Parent = head
end

-- Rebuilds both weapons in a player's hands in their equipped skins.
function CharacterService.RefreshSkins(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		addWorldGun(character, gunPowerUps[character])
		addWorldKnife(character)
	end
end

-- Makes a character invisible to everyone for `duration` seconds.
function CharacterService.MakeInvisible(player, duration)
	local character = player.Character
	if not character or character:GetAttribute("Invisible") then
		return
	end
	character:SetAttribute("Invisible", true)
	local saved = {}
	local effects = {}
	for _, part in ipairs(character:GetDescendants()) do
		if (part:IsA("BasePart") and part.Name ~= "HumanoidRootPart") or part:IsA("Decal") then
			saved[part] = part.Transparency -- (decals: the face)
			part.Transparency = 1
		elseif (part:IsA("ParticleEmitter") or part:IsA("PointLight") or part:IsA("Highlight")) and part.Enabled then
			effects[part] = true -- rifle power-up effects would give you away
			part.Enabled = false
		end
	end
	task.delay(duration, function()
		for part, transparency in pairs(saved) do
			if part.Parent then
				part.Transparency = transparency
			end
		end
		for effect in pairs(effects) do
			if effect.Parent then
				effect.Enabled = true
			end
		end
		if character.Parent then
			character:SetAttribute("Invisible", false)
			CharacterService.ShowWeapon(character) -- in case you switched weapons while invisible
		end
	end)
end

function CharacterService.GetAliveHumanoid(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid, character
	end
	return nil
end

function CharacterService.Init()
	Players.CharacterAutoLoads = false
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player] = nil
	end)

	-- Void check: anything that falls below its KillY dies.
	RunService.Heartbeat:Connect(function()
		local everyone = Players:GetPlayers()
		for bot in pairs(CharacterService.Bots) do
			table.insert(everyone, bot)
		end
		for _, player in ipairs(everyone) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local killY = character and character:GetAttribute("KillY")
			if root and humanoid and killY and humanoid.Health > 0 and root.Position.Y < killY then
				humanoid.Health = 0
			end
		end
	end)
end

return CharacterService
