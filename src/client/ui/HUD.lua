--[[
	HUD.lua  (Client.ui.HUD)

	In-match heads-up display. Two ScreenGuis:

	  "HUD" (full screen, pixel exact, never scaled)
		crosshair (gap = the real hipfire spread cone, dims while the bolt
		    cycles, pops when you can shoot again) + bolt reload bar
		hitmarkers (white body, red headshot, bigger X + fly-out on kills)
		scope overlay (black outside a circle, thin reticle) + Deadeye bar
		damage vignette, low-health pulse, direction indicator, colour flashes
		speed lines

	  "HUDPanels" (device-safe area, one UIScale so phones and 4K both read)
		scoreboard: names, round-win pips, score chips, round + timer,
		    MATCH POINT / FINAL ROUND tag, each player's power-up icons
		health panel (big number, damage trail, shield bar, low-health pulse)
		ability chips with keycaps, cooldown fill, seconds left, ready pop
		centre banner (round intro + 3-2-1 countdown, FIGHT, round won/lost,
		    match point), kill card under the crosshair, callouts, kill feed
		speedometer

	Public: HUD.Init, HUD.Start, HUD.OnState, HUD.Flash, HUD.Hitmarker,
	HUD.Callout, HUD.AddFeed (feed entries from other modules).

	Optional Config.Effects keys (all default on): DamageNumbers, SpeedLines,
	KillFeed, LowHealthPulse, ScreenShake (number, 0 = off).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
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
local FX = Config.Effects or {}
local player = Players.LocalPlayer

local HUD = {}
local Controllers

-- HUD-only colours
local SHIELD = Color3.fromRGB(90, 170, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local HEAL = Color3.fromRGB(90, 230, 140)
local TRAIL = Color3.fromRGB(255, 150, 150)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local gui -- full screen, unscaled
local safeGui, root, rootScale -- device-safe, scaled
local hudScale = 1

local ui = {} -- every built element lives in here
local st = { -- runtime state
	lastWins = {},
	pipCount = {},
	iconSig = {},
	abilitySig = nil,
	abilityRows = {},
	bannerToken = 0,
	hitToken = 0,
	killToken = 0,
	calloutToken = 0,
	lastCountdown = nil,
	lastTimerSecond = nil,
	boltWasCycling = false,
	hpFraction = 1,
	trail = 1,
	trailHoldUntil = 0,
	hpHumanoid = nil,
	hpShown = nil,
	speedShown = nil,
	nextHeartbeat = 0,
	indicatorFrom = nil,
	matchTag = nil,
	feedOrder = 0,
	feedRows = {},
	dmgPool = {},
	dmgCounter = 0,
}

local function fxOn(key)
	return FX[key] ~= false
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function touchLayout()
	return UserInputService.TouchEnabled
end

local function killCamPlaying()
	local kc = Controllers and Controllers.KillCam
	return kc ~= nil and kc.IsPlaying ~= nil and kc.IsPlaying() == true
end

local function textStroke(label, thickness, transparency)
	return Theme.new("UIStroke", {
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.55,
		Color = Palette.UIBackground,
		Parent = label,
	})
end

----------------------------------------------------------------------------
-- Building: full-screen layer
----------------------------------------------------------------------------
local function buildCrosshair()
	ui.crosshair = Theme.new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(90, 90),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local function bar(w, h)
		local f = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = WHITE,
			Parent = ui.crosshair,
		})
		Theme.stroke(f, BLACK, 1, 0.5)
		return f
	end
	ui.crossDot = bar(3, 3)
	ui.crossLines = {
		{ Frame = bar(2, 7), X = 0, Y = -1 },
		{ Frame = bar(2, 7), X = 0, Y = 1 },
		{ Frame = bar(7, 2), X = -1, Y = 0 },
		{ Frame = bar(7, 2), X = 1, Y = 0 },
	}

	ui.boltBar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 30),
		Size = UDim2.fromOffset(40, 3),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.55,
		Visible = false,
		Parent = gui,
	})
	Theme.corner(ui.boltBar, 2)
	ui.boltFill = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		Parent = ui.boltBar,
	})
	Theme.corner(ui.boltFill, 2)

	-- hitmarker: 4 ticks + 4 "ghost" ticks for the kill fly-out (reused)
	ui.hitmarker = Theme.new("Frame", {
		Name = "Hitmarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(90, 90),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	local function ticks()
		local list = {}
		for i = 0, 3 do
			local angle = math.rad(45 + i * 90)
			local frame = Theme.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(10, 3),
				Rotation = 45 + i * 90,
				BackgroundColor3 = Palette.UIHitmarker,
				BackgroundTransparency = 1,
				ZIndex = 6,
				Parent = ui.hitmarker,
			})
			local stroke = Theme.new("UIStroke", { Thickness = 1, Color = BLACK, Transparency = 1, Parent = frame })
			list[i + 1] = { Frame = frame, Stroke = stroke, Angle = angle }
		end
		return list
	end
	ui.ticks = ticks()
	ui.ghostTicks = ticks()
end

local function buildScope()
	local scope = Theme.new("Frame", {
		Name = "Scope",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	ui.scope = scope
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
		local viewport = viewportSize()
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
	-- small range ticks on the lower post
	for i = 1, 3 do
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5 + i * 0.045, 0),
			Size = UDim2.fromOffset(14 - i * 2, 2),
			BackgroundColor3 = dark,
			Parent = lens,
		})
	end
	-- centre dot
	local dot = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Palette.UIDanger,
		Parent = lens,
	})
	Theme.corner(dot, UDim.new(0.5, 0))

	-- DEADEYE: charge bar below the centre (gold when the shot is charged)
	ui.deadeyeBar = Theme.new("Frame", {
		Name = "DeadeyeCharge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 40),
		Size = UDim2.fromOffset(120, 5),
		BackgroundColor3 = Color3.fromRGB(30, 34, 44),
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = scope,
	})
	Theme.corner(ui.deadeyeBar, 3)
	ui.deadeyeFill = Theme.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Palette.UIText,
		Parent = ui.deadeyeBar,
	})
	Theme.corner(ui.deadeyeFill, 3)
end

-- Speed lines: thin streaks at the screen edges when you're moving fast.
local function buildSpeedLines()
	ui.speedLinesFrame = Theme.new("Frame", {
		Name = "SpeedLines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	ui.speedLines = {}
	for i = 1, 18 do
		local line = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			Parent = ui.speedLinesFrame,
		})
		Theme.new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }),
			Parent = line,
		})
		ui.speedLines[i] = { Frame = line, Angle = (i / 18) * math.pi * 2 }
	end
end

local function updateSpeedLines(speed, scoped)
	local from = FX.SpeedLinesFrom or 44
	local alpha = fxOn("SpeedLines") and not scoped and math.clamp((speed - from) / 45, 0, 1) or 0
	ui.speedLinesFrame.Visible = alpha > 0
	if alpha <= 0 then
		return
	end
	local viewport = viewportSize()
	local center = viewport / 2
	local radius = math.min(viewport.X, viewport.Y) * 0.42
	for _, l in ipairs(ui.speedLines) do
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

