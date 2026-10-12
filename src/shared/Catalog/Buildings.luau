--[[
	Buildings catalog
	Every placeable structure. All behaviour is data driven: the server
	services read these fields, the build menu renders them, and the
	ModelBuilder turns `model` + `params` into a clean low-poly asset.

	Units: size is in grid cells (1 cell = Config.CellSize studs),
	rates are per minute, income is per pay day.
]]

export type AirDefense = { range: number, chance: number, reload: number }
export type Refine = { oilCap: number, fuelCap: number, rate: number, trucks: number }

export type BuildingDef = {
	id: string,
	name: string,
	category: string, -- "Civilian" | "Military"
	tab: string,
	faction: string, -- "Standard" | "Eastern" | "European"
	cost: number,
	buildTime: number,
	size: { number }, -- { w, d }
	model: string,
	params: { [string]: any }?,
	desc: string,
	hp: number,
	order: number,
	research: string?,
	pass: string?,
	max: number?,
	drag: boolean?,
	workers: number?,
	power: number?,
	powerOut: number?,
	water: number?,
	waterOut: number?,
	housing: number?,
	income: number?,
	service: { kind: string, serves: number }?,
	pollution: number?,
	oilOut: number?,
	steelOut: number?,
	rpOut: number?,
	refine: Refine?,
	fuelCap: number?,
	factory: { speed: number }?,
	storage: { oil: number?, steel: number? }?,
	airDefense: AirDefense?,
	launcher: string?,
	reload: number?,
	depot: number?,
	radar: number?,
	billboard: boolean?,
	needsRoad: boolean,
}

local Buildings = {}

Buildings.Categories = {
	{ id = "Civilian", tabs = { "Housing", "Roads", "Utilities", "Industry", "Services" } },
	{ id = "Military", tabs = { "Research", "Buildings", "Air Defense", "Missiles", "Drones" } },
}

Buildings.Factions = { "Standard", "Eastern", "European" }
Buildings.FactionPass = { Eastern = "EasternPack", European = "EuropeanPack" }

local list: { BuildingDef } = {}
local byId: { [string]: BuildingDef } = {}
local orderCounter = 0

local function B(def: { [string]: any })
	orderCounter += 1
	def.order = orderCounter
	def.faction = def.faction or "Standard"
	def.hp = def.hp or 100
	if def.needsRoad == nil then
		def.needsRoad = def.tab ~= "Roads"
	end
	if def.faction ~= "Standard" then
		def.pass = def.pass or Buildings.FactionPass[def.faction]
	end
	local typed = def :: BuildingDef
	table.insert(list, typed)
	byId[typed.id] = typed
end

---------------------------------------------------------------------------
-- CIVILIAN / Housing
---------------------------------------------------------------------------
B({ id = "small_house", name = "Small House", category = "Civilian", tab = "Housing",
	cost = 600, buildTime = 4, size = { 2, 2 }, model = "house", params = { roof = "terracotta" },
	housing = 10, power = 1, water = 1, desc = "A cosy family home. Houses 10 citizens." })
B({ id = "cottage", name = "Cottage", category = "Civilian", tab = "Housing",
	cost = 900, buildTime = 5, size = { 2, 3 }, model = "house", params = { roof = "slate", long = true },
	housing = 16, power = 1, water = 1, desc = "A longer home with a slate roof. Houses 16 citizens." })
B({ id = "townhouse", name = "Townhouse Row", category = "Civilian", tab = "Housing",
	cost = 2400, buildTime = 8, size = { 6, 2 }, model = "townhouse", params = { count = 3 },
	housing = 45, power = 3, water = 3, desc = "Three terraced homes. Houses 45 citizens." })
B({ id = "apartment", name = "Apartment Block", category = "Civilian", tab = "Housing",
	cost = 7500, buildTime = 15, size = { 6, 4 }, model = "apartment", params = { floors = 4 },
	housing = 140, power = 8, water = 8, hp = 160, research = "urban_planning",
	desc = "Mid-rise apartments. Houses 140 citizens." })
