--[[
	Spring.lua  (Client.Spring)
	A damped spring for Vector3 values, used for viewmodel sway and recoil.

		local s = Spring.new(stiffness, damping)
		s.Target = Vector3.new(...)
		s:Impulse(Vector3.new(...))  -- kick the velocity
		s:Update(dt)                 -- returns s.Position
]]

local Spring = {}
Spring.__index = Spring

function Spring.new(stiffness, damping)
	return setmetatable({
		Stiffness = stiffness,
		Damping = damping,
		Position = Vector3.zero,
		Velocity = Vector3.zero,
		Target = Vector3.zero,
	}, Spring)
end

function Spring:Impulse(v)
	self.Velocity += v
end

function Spring:Update(dt)
	-- small fixed sub-steps keep it stable at low frame rates
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		local force = (self.Target - self.Position) * self.Stiffness - self.Velocity * self.Damping
		self.Velocity += force * h
		self.Position += self.Velocity * h
	end
	return self.Position
end

return Spring