-- Four soft red edges (gradients). Returns the holder and its edge frames.
local function edgeVignette(name, color)
	local holder = Theme.new("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local edges = {}
	local layout = {
		{ UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0.75), -90 },
		{ UDim2.fromScale(0.2, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.2, 1), UDim2.fromScale(0.8, 0), 180 },
	}
	for _, e in ipairs(layout) do
		local f = Theme.new("Frame", {
			Size = e[1],
			Position = e[2],
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			Parent = holder,
		})
		Theme.new("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new(0, 1), Parent = f })
		table.insert(edges, f)
	end
	return holder, edges
end

local function buildDamage()
	ui.vignette, ui.vignetteEdges = edgeVignette("DamageVignette", Palette.UIDanger)
	ui.lowVignette, ui.lowEdges = edgeVignette("LowHealth", Color3.fromRGB(200, 20, 40))

	ui.indicator = Theme.new("Frame", {
		Name = "DamageIndicator",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(250, 250),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	-- an arc-ish wedge: a wide bar with a short thick centre
	ui.indicatorBars = {
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(70, 4),
			BackgroundColor3 = Palette.UIDanger,
			Parent = ui.indicator,
		}),
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, -5),
			Size = UDim2.fromOffset(26, 6),
			BackgroundColor3 = Palette.UIDanger,
			Parent = ui.indicator,
		}),
	}
	for _, b in ipairs(ui.indicatorBars) do
		Theme.corner(b, 3)
	end

	-- one reusable full-screen colour flash (Second Wind, Jammed...)
	ui.flash = Theme.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = gui,
	})
end

----------------------------------------------------------------------------
-- Building: scaled panels
----------------------------------------------------------------------------
local function pill(props, text, textSize)
	local frame = Theme.new("Frame", {
		Name = props.Name or "Pill",
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0),
		Position = props.Position or UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, props.Height or 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = props.Color or Palette.UIDanger,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	Theme.corner(frame, UDim.new(0.5, 0))
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = frame })
	local label = Theme.label({
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text or "",
		TextSize = textSize or 11,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = frame,
	})
	return frame, label
end

local function buildScoreboard()
	local sb = Theme.new("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(520, 150),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	ui.scoreboard = sb
	local panel = Theme.new("Frame", {
		Name = "Panel",
		Size = UDim2.fromOffset(520, 58),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.22,
		Parent = sb,
	})
	Theme.corner(panel, 14)
	Theme.stroke(panel, Palette.UIText, 1, 0.88)
	ui.scorePanel = panel
	ui.names, ui.wins, ui.chips, ui.pipRows, ui.iconRows = {}, {}, {}, {}, {}
	for slot = 1, 2 do
		local left = slot == 1
		local color = ClientState.GetSlotColor(slot)
		local sideX = left and 0 or 1
		local edge = Theme.new("Frame", {
			AnchorPoint = Vector2.new(sideX, 0.5),
			Position = UDim2.new(sideX, left and 6 or -6, 0.5, 0),
			Size = UDim2.fromOffset(4, 30),
			BackgroundColor3 = color,
			Parent = panel,
		})
		Theme.corner(edge, 2)
		ui.names[slot] = Theme.label({
			AnchorPoint = Vector2.new(sideX, 0),
			Position = UDim2.new(sideX, left and 18 or -18, 0, 9),
			Size = UDim2.fromOffset(124, 20),
			TextXAlignment = left and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "-",
			Parent = panel,
		})
		ui.pipRows[slot] = Theme.new("Frame", {
			AnchorPoint = Vector2.new(sideX, 0),
			Position = UDim2.new(sideX, left and 18 or -18, 0, 35),
			Size = UDim2.fromOffset(124, 8),
			BackgroundTransparency = 1,
			Parent = panel,
		}, {
			Theme.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local chip = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, left and -86 or 86, 0.5, 0),
			Size = UDim2.fromOffset(48, 44),
			BackgroundColor3 = color,
			Parent = panel,
		})
		Theme.corner(chip, 10)
		Theme.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 190, 200)),
			Parent = chip,
		})
		ui.chips[slot] = chip
		ui.wins[slot] = Theme.label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 28,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Text = "0",
			Parent = chip,
		})
		textStroke(ui.wins[slot], 1.5, 0.6)
		-- collected power-ups under each player (7 per row)
		ui.iconRows[slot] = Theme.new("Frame", {
			AnchorPoint = Vector2.new(sideX, 0),
			Position = UDim2.new(sideX, 0, 0, 64),
			Size = UDim2.fromOffset(196, 84),
			BackgroundTransparency = 1,
			Parent = sb,
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
	ui.roundLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(110, 14),
		TextSize = 11,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		Parent = panel,
	})
	ui.timerLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.fromOffset(110, 28),
		TextSize = 22,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	ui.matchTag, ui.matchTagLabel = pill({
		Name = "MatchPoint",
		Position = UDim2.new(0.5, 0, 0, 64),
		Visible = false,
		Parent = sb,
	}, "MATCH POINT", 11)
end

local function buildHealth()
	local panel = Theme.new("Frame", {
		Name = "Health",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -20),
		Size = UDim2.fromOffset(280, 58),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.22,
		Visible = false,
		Parent = root,
	})
	Theme.corner(panel, 12)
	ui.healthStroke = Theme.stroke(panel, Palette.UIText, 1, 0.88)
	ui.health = panel
	ui.healthText = Theme.label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(62, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 30,
		Text = "100",
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	Theme.label({
		Position = UDim2.fromOffset(84, 11),
		Size = UDim2.fromOffset(80, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "HEALTH",
		TextSize = 10,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	ui.shieldText = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 11),
		Size = UDim2.fromOffset(100, 12),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 10,
		TextColor3 = SHIELD,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Visible = false,
		Parent = panel,
	})
	local track = Theme.new("Frame", {
		Position = UDim2.fromOffset(84, 27),
		Size = UDim2.new(1, -98, 0, 10),
		BackgroundColor3 = Palette.UIPanelLight,
		ClipsDescendants = true,
		Parent = panel,
	})
	Theme.corner(track, 5)
	ui.trailFill = Theme.new("Frame", {
		Name = "Trail",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = TRAIL,
		Parent = track,
	})
	Theme.corner(ui.trailFill, 5)
	ui.healthFill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIText,
		Parent = track,
	})
	Theme.corner(ui.healthFill, 5)
	-- quarter dividers so damage reads in chunks
	for i = 1, 3 do
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(i / 4, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = Palette.UIBackground,
			BackgroundTransparency = 0.35,
			ZIndex = 2,
			Parent = track,
		})
	end
	-- SHIELD (Overshield / Bloodlust): a blue strip under the health bar
	local shieldTrack = Theme.new("Frame", {
		Position = UDim2.fromOffset(84, 41),
		Size = UDim2.new(1, -98, 0, 4),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	ui.shieldFill = Theme.new("Frame", {
		Name = "Shield",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = SHIELD,
		Visible = false,
		Parent = shieldTrack,
	})
	Theme.corner(ui.shieldFill, 2)
end

local function buildAbilities()
	ui.abilityList = Theme.new("Frame", {
		Name = "Abilities",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(230, 330), -- room for every active power-up
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Theme.new("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	ui.abilityLayout = ui.abilityList:FindFirstChildOfClass("UIListLayout")
end

local function buildBanner()
	local banner = Theme.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.new(1, 0, 0, 170),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	ui.banner = banner
	ui.bannerBand = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.45,
		Parent = banner,
	})
	ui.bannerBandGradient = Theme.fade(ui.bannerBand, 0, { { 0, 1 }, { 0.3, 0 }, { 0.7, 0 }, { 1, 1 } })
	ui.bannerRing = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = banner,
	})
	Theme.corner(ui.bannerRing, UDim.new(0.5, 0))
	ui.bannerRingStroke = Theme.stroke(ui.bannerRing, WHITE, 4, 1)
	ui.bannerTag, ui.bannerTagLabel = pill({
		Name = "Tag",
		Position = UDim2.new(0.5, 0, 0, 0),
		Height = 22,
		Visible = false,
		Parent = banner,
	}, "", 12)
	ui.bannerTitle = Theme.label({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 80),
		TextSize = 72,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = banner,
	})
	textStroke(ui.bannerTitle, 2, 0.5)
	ui.bannerLine = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(0, 4),
		BackgroundColor3 = Palette.UIAccent,
		Parent = banner,
	})
	Theme.corner(ui.bannerLine, 2)
	ui.bannerSub = Theme.label({
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 28),
		TextSize = 20,
		TextColor3 = Palette.UISubText,
		Parent = banner,
	})
	textStroke(ui.bannerSub, 1, 0.6)