B({ id = "long_apartment", name = "Long Apartment", category = "Civilian", tab = "Housing",
	cost = 22000, buildTime = 30, size = { 18, 4 }, model = "apartment", params = { floors = 5 },
	housing = 450, power = 22, water = 22, hp = 260, research = "urban_planning",
	desc = "A long panel block. Houses 450 citizens." })
B({ id = "highrise", name = "Highrise Tower", category = "Civilian", tab = "Housing",
	cost = 45000, buildTime = 45, size = { 4, 4 }, model = "tower", params = { floors = 16 },
	housing = 900, power = 40, water = 40, hp = 300, research = "high_density",
	desc = "A residential skyscraper. Houses 900 citizens." })

---------------------------------------------------------------------------
-- CIVILIAN / Roads
---------------------------------------------------------------------------
B({ id = "road", name = "Road", category = "Civilian", tab = "Roads",
	cost = 40, buildTime = 0, size = { 2, 2 }, model = "road", drag = true, hp = 60,
	desc = "Connects buildings. Buildings without road access work at half speed. Drag to place." })
B({ id = "plaza", name = "Town Square", category = "Civilian", tab = "Roads",
	cost = 1200, buildTime = 4, size = { 4, 4 }, model = "plaza", hp = 60, needsRoad = false,
	service = { kind = "Leisure", serves = 150 }, desc = "Paved square that also counts as road access." })

---------------------------------------------------------------------------
-- CIVILIAN / Utilities
---------------------------------------------------------------------------
B({ id = "wind_turbine", name = "Wind Turbine", category = "Civilian", tab = "Utilities",
	cost = 1800, buildTime = 6, size = { 2, 2 }, model = "windTurbine", powerOut = 6, workers = 1,
	needsRoad = false, desc = "Clean power. Produces 6 MW." })
B({ id = "solar_farm", name = "Solar Farm", category = "Civilian", tab = "Utilities",
	cost = 9000, buildTime = 12, size = { 6, 6 }, model = "solarFarm", powerOut = 18, workers = 2,
	research = "solar", desc = "Rows of solar panels. Produces 18 MW." })
B({ id = "coal_plant", name = "Coal Power Plant", category = "Civilian", tab = "Utilities",
	cost = 28000, buildTime = 25, size = { 10, 8 }, model = "coalPlant", powerOut = 80, workers = 60,
	water = 10, pollution = 6, hp = 300, research = "coal_power", desc = "Cheap, dirty power. Produces 80 MW." })
B({ id = "nuclear_plant", name = "Nuclear Power Plant", category = "Civilian", tab = "Utilities",
	cost = 260000, buildTime = 60, size = { 14, 12 }, model = "nuclearPlant", powerOut = 450, workers = 160,
	water = 60, hp = 600, max = 2, research = "nuclear", desc = "Massive clean output. Produces 450 MW." })
B({ id = "water_tower", name = "Water Tower", category = "Civilian", tab = "Utilities",
	cost = 1400, buildTime = 5, size = { 2, 2 }, model = "waterTower", waterOut = 30, power = 1,
	needsRoad = false, desc = "Supplies 30 water." })
B({ id = "pump_station", name = "Pumping Station", category = "Civilian", tab = "Utilities",
	cost = 14000, buildTime = 15, size = { 6, 6 }, model = "pumpStation", waterOut = 220, workers = 20,
	power = 8, research = "water_treatment", desc = "Industrial water supply. Supplies 220 water." })

---------------------------------------------------------------------------
-- CIVILIAN / Industry
---------------------------------------------------------------------------
B({ id = "oil_pump", name = "Oil Pump", category = "Civilian", tab = "Industry",
	cost = 3500, buildTime = 8, size = { 2, 3 }, model = "oilPump", oilOut = 60, workers = 6, power = 2,
	pollution = 1, desc = "Pumps 60 oil / min into national storage." })
