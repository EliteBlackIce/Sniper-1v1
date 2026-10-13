--[[
	EffectsController.lua  (Client.EffectsController)

	All local visual effects (flat-coloured parts that fade out):
		* bullet tracers (yours + the enemy's), bright teal after a ricochet
		* impact puffs, ghost-round wall passes
		* explosions, shockwave rings, decoy pops, Second Wind flash
		* grapple ropes (yours and the enemy's)
		* Wallhack Pulse highlight on the enemy
		* Bullet Time and Phantom Dash screen tints

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
local player = Players.LocalPlayer

local Effects = {}
local Controllers

local folder
local localRope = { Point = nil, Part = nil }
local enemyRopes = {} -- [userId] = { Point, Part }
local bulletTimeCC
local bulletTimeOn = false

----------------------------------------------------------------------------
-- Helpers
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

local function flatPart(size, cf, color, shape)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cf
	part.Color = color
	if shape then
		part.Shape = shape
	end
	part.Parent = getFolder()
	return part
end

local function fadeOut(part, time, extraGoals)
	local goals = { Transparency = 1 }
	if extraGoals then
		for k, v in pairs(extraGoals) do
			goals[k] = v
		end
	end
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
	Debris:AddItem(part, time + 0.1)
end

-- A tracer line from a to b (a thin core plus a softer outer glow).
local function tracer(a, b, color, thickness, life)
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	local cf = CFrame.lookAt((a + b) / 2, b)
	local core = flatPart(Vector3.new(thickness, thickness, length), cf, color)
	core.Transparency = 0.05
	fadeOut(core, life, { Size = Vector3.new(thickness * 0.3, thickness * 0.3, length) })
	local glow = flatPart(Vector3.new(thickness * 3, thickness * 3, length), cf, color)
	glow.Transparency = 0.75
	fadeOut(glow, life * 0.7)
end

local function puff(position, color, size, life)
	local ball = flatPart(Vector3.one * size, CFrame.new(position), color, Enum.PartType.Ball)
	ball.Transparency = 0.2
	fadeOut(ball, life, { Size = Vector3.one * size * 3 })
end

local function ring(position, color, radius, life)
	local disc = flatPart(
		Vector3.new(0.4, 2, 2),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
	disc.Transparency = 0.3
	fadeOut(disc, life, { Size = Vector3.new(0.2, radius * 2, radius * 2) })
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
	for i, seg in ipairs(segments) do
		local from = seg.From
		if i == 1 and startPos then
			from = startPos
		end
		local color = Palette.Tracer
		local thickness = 0.12
		if seg.Kind == "Bounce" then
			color = Palette.TracerBounce
			thickness = 0.2
		elseif options.Explosive then
			color = Palette.TracerExplosive
		end
		tracer(from, seg.To, color, thickness, seg.Kind == "Bounce" and 0.7 or 0.45)
		if seg.Kind == "Bounce" or (segments[i + 1] and segments[i + 1].Kind == "Bounce" and seg.Kind ~= "Bounce") then
			puff(seg.To, Palette.TracerBounce, 0.8, 0.35)
		end
	end
	for _, p in ipairs(passes or {}) do
		puff(p, Palette.Hologram, 1.4, 0.4)
	end
	if endPosition and not options.HitPlayer then
		puff(endPosition, Palette.Mid, 0.7, 0.35)
	end
end

-- Enemy shot from the server: start tracers at their gun's muzzle.
local function onEnemyShot(userId, bullets, explosive)
	local shooter = Players:GetPlayerByUserId(userId)
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
		puff(muzzle, Palette.Tracer, 0.6, 0.15)
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
		rope.Part = flatPart(Vector3.new(0.1, 0.1, 1), CFrame.identity, Palette.Grapple)
	end
	local length = (rope.Point - fromPos).Magnitude
	rope.Part.Size = Vector3.new(0.1, 0.1, length)
	rope.Part.CFrame = CFrame.lookAt((rope.Point + fromPos) / 2, rope.Point)
end

function Effects.SetLocalGrapple(point)
	localRope.Point = point
	if point then
		puff(point, Palette.Grapple, 1, 0.3)
	else
		updateRope(localRope, nil)
	end
end

----------------------------------------------------------------------------
-- Screen tints
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
	puff(from, Palette.Hologram, 3, 0.35)
	puff(to, Color3.fromRGB(190, 160, 255), 3.5, 0.4)
	tracer(from, to, Color3.fromRGB(190, 160, 255), 0.5, 0.35)
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
	TweenService:Create(cc, TweenInfo.new(math.max(ClientState.Stats.PhantomTime, 0.3)), {
		TintColor = Color3.new(1, 1, 1),
		Saturation = 0,
	}):Play()
	Debris:AddItem(cc, math.max(ClientState.Stats.PhantomTime, 0.3) + 0.1)
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
		local ball = flatPart(Vector3.one * 2, CFrame.new(data.Position), Palette.Explosion, Enum.PartType.Ball)
		ball.Transparency = 0.1
		fadeOut(ball, 0.45, { Size = Vector3.one * radius * 2 })
		puff(data.Position, Color3.new(1, 1, 1), 2, 0.25)
		Sfx.PlayAt("Explosion", data.Position)
		local camera = workspace.CurrentCamera
		local distance = (camera.CFrame.Position - data.Position).Magnitude
		if distance < radius * 3 then
			Controllers.Camera.Shake(4 * (1 - distance / (radius * 3)))
		end
	elseif t == "Shockwave" then
		ring(data.Position - Vector3.new(0, 2.5, 0), Palette.AccentB, data.Radius or 20, 0.5)
		Sfx.PlayAt("Explosion", data.Position, { Pitch = 0.6 })
	elseif t == "DecoyPop" then
		puff(data.Position, Palette.Hologram, 3, 0.4)
	elseif t == "SecondWind" then
		if data.Position then
			puff(data.Position, Color3.fromRGB(90, 230, 140), 4, 0.6)
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
			tracer(seg.From, seg.To, Palette.TracerExplosive, 0.06, 0.3)
			puff(seg.To, Palette.TracerExplosive, 0.35, 0.25)
		end
		Sfx.PlayAt("Hit", data.Segments[1] and data.Segments[1].From or Vector3.zero, { Pitch = 2.2, Volume = 0.4 })
	elseif t == "Zap" then
		-- STATIC CHARGE: a jagged bolt from the bullet path to the target
		local points = { data.From }
		for i = 1, 3 do
			local p = data.From:Lerp(data.To, i / 4)
			table.insert(points, p + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6)
		end
		table.insert(points, data.To)
		for i = 1, #points - 1 do
			tracer(points[i], points[i + 1], Palette.Hologram, 0.12, 0.3)
		end
		puff(data.To, Palette.Hologram, 1.2, 0.3)
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

local function updateRopes()
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
		local other = Players:GetPlayerByUserId(userId)
		local hand = other and other.Character and (other.Character:FindFirstChild("LeftHand") or other.Character:FindFirstChild("Left Arm"))
		updateRope(rope, hand and hand.Position or nil)
	end
end

function Effects.Init(controllers)
	Controllers = controllers
end

function Effects.Start()
	Remotes.Get("ShotFx").OnClientEvent:Connect(onEnemyShot)
	Remotes.Get("Effect").OnClientEvent:Connect(onEffect)
	RunService:BindToRenderStep("SniperEffects", Enum.RenderPriority.Camera.Value + 3, updateRopes)
	task.spawn(wallhackLoop)
end

return Effects