end

-- The kill card under the crosshair ("HEADSHOT / their name") + callouts above it.
local function buildKillCard()
	local card = Theme.new("CanvasGroup", {
		Name = "KillCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 64),
		Size = UDim2.fromOffset(440, 72),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = root,
	})
	ui.killCard = card
	ui.killTitle = Theme.label({
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 28,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = card,
	})
	textStroke(ui.killTitle, 1.5, 0.45)
	ui.killLine = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 37),
		Size = UDim2.fromOffset(0, 3),
		BackgroundColor3 = Palette.UIAccent,
		Parent = card,
	})
	Theme.corner(ui.killLine, 2)
	ui.killSub = Theme.label({
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 15,
		TextColor3 = Palette.UIText,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		Parent = card,
	})
	textStroke(ui.killSub, 1, 0.6)

	ui.callout = Theme.label({
		Name = "Callout",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -70),
		Size = UDim2.fromOffset(600, 34),
		TextSize = 26,
		TextTransparency = 1,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Visible = false,
		Parent = root,
	})
	ui.calloutStroke = textStroke(ui.callout, 2, 1)
end

local function buildKillFeed()
	ui.feed = Theme.new("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 60),
		Size = UDim2.fromOffset(340, 130),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Theme.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

-- Speedometer (bottom centre): your horizontal speed, handy for bunny hopping.
local function buildSpeedometer()
	ui.speedLabel = Theme.label({
		Name = "Speed",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(160, 22),
		TextSize = 17,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		TextTransparency = 0.15,
		Parent = root,
	})
	textStroke(ui.speedLabel, 1.5, 0.6)
end

-- Panels follow the screen: one UIScale for everything in `root`, the kill
-- feed under Roblox's top bar, abilities above the health panel on touch
-- screens (the right side is full of buttons there).
local function fit()
	local vp = viewportSize()
	hudScale = math.clamp(math.min(vp.X / 1100, vp.Y / 620), 0.68, 1.3)
	rootScale.Scale = hudScale
	root.Size = UDim2.fromScale(1 / hudScale, 1 / hudScale)
	local topInset = 36
	pcall(function()
		topInset = GuiService:GetGuiInset().Y
	end)
	ui.feed.Position = UDim2.new(1, -14, 0, math.floor((topInset + 10) / hudScale))
	if touchLayout() then
		ui.abilityList.AnchorPoint = Vector2.new(0, 1)
		ui.abilityList.Position = UDim2.new(0, 20, 1, -90)
		ui.abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	else
		ui.abilityList.AnchorPoint = Vector2.new(1, 1)
		ui.abilityList.Position = UDim2.new(1, -20, 1, -20)
		ui.abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
end

----------------------------------------------------------------------------
-- Banner
----------------------------------------------------------------------------
local function showBanner(title, sub, color, duration, tag, tagColor)
	st.bannerToken += 1
	local token = st.bannerToken
	local banner = ui.banner
	color = color or Palette.UIText
	banner.Visible = true
	ui.bannerTitle.Text = title
	ui.bannerTitle.TextColor3 = color
	ui.bannerSub.Text = sub or ""
	-- punch in: big + transparent -> normal, band opens, underline wipes, subtitle fades
	ui.bannerTitle.TextTransparency = 1
	ui.bannerTitle.TextSize = 104
	Theme.tween(ui.bannerTitle, 0.3, { TextSize = 72, TextTransparency = 0 }, Enum.EasingStyle.Back)
	ui.bannerBand.BackgroundTransparency = 0.45
	ui.bannerBand.Size = UDim2.new(1, 0, 0, 0)
	Theme.tween(ui.bannerBand, 0.3, { Size = UDim2.new(1, 0, 0, title == "" and 60 or 100) }, Enum.EasingStyle.Quint)
	ui.bannerLine.BackgroundColor3 = color
	ui.bannerLine.BackgroundTransparency = 0
	ui.bannerLine.Size = UDim2.fromOffset(0, 4)
	Theme.tween(ui.bannerLine, 0.4, { Size = UDim2.fromOffset(title == "" and 0 or 280, 4) }, Enum.EasingStyle.Quint)
	ui.bannerSub.TextTransparency = 1
	Theme.tween(ui.bannerSub, 0.5, { TextTransparency = 0 })
	ui.bannerTag.Visible = tag ~= nil
	if tag then
		ui.bannerTagLabel.Text = tag
		ui.bannerTag.BackgroundColor3 = tagColor or Palette.UIDanger
		ui.bannerTag.BackgroundTransparency = 0
		ui.bannerTagLabel.TextTransparency = 0
		Theme.pop(ui.bannerTag, 0.3)
	end
	if duration then
		task.delay(duration, function()
			if st.bannerToken ~= token then
				return
			end
			Theme.tween(ui.bannerTitle, 0.25, { TextTransparency = 1 })
			Theme.tween(ui.bannerSub, 0.25, { TextTransparency = 1 })
			Theme.tween(ui.bannerLine, 0.25, { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 4) })
			Theme.tween(ui.bannerBand, 0.25, { BackgroundTransparency = 1 })
			Theme.tween(ui.bannerTag, 0.25, { BackgroundTransparency = 1 })
			Theme.tween(ui.bannerTagLabel, 0.25, { TextTransparency = 1 })
			task.wait(0.27)
			if st.bannerToken == token then
				banner.Visible = false
			end
		end)
	end
end

local function hideBanner()
	st.bannerToken += 1
	if ui.banner then
		ui.banner.Visible = false
	end
end

-- a ring that pulses out of the banner centre (countdown ticks, FIGHT)
local function bannerPulse(color)
	local ring = ui.bannerRing
	ring.Visible = true
	ring.Size = UDim2.fromOffset(50, 50)
	ui.bannerRingStroke.Color = color or WHITE
	ui.bannerRingStroke.Transparency = 0.1
	ui.bannerRingStroke.Thickness = 5
	Theme.tween(ring, 0.55, { Size = UDim2.fromOffset(230, 230) }, Enum.EasingStyle.Quint)
	Theme.tween(ui.bannerRingStroke, 0.55, { Transparency = 1, Thickness = 1 })
end

-- Short text above the crosshair (Second Wind, Jammed...). Never touches the banner.
function HUD.Callout(text, color)
	if not ui.callout then
		return
	end
	st.calloutToken += 1
	local token = st.calloutToken
	local label = ui.callout
	label.Visible = true
	label.Text = tostring(text)
	label.TextColor3 = color or Palette.UIText
	label.TextTransparency = 0
	ui.calloutStroke.Transparency = 0.45
	Theme.pop(label, 0.25)
	task.delay(1.1, function()
		if st.calloutToken == token then
			Theme.tween(label, 0.3, { TextTransparency = 1 })
			Theme.tween(ui.calloutStroke, 0.3, { Transparency = 1 })
		end
	end)
end

-- Short coloured flash + text (Second Wind etc.)
function HUD.Flash(color, text)
	if not gui then
		return
	end
	ui.flash.BackgroundColor3 = color or WHITE
	ui.flash.BackgroundTransparency = 0.6
	Theme.tween(ui.flash, 0.6, { BackgroundTransparency = 1 })
	if text then
		HUD.Callout(text, color)
	end
end

----------------------------------------------------------------------------
-- Kill feed (top right): "killer [x] victim [HEADSHOT]", newest on top
----------------------------------------------------------------------------
local FEED_MAX = 4
local FEED_TIME = 6

