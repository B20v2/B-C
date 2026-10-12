--[[
	Units catalog: ground vehicles built in military factories. Units roll out
	at home, deploy to the mainland through the tunnel and capture points.
]]

export type UnitDef = {
	id: string,
	name: string,
	role: string,
	faction: string,
	cost: number,
	fuel: number,
	steel: number,
	time: number,
	hp: number,
	speed: number,
	dps: number,
	range: number,
	capture: number, -- capture points per second
	antiAir: number?, -- chance to shoot down projectiles nearby
	model: string,
	params: { [string]: any }?,
	research: string,
	pass: string?,
	order: number,
	desc: string,
}

local Units = {}

local list: { UnitDef } = {}
local byId: { [string]: UnitDef } = {}

local FactionPass = { Eastern = "EasternPack", European = "EuropeanPack" }

local function U(def: { [string]: any })
	def.order = #list + 1
	def.faction = def.faction or "Standard"
	if def.faction ~= "Standard" then
		def.pass = FactionPass[def.faction]
	end
	local typed = def :: UnitDef
	table.insert(list, typed)
	byId[typed.id] = typed
end

U({ id = "truck", name = "Supply Truck", role = "Capture", cost = 1500, fuel = 20, steel = 10, time = 10,
	hp = 60, speed = 34, dps = 0, range = 0, capture = 1, model = "truck", research = "mechanized",
	desc = "Cheap and fast. Good for holding points." })
U({ id = "marder", name = "Marder", role = "IFV", cost = 6000, fuel = 60, steel = 40, time = 25,
	hp = 180, speed = 26, dps = 10, range = 60, capture = 3, model = "ifv", research = "mechanized",
	desc = "Infantry fighting vehicle. Best at capturing." })
U({ id = "leopard", name = "Leopard", role = "Tank", cost = 14000, fuel = 100, steel = 90, time = 40,
	hp = 420, speed = 20, dps = 24, range = 80, capture = 2, model = "tank", research = "armor",
	desc = "Main battle tank. Tough and hard hitting." })
U({ id = "himars", name = "HIMARS", role = "Artillery", cost = 18000, fuel = 80, steel = 60, time = 45,
	hp = 140, speed = 28, dps = 40, range = 220, capture = 1, model = "mlrs", research = "rocket_artillery",
	desc = "Long-range rockets. Shreds garrisons from afar." })
U({ id = "gepard", name = "Gepard", role = "Anti-Air", cost = 12000, fuel = 60, steel = 50, time = 30,
	hp = 200, speed = 24, dps = 8, range = 60, capture = 1, antiAir = 0.3, model = "spaag",
	research = "air_defense_2", desc = "Mobile anti-air. Protects your army from drones and missiles." })
U({ id = "bmp", name = "BMP-3", role = "IFV", faction = "Eastern", cost = 6500, fuel = 60, steel = 40,
	time = 22, hp = 190, speed = 28, dps = 13, range = 65, capture = 3, model = "ifv", params = { eastern = true },
	research = "mechanized", desc = "Eastern IFV with a heavier gun." })
U({ id = "t90", name = "T-90", role = "Tank", faction = "Eastern", cost = 15000, fuel = 100, steel = 95,
	time = 38, hp = 460, speed = 20, dps = 26, range = 80, capture = 2, model = "tank", params = { eastern = true },
	research = "armor", desc = "Eastern main battle tank." })
U({ id = "tor_m", name = "Tor-M", role = "Anti-Air", faction = "Eastern", cost = 13000, fuel = 60, steel = 50,
	time = 28, hp = 220, speed = 22, dps = 6, range = 60, capture = 1, antiAir = 0.4, model = "spaag",
	params = { eastern = true }, research = "air_defense_2", desc = "Eastern mobile SAM." })
U({ id = "vbci", name = "VBCI", role = "IFV", faction = "European", cost = 6500, fuel = 55, steel = 40,
	time = 22, hp = 200, speed = 32, dps = 11, range = 65, capture = 3, model = "ifv", params = { wheeled = true },
	research = "mechanized", desc = "Fast wheeled European IFV." })
U({ id = "leclerc", name = "Leclerc", role = "Tank", faction = "European", cost = 15500, fuel = 100, steel = 90,
	time = 38, hp = 420, speed = 24, dps = 26, range = 85, capture = 2, model = "tank", params = { european = true },
	research = "armor", desc = "Fast European main battle tank." })
U({ id = "caesar", name = "CAESAR", role = "Artillery", faction = "European", cost = 17000, fuel = 70, steel = 55,
	time = 40, hp = 150, speed = 32, dps = 44, range = 240, capture = 1, model = "mlrs", params = { gun = true },
	research = "rocket_artillery", desc = "Truck-mounted howitzer with extreme range." })

function Units.get(id: string): UnitDef?
	return byId[id]
end

function Units.all(): { UnitDef }
	return list
end

return Units
