--[[
	Strategic points on the central battlefield. Offsets are relative to
	Config.MainlandOrigin. The capital sits in the middle; the rest sit
	between the bridge lanes so every nation has something on its way in.
	Bonuses are paid to the owner every pay day / tick.
]]

export type PointDef = {
	id: string,
	name: string,
	offset: Vector3,
	garrison: number,
	model: string,
	bonus: { income: number?, oil: number?, power: number?, steel: number?, rp: number? },
	bonusText: string,
}

local WarMap: { PointDef } = {
	{ id = "capital", name = "CAPITAL", offset = Vector3.new(0, 0, 0), garrison = 2500, model = "city",
		bonus = { income = 20000 }, bonusText = "+$20k per pay" },
	{ id = "airport", name = "AIRPORT", offset = Vector3.new(-573, 0, -237), garrison = 900, model = "airport",
		bonus = { income = 6000, rp = 20 }, bonusText = "+$6k per pay, +20 RP/min" },
	{ id = "oil_field", name = "OIL FIELD", offset = Vector3.new(554, 0, 230), garrison = 700, model = "oilField",
		bonus = { oil = 600 }, bonusText = "+600 oil/min" },
	{ id = "nuclear_plant", name = "NUCLEAR POWER PLANT", offset = Vector3.new(237, 0, -573), garrison = 1100,
		model = "nuclear", bonus = { power = 400 }, bonusText = "+400 MW power" },
	{ id = "city", name = "CITY", offset = Vector3.new(480, 0, -199), garrison = 1000, model = "city",
		bonus = { income = 9000 }, bonusText = "+$9k per pay" },
	{ id = "port", name = "PORT", offset = Vector3.new(237, 0, 573), garrison = 800, model = "port",
		bonus = { steel = 300 }, bonusText = "+300 steel/min" },
	{ id = "military_base", name = "MILITARY BASE", offset = Vector3.new(-554, 0, 230), garrison = 1300,
		model = "base", bonus = { rp = 60 }, bonusText = "+60 RP/min" },
}

return WarMap
