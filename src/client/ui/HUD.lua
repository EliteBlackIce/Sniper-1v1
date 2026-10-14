--[[
	HUD.lua  (Client.ui.HUD)

	In-match heads-up display:
		crosshair (hidden while scoped) + bolt reload bar
		hitmarkers (red for headshots, bigger on kills) + kill sound
		scope overlay (black outside a circle, thin reticle)
		scoreboard (names, round wins, round timer) with each player's
		    collected power-up icons underneath
		health bar, ability hints with cooldowns
		big centre banner (countdown, GO, round won/lost)
		damage vignette + direction indicator
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerUps = require(Shared.PowerUps)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Keybinds = require(script.Parent.Parent.Keybinds)

local Palette = Config.Palette
local player = Players.LocalPlayer

local HUD = {}
local Controllers

local gui
local crosshair, boltBar, boltFill
local hitmarker
local scope
local scoreboard, nameLabels, winLabels, timerLabel, roundLabel, iconRows
local healthBar, healthFill, healthText
local abilityList
local banner, bannerTitle, bannerSub
local vignette, indicator
local lastCountdownNumber
local bannerToken = 0
local bannerLine
local speedLines = {}
local speedLinesFrame
local lastWins = {}
local speedLabel

----------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------
local function buildCrosshair()
	crosshair = Theme.new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local function line(pos, size)
		local f = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = size,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = crosshair,
		})
		Theme.stroke(f, Palette.UIBackground, 1, 0.5)
		return f
	end
	line(UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(3, 3)) -- centre dot
	line(UDim2.new(0.5, 0, 0.5, -9), UDim2.fromOffset(2, 6))
	line(UDim2.new(0.5, 0, 0.5, 9), UDim2.fromOffset(2, 6))
	line(UDim2.new(0.5, -9, 0.5, 0), UDim2.fromOffset(6, 2))
	line(UDim2.new(0.5, 9, 0.5, 0), UDim2.fromOffset(6, 2))

	boltBar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 26),
		Size = UDim2.fromOffset(34, 3),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.5,
		Visible = false,
		Parent = gui,
	})
	Theme.corner(boltBar, 2)
	boltFill = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = boltBar,
	})
	Theme.corner(boltFill, 2)

	hitmarker = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	for i = 0, 3 do
		local tick = Theme.new("Frame", {
			Name = "Tick",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(10, 3),
			Rotation = 45 + i * 90,
			BackgroundColor3 = Palette.UIHitmarker,
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = hitmarker,
		})
		tick:SetAttribute("Angle", math.rad(45 + i * 90))
		Theme.new("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.5, Parent = tick })
	end
end

local function buildScope()
	scope = Theme.new("Frame", {
		Name = "Scope",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	-- The lens: a circle whose huge outer stroke paints everything outside it black.
	local lens = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.92),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		Parent = scope,
	})
	Theme.corner(lens, UDim.new(0.5, 0))

	-- Black surround: four panels cover everything outside the lens's square,
	-- and a ring outline covers the square's corners outside the circle.
	local black = Color3.fromRGB(8, 9, 12)
	local panels = {}
	for i = 1, 4 do
		panels[i] = Theme.new("Frame", { BackgroundColor3 = black, Parent = scope })
	end
	local mask = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = scope,
	})
	Theme.corner(mask, UDim.new(0.5, 0))
	local maskStroke = Theme.stroke(mask, black, 1, 0)
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		local d = math.floor(viewport.Y * 0.92)
		local left = math.floor((viewport.X - d) / 2)
		local top = math.floor((viewport.Y - d) / 2)
		panels[1].Position, panels[1].Size = UDim2.fromOffset(0, 0), UDim2.new(0, left + 1, 1, 0) -- left
		panels[2].Position, panels[2].Size = UDim2.new(0, left + d - 1, 0, 0), UDim2.new(1, -(left + d - 1), 1, 0) -- right
		panels[3].Position, panels[3].Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, top + 1) -- top
		panels[4].Position, panels[4].Size = UDim2.new(0, 0, 0, top + d - 1), UDim2.new(1, 0, 1, -(top + d - 1)) -- bottom
		-- the corners between a circle and its square are ~0.21 x diameter deep
		mask.Size = UDim2.fromOffset(d, d)
		maskStroke.Thickness = math.ceil(d * 0.22) + 2
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	-- inner ring
	local ring = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = lens,
	})
	Theme.corner(ring, UDim.new(0.5, 0))
	Theme.stroke(ring, Color3.fromRGB(30, 34, 44), 10, 0)
	-- reticle lines
	local dark = Color3.fromRGB(12, 12, 16)
	Theme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = dark, Parent = lens })
	Theme.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = dark, Parent = lens })
	-- thicker outer posts
	Theme.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0.3, 0, 0, 6), BackgroundColor3 = dark, Parent = lens })
	Theme.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.3, 0, 0, 6), BackgroundColor3 = dark, Parent = lens })
	Theme.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0, 6, 0.3, 0), BackgroundColor3 = dark, Parent = lens })
	-- centre dot
	local dot = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Palette.UIDanger,
		Parent = lens,
	})
	Theme.corner(dot, UDim.new(0.5, 0))