B({ id = "oil_tank", name = "Oil Tank Farm", category = "Civilian", tab = "Industry",
	cost = 6000, buildTime = 10, size = { 4, 4 }, model = "oilTank", storage = { oil = 5000 },
	research = "heavy_industry", desc = "Stores +5,000 oil." })
B({ id = "small_refinery", name = "Small Refinery", category = "Civilian", tab = "Industry",
	cost = 12000, buildTime = 15, size = { 6, 6 }, model = "refinery", params = { scale = 1 },
	refine = { oilCap = 1000, fuelCap = 500, rate = 90, trucks = 1 }, workers = 25, power = 6, pollution = 3,
	hp = 200, desc = "Refines oil into fuel. Trucks deliver fuel to factories." })
B({ id = "medium_refinery", name = "Medium Refinery", category = "Civilian", tab = "Industry",
	cost = 35000, buildTime = 30, size = { 10, 8 }, model = "refinery", params = { scale = 2 },
	refine = { oilCap = 2500, fuelCap = 1000, rate = 180, trucks = 1 }, workers = 60, power = 14,
	pollution = 4, hp = 320, research = "heavy_industry", desc = "Refines 180 fuel / min." })
B({ id = "large_refinery", name = "Large Refinery", category = "Civilian", tab = "Industry",
	cost = 90000, buildTime = 45, size = { 14, 10 }, model = "refinery", params = { scale = 3 },
	refine = { oilCap = 6000, fuelCap = 2500, rate = 420, trucks = 2 }, workers = 140, power = 30,
	pollution = 6, hp = 500, research = "petrochemistry", desc = "Refines 420 fuel / min with two trucks." })
B({ id = "steel_mill", name = "Steel Mill", category = "Civilian", tab = "Industry",
	cost = 30000, buildTime = 25, size = { 10, 8 }, model = "steelMill", steelOut = 50, workers = 80, power = 20,
	pollution = 5, hp = 320, research = "heavy_industry", desc = "Produces 50 steel / min." })
B({ id = "warehouse", name = "Warehouse", category = "Civilian", tab = "Industry",
	cost = 8000, buildTime = 10, size = { 8, 6 }, model = "warehouse", storage = { steel = 5000 }, workers = 4,
	desc = "Stores +5,000 steel." })
B({ id = "light_factory", name = "Consumer Factory", category = "Civilian", tab = "Industry",
	cost = 16000, buildTime = 15, size = { 8, 6 }, model = "factory", params = { tint = "civil" },
	income = 1800, workers = 50, power = 10, pollution = 2, hp = 220, desc = "Makes goods. Earns $1,800 per pay." })

---------------------------------------------------------------------------
-- CIVILIAN / Services
---------------------------------------------------------------------------
B({ id = "shop", name = "Corner Shop", category = "Civilian", tab = "Services",
	cost = 3000, buildTime = 6, size = { 3, 3 }, model = "shop", income = 450, workers = 8, power = 2, water = 1,
	service = { kind = "Commerce", serves = 250 }, desc = "Earns $450 per pay and keeps 250 citizens happy." })
B({ id = "park", name = "Park", category = "Civilian", tab = "Services",
	cost = 2000, buildTime = 4, size = { 4, 4 }, model = "park", service = { kind = "Leisure", serves = 300 },
	desc = "Trees and paths. Keeps 300 citizens happy." })
B({ id = "office", name = "Office Block", category = "Civilian", tab = "Services",
	cost = 20000, buildTime = 18, size = { 6, 6 }, model = "office", income = 3500, workers = 90, power = 12,
	water = 6, hp = 220, research = "urban_planning", desc = "Earns $3,500 per pay." })
B({ id = "school", name = "School", category = "Civilian", tab = "Services",
	cost = 18000, buildTime = 18, size = { 8, 6 }, model = "school", workers = 40, power = 6, water = 4,
	rpOut = 3, service = { kind = "Education", serves = 1500 }, research = "public_services",
	desc = "Educates 1,500 citizens and adds a little research." })
