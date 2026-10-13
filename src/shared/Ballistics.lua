--[[
	Ballistics.lua  (ReplicatedStorage.Shared.Ballistics)

	Traces a sniper bullet through the world. The SAME code runs on:
	  * the shooter's client  -> instant tracers + hit claims
	  * the server            -> authoritative path used to validate hits

	Bullets are hitscan, but can be bent by power-ups:
	  Ghost Round   passes through N walls
	  Ricochet      reflects off N surfaces
	  Homing Rounds curves toward an enemy that is close to the bullet's path

	A simulation returns:
	{
		Segments = { {From, To, Kind = "Normal"|"Bounce", Hops}, ... },
		Hit = { Part, Position, Normal, Model, Hops } or nil  -- first character/decoy hit
		Impacts = { {Position, Normal, Direction}, ... } -- surfaces touched (Shrapnel)
		EndPosition = Vector3,                         -- where the bullet stopped
		EndNormal = Vector3?,                          -- surface normal at the end
		Passes = { Vector3, ... },                     -- points where it went through walls
	}
]]

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

local Ballistics = {}

local MAX_ITERATIONS = 64

-- Is this instance something a bullet should "hit" (stop on and report)?
-- Characters (have a Humanoid), decoys (Decoy=true) and practice dummies (Dummy=true).
local function findTargetModel(part)
	local character = Util.getCharacterFromPart(part)
	if character then
		return character
	end
	-- decoys and lobby practice dummies are models with an attribute
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("Decoy") or model:GetAttribute("Dummy") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end
Ballistics.FindTargetModel = findTargetModel

-- Returns the list of directions for one trigger pull. Normally 1 bullet;
-- Split Shot adds bullets in a tight horizontal fan around the aim direction.
function Ballistics.GetShotDirections(direction, bulletCount)
	direction = direction.Unit
	local dirs = { direction }
	if bulletCount <= 1 then
		return dirs
	end

	local right = direction:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-3 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(direction).Unit
	local step = math.rad(Config.PowerUps.SplitShot.SpreadDegrees)

	local extra = bulletCount - 1
	for i = 1, extra do
		-- alternate left / right: +1, -1, +2, -2 ...
		local ring = math.ceil(i / 2)
		local sign = (i % 2 == 1) and 1 or -1
		local rotation = CFrame.fromAxisAngle(up, step * ring * sign)
		table.insert(dirs, rotation:VectorToWorldSpace(direction))
	end
	return dirs
end

-- Rotates unit vector `from` toward unit vector `to` by at most maxRadians.
local function rotateToward(from, to, maxRadians)
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle < 1e-4 then
		return from
	end
	local t = math.min(1, maxRadians / angle)
	-- slerp approximation, fine for small angles
	return (from:Lerp(to, t)).Unit
end

