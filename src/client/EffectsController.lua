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
		            wallhack pulse, Bullet Time / Phantom Step tints

	Local effects live in a folder inside the camera so they never block
	bullets or movement raycasts.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
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

-- A glowing tracer line from a to b (thin hot core + soft outer glow).
local function tracer(a, b, color, thickness, life)
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	local cf = CFrame.lookAt((a + b) / 2, b)
	local core = fxPart(Vector3.new(thickness, thickness, length), cf, color:Lerp(Color3.new(1, 1, 1), 0.4), nil, true)
	fadeOut(core, life, { Size = Vector3.new(0.02, 0.02, length) })
	local glow = fxPart(Vector3.new(thickness * 3.5, thickness * 3.5, length), cf, color, nil, true)
	glow.Transparency = 0.82
	fadeOut(glow, life * 0.6)
end

-- A glowing ball that flies along a path (the "bullet").
local function bulletHead(points, color)
	if #points < 2 then
		return
	end
	local head = fxPart(Vector3.new(0.35, 0.35, 2.2), CFrame.lookAt(points[1], points[2]), color, nil, true)
	task.spawn(function()
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local time = math.min((b - a).Magnitude / 1400, 0.4)
			head.CFrame = CFrame.lookAt(a, b)
			local tween = TweenService:Create(head, TweenInfo.new(time, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(b, b + (b - a)) })
			tween:Play()
			tween.Completed:Wait()
		end
		head:Destroy()
	end)
end

local function puff(position, color, size, life, glow)
	local ball = fxPart(Vector3.one * size, CFrame.new(position), color, Enum.PartType.Ball, glow)
	ball.Transparency = 0.15
	fadeOut(ball, life, { Size = Vector3.one * size * 3 })
end

local function ring(position, color, radius, life, glow)
	local disc = fxPart(
		Vector3.new(0.3, 2, 2),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder,
		glow
	)
	disc.Transparency = 0.25
	fadeOut(disc, life, { Size = Vector3.new(0.1, radius * 2, radius * 2) }, Enum.EasingStyle.Quint)
end

----------------------------------------------------------------------------
-- Shots
----------------------------------------------------------------------------

--[[
	Draws one bullet path.
	segments  list of { From, To, Kind }   (from Ballistics)
	passes    points where the bullet went through a wall (Ghost Round)
	startPos  where the tracer visually starts (gun muzzle)
	options   { Explosive = bool, HitPlayer = bool }
]]
function Effects.DrawShot(segments, passes, endPosition, endNormal, startPos, options)
	options = options or {}
	local headPoints = {}
	for i, seg in ipairs(segments) do
		local from = seg.From
		if i == 1 and startPos then
			from = startPos
		end
		table.insert(headPoints, from)
		local color = Palette.Tracer
		local thickness = 0.1
		if seg.Kind == "Bounce" then
			color = Palette.TracerBounce
			thickness = 0.16
		elseif options.Explosive then
			color = Palette.TracerExplosive
		end
		tracer(from, seg.To, color, thickness, seg.Kind == "Bounce" and 0.7 or 0.5)
		-- ricochet flash
		if segments[i + 1] and segments[i + 1].Kind == "Bounce" and (segments[i + 1].Hops or 0) > (seg.Hops or 0) then
			puff(seg.To, Palette.TracerBounce, 0.9, 0.3, true)
			emit(seg.To, "Sparks", Palette.TracerBounce, 10)
			lightFlash(seg.To, Palette.TracerBounce, 3, 10, 0.2)
		end
	end
	if #segments > 0 then
		table.insert(headPoints, segments[#segments].To)
		bulletHead(headPoints, options.Explosive and Palette.TracerExplosive or Palette.Tracer)
	end
	for _, p in ipairs(passes or {}) do
		puff(p, Palette.Hologram, 1.4, 0.4, true)
		emit(p, "Dust", Palette.Light, 6)
	end
	if endPosition then
		if options.HitPlayer then
			emit(endPosition, "Sparks", Color3.fromRGB(255, 120, 120), 16)
			lightFlash(endPosition, Color3.fromRGB(255, 120, 120), 3, 10, 0.2)
		else
			-- impact on the world: sparks bouncing off the surface + a dust puff
			emit(endPosition, "Sparks", Color3.fromRGB(255, 220, 160), 12, endNormal)
			emit(endPosition, "Dust", Palette.Light, 4)
			puff(endPosition, Palette.Tracer, 0.5, 0.2, true)
			lightFlash(endPosition, Color3.fromRGB(255, 220, 170), 2, 8, 0.15)
		end
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
	lightFlash(position, Palette.MuzzleFlash, 6, 16, 0.08)
	emit(position, "Smoke", Color3.fromRGB(220, 220, 225), 3, direction)
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
		})
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
		shatter(data.Position, data.Color or Palette.PlayerB, data.Headshot)
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
end

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
end

return Effects
