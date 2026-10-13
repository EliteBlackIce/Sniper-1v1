--[[
	CrateController.lua  (Client.CrateController)

	The crate in the lobby's crate vault, and the opening cinematic.

	Idle: the crate floats over the altar, slowly turning, its glow cycling
	through the rarity colours.

	Opening (when the server sends a result over the "Crates" remote):
	  1. INTRO    the camera swoops in, letterbox bars slide on
	  2. CHARGE   the crate lifts and spins faster and faster, shaking, while
	              sparks get sucked in; its glow climbs the rarity ladder
	              (COMMON > UNCOMMON > ...) and stops on what you got.
	              Secret fakes you out: it stalls on Legendary, goes dark,
	              then cracks red.
	  3. BURST    the lid blasts off, a flash, a pillar of light, a shockwave
	              ring and a shower of sparks in the rarity colour
	  4. REVEAL   the rifle rises out of the crate in the skin's colours and
	              spins while ui/CrateReveal shows the rarity + skin
	Everything is local to you; the roll itself happened on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local CrateModel = require(Shared.CrateModel)
local GunModel = require(Shared.GunModel)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)
local CrateReveal = require(script.Parent.ui.CrateReveal)

local CR = Config.Crates
local player = Players.LocalPlayer

local CrateController = {}
local Controllers

local rarityById, tierOf, skinById = {}, {}, {}
for i, rarity in ipairs(CR.Rarities) do
	rarityById[rarity.Id] = rarity
	tierOf[rarity.Id] = i
end
for _, skin in ipairs(CR.Skins) do
	skinById[skin.Id] = skin
end

local CRATE_SCALE = 1.3
local HOVER = 0.5

local altar, prompt, ring
local crate -- CrateModel table (local to this client)
local idleT = 0
local lastColorSet = 0

-- cinematic state
local playing = false
local scene -- per-opening objects (cleaned up by clearScene)
local saved -- what we changed on the player (restored by finish)
local pendingResult -- a result that arrived while we were busy
local waitingAgain = false
local finishing = false
local againToken = 0

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function ease(x)
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end

local function newPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = props.Parent or workspace
	return part
end

-- flat ring on the floor that grows and fades
local function shockRing(center, color, size, time)
	local part = newPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 1, 1),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	})
	TweenService:Create(part, TweenInfo.new(time or 0.6, Enum.EasingStyle.Quint), {
		Size = Vector3.new(0.12, size, size),
		Transparency = 1,
	}):Play()
	task.delay((time or 0.6) + 0.1, function()
		part:Destroy()
	end)
end

local function cameraShake(amount)
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * amount
end

----------------------------------------------------------------------------
-- The display crate + idle animation
----------------------------------------------------------------------------
local function restPose(t)
	return altar.CFrame * CFrame.new(0, HOVER + math.sin(t * 1.6) * 0.16, 0) * CFrame.Angles(0, math.sin(t * 0.45) * 0.4, 0)
end

local function idleColor(t)
	-- hold each rarity colour for a moment, then blend to the next
	local n = #CR.Rarities
	local f = (t * 0.32) % n
	local i = math.floor(f) + 1
	local a = math.clamp((f - math.floor(f) - 0.65) / 0.35, 0, 1)
	return CR.Rarities[i].Color:Lerp(CR.Rarities[i % n + 1].Color, a)
end

local function setupAltar()
	local lobby = workspace:WaitForChild("Lobby", 60)
	altar = lobby and lobby:WaitForChild("CrateAltar", 30)
	if not altar then
		return false
	end
	prompt = altar:FindFirstChildOfClass("ProximityPrompt")
	for _, part in ipairs(lobby:GetDescendants()) do
		if part.Name == "AltarRing" and part:IsA("BasePart") then
			ring = part
			break
		end
	end
	crate = CrateModel.Build({ CFrame = restPose(0), Scale = CRATE_SCALE, Color = CR.Rarities[1].Color, Parent = workspace, Name = "LobbyCrate" })
	return true
