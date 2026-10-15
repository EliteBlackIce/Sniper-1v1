--[[
	Sfx.lua  (Client.Sfx)
	Plays the sounds listed in Config.Sounds, plus a few layered "stingers"
	defined below (built only from the same built-in rbxasset sounds).

		Sfx.Play("Fire")                         -- 2D (UI / your own gun)
		Sfx.Play("Explosion", { Parent = part }) -- 3D at a part/attachment
		Sfx.Play("Hit", { Pitch = 1.2 })         -- pitch multiplier
		Sfx.Play("RoundWon")                     -- a layered stinger
		Sfx.PlayAt("Explosion", position)        -- 3D at a world position

	Options: Volume, Pitch (multipliers), Parent (3D), Vary (random pitch
	+-fraction), NoThrottle (allow the same 2D sound twice in one frame).

	2D sounds are pooled (a few Sound objects per name, reused), and the same
	2D sound fired several times within THROTTLE seconds (split shot hits,
	shrapnel) plays once, so volume never stacks into a spike.
	Sfx.SetVolume(0..1) scales everything (for a settings slider).
]]

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Sfx = {}

local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local THUMP = "rbxasset://sounds/collide.wav"
local WHOOSH = "rbxasset://sounds/swordlunge.wav"

-- Layered stingers: { Id, Volume, Pitch, Delay }. Config.Sounds entries
-- with the same name win, so these can be overridden there.
local STINGERS = {
	RoundWon = {
		{ PING, 0.55, 1.0, 0 },
		{ PING, 0.5, 1.5, 0.1 },
		{ PING, 0.5, 2.0, 0.2 },
		{ THUMP, 0.4, 0.7, 0 },
	},
	RoundLost = {
		{ PING, 0.55, 0.7, 0 },
		{ PING, 0.5, 0.5, 0.16 },
		{ THUMP, 0.55, 0.45, 0 },
	},
	MatchPoint = {
		{ THUMP, 0.6, 0.4, 0 },
		{ PING, 0.4, 0.8, 0.05 },
		{ PING, 0.4, 0.8, 0.3 },
	},
	CountdownTick = {
		{ CLICK, 0.6, 1.0, 0 },
		{ PING, 0.2, 1.6, 0 },
	},
	FightStart = {
		{ THUMP, 0.5, 0.6, 0 },
		{ WHOOSH, 0.35, 1.4, 0.02 },
	},
	TimerTick = { { CLICK, 0.35, 1.5, 0 } },
	AbilityReady = {
		{ CLICK, 0.25, 2.0, 0 },
		{ PING, 0.12, 2.4, 0.03 },
	},
	Heartbeat = {
		{ THUMP, 0.22, 0.32, 0 },
		{ THUMP, 0.16, 0.3, 0.16 },
	},
	NearMiss = { { WHOOSH, 0.55, 2.4, 0 } },
	KillCamIn = {
		{ WHOOSH, 0.5, 0.6, 0 },
		{ THUMP, 0.35, 0.4, 0 },
	},
	SlowMo = { { THUMP, 0.5, 0.3, 0 }, { WHOOSH, 0.3, 0.45, 0 } },
	Impact = { { CLICK, 0.25, 0.7, 0 } },
}

local THROTTLE = 0.03
local POOL_PER_ID = 4
local masterVolume = 1
local lastPlayed = {} -- [name] = os.clock()
local pools = {} -- [soundId] = { Sound }

function Sfx.SetVolume(volume)
	masterVolume = math.clamp(tonumber(volume) or 1, 0, 1)
end

function Sfx.GetVolume()
	return masterVolume
end

-- A free pooled 2D sound for this id (or a new one / the one that's furthest along).
local function pooled(id)
	local list = pools[id]
	if not list then
		list = {}
		pools[id] = list
	end
	for _, s in ipairs(list) do
		if s.Parent and not s.IsPlaying then
			return s
		end
	end
	if #list < POOL_PER_ID then
		local s = Instance.new("Sound")
		s.Name = "Sfx"
		s.SoundId = id
		s.Parent = SoundService
		table.insert(list, s)
		return s
	end
	local best = list[1]
	for _, s in ipairs(list) do
		if s.TimePosition > best.TimePosition then
			best = s
		end
	end
	return best
end

local function playOne(id, volume, pitch, parent)
	if volume <= 0 then
		return nil
	end
	local sound
	if parent then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.RollOffMaxDistance = 600
		sound.RollOffMinDistance = 12
		sound.Volume = volume
		sound.PlaybackSpeed = pitch
		sound.Parent = parent
		sound:Play()
		Debris:AddItem(sound, 5)
	else
		sound = pooled(id)
		sound.Volume = volume
		sound.PlaybackSpeed = pitch
		sound.TimePosition = 0
		sound:Play()
	end
	return sound
end

function Sfx.Play(name, options)
	options = options or {}
	local def = Config.Sounds[name]
	local layers = not def and STINGERS[name]
	if not def and not layers then
		return nil
	end
	local parent = options.Parent
	if not parent and not options.NoThrottle then
		local now = os.clock()
		if lastPlayed[name] and now - lastPlayed[name] < THROTTLE then
			return nil
		end
		lastPlayed[name] = now
	end
	local volume = (options.Volume or 1) * masterVolume
	local pitch = options.Pitch or 1
	if options.Vary then
		pitch *= 1 + (math.random() * 2 - 1) * options.Vary
	end
	if def then
		return playOne(def.Id, (def.Volume or 0.5) * volume, (def.Pitch or 1) * pitch, parent)
	end
	local first
	for _, layer in ipairs(layers) do
		local id, v, p, delay = layer[1], layer[2] * volume, layer[3] * pitch, layer[4] or 0
		if delay > 0 then
			task.delay(delay, function()
				if not parent or parent.Parent then
					playOne(id, v, p, parent)
				end
			end)
		else
			first = first or playOne(id, v, p, parent)
		end
	end
	return first
end

-- Plays a 3D sound at a world position (creates a tiny invisible anchor).
function Sfx.PlayAt(name, position, options)
	if typeof(position) ~= "Vector3" then
		return nil
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	Debris:AddItem(anchor, 5)
	options = options and table.clone(options) or {}
	options.Parent = anchor
	return Sfx.Play(name, options)
end

return Sfx
