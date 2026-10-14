--[[
	KillCamController.lua  (Client.KillCamController)

	When your opponent kills you in a match, you watch the last few seconds
	again through THEIR eyes: where they were, where they were aiming, their
	shot flying at a ghost of you, ending in slow motion on the kill. Then
	the camera cuts round to face the winner, who strikes a victory pose
	(rifle up on the shoulder or knife raised, fist in the air).

	How it works (all on your client, nothing extra is sent):
	  * Every frame of a round we record your opponent's head position,
	    facing and aim pitch (the "AimPitch" attribute everyone already
	    shares), plus your own position, into a short rolling buffer.
	  * Their shots (the ShotFx remote) are recorded with a timestamp.
	  * When the server tells you that you died from a hit (Damaged with
	    Killed = true), we replay the buffer: the camera rides along their
	    head, with THEIR arms (a copy of their avatar's arms) holding THEIR
	    rifle (with their power-ups) in view, kicking and cycling the bolt on
	    every shot. A copy of your real character runs, jumps and aims where
	    you did, with Roblox's normal animations and the rifle-holding pose,
	    and their shot tracers are drawn again at the right moment.

	Press Space / tap the screen to skip. Tune it in Config.KillCam.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PowerUps = require(Shared.PowerUps)
local Cosmetics = require(Shared.Cosmetics)
local ClientState = require(script.Parent.ClientState)
local Theme = require(script.Parent.ui.Theme)

local K = Config.KillCam
local Palette = Config.Palette
local player = Players.LocalPlayer

local KillCam = {}
local Controllers

local BUFFER_SECONDS = 4
local samples = {} -- { T, Head (Vector3), Yaw, Pitch, Me (CFrame), MyPitch, MyAir }
local shots = {} -- { T, Bullets, Explosive }
local playing = false
local stopRequested = false
local gui, banner, killerLabel, vignette
local ghostTemplate -- a copy of you made at the start of each round (before you can die)
local ghostAnims = {} -- { idle = id, run = id, fall = id, ... } from your character's Animate script

-- Roblox's default R15 animations, in case your character has no Animate script
local DEFAULT_ANIMS = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
}

local function now()
	return os.clock()
end

local function trim(list)
	local cutoff = now() - BUFFER_SECONDS
	while list[1] and list[1].T < cutoff do
		table.remove(list, 1)
	end
end

local function opponentCharacter()
	local opponent = ClientState.GetOpponentPlayer()
	return opponent and opponent.Character
end

local function record()
	if playing or not ClientState.InMatch() or not ClientState.IsFighting() then
		return
	end
	local enemy = opponentCharacter()
	local head = enemy and enemy:FindFirstChild("Head")
	local enemyRoot = enemy and enemy:FindFirstChild("HumanoidRootPart")
	local me = player.Character
	local myRoot = me and me:FindFirstChild("HumanoidRootPart")
	if not head or not enemyRoot or not myRoot then
		return
	end
	local look = enemyRoot.CFrame.LookVector
	local myHumanoid = me:FindFirstChildOfClass("Humanoid")
	table.insert(samples, {
		T = now(),
		Head = head.Position + Vector3.new(0, 0.3, 0),
		Yaw = math.atan2(-look.X, -look.Z),
		Pitch = enemy:GetAttribute("AimPitch") or 0,
		Me = myRoot.CFrame,
		MyPitch = me:GetAttribute("AimPitch") or 0,
		MyAir = myHumanoid ~= nil and myHumanoid.FloorMaterial == Enum.Material.Air,
		Weapon = enemy:GetAttribute("Weapon") or "Sniper",
		Swing = enemy:GetAttribute("Swing"),
		SwingKind = enemy:GetAttribute("SwingKind"),
	})
	trim(samples)
end

-- The recorded state at time t (blended between the two nearest samples).
local function sampleAt(t)
	local count = #samples
	if count == 0 then
		return nil
	end
	if t <= samples[1].T then
		return samples[1]
	end
	for i = 2, count do
		local b = samples[i]
		if b.T >= t then
			local a = samples[i - 1]
			local alpha = (t - a.T) / math.max(b.T - a.T, 1e-4)
			local yawDelta = (b.Yaw - a.Yaw + math.pi) % (2 * math.pi) - math.pi
			return {
				Head = a.Head:Lerp(b.Head, alpha),
				Yaw = a.Yaw + yawDelta * alpha,
				Pitch = a.Pitch + (b.Pitch - a.Pitch) * alpha,
				Me = a.Me:Lerp(b.Me, alpha),
				MyPitch = a.MyPitch + (b.MyPitch - a.MyPitch) * alpha,
				MyAir = alpha < 0.5 and a.MyAir or b.MyAir,
				Weapon = b.Weapon,
				Swing = b.Swing,
				SwingKind = b.SwingKind,
			}
		end
	end
	return samples[count]
end

-- The animation ids your character uses (its Animate script's values).
local function readAnimations(character)
	local found = {}
	local animate = character:FindFirstChild("Animate")
	if animate then
		for name in pairs(DEFAULT_ANIMS) do
			local value = animate:FindFirstChild(name)
			local animation = value and value:FindFirstChildOfClass("Animation")
			if animation and animation.AnimationId ~= "" then
				found[name] = animation.AnimationId
			end
		end
	end
	for name, id in pairs(DEFAULT_ANIMS) do
		found[name] = found[name] or id
	end
	return found
end

-- A copy of your real character (avatar, clothes, rifle), still rigged so it
-- can be animated. Only the root is anchored; the kill cam moves it.
local function copyCharacter(character)
	if not character then
		return nil
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, ghost = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not ghost then
		return nil
	end
	for _, item in ipairs(ghost:GetDescendants()) do
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("Highlight") or item:IsA("ParticleEmitter") or item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = item.Name == "HumanoidRootPart"
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
			item.LocalTransparencyModifier = 0
		end
	end
	local humanoid = ghost:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
	-- a thin outline so you can spot yourself, but it's still your character
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Palette.PlayerB
	outline.OutlineTransparency = 0.25
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = ghost
	ghost.Name = "KillCamGhost"
	return ghost
end

-- A copy of you made at round start (before you can die).
local function makeGhost()
	if not player.Character then
		return nil
	end
	ghostAnims = readAnimations(player.Character)
	return copyCharacter(player.Character)
end

-- Loads idle / run / fall tracks on the ghost. Returns a function that picks
-- the right one for the current speed.
local function animateGhost(ghost)
	local humanoid = ghost:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return function() end
	end
	local tracks = {}
	for _, name in ipairs({ "idle", "run", "fall" }) do
		local animation = Instance.new("Animation")
		animation.AnimationId = ghostAnims[name] or DEFAULT_ANIMS[name]
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			tracks[name] = track
		end
	end
	local current
	return function(speed, inAir, rate)
		local want = inAir and "fall" or (speed > 2 and "run" or "idle")
		local track = tracks[want]
		if want ~= current then
			if current and tracks[current] then
				tracks[current]:Stop(0.15)
			end
			if track then
				track:Play(0.15)
			end
			current = want
		end
		if track then
			local base = want == "run" and math.clamp(speed / 16, 0.5, 2.2) or 1
			track:AdjustSpeed(base * rate)
		end
	end
end

local function setCharacterHidden(character, hidden)
	if not character then
		return
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function play(deathTime, killerName)
	if playing or #samples < 5 then
		return
	end
	playing = true
	stopRequested = false
	local camera = workspace.CurrentCamera
	local enemy = opponentCharacter()
	local ghost = ghostTemplate and ghostTemplate:Clone()
	local setGhostAnim = function() end
	if ghost then
		ghost:PivotTo(samples[1].Me) -- don't flash at the round-start spot
		ghost.Parent = workspace
		setGhostAnim = animateGhost(ghost)
	end
	local recordedShots = table.clone(shots)
	local drawn = {}

	-- the killer: a copy of their real character, placed where they were,
	-- seen from inside their head (only their arms + weapon show)
	local killerCopy = copyCharacter(enemy)
	if killerCopy then
		killerCopy.Name = "KillCamKiller"
		local outline = killerCopy:FindFirstChildOfClass("Highlight")
		if outline then
			outline:Destroy()
		end
		for _, part in ipairs(killerCopy:GetDescendants()) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			elseif part:IsA("Decal") then
				part.Transparency = 1
			end
		end
		killerCopy:PivotTo(CFrame.new(samples[1].Head - Vector3.new(0, 1.5, 0)))
		killerCopy.Parent = workspace
		Controllers.Viewmodel.Track(killerCopy)
	end
	if ghost then
		Controllers.Viewmodel.Track(ghost) -- your copy holds its weapon + aims like you did
	end

	-- the killer's arms + rifle on our camera (built before we hide them)
	local entry = ClientState.GetOpponentEntry()
	local owned = entry and entry.PowerUps or {}
	local boltTime = PowerUps.ComputeStats(owned).BoltTime or 1
	local okPuppet, puppetErr = pcall(Controllers.Viewmodel.SetPuppet, { Character = killerCopy, Owned = owned })
	if not okPuppet then
		warn("[KillCam]", puppetErr)
	end

	Controllers.Camera.SetSuspended(true)
	local oldType, oldFov = camera.CameraType, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = K.FieldOfView
	setCharacterHidden(enemy, true) -- we're inside their head
	setCharacterHidden(player.Character, true)

	killerLabel.Text = "KILLED BY " .. string.upper(killerName or "YOUR OPPONENT")
	gui.Enabled = true
	banner.Position = UDim2.new(0.5, 0, 0, -80)
	Theme.tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, 40) }, Enum.EasingStyle.Back)

	-- the killer's weapon + knife swings, as recorded
	local shownWeapon = Controllers.Viewmodel.GetWeapon() -- (you may have died holding the knife)
	local lastSwing = nil
	local function showWeapon(name)
		if name ~= shownWeapon then
			shownWeapon = name
			pcall(Controllers.Viewmodel.SetWeapon, name)
		end
	end
	local replayT = deathTime - K.Length
	local finish = deathTime + 0.5
	local victoryAt -- os.clock() when the victory pose started
	local rate = 1
	local current -- the sample for this frame


	local function stop()
		RunService:UnbindFromRenderStep("SniperKillCam")
		-- give the camera back first, so nothing below can leave it stuck
		camera.CameraType = oldType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or oldType
		camera.FieldOfView = oldFov
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		Controllers.Camera.SetSuspended(false)
		playing = false
		gui.Enabled = false
		if ghost then
			Controllers.Viewmodel.Untrack(ghost)
			ghost:Destroy()
		end
		if killerCopy then
			Controllers.Viewmodel.Untrack(killerCopy)
			killerCopy:Destroy()
		end
		setCharacterHidden(enemy, false)
		local ok, err = pcall(Controllers.Viewmodel.SetPuppet, nil)
		if not ok then
			warn("[KillCam]", err)
		end
		pcall(Controllers.Viewmodel.SetWeapon, ClientState.Weapon or "Sniper") -- (yours, now the puppet is gone)
	end

	-- runs just before the viewmodel (Camera + 2), so the arms use this frame's camera
	local frame
	RunService:BindToRenderStep("SniperKillCam", Enum.RenderPriority.Camera.Value + 1, function(dt)
		-- an error mid-replay must never leave the camera stuck
		local ok, err = pcall(frame, dt)
		if not ok then
			warn("[KillCam]", err)
			stop()
		end
	end)
	-- the cut to the winner's victory pose (their copy, seen from the front)
	local function startVictory()
		victoryAt = os.clock()
		pcall(Controllers.Viewmodel.SetPuppet, nil) -- (now it's seen from outside)
		for _, part in ipairs(killerCopy:GetDescendants()) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			elseif part:IsA("Decal") then
				part.Transparency = 0
			end
		end
		killerCopy:SetAttribute("AimPitch", 0)
		local pose = Cosmetics.Worn(ClientState.GetOpponentPlayer(), "Pose") -- (their pose cosmetic)
		Controllers.Viewmodel.PlayVictory(killerCopy, pose and pose.Style)
		vignette.BackgroundTransparency = 0.8
		killerLabel.Text = string.upper(killerName or "YOUR OPPONENT") .. " TAKES THE ROUND"
	end

	frame = function(dt)
		if victoryAt then
			local v = os.clock() - victoryAt
			local root = killerCopy:GetPivot()
			local head = root.Position + Vector3.new(0, 1.3, 0)
			local a = math.min(v / K.VictoryTime, 1)
			local from = root * CFrame.new(2.2 - a * 0.6, 2.2 - a * 0.3, -7.5 + a * 1.4) -- in front, slowly pushing in
			camera.CFrame = CFrame.lookAt(from.Position, head)
			camera.FieldOfView = 50
			local phase = ClientState.Snapshot.Phase
			if v >= K.VictoryTime or stopRequested or not ClientState.InMatch() or (phase ~= "RoundEnd" and phase ~= "Fight") then
				stop()
			end
			return
		end
		local slow = replayT > deathTime - K.SlowMoTime and replayT < deathTime + 0.3
		rate = slow and K.SlowMoSpeed or 1
		replayT += dt * rate
		vignette.BackgroundTransparency = slow and 0.6 or 0.85
		local at = math.min(replayT, deathTime)
		local s = sampleAt(at)
		current = s
		if s then
			showWeapon(s.Weapon or "Sniper")
			if s.Swing ~= lastSwing then
				if lastSwing ~= nil and s.Weapon == "Knife" then
					Controllers.Viewmodel.PlayKnife(s.SwingKind or "Slash")
				end
				lastSwing = s.Swing
			end
			local eye = CFrame.new(s.Head) * CFrame.fromOrientation(s.Pitch, s.Yaw, 0)
			camera.CFrame = eye * CFrame.new(0, 0, Controllers.Viewmodel.EyeBack or 0.5) -- framed like first person
			if killerCopy then
				killerCopy:PivotTo(CFrame.new(s.Head - Vector3.new(0, 1.5, 0)) * CFrame.fromOrientation(0, s.Yaw, 0))
			end
			-- how fast they were moving (walk bob on their arms)
			local before = sampleAt(at - 0.1)
			if before then
				local d = (s.Head - before.Head) * Vector3.new(1, 0, 1)
				Controllers.Viewmodel.SetPuppetSpeed(d.Magnitude / 0.1)
			end
			if ghost then
				ghost:PivotTo(s.Me)
				ghost:SetAttribute("AimPitch", s.MyPitch or 0)
				local prev = sampleAt(at - 0.1)
				local speed = prev and ((s.Me.Position - prev.Me.Position) * Vector3.new(1, 0, 1)).Magnitude / 0.1 or 0
				setGhostAnim(speed, s.MyAir, rate)
			end
		end
		for i, shot in ipairs(recordedShots) do
			if not drawn[i] and shot.T <= replayT and shot.T >= deathTime - K.Length then
				drawn[i] = true
				Controllers.Viewmodel.PlayFire(false)
				task.delay(0.12 / rate, function()
					if playing then
						Controllers.Viewmodel.PlayBolt(boltTime / rate)
					end
				end)
				local muzzle = Controllers.Viewmodel.GetMuzzlePosition()
					or (camera.CFrame.Position + camera.CFrame.LookVector * 1.5 - camera.CFrame.UpVector * 0.4)
				for _, bullet in ipairs(shot.Bullets) do
					Controllers.Effects.DrawShot(bullet.Segments, bullet.Passes, bullet.EndPosition, bullet.EndNormal, muzzle, {
						Explosive = shot.Explosive,
						HitPlayer = bullet.HitPlayer,
						Tracer = Cosmetics.TracerColor(ClientState.GetOpponentPlayer()),
					})
				end
			end
		end
		local phase = ClientState.Snapshot.Phase
		if killerCopy and not stopRequested and replayT >= deathTime + 0.15 and (K.VictoryTime or 0) > 0 then
			startVictory()
		elseif replayT >= finish or stopRequested or not ClientState.InMatch() or (phase ~= "RoundEnd" and phase ~= "Fight") then
			stop()
		end
	end
end

function KillCam.IsPlaying()
	return playing
end

function KillCam.Init(controllers)
	Controllers = controllers
end

function KillCam.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Theme.screen("KillCam", 6, playerGui)
	gui.Enabled = false
	vignette = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = gui,
	})
	for _, y in ipairs({ 0, 1 }) do -- letterbox bars
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0, y),
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0.07, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = gui,
		})
	end
	banner = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(420, 70),
		BackgroundColor3 = Palette.UIPanel,
		Parent = gui,
	})
	Theme.stroke(banner, Palette.PlayerB, 2, 0.1)
	Theme.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 8),
		Text = "KILL CAM",
		TextSize = 16,
		TextColor3 = Palette.PlayerB,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = banner,
	})
	killerLabel = Theme.label({
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 30),
		TextSize = 24,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = banner,
	})
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(300, 20),
		Text = "SPACE / TAP TO SKIP",
		TextSize = 14,
		TextColor3 = Palette.UISubText,
		Parent = gui,
	})
	-- crosshair dot: their aim
	local dot = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Palette.PlayerB,
		Parent = gui,
	})
	Theme.corner(dot, UDim.new(0.5, 0))

	RunService.RenderStepped:Connect(record)

	-- record the opponent's shots
	Remotes.Get("ShotFx").OnClientEvent:Connect(function(userId, bullets, explosive)
		local opponent = ClientState.GetOpponentEntry()
		if opponent and opponent.UserId == userId and typeof(bullets) == "table" then
			table.insert(shots, { T = now(), Bullets = bullets, Explosive = explosive })
			trim(shots)
		end
	end)

	-- you died from a hit in a match -> play it back
	Remotes.Get("Damaged").OnClientEvent:Connect(function(data)
		if not K.Enabled or typeof(data) ~= "table" or not data.Killed or not ClientState.InMatch() then
			return
		end
		local deathTime = now()
		local opponent = ClientState.GetOpponentEntry()
		task.delay(K.Delay, function()
			if ClientState.InMatch() then
				play(deathTime + 0.1, opponent and opponent.Name)
			end
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not playing then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA then
			stopRequested = true
		end
	end)

	-- a new round clears the buffers
	ClientState.Changed:Connect(function(snapshot, old)
		if snapshot.Phase == "Countdown" and (not old or old.Phase ~= "Countdown") then
			samples = {}
			shots = {}
		end
		if snapshot.Phase == "Fight" and (not old or old.Phase ~= "Fight") then
			if ghostTemplate then
				ghostTemplate:Destroy()
			end
			ghostTemplate = makeGhost()
		end
	end)
end

return KillCam
