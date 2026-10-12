--[[
	Weapons catalog: missiles and drones.
	Produced in military factories, stored in the national stockpile and
	fired from launchers of the matching `family`.
]]

export type WeaponDef = {
	id: string,
	name: string,
	short: string, -- hotbar label
	kind: string, -- "missile" | "drone"
	family: string, -- which launcher fires it
	cost: number,
	fuel: number,
	steel: number,
	time: number, -- seconds to produce at speed 1
	damage: number,
	radius: number,
	flight: number, -- seconds in the air
	apex: number, -- arc height (studs)
	interceptMod: number, -- multiplies air defense hit chance
	stockCap: number,
	research: string,
	order: number,
	color: Color3,
	desc: string,
}

local Weapons = {}

local list: { WeaponDef } = {}
local byId: { [string]: WeaponDef } = {}

local function W(def: { [string]: any })
	def.order = #list + 1
	def.stockCap = def.stockCap or 60
	local typed = def :: WeaponDef
	table.insert(list, typed)
	byId[typed.id] = typed
end

W({ id = "HORNET", name = "Hornet Drone", short = "HORNET", kind = "drone", family = "HORNET",
	cost = 600, fuel = 10, steel = 5, time = 8, damage = 30, radius = 14, flight = 22, apex = 40,
	interceptMod = 1.25, research = "drones_1", color = Color3.fromRGB(150, 155, 140),
	desc = "Slow, cheap loitering munition. Swarm defenses with them." })
W({ id = "RAPTOR", name = "Raptor Jet Drone", short = "RAPTOR", kind = "drone", family = "RAPTOR",
	cost = 1800, fuel = 25, steel = 12, time = 14, damage = 55, radius = 18, flight = 12, apex = 70,
	interceptMod = 0.9, research = "drones_2", color = Color3.fromRGB(120, 128, 118),
	desc = "Fast jet-powered strike drone." })
W({ id = "SRBM", name = "Short-Range Ballistic Missile", short = "SRBM", kind = "missile", family = "SRBM",
	cost = 2500, fuel = 40, steel = 20, time = 20, damage = 70, radius = 26, flight = 9, apex = 280,
	interceptMod = 1.0, research = "ballistics", color = Color3.fromRGB(96, 110, 70),
	desc = "Reliable ballistic strike." })
W({ id = "GLCM", name = "Ground-Launched Cruise Missile", short = "GLCM", kind = "missile", family = "GLCM",
	cost = 3200, fuel = 60, steel = 25, time = 24, damage = 80, radius = 22, flight = 15, apex = 28,
	interceptMod = 0.7, research = "cruise_missiles", color = Color3.fromRGB(150, 156, 162),
	desc = "Hugs the ground. Air defense struggles to hit it." })
W({ id = "MRBM", name = "Medium-Range Ballistic Missile", short = "MRBM", kind = "missile", family = "MRBM",
	cost = 6000, fuel = 90, steel = 50, time = 35, damage = 140, radius = 34, flight = 12, apex = 440,
	interceptMod = 0.9, research = "mrbm", color = Color3.fromRGB(180, 182, 176),
	desc = "Heavy warhead, big blast." })
W({ id = "CLUSTER", name = "Cluster Ballistic Missile", short = "CLUSTER", kind = "missile", family = "CLUSTER",
	cost = 7000, fuel = 90, steel = 60, time = 40, damage = 45, radius = 70, flight = 12, apex = 380,
	interceptMod = 1.0, research = "cluster", color = Color3.fromRGB(196, 178, 128),
	desc = "Scatters bomblets over a huge area." })
W({ id = "HYPERSONIC", name = "Hypersonic Ballistic Missile", short = "HYPER", kind = "missile", family = "HYPERSONIC",
	cost = 15000, fuel = 150, steel = 90, time = 60, damage = 200, radius = 34, flight = 6, apex = 180,
	interceptMod = 0.35, research = "hypersonic", color = Color3.fromRGB(60, 64, 70),
	desc = "Mach 10. Defenses rarely react in time." })

function Weapons.get(id: string): WeaponDef?
	return byId[id]
end

function Weapons.all(): { WeaponDef }
	return list
end

return Weapons
