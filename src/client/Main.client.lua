--[[
	Main  (StarterPlayerScripts.Client.Main)

	Client entry point. Requires every controller, gives each one a shared
	`controllers` table (so they can call each other without circular
	requires), then starts them.

	Client layout:
		ClientState          latest match snapshot, my power-up stats, settings
		CameraController     first-person lock, FOV, tilt, recoil, sensitivity
		MovementController   bhop / sprint / slide / wall run (power-up) / grapple
		ViewmodelController  arms + sniper attached to the camera
		WeaponController     scope + fire (sends shots to the server)
		EffectsController    tracers, explosions, ropes, screen tints
		UIController         all screens (ui/ folder)
		CharacterPoser       third-person rifle-holding pose for other players
		AimAssist            light controller aim assist (used by CameraController)
		KillCamController    replays your death through your killer's eyes
		LightingController   arena / indoor lobby lighting profiles
		CrateController      the lobby crate + its opening cinematic
		KnifeController      the combat knife: switching, slashes, stabs, hit checks
]]

local Client = script.Parent

local ClientState = require(Client.ClientState)
local CameraController = require(Client.CameraController)
local MovementController = require(Client.MovementController)
local ViewmodelController = require(Client.ViewmodelController)
local WeaponController = require(Client.WeaponController)
local EffectsController = require(Client.EffectsController)
local UIController = require(Client.UIController)
local CharacterPoser = require(Client.CharacterPoser)
local KillCamController = require(Client.KillCamController)
local LightingController = require(Client.LightingController)
local CrateController = require(Client.CrateController)
local KnifeController = require(Client.KnifeController)

local controllers = {
	Camera = CameraController,
	Movement = MovementController,
	Viewmodel = ViewmodelController,
	Weapon = WeaponController,
	Effects = EffectsController,
	UI = UIController,
	Poser = CharacterPoser,
	KillCam = KillCamController,
	Lighting = LightingController,
	Crates = CrateController,
	Knife = KnifeController,
}

ClientState.Init()

local order = {
	CameraController,
	MovementController,
	ViewmodelController,
	WeaponController,
	EffectsController,
	UIController,
	CharacterPoser,
	KillCamController,
	LightingController,
	CrateController,
	KnifeController,
}
for _, controller in ipairs(order) do
	controller.Init(controllers)
end
for _, controller in ipairs(order) do
	controller.Start()
end