B({ id = "hospital", name = "Hospital", category = "Civilian", tab = "Services",
	cost = 32000, buildTime = 25, size = { 8, 8 }, model = "hospital", workers = 70, power = 12, water = 10,
	service = { kind = "Health", serves = 3000 }, hp = 260, research = "public_services",
	desc = "Treats 3,000 citizens." })
B({ id = "billboard", name = "Billboard", category = "Civilian", tab = "Services",
	cost = 5000, buildTime = 3, size = { 4, 1 }, model = "billboard", billboard = true, pass = "Billboard",
	needsRoad = false, max = 6, desc = "Show your own message to every nation. Requires the Billboard pass." })

---------------------------------------------------------------------------
-- MILITARY / Research
---------------------------------------------------------------------------
B({ id = "research_lab", name = "Research Lab", category = "Military", tab = "Research",
	cost = 10000, buildTime = 12, size = { 6, 6 }, model = "researchLab", rpOut = 10, workers = 20, power = 6,
	desc = "Generates 10 research points / min." })
B({ id = "university", name = "University", category = "Military", tab = "Research",
	cost = 40000, buildTime = 30, size = { 10, 8 }, model = "university", rpOut = 30, workers = 60, power = 12,
	water = 6, research = "public_services", service = { kind = "Education", serves = 2500 },
	desc = "Generates 30 RP / min and educates citizens." })
B({ id = "military_academy", name = "Military Research Center", category = "Military", tab = "Research",
	cost = 60000, buildTime = 35, size = { 10, 10 }, model = "milResearch", rpOut = 45, workers = 80, power = 20,
	hp = 300, research = "military_doctrine", desc = "Generates 45 RP / min." })

---------------------------------------------------------------------------
-- MILITARY / Buildings
---------------------------------------------------------------------------
B({ id = "small_military_factory", name = "Small Military Factory", category = "Military", tab = "Buildings",
	cost = 25000, buildTime = 25, size = { 8, 8 }, model = "factory", params = { tint = "military" },
	fuelCap = 500, factory = { speed = 1 }, workers = 60, power = 15, pollution = 3, hp = 260,
	research = "military_doctrine", desc = "Builds missiles, drones and vehicles. Needs fuel deliveries." })
B({ id = "large_military_factory", name = "Large Military Factory", category = "Military", tab = "Buildings",
	cost = 80000, buildTime = 45, size = { 14, 10 }, model = "factory", params = { tint = "military", large = true },
	fuelCap = 1000, factory = { speed = 2 }, workers = 150, power = 35, pollution = 5, hp = 450,
	research = "mechanized", desc = "Builds twice as fast. Needs fuel deliveries." })
B({ id = "vehicle_depot", name = "Vehicle Depot", category = "Military", tab = "Buildings",
	cost = 15000, buildTime = 15, size = { 8, 6 }, model = "depot", depot = 10, research = "mechanized",
	desc = "Garage for 10 more vehicles. Vehicles roll out here." })
B({ id = "radar_station", name = "Radar Station", category = "Military", tab = "Buildings",
	cost = 20000, buildTime = 20, size = { 4, 4 }, model = "radar", radar = 0.25, power = 10,
	research = "air_defense_2", needsRoad = false, desc = "+25% range for all your air defense." })

---------------------------------------------------------------------------
-- MILITARY / Air Defense
---------------------------------------------------------------------------
B({ id = "ciws", name = "CIWS Turret", category = "Military", tab = "Air Defense",
	cost = 8000, buildTime = 15, size = { 2, 2 }, model = "ciws", power = 3, needsRoad = false,
	airDefense = { range = 90, chance = 0.35, reload = 4 }, research = "air_defense_1",
	desc = "Rapid-fire point defense. Short range." })
B({ id = "sam_site", name = "SAM Site", category = "Military", tab = "Air Defense",
	cost = 22000, buildTime = 30, size = { 4, 4 }, model = "sam", power = 6, needsRoad = false,
	airDefense = { range = 180, chance = 0.55, reload = 8 }, research = "air_defense_2",
	desc = "Medium-range surface-to-air missiles." })
