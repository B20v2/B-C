--[[
	Objective chain. Guides new players through every system and pays out
	cash so the early game feels fast. Checked on the server every second.

	kinds:
	  build      - own `count` finished buildings with id `target`
	  population - reach `count` citizens
	  research   - complete research node `target`
	  stock      - hold `count` of weapon `target`
	  launch     - fire `count` weapons in total
	  hits       - land `count` hits in total
	  capture    - capture `count` strategic points in total
	  units      - own `count` units
	  harvests   - harvest `count` crops in total
	  fob        - have `count` FOBs on the battlefield
]]

export type QuestDef = {
	kind: string,
	target: string?,
	count: number,
	reward: number,
	text: string,
}

local Quests: { QuestDef } = {
	{ kind = "build", target = "road", count = 4, reward = 2000, text = "Draw 32 studs of road" },
	{ kind = "build", target = "small_house", count = 3, reward = 3000, text = "Build 3 Small Houses" },
	{ kind = "build", target = "wind_turbine", count = 1, reward = 3000, text = "Build a Wind Turbine" },
	{ kind = "build", target = "water_tower", count = 1, reward = 3000, text = "Build a Water Tower" },
	{ kind = "population", count = 60, reward = 5000, text = "Reach 60 population" },
	{ kind = "build", target = "shop", count = 1, reward = 5000, text = "Build a Corner Shop" },
	{ kind = "build", target = "park", count = 1, reward = 5000, text = "Build a Park" },
	{ kind = "build", target = "farm_field", count = 1, reward = 4000, text = "Build a Farm Field (Farms tab)" },
	{ kind = "harvests", count = 1, reward = 6000, text = "Plant and harvest a crop - walk up and press E" },
	{ kind = "build", target = "oil_pump", count = 2, reward = 8000, text = "Build 2 Oil Pumps" },
	{ kind = "build", target = "small_refinery", count = 1, reward = 10000, text = "Build a Small Refinery" },
	{ kind = "build", target = "research_lab", count = 1, reward = 10000, text = "Build a Research Lab" },
	{ kind = "research", target = "military_doctrine", count = 1, reward = 20000, text = "Research Military Doctrine" },
	{ kind = "build", target = "small_military_factory", count = 1, reward = 25000, text = "Build a Small Military Factory" },
	{ kind = "build", target = "barracks", count = 1, reward = 20000, text = "Build a Barracks and train a squad" },
	{ kind = "research", target = "ballistics", count = 1, reward = 25000, text = "Research Ballistics" },
	{ kind = "build", target = "srbm_launcher", count = 1, reward = 30000, text = "Build an SRBM Launcher" },
	{ kind = "stock", target = "SRBM", count = 3, reward = 30000, text = "Produce 3 SRBMs" },
	{ kind = "launch", count = 1, reward = 40000, text = "Travel and launch a missile" },
	{ kind = "population", count = 1000, reward = 50000, text = "Reach 1,000 population" },
	{ kind = "hits", count = 5, reward = 60000, text = "Land 5 hits" },
	{ kind = "units", count = 3, reward = 75000, text = "Have 3 units (squads, vehicles or helicopters)" },
	{ kind = "capture", count = 1, reward = 100000, text = "Capture a strategic point" },
	{ kind = "fob", count = 1, reward = 120000, text = "Set up a FOB on the battlefield" },
	{ kind = "population", count = 5000, reward = 150000, text = "Reach 5,000 population" },
	{ kind = "hits", count = 30, reward = 200000, text = "Land 30 hits" },
	{ kind = "population", count = 15000, reward = 400000, text = "Reach 15,000 population" },
	{ kind = "hits", count = 100, reward = 750000, text = "Land 100 hits" },
}

return Quests
