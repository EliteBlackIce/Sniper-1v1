--[[
	Keybinds.lua  (Client.Keybinds)

	Every rebindable action with its default KEYBOARD and CONTROLLER
	binding. Players change them in Settings (P) > Keyboard / Controller,
	and they're saved with the other settings.

	A binding is the name of an Enum.KeyCode ("Space", "ButtonA") or of a
	mouse Enum.UserInputType ("MouseButton1").

	Moving (WASD / left stick) and looking (mouse / right stick) are not
	rebindable.

	Usage:  if Keybinds.Matches("Jump", input) then ... end

	Gamepad note: a few power-up actives share a button with a LOBBY-only
	action (Barrier = LB like Playground, Recall / Smoke = D-pad right / left
	like Find match / Power-Up Lab). In a match those lobby actions do
	nothing, so there's no clash where it matters.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.ClientState)
local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local Keybinds = {}

-- On-screen buttons (mobile) press actions through these. Every place that
-- listens to UserInputService.InputBegan/Ended for an action also listens
-- here, so a button press runs exactly the same code as the key.
Keybinds.VirtualBegan = Signal.new() -- (fakeInput, processed)
Keybinds.VirtualEnded = Signal.new()

function Keybinds.Press(actionId, down)
	local fake = {
		Action = actionId,
		UserInputType = Enum.UserInputType.Touch,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.zero,
		Delta = Vector3.zero,
	}
	if down then
		Keybinds.VirtualBegan:Fire(fake, false)
	else
		Keybinds.VirtualEnded:Fire(fake, false)
	end
end

Keybinds.Actions = {
	{ Id = "Fire", Name = "Fire", Keyboard = "MouseButton1", Gamepad = "ButtonR2" },
	{ Id = "Scope", Name = "Scope", Keyboard = "MouseButton2", Gamepad = "ButtonL2" },
	{ Id = "Jump", Name = "Jump / Bunny hop", Keyboard = "Space", Gamepad = "ButtonA" },
	{ Id = "Slide", Name = "Slide", Keyboard = "C", Gamepad = "ButtonB" },
	{ Id = "Sprint", Name = "Sprint", Keyboard = "LeftShift", Gamepad = "ButtonL3" },
	{ Id = "Grapple", Name = "Grapple (power-up)", Keyboard = "E", Gamepad = "ButtonY" },
	{ Id = "Blink", Name = "Blink (power-up)", Keyboard = "R", Gamepad = "ButtonX" },
	{ Id = "Decoy", Name = "Decoy (power-up)", Keyboard = "Q", Gamepad = "DPadUp" },
	{ Id = "Barrier", Name = "Barrier Dome (power-up)", Keyboard = "Z", Gamepad = "ButtonL1" },
	{ Id = "Recall", Name = "Recall (power-up)", Keyboard = "X", Gamepad = "DPadRight" },
	{ Id = "Smoke", Name = "Smoke Grenade (power-up)", Keyboard = "Three", Gamepad = "DPadLeft" },
	-- (Air Dash has no key of its own: it's Sprint while in the air. On a
	-- touch screen the DASH button presses the virtual "AirDash" action.)
	{ Id = "Inspect", Name = "Inspect weapon", Keyboard = "V", Gamepad = "DPadDown" },
	{ Id = "Primary", Name = "Sniper", Keyboard = "One", Gamepad = "ButtonR1" },
	{ Id = "Knife", Name = "Knife", Keyboard = "Two", Gamepad = "ButtonR1" },
	{ Id = "PowerUpLab", Name = "Power-Up Lab", Keyboard = "B", Gamepad = "DPadLeft" },
	{ Id = "Locker", Name = "Locker (skins)", Keyboard = "L", Gamepad = "None" },
	{ Id = "Shop", Name = "Shop (crates, credits, VIP)", Keyboard = "M", Gamepad = "None" },
	{ Id = "FindMatch", Name = "Find match", Keyboard = "F", Gamepad = "DPadRight" },
	{ Id = "Playground", Name = "Playground", Keyboard = "G", Gamepad = "ButtonL1" },
	{ Id = "BotMatch", Name = "Play vs bot (admin)", Keyboard = "N", Gamepad = "None" }, -- (RB is the knife)
	{ Id = "DuelFriend", Name = "Duel a player", Keyboard = "U", Gamepad = "ButtonR3" },
	{ Id = "Rematch", Name = "Rematch", Keyboard = "T", Gamepad = "DPadUp" },
	{ Id = "Settings", Name = "Settings", Keyboard = "P", Gamepad = "ButtonSelect" },
}

Keybinds.ById = {}
for _, action in ipairs(Keybinds.Actions) do
	Keybinds.ById[action.Id] = action
end

-- The current binding name for an action on a device ("Keyboard" or "Gamepad").
function Keybinds.Get(actionId, device)
	local binds = ClientState.Settings.Binds
	local custom = binds and binds[device] and binds[device][actionId]
	local action = Keybinds.ById[actionId]
	return custom or (action and action[device])
end

local function inputName(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
		return t.Name
	end
	return input.KeyCode.Name
end
Keybinds.InputName = inputName

local function isGamepad(input)
	return input.UserInputType.Name:find("Gamepad") ~= nil
end
Keybinds.IsGamepad = isGamepad

-- True if `input` is the key / button bound to `actionId`.
function Keybinds.Matches(actionId, input)
	if typeof(input) == "table" then
		return input.Action == actionId -- a virtual (on-screen button) press
	end
	local device = isGamepad(input) and "Gamepad" or "Keyboard"
	local bound = Keybinds.Get(actionId, device)
	return bound ~= nil and bound == inputName(input)
end

-- Short label for a binding ("MouseButton1" -> "LMB", "ButtonA" -> "A").
function Keybinds.Label(name)
	local labels = {
		MouseButton1 = "LMB",
		MouseButton2 = "RMB",
		MouseButton3 = "MMB",
		LeftShift = "L-SHIFT",
		RightShift = "R-SHIFT",
		LeftControl = "L-CTRL",
		RightControl = "R-CTRL",
		ButtonR2 = "RT / R2",
		ButtonL2 = "LT / L2",
		ButtonR1 = "RB / R1",
		ButtonL1 = "LB / L1",
		ButtonR3 = "R-STICK",
		ButtonL3 = "L-STICK",
		ButtonA = "A / X",
		ButtonB = "B / O",
		ButtonX = "X / []",
		ButtonY = "Y / ^",
		ButtonSelect = "SELECT",
		DPadUp = "D-UP",
		DPadDown = "D-DOWN",
		DPadLeft = "D-LEFT",
		DPadRight = "D-RIGHT",
		None = "-",
	}
	return labels[name] or string.upper(name or "-")
end

return Keybinds
