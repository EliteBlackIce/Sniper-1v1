--[[
	Config.lua  (ReplicatedStorage.Shared.Config)

	EVERY tunable number in the game lives here. Server and client both read
	this module, so changing a value here changes it everywhere.

	Units: distances are studs, speeds are studs/second, times are seconds,
	angles are degrees unless the name says otherwise.
]]

local Config = {}

----------------------------------------------------------------------------
-- COLOUR PALETTE
-- Flat look: every part in the game picks one of these colours. Change the
-- palette here and the map, viewmodel, characters and UI all follow.
----------------------------------------------------------------------------
Config.Palette = {
	-- Structures (soft whites and greys)
	Snow = Color3.fromRGB(246, 246, 243), -- main floor / big surfaces
	Light = Color3.fromRGB(230, 231, 234), -- walls
	Mid = Color3.fromRGB(204, 207, 213), -- trims, pillars
	Dark = Color3.fromRGB(150, 156, 168), -- deep accents, frames

	-- Accents (cover and highlights)
	AccentA = Color3.fromRGB(56, 199, 182), -- teal: cover blocks
	AccentB = Color3.fromRGB(255, 196, 77), -- mustard: ramps / jump pads / highlights

	-- Players (each player in a match gets one of these)
	PlayerA = Color3.fromRGB(90, 132, 255), -- blue
	PlayerB = Color3.fromRGB(255, 94, 112), -- red
	LobbyPlayer = Color3.fromRGB(205, 210, 220),

	-- Sniper + arms (viewmodel and the gun other players see)
	GunMetal = Color3.fromRGB(38, 41, 49), -- barrel, receiver, scope
	GunMetalLight = Color3.fromRGB(70, 75, 88), -- rails, bolt, small metal bits
	GunFurniture = Color3.fromRGB(84, 104, 78), -- stock + handguard (classic olive)
	GunAccent = Color3.fromRGB(56, 199, 182), -- tiny highlights (matches AccentA)
	ScopeGlass = Color3.fromRGB(120, 220, 255),
	Glove = Color3.fromRGB(36, 38, 44),
	Sleeve = Color3.fromRGB(62, 70, 86),
	SleeveCuff = Color3.fromRGB(48, 54, 68),
	MuzzleFlash = Color3.fromRGB(255, 236, 170),

	-- Effects
	Tracer = Color3.fromRGB(255, 244, 214),
	TracerBounce = Color3.fromRGB(80, 255, 230),
	TracerExplosive = Color3.fromRGB(255, 140, 60),
	Explosion = Color3.fromRGB(255, 150, 70),
	Hologram = Color3.fromRGB(120, 230, 255),
	Grapple = Color3.fromRGB(255, 196, 77),

	-- UI
	UIBackground = Color3.fromRGB(18, 20, 26),
	UIPanel = Color3.fromRGB(30, 33, 42),
	UIPanelLight = Color3.fromRGB(44, 48, 60),
	UIText = Color3.fromRGB(245, 246, 250),
	UISubText = Color3.fromRGB(160, 167, 184),
	UIAccent = Color3.fromRGB(56, 199, 182),
	UIDanger = Color3.fromRGB(255, 84, 96),
	UIHitmarker = Color3.fromRGB(255, 255, 255),
	UIHeadshot = Color3.fromRGB(255, 70, 80),
}

-- City map colours (Downtown arena). Still flat, single-colour parts.
Config.MapPalette = {
	Asphalt = Color3.fromRGB(70, 74, 84),
	RoadLine = Color3.fromRGB(250, 214, 92),
	RoadWhite = Color3.fromRGB(236, 238, 242),
	Sidewalk = Color3.fromRGB(214, 214, 208),
	Curb = Color3.fromRGB(182, 184, 190),
	Concrete = Color3.fromRGB(196, 198, 204),
	BuildingA = Color3.fromRGB(236, 230, 218), -- warm white
	BuildingB = Color3.fromRGB(184, 198, 216), -- cool blue-grey
	BuildingC = Color3.fromRGB(222, 186, 158), -- sandstone
	BuildingD = Color3.fromRGB(160, 172, 188), -- slate (city skyline)
	BuildingE = Color3.fromRGB(205, 214, 200), -- sage
	Trim = Color3.fromRGB(122, 130, 144),
	Roof = Color3.fromRGB(150, 156, 168),
	Window = Color3.fromRGB(88, 118, 150),
	WindowLit = Color3.fromRGB(170, 205, 230),
	Metal = Color3.fromRGB(86, 92, 104),
	Dark = Color3.fromRGB(46, 50, 58),
	Grass = Color3.fromRGB(142, 196, 120),
	Foliage = Color3.fromRGB(104, 178, 110),
	FoliageDark = Color3.fromRGB(76, 150, 96),
	Trunk = Color3.fromRGB(128, 96, 72),
	Wood = Color3.fromRGB(184, 140, 96),
	Water = Color3.fromRGB(110, 196, 232),
	LampLight = Color3.fromRGB(255, 240, 200),
	CarColors = {
		Color3.fromRGB(235, 92, 76),
		Color3.fromRGB(72, 140, 230),
		Color3.fromRGB(244, 244, 244),
		Color3.fromRGB(56, 199, 182),
		Color3.fromRGB(60, 64, 74),
	},
	Bus = Color3.fromRGB(255, 196, 77),
	Train = Color3.fromRGB(56, 199, 182),
	Awning = { Color3.fromRGB(235, 92, 76), Color3.fromRGB(72, 140, 230), Color3.fromRGB(255, 196, 77) },
}

