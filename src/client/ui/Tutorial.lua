--[[
	Tutorial.lua  (Client.ui.Tutorial)

	The guided first steps, in the lobby (Profile > TUTORIAL, or the welcome
	card). A card at the top of the screen shows one goal at a time with
	your real keys; it ticks off by itself when you do it:

		1  walk around                 5  scope in
		2  sprint + jump               6  hit a practice dummy
		3  bunny hop up to speed       7  headshot a dummy
		4  slide                       8  knife a dummy
		                               9  try a power-up in the Lab

	Finishing tells the server (ProfileService pays Config.Tutorial.RewardKeys
	the first time). SKIP ends it; a match starting ends it too.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Keybinds = require(script.Parent.Parent.Keybinds)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette
local player = Players.LocalPlayer

local Tutorial = {}
local Controllers

local gui, card, stepLabel, titleLabel, hintLabel, bar, barFill
local running = false
local index = 0
local moved = 0
local lastPos
local flags = {}

local function key(actionId)
	local device = UserInputService:GetLastInputType().Name:find("Gamepad") and "Gamepad" or "Keyboard"
	local ok, label = pcall(function()
		return Keybinds.Label(Keybinds.Get(actionId, device))
	end)
	return ok and label or "?"
end

local function touch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Each step: title, hint (a function so it shows your current keys), done().
local STEPS = {
	{
		Title = "WALK AROUND",
		Hint = function()
			return touch() and "Use the stick on the left" or "Move with W A S D"
		end,
		Done = function()
			return moved >= 25
		end,
	},
	{
		Title = "SPRINT AND JUMP",
		Hint = function()
			return touch() and "Tap JUMP while you run" or ("Hold %s to sprint, press %s to jump"):format(key("Sprint"), key("Jump"))
		end,
		Done = function()
			return flags.Jumped
		end,
	},
	{
		Title = "BUNNY HOP",
		Hint = function()
			return ("Keep %s held as you land, and steer in the air - reach 30 speed"):format(touch() and "JUMP" or key("Jump"))
		end,
		Done = function()
			return Controllers.Movement.GetSpeed() >= 30
		end,
	},
	{
		Title = "SLIDE",
		Hint = function()
			return touch() and "Tap SLIDE while running" or ("Press %s while running"):format(key("Slide"))
		end,
		Done = function()
			return flags.Slid
		end,
	},
	{
		Title = "SCOPE IN",
		Hint = function()
			return touch() and "Tap SCOPE" or ("Hold %s"):format(key("Scope"))
		end,
		Done = function()
			return Controllers.Weapon.IsScoped()
		end,
	},
	{
		Title = "HIT A PRACTICE DUMMY",
		Hint = function()
			return "Find the dummies on the shooting range and shoot one"
		end,
		Done = function()
			return flags.Hit
		end,
	},
	{
		Title = "HEADSHOT",
		Hint = function()
			return "A shot to the head is always a kill - land one on a dummy"
		end,
		Done = function()
			return flags.Headshot
		end,
	},
	{
		Title = "KNIFE",
		Hint = function()
			return touch() and "Tap the KNIFE button, then hit a dummy up close"
				or ("Press %s for the knife, then hit a dummy up close (%s for the rifle)"):format(key("Knife"), key("Primary"))
		end,
		Done = function()
			return flags.Knifed
		end,
	},
	{
		Title = "TRY A POWER-UP",
		Hint = function()
			return touch() and "Open MENU > LAB and add any power-up"
				or ("Open the Power-Up Lab (%s) and add any power-up"):format(key("PowerUpLab"))
		end,
		Done = function()
			return next(ClientState.Owned or {}) ~= nil and not ClientState.InMatch()
		end,
	},
}

local function show()
	local step = STEPS[index]
	stepLabel.Text = ("STEP %d / %d"):format(index, #STEPS)
	titleLabel.Text = step.Title
	hintLabel.Text = step.Hint()
	barFill.Size = UDim2.fromScale((index - 1) / #STEPS, 1)
	Theme.pop(card, 0.08)
end

local function finish(completed)
	if not running then
		return
	end
	running = false
	if completed then
		barFill.Size = UDim2.fromScale(1, 1)
		stepLabel.Text = "TUTORIAL COMPLETE"
		titleLabel.Text = "YOU'RE READY"
		hintLabel.Text = ("Press %s to find a 1v1 match"):format(touch() and "FIND MATCH" or key("FindMatch"))
		Sfx.Play("Victory", { Volume = 0.6 })
		Theme.burst(gui, card.AbsolutePosition + card.AbsoluteSize / 2, Palette.UIAccent, 20, 180, 8)
		Remotes.Get("ProfileAction"):FireServer("TutorialDone")
		task.delay(4, function()
			if not running then
				gui.Enabled = false
			end
		end)
	else
		gui.Enabled = false
	end
end

local function advance()
	Sfx.Play("Ding", { Pitch = 1 + index * 0.05 })
	Theme.burst(gui, card.AbsolutePosition + card.AbsoluteSize / 2, Palette.UIAccent, 10, 120, 6)
	index += 1
	table.clear(flags) -- (each step wants it done again, now)
	if index > #STEPS then
		finish(true)
	else
		show()
	end
end

function Tutorial.Start()
	if ClientState.InMatch() then
		return
	end
	running = true
	index = 1
	moved = 0
	lastPos = nil
	table.clear(flags)
	gui.Enabled = true
	card.Position = UDim2.new(0.5, 0, 0, -120)
	Theme.tween(card, 0.4, { Position = UDim2.new(0.5, 0, 0, 90) }, Enum.EasingStyle.Back)
	Sfx.Play("CardPick", { Pitch = 1.1 })
	show()
end

function Tutorial.IsRunning()
	return running
end

function Tutorial.Init(controllers)
	Controllers = controllers
end

-- Builds the card (UIController calls this once).
function Tutorial.Build(playerGui)
	gui = Theme.screen("Tutorial", 6, playerGui)
	gui.Enabled = false
	card = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(560, 112),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.12,
		Parent = gui,
	})
	Theme.corner(card, 14)
	Theme.stroke(card, Palette.UIAccent, 1.5, 0.3)
	local scale = Theme.scaleOf(card)
	local function fit()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 900, vp.Y / 520), 0.6, 1.2)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	stepLabel = Theme.label({
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.fromOffset(300, 16),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UIAccent,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = card,
	})
	titleLabel = Theme.label({
		Position = UDim2.fromOffset(18, 30),
		Size = UDim2.new(1, -120, 0, 32),
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = card,
	})
	hintLabel = Theme.label({
		Position = UDim2.fromOffset(18, 64),
		Size = UDim2.new(1, -36, 0, 20),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		Parent = card,
	})
	bar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -36, 0, 4),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = card,
	})
	Theme.corner(bar, 2)
	barFill = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Palette.UIAccent, Parent = bar })
	Theme.corner(barFill, 2)
	local skip = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(80, 30),
		Text = "SKIP",
		TextSize = 13,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = card,
	})
	skip.Activated:Connect(function()
		finish(false)
	end)

	Controllers.Movement.Jumped:Connect(function()
		flags.Jumped = true
	end)
	Controllers.Movement.Slid:Connect(function()
		flags.Slid = true
	end)
	Remotes.Get("HitConfirm").OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" or ClientState.InMatch() then
			return
		end
		if data.Melee then
			flags.Knifed = true
		else
			flags.Hit = true
			if data.Headshot then
				flags.Headshot = true
			end
		end
	end)
	ClientState.Changed:Connect(function(snapshot)
		if snapshot.InMatch and running then
			finish(false)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if not running then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			if lastPos then
				moved += (root.Position - lastPos).Magnitude
			end
			lastPos = root.Position
		end
		local step = STEPS[index]
		if step and step.Done() then
			advance()
		end
	end)
end

return Tutorial