local function makeFeedRow()
	local row = Theme.new("CanvasGroup", {
		Name = "FeedRow",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = ui.feed,
	})
	Theme.corner(row, 8)
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = row })
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local function name(order)
		return Theme.label({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 13,
			LayoutOrder = order,
			Parent = row,
		})
	end
	local killer = name(1)
	local icon = Theme.icon("target", 14, Palette.UIText)
	icon.LayoutOrder = 2
	icon.Parent = row
	local victim = name(3)
	local tag, tagLabel = pill({ Height = 16, Color = Palette.UIHeadshot, Parent = row }, "", 10)
	tag.AnchorPoint = Vector2.new(0, 0)
	tag.LayoutOrder = 4
	return { Frame = row, Killer = killer, Icon = icon, Victim = victim, Tag = tag, TagLabel = tagLabel, Token = 0 }
end

-- Adds a kill feed entry. Colours default to the slot colours.
function HUD.AddFeed(killerName, killerColor, victimName, victimColor, tag, tagColor)
	if not ui.feed or not fxOn("KillFeed") then
		return
	end
	local entry
	for _, r in ipairs(st.feedRows) do
		if not r.Frame.Visible then
			entry = r
			break
		end
	end
	if not entry then
		if #st.feedRows < FEED_MAX then
			entry = makeFeedRow()
			table.insert(st.feedRows, entry)
		else
			-- recycle the oldest
			entry = st.feedRows[1]
			for _, r in ipairs(st.feedRows) do
				if r.Frame.LayoutOrder > entry.Frame.LayoutOrder then
					entry = r
				end
			end
		end
	end
	st.feedOrder -= 1
	entry.Token += 1
	local token = entry.Token
	local row = entry.Frame
	row.LayoutOrder = st.feedOrder
	entry.Killer.Text = tostring(killerName or "?")
	entry.Killer.TextColor3 = killerColor or Palette.UIText
	entry.Victim.Text = tostring(victimName or "?")
	entry.Victim.TextColor3 = victimColor or Palette.UIText
	entry.Tag.Visible = tag ~= nil
	if tag then
		entry.TagLabel.Text = tag
		entry.Tag.BackgroundColor3 = tagColor or Palette.UIHeadshot
	end
	row.Visible = true
	row.GroupTransparency = 1
	Theme.tween(row, 0.2, { GroupTransparency = 0 })
	Theme.pop(row, 0.12)
	task.delay(FEED_TIME, function()
		if entry.Token ~= token then
			return
		end
		Theme.tween(row, 0.4, { GroupTransparency = 1 })
		task.delay(0.42, function()
			if entry.Token == token then
				row.Visible = false
			end
		end)
	end)
end

local function clearFeed()
	for _, r in ipairs(st.feedRows) do
		r.Token += 1
		r.Frame.Visible = false
	end
end

local function slotOf(userId)
	for slot, entry in ipairs(ClientState.Snapshot.Players or {}) do
		if entry.UserId == userId then
			return slot, entry
		end
	end
	return nil, nil
end

----------------------------------------------------------------------------
-- Hits and damage
----------------------------------------------------------------------------
-- The X on a hit: the four ticks snap in from further out, hold for a
-- moment and fade. Headshots are red, kills are bigger and red, with a
-- second, wider X that flies out.
function HUD.Hitmarker(headshot, killed)
	if not ui.hitmarker then
		return
	end
	st.hitToken += 1
	local token = st.hitToken
	local color = (headshot or killed) and Palette.UIHeadshot or Palette.UIHitmarker
	local length, thick = killed and 16 or (headshot and 13 or 10), killed and 4 or 3
	local radius = killed and 13 or (headshot and 11 or 9)
	for _, t in ipairs(ui.ticks) do
		local cos, sin = math.cos(t.Angle), math.sin(t.Angle)
		t.Frame.BackgroundColor3 = color
		t.Frame.BackgroundTransparency = 0
		t.Stroke.Transparency = 0.45
		t.Frame.Size = UDim2.fromOffset(length * 1.4, thick)
		t.Frame.Position = UDim2.new(0.5, cos * (radius + 9), 0.5, sin * (radius + 9))
		Theme.tween(t.Frame, 0.07, {
			Position = UDim2.new(0.5, cos * radius, 0.5, sin * radius),
			Size = UDim2.fromOffset(length, thick),
		})
	end
	ui.hitmarker.Visible = true
	ui.hitmarker.Rotation = killed and -14 or (headshot and -6 or 0)
	Theme.tween(ui.hitmarker, 0.15, { Rotation = 0 }, Enum.EasingStyle.Back)
	task.delay(killed and 0.34 or 0.2, function()
		if token ~= st.hitToken then
			return -- a newer hit took over
		end
		for _, t in ipairs(ui.ticks) do
			Theme.tween(t.Frame, 0.25, { BackgroundTransparency = 1 })
			Theme.tween(t.Stroke, 0.25, { Transparency = 1 })
		end
		task.delay(0.3, function()
			if token == st.hitToken then
				ui.hitmarker.Visible = false
			end
		end)
	end)
	-- the wide X flying out (kills)
	for _, g in ipairs(ui.ghostTicks) do
		if killed then
			local cos, sin = math.cos(g.Angle), math.sin(g.Angle)
			g.Frame.BackgroundColor3 = color
			g.Frame.Size = UDim2.fromOffset(length, thick)
			g.Frame.Position = UDim2.new(0.5, cos * radius, 0.5, sin * radius)
			g.Frame.BackgroundTransparency = 0.2
			g.Stroke.Transparency = 0.5
			Theme.tween(g.Frame, 0.38, {
				Position = UDim2.new(0.5, cos * 36, 0.5, sin * 36),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quint)
			Theme.tween(g.Stroke, 0.38, { Transparency = 1 })
		else
			g.Frame.BackgroundTransparency = 1
			g.Stroke.Transparency = 1
		end
	end
end

local function shakeScale()
	local s = FX.ScreenShake
	if s == false then
		return 0
	end
	return typeof(s) == "number" and s or 1
end

local function onDamaged(data)
	if typeof(data) ~= "table" then
		return
	end
	local damage = typeof(data.Damage) == "number" and data.Damage or 30
	local dot = data.Dot == true -- bleed / acid tick: just a faint edge, no sound or shake
	if not dot then
		Sfx.Play("Hurt")
	end
	ui.vignette.Visible = true
	local strength = dot and 0.15 or math.clamp(damage / 60, 0.35, 1)
	for _, edge in ipairs(ui.vignetteEdges) do
		edge.BackgroundTransparency = 0.55 - strength * 0.35
		Theme.tween(edge, 0.75, { BackgroundTransparency = 1 })
	end
	if not dot and Controllers and Controllers.Camera then
		Controllers.Camera.Shake(math.clamp(damage / 35, 1, 3) * shakeScale())
	end
	Theme.pop(ui.healthText, dot and 0.12 or 0.35)
	-- point toward the attacker (kept pointing at that spot while it fades)
	if not dot and typeof(data.From) == "Vector3" then
		st.indicatorFrom = data.From
		ui.indicator.Visible = true
		for _, b in ipairs(ui.indicatorBars) do
			b.BackgroundTransparency = 0
			Theme.tween(b, 1.3, { BackgroundTransparency = 1 })
		end
		local camera = workspace.CurrentCamera
		if camera and Controllers and Controllers.Camera and Controllers.Camera.Flinch then
			local localDir = camera.CFrame:VectorToObjectSpace(data.From - camera.CFrame.Position)
			Controllers.Camera.Flinch(localDir.X < 0 and 1 or -1, math.clamp(damage / 50, 0.4, 1.4))
		end
	end
	if data.Killed and ClientState.InMatch() then
		local opp = ClientState.GetOpponentEntry()
		local oppSlot = opp and slotOf(opp.UserId)
		local mySlot = slotOf(player.UserId)
		HUD.AddFeed(
			opp and opp.Name or "OPPONENT",
			oppSlot and ClientState.GetSlotColor(oppSlot),
			"YOU",
			mySlot and ClientState.GetSlotColor(mySlot),
			dot and "BLED OUT" or nil,
			dot and Palette.AccentB or nil
		)
	end
end

-- Floating damage numbers (pooled BillboardGuis): rise, pop and fade.
local DMG_POOL_MAX = 6
local function getDamageNumber()
	local best
	for _, d in ipairs(st.dmgPool) do
		if not d.Busy then
			best = d
			break
		end
	end
	if not best and #st.dmgPool < DMG_POOL_MAX then
		local anchor = Instance.new("Attachment")
		anchor.Name = "DamageNumberAnchor"
		anchor.Parent = workspace.Terrain
		local billboard = Theme.new("BillboardGui", {
			Name = "DamageNumber",
			Adornee = anchor,
			Size = UDim2.fromOffset(170, 50),
			AlwaysOnTop = true,
			LightInfluence = 0,
			Enabled = false,
			ResetOnSpawn = false,
			Parent = gui.Parent, -- BillboardGuis live directly in PlayerGui
		})
		local label = Theme.label({
			Size = UDim2.fromScale(1, 1),
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = billboard,
		})
		local stroke = Theme.new("UIStroke", { Thickness = 2, Color = Palette.UIBackground, Transparency = 0.2, Parent = label })
		best = { Anchor = anchor, Billboard = billboard, Label = label, Stroke = stroke, Busy = false, Order = 0 }
		table.insert(st.dmgPool, best)
	end
	if not best then
		best = st.dmgPool[1]
		for _, d in ipairs(st.dmgPool) do
			if d.Order < best.Order then
				best = d
			end
		end
	end
	st.dmgCounter += 1
	best.Order = st.dmgCounter
	best.Busy = true
	return best
end

local function damageNumber(position, amount, headshot, splash, killed, dot)
	if not fxOn("DamageNumbers") or typeof(position) ~= "Vector3" or typeof(amount) ~= "number" then
		return
	end
	local d = getDamageNumber()
	local order = d.Order
	if d.Anchor.Parent ~= workspace.Terrain then
		d.Anchor.Parent = workspace.Terrain
	end
	d.Anchor.WorldPosition = position
	local offset = Vector3.new((math.random() - 0.5) * 1.5, 1, 0)
	d.Billboard.StudsOffsetWorldSpace = offset
	d.Billboard.Enabled = true
	local color = headshot and Palette.UIHeadshot or splash and Palette.TracerExplosive or killed and Palette.UIAccent or Palette.UIText
	d.Label.Text = headshot and "HEADSHOT" or tostring(math.floor(amount + 0.5))
	d.Label.TextSize = dot and 14 or headshot and 30 or math.clamp(18 + amount * 0.12, 18, 34)
	d.Label.TextColor3 = dot and Palette.UISubText or color
	d.Label.TextTransparency = dot and 0.3 or 0
	d.Stroke.Transparency = dot and 0.5 or 0.2
	Theme.pop(d.Label, dot and 0.15 or headshot and 0.7 or 0.5)
	Theme.tween(d.Billboard, 0.8, { StudsOffsetWorldSpace = offset + Vector3.new(0, 3, 0) }, Enum.EasingStyle.Quint)
	task.delay(0.45, function()
		if d.Order == order then
			Theme.tween(d.Label, 0.35, { TextTransparency = 1 })
			Theme.tween(d.Stroke, 0.35, { Transparency = 1 })
		end
	end)
	task.delay(0.85, function()
		if d.Order == order then
			d.Billboard.Enabled = false
			d.Busy = false
		end
	end)
end

local function showKillCard(title, sub, color)
	st.killToken += 1
	local token = st.killToken
	local card = ui.killCard
	card.Visible = true
	card.GroupTransparency = 1
	card.Position = UDim2.new(0.5, 0, 0.5, 78)
	Theme.tween(card, 0.18, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 64) }, Enum.EasingStyle.Quint)
	ui.killTitle.Text = title
	ui.killTitle.TextColor3 = color
	ui.killSub.Text = sub or ""
	ui.killLine.BackgroundColor3 = color
	ui.killLine.Size = UDim2.fromOffset(0, 3)
	Theme.tween(ui.killLine, 0.35, { Size = UDim2.fromOffset(170, 3) }, Enum.EasingStyle.Quint)
	Theme.pop(ui.killTitle, 0.3)
	task.delay(1.6, function()
		if st.killToken ~= token then
			return
		end
		Theme.tween(card, 0.3, { GroupTransparency = 1 })
		task.delay(0.32, function()
			if st.killToken == token then
				card.Visible = false
			end
		end)
	end)