B({ id = "lr_sam", name = "Long-Range SAM", category = "Military", tab = "Air Defense",
	cost = 55000, buildTime = 45, size = { 6, 6 }, model = "sam", params = { large = true }, power = 12,
	airDefense = { range = 320, chance = 0.7, reload = 12 }, research = "air_defense_3", needsRoad = false,
	desc = "Covers most of your nation." })
B({ id = "laser_defense", name = "Laser Defense", category = "Military", tab = "Air Defense",
	cost = 120000, buildTime = 60, size = { 3, 3 }, model = "laser", power = 60, needsRoad = false,
	airDefense = { range = 140, chance = 0.85, reload = 3 }, research = "directed_energy",
	desc = "Directed energy. Very high hit chance, needs lots of power." })
B({ id = "tor_system", name = "Tor-M2", category = "Military", tab = "Air Defense", faction = "Eastern",
	cost = 14000, buildTime = 18, size = { 3, 3 }, model = "ciws", params = { eastern = true }, power = 4,
	airDefense = { range = 130, chance = 0.45, reload = 5 }, research = "air_defense_1", needsRoad = false,
	desc = "Eastern short-range system with better reach." })
B({ id = "s300", name = "S-300 Battery", category = "Military", tab = "Air Defense", faction = "Eastern",
	cost = 48000, buildTime = 40, size = { 6, 6 }, model = "sam", params = { large = true, eastern = true },
	power = 10, airDefense = { range = 300, chance = 0.62, reload = 10 }, research = "air_defense_2",
	needsRoad = false, desc = "Long reach, early. Eastern pack." })
B({ id = "s400", name = "S-400 Battery", category = "Military", tab = "Air Defense", faction = "Eastern",
	cost = 90000, buildTime = 55, size = { 7, 7 }, model = "sam", params = { large = true, eastern = true },
	power = 16, airDefense = { range = 420, chance = 0.75, reload = 12 }, research = "air_defense_3",
	needsRoad = false, desc = "The longest-range defense in the game." })
B({ id = "crotale", name = "Crotale NG", category = "Military", tab = "Air Defense", faction = "European",
	cost = 13000, buildTime = 16, size = { 3, 3 }, model = "ciws", params = { european = true }, power = 4,
	airDefense = { range = 120, chance = 0.5, reload = 5 }, research = "air_defense_1", needsRoad = false,
	desc = "Accurate short-range European system." })
B({ id = "samp_t", name = "SAMP/T", category = "Military", tab = "Air Defense", faction = "European",
	cost = 60000, buildTime = 45, size = { 6, 6 }, model = "sam", params = { large = true, european = true },
	power = 12, airDefense = { range = 340, chance = 0.72, reload = 10 }, research = "air_defense_2",
	needsRoad = false, desc = "Fast-reloading long-range European battery." })

---------------------------------------------------------------------------
-- MILITARY / Missiles
---------------------------------------------------------------------------
B({ id = "srbm_launcher", name = "SRBM Launcher", category = "Military", tab = "Missiles",
	cost = 12000, buildTime = 48, size = { 3, 5 }, model = "launcher", params = { kind = "erect" },
	launcher = "SRBM", reload = 20, research = "ballistics", needsRoad = false,
	desc = "Fires short-range ballistic missiles." })
B({ id = "glcm_launcher", name = "GLCM Launcher", category = "Military", tab = "Missiles",
	cost = 15000, buildTime = 52, size = { 4, 6 }, model = "launcher", params = { kind = "box" },
	launcher = "GLCM", reload = 20, research = "cruise_missiles", needsRoad = false,
	desc = "Fires low-flying cruise missiles that dodge defenses." })
B({ id = "mrbm_launcher", name = "MRBM Launcher", category = "Military", tab = "Missiles",
	cost = 18000, buildTime = 56, size = { 4, 6 }, model = "launcher", params = { kind = "erect", big = true },
	launcher = "MRBM", reload = 30, research = "mrbm", needsRoad = false, desc = "Heavy ballistic missiles." })