-- Rarity colours (card borders, icons in the HUD) and draw weights.
-- Weight = relative chance a card of this rarity is drawn. Higher rarities
-- have lower weights so they appear less often.
Config.Rarity = {
	Common = { Color = Color3.fromRGB(176, 182, 194), Weight = 55, Order = 1 },
	Rare = { Color = Color3.fromRGB(64, 152, 255), Weight = 28, Order = 2 },
	Epic = { Color = Color3.fromRGB(172, 92, 255), Weight = 13, Order = 3 },
	Legendary = { Color = Color3.fromRGB(255, 196, 60), Weight = 4, Order = 4 },
}

----------------------------------------------------------------------------
-- MATCH FLOW
----------------------------------------------------------------------------
Config.Match = {
	RoundsToWin = 5, -- first to 5 round wins (best of 9)
	CountdownTime = 3, -- "3, 2, 1, GO"
	RoundEndTime = 2.5, -- pause after a kill before the pick screen
	PickTime = 15, -- seconds the loser has to pick a card
	PickRevealTime = 1.6, -- how long the chosen card is shown before the next round
	VictoryTime = 7, -- victory screen length before returning to lobby
	MaxRoundTime = 150, -- if nobody dies, higher health % wins the round (tie = replay)
	CardsPerPick = 5,
	Map = "Downtown", -- "Downtown" (detailed city) or "Classic" (the original simple arena)
	MaxArenas = 4, -- how many matches can run at the same time in one server
	ArenaSpacing = 2000, -- distance between arena copies
	VoidDepth = 80, -- falling this far below the arena floor kills you
}

----------------------------------------------------------------------------
-- LOBBY PRACTICE RANGE
----------------------------------------------------------------------------
Config.Lobby = {
	QueueKey = Enum.KeyCode.F, -- press in the lobby to find a match
	DummyHealth = 100,
	DummyRespawnTime = 1.2,
}

----------------------------------------------------------------------------
-- PLAYER / HEALTH
----------------------------------------------------------------------------
Config.Player = {
	MaxHealth = 100,
}

----------------------------------------------------------------------------
-- CAMERA
----------------------------------------------------------------------------
Config.Camera = {
	BaseFOV = 82,
	ScopeFOV = 22, -- field of view while fully scoped
	FOVLerpSpeed = 12, -- how quickly FOV follows its target
	SprintFOVKick = 5,
	SlideFOVKick = 9,
	BlinkFOVKick = 18,
	WallRunFOVKick = 6,
	SpeedFOVPerStud = 0.22, -- extra FOV per stud/s above sprint speed
	MaxSpeedFOV = 14,

	WallRunTilt = 11, -- camera roll while wall running
	SlideTilt = 5,
	StrafeTilt = 1.2, -- tiny roll when strafing
	TiltLerpSpeed = 10,

	SlideCameraDrop = 1.7, -- studs the camera lowers while sliding
	CameraDropLerpSpeed = 14,

	RecoilPitch = 2.4, -- degrees the aim kicks up per shot (hipfire)
	ScopedRecoilPitch = 1.2,

	FirstPersonInLobby = true, -- lobby is first person too (you can practise there)
	HeadBob = 0.07, -- studs of camera bob while running (0 = off)
	LandingDip = 0.012, -- camera dip per stud/s of landing speed
	MaxLandingDip = 0.9,
}