end

local function onHitConfirm(data)
	if typeof(data) ~= "table" then
		return
	end
	local dot = data.Dot == true and not data.Killed -- bleed / acid tick
	if not dot then
		HUD.Hitmarker(data.Headshot, data.Killed)
	end
	damageNumber(data.Position, data.Damage, data.Headshot, data.Splash, data.Killed, dot)
	if dot then
		return
	elseif data.Killed then
		local viewport = viewportSize()
		local accent = data.Headshot and Palette.UIHeadshot or Palette.UIAccent
		Theme.burst(gui, viewport / 2, accent, 18, 120, 7)
		Theme.ring(gui, viewport / 2, data.Headshot and Palette.UIHeadshot or WHITE, 170, 5)
		Sfx.Play("Kill")
		Sfx.Play("KillThump")
		Sfx.Play("HitTick", { Pitch = 0.85 })
		if data.Headshot then
			task.delay(0.05, Sfx.Play, "Ding")
		end
		if Controllers and Controllers.Camera and Controllers.Camera.AddFovPunch then
			Controllers.Camera.AddFovPunch(3)
		end
		local inMatch = ClientState.InMatch()
		local opp = inMatch and ClientState.GetOpponentEntry() or nil
		local victim = opp and opp.Name or (inMatch and "OPPONENT" or "PRACTICE TARGET")
		local title, color, tag
		if data.Backstab then
			title, color, tag = "BACKSTAB", Palette.AccentB, "BACKSTAB"
		elseif data.Melee then
			title, color, tag = "KNIFED", Palette.UIAccent, "KNIFE"
		elseif data.Headshot then
			title, color, tag = "HEADSHOT", Palette.UIHeadshot, "HEADSHOT"
		elseif data.Dot then
			title, color, tag = "BLED OUT", Palette.AccentB, "BLED OUT"
		else
			title, color = "ELIMINATED", Palette.UIText
		end
		showKillCard(title, string.upper(victim), color)
		if inMatch then
			local mySlot = slotOf(player.UserId)
			local oppSlot = opp and slotOf(opp.UserId)
			HUD.AddFeed(
				"YOU",
				mySlot and ClientState.GetSlotColor(mySlot),
				victim,
				oppSlot and ClientState.GetSlotColor(oppSlot),
				tag,
				(data.Backstab or data.Dot) and Palette.AccentB or (data.Melee and Palette.UIAccent or Palette.UIHeadshot)
			)
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
		local entry = snapshot.Players and snapshot.Players[slot]
		local owned = entry and entry.PowerUps or {}
		-- only rebuild when this player's power-ups changed
		local parts = {}
		for _, def in ipairs(PowerUps.Definitions) do
			local stacks = owned[def.Id]
			if stacks and stacks > 0 then
				table.insert(parts, def.Id .. "x" .. stacks)
			end
		end
		local sig = table.concat(parts, ",")
		if st.iconSig[slot] ~= sig then
			st.iconSig[slot] = sig
			local row = ui.iconRows[slot]
			for _, child in ipairs(row:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local order = 0
			for _, def in ipairs(PowerUps.Definitions) do
				local stacks = owned[def.Id]
				if stacks and stacks > 0 then
					order += 1
					local icon = Icons.Create(def, 24)
					icon.LayoutOrder = order
					local rarity = Config.Rarity[def.Rarity]
					Theme.stroke(icon, rarity and rarity.Color or Palette.UIText, 1.5, 0)
					if stacks > 1 then
						local count = Theme.label({
							AnchorPoint = Vector2.new(1, 1),
							Position = UDim2.new(1, 3, 1, 3),
							Size = UDim2.fromOffset(14, 12),
							Text = "x" .. stacks,
							TextSize = 10,
							FontFace = Theme.Font(Enum.FontWeight.Heavy),
							Parent = icon,
						})
						textStroke(count, 1, 0.3)
					end
					icon.Parent = row
				end
			end
		end
	end
end

local function rebuildPips(slot, total)
	if st.pipCount[slot] == total then
		return
	end
	st.pipCount[slot] = total
	local row = ui.pipRows[slot]
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local width = math.clamp(math.floor((124 - (total - 1) * 4) / math.max(total, 1)), 6, 16)
	for i = 1, total do
		local pip = Theme.new("Frame", {
			Name = "Pip" .. i,
			Size = UDim2.fromOffset(width, 6),
			BackgroundColor3 = Palette.UIPanelLight,
			-- both rows fill from the panel's outer edge
			LayoutOrder = slot == 1 and i or -i,
			Parent = row,
		})
		Theme.corner(pip, 3)
	end
end

local function setPips(slot, wins, animate)
	local color = ClientState.GetSlotColor(slot)
	for _, pip in ipairs(ui.pipRows[slot]:GetChildren()) do
		if pip:IsA("Frame") then
			local i = tonumber(pip.Name:sub(4)) or 0
			local filled = i <= wins
			pip.BackgroundColor3 = filled and color or Palette.UIPanelLight
			if animate and i == wins then
				Theme.pop(pip, 0.8)
			end
		end
	end
end

local function cooldownTotal(name)
	local stats = ClientState.Stats
	local PU = Config.PowerUps
	return name == "Grapple" and math.max(stats.GrappleCooldown or 0.1, 0.1)
		or name == "Blink" and math.max(stats.BlinkCooldown or 0.1, 0.1)
		or name == "Decoy" and PU.Decoy.Cooldown
		or name == "Barrier" and PU.BarrierDome.Cooldown
		or name == "Recall" and math.max(stats.RecallCooldown or 0.1, 0.1)
		or name == "Smoke" and math.max(stats.SmokeCooldown or 0.1, 0.1)
		or name == "AirDash" and PU.AirDash.Cooldown
		or PU.BulletTime.Cooldown
end

local function abilityEntries()
	local stats = ClientState.Stats
	local device = UserInputService:GetLastInputType().Name:find("Gamepad") and "Gamepad" or "Keyboard"
	-- phones: the on-screen buttons are the keys
	local showKeys = device == "Gamepad" or not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	local function key(actionId)
		if not showKeys then
			return nil
		end
		local ok, label = pcall(function()
			return Keybinds.Label(Keybinds.Get(actionId, device))
		end)
		return ok and label or nil
	end
	local entries = {}
	local function add(flag, action, name, cooldown)
		if flag then
			table.insert(entries, { Key = key(action), Name = name, Cooldown = cooldown })
		end
	end
	add(stats.Grapple, "Grapple", "Grapple", "Grapple")
	add(stats.Blink, "Blink", "Blink", "Blink")
	add(stats.Decoy, "Decoy", "Decoy", "Decoy")
	add(stats.BulletTime, "Scope", "Bullet Time (air)", "BulletTime")
	add(stats.Barrier, "Barrier", "Barrier Dome", "Barrier")
	add(stats.Recall, "Recall", "Recall", "Recall")
	add(stats.Smoke, "Smoke", "Smoke Grenade", "Smoke")
	add(stats.AirDash, "Sprint", "Air Dash (in air)", "AirDash")
	return entries
end

local function refreshAbilities()
	local entries = abilityEntries()
	local parts = {}
	for _, e in ipairs(entries) do
		table.insert(parts, e.Name .. "=" .. tostring(e.Key))
	end
	local sig = table.concat(parts, ";")
	if sig == st.abilitySig then
		return
	end
	st.abilitySig = sig
	for _, row in ipairs(st.abilityRows) do
		row.Frame:Destroy()
	end
	table.clear(st.abilityRows)
	for i, e in ipairs(entries) do
		local frame = Theme.new("Frame", {
			Name = e.Name,
			Size = UDim2.fromOffset(212, 34),
			BackgroundColor3 = Palette.UIBackground,
			BackgroundTransparency = 0.22,
			LayoutOrder = i,
			ClipsDescendants = true,
			Parent = ui.abilityList,
		})
		Theme.corner(frame, 10)
		local stroke = Theme.stroke(frame, Palette.UIText, 1, 0.88)
		local textX = 12
		if e.Key then
			local cap = Theme.keycap(e.Key, 11, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				ZIndex = 3,
				Parent = frame,
			})
			cap.Size = UDim2.fromOffset(math.min(Theme.keycapWidth(e.Key, 11), 80), 22)
			for _, d in ipairs(cap:GetDescendants()) do
				if d:IsA("GuiObject") then
					d.ZIndex = 3
				end
			end
			textX = 6 + cap.Size.X.Offset + 8
		end
		Theme.label({
			Position = UDim2.fromOffset(textX, 0),
			Size = UDim2.new(1, -(textX + 40), 1, 0),
			Text = e.Name,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = Theme.Font(Enum.FontWeight.SemiBold),
			ZIndex = 3,
			Parent = frame,
		})
		local fill = Theme.new("Frame", {
			Name = "CooldownFill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.45,
			ZIndex = 2,
			Parent = frame,
		})
		local seconds = Theme.label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(32, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = 13,
			TextColor3 = Palette.UISubText,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			ZIndex = 3,
			Parent = frame,
		})
		local dot = Theme.new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = Palette.UIAccent,
			ZIndex = 3,
			Parent = frame,
		})
		Theme.corner(dot, UDim.new(0.5, 0))
		table.insert(st.abilityRows, {
			Frame = frame,
			Fill = fill,
			Seconds = seconds,
			Dot = dot,
			Stroke = stroke,
			Cooldown = e.Cooldown,
			Cooling = false,
			Shown = nil,
		})
	end
