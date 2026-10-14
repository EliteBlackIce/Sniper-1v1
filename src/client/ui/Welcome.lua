--[[
	Welcome.lua  (Client.ui.Welcome)

	A one-time card for brand-new players (the server sets the "FirstVisit"
	attribute when there's no save yet): what the game is and the keys that
	matter, then LET'S GO.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette
local player = Players.LocalPlayer

local Welcome = {}

local LINES = {
	{ "F", "Find a 1v1 match (U: challenge someone, bet keys if you like)" },
	{ "LMB / RMB", "Fire / scope.  1 / 2: rifle / knife" },
	{ "SHIFT  C  SPACE", "Sprint, slide, jump (hop again as you land to keep your speed)" },
	{ "M", "Shop: open crates with keys you earn by playing" },
	{ "L", "Locker: skins, tracers, kill effects, poses, titles" },
	{ "G", "Playground: free roam with practice dummies" },
}

function Welcome.Show(playerGui)
	if ClientState.InMatch() then
		return
	end
	local gui = Theme.screen("Welcome", 20, playerGui)
	local unlocker = Theme.mouseUnlocker(gui)
	unlocker.Visible = true
	ClientState.SetMenu("Welcome", true)
	Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.3,
		Parent = gui,
	})
	local card = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 470),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	Theme.padding(card, 28)
	local scale = Theme.new("UIScale", { Parent = card })
	local view = workspace.CurrentCamera.ViewportSize
	scale.Scale = math.min(1, (view.X - 40) / 620, (view.Y - 40) / 470)
	Theme.label({
		Size = UDim2.new(1, 0, 0, 40),
		RichText = true,
		Text = string.format('WELCOME TO SNIPER <font color="#%s">DUEL</font>', Palette.UIAccent:ToHex()),
		TextSize = 34,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = card,
	})
	Theme.label({
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "One shot, one kill. First to 5 rounds wins, and the loser of each round picks a power-up.",
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = card,
	})
	for i, line in ipairs(LINES) do
		local y = 86 + (i - 1) * 44
		local key = Theme.label({
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.fromOffset(150, 34),
			Text = line[1],
			TextSize = 14,
			TextColor3 = Palette.UIBackground,
			BackgroundColor3 = Palette.UIAccent,
			BackgroundTransparency = 0,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = card,
		})
		Theme.corner(key, 8)
		Theme.label({
			Position = UDim2.fromOffset(164, y),
			Size = UDim2.new(1, -164, 0, 34),
			Text = line[2],
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.Font(Enum.FontWeight.Medium),
			Parent = card,
		})
	end
	local go = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(220, 48),
		Text = "LET'S GO",
		TextSize = 20,
		Parent = card,
	})
	Theme.pop(card, 0.08)
	go.Activated:Connect(function()
		Sfx.Play("CardPick", { Pitch = 1.1 })
		ClientState.SetMenu("Welcome", false)
		gui:Destroy()
	end)
end

function Welcome.Start(playerGui)
	local shown = false
	local function check()
		if player:GetAttribute("FirstVisit") and not shown then
			shown = true
			task.delay(1.5, Welcome.Show, playerGui)
		end
	end
	player:GetAttributeChangedSignal("FirstVisit"):Connect(check)
	check()
end

return Welcome