-- Viewmodel (first-person arms + gun) animation
Config.Viewmodel = {
	EquipTime = 0.45, -- gun raise animation when you spawn
	SwayAmount = 0.06, -- how much the gun lags behind the mouse
	BobAmount = 1.0, -- walk bob strength
	InspectKey = Enum.KeyCode.V, -- admire your rifle
}

-- Defaults for the settings menu (players can change and save these).
Config.SettingsDefaults = {
	Sensitivity = 1.0, -- normal look sensitivity multiplier
	ScopedSensitivity = 0.45, -- multiplier used while scoped
	ToggleScope = false, -- false = hold right mouse, true = click to toggle
	AimAssist = true, -- controller aim assist on/off (players can change it)
}
Config.SettingsLimits = {
	Sensitivity = { Min = 0.1, Max = 3.0 },
	ScopedSensitivity = { Min = 0.05, Max = 2.0 },
}

----------------------------------------------------------------------------
-- AIM ASSIST (controller only, deliberately subtle)
----------------------------------------------------------------------------
Config.AimAssist = {
	Enabled = true, -- master switch (players can also turn it off in settings)
	ConeDegrees = 4.5, -- only helps when the crosshair is this close to a target (at normal FOV)
	Slowdown = 0.3, -- aim turns up to 30% slower right on top of a target
	PullDegreesPerSecond = 3.5, -- max gentle drift toward the body while moving / aiming
	ScopedPullMultiplier = 0.6, -- less pull while scoped
	Range = 900, -- studs
}