end

local function matchPointInfo(snapshot)
	local need = (snapshot.RoundsToWin or 5) - 1
	if need < 1 then
		return nil, nil
	end
	local mine, theirs = false, false
	for _, e in ipairs(snapshot.Players or {}) do
		if (e.Wins or 0) == need then
			if e.UserId == player.UserId then
				mine = true
			else
				theirs = true
			end
		end
	end
	if mine and theirs then
		return "FINAL ROUND", Palette.AccentB
	elseif mine then
		return "MATCH POINT", Palette.UIAccent
	elseif theirs then
		return "MATCH POINT", Palette.UIDanger
	end
	return nil, nil
end

function HUD.OnState(snapshot, old)
	if not ui.scoreboard then
		return
	end
	old = old or {}
	local inMatch = snapshot.InMatch == true
	ui.scoreboard.Visible = inMatch
	ui.health.Visible = inMatch
	ui.abilityList.Visible = true -- also shows Power-Up Lab abilities in the lobby
	refreshAbilities()
	if not inMatch then
		if old.InMatch then
			hideBanner()
			clearFeed()
		end
		table.clear(st.lastWins)
		st.matchTag = nil
		ui.matchTag.Visible = false
		return
	end
	if snapshot.MatchId ~= old.MatchId then
		table.clear(st.lastWins) -- a new match (no score pop for the first snapshot)
	end

	local roundsToWin = snapshot.RoundsToWin or 5
	for slot = 1, 2 do
		local entry = snapshot.Players and snapshot.Players[slot]
		local wins = entry and entry.Wins or 0
		local isMe = entry ~= nil and entry.UserId == player.UserId
		ui.names[slot].Text = entry and entry.Name or "-"
		ui.names[slot].TextColor3 = isMe and Palette.UIAccent or Palette.UIText
		ui.wins[slot].Text = tostring(wins)
		rebuildPips(slot, roundsToWin)
		-- pop + burst when a score goes up
		local scored = entry ~= nil and st.lastWins[slot] ~= nil and wins > st.lastWins[slot]
		setPips(slot, wins, scored)
		if scored then
			local chip = ui.chips[slot]
			Theme.pop(chip, 0.4)
			local panel = ui.scorePanel
			local scale = math.max(hudScale, 0.01)
			local center = (chip.AbsolutePosition - panel.AbsolutePosition + chip.AbsoluteSize / 2) / scale
			Theme.burst(panel, center, ClientState.GetSlotColor(slot), 12, 70, 6)
		end
		st.lastWins[slot] = wins
	end
	ui.roundLabel.Text = ("ROUND %d"):format(snapshot.Round or 1)
	rebuildIcons(snapshot)

	local phase = snapshot.Phase
	local tag, tagColor = matchPointInfo(snapshot)
	st.matchTag = (phase == "Countdown" or phase == "Fight") and tag or nil
	ui.matchTag.Visible = st.matchTag ~= nil
	if tag then
		ui.matchTagLabel.Text = tag
		ui.matchTag.BackgroundColor3 = tagColor
	end

	if phase ~= old.Phase or snapshot.Round ~= old.Round then
		if phase == "Countdown" then
			st.lastCountdown = nil
			local map = snapshot.MapName and ("  ·  " .. string.upper(snapshot.MapName)) or ""
			showBanner("", "ROUND " .. tostring(snapshot.Round or 1) .. map, Palette.UIText, nil, tag, tagColor)
			if tag then
				task.delay(0.15, Sfx.Play, "MatchPoint")
			end
		elseif phase == "Fight" then
			Sfx.Play("Go")
			Sfx.Play("FightStart")
			showBanner("FIGHT", nil, Palette.UIAccent, 0.75)
			bannerPulse(Palette.UIAccent)
			if Controllers and Controllers.Camera and Controllers.Camera.AddFovPunch then
				Controllers.Camera.AddFovPunch(4)
			end
		elseif phase == "RoundEnd" then
			local me, opp
			for _, e in ipairs(snapshot.Players or {}) do
				if e.UserId == player.UserId then
					me = e
				else
					opp = e
				end
			end
			local score = me and opp and ("%d  -  %d"):format(me.Wins or 0, opp.Wins or 0) or ""
			if snapshot.RoundWinnerUserId == nil then
				showBanner("DRAW", snapshot.Message, Palette.UISubText, 2.2)
				Sfx.Play("RoundLost", { Pitch = 1.2, Volume = 0.6 })
			else
				local won = snapshot.RoundWinnerUserId == player.UserId
				local winner = won and me or opp
				local matchOver = winner ~= nil and (winner.Wins or 0) >= roundsToWin
				local title = matchOver and (won and "MATCH WON" or "MATCH LOST") or (won and "ROUND WON" or "ROUND LOST")
				local sub = snapshot.Message and (snapshot.Message .. "     " .. score) or score
				local nextTag, nextColor
				if not matchOver then
					nextTag, nextColor = tag, tagColor
				end
				showBanner(title, sub, won and Palette.UIAccent or Palette.UIDanger, 2.4, nextTag, nextColor)
				bannerPulse(won and Palette.UIAccent or Palette.UIDanger)
				Sfx.Play(won and "RoundWon" or "RoundLost")
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

