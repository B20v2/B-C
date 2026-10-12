--[[
	Research tree. Research labs generate research points (RP). A node costs
	RP + cash, takes time and unlocks buildings, weapons and units that list it
	in their `research` field. Some military nodes also need confirmed hits,
	so players climb the missile ladder by actually using their arsenal.
]]

export type ResearchDef = {
	id: string,
	name: string,
	branch: string, -- "Civil" | "Military"
	col: number,
	row: number,
	rp: number,
	cash: number,
	time: number,
	requires: { string },
	hits: number?,
	desc: string,
}

local Research = {}

local list: { ResearchDef } = {}
local byId: { [string]: ResearchDef } = {}

local function R(def: { [string]: any })
	def.requires = def.requires or {}
	local typed = def :: ResearchDef
	table.insert(list, typed)
	byId[typed.id] = typed
end

-- Civil branch
R({ id = "urban_planning", name = "Urban Planning", branch = "Civil", col = 1, row = 1, rp = 40, cash = 15000,
	time = 30, desc = "Apartment blocks and offices." })
R({ id = "coal_power", name = "Coal Power", branch = "Civil", col = 1, row = 2, rp = 60, cash = 20000,
	time = 40, desc = "Coal power plants." })
R({ id = "water_treatment", name = "Water Treatment", branch = "Civil", col = 1, row = 3, rp = 60, cash = 18000,
	time = 40, desc = "Pumping stations." })
R({ id = "heavy_industry", name = "Heavy Industry", branch = "Civil", col = 1, row = 4, rp = 120, cash = 40000,
	time = 60, desc = "Steel mills, medium refineries, tank farms." })
R({ id = "solar", name = "Solar Power", branch = "Civil", col = 2, row = 2, rp = 80, cash = 25000, time = 45,
	requires = { "coal_power" }, desc = "Solar farms." })
R({ id = "public_services", name = "Public Services", branch = "Civil", col = 2, row = 1, rp = 150, cash = 50000,
	time = 60, requires = { "urban_planning" }, desc = "Schools, hospitals and universities." })
R({ id = "petrochemistry", name = "Petrochemistry", branch = "Civil", col = 2, row = 4, rp = 400, cash = 150000,
	time = 120, requires = { "heavy_industry" }, desc = "Large refineries." })
R({ id = "high_density", name = "High Density Living", branch = "Civil", col = 3, row = 1, rp = 300,
	cash = 120000, time = 90, requires = { "public_services" }, desc = "Highrise towers." })
R({ id = "nuclear", name = "Nuclear Fission", branch = "Civil", col = 3, row = 3, rp = 800, cash = 400000,
	time = 180, requires = { "solar", "heavy_industry" }, desc = "Nuclear power plants." })

-- Military branch
R({ id = "military_doctrine", name = "Military Doctrine", branch = "Military", col = 1, row = 2, rp = 100,
	cash = 30000, time = 45, desc = "Small military factory, research center." })
R({ id = "ballistics", name = "Ballistics", branch = "Military", col = 2, row = 1, rp = 150, cash = 40000,
	time = 60, requires = { "military_doctrine" }, desc = "SRBM launcher and missiles." })
R({ id = "air_defense_1", name = "Air Defense I", branch = "Military", col = 2, row = 2, rp = 120, cash = 30000,
	time = 45, requires = { "military_doctrine" }, desc = "CIWS turrets." })
R({ id = "drones_1", name = "Drone Warfare", branch = "Military", col = 2, row = 3, rp = 150, cash = 35000,
	time = 60, requires = { "military_doctrine" }, desc = "Hornet drones and racks." })
R({ id = "mechanized", name = "Mechanized Forces", branch = "Military", col = 2, row = 4, rp = 250,
	cash = 70000, time = 90, requires = { "military_doctrine", "heavy_industry" },
	desc = "Large factory, vehicle depot, trucks and IFVs." })
R({ id = "cruise_missiles", name = "Cruise Missiles", branch = "Military", col = 3, row = 1, rp = 300,
	cash = 90000, time = 90, requires = { "ballistics" }, hits = 5, desc = "GLCM launcher and missiles." })
R({ id = "air_defense_2", name = "Air Defense II", branch = "Military", col = 3, row = 2, rp = 300, cash = 80000,
	time = 90, requires = { "air_defense_1" }, desc = "SAM sites, radar, mobile anti-air." })
R({ id = "drones_2", name = "Jet Drones", branch = "Military", col = 3, row = 3, rp = 350, cash = 100000,
	time = 100, requires = { "drones_1" }, hits = 5, desc = "Raptor jet drones." })
R({ id = "armor", name = "Armored Warfare", branch = "Military", col = 3, row = 4, rp = 450, cash = 130000,
	time = 120, requires = { "mechanized" }, desc = "Main battle tanks." })
R({ id = "mrbm", name = "Medium-Range Missiles", branch = "Military", col = 4, row = 1, rp = 700, cash = 220000,
	time = 150, requires = { "cruise_missiles" }, hits = 10, desc = "MRBM launcher and missiles." })
R({ id = "air_defense_3", name = "Air Defense III", branch = "Military", col = 4, row = 2, rp = 800,
	cash = 250000, time = 180, requires = { "air_defense_2" }, desc = "Long-range SAM." })
R({ id = "rocket_artillery", name = "Rocket Artillery", branch = "Military", col = 4, row = 4, rp = 600,
	cash = 180000, time = 150, requires = { "armor" }, desc = "HIMARS." })
R({ id = "cluster", name = "Cluster Munitions", branch = "Military", col = 5, row = 1, rp = 1000, cash = 350000,
	time = 200, requires = { "mrbm" }, hits = 30, desc = "Cluster BM launcher and missiles." })
R({ id = "directed_energy", name = "Directed Energy", branch = "Military", col = 5, row = 2, rp = 2000,
	cash = 900000, time = 300, requires = { "air_defense_3" }, desc = "Laser defense." })
R({ id = "hypersonic", name = "Hypersonic Weapons", branch = "Military", col = 6, row = 1, rp = 2500,
	cash = 1200000, time = 360, requires = { "cluster" }, hits = 100, desc = "Hypersonic BM launcher." })

function Research.get(id: string): ResearchDef?
	return byId[id]
end

function Research.all(): { ResearchDef }
	return list
end

return Research
