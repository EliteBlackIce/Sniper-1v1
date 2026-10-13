--[[
	LightingController.lua  (Client.LightingController)

	Blends Lighting between the two profiles in Config.Lighting: the arena
	(the base values, also set by the server) and the indoor lobby
	(Config.Lighting.Lobby). Lighting changes made on the client only affect
	this player, so each player gets the profile for where they are.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local ClientState = require(script.Parent.ClientState)

local LightingController = {}

local L = Config.Lighting
local LIGHTING_KEYS = {
	"ClockTime",
	"Brightness",
	"Ambient",
	"OutdoorAmbient",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"ShadowSoftness",
}
local EFFECTS = {
	Atmosphere = "Atmosphere",
	Bloom = "BloomEffect",
	ColorCorrection = "ColorCorrectionEffect",
	SunRays = "SunRaysEffect",
}

local current -- "Arena" / "Lobby"
local tweens = {}

-- the property table for one profile: the arena base, with the lobby's overrides
local function profile(name)
	local over = name == "Lobby" and L.Lobby or {}
	local props = {}
	for _, key in ipairs(LIGHTING_KEYS) do
		props[key] = over[key] ~= nil and over[key] or L[key]
	end
	local effects = {}
	for key in pairs(EFFECTS) do
		local merged = table.clone(L[key])
		for k, v in pairs(over[key] or {}) do
			merged[k] = v
		end
		effects[key] = merged
	end
	return props, effects
end

local function apply(name, instant)
	if name == current then
		return
	end
	current = name
	for _, t in ipairs(tweens) do
		t:Cancel()
	end
	table.clear(tweens)

	local info = TweenInfo.new(instant and 0 or (L.BlendTime or 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local function to(inst, goal)
		if instant then
			for k, v in pairs(goal) do
				inst[k] = v
			end
		else
			local t = TweenService:Create(inst, info, goal)
			table.insert(tweens, t)
			t:Play()
		end
	end

	local props, effects = profile(name)
	to(Lighting, props)
	for key, className in pairs(EFFECTS) do
		local inst = Lighting:FindFirstChild(key)
		if inst and inst.ClassName == className then
			to(inst, effects[key])
		end
	end
end

local function wanted()
	local s = ClientState.Snapshot
	return (s.InMatch or s.Playground) and "Arena" or "Lobby"
end

function LightingController.Init() end

function LightingController.Start()
	-- the server creates the effects at startup; wait briefly so we can blend them too
	Lighting:WaitForChild("ColorCorrection", 5)
	apply(wanted(), true)
	ClientState.Changed:Connect(function()
		apply(wanted(), false)
	end)
end

return LightingController