end

local function idle(dt)
	if playing or not crate then
		return
	end
	local camera = workspace.CurrentCamera
	if (camera.CFrame.Position - altar.Position).Magnitude > 220 then
		return
	end
	idleT += dt
	crate.Model:PivotTo(restPose(idleT))
	local now = os.clock()
	if now - lastColorSet > 0.08 then
		lastColorSet = now
		local color = idleColor(idleT)
		CrateModel.SetColor(crate, color)
		if ring then
			ring.Color = color
		end
	end
	if prompt then
		local keys = player:GetAttribute("Keys") or 0
		prompt.ObjectText = (CR.FreeInStudio and RunService:IsStudio()) and "Free in Studio"
			or ("%d key%s"):format(keys, keys == 1 and "" or "s")
	end
end

----------------------------------------------------------------------------
-- Rifle in the skin's colours
----------------------------------------------------------------------------
local function buildRifle(skin, rarity)
	local model = Instance.new("Model")
	model.Name = "CrateRifle"
	local scale = 1.7
	local built = GunModel.Build(model, { Scale = scale, Anchored = true, CastShadow = false, Effects = false })
	for _, part in pairs(built.Parts) do
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	if built.UsesMesh then
		-- textured meshes can't be recoloured: wash them in the skin colour
		local highlight = Instance.new("Highlight")
		highlight.FillColor = skin.Body
		highlight.FillTransparency = 0.45
		highlight.OutlineColor = rarity.Color
		highlight.OutlineTransparency = 0.1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
	else
		for _, part in pairs(built.Parts) do
			local _, s, v = part.Color:ToHSV()
			if part.Material == Enum.Material.Neon or s > 0.45 then
				part.Color = skin.Accent
			elseif v < 0.38 then
				part.Color = skin.Metal
			else
				part.Color = skin.Body
			end
		end
	end
	model.Parent = workspace
	return { Model = model, Built = built, Scale = scale }
end

local function placeRifle(rifle, cf)
	-- GunModel's grip is near the back: shift so it spins around its middle
	GunModel.Place(rifle.Built, cf * CFrame.new(0, 0, 1.4 * rifle.Scale), rifle.Scale)
end

----------------------------------------------------------------------------
-- Take over / give back the player's view
----------------------------------------------------------------------------
local function takeOver()
	local camera = workspace.CurrentCamera
	saved = {
		CameraType = camera.CameraType,
		Fov = camera.FieldOfView,
		Guis = {},
	}
	Controllers.Camera.SetSuspended(true)
	Controllers.Viewmodel.SetHidden("Crate", true)
	ClientState.SetMenu("Crate", true)
	camera.CameraType = Enum.CameraType.Scriptable
	-- hide the other screens (HUD, lobby, touch controls) for a clean shot
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	for _, screen in ipairs(playerGui and playerGui:GetChildren() or {}) do
		if screen:IsA("ScreenGui") and screen.Enabled and screen.Name ~= "CrateReveal" then
			screen.Enabled = false
			table.insert(saved.Guis, screen)
		end
	end
	-- stand still
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		saved.Root = root
		saved.RootAnchored = root.Anchored
		root.Anchored = true
	end
	if prompt then
		prompt.Enabled = false
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "CrateFX"
	cc.Parent = Lighting
	saved.CC = cc
	CrateReveal.Show()
end

local function giveBack()
	local camera = workspace.CurrentCamera
	if saved then
		for _, screen in ipairs(saved.Guis) do
			if screen.Parent then
				screen.Enabled = true
			end
		end
		if saved.Root and saved.Root.Parent then
			saved.Root.Anchored = saved.RootAnchored
		end
		if saved.CC then
			saved.CC:Destroy()
		end
		camera.FieldOfView = saved.Fov
	end
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	Controllers.Camera.SetSuspended(false)
	Controllers.Viewmodel.SetHidden("Crate", false)
	ClientState.SetMenu("Crate", false)
	if prompt then
		prompt.Enabled = true
	end
	saved = nil
