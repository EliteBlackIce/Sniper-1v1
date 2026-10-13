--[[
	BotService.lua  (ServerScriptService.Server.BotService)

	A computer opponent for testing (and for playing solo). Admins start one
	with N in the lobby or the chat command "/bot [easy|normal|hard]" (see
	MatchService and Config.Admin / Config.Bot).

	HOW IT FITS IN
	  A bot is a plain table that looks enough like a Player for the match
	  code: UserId (negative), Name, DisplayName, Parent, Character,
	  SetAttribute / GetAttribute and LoadCharacter. Match, CharacterService
	  and CombatService treat it like anyone else; remotes skip it (see
	  Remotes.Get on the server). Use Util.isBot(player) to tell them apart.

	THE AI (runs on the server every frame)
	  * Sight: raycasts from its head to your head and chest.
	  * Fighting (it can see you): faces you, strafes left/right, hops now
	    and then, keeps a comfortable distance, and shoots once it has
	    tracked you for its reaction time. Aim error shrinks the longer it
	    keeps you in view, and grows when you move fast.
	  * Hunting (it can't): walks a PathfindingService path to where it
	    last saw you, or to you if it lost you a while ago.
	  * Shots go through CombatService.BotFire, the same validation and
	    damage code players use, so power-ups work the same for it.
	  * When it loses a round it picks the rarest card offered.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PowerUps = require(ReplicatedStorage.Shared.PowerUps)
local CharacterService = require(script.Parent.CharacterService)

local B = Config.Bot

local BotService = {}

local CombatService -- set in Init (avoids a circular require)
local bots = {} -- [bot] = brain state
local nextId = 0
local folder

-- Roblox's default R15 animations
local ANIMATIONS = {
	Idle = "rbxassetid://507766388",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
}

----------------------------------------------------------------------------
-- The fake player
----------------------------------------------------------------------------
local Bot = {}
Bot.__index = Bot

function Bot:SetAttribute(name, value)
	self.Attributes[name] = value
end

function Bot:GetAttribute(name)
	return self.Attributes[name]
end

-- Builds a fresh R15 body (CharacterService.Spawn styles and places it).
function Bot:LoadCharacter()
	if self.Character then
		self.Character:Destroy()
		self.Character = nil
	end
	local description = Instance.new("HumanoidDescription")
	local ok, character = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not ok or not character then
		warn("[Bot] couldn't build a character:", character)
		return
	end
	character.Name = "SniperBot" .. -self.UserId
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy() -- we animate it ourselves below
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = self.DisplayName
	humanoid.BreakJointsOnDeath = true
	humanoid.RequiresNeck = true
	character.Parent = folder
	self.Character = character

	local brain = bots[self]
	if brain then
		brain.Tracks = nil
		brain.Path = nil
		brain.SeenFor = 0
	end
end

-- Picks the rarest card offered (ties: random).
function Bot:ChooseCard(cards)
	local best, bestOrder = 1, -1
	for i, id in ipairs(cards) do
		local def = PowerUps.Get(id)
		local order = (def and Config.Rarity[def.Rarity] and Config.Rarity[def.Rarity].Order or 0) + math.random() * 0.5
		if order > bestOrder then
			best, bestOrder = i, order
		end
	end
	return best
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function randomInCone(dir, degrees)
	if degrees <= 0 then
		return dir
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local spin = math.random() * math.pi * 2
	local frame = CFrame.lookAt(Vector3.zero, dir)
	return (frame * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function sightParams(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { character }
	for _, name in ipairs({ "Effects", "Dummies" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

-- Returns the target part we can see (head first), or nil.
local function findVisiblePart(fromPos, character, targetCharacter)
	if targetCharacter:GetAttribute("Invisible") then
		return nil
	end
	local params = sightParams(character)
	for _, name in ipairs({ "Head", "UpperTorso", "LowerTorso" }) do
		local part = targetCharacter:FindFirstChild(name)
		if part then
			local result = workspace:Raycast(fromPos, part.Position - fromPos, params)
			if not result or result.Instance:IsDescendantOf(targetCharacter) then
				return part
			end
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- Animation (server-side Animator replicates to every client)
----------------------------------------------------------------------------
local function animate(brain, humanoid, root)
	if not brain.Tracks then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local tracks = {}
		for name, id in pairs(ANIMATIONS) do
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Looped = name ~= "Jump"
				track.Priority = Enum.AnimationPriority.Core
				tracks[name] = track
			end
		end
		brain.Tracks = tracks
		brain.Playing = nil
	end

	local state = humanoid:GetState()
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	local want
	if state == Enum.HumanoidStateType.Jumping then
		want = "Jump"
	elseif state == Enum.HumanoidStateType.Freefall then
		want = "Fall"
	elseif speed > 2 then
		want = "Run"
	else
		want = "Idle"
	end
	local track = brain.Tracks[want]
	if want ~= brain.Playing and track then
		local old = brain.Playing and brain.Tracks[brain.Playing]
		if old then
			old:Stop(0.15)
		end
		track:Play(0.15)
		brain.Playing = want
	end
	if want == "Run" and track then
		track:AdjustSpeed(math.clamp(speed / 20, 0.6, 1.8))
	end
end

----------------------------------------------------------------------------
-- Pathfinding
----------------------------------------------------------------------------
local function requestPath(brain, root, goal)
	if brain.Computing then
		return
	end
	brain.Computing = true
	brain.PathAt = os.clock()
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5.5,
			AgentCanJump = true,
			AgentCanClimb = true,
			WaypointSpacing = 6,
		})
		local ok = pcall(function()
			path:ComputeAsync(root.Position, goal)
		end)
		brain.Computing = false
		if ok and path.Status == Enum.PathStatus.Success then
			brain.Path = path:GetWaypoints()
			brain.PathIndex = 2
		else
			brain.Path = nil
		end
	end)
end

local function followPath(brain, humanoid, root)
	local path = brain.Path
	if not path then
		return false
	end
	local waypoint = path[brain.PathIndex]
	while waypoint and flat(waypoint.Position - root.Position).Magnitude < 3.5 do
		brain.PathIndex += 1
		waypoint = path[brain.PathIndex]
	end
	if not waypoint then
		brain.Path = nil
		return false
	end
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		humanoid.Jump = true
	end
	humanoid:MoveTo(waypoint.Position)
	return true
end

----------------------------------------------------------------------------
-- Brain
----------------------------------------------------------------------------
local function think(bot, brain, dt)
	local match = brain.Match
	local character = bot.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not humanoid or not root or not head or humanoid.Health <= 0 then
		return
	end
	animate(brain, humanoid, root)

	local difficulty = B.Difficulties[bot.Difficulty] or B.Difficulties.Normal
	humanoid.WalkSpeed = difficulty.WalkSpeed

	if not match:IsFighting() or character:GetAttribute("Frozen") then
		humanoid:Move(Vector3.zero)
		brain.SeenFor = 0
		brain.NextShot = os.clock() + 0.6 -- small grace period after the countdown
		return
	end

	local opponent = match:GetOpponent(bot)
	local _, targetCharacter = CharacterService.GetAliveHumanoid(opponent)
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		humanoid:Move(Vector3.zero)
		return
	end

	local now = os.clock()
	local seenPart = findVisiblePart(head.Position, character, targetCharacter)
	local toTarget = targetRoot.Position - root.Position
	local distance = toTarget.Magnitude

	if seenPart then
		brain.SeenFor += dt
		brain.LastSeen = targetRoot.Position
		brain.LastSeenAt = now
		brain.Path = nil

		-- face the target (the server owns the bot's physics)
		humanoid.AutoRotate = false
		local look = flat(toTarget)
		if look.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
		end
		local aimDir = (seenPart.Position - head.Position).Unit
		character:SetAttribute("AimPitch", math.clamp(math.asin(aimDir.Y), -1.4, 1.4))

		-- strafe, keep a sniping distance, hop now and then
		if now >= (brain.StrafeUntil or 0) then
			brain.StrafeSign = (brain.StrafeSign or 1) * (math.random() < 0.75 and -1 or 1)
			brain.StrafeUntil = now + B.StrafeTime[1] + math.random() * (B.StrafeTime[2] - B.StrafeTime[1])
			if math.random() < B.JumpChance then
				humanoid.Jump = true
			end
		end
		local forward = look.Magnitude > 0.1 and look.Unit or Vector3.zero
		local side = Vector3.new(-forward.Z, 0, forward.X) * brain.StrafeSign
		local approach = distance > 150 and 0.7 or (distance < 45 and -0.6 or 0)
		local move = side + forward * approach
		humanoid:Move(move.Magnitude > 0.01 and move.Unit or Vector3.zero)

		-- shoot
		if brain.SeenFor >= difficulty.ReactionTime and now >= (brain.NextShot or 0) then
			local aimHead = seenPart.Name == "Head" and math.random() < difficulty.HeadshotChance
			local aimPart = aimHead and seenPart
				or targetCharacter:FindFirstChild("UpperTorso")
				or seenPart
			-- settle: the longer it tracks you the steadier it gets; fast movers are harder
			local settle = math.clamp(1 - (brain.SeenFor - difficulty.ReactionTime) * 0.3, 0.45, 1)
			local moveError = targetRoot.AssemblyLinearVelocity.Magnitude * 0.025
			local errorDegrees = difficulty.AimError * settle + moveError
			local origin = head.Position
			local direction = randomInCone((aimPart.Position - origin).Unit, errorDegrees)
			CombatService.BotFire(bot, origin, direction)
			brain.NextShot = now
				+ CombatService.GetBoltTime(bot, match)
				+ difficulty.ExtraShotDelay * (0.7 + math.random() * 0.6)
		end
	else
		brain.SeenFor = math.max(0, brain.SeenFor - dt * 2)
		humanoid.AutoRotate = true
		character:SetAttribute("AimPitch", 0)

		-- hunt: where we last saw them, or straight to them after a while
		local goal = targetRoot.Position
		if brain.LastSeen and now - (brain.LastSeenAt or 0) < 5 then
			goal = brain.LastSeen
			if flat(goal - root.Position).Magnitude < 6 then
				brain.LastSeen = nil
			end
		end
		if not brain.Path or now - (brain.PathAt or 0) > B.PathInterval then
			requestPath(brain, root, goal)
		end
		if not followPath(brain, humanoid, root) then
			humanoid:MoveTo(goal)
		end
	end

	-- unstick: trying to move but not going anywhere -> jump and re-path
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	if humanoid.MoveDirection.Magnitude > 0.1 and speed < 3 then
		brain.StuckFor = (brain.StuckFor or 0) + dt
		if brain.StuckFor > 0.6 then
			humanoid.Jump = true
			brain.Path = nil
			brain.StuckFor = 0
			brain.StrafeSign = -(brain.StrafeSign or 1)
		end
	else
		brain.StuckFor = 0
	end
end

----------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------

-- Creates a bot "player". difficulty: "Easy" / "Normal" / "Hard".
function BotService.Create(difficulty)
	nextId += 1
	local name = "BOT (" .. string.upper(difficulty) .. ")"
	local bot = setmetatable({
		IsBot = true,
		UserId = -(1000 + nextId), -- Studio test players use -1, -2, ...
		Name = name,
		DisplayName = name,
		Parent = Players,
		Character = nil,
		CameraMode = nil,
		Difficulty = difficulty,
		Attributes = {},
	}, Bot)
	bots[bot] = { SeenFor = 0 }
	CharacterService.Bots[bot] = true
	return bot
end

-- Gives the bot its match (the AI only plays while that match is fighting).
function BotService.Attach(bot, match)
	local brain = bots[bot]
	if brain then
		brain.Match = match
	end
end

function BotService.Remove(bot)
	bots[bot] = nil
	CharacterService.Bots[bot] = nil
	bot.Parent = nil
	if bot.Character then
		bot.Character:Destroy()
		bot.Character = nil
	end
end

function BotService.Init(combatService)
	CombatService = combatService
	folder = Instance.new("Folder")
	folder.Name = "Bots" -- clients look bots' bodies up here
	folder.Parent = workspace

	RunService.Heartbeat:Connect(function(dt)
		for bot, brain in pairs(bots) do
			if brain.Match then
				local ok, err = pcall(think, bot, brain, dt)
				if not ok then
					warn("[Bot] error:", err)
				end
			end
		end
	end)
end

return BotService
