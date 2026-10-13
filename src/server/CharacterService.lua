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
local Util = require(ReplicatedStorage.Shared.Util)

local Palette = Config.Palette
local CharacterService = {}

-- Called with (player, character) when a character dies. Set by MatchService.
CharacterService.OnDied = nil

-- Bots (BotService) aren't in Players, so the void check tracks them here.
CharacterService.Bots = {} -- [bot] = true

----------------------------------------------------------------------------
-- Styling
----------------------------------------------------------------------------
local WORLD_GUN_SCALE = 0.8

-- The rifle other players see in your hands (same model as your viewmodel,
-- a bit smaller). The barrel points along the hand's -Y axis, so when the
-- client's aim pose raises the arm forward (CharacterPoser), the gun points
-- where you're looking.
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
	local gun = Instance.new("Model")
	gun.Name = "WorldGun"
	local built = GunModel.Build(gun, { Scale = WORLD_GUN_SCALE, CastShadow = true, PowerUps = powerUps })

	local grip = hand.CFrame * CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	GunModel.Place(built, grip, WORLD_GUN_SCALE)
	for _, part in pairs(built.Parts) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = part
		weld.Parent = part
	end

	-- tracers seen by other players start here (WorldGun.Barrel.Muzzle)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = built.Parts.Barrel
	muzzle.WorldCFrame = grip * CFrame.new(built.Profile.Muzzle.Position * WORLD_GUN_SCALE)

	gun.Parent = character
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

	CharacterService.Style(character, options.Color or Palette.LobbyPlayer, player)
	addWorldGun(character, options.PowerUps)

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
