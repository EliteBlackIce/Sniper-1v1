--[[
	EffectsController.lua  (Client.EffectsController)

	All local visual effects. Effects are built from glowing flat parts
	(Neon, so they bloom), Roblox's built-in particle textures (sparks and
	smoke) and short light flashes. Everything can be toned down in
	Config.Effects.

		shots       glowing tracers with a travelling bullet head, muzzle flash
		            light, impact sparks + smoke + light, ricochet / ghost marks
		explosions  fireball, shockwave ring, sparks, smoke, light, camera shake
		kills       the body shatters into flat shards, headshots get a red burst
		movement    landing dust ring, jump puff, slide dust
		powers      shrapnel, static zaps, blink trail, grapple rope, marks,
		            wallhack pulse, Bullet Time / Phantom Step tints,
		            acid pools, frost / bleed on the target, sonar reveals,
		            recall + air dash trails, smoke throws (and the fog you
		            see from inside a smoke cloud), barrier domes going up

	Local effects live in a folder inside the camera so they never block
	bullets or movement raycasts.

	Short-lived glow parts (tracers, puffs, rings, bullet heads, impact
	marks) come from a small part pool instead of being created and
	destroyed every shot.

	Extra toggles read from Config.Effects (all default on): ImpactMarks
	(scorch + ember where a bullet hits the world), NearMiss (a whizz and a
	tiny shake when an enemy bullet passes close to your head).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)

local Palette = Config.Palette
local FX = Config.Effects
local player = Players.LocalPlayer

local Effects = {}
local Controllers

local folder
local localRope = { Point = nil, Part = nil }
local enemyRopes = {} -- [userId] = { Point, Part }
local bulletTimeCC
local bulletTimeOn = false
local acidPools = {} -- [id] = the pool's parts (Acid Rounds)
local smokeCC, smokeBlur -- the fog inside a smoke cloud
local smokeFog = 0

----------------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------------
local function getFolder()
	local camera = workspace.CurrentCamera
	if not folder or folder.Parent ~= camera then
		folder = Instance.new("Folder")
		folder.Name = "LocalEffects"
		folder.Parent = camera
	end
	return folder
end

-- An effect part. `glow` = Neon (blooms) when Config.Effects.NeonEffects is on.
local function fxPart(size, cf, color, shape, glow)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = (glow and FX.NeonEffects) and Enum.Material.Neon or Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cf
	part.Color = color
	if shape then
		part.Shape = shape
	end
	part.Parent = getFolder()
	return part
end

local function fadeOut(part, time, extraGoals, style)
	local goals = { Transparency = 1 }
	if extraGoals then
		for k, v in pairs(extraGoals) do
			goals[k] = v
		end
	end
	TweenService:Create(part, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
	Debris:AddItem(part, time + 0.1)
end

-- An invisible anchor at a world position (for particles, lights, sounds).
local function anchorAt(position, life)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	Debris:AddItem(attachment, life or 3)
	return attachment
end

--[[
	Particle burst using Roblox's built-in textures.
	kind: "Sparks" | "Smoke" | "Dust"
]]
local function emit(position, kind, color, count, direction)
	if not FX.Particles or count <= 0 then
		return
	end
	local attachment = anchorAt(position, 3)
	if direction and direction.Magnitude > 0.01 then
		attachment.WorldCFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(-math.pi / 2, 0, 0)
	end
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Color = ColorSequence.new(color)
	e.LightInfluence = 0
	if kind == "Sparks" then
		e.Texture = FX.SparkTexture
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
		e.Speed = NumberRange.new(18, 42)
		e.Lifetime = NumberRange.new(0.15, 0.4)
		e.SpreadAngle = direction and Vector2.new(55, 55) or Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, -60, 0)
		e.Drag = 3
	elseif kind == "Fire" then
		e.Texture = "rbxasset://textures/particles/fire_main.dds"
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Speed = NumberRange.new(4, 12)
		e.Lifetime = NumberRange.new(0.4, 0.9)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Acceleration = Vector3.new(0, 14, 0)
		e.Drag = 1.5
	else -- Smoke / Dust
		e.Texture = FX.SmokeTexture
		e.LightEmission = 0
		local big = kind == "Smoke" and 3.5 or 2.2
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, big * 0.4), NumberSequenceKeypoint.new(1, big) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Speed = NumberRange.new(2, kind == "Smoke" and 8 or 5)
		e.Lifetime = NumberRange.new(0.5, 1.1)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-40, 40)
		e.Drag = 2
	end
	e.Parent = attachment
	e:Emit(count)
end