local function updateCrosshair(inArena, firstPerson, scopeAlpha, bolt, hideAll)
	local show = inArena and firstPerson and scopeAlpha < 0.3 and not ClientState.MenuOpen and not hideAll
	ui.crosshair.Visible = show
	ui.boltBar.Visible = inArena and bolt > 0 and not hideAll
	ui.boltFill.Size = UDim2.fromScale(1 - bolt, 1)
	local cycling = bolt > 0
	if st.boltWasCycling and not cycling and show then
		Theme.pop(ui.crosshair, 0.18) -- ready to fire again
	end
	st.boltWasCycling = cycling
	if not show then
		return
	end
	-- the gap is the real hipfire spread cone on screen, kicked open right after a shot
	local camera = workspace.CurrentCamera
	local spread = math.rad(Config.Weapon.HipSpreadDegrees or 0)
	local halfFov = math.rad(math.clamp(camera.FieldOfView, 1, 120)) / 2
	local gap = math.clamp(math.tan(spread) / math.tan(halfFov) * camera.ViewportSize.Y / 2, 4, 40)
	gap += math.max(bolt - 0.8, 0) / 0.2 * 9
	local knife = ClientState.Weapon == "Knife"
	local alpha = cycling and 0.6 or 0
	for _, l in ipairs(ui.crossLines) do
		l.Frame.Visible = not knife
		l.Frame.Position = UDim2.new(0.5, l.X * (gap + 3.5), 0.5, l.Y * (gap + 3.5))
		l.Frame.BackgroundTransparency = alpha
	end
	ui.crossDot.BackgroundTransparency = cycling and 0.3 or 0
end

local function updateHealth(dt, hideAll)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		ui.lowVignette.Visible = false
		return
	end
	local maxHealth = math.max(humanoid.MaxHealth, 1)
	local fraction = math.clamp(humanoid.Health / maxHealth, 0, 1)
	local now = os.clock()
	if humanoid ~= st.hpHumanoid then
		-- new character: no damage trail / heal flash from the respawn
		st.hpHumanoid = humanoid
		st.hpFraction, st.trail = fraction, fraction
	elseif fraction < st.hpFraction - 0.0005 then
		st.trailHoldUntil = now + 0.45
		st.trail = math.max(st.trail, st.hpFraction)
	elseif fraction - st.hpFraction > 0.01 then
		st.healFlashUntil = now + 0.5 -- healed (Vampire...): the bar flashes green
	end
	st.hpFraction = fraction
	if now > st.trailHoldUntil then
		st.trail = math.max(fraction, st.trail - dt * 1.4)
	end
	if st.trail < fraction then
		st.trail = fraction
	end
	ui.healthFill.Size = UDim2.fromScale(fraction, 1)
	ui.trailFill.Size = UDim2.fromScale(st.trail, 1)
	local low = fraction < 0.35 and humanoid.Health > 0
	local fillColor = low and Palette.UIDanger or Palette.UIText
	local heal = (st.healFlashUntil or 0) - now
	if heal > 0 then
		fillColor = fillColor:Lerp(HEAL, heal / 0.5)
	end
	ui.healthFill.BackgroundColor3 = fillColor
	local shown = math.ceil(humanoid.Health)
	if shown ~= st.hpShown then
		st.hpShown = shown
		ui.healthText.Text = tostring(math.max(shown, 0))
	end
	ui.healthText.TextColor3 = low and Palette.UIDanger or Palette.UIText
	-- shield strip (Overshield / Bloodlust)
	local shield = character:GetAttribute("Shield") or 0
	ui.shieldFill.Visible = shield > 0
	ui.shieldText.Visible = shield > 0
	if shield > 0 then
		ui.shieldFill.Size = UDim2.fromScale(math.clamp(shield / maxHealth, 0, 1), 1)
		ui.shieldText.Text = "+" .. tostring(math.ceil(shield)) .. " SHIELD"
	end
	-- low health: the panel outline and the screen edges pulse, a soft heartbeat
	local pulse = low and ClientState.IsFighting() and not hideAll and fxOn("LowHealthPulse")
	ui.lowVignette.Visible = pulse
	if pulse then
		local beat = (math.sin(now * (fraction < 0.2 and 9 or 6)) + 1) / 2
		for _, edge in ipairs(ui.lowEdges) do
			edge.BackgroundTransparency = 0.82 - beat * 0.12
		end
		ui.healthStroke.Color = Palette.UIDanger
		ui.healthStroke.Transparency = 0.2 + beat * 0.5
		if now >= st.nextHeartbeat then
			st.nextHeartbeat = now + (fraction < 0.2 and 0.75 or 1.05)
			Sfx.Play("Heartbeat")
		end
	else
		ui.healthStroke.Color = Palette.UIText
		ui.healthStroke.Transparency = 0.88
	end
