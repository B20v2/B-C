--[[
	Rank
	Nation power score and the rank ladder (Outpost -> Superpower).
	Shared so the server awards ranks and the client can show what's next.
]]

local Config = require(script.Parent.Parent.Config)

local Rank = {}

export type Input = { pop: number, buildingValue: number, researched: number, units: number, points: number }
export type Info = { level: number, name: string, power: number, progress: number, next: string?, nextPower: number? }

function Rank.power(i: Input): number
	return math.floor(i.pop + i.buildingValue / 100 + i.researched * 150 + i.units * 80 + i.points * 600)
end

function Rank.of(power: number): Info
	local ranks = Config.Ranks
	local level = 1
	for i, r in ranks do
		if power >= r.power then
			level = i
		end
	end
	local cur, nxt = ranks[level], ranks[level + 1]
	local progress = 1
	if nxt then
		progress = math.clamp((power - cur.power) / (nxt.power - cur.power), 0, 1)
	end
	return {
		level = level,
		name = cur.name,
		power = power,
		progress = progress,
		next = nxt and nxt.name,
		nextPower = nxt and nxt.power,
	}
end

return Rank