end

local function buildScoreboard()
	scoreboard = Theme.new("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(520, 110),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(420, 54),
		Parent = scoreboard,
	})
	nameLabels, winLabels, iconRows = {}, {}, {}
	for slot = 1, 2 do
		local left = slot == 1
		nameLabels[slot] = Theme.label({
			AnchorPoint = Vector2.new(left and 0 or 1, 0.5),
			Position = UDim2.new(left and 0 or 1, left and 16 or -16, 0.5, 0),
			Size = UDim2.fromOffset(130, 24),
			TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
			TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = panel,
		})
		local chip = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, left and -36 or 36, 0.5, 0),
			Size = UDim2.fromOffset(46, 40),
			BackgroundColor3 = ClientState.GetSlotColor(slot),
			Parent = panel,
		})
		Theme.corner(chip, 8)
		winLabels[slot] = Theme.label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 26,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Text = "0",
			Parent = chip,
		})
		-- collected power-ups under each player (5 per row, up to 3 rows)
		iconRows[slot] = Theme.new("Frame", {
			AnchorPoint = Vector2.new(left and 0 or 1, 0),
			Position = UDim2.new(0.5, left and -210 or 210, 0, 60),
			Size = UDim2.fromOffset(140, 80),
			BackgroundTransparency = 1,
			Parent = scoreboard,
		}, {
			Theme.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(24, 24),
				CellPadding = UDim2.fromOffset(4, 4),
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		Text = "-",
		TextSize = 22,
		TextColor3 = Palette.UISubText,
		Parent = panel,
	})
	roundLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(120, 16),
		TextSize = 12,
		TextColor3 = Palette.UISubText,
		Parent = scoreboard,
	})
	timerLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(120, 20),
		TextSize = 18,
		Parent = scoreboard,
	})
end

local function buildHealth()
	local panel = Theme.panel({
		Name = "Health",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -22),
		Size = UDim2.fromOffset(260, 46),
		Visible = false,
		Parent = gui,
	})
	healthBar = panel
	Theme.padding(panel, 10)
	local track = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -64, 0, 10),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = panel,
	})
	Theme.corner(track, 5)
	healthFill = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIText,
		Parent = track,
	})
	Theme.corner(healthFill, 5)
	healthText = Theme.label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(56, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 24,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
end

local function buildAbilities()
	abilityList = Theme.new("Frame", {
		Name = "Abilities",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -22),
		Size = UDim2.fromOffset(220, 140),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Theme.new("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function buildBanner()
	banner = Theme.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(700, 140),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	bannerTitle = Theme.label({
		Size = UDim2.new(1, 0, 0, 90),
		TextSize = 78,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = banner,
	})
	Theme.new("UIStroke", { Thickness = 2, Transparency = 0.55, Color = Palette.UIBackground, Parent = bannerTitle })
	bannerLine = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.fromOffset(0, 4),
		BackgroundColor3 = Palette.UIAccent,
		Parent = banner,
	})
	Theme.corner(bannerLine, 2)
	bannerSub = Theme.label({
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 22,
		TextColor3 = Palette.UISubText,
		Parent = banner,
	})
end

-- Speedometer (bottom centre): your horizontal speed, handy for bunny hopping.
local function buildSpeedometer()
	speedLabel = Theme.label({
		Name = "Speed",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(160, 24),
		TextSize = 20,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		TextTransparency = 0.15,
		Parent = gui,
	})
	Theme.new("UIStroke", { Thickness = 1.5, Transparency = 0.6, Color = Palette.UIBackground, Parent = speedLabel })
end

-- Speed lines: thin streaks at the screen edges when you're moving fast.
local function buildSpeedLines()
	speedLinesFrame = Theme.new("Frame", {
		Name = "SpeedLines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	for i = 1, 18 do
		local line = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Parent = speedLinesFrame,
		})
		Theme.new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }),
			Parent = line,
		})
		speedLines[i] = { Frame = line, Angle = (i / 18) * math.pi * 2 }
	end