end

local function updateTimers(snapshot)
	local timeLeft = ClientState.TimeLeft()
	if snapshot.Phase == "Fight" and timeLeft then
		ui.timerLabel.TextSize = 22
		ui.timerLabel.Text = formatTime(timeLeft)
		local urgent = timeLeft < 15
		ui.timerLabel.TextColor3 = urgent and Palette.UIDanger or Palette.UIText
		local second = math.floor(timeLeft)
		if second ~= st.lastTimerSecond then
			if st.lastTimerSecond and second < 10 then
				Theme.pop(ui.timerLabel, 0.25)
				Sfx.Play("TimerTick")
			end
			st.lastTimerSecond = second
		end
	else
		st.lastTimerSecond = nil
		ui.timerLabel.TextSize = 12
		ui.timerLabel.TextColor3 = Palette.UISubText
		ui.timerLabel.Text = ("FIRST TO %d"):format(snapshot.RoundsToWin or 5)
	end
	if snapshot.Phase == "Countdown" and timeLeft then
		local n = math.ceil(timeLeft)
		if n ~= st.lastCountdown and n > 0 then
			st.lastCountdown = n
			ui.bannerTitle.Text = tostring(n)
			ui.bannerTitle.TextColor3 = n == 1 and Palette.AccentB or Palette.UIText
			ui.bannerTitle.TextTransparency = 0
			ui.bannerTitle.TextSize = 112
			Theme.tween(ui.bannerTitle, 0.3, { TextSize = 72 }, Enum.EasingStyle.Back)
			bannerPulse(n == 1 and Palette.AccentB or WHITE)
			Sfx.Play("CountdownTick", { Pitch = n == 1 and 1.25 or 1 })
		end
	end
	-- match point tag breathes
	if st.matchTag then
		local k = (math.sin(os.clock() * 4) + 1) / 2
		ui.matchTag.BackgroundTransparency = k * 0.35
	end
end

local function updateAbilities()
	if #st.abilityRows == 0 then
		return
	end
	local cooldowns = Controllers.Movement.GetCooldowns()
	for _, row in ipairs(st.abilityRows) do
		-- (a jam from Disruptor Rounds can be longer than the cooldown: the bar just stays full)
		local left = cooldowns[row.Cooldown] or 0
		local total = cooldownTotal(row.Cooldown)
		row.Fill.Size = UDim2.fromScale(math.clamp(left / math.max(total, 0.01), 0, 1), 1)
		local cooling = left > 0.05
		local shown = cooling and (left >= 10 and tostring(math.ceil(left)) or ("%.1f"):format(left)) or ""
		if shown ~= row.Shown then
			row.Shown = shown
			row.Seconds.Text = shown
		end
		row.Dot.Visible = not cooling
		if row.Cooling and not cooling then
			-- ready again
			Theme.pop(row.Frame, 0.08)
			row.Stroke.Color = Palette.UIAccent
			row.Stroke.Transparency = 0
			Theme.tween(row.Stroke, 0.6, { Transparency = 0.88 })
			task.delay(0.6, function()
				if row.Stroke.Parent then
					row.Stroke.Color = Palette.UIText
				end
			end)
			if ClientState.HasGun() then
				Sfx.Play("AbilityReady")
			end
		end
		row.Cooling = cooling
	end
end

local function update(dt)
	local weapon = Controllers.Weapon
	local inArena = ClientState.HasGun() -- lobby practice range or a live round
	local scopeAlpha = weapon.GetScopeAlpha()
	local firstPerson = Controllers.Camera.IsFirstPerson()
	local hideAll = killCamPlaying()

	ui.scope.Visible = inArena and scopeAlpha > 0.85 and not hideAll
	updateCrosshair(inArena, firstPerson, scopeAlpha, weapon.GetBoltProgress(), hideAll)

	-- speedometer: white at normal speed, teal when bunny hopping fast
	local speed = Controllers.Movement.GetSpeed()
	ui.speedLabel.Visible = inArena and scopeAlpha < 0.85 and not ClientState.MenuOpen and not hideAll
	local speedInt = math.floor(speed + 0.5)
	if speedInt ~= st.speedShown then
		st.speedShown = speedInt
		ui.speedLabel.Text = tostring(speedInt) .. " u/s"
	end
	ui.speedLabel.TextColor3 = speed > Config.Movement.SprintSpeed + 6 and Palette.UIAccent or Palette.UIText
	updateSpeedLines((inArena and not hideAll) and speed or 0, scopeAlpha > 0.3)

	updateHealth(dt, hideAll)

	-- damage direction keeps pointing at where the shot came from as you turn
	if ui.indicator.Visible then
		local from = st.indicatorFrom
		local camera = workspace.CurrentCamera
		if from and camera and ui.indicatorBars[1].BackgroundTransparency < 0.99 and not hideAll then
			local localDir = camera.CFrame:VectorToObjectSpace(from - camera.CFrame.Position)
			ui.indicator.Rotation = math.deg(math.atan2(localDir.X, -localDir.Z))
		else
			ui.indicator.Visible = false
		end
	end

	-- DEADEYE charge (only while scoped)
	local charge = weapon.GetDeadeyeCharge and weapon.GetDeadeyeCharge() or 0
	ui.deadeyeBar.Visible = ui.scope.Visible and (ClientState.Stats.DeadeyeBonus or 0) > 0
	if ui.deadeyeBar.Visible then
		ui.deadeyeFill.Size = UDim2.fromScale(charge, 1)
		ui.deadeyeFill.BackgroundColor3 = charge >= 1 and GOLD or Palette.UIText
	end

	local snapshot = ClientState.Snapshot
	if snapshot.InMatch then
		updateTimers(snapshot)
	end
	updateAbilities()
end

function HUD.Init(controllers)
	Controllers = controllers
end

function HUD.Start(playerGui)
	gui = Theme.screen("HUD", 1, playerGui)
	safeGui = Theme.screen("HUDPanels", 2, playerGui)
	pcall(function()
		safeGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	root = Theme.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = safeGui,
	})
	rootScale = Theme.scaleOf(root)

	buildScope()
	buildSpeedLines()
	buildDamage()
	buildCrosshair()
	buildScoreboard()
	buildHealth()
	buildAbilities()
	buildBanner()
	buildKillCard()
	buildKillFeed()
	buildSpeedometer()

	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	UserInputService.LastInputTypeChanged:Connect(function()
		refreshAbilities() -- keycaps follow keyboard / controller
	end)
	ClientState.SettingsChanged:Connect(function()
		refreshAbilities() -- rebinds
	end)

	Remotes.Get("HitConfirm").OnClientEvent:Connect(onHitConfirm)
	Remotes.Get("Damaged").OnClientEvent:Connect(onDamaged)
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(update, dt)
		if not ok then
			-- never let one bad frame spam: report once per second at most
			local now = os.clock()
			if now - (st.lastError or 0) > 1 then
				st.lastError = now
				warn("[HUD]", err)
			end
		end
	end)
end

return HUD
