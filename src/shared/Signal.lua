--[[
	Signal.lua  (ReplicatedStorage.Shared.Signal)
	Tiny event class:  local s = Signal.new(); s:Connect(fn); s:Fire(...)
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self._handlers
	table.insert(handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in ipairs(table.clone(self._handlers)) do
		task.spawn(fn, ...)
	end
end

return Signal