end

local function updateSpeedLines(speed, scoped)
	if not speedLinesFrame then
		return
	end
	local from = Config.Effects.SpeedLinesFrom
	local alpha = Config.Effects.SpeedLines and not scoped and math.clamp((speed - from) / 45, 0, 1) or 0
	speedLinesFrame.Visible = alpha > 0
	if alpha <= 0 then
		return
	end
	local viewport = workspace.CurrentCamera.ViewportSize
	local center = viewport / 2
	local radius = math.min(viewport.X, viewport.Y) * 0.42
	for _, l in ipairs(speedLines) do
		local angle = l.Angle + (math.random() - 0.5) * 0.12
		local r = radius + math.random() * radius * 0.5
		local length = 60 + math.random() * 140 * alpha
		local dir = Vector2.new(math.cos(angle), math.sin(angle))
		local pos = center + dir * (r + length / 2)
		l.Frame.Position = UDim2.fromOffset(pos.X, pos.Y)
		l.Frame.Size = UDim2.fromOffset(length, 2)
		l.Frame.Rotation = math.deg(angle)
		l.Frame.BackgroundTransparency = 1 - alpha * (0.25 + math.random() * 0.35)
	end
end

local function buildDamage()
	vignette = Theme.new("Frame", {
		Name = "DamageVignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	-- four soft edges made with gradients
	local edges = {
		{ UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0.75), -90 },
		{ UDim2.fromScale(0.2, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.2, 1), UDim2.fromScale(0.8, 0), 180 },
	}
	for _, e in ipairs(edges) do
		local f = Theme.new("Frame", {
			Size = e[1],
			Position = e[2],
			BackgroundColor3 = Palette.UIDanger,
			Parent = vignette,
		})
		Theme.new("UIGradient", {
			Rotation = e[3],
			Transparency = NumberSequence.new(0, 1),
			Parent = f,
		})
	end
	vignette.Visible = false

	indicator = Theme.new("Frame", {
		Name = "DamageIndicator",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(240, 240),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local arrow = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(60, 6),
		BackgroundColor3 = Palette.UIDanger,
		Parent = indicator,
	})
	Theme.corner(arrow, 3)
end

----------------------------------------------------------------------------
-- Banner
----------------------------------------------------------------------------
local function showBanner(title, sub, color, duration)
	bannerToken += 1
	local token = bannerToken
	banner.Visible = true
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color or Palette.UIText
	bannerSub.Text = sub or ""
	-- punch in: big + transparent -> normal, underline wipes open, subtitle fades in
	bannerTitle.TextTransparency = 1
	bannerTitle.Size = UDim2.new(1, 0, 0, 90)
	bannerTitle.TextSize = 110
	Theme.tween(bannerTitle, 0.3, { TextSize = 78, TextTransparency = 0 }, Enum.EasingStyle.Back)
	bannerLine.BackgroundColor3 = color or Palette.UIAccent
	bannerLine.BackgroundTransparency = 0
	bannerLine.Size = UDim2.fromOffset(0, 4)
	Theme.tween(bannerLine, 0.4, { Size = UDim2.fromOffset(title == "" and 0 or 260, 4) }, Enum.EasingStyle.Quint)
	bannerSub.TextTransparency = 1
	Theme.tween(bannerSub, 0.5, { TextTransparency = 0 })
	if duration then
		task.delay(duration, function()
			if bannerToken == token then
				Theme.tween(bannerTitle, 0.25, { TextTransparency = 1 })
				Theme.tween(bannerSub, 0.25, { TextTransparency = 1 })
				Theme.tween(bannerLine, 0.25, { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 4) })
				task.wait(0.25)
				if bannerToken == token then
					banner.Visible = false
				end
			end
		end)
	end