----------------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------------
Config.Movement = {
	Gravity = 185, -- workspace gravity (default Roblox is 196.2). Higher = snappier jumps

	-- Movement uses the same model as Source games (CS / TF2 / Titanfall):
	-- ground friction + acceleration, and "air strafing" in the air, which is
	-- what makes bunny hopping work.
	RunSpeed = 30, -- normal top speed on the ground
	SprintSpeed = 38, -- top speed while holding Shift on the ground
	GroundAccel = 15, -- how quickly you reach top speed (higher = snappier)
	Friction = 7, -- ground friction (higher = stop faster)
	StopSpeed = 10, -- below this speed friction acts as if you were going this fast

	-- BUNNY HOPPING
	-- Hold Space: you jump again the instant you land, and the landing frame
	-- skips friction, so you keep all your speed. Hold A or D and turn the
	-- mouse the same way in the air to GAIN speed (air strafing).
	AutoBhop = true, -- true = holding Space re-jumps on landing
	JumpBuffer = 0.15, -- a jump pressed this long before landing still counts
	CoyoteTime = 0.12, -- you can still jump this long after leaving the ground
	AirAccel = 14, -- air strafe strength (Source uses 10-12)
	AirSpeedCap = 4.2, -- small cap per frame = the classic strafe gain (Source: 30 units)
	AirControlSpeed = 30, -- wish speed used in the air
	AirSteer = 4.5, -- holding W in the air turns your momentum toward your aim (per second)
	AirMinSpeed = 26, -- in the air you can always accelerate up to this speed...
	AirLowSpeedAccel = 7, -- ...this quickly (so standing jumps aren't stuck)
	MaxSpeed = 120, -- hard limit on horizontal speed

	JumpPower = 55,
	AirJumps = 0, -- no double jump by default (the Double Jump power-up adds one)
	AirJumpVelocity = 53,
	AirJumpMinSpeed = 30, -- a double jump re-aims you toward your keys at least this fast

	-- Slide
	SlideKey = Enum.KeyCode.C, -- LeftControl also works
	SlideHold = false, -- false = tap C to slide (press again to stop), true = hold C
	SlideMinSpeed = 18, -- need at least this speed to start a slide
	SlideBoost = 12, -- speed added when the slide starts...
	SlideBoostCap = 55, -- ...but only up to this speed (no infinite slide boosting)
	SlideFriction = 0.55, -- slide friction (much lower than running)
	SlideEndSpeed = 16, -- slide ends below this speed
	SlideSteer = 2.2, -- how much you can steer a slide
	SlideCooldown = 0.25,
	SlideJumpBoost = 4, -- extra speed for jumping out of a slide (up to SlideBoostCap)

	-- Wall run (automatic: be in the air, moving, next to a wall)
	WallCheckDistance = 3.4,
	WallRunMinSpeed = 14,
	WallRunSpeed = 38, -- minimum speed while wall running
	WallRunDuration = 1.6,
	WallRunStartLift = 8, -- small upward pop when you latch on
	WallRunGravity = 22, -- how quickly you sink while wall running
	WallJumpOut = 34, -- push away from wall
	WallJumpUp = 50,
	WallReattachDelay = 0.3,

	-- Grapple Hook power-up (press E)
	GrappleRange = 220,
	GrapplePullSpeed = 95,
	GrappleAccel = 260,
	GrappleMaxTime = 1.6,
	GrappleReleaseDistance = 7,
	GrappleCooldown = 3,

	-- Knockback received from explosions / shockwaves is multiplied by this
	KnockbackScale = 1.0,
}

----------------------------------------------------------------------------
-- SNIPER
----------------------------------------------------------------------------
Config.Weapon = {
	HeadDamage = 1000, -- headshot = instant kill
	BodyDamage = 72, -- torso / root
	LimbDamage = 55, -- arms / legs
	BoltTime = 1.05, -- seconds between shots (bolt-action delay)
	ScopeInTime = 0.22, -- seconds to fully scope in
	MaxRange = 2500,
	HipSpreadDegrees = 1.4, -- random spread when NOT scoped (0 = perfect hipfire)
	ScopedSpreadDegrees = 0,

	-- Server-side validation (anti-exploit)
	FireRateTolerance = 0.82, -- shots faster than BoltTime * this are rejected
	OriginTolerance = 7, -- shot origin must be this close to the server's head position...
	OriginSpeedAllowance = 0.3, -- ...plus (shooter speed * this) to allow for latency
	ClaimPathTolerance = 2.5, -- claimed hit must be this close to the server's bullet path
	ClaimTargetTolerance = 5, -- and this close to where the victim really is...
	ClaimSpeedAllowance = 0.25, -- ...plus (victim speed * this)
}

----------------------------------------------------------------------------
-- POWER-UP STRENGTHS
-- The power-up definitions themselves live in PowerUps.lua; the numbers
-- they use live here.
----------------------------------------------------------------------------
Config.PowerUps = {
	-- Most numbers below are "per stack": picking the same card again makes it stronger.

	-- BULLET PATH
	GhostRound = { WallsPerStack = 1 },
	Ricochet = { BouncesPerStack = 1 },
	SplitShot = { BulletsPerStack = 2, SpreadDegrees = 1.6 }, -- 1 + 2 = 3 bullets, 5 at 2 stacks
	HomingRounds = { Radius = 9, RadiusPerStack = 3, TurnDegreesPerStack = 5, StepLength = 18 },
	ExplosiveRounds = {
		Radius = 13,
		RadiusPerStack = 4, -- extra stacks
		Damage = 45,
		DamagePerStack = 15, -- extra stacks
		Knockback = 70,
		SelfKnockback = 55,
	},
	Shrapnel = { ShardsPerStack = 2, Damage = 16, Range = 60, SpreadDegrees = 40, MaxShardsPerShot = 14 },
	StaticCharge = { Damage = 20, Radius = 7, RadiusPerStack = 2 }, -- near misses zap the enemy

	-- DAMAGE
	Pinball = { BonusPerHop = 0.35 }, -- +35% damage per bounce / wall pass, per stack
	MomentumRounds = { BonusPerSpeed = 0.012, MaxBonus = 0.6, FreeSpeed = 30 }, -- per stack
	SkySniper = { AirBonus = 0.2 }, -- per stack
	GlassCannon = { DamageBonus = 0.3, HealthCost = 20 }, -- per stack
	Marked = { Duration = 4, BonusPerStack = 0.25 },
	HairTrigger = {}, -- a hit re-chambers your rifle instantly
	Vampire = { HealFraction = 0.5 }, -- per stack (of damage dealt)

	-- MOVEMENT
	DoubleJump = { ExtraJumpsPerStack = 1 },
	Adrenaline = { SpeedPerStack = 0.08 },
	Featherweight = { GravityReductionPerStack = 0.18 },
	SpringLegs = { JumpPerStack = 0.15 },
	Blink = { Distance = 28, DistancePerStack = 8, Cooldown = 6 }, -- cooldown is divided by stacks
	Grapple = { CooldownDividedByStacks = true, PullPerStack = 0.2 },
	MagneticBoots = {},
	RocketJump = { Radius = 9, LaunchUp = 88, LaunchAway = 28, PowerPerStack = 0.25 },
	PhantomDash = { InvisibleTime = 0.5, TimePerStack = 0.35 },
	ShockwaveLanding = {
		MinFallHeight = 20,
		Radius = 24,
		RadiusPerStack = 6,
		Knockback = 90,
		KnockbackPerStack = 20,
		DamagePerExtraStack = 20, -- stacks 2+ also deal damage
		Cooldown = 2,
	},

	-- UTILITY / DEFENCE
	BulletTime = {
		Duration = 2,
		DurationPerStack = 1, -- extra stacks
		Cooldown = 6,
		GravityScale = 0.15, -- fall speed multiplier while active
		MoveScale = 0.45, -- horizontal momentum multiplier while active
		SensitivityScale = 0.6,
		BoltSpeedScale = 2, -- bolt cycles this many times faster while active
	},
	Quickdraw = { SpeedPerStack = 0.4 }, -- 40% faster bolt + scope (multiplies per stack)
	ThickSkin = { HealthPerStack = 40 },
	SecondWind = { SpeedMultiplier = 1.35, BoostTime = 3 }, -- one save per stack, each round
	WallhackPulse = { Interval = 10, IntervalScalePerStack = 0.7, Duration = 1, DurationPerStack = 0.25 },
	Decoy = { Cooldown = 8, Lifetime = 4, Speed = 26, SpreadDegrees = 30 }, -- one decoy per stack
}

----------------------------------------------------------------------------
-- SOUNDS
-- These use sounds that ship with the Roblox client (rbxasset://). If one
-- doesn't play on your machine, swap it for any rbxassetid://<id> from the
-- Creator Store.
----------------------------------------------------------------------------
Config.Sounds = {
	Fire = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.6, Pitch = 1.6 },
	Bolt = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Pitch = 0.8 },
	Hit = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.4 },
	Headshot = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Pitch = 1.9 },
	Kill = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Pitch = 0.75 },
	Hurt = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.5, Pitch = 0.7 },
	Dash = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.45, Pitch = 1.2 },
	Jump = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.35, Pitch = 1.1 },
	Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.35, Pitch = 1 },
	Explosion = { Id = "rbxasset://sounds/collide.wav", Volume = 0.7, Pitch = 0.9 },
	CardFlip = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.35, Pitch = 1.8 },
	CardLegendary = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 0.6 },
	CardHover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25, Pitch = 1.6 },
	CardPick = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.6, Pitch = 1.2 },
	Countdown = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Pitch = 1 },
	Go = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 1.2 },
	Victory = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 0.5 },
	Ability = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.4, Pitch = 0.8 },
}

