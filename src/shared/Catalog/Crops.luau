--[[
	Crops you can plant in a Farm Field. Seed is paid when planting; the
	field grows through four stages (ploughed, sprouts, growing, ripe) and
	is harvested for food. Food feeds your population (well-fed nations are
	happier), is packed into supplies for your FOB, and overflow is sold.
]]

export type CropDef = {
	id: string,
	name: string,
	seed: number, -- $ per planting
	time: number, -- seconds to ripen at 100% efficiency
	yield: number, -- food per harvest
	height: number, -- plant height when ripe (studs)
	green: Color3,
	ripe: Color3,
	order: number,
}

local Crops = {}

local list: { CropDef } = {}
local byId: { [string]: CropDef } = {}

local function C(def: { [string]: any })
	def.order = #list + 1
	local typed = def :: CropDef
	table.insert(list, typed)
	byId[typed.id] = typed
end

local rgb = Color3.fromRGB

C({ id = "wheat", name = "Wheat", seed = 120, time = 60, yield = 90, height = 1.6,
	green = rgb(118, 164, 70), ripe = rgb(226, 188, 92) })
C({ id = "potatoes", name = "Potatoes", seed = 150, time = 90, yield = 150, height = 1.1,
	green = rgb(84, 140, 64), ripe = rgb(98, 132, 58) })
C({ id = "corn", name = "Corn", seed = 220, time = 120, yield = 220, height = 3.4,
	green = rgb(88, 150, 60), ripe = rgb(212, 184, 86) })
C({ id = "sunflowers", name = "Sunflowers", seed = 320, time = 160, yield = 300, height = 3.8,
	green = rgb(80, 132, 56), ripe = rgb(250, 196, 40) })

function Crops.get(id: string?): CropDef?
	return id and byId[id] or nil
end

function Crops.all(): { CropDef }
	return list
end

-- Growth stage 0-3 from progress 0-1.
function Crops.stage(progress: number): number
	if progress >= 1 then
		return 3
	elseif progress >= 0.55 then
		return 2
	elseif progress >= 0.2 then
		return 1
	end
	return 0
end

Crops.StageNames = { [0] = "Ploughed", [1] = "Sprouting", [2] = "Growing", [3] = "Ripe" }

return Crops