end

local function hideBanner()
	bannerToken += 1
	banner.Visible = false
end

-- Short coloured flash + text (Second Wind etc.)
function HUD.Flash(color, text)
	local flash = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.6,
		Parent = gui,
	})
	Theme.tween(flash, 0.6, { BackgroundTransparency = 1 })
	task.delay(0.65, function()
		flash:Destroy()
	end)
	if text then
		showBanner(text, nil, color, 1.2)
	end
end

----------------------------------------------------------------------------
-- Hits and damage
----------------------------------------------------------------------------
-- The X on a hit: the four ticks snap in from further out, hold for a
-- moment and fade. Headshots are red, kills are bigger and red, with a
-- second, wider X that flies out.
local hitToken = 0
function HUD.Hitmarker(headshot, killed)
	hitToken += 1
	local token = hitToken
	local color = (headshot or killed) and Palette.UIHeadshot or Palette.UIHitmarker
	local length, thick = killed and 15 or 10, killed and 4 or 3
	local radius = killed and 13 or 10
	for _, tick in ipairs(hitmarker:GetChildren()) do
		local angle = tick:GetAttribute("Angle")
		if angle then
			tick.BackgroundColor3 = color
			tick.BackgroundTransparency = 0
			tick.UIStroke.Transparency = 0.5
			tick.Size = UDim2.fromOffset(length * 1.4, thick)
			tick.Position = UDim2.new(0.5, math.cos(angle) * (radius + 9), 0.5, math.sin(angle) * (radius + 9))
			Theme.tween(tick, 0.07, {
				Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
				Size = UDim2.fromOffset(length, thick),
			})
		end
	end
	hitmarker.Visible = true
	hitmarker.Rotation = killed and -12 or 0
	Theme.tween(hitmarker, 0.15, { Rotation = 0 }, Enum.EasingStyle.Back)
	task.delay(killed and 0.32 or 0.2, function()
		if token ~= hitToken then
			return -- a newer hit took over
		end
		for _, tick in ipairs(hitmarker:GetChildren()) do
			if tick:GetAttribute("Angle") then
				Theme.tween(tick, 0.25, { BackgroundTransparency = 1 })
				Theme.tween(tick.UIStroke, 0.25, { Transparency = 1 })
			end
		end
		task.delay(0.3, function()
			if token == hitToken then
				hitmarker.Visible = false
			end
		end)
	end)
	if killed then
		-- the wide X flying out
		for _, tick in ipairs(hitmarker:GetChildren()) do
			local angle = tick:GetAttribute("Angle")
			if angle then
				local ghost = tick:Clone()
				ghost:SetAttribute("Angle", nil)
				ghost.BackgroundTransparency = 0.2
				ghost.Parent = hitmarker
				Theme.tween(ghost, 0.35, {
					Position = UDim2.new(0.5, math.cos(angle) * 34, 0.5, math.sin(angle) * 34),
					BackgroundTransparency = 1,
				}, Enum.EasingStyle.Quint)
				Theme.tween(ghost.UIStroke, 0.35, { Transparency = 1 })
				task.delay(0.4, ghost.Destroy, ghost)
			end
		end
	end
end

local function onDamaged(data)
	Sfx.Play("Hurt")
	vignette.Visible = true
	for _, edge in ipairs(vignette:GetChildren()) do
		edge.BackgroundTransparency = 0.3
		Theme.tween(edge, 0.7, { BackgroundTransparency = 1 })
	end
	Controllers.Camera.Shake(1.5)
	-- point toward the attacker
	if data.From then
		local camera = workspace.CurrentCamera
		local toAttacker = data.From - camera.CFrame.Position
		local localDir = camera.CFrame:VectorToObjectSpace(toAttacker)
		local angle = math.deg(math.atan2(localDir.X, -localDir.Z))
		indicator.Rotation = angle
		indicator.Visible = true
		local arrow = indicator:FindFirstChildOfClass("Frame")
		arrow.BackgroundTransparency = 0
		Theme.tween(arrow, 1.2, { BackgroundTransparency = 1 })
	end