end

local function clearScene()
	if not scene then
		return
	end
	if scene.Connection then
		scene.Connection:Disconnect()
	end
	for _, item in ipairs(scene.Trash) do
		item:Destroy()
	end
	if scene.Rifle then
		scene.Rifle.Model:Destroy()
	end
	CrateModel.SetFade(crate, 0)
	CrateModel.SetLid(crate, 0)
	crate.Light.Brightness = 1.1
	scene = nil
end

local function finish()
	if not playing or finishing then
		return
	end
	finishing = true
	waitingAgain = false
	CrateReveal.HideCard()
	local black = CrateReveal.Black(1, 0.22)
	black.Completed:Wait()
	clearScene()
	giveBack()
	playing = false
	crate.Model:PivotTo(restPose(idleT))
	if ClientState.InMatch() then
		-- a match started: don't bring the lobby screen back over it
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		local lobbyGui = playerGui and playerGui:FindFirstChild("Lobby")
		if lobbyGui then
			lobbyGui.Enabled = false
		end
	end
	CrateReveal.Black(0, 0.3).Completed:Wait()
	if not playing then
		CrateReveal.Hide()
	end
	finishing = false
end

----------------------------------------------------------------------------
-- The cinematic
----------------------------------------------------------------------------
local function play(result, continuing)
	local rarity = rarityById[result.Rarity] or CR.Rarities[1]
	local skin = skinById[result.Skin] or CR.Skins[1]
	local tier = tierOf[rarity.Id] or 1
	local isSecret = rarity.Id == "Secret"
	local big = tier >= 5

	playing = true
	waitingAgain = false
	if not continuing then
		takeOver()
	end
	local camera = workspace.CurrentCamera
	local altarCf = altar.CFrame
	local center = (altarCf * CFrame.new(0, HOVER + 1.6 * CRATE_SCALE, 0)).Position
	local camFrom = camera.CFrame
	local fov0 = saved.Fov

	scene = { Trash = {} }
	local function trash(item)
		table.insert(scene.Trash, item)
		return item
	end

	-- particles: sparks sucked in during the charge, a burst on the blast
	local fxPart = trash(newPart({ Transparency = 1, Size = Vector3.new(16, 16, 16), CFrame = CFrame.new(center) }))
	local inward, burst
	if Config.Effects.Particles then
		inward = Instance.new("ParticleEmitter")
		inward.Texture = Config.Effects.SparkTexture
		inward.Shape = Enum.ParticleEmitterShape.Sphere
		inward.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		inward.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		inward.Speed = NumberRange.new(12, 15)
		inward.Lifetime = NumberRange.new(0.5, 0.6)
		inward.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.45) })
		inward.LightEmission = 1
		inward.Rate = 0
		inward.Parent = fxPart
		local attachment = Instance.new("Attachment")
		attachment.Parent = fxPart
		burst = Instance.new("ParticleEmitter")
		burst.Texture = Config.Effects.SparkTexture
		burst.Speed = NumberRange.new(25, 60)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Drag = 3
		burst.Acceleration = Vector3.new(0, -18, 0)
		burst.Lifetime = NumberRange.new(0.8, 1.8)
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		burst.LightEmission = 1
		burst.Rate = 0
		burst.Parent = attachment
	end

	-- timeline
	local tIntro = continuing and 0.35 or 1.0
	local stepTime = 0.5
	local steps = {} -- { time, rarity, final }
	local climbTo = isSecret and 5 or tier
	local stepCount = math.max(climbTo, 2) -- always build a little suspense
	for k = 1, stepCount do
		local r = CR.Rarities[math.min(k, climbTo)]
		table.insert(steps, { T = tIntro + (k - 1) * stepTime, Rarity = r, Final = (k == stepCount) and not isSecret })
	end
	local chargeEnd = tIntro + stepCount * stepTime + (big and 0.5 or 0.25)
	local stallStart, crackTime
	if isSecret then
		stallStart = chargeEnd - 0.25
		crackTime = stallStart + 1.1
		chargeEnd = crackTime + 0.55
	end
	local tBurst = chargeEnd
	local tReveal = tBurst + 0.35
	local fired = {}
	local function once(key, t, now)
		if now >= t and not fired[key] then
			fired[key] = true
			return true
		end
		return false
	end

	local color = CR.Rarities[1].Color
	local spin, yaw = 0, 0
	local lidStart, lidVel, lidSpin
	local beam
	local rifle
	local shotFrom = altarCf * CFrame.new(3, 4.2, -12)
	local start = os.clock()
	if not continuing then
		Sfx.Play("CardFlip", { Pitch = 0.6, Volume = 1.4 })
	end

	scene.Connection = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - start
		CrateReveal.Update(dt)

		-- rarity climb
		for i, step in ipairs(steps) do
			if once("step" .. i, step.T, t) then
				color = step.Rarity.Color
				CrateModel.SetColor(crate, color)
				if ring then
					ring.Color = color
				end
				CrateReveal.Tier(step.Rarity, step.Final)
				Sfx.Play("CardHover", { Pitch = 0.8 + i * 0.18, Volume = 2.2 })
				shockRing(altarCf.Position + Vector3.new(0, 0.2, 0), color, 10 + i * 3, 0.55)
				crate.Light.Brightness = 3
			end
		end
		crate.Light.Brightness = math.max(1.2, crate.Light.Brightness - dt * 6)
		if isSecret then
			if once("stall", stallStart, t) then
				-- "it's over"... everything goes dark
				CrateReveal.Stall()
				Sfx.Play("Countdown", { Pitch = 0.5, Volume = 1.5 })
			end
			if t >= stallStart and t < crackTime then
				local dim = Color3.fromRGB(30, 26, 30):Lerp(CR.Rarities[5].Color, math.random() < 0.08 and 0.6 or 0)
				CrateModel.SetColor(crate, dim)
				crate.Light.Brightness = 0
			end
			if once("crack", crackTime, t) then
				color = rarity.Color
				CrateModel.SetColor(crate, color)
				if ring then
					ring.Color = color
				end
				CrateReveal.Tier(rarity, true)
				CrateReveal.Flash(color, 0.35)
				Sfx.Play("Explosion", { Pitch = 0.5, Volume = 1.5 })
				shockRing(altarCf.Position + Vector3.new(0, 0.2, 0), color, 36, 0.7)
			end
		end

		-- the crate: lift, spin up, shake
		local charge = math.clamp((t - tIntro) / (chargeEnd - tIntro), 0, 1)
		local lift, shake = 0, 0
		if t < tBurst then
			lift = ease(charge) * 2.2
			shake = (charge ^ 2) * (big and 0.32 or 0.22)
			spin = 0.6 + charge ^ 2 * 14
			if isSecret and t >= stallStart and t < crackTime then
				spin, shake = 0.3, 0.02 -- the fake-out: it all winds down
			end
			if inward then
				inward.Color = ColorSequence.new(color)
				inward.Rate = t > tIntro and (20 + charge * 120) or 0
			end
		else
			local after = t - tBurst
			lift = 2.2 - ease(after / 0.8) * 1.4
			spin = math.max(0.5, 14 * (1 - after * 1.5))
		end
		yaw += spin * dt
		local pose = altarCf * CFrame.new(cameraShake(shake)) * CFrame.new(0, HOVER + lift, 0) * CFrame.Angles(0, yaw, 0)
		crate.Model:PivotTo(pose)
		if t < tBurst then
			CrateModel.SetLid(crate, charge > 0.3 and math.random() * charge * 9 or 0)
		end

		-- BURST
		if once("burst", tBurst, t) then
			if inward then
				inward.Rate = 0
			end
			if burst then
				burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
				burst:Emit(60 + tier * 25)
			end
			lidStart = crate.Lid:GetPivot()
			-- up and back, away from the camera (the crate's front faces the camera)
			lidVel = Vector3.new(math.random(-4, 4), 26, 0) + altarCf.LookVector * -9
			lidSpin = Vector3.new(math.random(4, 7), math.random(-3, 3), math.random(-2, 2))
			CrateReveal.Flash(Color3.new(1, 1, 1), big and 0.9 or 0.6)
			Sfx.Play("Explosion", { Pitch = 1.1, Volume = 1.3 })
			if tier >= 4 then
				Sfx.Play("CardLegendary", { Pitch = isSecret and 0.45 or 0.8, Volume = 1.2 })
			end
			shockRing(altarCf.Position + Vector3.new(0, 0.3, 0), color, 30 + tier * 8, 0.8)
			saved.CC.TintColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
			saved.CC.Brightness = 0.5
			saved.CC.Saturation = 0.4
			TweenService:Create(saved.CC, TweenInfo.new(1.2), {
				TintColor = Color3.new(1, 1, 1),
				Brightness = 0,
				Saturation = 0.1,
			}):Play()
			-- pillar of light
			beam = trash(newPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(80, 0.5, 0.5),
				CFrame = CFrame.new(center + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Color = color,
				Material = Enum.Material.Neon,
				Transparency = 0.1,
			}))
			TweenService:Create(beam, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = Vector3.new(80, big and 6 or 4, big and 6 or 4) }):Play()
			task.delay(0.3, function()
				if beam.Parent then
					TweenService:Create(beam, TweenInfo.new(0.9), { Size = Vector3.new(80, 1.2, 1.2), Transparency = 0.45 }):Play()
				end
			end)
			-- light shafts for the top tiers
			if big then
				for k = 1, 6 do
					local shaft = trash(newPart({
						Size = Vector3.new(0.4, 30, 0.4),
						Color = color,
						Material = Enum.Material.Neon,
						Transparency = 0.35,
					}))
					shaft:SetAttribute("Angle", k * 60)
				end
			end
			local burstLight = Instance.new("PointLight")
			burstLight.Color = color
			burstLight.Range = 40
			burstLight.Brightness = 8
			burstLight.Parent = fxPart
			TweenService:Create(burstLight, TweenInfo.new(1.5), { Brightness = 1.5, Range = 24 }):Play()
		end
		if lidStart then
			local tau = t - tBurst
			local pos = lidStart.Position + lidVel * tau + Vector3.new(0, -45, 0) * tau * tau * 0.5
			crate.Lid:PivotTo(CFrame.new(pos) * lidStart.Rotation * CFrame.Angles(lidSpin.X * tau, lidSpin.Y * tau, lidSpin.Z * tau))
			if tau > 0.45 then
				CrateModel.SetFade(crate, math.clamp((tau - 0.45) / 0.4, 0, 1), true)
			end
		end
		-- spinning light shafts
		for _, item in ipairs(scene.Trash) do
			local angle = item:GetAttribute("Angle")
			if angle then
				local a = math.rad(angle) + t * 0.8
				item.CFrame = CFrame.new(center) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(28), 0, 0) * CFrame.new(0, 15, 0)
			end
		end

		-- REVEAL: the rifle rises out of the crate and spins
		if once("reveal", tReveal, t) then
			rifle = buildRifle(skin, rarity)
			scene.Rifle = rifle
			CrateReveal.Reveal({
				Rarity = rarity,
				Skin = skin,
				New = result.New,
				Count = result.Count,
				Keys = result.Keys,
				Free = result.Free,
				CanAgain = result.Free or (result.Keys or 0) >= CR.Cost,
			})
			Sfx.Play(isSecret and "Victory" or "CardPick", { Pitch = 1, Volume = 1.2 })
		end
		if rifle then
			local r = t - tReveal
			local rise = ease(r / 0.9)
			local rifleCf = CFrame.new(center + Vector3.new(0, 0.5 + rise * 3.6 + math.sin(t * 2) * 0.15, 0))
				* CFrame.Angles(0, t * 1.1, 0)
				* CFrame.Angles(math.rad(-8), 0, math.rad(math.sin(t * 1.4) * 6))
			placeRifle(rifle, rifleCf)
		end

		-- CAMERA
		local shotCf
		if t < tIntro then
			local a = ease(t / tIntro)
			local target = CFrame.lookAt(shotFrom.Position, center)
			shotCf = camFrom:Lerp(target, a)
		elseif t < tBurst then
			local dolly = ease(charge) * 3.2
			local p = (altarCf * CFrame.new(3 - charge * 1.2, 4.2 - charge * 0.6, -12 + dolly)).Position
			shotCf = CFrame.lookAt(p, center + Vector3.new(0, lift * 0.6, 0))
		else
			-- pull back and drift round while the rifle shows off
			local after = t - tBurst
			local back = ease(after / 0.6)
			local orbit = math.rad(math.sin(after * 0.35) * 16)
			local local0 = CFrame.Angles(0, orbit, 0) * CFrame.new(2.2 - back * 1, 4.6 + back * 1.6, -9 - back * 4.5)
			local p = (altarCf * local0).Position
			shotCf = CFrame.lookAt(p, center + Vector3.new(0, 2.6 * math.min(1, after), 0))
		end
		local camShake = 0
		if t < tBurst then
			camShake = charge ^ 3 * (big and 0.18 or 0.1)
		else
			camShake = math.max(0, (big and 1.0 or 0.6) * (1 - (t - tBurst) / 0.7))
		end
		camera.CFrame = shotCf * CFrame.new(cameraShake(camShake))
		local fov = fov0
		if t < tBurst then
			fov = fov0 - charge * 12
		else
			local after = t - tBurst
			fov = fov0 + 10 * math.exp(-after * 3) - 2
		end
		camera.FieldOfView = fov
	end)