----------------------------------------------------------------------------
-- VISUAL EFFECTS (client). Turn things off here if you want a calmer look
-- or better performance.
----------------------------------------------------------------------------
Config.Effects = {
	NeonEffects = true, -- tracers, flashes and explosions glow (Neon + bloom)
	Particles = true, -- sparks / smoke / dust (Roblox's built-in particle textures)
	Lights = true, -- muzzle, impact and explosion light flashes
	KillShatter = true, -- bodies burst into shards on a kill
	DamageNumbers = true, -- floating numbers where your shots land
	SpeedLines = true, -- streaks at the screen edges when you're fast
	SpeedLinesFrom = 44, -- speed (u/s) where speed lines start
	SparkTexture = "rbxasset://textures/particles/sparkles_main.dds",
	SmokeTexture = "rbxasset://textures/particles/smoke_main.dds",
}

----------------------------------------------------------------------------
-- LIGHTING (applied by the server at startup, see LightingSetup.lua)
----------------------------------------------------------------------------
Config.Lighting = {
	ClockTime = 15.3, -- mid-afternoon: long, clean shadows
	GeographicLatitude = 38,
	Brightness = 3.2,
	Ambient = Color3.fromRGB(70, 74, 84),
	OutdoorAmbient = Color3.fromRGB(150, 156, 170),
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.25,
	ShadowSoftness = 0.08,

	Atmosphere = {
		Density = 0.28,
		Offset = 0.12,
		Color = Color3.fromRGB(205, 218, 235),
		Decay = Color3.fromRGB(120, 140, 175),
		Glare = 0.15,
		Haze = 1.2,
	},
	Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.4 },
	ColorCorrection = {
		Brightness = 0.02,
		Contrast = 0.1,
		Saturation = 0.12,
		TintColor = Color3.fromRGB(255, 252, 246),
	},
	SunRays = { Intensity = 0.06, Spread = 0.6 },
}

----------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------
Config.UI = {
	FontFamily = "rbxasset://fonts/families/GothamSSm.json",
	CornerRadius = 10,
	SettingsKey = Enum.KeyCode.P,
}

----------------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------------
Config.Debug = {
	LogRejectedShots = true, -- print a warning when the server rejects a shot
}

return Config