end

-- Floating damage number at the hit position (rises, pops and fades).
local function damageNumber(position, amount, headshot, splash, killed)
	if not Config.Effects.DamageNumbers or not position or not amount then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local billboard = Theme.new("BillboardGui", {
		Adornee = anchor,
		Size = UDim2.fromOffset(160, 50),
		AlwaysOnTop = true,
		LightInfluence = 0,
		StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 1.5, 1, 0),
		Parent = gui.Parent, -- BillboardGuis live directly in PlayerGui
	})
	local color = headshot and Palette.UIHeadshot or splash and Palette.TracerExplosive or killed and Palette.UIAccent or Palette.UIText
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = headshot and "HEADSHOT" or tostring(math.floor(amount + 0.5)),
		TextSize = headshot and 30 or math.clamp(18 + amount * 0.12, 18, 34),
		TextColor3 = color,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = billboard,
	})
	Theme.new("UIStroke", { Thickness = 2, Color = Palette.UIBackground, Transparency = 0.2, Parent = label })
	Theme.pop(label, 0.5)
	Theme.tween(billboard, 0.8, { StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) }, Enum.EasingStyle.Quint)
	task.delay(0.45, function()
		Theme.tween(label, 0.35, { TextTransparency = 1 })
	end)
	task.delay(0.85, function()
		billboard:Destroy()
		anchor:Destroy()
	end)
end

local function onHitConfirm(data)
	HUD.Hitmarker(data.Headshot, data.Killed)
	damageNumber(data.Position, data.Damage, data.Headshot, data.Splash, data.Killed)
	if data.Killed then
		local viewport = workspace.CurrentCamera.ViewportSize
		Theme.burst(gui, viewport / 2, data.Headshot and Palette.UIHeadshot or Palette.UIAccent, 18, 120, 7)
		Theme.ring(gui, viewport / 2, data.Headshot and Palette.UIHeadshot or Color3.new(1, 1, 1), 160, 5)
		Sfx.Play("Kill")
		Sfx.Play("KillThump")
		Sfx.Play("HitTick", { Pitch = 0.85 })
		if data.Headshot then
			task.delay(0.05, Sfx.Play, "Ding")
		end
		if data.Backstab then
			showBanner("BACKSTAB", nil, Palette.AccentB, 1.4)
		elseif data.Melee then
			showBanner("KNIFED", nil, Palette.UIAccent, 1.2)
		else
			showBanner(data.Headshot and "HEADSHOT" or "ELIMINATED", nil, data.Headshot and Palette.UIHeadshot or Palette.UIText, 1.2)
		end
	elseif data.Headshot then
		Sfx.Play("Headshot")
		Sfx.Play("Ding")
		Sfx.Play("HitTick")
	else
		Sfx.Play("Hit", { Pitch = data.Splash and 0.8 or 1 })
		Sfx.Play("HitTick", { Pitch = data.Splash and 0.8 or 1 })
	end
end