B({ id = "cluster_launcher", name = "Cluster BM Launcher", category = "Military", tab = "Missiles",
	cost = 20000, buildTime = 56, size = { 4, 6 }, model = "launcher", params = { kind = "erect", tint = "sand" },
	launcher = "CLUSTER", reload = 30, research = "cluster", needsRoad = false, desc = "Wide-area cluster warheads." })
B({ id = "hypersonic_launcher", name = "Hypersonic BM Launcher", category = "Military", tab = "Missiles",
	cost = 36000, buildTime = 80, size = { 4, 7 }, model = "launcher", params = { kind = "erect", big = true, tint = "dark" },
	launcher = "HYPERSONIC", reload = 40, research = "hypersonic", needsRoad = false,
	desc = "Almost impossible to intercept." })
B({ id = "otr_launcher", name = "OTR Launcher", category = "Military", tab = "Missiles", faction = "Eastern",
	cost = 16000, buildTime = 44, size = { 3, 5 }, model = "launcher", params = { kind = "erect", tint = "eastern" },
	launcher = "SRBM", reload = 12, research = "ballistics", needsRoad = false,
	desc = "Eastern SRBM launcher that reloads much faster." })
B({ id = "scalp_battery", name = "Storm Battery", category = "Military", tab = "Missiles", faction = "European",
	cost = 19000, buildTime = 48, size = { 4, 6 }, model = "launcher", params = { kind = "box", tint = "european" },
	launcher = "GLCM", reload = 12, research = "cruise_missiles", needsRoad = false,
	desc = "European cruise battery that reloads much faster." })

---------------------------------------------------------------------------
-- MILITARY / Drones
---------------------------------------------------------------------------
B({ id = "hornet_launcher", name = "Hornet Drone Rack", category = "Military", tab = "Drones",
	cost = 6000, buildTime = 20, size = { 3, 3 }, model = "droneRack", launcher = "HORNET", reload = 6,
	research = "drones_1", needsRoad = false, desc = "Launches cheap one-way attack drones." })
B({ id = "raptor_launcher", name = "Raptor Jet Ramp", category = "Military", tab = "Drones",
	cost = 14000, buildTime = 35, size = { 4, 7 }, model = "droneRamp", launcher = "RAPTOR", reload = 12,
	research = "drones_2", needsRoad = false, desc = "Launches fast jet-powered strike drones." })
B({ id = "swarm_rack", name = "Swarm Rack", category = "Military", tab = "Drones", faction = "Eastern",
	cost = 9000, buildTime = 20, size = { 4, 4 }, model = "droneRack", params = { big = true }, launcher = "HORNET",
	reload = 3, research = "drones_1", needsRoad = false, desc = "Eastern rack that fires Hornets twice as fast." })
B({ id = "falcon_ramp", name = "Falcon Ramp", category = "Military", tab = "Drones", faction = "European",
	cost = 18000, buildTime = 30, size = { 4, 7 }, model = "droneRamp", params = { tint = "european" },
	launcher = "RAPTOR", reload = 6, research = "drones_2", needsRoad = false,
	desc = "European ramp that launches Raptors twice as fast." })

function Buildings.get(id: string): BuildingDef?
	return byId[id]
end

function Buildings.all(): { BuildingDef }
	return list
end

function Buildings.forTab(category: string, tab: string, faction: string?): { BuildingDef }
	local out = {}
	for _, def in list do
		if def.category == category and def.tab == tab then
			if faction == nil or def.faction == faction then
				table.insert(out, def)
			end
		end
	end
	return out
end

-- Tabs that contain faction variants show the Standard / Eastern / European toggle.
function Buildings.tabHasFactions(category: string, tab: string): boolean
	for _, def in list do
		if def.category == category and def.tab == tab and def.faction ~= "Standard" then
			return true
		end
	end
	return false
end

return Buildings
