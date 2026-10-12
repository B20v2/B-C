--[[
	Monetization catalog.

	HOW TO GO LIVE: create each pass / developer product on the Creator Hub
	(Monetization tab of your experience) and paste its ID into `id` below.
	While an ID is 0 the item is still shown in the store and, in Studio with
	Config.StudioFreePurchases enabled, buying it grants it for free so every
	perk can be tested.

	`robux` is only the fallback label; the live price is fetched from
	MarketplaceService at runtime.
]]

export type PassDef = {
	key: string,
	id: number,
	name: string,
	robux: number,
	desc: string,
	perks: { string },
	color: Color3,
	order: number?,
}

export type ProductDef = {
	key: string,
	id: number,
	name: string,
	robux: number,
	desc: string,
	kind: string, -- "cash" | "instantBuild" | "instantResearch" | "boost" | "supply" | "starter" | "repair"
	minutes: number?, -- cash packs: minutes of income; boosts: duration
	minCash: number?,
	oneTime: boolean?,
	tag: string?,
	order: number?,
}

local Products = {}

Products.Passes = {
	{ key = "DoubleCash", id = 0, name = "2x Cash", robux = 449, color = Color3.fromRGB(46, 160, 90),
		desc = "Double every pay day, forever.", perks = { "2x pay day income", "2x offline earnings" } },
	{ key = "VIP", id = 0, name = "VIP", robux = 299, color = Color3.fromRGB(222, 170, 40),
		desc = "+25% income, VIP tag and longer offline earnings.",
		perks = { "+25% income", "VIP chat tag", "Offline earnings x2", "+10 unit cap" } },
	{ key = "FastBuild", id = 0, name = "Fast Construction", robux = 249, color = Color3.fromRGB(60, 130, 220),
		desc = "Buildings, research and factories work twice as fast.",
		perks = { "2x construction speed", "2x research speed", "2x factory speed" } },
	{ key = "EasternPack", id = 0, name = "Eastern Military Pack", robux = 399, color = Color3.fromRGB(176, 60, 60),
		desc = "Unlock the Eastern faction arsenal.",
		perks = { "Tor-M2, S-300, S-400", "OTR Launcher, Swarm Rack", "BMP-3, T-90, Tor-M" } },
	{ key = "EuropeanPack", id = 0, name = "European Military Pack", robux = 399, color = Color3.fromRGB(56, 92, 170),
		desc = "Unlock the European faction arsenal.",
		perks = { "Crotale NG, SAMP/T", "Storm Battery, Falcon Ramp", "VBCI, Leclerc, CAESAR" } },
	{ key = "ExtraQueue", id = 0, name = "Factory Expansion", robux = 149, color = Color3.fromRGB(120, 90, 200),
		desc = "Bigger production queues and a bigger army.",
		perks = { "+3 queue slots per factory", "+20 unit cap" } },
	{ key = "Billboard", id = 0, name = "Billboard", robux = 99, color = Color3.fromRGB(230, 120, 40),
		desc = "Place billboards with your own message.", perks = { "Up to 6 custom billboards" } },
} :: { PassDef }

Products.Developer = {
	{ key = "StarterPack", id = 0, name = "Starter Pack", robux = 99, kind = "starter", oneTime = true,
		tag = "BEST VALUE", desc = "$150k, 10 SRBMs and 30 minutes of 2x cash. One time only." },
	{ key = "Cash1", id = 0, name = "Pocket Change", robux = 49, kind = "cash", minutes = 10, minCash = 25000,
		desc = "10 minutes of income." },
	{ key = "Cash2", id = 0, name = "Briefcase", robux = 149, kind = "cash", minutes = 40, minCash = 100000,
		desc = "40 minutes of income." },
	{ key = "Cash3", id = 0, name = "Vault", robux = 399, kind = "cash", minutes = 150, minCash = 400000,
		tag = "POPULAR", desc = "2.5 hours of income." },
	{ key = "Cash4", id = 0, name = "National Treasury", robux = 999, kind = "cash", minutes = 480,
		minCash = 1500000, desc = "8 hours of income." },
	{ key = "Boost2x", id = 0, name = "2x Cash Boost", robux = 99, kind = "boost", minutes = 30,
		desc = "Double income for 30 minutes. Stacks time." },
	{ key = "InstantBuild", id = 0, name = "Instant Construction", robux = 39, kind = "instantBuild",
		desc = "Finish every building under construction now." },
	{ key = "InstantResearch", id = 0, name = "Instant Research", robux = 79, kind = "instantResearch",
		desc = "Finish your current research now." },
	{ key = "SupplyDrop", id = 0, name = "Supply Drop", robux = 149, kind = "supply",
		desc = "Fill every unlocked missile and drone stockpile." },
	{ key = "Repairs", id = 0, name = "Emergency Repairs", robux = 25, kind = "repair",
		desc = "Repair every damaged building for free." },
} :: { ProductDef }

for i, p in Products.Passes do
	p.order = i
end
for i, p in Products.Developer do
	p.order = i
end

function Products.pass(key: string): PassDef?
	for _, p in Products.Passes do
		if p.key == key then
			return p
		end
	end
	return nil
end

function Products.product(key: string): ProductDef?
	for _, p in Products.Developer do
		if p.key == key then
			return p
		end
	end
	return nil
end

function Products.productById(id: number): ProductDef?
	if id == 0 then
		return nil
	end
	for _, p in Products.Developer do
		if p.id == id then
			return p
		end
	end
	return nil
end

return Products
