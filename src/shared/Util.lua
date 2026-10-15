--[[
	Util.lua  (ReplicatedStorage.Shared.Util)
	Small helpers used by both server and client.
]]

local Util = {}

-- Moves `current` toward `target` by at most `maxDelta`.
function Util.approach(current, target, maxDelta)
	if current < target then
		return math.min(current + maxDelta, target)
	end
	return math.max(current - maxDelta, target)
end

-- Frame-rate independent exponential smoothing factor.
-- lerp(a, b, Util.smooth(speed, dt)) moves a toward b at `speed`.
function Util.smooth(speed, dt)
	return 1 - math.exp(-speed * dt)
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

-- Removes the Y component of a vector.
function Util.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Returns v.Unit, or `fallback` (default zero vector) if v is ~zero.
function Util.safeUnit(v, fallback)
	if v.Magnitude < 1e-4 then
		return fallback or Vector3.zero
	end
	return v.Unit
end

-- True if the value is a Vector3 with finite components (rejects NaN / inf
-- that an exploiter could send through a RemoteEvent).
function Util.isFiniteVector3(v)
	if typeof(v) ~= "Vector3" then
		return false
	end
	for _, c in ipairs({ v.X, v.Y, v.Z }) do
		if c ~= c or c == math.huge or c == -math.huge then
			return false
		end
	end
	return true
end

-- Shortest distance from point p to the segment a-b.
function Util.distanceToSegment(p, a, b)
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- Smoke Grenade clouds (workspace.Smoke) are CanQuery = false so bullets
-- fly through them, which means raycasts can't see them either. Anything
-- that needs real line of sight (the bot's eyes, controller aim assist)
-- checks the segment a-b against the puffs with this. Fading puffs
-- (Transparency >= 0.6) no longer block.
function Util.smokeBlocks(a, b)
	local folder = workspace:FindFirstChild("Smoke")
	if not folder then
		return false
	end
	for _, cloud in ipairs(folder:GetChildren()) do
		for _, puff in ipairs(cloud:GetChildren()) do
			if puff:IsA("BasePart") and puff.Transparency < 0.6 then
				if Util.distanceToSegment(puff.Position, a, b) < puff.Size.X * 0.45 then
					return true
				end
			end
		end
	end
	return false
end

-- Finds the character model a part belongs to (a Model containing a Humanoid).
function Util.getCharacterFromPart(part)
	local model = part and part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Body-part category used for damage: "Head", "Body" or "Limb".
local BODY_PARTS = {
	UpperTorso = true,
	LowerTorso = true,
	Torso = true,
	HumanoidRootPart = true,
}
function Util.hitZone(partName)
	if partName == "Head" or partName == "HitboxHead" then
		return "Head"
	elseif partName == "HitboxLegs" then
		return "Limb"
	elseif BODY_PARTS[partName] or partName == "HitboxTorso" then
		return "Body"
	end
	return "Limb"
end

-- True for server-side bots (plain tables standing in for a Player).
-- Never index .IsBot on a real Player: unknown properties throw.
function Util.isBot(player)
	return typeof(player) == "table" and player.IsBot == true
end

return Util
