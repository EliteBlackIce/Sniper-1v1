--[[
	KillCamController.lua  (Client.KillCamController)

	When your opponent kills you in a match, you watch the last few seconds
	again through THEIR eyes: where they were, where they were aiming, their
	shot flying at a ghost of you, ending in slow motion on the kill.

	How it works (all on your client, nothing extra is sent):
	  * Every frame of a round we record your opponent's head position,
	    facing and aim pitch (the "AimPitch" attribute everyone already
	    shares), plus your own position, into a short rolling buffer.
	  * Their shots (the ShotFx remote) are recorded with a timestamp.
	  * When the server tells you that you died from a hit (Damaged with
	    Killed = true), we replay the buffer: the camera rides along their
	    head, a translucent copy of you stands where you were, and their
	    shot tracers are drawn again at the right moment.

	Press Space / tap the screen to skip. Tune it in Config.KillCam.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.ClientState)
local Theme = require(script.Parent.ui.Theme)

local K = Config.KillCam
local Palette = Config.Palette
local player = Players.LocalPlayer

local KillCam = {}
local Controllers

local BUFFER_SECONDS = 4
local samples = {} -- { T, Head (Vector3), Yaw, Pitch, Me (CFrame) }
local shots = {} -- { T, Bullets, Explosive }
local playing = false
local stopRequested = false
local gui, banner, killerLabel, vignette
local ghostTemplate -- a copy of you made at the start of each round (before you can die)

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
	table.insert(samples, {
		T = now(),
		Head = head.Position + Vector3.new(0, 0.3, 0),
		Yaw = math.atan2(-look.X, -look.Z),
		Pitch = enemy:GetAttribute("AimPitch") or 0,
		Me = myRoot.CFrame,
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
			}
		end
	end
	return samples[count]
end

-- A see-through copy of you, posed where you stood.
local function makeGhost()
	local character = player.Character
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
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("Highlight") or item:IsA("ParticleEmitter") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.LocalTransparencyModifier = 0
		end
	end
	local humanoid = ghost:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.EvaluateStateMachine = false
	end
	local outline = Instance.new("Highlight")
	outline.FillColor = Palette.PlayerB
	outline.FillTransparency = 0.6
	outline.OutlineColor = Color3.new(1, 1, 1)
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = ghost
	ghost.Name = "KillCamGhost"
	return ghost
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
	if ghost then
		ghost.Parent = workspace
	end
	local recordedShots = table.clone(shots)
	local drawn = {}

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

	local replayT = deathTime - K.Length
	local finish = deathTime + 0.5
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		local slow = replayT > deathTime - K.SlowMoTime and replayT < deathTime + 0.3
		replayT += dt * (slow and K.SlowMoSpeed or 1)
		vignette.BackgroundTransparency = slow and 0.6 or 0.85
		local s = sampleAt(math.min(replayT, deathTime))
		if s then
			camera.CFrame = CFrame.new(s.Head) * CFrame.fromOrientation(s.Pitch, s.Yaw, 0)
			if ghost and ghost.PrimaryPart then
				ghost:PivotTo(s.Me)
			elseif ghost then
				local root = ghost:FindFirstChild("HumanoidRootPart")
				if root then
					ghost:PivotTo(s.Me * root.CFrame:ToObjectSpace(ghost:GetPivot()))
				end
			end
		end
		for i, shot in ipairs(recordedShots) do
			if not drawn[i] and shot.T <= replayT and shot.T >= deathTime - K.Length then
				drawn[i] = true
				local muzzle = camera.CFrame.Position + camera.CFrame.LookVector * 1.5 - camera.CFrame.UpVector * 0.4
				for _, bullet in ipairs(shot.Bullets) do
					Controllers.Effects.DrawShot(bullet.Segments, bullet.Passes, bullet.EndPosition, bullet.EndNormal, muzzle, {
						Explosive = shot.Explosive,
						HitPlayer = bullet.HitPlayer,
					})
				end
			end
		end
		local phase = ClientState.Snapshot.Phase
		if replayT >= finish or stopRequested or not ClientState.InMatch() or (phase ~= "RoundEnd" and phase ~= "Fight") then
			connection:Disconnect()
			if ghost then
				ghost:Destroy()
			end
			setCharacterHidden(enemy, false)
			gui.Enabled = false
			camera.CameraType = oldType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or oldType
			camera.FieldOfView = oldFov
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
			Controllers.Camera.SetSuspended(false)
			playing = false
		end
	end)
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
