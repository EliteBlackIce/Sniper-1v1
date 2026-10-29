--[[
	SpectateController.lua  (Client.SpectateController)

	Watching a live duel from the lobby (Profile > WATCH). The server sends
	the match's snapshots through "SpectateState" (nil = stopped) and the
	duel's shots / effects like it does to the players.

	The camera follows one duelist over the shoulder, looking where they
	aim (smoothed). A bar at the top shows both names, the score, the round
	and the phase; a bar at the bottom has the keys:
		WatchNext (H / X)       follow the other player
		StopWatching (Backspace / B)   back to your own camera
	Both are buttons too (the mouse is free while watching).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.ClientState)
local Keybinds = require(script.Parent.Keybinds)
local Sfx = require(script.Parent.Sfx)
local Theme = require(script.Parent.ui.Theme)

local Palette = Config.Palette
local player = Players.LocalPlayer

local Spectate = {}
local Controllers

local snapshot -- the watched match (nil = not watching)
local followSlot = 1
local camPos, camLook
local gui, unlocker, topBar, nameLabels, scoreLabel, infoLabel, keysLabel
local PHASES = {
	Countdown = "GET READY",
	Fight = "FIGHT",
	RoundEnd = "ROUND OVER",
	Pick = "PICKING A POWER-UP",
	PickReveal = "PICKING A POWER-UP",
	Victory = "MATCH OVER",
}

function Spectate.IsWatching()
	return snapshot ~= nil
end

local function bodyOf(entry)
	if not entry then
		return nil
	end
	if entry.IsBot then
		local bots = workspace:FindFirstChild("Bots")
		return bots and entry.CharacterName and bots:FindFirstChild(entry.CharacterName) or nil
	end
	local p = Players:GetPlayerByUserId(entry.UserId)
	return p and p.Character
end

local function keyLabel(actionId)
	local device = UserInputService:GetLastInputType().Name:find("Gamepad") and "Gamepad" or "Keyboard"
	local ok, label = pcall(function()
		return Keybinds.Label(Keybinds.Get(actionId, device))
	end)
	return ok and label or "?"
end

local function refreshBar()
	if not snapshot then
		return
	end
	for slot = 1, 2 do
		local entry = snapshot.Players and snapshot.Players[slot]
		nameLabels[slot].Text = entry and string.upper(entry.Name or "?") or "-"
		nameLabels[slot].TextTransparency = slot == followSlot and 0 or 0.35
	end
	local a, b = snapshot.Players and snapshot.Players[1], snapshot.Players and snapshot.Players[2]
	scoreLabel.Text = ("%d  -  %d"):format(a and a.Wins or 0, b and b.Wins or 0)
	infoLabel.Text = ("%s  ·  ROUND %d  ·  %s"):format(
		string.upper(snapshot.MapName or "ARENA"),
		snapshot.Round or 1,
		PHASES[snapshot.Phase] or ""
	)
	keysLabel.Text = ("[%s] SWITCH PLAYER     [%s] STOP WATCHING"):format(keyLabel("WatchNext"), keyLabel("StopWatching"))
end

local function stopLocal()
	if not snapshot then
		return
	end
	snapshot = nil
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("Spectate", false)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	Controllers.Camera.SetSuspended(false)
end

local function onState(data)
	if typeof(data) ~= "table" then
		stopLocal()
		return
	end
	local starting = snapshot == nil
	snapshot = data
	if starting then
		followSlot = 1
		camPos, camLook = nil, nil
		gui.Enabled = true
		unlocker.Visible = true
		ClientState.SetMenu("Spectate", true)
		Controllers.Camera.SetSuspended(true)
		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		Sfx.Play("KillCamIn", { Volume = 0.6 })
		topBar.Position = UDim2.new(0.5, 0, 0, -80)
		Theme.tween(topBar, 0.35, { Position = UDim2.new(0.5, 0, 0, 16) }, Enum.EasingStyle.Back)
	end
	refreshBar()
end

local function stop()
	Remotes.Get("Spectate"):FireServer(nil)
	stopLocal()
end

local function switch()
	followSlot = followSlot == 1 and 2 or 1
	camPos = nil -- cut, don't swoop across the map
	Sfx.Play("CardHover", { Pitch = 1.1 })
	refreshBar()
end

local function update(dt)
	if not snapshot then
		return
	end
	if ClientState.InMatch() then
		stopLocal() -- (you got matched)
		return
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local entry = snapshot.Players and snapshot.Players[followSlot]
	local body = bodyOf(entry)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	local head = body and body:FindFirstChild("Head")
	if not root or not head then
		-- (between rounds the dead player has no body: watch the other one)
		local other = bodyOf(snapshot.Players and snapshot.Players[followSlot == 1 and 2 or 1])
		if other and other:FindFirstChild("HumanoidRootPart") then
			body, root, head = other, other.HumanoidRootPart, other:FindFirstChild("Head")
		end
	end
	if not root then
		return
	end
	-- aim: where their body faces, tilted by the pitch they replicate
	local pitch = tonumber(body:GetAttribute("AimPitch")) or 0 -- (radians)
	local flatLook = root.CFrame.LookVector
	local look = (CFrame.lookAt(Vector3.zero, flatLook) * CFrame.Angles(pitch, 0, 0)).LookVector
	local eye = (head and head.Position or root.Position + Vector3.new(0, 1.5, 0))
	local goal = eye - look * 9 + Vector3.new(0, 2.2, 0) + root.CFrame.RightVector * 2.2
	-- keep the camera out of walls
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { body, camera }
	local hit = workspace:Raycast(eye, goal - eye, params)
	if hit then
		goal = hit.Position + hit.Normal * 0.6
	end
	local k = 1 - math.exp(-dt * 10)
	camPos = camPos and camPos:Lerp(goal, k) or goal
	local lookAt = eye + look * 60
	camLook = camLook and camLook:Lerp(lookAt, 1 - math.exp(-dt * 8)) or lookAt
	camera.FieldOfView = 70
	camera.CFrame = CFrame.lookAt(camPos, camLook)
end

function Spectate.Init(controllers)
	Controllers = controllers
end

function Spectate.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Theme.screen("Spectate", 7, playerGui)
	gui.Enabled = false
	unlocker = Theme.mouseUnlocker(gui)

	topBar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(560, 86),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	Theme.corner(topBar, 14)
	Theme.scaleOf(topBar)
	local tag = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(110, 20),
		BackgroundColor3 = Palette.UIDanger,
		Parent = topBar,
	})
	Theme.corner(tag, UDim.new(0.5, 0))
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = "● WATCHING LIVE",
		TextSize = 11,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = tag,
	})
	nameLabels = {}
	for slot = 1, 2 do
		local left = slot == 1
		nameLabels[slot] = Theme.label({
			AnchorPoint = Vector2.new(left and 0 or 1, 0),
			Position = UDim2.new(left and 0 or 1, left and 18 or -18, 0, 18),
			Size = UDim2.fromOffset(190, 28),
			TextSize = 20,
			TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = ClientState.GetSlotColor(slot),
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = topBar,
		})
	end
	scoreLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(140, 38),
		TextSize = 32,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = topBar,
	})
	infoLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 54),
		Size = UDim2.new(1, -30, 0, 18),
		TextSize = 13,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = topBar,
	})

	local bottom = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(520, 44),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	keysLabel = Theme.label({
		Position = UDim2.fromOffset(0, -24),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 13,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = bottom,
	})
	Theme.new("UIStroke", { Thickness = 1.5, Transparency = 0.5, Color = Palette.UIBackground, Parent = keysLabel })
	local switchButton = Theme.button({
		Size = UDim2.new(0.5, -6, 1, 0),
		Text = "SWITCH PLAYER",
		TextSize = 16,
		BackgroundColor3 = Palette.UIPanel,
		TextColor3 = Palette.UIText,
		Parent = bottom,
	})
	local stopButton = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -6, 1, 0),
		Text = "STOP WATCHING",
		TextSize = 16,
		Parent = bottom,
	})
	switchButton.Activated:Connect(switch)
	stopButton.Activated:Connect(stop)

	local scale = Theme.scaleOf(bottom)
	local topScale = Theme.scaleOf(topBar)
	local function fit()
		local vp = workspace.CurrentCamera.ViewportSize
		local s = math.clamp(math.min(vp.X / 900, vp.Y / 520), 0.6, 1.2)
		scale.Scale, topScale.Scale = s, s
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	Remotes.Get("SpectateState").OnClientEvent:Connect(onState)
	local function onInput(input, processed)
		if not snapshot or (processed and UserInputService:GetFocusedTextBox()) then
			return
		end
		if Keybinds.Matches("StopWatching", input) then
			stop()
		elseif Keybinds.Matches("WatchNext", input) then
			switch()
		end
	end
	UserInputService.InputBegan:Connect(onInput)
	Keybinds.VirtualBegan:Connect(onInput)
	RunService:BindToRenderStep("SniperSpectate", Enum.RenderPriority.Camera.Value + 2, update)
end

return Spectate