end

----------------------------------------------------------------------------
-- Input during the reveal
----------------------------------------------------------------------------
local function openAgain()
	if not playing or finishing or waitingAgain or not CrateReveal.CanAgain() then
		return
	end
	waitingAgain = true
	CrateReveal.HideCard()
	clearScene()
	crate.Model:PivotTo(restPose(idleT))
	Remotes.Get("CrateOpen"):FireServer()
	-- no answer at all: give the view back (a stale timer can't end a later opening)
	againToken += 1
	local token = againToken
	task.delay(3, function()
		if waitingAgain and token == againToken then
			finish()
		end
	end)
end

local function onResult(result)
	if typeof(result) ~= "table" then
		return
	end
	if result.Type == "Denied" then
		if waitingAgain then
			task.spawn(finish)
		end
		return
	end
	if result.Type ~= "Result" or not crate or ClientState.InMatch() then
		return
	end
	if playing and waitingAgain then
		waitingAgain = false
		play(result, true)
	elseif not playing and not finishing then
		play(result, false)
	else
		pendingResult = result
	end
end

function CrateController.Init(controllers)
	Controllers = controllers
end

function CrateController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	CrateReveal.Start(playerGui)
	CrateReveal.Again:Connect(openAgain)
	CrateReveal.Done:Connect(finish)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not playing or finishing or not CrateReveal.IsShowingButtons() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.X or key == Enum.KeyCode.ButtonX then
			openAgain()
		elseif key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.ButtonB then
			finish()
		end
	end)

	Remotes.Get("Crates").OnClientEvent:Connect(onResult)

	-- a match starting (or dying) mid-opening ends it at once
	ClientState.Changed:Connect(function(snapshot)
		if playing and snapshot.InMatch then
			task.spawn(finish)
		end
	end)

	task.spawn(function()
		if setupAltar() then
			RunService.RenderStepped:Connect(idle)
			RunService.RenderStepped:Connect(function()
				if not playing and not finishing and pendingResult and not ClientState.InMatch() then
					local result = pendingResult
					pendingResult = nil
					play(result, false)
				end
			end)
		end
	end)
end

return CrateController
