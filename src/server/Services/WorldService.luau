--[[
	WorldService
	Day / night cycle. Days are long, nights short (Config.NightShare), and the
	clock replicates through Lighting so every client sees the same sky. At
	night, buildings switch on their window and beacon lights (client side,
	see NightLights).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldService = {}

-- Maps a 0..1 phase of the cycle onto a 24h clock: day spans 06:00-18:00
-- over (1 - NightShare) of the cycle, night spans 18:00-06:00 over the rest.
function WorldService.clockAt(phase: number): number
	local dayShare = 1 - Config.NightShare
	phase = phase % 1
	if phase < dayShare then
		return 6 + 12 * (phase / dayShare)
	end
	return (18 + 12 * ((phase - dayShare) / Config.NightShare)) % 24
end

function WorldService.isNight(clock: number): boolean
	return clock >= 18.4 or clock < 5.6
end

function WorldService.init(_S) end

function WorldService.start()
	task.spawn(function()
		-- start mid-morning so a fresh server opens in daylight
		local offset = 0.2 * Config.DayLength
		while true do
			local phase = ((workspace:GetServerTimeNow() + offset) / Config.DayLength) % 1
			Lighting.ClockTime = WorldService.clockAt(phase)
			task.wait(0.5)
		end
	end)
end

return WorldService
