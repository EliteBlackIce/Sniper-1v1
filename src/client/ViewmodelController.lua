--[[
	ViewmodelController.lua  (Client.ViewmodelController)

	First-person arms + sniper, built from flat-coloured parts and attached to
	the camera. Only YOU see it (it lives inside workspace.CurrentCamera).
	The rifle itself comes from Shared/GunModel (same model other players see).

	All animation is procedural (no animation assets needed):
		equip     gun swings up into view when you spawn
		sway      lags behind mouse movement
		bob       figure-8 walk/run bob, stronger when sprinting
		jump/land gun dips when you jump and slams down when you land hard
		dash      gun pulls back
		poses     lowered while sprinting, canted while sliding, tilted on wall runs
		recoil    kick back + up, muzzle flash
		bolt      right hand leaves the grip, works the bolt, comes back
		aim       slides to the centre when scoping, then hides behind the scope
		inspect   press V to admire the rifle
	power-ups your power-ups change how it moves (see "Power-up animation
	          styles" below): spin-cocking, heavy kicks, twirls, kill flourishes...

	Gun space: origin = right hand on the grip, +X right, +Y up, -Z forward.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GunModel = require(Shared.GunModel)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local Spring = require(script.Parent.Spring)
local Sfx = require(script.Parent.Sfx)
local Keybinds = require(script.Parent.Keybinds)
local Remotes = require(Shared.Remotes)

local Palette = Config.Palette
local VM = Config.Viewmodel
local player = Players.LocalPlayer

local Viewmodel = {}
local Controllers

local rad = math.rad

-- Where the grip sits in camera space when hip-firing / aiming down the scope.
local HIP_OFFSET = CFrame.new(0.62, -0.7, -1.1)
local SPRINT_POSE = CFrame.new(-0.1, -0.22, 0.15) * CFrame.Angles(rad(-16), rad(38), rad(14))
local EQUIP_POSE = CFrame.new(0.15, -1.2, 0.45) * CFrame.Angles(rad(-55), rad(25), rad(20))

-- Hands (gun space)
local RIGHT_GRIP = CFrame.new(0, -0.22, 0.18) * CFrame.Angles(rad(-18), 0, 0)
-- Arm joints (gun space). Shoulders sit behind the camera, out of view.
local RIGHT_ELBOW = Vector3.new(0.42, -0.62, 0.78)
local RIGHT_SHOULDER = Vector3.new(0.95, -1.1, 1.9)
local LEFT_ELBOW = Vector3.new(-0.42, -0.62, -0.55)
local LEFT_SHOULDER = Vector3.new(-1.0, -1.05, 0.95)

local model
local gun -- result of GunModel.Build
local parts = {} -- extra parts: hands, arms, flash
local visible = false

local swaySpring = Spring.new(140, 16) -- rotation (degrees)
local recoilSpring = Spring.new(220, 18) -- X = pitch, Y = push back, Z = roll
local moveSpring = Spring.new(150, 13) -- position offset from jumps / landings / dashes
local bobTime = 0
local sprintAlpha, slideAlpha, wallAlpha, airOffset = 0, 0, 0, 0
local wallRetract = 0 -- studs the gun is pulled back because a wall is in front of you
local retractParams = RaycastParams.new()
retractParams.FilterType = Enum.RaycastFilterType.Exclude
local boltStart, boltDuration = 0, 0
local boltSoundPlayed = true
local equipStart = -10
local inspectStart, inspecting = 0, false
local flashUntil = 0
local lastCharacter
local hadGun = false

----------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------
local function addPart(name, size, color, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	parts[name] = part
	return part
end

-- A string that changes whenever your power-ups change.
local function ownedSignature(owned)
	local list = {}
	for id, stacks in pairs(owned) do
		table.insert(list, id .. "=" .. stacks)
	end
	table.sort(list)
	return table.concat(list, ",")
end
local builtSignature = nil
local builtLevel = 0

local function setGunEffects(on)
	for _, part in pairs(gun.Parts) do
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("ParticleEmitter") or child:IsA("PointLight") then
				child.Enabled = on
			end
		end
	end
end

-- (Re)builds the rifle with an attachment for every power-up you own.
-- Returns true if you gained something (so we can show it off).
local function buildGun()
	local owned = ClientState.Owned or {}
	local signature = ownedSignature(owned) .. (GunModel.FindTemplate() and "|mesh" or "")
	if gun and signature == builtSignature then
		return false
	end
	if gun then
		for _, part in pairs(gun.Parts) do
			part:Destroy()
		end
	end
	builtSignature = signature
	gun = GunModel.Build(model, { Anchored = true, PowerUps = owned })
	for _, part in pairs(gun.Parts) do
		part.LocalTransparencyModifier = visible and 0 or 1
	end
	setGunEffects(visible)
	local level = GunModel.PowerLevel(owned)
	local gained = level > builtLevel
	builtLevel = level
	return gained
end

local function build()
	model = Instance.new("Model")
	model.Name = "Viewmodel"
	buildGun()

	-- Gloved hands
	for _, side in ipairs({ "Right", "Left" }) do
		addPart(side .. "Palm", Vector3.new(0.21, 0.27, 0.25), Palette.Glove)
		addPart(side .. "Fingers", Vector3.new(0.22, 0.23, 0.08), Palette.Glove)
		addPart(side .. "Thumb", Vector3.new(0.07, 0.07, 0.19), Palette.Glove)
		addPart(side .. "Cuff", Vector3.new(0.3, 0.3, 0.14), Palette.SleeveCuff)
		addPart(side .. "Forearm", Vector3.new(0.27, 0.27, 1), Palette.Sleeve)
		addPart(side .. "Elbow", Vector3.new(0.3, 0.3, 0.3), Palette.Sleeve, Enum.PartType.Ball)
		addPart(side .. "UpperArm", Vector3.new(0.32, 0.32, 1), Palette.Sleeve)
	end
	-- the left palm lies flat under the handguard
	parts.LeftPalm.Size = Vector3.new(0.27, 0.1, 0.33)
	parts.LeftFingers.Size = Vector3.new(0.06, 0.2, 0.28)
	parts.LeftThumb.Size = Vector3.new(0.06, 0.14, 0.2)

	-- Muzzle flash (a flat star)
	addPart("FlashCore", Vector3.new(0.4, 0.4, 0.4), Palette.MuzzleFlash, Enum.PartType.Ball)
	addPart("FlashA", Vector3.new(0.07, 0.9, 0.07), Palette.MuzzleFlash)
	addPart("FlashB", Vector3.new(0.9, 0.07, 0.07), Palette.MuzzleFlash)
	addPart("FlashLong", Vector3.new(0.12, 0.12, 0.7), Palette.MuzzleFlash)
	for _, name in ipairs({ "FlashCore", "FlashA", "FlashB", "FlashLong" }) do
		if Config.Effects.NeonEffects then
			parts[name].Material = Enum.Material.Neon -- glows with bloom
		end
	end
	-- a light that flashes with each shot (lights up your arms and the room)
	local light = Instance.new("PointLight")
	light.Name = "MuzzleLight"
	light.Color = Palette.MuzzleFlash
	light.Range = 14
	light.Brightness = 0
	light.Shadows = false
	light.Parent = parts.FlashCore

	model.Parent = workspace.CurrentCamera
end

----------------------------------------------------------------------------
-- Avatar arms (Config.Viewmodel.UseAvatarArms)
----------------------------------------------------------------------------
--[[
	Your first-person arms are a copy of your own avatar's arms: skin
	colour, shirt and all. The copy sits in a little model with a Humanoid
	(that's what makes the shirt show up), is scaled down to
	ArmThickness so it fits the rifle, and each part is stretched between
	the same shoulder / elbow / hand points the plain arms use. If your
	character has no R15 arms, the plain gloved arms are used instead.
]]
local ARM_NAMES = { "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" }
local BLOCK_PIECES = { "Palm", "Fingers", "Thumb", "Cuff", "Forearm", "Elbow", "UpperArm" }
local avatarArms -- { Model, Parts = {[name] = part}, Base = {[name] = original size} }

local function setBlockArms(shown)
	for _, side in ipairs({ "Right", "Left" }) do
		for _, piece in ipairs(BLOCK_PIECES) do
			local part = parts[side .. piece]
			if part then
				part.Transparency = shown and 0 or 1
			end
		end
	end
end

local function buildAvatarArms(character)
	if avatarArms then
		avatarArms.Model:Destroy()
		avatarArms = nil
	end
	if not Config.Viewmodel.UseAvatarArms or not character then
		setBlockArms(true)
		return
	end
	for _, name in ipairs(ARM_NAMES) do
		if not character:FindFirstChild(name) then
			setBlockArms(true)
			return
		end
	end
	local rig = Instance.new("Model")
	rig.Name = "AvatarArms"
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.EvaluateStateMachine = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = rig
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Shirt") or item:IsA("BodyColors") then
			item:Clone().Parent = rig
		end
	end
	local armParts, base = {}, {}
	for _, name in ipairs(ARM_NAMES) do
		local source = character[name]
		local ok, part = pcall(function()
			return source:Clone()
		end)
		if not ok or not part then
			rig:Destroy()
			setBlockArms(true)
			return
		end
		for _, child in ipairs(part:GetChildren()) do
			if not (child:IsA("SurfaceAppearance") or child:IsA("SpecialMesh") or child:IsA("Decal") or child:IsA("Texture")) then
				child:Destroy()
			end
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		part.Transparency = 0
		part.Parent = rig
		armParts[name] = part
		base[name] = source.Size
	end
	rig.Parent = model
	avatarArms = { Model = rig, Parts = armParts, Base = base }
	setBlockArms(false)
end

-- CFrame (gun space) for an avatar limb stretched from a to b, `thick` studs wide.
local function avatarLimb(name, a, b, thick)
	local part, base = avatarArms.Parts[name], avatarArms.Base[name]
	local length = math.max((b - a).Magnitude, 0.05)
	local k = thick / math.max(base.X, 0.01)
	local size = Vector3.new(base.X * k, length, base.Z * k)
	if (part.Size - size).Magnitude > 0.001 then
		part.Size = size
	end
	-- the limb's -Y runs from a (shoulder end) to b (hand end)
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(rad(90), 0, 0)
end

-- CFrame-free helper: scales an avatar hand to fit and returns its size.
local function avatarHandSize(name, width)
	local part, base = avatarArms.Parts[name], avatarArms.Base[name]
	local size = base * (width / math.max(base.X, 0.01))
	if (part.Size - size).Magnitude > 0.001 then
		part.Size = size
	end
	return size
end

-- CFrame for a limb part stretched between points a and b.
local function limbBetween(part, a, b)
	local length = math.max((b - a).Magnitude, 0.05)
	if math.abs(part.Size.Z - length) > 0.001 then
		part.Size = Vector3.new(part.Size.X, part.Size.Y, length)
	end
	return CFrame.lookAt((a + b) / 2, b)
end

----------------------------------------------------------------------------
-- Animation helpers
----------------------------------------------------------------------------
local function easeOutBack(t)
	local c1, c3 = 1.4, 2.4
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function seg(t, a, b)
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

-- Bolt cycle for progress t (0-1).
-- Returns: bolt pivot CFrame (gun space), right hand CFrame (gun space), gun roll.
local function boltPose(t)
	-- reach (0-.15) lift (.15-.3) pull (.3-.5) push (.5-.68) lower (.68-.8) return (.8-1)
	local lift = smoothstep(seg(t, 0.15, 0.3)) - smoothstep(seg(t, 0.68, 0.8))
	local pull = smoothstep(seg(t, 0.3, 0.5)) - smoothstep(seg(t, 0.5, 0.68))
	-- the bolt turns up around the bore line, then slides back and forward
	local profile = gun.Profile
	local pivot = profile.BoltPivot
		* CFrame.new(0, 0, pull * profile.BoltTravel)
		* CFrame.Angles(0, 0, rad(profile.BoltLift) * lift)
	local onKnob = pivot * profile.KnobHold * CFrame.Angles(0, 0, rad(-25))
	local reach = smoothstep(seg(t, 0, 0.15))
	local back = smoothstep(seg(t, 0.8, 1))
	local hand
	if t <= 0 or t >= 1 then
		hand = RIGHT_GRIP
	elseif t < 0.15 then
		hand = RIGHT_GRIP:Lerp(onKnob, reach)
	elseif t < 0.8 then
		hand = onKnob
	else
		hand = onKnob:Lerp(RIGHT_GRIP, back)
	end
	local roll = math.sin(math.clamp(t, 0, 1) * math.pi) * rad(16)
	return pivot, hand, roll
end

----------------------------------------------------------------------------
-- Power-up animation styles
----------------------------------------------------------------------------
--[[
	Your power-ups change how the rifle moves:
	  fire     Explosive Rounds / Glass Cannon: heavy kick that shoves the rifle back
	           Split Shot: double kick   Hair Trigger / Quickdraw: short snappy kick
	           Static Charge: the rifle buzzes with electricity for a moment
	  bolt     Hair Trigger / Quickdraw: spin-cock (the rifle spins round the barrel)
	           Bullet Time: smooth bolt with the rifle tilted up to admire it
	           Explosive Rounds / Split Shot: heavy pump, pulled back toward you
	           Ricochet / Pinball: the rifle bounces while you work the bolt
	  equip    Quickdraw: twirls into your hands   Ghost Round: phases in
	  idle     Ghost Round: floats   Momentum Rounds: leans with your speed
	           Static Charge: random twitches   Vampire: heartbeat pulse
	  kills    Ricochet / Pinball: barrel spin   Explosive Rounds: tilts up to blow
	           the smoke away   Vampire: pulls the rifle in   otherwise: a nod
	  inspect  with power-ups: turns the rifle both ways to show the attachments
]]
local function has(id)
	return (ClientState.Owned[id] or 0) > 0
end

local boltStyle, equipStyle = "Normal", "Normal"
local flourish, flourishStart = nil, -10
local jitterUntil, nextTwitch = 0, 0

local function chooseBoltStyle()
	if has("HairTrigger") or has("Quickdraw") then
		return "Spin"
	elseif has("BulletTime") then
		return "Admire"
	elseif has("ExplosiveRounds") or has("SplitShot") then
		return "Heavy"
	elseif has("Ricochet") or has("Pinball") then
		return "Bounce"
	end
	return "Normal"
end

-- Rotation around the barrel (gun space)
local function aroundBarrel(angle)
	local axis = CFrame.new(0, gun.Profile.BarrelY, 0)
	return axis * CFrame.Angles(0, 0, angle) * axis:Inverse()
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------
function Viewmodel.PlayFire(scoped)
	local kick = scoped and 0.5 or 1
	if has("ExplosiveRounds") or has("GlassCannon") then
		kick *= 1.5
		moveSpring:Impulse(Vector3.new(0, 0.8, scoped and 1.5 or 4.5))
	elseif has("HairTrigger") or has("Quickdraw") then
		kick *= 0.7
	end
	recoilSpring:Impulse(Vector3.new(22 * kick, 9 * kick, (math.random() - 0.5) * 8))
	if has("SplitShot") then
		task.delay(0.07, function()
			recoilSpring:Impulse(Vector3.new(12 * kick, 5 * kick, (math.random() - 0.5) * 12))
		end)
	end
	if has("StaticCharge") then
		jitterUntil = os.clock() + 0.3
	end
	flashUntil = os.clock() + 0.05
	inspecting = false
end

function Viewmodel.PlayBolt(duration)
	boltStart = os.clock()
	boltDuration = duration
	boltSoundPlayed = false
	boltStyle = chooseBoltStyle()
end

function Viewmodel.PlayEquip()
	equipStart = os.clock()
	inspecting = false
	equipStyle = has("Quickdraw") and "Twirl" or (has("GhostRound") and "Phase" or "Normal")
	Sfx.Play("Bolt", { Pitch = 1.3, Volume = 0.6 })
end

-- A little flourish after a kill (plays once the bolt is cycled).
function Viewmodel.PlayKill()
	if has("Ricochet") or has("Pinball") then
		flourish = "Spin"
	elseif has("ExplosiveRounds") then
		flourish = "Blow"
	elseif has("Vampire") then
		flourish = "Feed"
	else
		flourish = "Nod"
	end
	flourishStart = math.max(os.clock() + 0.1, boltStart + boltDuration)
end

function Viewmodel.GetMuzzlePosition()
	if gun and gun.Parts.Receiver then
		local grip = gun.Parts.Receiver.CFrame * gun.Offsets.Receiver:Inverse()
		return (grip * gun.Profile.Muzzle).Position
	end
	return workspace.CurrentCamera.CFrame.Position
end

function Viewmodel.GetLeftHandPosition()
	return parts.LeftPalm and parts.LeftPalm.Position or workspace.CurrentCamera.CFrame.Position
end

local function setVisible(v)
	if v == visible then
		return
	end
	visible = v
	for _, part in pairs(gun.Parts) do
		part.LocalTransparencyModifier = v and 0 or 1
	end
	setGunEffects(v)
	for name, part in pairs(parts) do
		if not name:find("Flash") then
			part.LocalTransparencyModifier = v and 0 or 1
		end
	end
	if avatarArms then
		for _, part in pairs(avatarArms.Parts) do
			part.LocalTransparencyModifier = v and 0 or 1
		end
	end
end

----------------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------------
local function update(dt)
	local camera = workspace.CurrentCamera
	if model.Parent ~= camera then
		model.Parent = camera
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local hasGun = ClientState.HasGun()
	local scopeAlpha = Controllers.Weapon.GetScopeAlpha()

	-- replay the equip animation on a new life / when the gun comes back
	if alive and hasGun and (character ~= lastCharacter or not hadGun) then
		Viewmodel.PlayEquip()
	end
	lastCharacter = character
	hadGun = alive and hasGun

	local shouldShow = alive and hasGun and Controllers.Camera.IsFirstPerson() and scopeAlpha < 0.92
	setVisible(shouldShow)
	if not shouldShow then
		for name, part in pairs(parts) do
			if name:find("Flash") then
				part.LocalTransparencyModifier = 1
			end
		end
		if not hasGun then
			return
		end
	end

	local movement = Controllers.Movement
	local mode = movement.GetMode()
	local speed = movement.GetSpeed()
	local grounded = movement.IsGrounded()
	local t = os.clock()

	-- SWAY from mouse movement
	local delta = UserInputService:GetMouseDelta()
	local swayScale = (1 - scopeAlpha * 0.85) * VM.SwayAmount
	swaySpring.Target = Vector3.new(
		math.clamp(-delta.Y * swayScale, -5, 5),
		math.clamp(-delta.X * swayScale, -5, 5),
		math.clamp(-delta.X * swayScale * 0.7, -4, 4)
	)
	local sway = swaySpring:Update(dt)

	-- BOB: figure-8 while running on the ground
	local running = grounded and speed > 2 and mode == "Ground"
	if running then
		bobTime += dt * (7 + speed * 0.2)
	end
	local bobAmount = running and math.clamp(speed / Config.Movement.RunSpeed, 0, 1.4) * (1 - scopeAlpha * 0.9) * VM.BobAmount or 0
	local idle = math.sin(t * 1.7) * 0.012
	local bobPos = Vector3.new(math.sin(bobTime) * 0.05, math.sin(bobTime * 2) * 0.035 + idle, 0) * bobAmount
	local bobRoll = math.sin(bobTime) * rad(2.2) * bobAmount

	-- POSES
	local boltT = boltDuration > 0 and (t - boltStart) / boltDuration or 1
	local cycling = boltT < 1
	local sprinting = movement.IsSprinting() and scopeAlpha < 0.1 and not cycling
	sprintAlpha = Util.lerp(sprintAlpha, sprinting and 1 or 0, Util.smooth(10, dt))
	slideAlpha = Util.lerp(slideAlpha, mode == "Slide" and 1 or 0, Util.smooth(12, dt))
	wallAlpha = Util.lerp(wallAlpha, movement.GetWallSide(), Util.smooth(10, dt))
	local vy = root and root.AssemblyLinearVelocity.Y or 0
	airOffset = Util.lerp(airOffset, grounded and 0 or math.clamp(-vy * 0.0025, -0.1, 0.1), Util.smooth(8, dt))

	-- EQUIP
	local equipTime = equipStyle == "Twirl" and VM.EquipTime * 1.4 or VM.EquipTime
	local equipT = math.clamp((t - equipStart) / equipTime, 0, 1)
	local equipPose = EQUIP_POSE:Lerp(CFrame.identity, easeOutBack(equipT))
	if equipStyle == "Twirl" then
		equipPose *= CFrame.Angles(0, (1 - smoothstep(equipT)) * math.pi * 2, 0)
	end
	local phaseFade = equipStyle == "Phase" and (1 - smoothstep(equipT)) or 0

	-- INSPECT (V)
	local inspectPose = CFrame.identity
	if inspecting then
		local it = (t - inspectStart) / 2.4
		if it >= 1 or scopeAlpha > 0.05 or cycling then
			inspecting = false
		else
			local w = math.sin(it * math.pi) ^ 0.7
			local wiggle = math.sin(it * math.pi * 3) * 0.08 * w
			if GunModel.PowerLevel(ClientState.Owned) > 0 then
				-- show off the attachments: turn it one way, then the other
				local turn = math.sin(it * math.pi * 2)
				inspectPose = CFrame.new(-0.4 * w, 0.22 * w, 0.35 * w)
					* CFrame.Angles(rad(14) * w + wiggle, rad(70) * turn * w, rad(-30) * w)
			else
				inspectPose = CFrame.new(-0.4 * w, 0.2 * w, 0.3 * w)
					* CFrame.Angles(rad(12) * w + wiggle, rad(55) * w, rad(-40) * w)
			end
		end
	end

	-- SPRINGS
	local recoil = recoilSpring:Update(dt)
	local kick = moveSpring:Update(dt)

	-- BOLT
	local boltPivot, rightHand, boltRoll = boltPose(math.clamp(boltT, 0, 1))

	-- POWER-UP STYLES (see the table above PlayFire)
	local styleOffset = CFrame.identity
	if cycling then
		local bt = math.clamp(boltT, 0, 1)
		local w = math.sin(bt * math.pi)
		if boltStyle == "Spin" then
			-- no hand on the bolt: the rifle spins once round the barrel instead
			rightHand, boltPivot, boltRoll = RIGHT_GRIP, gun.Profile.BoltPivot, 0
			styleOffset = aroundBarrel(-smoothstep(bt) * math.pi * 2)
		elseif boltStyle == "Admire" then
			styleOffset = CFrame.new(-0.1 * w, 0.14 * w, 0.12 * w) * CFrame.Angles(rad(16) * w, rad(-14) * w, 0)
		elseif boltStyle == "Heavy" then
			styleOffset = CFrame.new(0, -0.1 * w, 0.4 * w) * CFrame.Angles(rad(-10) * w, 0, 0)
		elseif boltStyle == "Bounce" then
			styleOffset = CFrame.new(0, math.abs(math.sin(bt * math.pi * 3)) * 0.14 * (1 - bt), 0)
		end
	end
	local calm = 1 - scopeAlpha
	local idlePose = CFrame.identity
	if has("GhostRound") then
		idlePose *= CFrame.new(math.sin(t * 0.9) * 0.03 * calm, math.sin(t * 1.3) * 0.035 * calm, 0)
			* CFrame.Angles(0, 0, math.sin(t * 0.7) * rad(2) * calm)
	end
	if has("MomentumRounds") then
		local lean = math.clamp((speed - 30) / 40, 0, 1) * calm
		idlePose *= CFrame.Angles(rad(-6) * lean, 0, rad(6) * lean)
	end
	if has("Vampire") then
		local beat = t % 1.1
		local pulse = math.exp(-((beat - 0.1) / 0.05) ^ 2) + 0.6 * math.exp(-((beat - 0.32) / 0.05) ^ 2)
		idlePose *= CFrame.new(0, 0, -0.035 * pulse * calm)
	end
	if has("StaticCharge") and t > nextTwitch then
		nextTwitch = t + 1.2 + math.random() * 2
		recoilSpring:Impulse(Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 14) * calm)
	end
	if t < jitterUntil then
		idlePose *= CFrame.Angles(rad((math.random() - 0.5) * 3), rad((math.random() - 0.5) * 3), 0)
	end
	-- kill flourish
	local flourishPose = CFrame.identity
	if flourish and t >= flourishStart then
		local ft = (t - flourishStart) / 0.75
		if ft >= 1 then
			flourish = nil
		else
			local w = math.sin(ft * math.pi) * calm
			if flourish == "Spin" then
				flourishPose = aroundBarrel(smoothstep(ft) * math.pi * 2 * calm)
			elseif flourish == "Blow" then
				flourishPose = CFrame.new(-0.25 * w, 0.28 * w, 0.3 * w) * CFrame.Angles(rad(38) * w, rad(25) * w, 0)
			elseif flourish == "Feed" then
				flourishPose = CFrame.new(-0.22 * w, -0.05 * w, 0.4 * w) * CFrame.Angles(0, rad(30) * w, rad(-22) * w)
			else
				flourishPose = CFrame.Angles(rad(-9) * w, 0, rad(4) * w)
			end
		end
	end
	if cycling and not boltSoundPlayed and boltT > 0.3 then
		boltSoundPlayed = true
		Sfx.Play("Bolt")
	end

	-- Combine everything into the grip CFrame (camera space -> world)
	-- WALL RETRACT: if a wall is closer than the end of the barrel, pull the
	-- rifle back and tilt it up so it never pokes through walls
	local exclude = { camera }
	if character then
		table.insert(exclude, character)
	end
	local effects = workspace:FindFirstChild("Effects")
	if effects then
		table.insert(exclude, effects)
	end
	retractParams.FilterDescendantsInstances = exclude
	local reach = 5.4
	local wallHit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * reach, retractParams)
	local wantRetract = wallHit and math.clamp(reach - wallHit.Distance, 0, 3.6) or 0
	wallRetract = Util.lerp(wallRetract, wantRetract * (1 - scopeAlpha), Util.smooth(14, dt))
	local retractAlpha = wallRetract / 3.6

	local eye = gun.Profile.ScopeEye
	local adsOffset = CFrame.new(-eye.X, -eye.Y, -0.55 - eye.Z)
	local base = HIP_OFFSET:Lerp(adsOffset, scopeAlpha)
		* CFrame.new(0.1 * retractAlpha, -0.15 * retractAlpha, wallRetract)
		* CFrame.Angles(rad(28) * retractAlpha, rad(12) * retractAlpha, rad(-10) * retractAlpha)
	local pose = CFrame.identity:Lerp(SPRINT_POSE, sprintAlpha)
		* CFrame.new(0, -0.14 * slideAlpha, 0.05 * slideAlpha)
		* CFrame.Angles(0, 0, rad(-18) * slideAlpha)
		* CFrame.Angles(0, 0, rad(9) * wallAlpha)
	local grip = camera.CFrame
		* base
		* equipPose
		* inspectPose
		* pose
		* CFrame.new(bobPos.X + kick.X, bobPos.Y + airOffset + kick.Y, kick.Z + recoil.Y * 0.02)
		* CFrame.Angles(rad(sway.X + recoil.X * 0.35), rad(sway.Y), rad(sway.Z + recoil.Z * 0.3) + bobRoll)
		* CFrame.Angles(0, 0, -boltRoll)
		* idlePose
		* flourishPose
		* styleOffset

	local list, cframes = {}, {}
	local function put(part, cf)
		table.insert(list, part)
		table.insert(cframes, cf)
	end

	-- Gun (bolt parts follow the animated bolt pivot; power-up parts animate)
	local boltWorld = grip * boltPivot
	local fast = math.clamp((speed - 30) / 40, 0, 1)
	for name, part in pairs(gun.Parts) do
		local offset = gun.Offsets[name]
		local anim = gun.Anims[name]
		if anim then
			local base = gun.BaseTransparency[name]
			local fade = 0
			if anim == "Spin" then
				offset = aroundBarrel(t * 3) * offset
			elseif anim == "Tick" then
				offset = offset * CFrame.Angles(-t * 2, 0, 0)
			elseif anim == "Turn" then
				offset = CFrame.new(offset.Position) * CFrame.Angles(0, t * 2.5, 0) * offset.Rotation
			elseif anim == "Pulse" then
				fade = 0.3 * (1 + math.sin(t * 4)) / 2
			elseif anim == "Ghost" then
				fade = 0.5 * (1 + math.sin(t * 6 + offset.Position.Z * 8)) / 2
			elseif anim == "Flicker" then
				fade = math.random() < 0.25 and 0.85 or 0
			elseif anim == "Speed" then
				fade = 0.85 * (1 - fast)
			end
			if shouldShow then
				part.LocalTransparencyModifier = math.min(1, math.max(fade / math.max(1 - base, 0.01), phaseFade))
			end
		elseif shouldShow and (phaseFade > 0 or part.LocalTransparencyModifier ~= 0) then
			part.LocalTransparencyModifier = phaseFade -- Ghost Round equip: phase in
		end
		put(part, (gun.Bolt[name] and boltWorld or grip) * offset)
	end
	-- glow lines breathe, and flare white for a moment when you fire
	local flare = math.clamp((flashUntil - t) / 0.05, 0, 1)
	local glow = gun.GlowColor:Lerp(Color3.new(1, 1, 1), 0.12 * (1 + math.sin(t * 2.4)) / 2 + flare * 0.6)
	for _, part in ipairs(gun.Glow) do
		part.Color = glow
	end

	-- Right hand + arm
	local rh = grip * rightHand
	put(parts.RightPalm, rh)
	put(parts.RightFingers, rh * CFrame.new(0, -0.02, -0.15))
	put(parts.RightThumb, rh * CFrame.new(-0.12, 0.07, -0.06))
	local rWrist = (rightHand * CFrame.new(0, -0.04, 0.17)).Position
	put(parts.RightCuff, grip * limbBetween(parts.RightCuff, rWrist, rWrist + (RIGHT_ELBOW - rWrist).Unit * 0.14))
	put(parts.RightForearm, grip * limbBetween(parts.RightForearm, RIGHT_ELBOW, rWrist))
	put(parts.RightElbow, grip * CFrame.new(RIGHT_ELBOW))
	put(parts.RightUpperArm, grip * limbBetween(parts.RightUpperArm, RIGHT_SHOULDER, RIGHT_ELBOW))

	-- Left hand + arm (holds the handguard)
	local LEFT_HOLD = gun.Profile.LeftHold
	local lh = grip * LEFT_HOLD
	put(parts.LeftPalm, lh)
	put(parts.LeftFingers, lh * CFrame.new(0.155, 0.09, 0))
	put(parts.LeftThumb, lh * CFrame.new(-0.155, 0.07, 0.02))
	local lWrist = (LEFT_HOLD * CFrame.new(-0.05, -0.06, 0.2)).Position
	put(parts.LeftCuff, grip * limbBetween(parts.LeftCuff, lWrist, lWrist + (LEFT_ELBOW - lWrist).Unit * 0.14))
	put(parts.LeftForearm, grip * limbBetween(parts.LeftForearm, LEFT_ELBOW, lWrist))
	put(parts.LeftElbow, grip * CFrame.new(LEFT_ELBOW))
	put(parts.LeftUpperArm, grip * limbBetween(parts.LeftUpperArm, LEFT_SHOULDER, LEFT_ELBOW))

	-- Avatar arms (replace the plain arms above when available)
	if avatarArms then
		local thick = Config.Viewmodel.ArmThickness or 0.3
		local hide = visible and 0 or 1
		for _, part in pairs(avatarArms.Parts) do
			part.LocalTransparencyModifier = hide
		end
		-- right: hand on the grip (or the bolt), wrist at the top of the hand
		local rSize = avatarHandSize("RightHand", thick * 0.95)
		local rHandCF = rightHand * CFrame.new(0, -0.02, 0)
		local rWristA = (rHandCF * CFrame.new(0, rSize.Y / 2, 0)).Position
		put(avatarArms.Parts.RightHand, grip * rHandCF)
		put(avatarArms.Parts.RightLowerArm, grip * avatarLimb("RightLowerArm", RIGHT_ELBOW, rWristA, thick * 0.9))
		put(avatarArms.Parts.RightUpperArm, grip * avatarLimb("RightUpperArm", RIGHT_SHOULDER, RIGHT_ELBOW, thick))
		-- left: palm up under the handguard, fingers curled toward the right
		local lSize = avatarHandSize("LeftHand", thick * 0.95)
		local lHandCF = LEFT_HOLD * CFrame.new(0, -0.03, 0) * CFrame.Angles(0, 0, rad(90))
		local lWristA = (lHandCF * CFrame.new(0, lSize.Y / 2, 0)).Position
		put(avatarArms.Parts.LeftHand, grip * lHandCF)
		put(avatarArms.Parts.LeftLowerArm, grip * avatarLimb("LeftLowerArm", LEFT_ELBOW, lWristA, thick * 0.9))
		put(avatarArms.Parts.LeftUpperArm, grip * avatarLimb("LeftUpperArm", LEFT_SHOULDER, LEFT_ELBOW, thick))
	end

	-- Muzzle flash
	local flashing = shouldShow and t < flashUntil
	local muzzle = grip * gun.Profile.Muzzle * CFrame.Angles(0, 0, math.random() * math.pi)
	for _, name in ipairs({ "FlashCore", "FlashA", "FlashB", "FlashLong" }) do
		parts[name].LocalTransparencyModifier = flashing and 0 or 1
	end
	if Config.Effects.Lights then
		parts.FlashCore.MuzzleLight.Brightness = flashing and 7 or 0
	end
	put(parts.FlashCore, muzzle * CFrame.new(0, 0, -0.15))
	put(parts.FlashA, muzzle * CFrame.new(0, 0, -0.15))
	put(parts.FlashB, muzzle * CFrame.new(0, 0, -0.15))
	put(parts.FlashLong, muzzle * CFrame.new(0, 0, -0.45))

	workspace:BulkMoveTo(list, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function Viewmodel.Init(controllers)
	Controllers = controllers
end

function Viewmodel.Start()
	build()
	visible = true
	setVisible(false)

	-- movement reactions
	Controllers.Movement.Jumped:Connect(function()
		moveSpring:Impulse(Vector3.new(0, -2.2, 0))
	end)
	Controllers.Movement.Landed:Connect(function(fallSpeed)
		local strength = math.clamp((fallSpeed - 25) / 60, 0.08, 1.6)
		moveSpring:Impulse(Vector3.new(0, -3.5 * strength, 0))
		recoilSpring:Impulse(Vector3.new(-10 * strength, 0, 0))
	end)
	Controllers.Movement.Slid:Connect(function()
		moveSpring:Impulse(Vector3.new(0, -1.5, 2.5))
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if Keybinds.Matches("Inspect", input) and visible and not inspecting then
			inspecting = true
			inspectStart = os.clock()
			Sfx.Play("CardHover", { Pitch = 0.8, Volume = 1.5 })
		end
	end)

	-- your avatar's arms (rebuilt for every new character / appearance)
	local function refreshArms()
		task.defer(buildAvatarArms, player.Character)
	end
	player.CharacterAppearanceLoaded:Connect(refreshArms)
	player.CharacterAdded:Connect(function()
		task.delay(1, refreshArms) -- in case the appearance event already fired
	end)
	if player.Character then
		refreshArms()
	end

	-- kills play a flourish
	Remotes.Get("HitConfirm").OnClientEvent:Connect(function(info)
		if typeof(info) == "table" and info.Killed and visible then
			Viewmodel.PlayKill()
		end
	end)

	-- the imported rifle can arrive a moment after we start
	local function onRifleChanged(child)
		if child.Name == (Config.Viewmodel.MeshTemplate or "SniperRifle") then
			task.defer(buildGun)
		end
	end
	ReplicatedStorage.ChildAdded:Connect(onRifleChanged)
	ReplicatedStorage.ChildRemoved:Connect(onRifleChanged)

	-- new power-up = new attachment on the rifle; show it off with an inspect
	ClientState.Changed:Connect(function()
		if buildGun() and visible and not inspecting then
			inspecting = true
			inspectStart = os.clock()
			Sfx.Play("CardPick", { Pitch = 1.3, Volume = 0.6 })
		end
	end)

	-- after the camera controller (Camera + 1) so we use the final camera CFrame
	RunService:BindToRenderStep("SniperViewmodel", Enum.RenderPriority.Camera.Value + 2, update)
end

return Viewmodel
