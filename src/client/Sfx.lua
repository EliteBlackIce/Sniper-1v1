--[[
	Sfx.lua  (Client.Sfx)
	Plays the sounds listed in Config.Sounds.

		Sfx.Play("Fire")                         -- 2D (UI / your own gun)
		Sfx.Play("Explosion", { Parent = part }) -- 3D at a part/attachment
		Sfx.Play("Hit", { Pitch = 1.2 })         -- pitch multiplier
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Sfx = {}

function Sfx.Play(name, options)
	local def = Config.Sounds[name]
	if not def then
		return nil
	end
	options = options or {}
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = (def.Volume or 0.5) * (options.Volume or 1)
	sound.PlaybackSpeed = (def.Pitch or 1) * (options.Pitch or 1)
	if options.Parent then
		sound.RollOffMaxDistance = 600
		sound.RollOffMinDistance = 12
		sound.Parent = options.Parent
	else
		sound.Parent = SoundService
	end
	sound:Play()
	Debris:AddItem(sound, 5)
	return sound
end

-- Plays a 3D sound at a world position (creates a tiny invisible anchor).
function Sfx.PlayAt(name, position, options)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	Debris:AddItem(anchor, 5)
	options = options or {}
	options.Parent = anchor
	return Sfx.Play(name, options)
end

return Sfx