--[[
	params:
		Origin        Vector3
		Direction     Vector3 (unit)
		Stats         power-up stat table (PowerUps.ComputeStats)
		Exclude       { Instance } ignored by the ray (shooter, effects, viewmodel)
		HomingTargets { Vector3 } positions bullets may curve toward (optional)
		IgnoreTargets boolean - if true, characters are passed through (used by the
		              server to get the "world only" path for claim validation)
]]
function Ballistics.Simulate(params)
	local stats = params.Stats
	local exclude = table.clone(params.Exclude or {})

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = exclude
	raycastParams.IgnoreWater = true

	local pos = params.Origin
	local dir = params.Direction.Unit
	local remaining = Config.Weapon.MaxRange
	local ghostLeft = stats.GhostWalls or 0
	local bouncesLeft = stats.Bounces or 0
	local homing = stats.Homing and params.HomingTargets and #params.HomingTargets > 0
	local homingStep = Config.PowerUps.HomingRounds.StepLength
	local homingRadius = stats.HomingRadius or 0
	local homingTurn = math.rad(stats.HomingTurn or 0)

	local result = { Segments = {}, Passes = {}, Impacts = {}, Hit = nil }
	local segStart = pos
	local segKind = "Normal"
	local hops = 0 -- bounces + wall passes so far (Pinball damage)

	local function closeSegment(toPos)
		table.insert(result.Segments, { From = segStart, To = toPos, Kind = segKind, Hops = hops })
		segStart = toPos
	end

	-- surfaces the bullet touched (Shrapnel sprays shards from these)
	local function addImpact(position, normal, direction)
		table.insert(result.Impacts, { Position = position, Normal = normal, Direction = direction })
	end

	for _ = 1, MAX_ITERATIONS do
		if remaining <= 0.01 then
			break
		end
		local stepLength = homing and math.min(homingStep, remaining) or remaining
		local ray = workspace:Raycast(pos, dir * stepLength, raycastParams)

		if not ray then
			-- No hit this step: advance, and maybe curve toward a target.
			local newPos = pos + dir * stepLength
			remaining -= stepLength
			if homing then
				local newDir = dir
				for _, target in ipairs(params.HomingTargets) do
					local toTarget = target - newPos
					local closeEnough = Util.distanceToSegment(target, pos, newPos + dir * homingStep) <= homingRadius
					if closeEnough and toTarget.Magnitude > 0.5 and toTarget.Unit:Dot(dir) > 0.2 then
						newDir = rotateToward(dir, toTarget.Unit, homingTurn)
						break
					end
				end
				if newDir ~= dir then
					closeSegment(newPos)
					dir = newDir
				end
			end
			pos = newPos
			continue
		end

		local hitPos = ray.Position
		remaining -= (hitPos - pos).Magnitude
		local targetModel = findTargetModel(ray.Instance)

		if targetModel then
			if params.IgnoreTargets then
				-- World-only trace: walk through characters.
				table.insert(exclude, targetModel)
				raycastParams.FilterDescendantsInstances = exclude
				pos = hitPos
				continue
			end
			closeSegment(hitPos)
			result.Hit = {
				Part = ray.Instance,
				Position = hitPos,
				Normal = ray.Normal,
				Model = targetModel,
				Hops = hops,
			}
			result.EndPosition = hitPos
			result.EndNormal = ray.Normal
			return result
		end

		if ghostLeft > 0 then
			-- Ghost Round: ignore this wall and keep going in a straight line.
			ghostLeft -= 1
			table.insert(exclude, ray.Instance)
			raycastParams.FilterDescendantsInstances = exclude
			table.insert(result.Passes, hitPos)
			addImpact(hitPos, ray.Normal, dir)
			closeSegment(hitPos)
			hops += 1
			pos = hitPos
		elseif bouncesLeft > 0 then
			-- Ricochet: reflect off the surface.
			bouncesLeft -= 1
			closeSegment(hitPos)
			segKind = "Bounce"
			hops += 1
			local n = ray.Normal
			dir = (dir - 2 * dir:Dot(n) * n).Unit
			addImpact(hitPos, n, dir)
			pos = hitPos + n * 0.05
			segStart = pos
		else
			closeSegment(hitPos)
			addImpact(hitPos, ray.Normal, (dir - 2 * dir:Dot(ray.Normal) * ray.Normal).Unit)
			result.EndPosition = hitPos
			result.EndNormal = ray.Normal
			return result
		end
	end

	closeSegment(pos)
	result.EndPosition = pos
	return result
end

-- Closest point on a simulated path to `point`, plus the distance and the
-- number of hops (bounces / wall passes) the bullet had made by then.
function Ballistics.ClosestOnPath(sim, point)
	local bestDistance, bestPoint, bestHops = math.huge, nil, 0
	for _, seg in ipairs(sim.Segments) do
		local ab = seg.To - seg.From
		local len2 = ab:Dot(ab)
		local t = len2 > 1e-6 and math.clamp((point - seg.From):Dot(ab) / len2, 0, 1) or 0
		local closest = seg.From + ab * t
		local distance = (point - closest).Magnitude
		if distance < bestDistance then
			bestDistance, bestPoint, bestHops = distance, closest, seg.Hops or 0
		end
	end
	return bestPoint, bestDistance, bestHops
end

-- Shortest distance from a point to any segment of a simulated path.
function Ballistics.DistanceToPath(sim, point)
	local best = math.huge
	for _, seg in ipairs(sim.Segments) do
		best = math.min(best, Util.distanceToSegment(point, seg.From, seg.To))
	end
	return best
end

return Ballistics
