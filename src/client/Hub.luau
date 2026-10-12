--[[
	Hub
	A tiny registry so controllers can open each other's windows without
	requiring each other (avoids circular requires). Controllers assign
	functions here during init, e.g. Hub.openShop = function() ... end.
]]

local Hub: { [string]: any } = {}

function Hub.call(name: string, ...: any)
	local fn = Hub[name]
	if type(fn) == "function" then
		fn(...)
	else
		warn("[Hub] nothing registered for " .. name)
	end
end

return Hub
