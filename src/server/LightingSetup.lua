--[[
	LightingSetup.lua  (ServerScriptService.Server.LightingSetup)

	Sets up Lighting from Config.Lighting: time of day, ambient colours and the
	post effects (Atmosphere, Bloom, ColorCorrection, SunRays) and clouds.

	NOTE: Lighting.Technology = Future cannot be set from a script; it is set in
	default.project.json (and you can double check it in Studio: Lighting >
	Technology).
]]

local Lighting = game:GetService("Lighting")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local LightingSetup = {}

local function getOrCreate(className, name)
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function LightingSetup.Apply()
	local L = Config.Lighting

	Lighting.GlobalShadows = true
	Lighting.ClockTime = L.ClockTime
	Lighting.GeographicLatitude = L.GeographicLatitude
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient
	Lighting.EnvironmentDiffuseScale = L.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = L.EnvironmentSpecularScale
	Lighting.ShadowSoftness = L.ShadowSoftness

	local atmosphere = getOrCreate("Atmosphere", "Atmosphere")
	for key, value in pairs(L.Atmosphere) do
		atmosphere[key] = value
	end

	local bloom = getOrCreate("BloomEffect", "Bloom")
	for key, value in pairs(L.Bloom) do
		bloom[key] = value
	end

	local cc = getOrCreate("ColorCorrectionEffect", "ColorCorrection")
	for key, value in pairs(L.ColorCorrection) do
		cc[key] = value
	end

	local sunRays = getOrCreate("SunRaysEffect", "SunRays")
	for key, value in pairs(L.SunRays) do
		sunRays[key] = value
	end

	if L.Clouds then
		local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		for key, value in pairs(L.Clouds) do
			clouds[key] = value
		end
		clouds.Parent = workspace.Terrain
	end

	workspace.Gravity = Config.Movement.Gravity
end

return LightingSetup
