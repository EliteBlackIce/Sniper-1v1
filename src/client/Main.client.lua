--[[
	Main  (StarterPlayerScripts.Client.Main)

	Client entry point. Requires every controller, gives each one a shared
	`controllers` table (so they can call each other without circular
	requires), then starts them.

	Client layout:
		ClientState          latest match snapshot, my power-up stats, settings
		CameraController     first-person lock, FOV, tilt, recoil, sensitivity
		MovementController   sprint / slide / double jump / dash / wall run / grapple
		ViewmodelController  arms + sniper attached to the camera
		WeaponController     scope + fire (sends shots to the server)
		EffectsController    tracers, explosions, ropes, screen tints
		UIController         all screens (ui/ folder)
		CharacterPoser       third-person rifle-holding pose for other players
		AimAssist            light controller aim assist (used by CameraController)
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

local controllers = {
	Camera = CameraController,
	Movement = MovementController,
	Viewmodel = ViewmodelController,
	Weapon = WeaponController,
	Effects = EffectsController,
	UI = UIController,
	Poser = CharacterPoser,
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
}
for _, controller in ipairs(order) do
	controller.Init(controllers)
end
for _, controller in ipairs(order) do
	controller.Start()
end
