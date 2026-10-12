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

	-- Viewmodel
	Skin = Color3.fromRGB(238, 200, 170),
	Sleeve = Color3.fromRGB(52, 57, 70),
	GunBody = Color3.fromRGB(44, 48, 58),
	GunTrim = Color3.fromRGB(120, 126, 140),
	ScopeGlass = Color3.fromRGB(120, 220, 255),

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
	RoundsToWin = 4, -- best of 7
	CountdownTime = 3, -- "3, 2, 1, GO"
	RoundEndTime = 2.5, -- pause after a kill before the pick screen
	PickTime = 15, -- seconds the loser has to pick a card
	PickRevealTime = 1.6, -- how long the chosen card is shown before the next round
	VictoryTime = 7, -- victory screen length before returning to lobby
	MaxRoundTime = 150, -- if nobody dies, higher health % wins the round (tie = replay)
	CardsPerPick = 5,
	MaxArenas = 4, -- how many matches can run at the same time in one server
	ArenaSpacing = 2000, -- distance between arena copies
	VoidDepth = 80, -- falling this far below the arena floor kills you
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
	DashFOVKick = 14,
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
}

-- Defaults for the settings menu (players can change and save these).
Config.SettingsDefaults = {
	Sensitivity = 1.0, -- normal look sensitivity multiplier
	ScopedSensitivity = 0.45, -- multiplier used while scoped
	ToggleScope = false, -- false = hold right mouse, true = click to toggle
}
Config.SettingsLimits = {
	Sensitivity = { Min = 0.1, Max = 3.0 },
	ScopedSensitivity = { Min = 0.05, Max = 2.0 },
}

----------------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------------
Config.Movement = {
	Gravity = 170, -- workspace gravity (default Roblox is 196.2)

	WalkSpeed = 22,
	SprintSpeed = 32,
	GroundAccel = 160, -- how fast you reach target speed on the ground
	GroundFriction = 140, -- how fast you stop with no input
	ExcessFriction = 55, -- how fast speed ABOVE sprint speed bleeds off on the ground
	BhopGrace = 0.12, -- seconds after landing with no friction (slide/dash -> jump chains)

	JumpPower = 52,
	AirJumps = 1, -- 1 = double jump (Triple Jump power-up adds more)
	AirJumpVelocity = 52,
	AirAccel = 70, -- air steering acceleration
	AirMaxInputSpeed = 32, -- input alone can't push you faster than this in the air
	AirTurnRate = 2.2, -- how strongly air input re-aims existing momentum (per second)
	AirDrag = 0.35, -- fraction of excess momentum lost per second in the air

	-- Slide
	SlideKey = Enum.KeyCode.C, -- LeftControl also works
	SlideMinSpeed = 18, -- need at least this speed to start a slide
	SlideBoost = 14, -- speed added when the slide starts
	SlideMaxSpeed = 62,
	SlideFriction = 22, -- speed lost per second while sliding
	SlideEndSpeed = 14, -- slide ends below this speed
	SlideSteer = 1.6, -- how much you can steer a slide
	SlideCooldown = 0.35,
	SlideJumpBoost = 4, -- extra speed for jumping out of a slide

	-- Air dash (press Shift in the air)
	DashSpeed = 82,
	DashDuration = 0.16,
	DashExitSpeed = 44, -- speed you keep after the dash
	DashesPerAir = 1, -- refills on landing / wall run
	DashCooldown = 0.5,

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
	GhostRound = { WallsPerStack = 1 },
	Ricochet = { BouncesPerStack = 1 },
	BulletTime = {
		Duration = 2,
		Cooldown = 6,
		GravityScale = 0.15, -- fall speed multiplier while active
		MoveScale = 0.45, -- horizontal momentum multiplier while active
		SensitivityScale = 0.6,
		BoltSpeedScale = 2, -- bolt cycles this many times faster while active
	},
	PhantomDash = { InvisibleTime = 0.5 },
	SplitShot = { BulletsPerStack = 2, SpreadDegrees = 1.6 }, -- 1 + 2 = 3 bullets
	RocketJump = { Radius = 9, LaunchUp = 88, LaunchAway = 28 },
	SecondWind = { SpeedMultiplier = 1.35, BoostTime = 3 },
	HomingRounds = { Radius = 9, TurnDegreesPerStep = 5, StepLength = 18 },
	TripleJump = { ExtraJumpsPerStack = 1 },
	Quickdraw = { SpeedPerStack = 0.4 }, -- 40% faster bolt + scope
	ThickSkin = { HealthPerStack = 40 },
	WallhackPulse = { Interval = 10, Duration = 1 },
	Decoy = { Cooldown = 8, Lifetime = 4, Speed = 26 },
	ExplosiveRounds = { Radius = 13, Damage = 45, Knockback = 70, SelfKnockback = 55 },
	MagneticBoots = {},
	Vampire = { HealFraction = 0.5 },
	ShockwaveLanding = { MinFallHeight = 20, Radius = 24, Knockback = 90, Cooldown = 2 },
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
	FirstPersonInLobby = false, -- true = lobby also uses the locked first-person camera
	LogRejectedShots = true, -- print a warning when the server rejects a shot
}

return Config
