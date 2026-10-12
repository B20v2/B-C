--[[
	Units catalog: everything you command on the map.

	  class      "vehicle" (military factories), "infantry" (barracks: squads
	             of classic Roblox soldiers) or "air" (helipad: helicopters)
	  vs         damage multipliers against each class (missing = 1, air = 0
	             unless listed - only anti-air and door guns hit helicopters)
	  cargo      transports: squads carried, supply points, slung vehicles
	  light      vehicles a Chinook can sling-load
	  fob        can set up a Forward Operating Base on the battlefield
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
	class: string, -- "vehicle" | "infantry" | "air"
	vs: { [string]: number },
	cargo: { squads: number?, supplies: number?, vehicles: number? }?,
	light: boolean?,
	fob: boolean?,
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

local DEFAULT_VS = { infantry = 1, vehicle = 1, air = 0 }

local function U(def: { [string]: any })
	def.order = #list + 1
	def.faction = def.faction or "Standard"
	def.class = def.class or "vehicle"
	local vs = table.clone(DEFAULT_VS)
	for k, v in def.vs or {} do
		vs[k] = v
	end
	def.vs = vs
	if def.faction ~= "Standard" then
		def.pass = FactionPass[def.faction]
	end
	local typed = def :: UnitDef
	table.insert(list, typed)
	byId[typed.id] = typed
end

-- Vehicles (military factories) ------------------------------------------
U({ id = "truck", name = "Logistics Truck", role = "Transport", cost = 1500, fuel = 20, steel = 10, time = 10,
	hp = 70, speed = 34, dps = 0, range = 0, capture = 1, model = "truck", research = "mechanized",
	cargo = { squads = 2, supplies = 150 }, light = true, fob = true,
	desc = "Carries 2 squads or 150 supplies. Can set up a FOB." })
U({ id = "humvee", name = "Humvee", role = "Transport", cost = 3500, fuel = 20, steel = 15, time = 14,
	hp = 120, speed = 40, dps = 6, range = 55, capture = 2, model = "humvee", research = "military_doctrine",
	cargo = { squads = 1 }, light = true, vs = { infantry = 1.4, vehicle = 0.3, air = 0.3 },
	desc = "Fast armoured car with a roof gun. Carries 1 squad." })
U({ id = "marder", name = "Marder", role = "IFV", cost = 6000, fuel = 60, steel = 40, time = 25,
	hp = 180, speed = 26, dps = 10, range = 60, capture = 3, model = "ifv", research = "mechanized",
	cargo = { squads = 1 }, light = true, vs = { infantry = 1.3, vehicle = 0.8, air = 0.2 },
	desc = "Infantry fighting vehicle. Carries a squad and captures fast." })
U({ id = "leopard", name = "Leopard", role = "Tank", cost = 14000, fuel = 100, steel = 90, time = 40,
	hp = 420, speed = 20, dps = 24, range = 80, capture = 2, model = "tank", research = "armor",
	vs = { vehicle = 1.2 }, desc = "Main battle tank. Tough and hard hitting." })
U({ id = "himars", name = "HIMARS", role = "Artillery", cost = 18000, fuel = 80, steel = 60, time = 45,
	hp = 140, speed = 28, dps = 40, range = 220, capture = 1, model = "mlrs", research = "rocket_artillery",
	desc = "Long-range rockets. Shreds garrisons from afar." })
U({ id = "gepard", name = "Gepard", role = "Anti-Air", cost = 12000, fuel = 60, steel = 50, time = 30,
	hp = 200, speed = 24, dps = 8, range = 60, capture = 1, antiAir = 0.3, model = "spaag",
	vs = { air = 3, vehicle = 0.4, infantry = 0.8 }, light = true,
	research = "air_defense_2", desc = "Mobile anti-air. Shreds helicopters, drones and missiles." })
U({ id = "bmp", name = "BMP-3", role = "IFV", faction = "Eastern", cost = 6500, fuel = 60, steel = 40,
	time = 22, hp = 190, speed = 28, dps = 13, range = 65, capture = 3, model = "ifv", params = { eastern = true },
	cargo = { squads = 1 }, light = true, vs = { infantry = 1.3, vehicle = 0.9, air = 0.2 },
	research = "mechanized", desc = "Eastern IFV with a heavier gun. Carries a squad." })
U({ id = "t90", name = "T-90", role = "Tank", faction = "Eastern", cost = 15000, fuel = 100, steel = 95,
	time = 38, hp = 460, speed = 20, dps = 26, range = 80, capture = 2, model = "tank", params = { eastern = true },
	vs = { vehicle = 1.2 }, research = "armor", desc = "Eastern main battle tank." })
U({ id = "tor_m", name = "Tor-M", role = "Anti-Air", faction = "Eastern", cost = 13000, fuel = 60, steel = 50,
	time = 28, hp = 220, speed = 22, dps = 6, range = 60, capture = 1, antiAir = 0.4, model = "spaag",
	params = { eastern = true }, vs = { air = 3.5, vehicle = 0.3, infantry = 0.6 }, light = true,
	research = "air_defense_2", desc = "Eastern mobile SAM." })
U({ id = "vbci", name = "VBCI", role = "IFV", faction = "European", cost = 6500, fuel = 55, steel = 40,
	time = 22, hp = 200, speed = 32, dps = 11, range = 65, capture = 3, model = "ifv", params = { wheeled = true },
	cargo = { squads = 1 }, light = true, vs = { infantry = 1.3, vehicle = 0.8, air = 0.2 },
	research = "mechanized", desc = "Fast wheeled European IFV. Carries a squad." })
U({ id = "leclerc", name = "Leclerc", role = "Tank", faction = "European", cost = 15500, fuel = 100, steel = 90,
	time = 38, hp = 420, speed = 24, dps = 26, range = 85, capture = 2, model = "tank", params = { european = true },
	vs = { vehicle = 1.2 }, research = "armor", desc = "Fast European main battle tank." })
U({ id = "caesar", name = "CAESAR", role = "Artillery", faction = "European", cost = 17000, fuel = 70, steel = 55,
	time = 40, hp = 150, speed = 32, dps = 44, range = 240, capture = 1, model = "mlrs", params = { gun = true },
	research = "rocket_artillery", desc = "Truck-mounted howitzer with extreme range." })

-- Infantry (barracks): squads of classic Roblox soldiers ---------------------
U({ id = "rifle_squad", name = "Rifle Squad", role = "Infantry", class = "infantry", cost = 1200, fuel = 0,
	steel = 5, time = 12, hp = 110, speed = 13, dps = 7, range = 55, capture = 4, model = "squad",
	params = { kit = "rifle", count = 4 }, research = "military_doctrine",
	vs = { infantry = 1.2, vehicle = 0.25, air = 0.15 },
	desc = "Four riflemen in plate carriers. The best at capturing points." })
U({ id = "at_team", name = "Anti-Tank Team", role = "Anti-Tank", class = "infantry", cost = 2400, fuel = 0,
	steel = 12, time = 16, hp = 90, speed = 12, dps = 15, range = 75, capture = 2, model = "squad",
	params = { kit = "at", count = 3 }, research = "mechanized",
	vs = { infantry = 0.4, vehicle = 2.2, air = 0.6 },
	desc = "Three soldiers with rocket launchers. Wrecks armour." })
U({ id = "recon_team", name = "Recon Team", role = "Recon", class = "infantry", cost = 1800, fuel = 0,
	steel = 6, time = 14, hp = 80, speed = 16, dps = 9, range = 90, capture = 3, model = "squad",
	params = { kit = "recon", count = 2 }, research = "military_doctrine",
	vs = { infantry = 1.5, vehicle = 0.2, air = 0.1 },
	desc = "Two marksmen in ghillie wraps. Fast and long-ranged." })
U({ id = "vdv_squad", name = "VDV Squad", role = "Infantry", class = "infantry", faction = "Eastern", cost = 1500,
	fuel = 0, steel = 6, time = 12, hp = 130, speed = 13, dps = 8, range = 55, capture = 4, model = "squad",
	params = { kit = "rifle", count = 4, eastern = true }, research = "military_doctrine",
	vs = { infantry = 1.25, vehicle = 0.3, air = 0.15 },
	desc = "Eastern paratroopers in digital camo and heavy helmets." })
U({ id = "legion_squad", name = "Legion Squad", role = "Infantry", class = "infantry", faction = "European",
	cost = 1500, fuel = 0, steel = 6, time = 12, hp = 115, speed = 15, dps = 8, range = 60, capture = 4,
	model = "squad", params = { kit = "rifle", count = 4, european = true }, research = "military_doctrine",
	vs = { infantry = 1.25, vehicle = 0.3, air = 0.15 },
	desc = "European legionnaires in desert kit. Quick on their feet." })

-- Helicopters (helipad) -----------------------------------------------------
U({ id = "blackhawk", name = "Black Hawk", role = "Air Assault", class = "air", cost = 16000, fuel = 80,
	steel = 40, time = 35, hp = 220, speed = 80, dps = 8, range = 70, capture = 0, model = "blackhawk",
	cargo = { squads = 2, supplies = 60 }, research = "aviation", vs = { infantry = 1.3, vehicle = 0.3, air = 0 },
	desc = "Fast utility helicopter with door guns. Flies 2 squads anywhere." })
U({ id = "chinook", name = "Chinook", role = "Heavy Lift", class = "air", cost = 28000, fuel = 140, steel = 70,
	time = 50, hp = 320, speed = 64, dps = 0, range = 0, capture = 0, model = "chinook",
	cargo = { squads = 3, supplies = 300, vehicles = 1 }, fob = true, research = "aviation",
	desc = "Twin-rotor heavy lifter: 3 squads, 300 supplies and a light vehicle under the belly." })

function Units.get(id: string): UnitDef?
	return byId[id]
end

function Units.all(): { UnitDef }
	return list
end

-- Which production building makes a unit: "vehicle" | "infantry" | "air".
function Units.makes(def: UnitDef): string
	return def.class
end

return Units