-- A brief point-light flash (looks great with Future lighting).
local function lightFlash(position, color, brightness, range, time)
	if not FX.Lights then
		return
	end
	local attachment = anchorAt(position, time + 0.2)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = attachment
	TweenService:Create(light, TweenInfo.new(time, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
end

--[[
	Part pool for short-lived effect parts. Only used by the local helpers
	below (tracer / bulletHead / puff / ring / impactMark), which never hand
	their parts to anyone else, so a part can't be reused while still in use.
]]
local POOL_MAX = 48 -- per shape
local partPool = {} -- [shapeName] = { Part }
local function acquire(size, cf, color, shape, glow)
	local key = shape and shape.Name or "Block"
	local list = partPool[key]
	local part = list and table.remove(list)
	if not part then
		part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		if shape then
			part.Shape = shape
		end
	end
	part.Material = (glow and FX.NeonEffects) and Enum.Material.Neon or Enum.Material.SmoothPlastic
	part.Transparency = 0
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Parent = getFolder()
	return part
end

local function release(part, key)
	local list = partPool[key]
	if not list then
		list = {}
		partPool[key] = list
	end
	if table.find(list, part) then
		return -- already back
	end
	-- (a part whose folder was destroyed with an old camera can't be reparented)
	if #list >= POOL_MAX or part.Parent == nil then
		part:Destroy()
		return
	end
	part.Parent = nil
	table.insert(list, part)
end

-- fadeOut for pooled parts: back to the pool instead of Destroy.
local function fadePooled(part, time, extraGoals, style, delayTime)
	local goals = { Transparency = 1 }
	if extraGoals then
		for k, v in pairs(extraGoals) do
			goals[k] = v
		end
	end
	local key = part.Shape.Name
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delayTime or 0)
	TweenService:Create(part, info, goals):Play()
	task.delay(time + (delayTime or 0) + 0.05, release, part, key)
end

-- A glowing tracer line from a to b (thin hot core + soft outer glow).
local function tracer(a, b, color, thickness, life)
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	local cf = CFrame.lookAt((a + b) / 2, b)
	local core = acquire(Vector3.new(thickness, thickness, length), cf, color:Lerp(Color3.new(1, 1, 1), 0.4), nil, true)
	fadePooled(core, life, { Size = Vector3.new(0.02, 0.02, length) })
	local glow = acquire(Vector3.new(thickness * 3.5, thickness * 3.5, length), cf, color, nil, true)
	glow.Transparency = 0.82
	fadePooled(glow, life * 0.6)
end

-- A glowing ball that flies along a path (the "bullet").
local function bulletHead(points, color)
	if #points < 2 then
		return
	end
	local head = acquire(Vector3.new(0.35, 0.35, 2.2), CFrame.lookAt(points[1], points[2]), color, nil, true)
	task.spawn(function()
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			if (b - a).Magnitude > 0.01 then
				local time = math.min((b - a).Magnitude / 1400, 0.4)
				head.CFrame = CFrame.lookAt(a, b)
				local tween = TweenService:Create(head, TweenInfo.new(time, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(b, b + (b - a)) })
				tween:Play()
				tween.Completed:Wait()
			end
		end
		release(head, "Block")
	end)
end

local function puff(position, color, size, life, glow)
	local ball = acquire(Vector3.one * size, CFrame.new(position), color, Enum.PartType.Ball, glow)
	ball.Transparency = 0.15
	fadePooled(ball, life, { Size = Vector3.one * size * 3 })
end

local function ring(position, color, radius, life, glow)
	local disc = acquire(
		Vector3.new(0.3, 2, 2),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder,
		glow
	)
	disc.Transparency = 0.25
	fadePooled(disc, life, { Size = Vector3.new(0.1, radius * 2, radius * 2) }, Enum.EasingStyle.Quint)
end

-- Where a bullet hits the world: a dark scorch that lingers, a hot ember
-- that cools in a moment, and a small ring along the surface.
local function impactMark(position, normal)
	if FX.ImpactMarks == false or typeof(normal) ~= "Vector3" or normal.Magnitude < 0.5 then
		return
	end
	normal = normal.Unit
	-- a cylinder's axis is its X: point X along the surface normal
	local up = math.abs(normal.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local basis = CFrame.fromMatrix(position + normal * 0.03, normal, up:Cross(normal).Unit)
	local spin = CFrame.Angles(math.random() * math.pi * 2, 0, 0)
	local scorch = acquire(Vector3.new(0.04, 0.7, 0.7), basis * spin, Color3.fromRGB(28, 28, 32), Enum.PartType.Cylinder, false)
	scorch.Transparency = 0.15
	fadePooled(scorch, 1.2, nil, Enum.EasingStyle.Quad, 3)
	local ember = acquire(Vector3.new(0.05, 0.42, 0.42), basis * CFrame.new(0.01, 0, 0), Color3.fromRGB(255, 160, 70), Enum.PartType.Cylinder, true)
	fadePooled(ember, 0.6, { Size = Vector3.new(0.05, 0.18, 0.18), Color = Color3.fromRGB(120, 40, 20) })
	local wave = acquire(Vector3.new(0.05, 0.5, 0.5), basis, Color3.fromRGB(255, 235, 200), Enum.PartType.Cylinder, true)
	wave.Transparency = 0.4
	fadePooled(wave, 0.25, { Size = Vector3.new(0.05, 2.6, 2.6) }, Enum.EasingStyle.Quint)
end

----------------------------------------------------------------------------
-- Shots
----------------------------------------------------------------------------

--[[
	Draws one bullet path.
	segments  list of { From, To, Kind }   (from Ballistics)
	passes    points where the bullet went through a wall (Ghost Round)
	startPos  where the tracer visually starts (gun muzzle)
	options   { Explosive = bool, HitPlayer = bool, Tracer = Color3 (the shooter's tracer cosmetic),
	            Owned = { [powerUpId] = stacks } (the shooter's power-ups: PowerFx
	            restyles the shot), Shooter = Model, Charged = bool (Deadeye) }
]]
function Effects.DrawShot(segments, passes, endPosition, endNormal, startPos, options)
	options = options or {}
	local powerFx = Controllers and Controllers.PowerFx
	if powerFx and options.Owned then
		options.Tracer = powerFx.TracerColor(options.Owned, options) or options.Tracer
	end
	local headPoints = {}
	for i, seg in ipairs(segments) do
		local from = seg.From
		if i == 1 and startPos then
			from = startPos
		end
		table.insert(headPoints, from)
		local color = options.Tracer or Palette.Tracer
		local thickness = options.Enemy and 0.13 or 0.1 -- enemy shots read a bit stronger
		if seg.Kind == "Bounce" then
			color = Palette.TracerBounce
			thickness = 0.16
		elseif options.Explosive then
			color = Palette.TracerExplosive
		end
		tracer(from, seg.To, color, thickness, (seg.Kind == "Bounce" and 0.7 or 0.5) * (options.Enemy and 1.25 or 1))
		-- ricochet flash
		if segments[i + 1] and segments[i + 1].Kind == "Bounce" and (segments[i + 1].Hops or 0) > (seg.Hops or 0) then
			puff(seg.To, Palette.TracerBounce, 0.9, 0.3, true)
			emit(seg.To, "Sparks", Palette.TracerBounce, 10)
			lightFlash(seg.To, Palette.TracerBounce, 3, 10, 0.2)
		end
	end
	if #segments > 0 then
		table.insert(headPoints, segments[#segments].To)
		bulletHead(headPoints, options.Explosive and Palette.TracerExplosive or options.Tracer or Palette.Tracer)
	end
	for _, p in ipairs(passes or {}) do
		puff(p, Palette.Hologram, 1.4, 0.4, true)
		emit(p, "Dust", Palette.Light, 6)
	end
	if endPosition then
		if options.HitPlayer then
			emit(endPosition, "Sparks", Color3.fromRGB(255, 120, 120), 16)
			puff(endPosition, Color3.fromRGB(255, 90, 100), 0.7, 0.18, true)
			lightFlash(endPosition, Color3.fromRGB(255, 120, 120), 3, 10, 0.2)
		else
			-- impact on the world: sparks bouncing off the surface + a dust puff
			emit(endPosition, "Sparks", Color3.fromRGB(255, 220, 160), 12, endNormal)
			emit(endPosition, "Dust", Palette.Light, 4)
			puff(endPosition, Palette.Tracer, 0.5, 0.2, true)
			lightFlash(endPosition, Color3.fromRGB(255, 220, 170), 2, 8, 0.15)
			impactMark(endPosition, endNormal)
		end
	end
	if powerFx and options.Owned then
		powerFx.DecorateShot(segments, endPosition, endNormal, startPos, options)
	end
end

-- Muzzle flash light + smoke at a world position (your own gun or theirs).
-- Knife hits: sparks off a wall, a red burst on a body.
function Effects.KnifeImpact(position, normal, flesh)
	if flesh then
		emit(position, "Sparks", Color3.fromRGB(255, 70, 80), 14, normal)
		puff(position, Color3.fromRGB(255, 90, 100), 0.5, 0.18, true)
	else
		emit(position, "Sparks", Color3.fromRGB(255, 236, 190), 10, normal)
		lightFlash(position, Color3.fromRGB(255, 230, 180), 2, 8, 0.12)
	end
end

function Effects.MuzzleFlash(position, direction)
	if typeof(position) ~= "Vector3" then
		return
	end
	lightFlash(position, Palette.MuzzleFlash, 6, 16, 0.08)
	emit(position, "Smoke", Color3.fromRGB(220, 220, 225), 3, direction)
	if typeof(direction) == "Vector3" and direction.Magnitude > 0.01 then
		-- a quick hot cone of flash just past the muzzle
		puff(position + direction.Unit * 0.6, Palette.MuzzleFlash, 0.45, 0.06, true)
	end
end

-- Closest point on segment a-b to p.
local function closestOnSegment(a, b, p)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return a
	end
	return a + ab * math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
end

-- An enemy bullet that passed close to your head (and didn't hit you):
-- a whizz from where it passed and a tiny shake. Tension!
local lastNearMiss = 0
local function nearMiss(bullets)
	if FX.NearMiss == false or not ClientState.InMatch() then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or os.clock() - lastNearMiss < 0.2 then
		return
	end
	local eye = camera.CFrame.Position
	local best, bestPoint = 7, nil
	for _, bullet in ipairs(bullets) do
		if not bullet.HitPlayer then
			for _, seg in ipairs(bullet.Segments or {}) do
				if typeof(seg.From) == "Vector3" and typeof(seg.To) == "Vector3" then
					local point = closestOnSegment(seg.From, seg.To, eye)
					local d = (point - eye).Magnitude
					-- (ignore the very end: that's a bullet that hit the wall next to you)
					if d < best and (point - seg.To).Magnitude > 1 then
						best, bestPoint = d, point
					end
				end
			end
		end
	end
	if bestPoint then
		lastNearMiss = os.clock()
		local k = 1 - best / 7
		Sfx.PlayAt("NearMiss", bestPoint, { Volume = 0.6 + k * 0.8, Vary = 0.08 })
		if Controllers and Controllers.Camera then
			Controllers.Camera.Shake(0.4 + k * 0.8)
		end
	end
end

-- Enemy shot from the server: start tracers at their gun's muzzle.
local function onEnemyShot(userId, bullets, explosive)
	local shooter = ClientState.FindPlayer(userId)
	local character = shooter and shooter.Character
	local muzzleAttachment = character
		and character:FindFirstChild("WorldGun")
		and character.WorldGun:FindFirstChild("Barrel")
		and character.WorldGun.Barrel:FindFirstChild("Muzzle")
	local muzzle = muzzleAttachment and muzzleAttachment.WorldPosition
	for _, bullet in ipairs(bullets) do
		Effects.DrawShot(bullet.Segments, bullet.Passes, bullet.EndPosition, bullet.EndNormal, muzzle, {
			Explosive = explosive,
			HitPlayer = bullet.HitPlayer,
			Tracer = Cosmetics.TracerColor(shooter),
			Enemy = true,
			Owned = Controllers.PowerFx and Controllers.PowerFx.OwnedOf(character) or nil,
			Shooter = character,
		})
	end
	if typeof(bullets) == "table" and userId ~= player.UserId then
		nearMiss(bullets)
	end
	if muzzleAttachment then
		Sfx.Play("Fire", { Parent = muzzleAttachment, Volume = 1.4 })
		puff(muzzle, Palette.MuzzleFlash, 0.9, 0.12, true)
		Effects.MuzzleFlash(muzzle)
	end
end

----------------------------------------------------------------------------
-- Kills: the body shatters into flat shards
----------------------------------------------------------------------------
local function shatter(position, color, headshot)
	if not FX.KillShatter then
		return
	end
	puff(position, Color3.new(1, 1, 1), 3, 0.35, true)
	lightFlash(position, Color3.new(1, 1, 1), 4, 18, 0.3)
	emit(position, "Sparks", color, 24)
	for _ = 1, 14 do
		local size = 0.5 + math.random() * 0.8
		local shard = Instance.new("Part")
		shard.Size = Vector3.new(size, size, size)
		shard.CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, math.random() * 2 - 1, math.random() - 0.5) * 2)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		shard.Color = color
		shard.Material = Enum.Material.SmoothPlastic
		shard.CanCollide = true
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = true
		-- in workspace.Effects (ignored by bullets + movement) so physics runs
		shard.Parent = workspace:FindFirstChild("Effects") or getFolder()
		shard.AssemblyLinearVelocity = Vector3.new(math.random() - 0.5, 0.6 + math.random(), math.random() - 0.5).Unit
			* (25 + math.random() * 30)
		shard.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		task.delay(1.4, function()
			if shard.Parent then
				fadeOut(shard, 0.6, { Size = Vector3.new(0.05, 0.05, 0.05) })
			end
		end)
	end
	if headshot then
		ring(position + Vector3.new(0, 1.5, 0), Palette.UIHeadshot, 7, 0.45, true)
	end
end

-- The killer's kill effect (Config.Cosmetics.KillEffects): data.KillFx is
-- its id; the default is the shatter.
local CONFETTI = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(80, 220, 120),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(200, 100, 255),
}
local function killEffect(data)
	local item = Cosmetics.Get(data.KillFx)
	local style = item and item.Style or "Shatter"
	local position = data.Position
	local color = item and item.Color or data.Color or Palette.PlayerB
	if style == "Shatter" or not FX.KillShatter then
		shatter(position, data.Color or Palette.PlayerB, data.Headshot)
		return
	end
	if data.Headshot then
		ring(position + Vector3.new(0, 1.5, 0), Palette.UIHeadshot, 7, 0.45, true)
	end
	if style == "Confetti" then
		puff(position, Color3.new(1, 1, 1), 2.5, 0.3, true)
		for _, c in ipairs(CONFETTI) do
			emit(position + Vector3.new(0, 1, 0), "Sparks", c, 14)
		end
		Sfx.PlayAt("CardFlip", position, { Pitch = 1.4, Volume = 1.2 })
	elseif style == "Vaporize" then
		puff(position, color, 4.5, 0.5, true)
		puff(position + Vector3.new(0, 2, 0), Color3.new(1, 1, 1), 2.5, 0.35, true)
		emit(position, "Sparks", color, 30)
		emit(position + Vector3.new(0, 2, 0), "Sparks", color, 20)
		lightFlash(position, color, 6, 20, 0.35)
	elseif style == "Flames" then
		emit(position, "Fire", color, 30)
		emit(position, "Sparks", Color3.fromRGB(255, 200, 80), 26)
		puff(position, color, 3.5, 0.45, true)
		lightFlash(position, color, 6, 22, 0.5)
		Sfx.PlayAt("Explosion", position, { Pitch = 1.3, Volume = 0.8 })
	elseif style == "Lightning" then
		local sky = position + Vector3.new(math.random(-4, 4), 60, math.random(-4, 4))
		local last = sky
		for i = 1, 6 do
			local nextPoint = sky:Lerp(position, i / 6) + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * (i < 6 and 6 or 0)
			tracer(last, nextPoint, color, 0.5, 0.35)
			last = nextPoint
		end
		ring(position - Vector3.new(0, 2.5, 0), color, 14, 0.5, true)
		lightFlash(position, color, 10, 40, 0.3)
		emit(position, "Sparks", color, 30)
		Sfx.PlayAt("Explosion", position, { Pitch = 0.7, Volume = 1.2 })
	elseif style == "Void" then
		-- a dark sphere that swallows the body, then collapses
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball
		sphere.Size = Vector3.new(0.5, 0.5, 0.5)
		sphere.CFrame = CFrame.new(position)
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.CanQuery = false
		sphere.CanTouch = false
		sphere.CastShadow = false
		sphere.Color = Color3.fromRGB(8, 4, 16)
		sphere.Material = Enum.Material.SmoothPlastic
		sphere.Parent = workspace:FindFirstChild("Effects") or getFolder()
		TweenService:Create(sphere, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = Vector3.new(7, 7, 7) }):Play()
		task.delay(0.45, function()
			TweenService:Create(sphere, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Size = Vector3.new(0.1, 0.1, 0.1) }):Play()
			task.delay(0.36, function()
				sphere:Destroy()
				ring(position, color, 12, 0.4, true)
				emit(position, "Sparks", color, 24)
			end)
		end)
		ring(position, color, 9, 0.4, true)
		lightFlash(position, color, 5, 18, 0.6)
	else
		shatter(position, data.Color or Palette.PlayerB, data.Headshot)
	end
end

----------------------------------------------------------------------------
-- Movement dust (your own character)
----------------------------------------------------------------------------
local function feetPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and (root.Position - Vector3.new(0, 3, 0)) or nil
end

local function onLanded(fallSpeed)
	local feet = feetPosition()
	if not feet or fallSpeed < 40 then
		return
	end
	local strength = math.clamp((fallSpeed - 40) / 60, 0, 1)
	ring(feet + Vector3.new(0, 0.2, 0), Palette.Light, 4 + strength * 7, 0.45)
	emit(feet, "Dust", Palette.Light, math.floor(4 + strength * 10))
end

local function onJumped()
	local feet = feetPosition()
	if feet then
		emit(feet, "Dust", Palette.Light, 3)
	end
end

local slideDustTimer = 0
local function updateMovementFx(dt)
	if Controllers.Movement.GetMode() ~= "Slide" then
		return
	end
	slideDustTimer += dt
	if slideDustTimer > 0.06 then
		slideDustTimer = 0
		local feet = feetPosition()
		if feet then
			emit(feet, "Dust", Palette.Light, 1)
			emit(feet, "Sparks", Color3.fromRGB(255, 220, 170), 2)
		end
	end
end

----------------------------------------------------------------------------
-- Grapple ropes
----------------------------------------------------------------------------
local function updateRope(rope, fromPos)
	if not rope.Point or not fromPos then
		if rope.Part then
			rope.Part:Destroy()
			rope.Part = nil
		end
		return
	end
	if not rope.Part then
		rope.Part = fxPart(Vector3.new(0.12, 0.12, 1), CFrame.identity, Palette.Grapple, nil, true)
	end
	local length = (rope.Point - fromPos).Magnitude
	rope.Part.Size = Vector3.new(0.12, 0.12, length)
	rope.Part.CFrame = CFrame.lookAt((rope.Point + fromPos) / 2, rope.Point)
end

function Effects.SetLocalGrapple(point)
	localRope.Point = point
	if point then
		puff(point, Palette.Grapple, 1.2, 0.3, true)
		emit(point, "Sparks", Palette.Grapple, 10)
	else
		updateRope(localRope, nil)
	end
end

----------------------------------------------------------------------------
-- Screen tints + power visuals
----------------------------------------------------------------------------
function Effects.SetBulletTime(on)
	bulletTimeOn = on
	if not bulletTimeCC then
		bulletTimeCC = Instance.new("ColorCorrectionEffect")
		bulletTimeCC.Name = "BulletTimeTint"
		bulletTimeCC.Parent = workspace.CurrentCamera
	end
	local goals = on
			and { Saturation = -0.45, Contrast = 0.15, TintColor = Color3.fromRGB(205, 225, 255) }
		or { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }
	TweenService:Create(bulletTimeCC, TweenInfo.new(on and 0.15 or 0.4), goals):Play()
	if on then
		Sfx.Play("Ability", { Pitch = 0.5, Volume = 1.5 })
	end
end

-- BLINK: a flash where you left and where you arrived, joined by a streak.
function Effects.Blink(from, to)
	if not from or not to then
		return
	end
	local color = Color3.fromRGB(190, 160, 255)
	puff(from, Palette.Hologram, 3, 0.35, true)
	puff(to, color, 3.5, 0.4, true)
	tracer(from, to, color, 0.5, 0.4)
	emit(from, "Sparks", Palette.Hologram, 14)
	emit(to, "Sparks", color, 18)
	lightFlash(to, color, 4, 16, 0.3)
	Sfx.PlayAt("Dash", to, { Pitch = 1.6 })
end

function Effects.IsBulletTimeVisible()
	return bulletTimeOn
end

function Effects.PhantomFlash()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(190, 230, 255)
	cc.Saturation = -0.3
	cc.Parent = workspace.CurrentCamera
	local time = math.max(ClientState.Stats.PhantomTime, 0.3)
	TweenService:Create(cc, TweenInfo.new(time), { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
	Debris:AddItem(cc, time + 0.1)
	local feet = feetPosition()
	if feet then
		emit(feet + Vector3.new(0, 2, 0), "Smoke", Palette.Hologram, 6)
	end
end

-- A short full-screen tint that fades out (Frost, Disruptor...).
local function screenTint(color, saturation, time)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = color
	cc.Saturation = saturation or 0
	cc.Parent = workspace.CurrentCamera
	TweenService:Create(cc, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TintColor = Color3.new(1, 1, 1),
		Saturation = 0,
	}):Play()
	Debris:AddItem(cc, time + 0.1)
end

-- A highlight on a model for a while (Frost, Sonar...). `name` replaces an
-- older one of the same kind on the same model.
local tags = { Frost = setmetatable({}, { __mode = "k" }), Sonar = setmetatable({}, { __mode = "k" }) }
local function tagModel(model, name, fill, outline, depthMode, duration)
	if typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	local old = tags[name][model]
	if old then
		old:Destroy()
	end
	local highlight = Instance.new("Highlight")
	tags[name][model] = highlight
	highlight.Name = name
	highlight.DepthMode = depthMode
	highlight.FillColor = fill
	highlight.FillTransparency = 0.5
	highlight.OutlineColor = outline
	highlight.OutlineTransparency = 0
	highlight.Adornee = model
	highlight.Parent = getFolder()
	Debris:AddItem(highlight, duration)
end

local function torsoOf(model)
	return model and (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart"))
end

-- FROST ROUNDS: you've been chilled.
function Effects.Chill(duration)
	screenTint(Color3.fromRGB(170, 215, 255), -0.4, math.max(duration, 0.3))
	Sfx.Play("Hurt", { Pitch = 1.6, Volume = 0.4 })
end

-- DISRUPTOR ROUNDS: your abilities are jammed.
function Effects.Jammed(duration)
	screenTint(Color3.fromRGB(170, 180, 255), -0.6, math.min(duration, 1))
	if Controllers.HUD then
		Controllers.HUD.Flash(Color3.fromRGB(90, 110, 230), "JAMMED")
	end
end

-- AIR DASH: a burst of wind behind you.
function Effects.Dash(position, direction)
	if not position then
		return
	end
	local back = position - (direction or Vector3.zero) * 2
	puff(back, Color3.fromRGB(150, 210, 255), 2.2, 0.3, true)
	emit(back, "Dust", Color3.fromRGB(220, 235, 255), 8, direction and -direction or nil)
end

-- RECALL: a golden streak back to where you were.
function Effects.Recall(from, to)
	if not from or not to then
		return
	end
	local color = Color3.fromRGB(255, 205, 90)
	puff(from, color, 3, 0.45, true)
	puff(to, Color3.fromRGB(255, 240, 190), 3.5, 0.5, true)
	tracer(from, to, color, 0.35, 0.6)
	ring(to - Vector3.new(0, 2.5, 0), color, 6, 0.5, true)
	emit(to, "Sparks", color, 16)
	lightFlash(to, color, 4, 16, 0.35)
	Sfx.PlayAt("Dash", to, { Pitch = 0.75 })
end

-- SMOKE GRENADE: inside a cloud everything turns to grey fog.
local function updateSmokeFog(dt)
	local camera = workspace.CurrentCamera
	if not smokeCC or smokeCC.Parent ~= camera then
		smokeCC = Instance.new("ColorCorrectionEffect")
		smokeCC.Name = "SmokeFog"
		smokeCC.Parent = camera
		smokeBlur = Instance.new("BlurEffect")
		smokeBlur.Name = "SmokeBlur"
		smokeBlur.Size = 0
		smokeBlur.Parent = camera
	end
	local inside = false
	local folder = workspace:FindFirstChild("Smoke")
	if folder then
		local eye = camera.CFrame.Position
		for _, puffPart in ipairs(folder:GetDescendants()) do
			if puffPart:IsA("BasePart") and puffPart.Transparency < 0.7
				and (puffPart.Position - eye).Magnitude < puffPart.Size.X * 0.5 then
				inside = true
				break
			end
		end
	end
	local goal = inside and 1 or 0
	local step = dt * 4
	smokeFog = math.abs(goal - smokeFog) <= step and goal or smokeFog + math.sign(goal - smokeFog) * step
	smokeCC.Brightness = 0.35 * smokeFog
	smokeCC.Contrast = -0.6 * smokeFog
	smokeCC.Saturation = -0.8 * smokeFog
	smokeBlur.Size = 22 * smokeFog
	smokeCC.Enabled = smokeFog > 0
	smokeBlur.Enabled = smokeFog > 0
end

----------------------------------------------------------------------------
-- Wallhack Pulse
----------------------------------------------------------------------------
local function wallhackLoop()
	local elapsed = 0
	while true do
		elapsed += task.wait(0.25)
		-- Wallhack Pulse stacks pulse more often and for longer
		local stats = ClientState.Stats
		if not stats.WallhackPulse then
			elapsed = 0
		elseif elapsed >= stats.WallhackInterval and ClientState.CanShoot() then
			elapsed = 0
			-- the enemy in a match, the practice dummies in the lobby
			local targets = {}
			if ClientState.InMatch() then
				local opponent = ClientState.GetOpponentPlayer()
				table.insert(targets, opponent and opponent.Character)
			else
				local dummies = workspace:FindFirstChild("Dummies")
				for _, dummy in ipairs(dummies and dummies:GetChildren() or {}) do
					table.insert(targets, dummy)
				end
			end
			for _, target in ipairs(targets) do
				local highlight = Instance.new("Highlight")
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.FillColor = Palette.UIDanger
				highlight.FillTransparency = 0.6
				highlight.OutlineColor = Color3.new(1, 1, 1)
				highlight.OutlineTransparency = 0
				highlight.Adornee = target
				highlight.Parent = getFolder()
				Debris:AddItem(highlight, stats.WallhackDuration)
			end
			if #targets > 0 then
				Sfx.Play("Ability", { Pitch = 1.6, Volume = 0.5 })
			end
		end
	end
end

----------------------------------------------------------------------------
-- Server effects
----------------------------------------------------------------------------
local function onEffect(data)
	local t = data.Type
	if t == "Explosion" then
		local radius = data.Radius or 10
		local p = data.Position
		local ball = fxPart(Vector3.one * 2, CFrame.new(p), Palette.Explosion, Enum.PartType.Ball, true)
		ball.Transparency = 0.05
		fadeOut(ball, 0.5, { Size = Vector3.one * radius * 2 }, Enum.EasingStyle.Quint)
		local core = fxPart(Vector3.one * 2, CFrame.new(p), Color3.fromRGB(255, 240, 200), Enum.PartType.Ball, true)
		fadeOut(core, 0.25, { Size = Vector3.one * radius })
		ring(p, Palette.Explosion, radius * 1.4, 0.5, true)
		emit(p, "Sparks", Palette.Explosion, 36)
		emit(p, "Smoke", Color3.fromRGB(90, 92, 100), 14)
		lightFlash(p, Palette.Explosion, 8, radius * 3, 0.45)
		Sfx.PlayAt("Explosion", p)
		local camera = workspace.CurrentCamera
		local distance = (camera.CFrame.Position - p).Magnitude
		if distance < radius * 4 then
			Controllers.Camera.Shake(5 * (1 - distance / (radius * 4)))
		end
	elseif t == "Shockwave" then
		local ground = data.Position - Vector3.new(0, 2.5, 0)
		ring(ground, Palette.AccentB, data.Radius or 20, 0.55, true)
		ring(ground, Color3.new(1, 1, 1), (data.Radius or 20) * 0.6, 0.35, true)
		emit(ground, "Dust", Palette.Light, 18)
		lightFlash(ground, Palette.AccentB, 4, 24, 0.3)
		Sfx.PlayAt("Explosion", data.Position, { Pitch = 0.6 })
	elseif t == "DecoyPop" then
		puff(data.Position, Palette.Hologram, 3, 0.4, true)
		emit(data.Position, "Sparks", Palette.Hologram, 16)
	elseif t == "Kill" then
		killEffect(data)
	elseif t == "SecondWind" then
		if data.Position then
			puff(data.Position, Color3.fromRGB(90, 230, 140), 4, 0.6, true)
			emit(data.Position, "Sparks", Color3.fromRGB(90, 230, 140), 24)
		end
		if data.UserId == player.UserId then
			Controllers.HUD.Flash(Color3.fromRGB(90, 230, 140), "SECOND WIND")
		end
	elseif t == "Grapple" then
		enemyRopes[data.UserId] = enemyRopes[data.UserId] or {}
		enemyRopes[data.UserId].Point = data.Point
	elseif t == "Shards" then
		-- SHRAPNEL
		for _, seg in ipairs(data.Segments or {}) do
			tracer(seg.From, seg.To, Palette.TracerExplosive, 0.05, 0.3)
			emit(seg.To, "Sparks", Palette.TracerExplosive, 3)
		end
		if data.Segments and data.Segments[1] then
			Sfx.PlayAt("Hit", data.Segments[1].From, { Pitch = 2.2, Volume = 0.4 })
		end
	elseif t == "Zap" then
		-- STATIC CHARGE: a jagged bolt from the bullet path to the target
		local points = { data.From }
		for i = 1, 4 do
			local p = data.From:Lerp(data.To, i / 5)
			table.insert(points, p + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.8)
		end
		table.insert(points, data.To)
		for i = 1, #points - 1 do
			tracer(points[i], points[i + 1], Palette.Hologram, 0.12, 0.3)
		end
		puff(data.To, Palette.Hologram, 1.4, 0.3, true)
		emit(data.To, "Sparks", Palette.Hologram, 14)
		lightFlash(data.To, Palette.Hologram, 4, 14, 0.25)
		Sfx.PlayAt("Hit", data.To, { Pitch = 2.6, Volume = 0.6 })
	elseif t == "Mark" then
		-- MARKED: the target glows for you while the mark lasts
		if data.Target and data.Target.Parent then
			local existing = getFolder():FindFirstChild("Mark")
			if existing then
				existing:Destroy()
			end
			local highlight = Instance.new("Highlight")
			highlight.Name = "Mark"
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.FillColor = Color3.fromRGB(255, 80, 80)
			highlight.FillTransparency = 0.55
			highlight.OutlineColor = Color3.fromRGB(255, 220, 220)
			highlight.Adornee = data.Target
			highlight.Parent = getFolder()
			Debris:AddItem(highlight, data.Duration or 4)
		end
	elseif t == "Blink" then
		Effects.Blink(data.From, data.To)
	elseif t == "AcidPool" then
		-- ACID ROUNDS: a bubbling green puddle
		local p, radius = data.Position, data.Radius or 7
		local duration = data.Duration or 3
		local color = Color3.fromRGB(120, 230, 60)
		local disc = fxPart(
			Vector3.new(0.25, radius * 2, radius * 2),
			CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			Enum.PartType.Cylinder,
			true
		)
		disc.Transparency = 0.45
		local rim = fxPart(
			Vector3.new(0.15, radius * 2.15, radius * 2.15),
			CFrame.new(p + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(70, 150, 40),
			Enum.PartType.Cylinder
		)
		rim.Transparency = 0.3
		emit(p + Vector3.new(0, 0.5, 0), "Smoke", color, 6)
		if FX.Particles then
			local attachment = anchorAt(p + Vector3.new(0, 0.3, 0), duration + 1)
			local bubbles = Instance.new("ParticleEmitter")
			bubbles.Texture = FX.SparkTexture
			bubbles.Color = ColorSequence.new(color)
			bubbles.LightEmission = 0.6
			bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			bubbles.Lifetime = NumberRange.new(0.4, 0.8)
			bubbles.Speed = NumberRange.new(2, 5)
			bubbles.SpreadAngle = Vector2.new(25, 25)
			bubbles.Rate = 10 + radius * 2
			bubbles.Shape = Enum.ParticleEmitterShape.Disc
			bubbles.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
			bubbles.Orientation = Enum.ParticleOrientation.FacingCamera
			attachment.WorldCFrame = CFrame.new(p + Vector3.new(0, 0.3, 0))
			bubbles.Parent = attachment
			task.delay(duration, function()
				bubbles.Enabled = false
			end)
		end
		Sfx.PlayAt("Hit", p, { Pitch = 0.6, Volume = 0.5 })
		local parts = { disc, rim }
		if data.Id then
			acidPools[data.Id] = parts
		end
		task.delay(math.max(duration - 0.4, 0), function()
			for _, part in ipairs(parts) do
				if part.Parent then
					fadeOut(part, 0.4)
				end
			end
			if data.Id then
				acidPools[data.Id] = nil
			end
		end)
	elseif t == "AcidPoolEnd" then
		for _, part in ipairs(acidPools[data.Id] or {}) do
			if part.Parent then
				fadeOut(part, 0.3)
			end
		end
		acidPools[data.Id] = nil
	elseif t == "Frost" then
		-- FROST ROUNDS: the target frosts over
		tagModel(data.Target, "Frost", Color3.fromRGB(170, 225, 255), Color3.fromRGB(230, 245, 255), Enum.HighlightDepthMode.Occluded, data.Duration or 1.5)
		local torso = torsoOf(data.Target)
		if torso then
			emit(torso.Position, "Sparks", Color3.fromRGB(190, 235, 255), 18)
			puff(torso.Position, Color3.fromRGB(200, 235, 255), 2.5, 0.35, true)
		end
	elseif t == "Bleed" then
		-- SERRATED ROUNDS: drips while the bleed lasts
		local torso = torsoOf(data.Target)
		if torso and FX.Particles then
			local old = torso:FindFirstChild("BleedFx")
			if old then
				old:Destroy()
			end
			local drips = Instance.new("ParticleEmitter")
			drips.Name = "BleedFx"
			drips.Texture = FX.SparkTexture
			drips.Color = ColorSequence.new(Color3.fromRGB(200, 20, 40))
			drips.LightEmission = 0.2
			drips.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.05) })
			drips.Lifetime = NumberRange.new(0.4, 0.7)
			drips.Speed = NumberRange.new(1, 3)
			drips.SpreadAngle = Vector2.new(60, 60)
			drips.Acceleration = Vector3.new(0, -30, 0)
			drips.Rate = 18
			drips.Parent = torso
			Debris:AddItem(drips, math.clamp(data.Duration or 2.5, 0.3, 8))
		end
	elseif t == "Reveal" then
		-- SONAR: the enemy fired - see them through walls for a moment
		tagModel(data.Target, "Sonar", Color3.fromRGB(60, 230, 190), Color3.new(1, 1, 1), Enum.HighlightDepthMode.AlwaysOnTop, data.Duration or 1.2)
		if data.Position then
			ring(data.Position, Color3.fromRGB(60, 230, 190), 8, 0.6, true)
		end
		Sfx.Play("Ability", { Pitch = 1.9, Volume = 0.45 })
	elseif t == "Recall" then
		Effects.Recall(data.From, data.To)
	elseif t == "Dash" then
		Effects.Dash(data.Position, nil)
		Sfx.PlayAt("Dash", data.Position, { Pitch = 1.45 })
	elseif t == "SmokeThrow" then
		-- SMOKE GRENADE: a quick lob (the cloud itself is built by the server)
		if data.From and data.To then
			local mid = (data.From + data.To) / 2 + Vector3.new(0, math.min((data.To - data.From).Magnitude * 0.25, 20), 0)
			tracer(data.From, mid, Color3.fromRGB(200, 205, 215), 0.18, 0.5)
			tracer(mid, data.To, Color3.fromRGB(200, 205, 215), 0.18, 0.5)
			task.delay(0.35, function()
				emit(data.To + Vector3.new(0, 1, 0), "Smoke", Color3.fromRGB(220, 224, 232), 24)
				Sfx.PlayAt("Explosion", data.To, { Pitch = 1.6, Volume = 0.4 })
			end)
		end
	elseif t == "Barrier" then
		-- BARRIER DOME going up
		local p = data.Position
		if p then
			ring(p - Vector3.new(0, 2.5, 0), Palette.Hologram, (data.Radius or 8) * 1.2, 0.45, true)
			emit(p, "Sparks", Palette.Hologram, 20)
			lightFlash(p, Palette.Hologram, 3, 18, 0.4)
			Sfx.PlayAt("Ability", p, { Pitch = 0.6, Volume = 0.8 })
		end
	elseif t == "GrappleEnd" then
		local rope = enemyRopes[data.UserId]
		if rope then
			rope.Point = nil
			updateRope(rope, nil)
		end
	end
end

local function updateRopes(dt)
	if not ClientState.IsFighting() then
		for _, rope in pairs(enemyRopes) do
			rope.Point = nil
			updateRope(rope, nil)
		end
	end
	if localRope.Point then
		updateRope(localRope, Controllers.Viewmodel.GetLeftHandPosition())
	end
	for userId, rope in pairs(enemyRopes) do
		local other = ClientState.FindPlayer(userId)
		local hand = other and other.Character and (other.Character:FindFirstChild("LeftHand") or other.Character:FindFirstChild("Left Arm"))
		updateRope(rope, hand and hand.Position or nil)
	end
	updateMovementFx(dt)
	updateSmokeFog(dt)
end

-- Legendary skins: their glowing trims pulse between two colours (parts
-- tagged "SkinPulse" by Skins.Apply, with PulseA / PulseB attributes).
local function pulseSkins()
	local k = (math.sin(os.clock() * 3) + 1) / 2
	for _, part in ipairs(CollectionService:GetTagged("SkinPulse")) do
		local a, b = part:GetAttribute("PulseA"), part:GetAttribute("PulseB")
		if part:IsA("BasePart") and typeof(a) == "Color3" and typeof(b) == "Color3" then
			part.Color = a:Lerp(b, k)
		end
	end
end

-- Building blocks for other effect modules (PowerFx).
Effects.Lib = {
	FxPart = fxPart,
	FadeOut = fadeOut,
	Emit = emit,
	LightFlash = lightFlash,
	Tracer = tracer,
	Puff = puff,
	Ring = ring,
	Folder = getFolder,
}

function Effects.Init(controllers)
	Controllers = controllers
end

function Effects.Start()
	Remotes.Get("ShotFx").OnClientEvent:Connect(onEnemyShot)
	Remotes.Get("Effect").OnClientEvent:Connect(onEffect)
	Controllers.Movement.Landed:Connect(onLanded)
	Controllers.Movement.Jumped:Connect(onJumped)
	RunService:BindToRenderStep("SniperEffects", Enum.RenderPriority.Camera.Value + 3, updateRopes)
	task.spawn(wallhackLoop)
	RunService.Heartbeat:Connect(pulseSkins)
end

return Effects