----------------------------------------------------------------------------
-- State updates
----------------------------------------------------------------------------
local function rebuildIcons(snapshot)
	for slot = 1, 2 do
		local row = iconRows[slot]
		for _, child in ipairs(row:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local entry = snapshot.Players and snapshot.Players[slot]
		if entry then
			local order = 0
			for _, def in ipairs(PowerUps.Definitions) do
				local stacks = entry.PowerUps[def.Id]
				if stacks and stacks > 0 then
					order += 1
					local icon = Icons.Create(def, 24)
					icon.LayoutOrder = order
					Theme.stroke(icon, Config.Rarity[def.Rarity].Color, 1.5, 0)
					if stacks > 1 then
						Theme.label({
							AnchorPoint = Vector2.new(1, 1),
							Position = UDim2.new(1, 3, 1, 3),
							Size = UDim2.fromOffset(14, 12),
							Text = "x" .. stacks,
							TextSize = 10,
							FontFace = Theme.Font(Enum.FontWeight.Heavy),
							Parent = icon,
						})
					end
					icon.Parent = row
				end
			end
		end
	end
end

local function rebuildAbilities()
	for _, child in ipairs(abilityList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local stats = ClientState.Stats
	local entries = {}
	local device = game:GetService("UserInputService"):GetLastInputType().Name:find("Gamepad") and "Gamepad" or "Keyboard"
	local function key(actionId)
		return Keybinds.Label(Keybinds.Get(actionId, device))
	end
	if stats.Grapple then
		table.insert(entries, { Key = key("Grapple"), Name = "Grapple", Cooldown = "Grapple" })
	end
	if stats.Blink then
		table.insert(entries, { Key = key("Blink"), Name = "Blink", Cooldown = "Blink" })
	end
	if stats.Decoy then
		table.insert(entries, { Key = key("Decoy"), Name = "Decoy", Cooldown = "Decoy" })
	end
	if stats.BulletTime then
		table.insert(entries, { Key = key("Scope"), Name = "Bullet Time (air)", Cooldown = "BulletTime" })
	end
	for i, e in ipairs(entries) do
		local row = Theme.panel({
			Name = e.Name,
			Size = UDim2.fromOffset(210, 30),
			LayoutOrder = i,
			Parent = abilityList,
		})
		local key = Theme.new("Frame", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(52, 22),
			BackgroundColor3 = Palette.UIPanelLight,
			Parent = row,
		})
		Theme.corner(key, 6)
		Theme.label({ Size = UDim2.fromScale(1, 1), Text = e.Key, TextSize = 13, Parent = key })
		Theme.label({
			Position = UDim2.fromOffset(64, 0),
			Size = UDim2.new(1, -70, 1, 0),
			Text = e.Name,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		if e.Cooldown then
			local fill = Theme.new("Frame", {
				Name = "CooldownFill",
				Size = UDim2.fromScale(0, 1),
				BackgroundColor3 = Palette.UIBackground,
				BackgroundTransparency = 0.4,
				ZIndex = 2,
				Parent = row,
			})
			Theme.corner(fill)
			fill:SetAttribute("Cooldown", e.Cooldown)
		end
	end
end

function HUD.OnState(snapshot, old)
	local inMatch = snapshot.InMatch
	scoreboard.Visible = inMatch
	healthBar.Visible = inMatch
	abilityList.Visible = true -- also shows Power-Up Lab abilities in the lobby
	rebuildAbilities()
	if not inMatch then
		if old.InMatch then
			hideBanner()
		end
		return
	end

	for slot = 1, 2 do
		local entry = snapshot.Players[slot]
		nameLabels[slot].Text = entry and entry.Name or "-"
		nameLabels[slot].TextColor3 = (entry and entry.UserId == player.UserId) and Palette.UIAccent or Palette.UIText
		winLabels[slot].Text = entry and tostring(entry.Wins) or "0"
		-- pop + burst when a score goes up
		if entry and lastWins[slot] and entry.Wins > lastWins[slot] then
			local chip = winLabels[slot].Parent
			Theme.pop(chip, 0.4)
			local center = chip.AbsolutePosition + chip.AbsoluteSize / 2
			Theme.burst(gui, center, ClientState.GetSlotColor(slot), 12, 70, 6)
		end
		lastWins[slot] = entry and entry.Wins or 0
	end
	roundLabel.Text = ("ROUND %d  -  FIRST TO %d"):format(snapshot.Round or 1, snapshot.RoundsToWin or 5)
	rebuildIcons(snapshot)

	local phase = snapshot.Phase
	if phase ~= old.Phase or snapshot.Round ~= old.Round then
		if phase == "Countdown" then
			lastCountdownNumber = nil
			local map = snapshot.MapName and ("   -   " .. string.upper(snapshot.MapName)) or ""
			showBanner("", "ROUND " .. tostring(snapshot.Round) .. map, Palette.UIText)
		elseif phase == "Fight" then
			Sfx.Play("Go")
			showBanner("GO", nil, Palette.UIAccent, 0.7)
		elseif phase == "RoundEnd" then
			local won = snapshot.RoundWinnerUserId == player.UserId
			local me, opp = ClientState.GetMe(), ClientState.GetOpponentEntry()
			local score = me and opp and ("%d  -  %d"):format(me.Wins, opp.Wins) or ""
			local sub = snapshot.Message and (snapshot.Message .. "   " .. score) or score
			if snapshot.RoundWinnerUserId == nil then
				showBanner("DRAW", snapshot.Message, Palette.UISubText, 2.2)
			else
				showBanner(won and "ROUND WON" or "ROUND LOST", sub, won and Palette.UIAccent or Palette.UIDanger, 2.3)
			end
		elseif phase == "Pick" or phase == "PickReveal" or phase == "Victory" then
			hideBanner()
		end
	end
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function update()
	local inArena = ClientState.HasGun() -- lobby practice range or a live round
	local scopeAlpha = Controllers.Weapon.GetScopeAlpha()
	local firstPerson = Controllers.Camera.IsFirstPerson()

	crosshair.Visible = inArena and firstPerson and scopeAlpha < 0.3 and not ClientState.MenuOpen
	scope.Visible = inArena and scopeAlpha > 0.85
	local bolt = Controllers.Weapon.GetBoltProgress()
	boltBar.Visible = inArena and bolt > 0
	boltFill.Size = UDim2.fromScale(1 - bolt, 1)

	-- speedometer: white at normal speed, teal when bunny hopping fast
	local speed = Controllers.Movement.GetSpeed()
	speedLabel.Visible = inArena and scopeAlpha < 0.85 and not ClientState.MenuOpen
	speedLabel.Text = tostring(math.floor(speed + 0.5)) .. " u/s"
	speedLabel.TextColor3 = speed > Config.Movement.SprintSpeed + 6 and Palette.UIAccent or Palette.UIText
	updateSpeedLines(inArena and speed or 0, scopeAlpha > 0.3)

	-- health
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		healthFill.Size = UDim2.fromScale(fraction, 1)
		healthFill.BackgroundColor3 = fraction < 0.35 and Palette.UIDanger or Palette.UIText
		healthText.Text = tostring(math.ceil(humanoid.Health))
	end

	-- timers
	local snapshot = ClientState.Snapshot
	local timeLeft = ClientState.TimeLeft()
	if snapshot.InMatch then
		if snapshot.Phase == "Fight" and timeLeft then
			timerLabel.Text = formatTime(timeLeft)
			timerLabel.TextColor3 = timeLeft < 15 and Palette.UIDanger or Palette.UIText
		else
			timerLabel.Text = ""
		end
		if snapshot.Phase == "Countdown" and timeLeft then
			local n = math.ceil(timeLeft)
			if n ~= lastCountdownNumber and n > 0 then
				lastCountdownNumber = n
				bannerTitle.Text = tostring(n)
				bannerTitle.TextSize = 110
				Theme.tween(bannerTitle, 0.3, { TextSize = 78 }, Enum.EasingStyle.Back)
				Sfx.Play("Countdown")
			end
		end
	end

	-- ability cooldowns
	local cooldowns = Controllers.Movement.GetCooldowns()
	for _, row in ipairs(abilityList:GetChildren()) do
		local fill = row:IsA("Frame") and row:FindFirstChild("CooldownFill")
		if fill then
			local name = fill:GetAttribute("Cooldown")
			local stats = ClientState.Stats
			local total = name == "Grapple" and stats.GrappleCooldown
				or name == "Blink" and math.max(stats.BlinkCooldown, 0.1)
				or name == "Decoy" and Config.PowerUps.Decoy.Cooldown
				or Config.PowerUps.BulletTime.Cooldown
			fill.Size = UDim2.fromScale(math.clamp((cooldowns[name] or 0) / total, 0, 1), 1)
		end
	end
end

function HUD.Init(controllers)
	Controllers = controllers
end

function HUD.Start(playerGui)
	gui = Theme.screen("HUD", 1, playerGui)
	buildScope()
	buildCrosshair()
	buildScoreboard()
	buildHealth()
	buildAbilities()
	buildBanner()
	buildDamage()
	buildSpeedometer()
	buildSpeedLines()

	Remotes.Get("HitConfirm").OnClientEvent:Connect(onHitConfirm)
	Remotes.Get("Damaged").OnClientEvent:Connect(onDamaged)
	RunService.RenderStepped:Connect(update)
end

return HUD
