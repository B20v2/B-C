--[[
	FarmService
	Playable farmland. Each Farm Field is planted with a crop (paid seed),
	grows through four visible stages (faster with workers, nearby
	farmhouses and barns), then is harvested for food. Fields can replant
	themselves automatically. Players can walk up to a field and press E
	(ProximityPrompt) or use the building panel.

	Food: stored nationally (base cap + barns/silos), eaten by citizens every
	pay day (well-fed nations are happier), packed into FOB supplies, and
	sold for cash when storage overflows or from the panel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Crops = require(Shared.Catalog.Crops)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local ModelBuilder = require(Shared.ModelBuilder)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation
type BRuntime = Nations.BRuntime

local FarmService = {}
local S: { [string]: any }

function FarmService.foodCap(n: Nation): number
	return n.stats.foodCap or Config.FoodBaseCap
end

-- Add food; overflow is sold. Returns (stored, sold cash).
function FarmService.addFood(n: Nation, amount: number): (number, number)
	local room = math.max(0, FarmService.foodCap(n) - n.data.Food)
	local stored = math.min(room, amount)
	n.data.Food += stored
	local cash = math.floor((amount - stored) * Config.FoodPrice)
	n.data.Cash += cash
	return stored, cash
end

-- Growth speed boost from farmhouses / barns near the field (capped).
local function boostFor(n: Nation, b: BRuntime): number
	local pos = S.BuildService.worldCFrame(n, b).Position
	local boost = 0
	for _, o in n.buildings do
		if o.def.farmBoost and Nations.isActive(o) then
			local d = (S.BuildService.worldCFrame(n, o).Position - pos).Magnitude
			if d <= Config.FarmBoostRange then
				boost += o.def.farmBoost
			end
		end
	end
	return math.min(boost, 0.5)
end

local function promptText(b: BRuntime): (string, string)
	local crop = Crops.get(b.crop)
	if not crop then
		local last = Crops.get(b.lastCrop) or Crops.all()[1]
		return ("Plant %s ($%d)"):format(last.name, last.seed), "Empty field"
	elseif (b.growth or 0) >= 1 then
		return ("Harvest %s"):format(crop.name), ("%d food ready"):format(crop.yield)
	end
	return ("%s %d%%"):format(crop.name, math.floor((b.growth or 0) * 100)), Crops.StageNames[Crops.stage(b.growth or 0)]
end

-- Rebuild crop visuals + attributes (only when the stage changes).
function FarmService.refresh(b: BRuntime, force: boolean?)
	local model = b.model
	if not model then
		return
	end
	local crop = Crops.get(b.crop)
	local stage = crop and Crops.stage(b.growth or 0) or -1
	if force or model:GetAttribute("Stage") ~= stage or model:GetAttribute("Crop") ~= b.crop then
		ModelBuilder.crops(model, crop, math.max(stage, 0))
		model:SetAttribute("Stage", stage)
	end
	model:SetAttribute("Crop", b.crop)
	model:SetAttribute("Growth", math.floor((b.growth or 0) * 100))
	model:SetAttribute("AutoReplant", b.auto == true)
	local prompt = model:FindFirstChild("FarmPrompt", true) :: ProximityPrompt?
	if prompt then
		local action, object = promptText(b)
		prompt.ActionText = action
		prompt.ObjectText = object
	end
end

function FarmService.plant(n: Nation, b: BRuntime, cropId: string?): (boolean, string?)
	if not b.def.farm then
		return false, "Not a farm field"
	end
	if b.finishAt then
		return false, "The field is still being prepared"
	end
	if b.crop then
		return false, "Something is already growing here"
	end
	local crop = Crops.get(cropId)
	if not crop then
		return false, "Pick a crop"
	end
	if n.data.Cash < crop.seed then
		return false, "Not enough cash for seed"
	end
	n.data.Cash -= crop.seed
	b.crop = crop.id
	b.lastCrop = crop.id
	b.growth = 0
	FarmService.refresh(b)
	return true, nil
end

function FarmService.harvest(n: Nation, b: BRuntime): (boolean, string?, number?)
	local crop = Crops.get(b.crop)
	if not crop then
		return false, "Nothing planted", nil
	end
	if (b.growth or 0) < 1 then
		return false, ("Not ripe yet (%d%%)"):format(math.floor((b.growth or 0) * 100)), nil
	end
	local stored, cash = FarmService.addFood(n, crop.yield)
	n.data.Stats.Harvests = (n.data.Stats.Harvests or 0) + 1
	b.crop = nil
	b.growth = 0
	local pos = b.model and b.model:GetPivot().Position or n.origin
	Net.event("Effect"):FireClient(n.player, "Harvest", pos, crop.yield, cash)
	if b.auto and n.data.Cash >= crop.seed then
		FarmService.plant(n, b, crop.id)
	else
		FarmService.refresh(b)
	end
	local _ = stored
	return true, nil, crop.yield
end

-- Prompt pressed: harvest when ripe, replant the last crop when empty.
local function onPrompt(n: Nation, b: BRuntime, player: Player)
	if player ~= n.player then
		return
	end
	local ok, err
	if b.crop and (b.growth or 0) >= 1 then
		ok, err = FarmService.harvest(n, b)
	elseif not b.crop then
		ok, err = FarmService.plant(n, b, b.lastCrop or Crops.all()[1].id)
	else
		ok, err = false, ("Still growing (%d%%)"):format(math.floor((b.growth or 0) * 100))
	end
	if not ok and err then
		Nations.notify(player, err, "info")
	end
	S.StateService.push(n)
end

-- Called when a field's model is (re)spawned.
function FarmService.attach(n: Nation, b: BRuntime)
	if not b.def.farm or not b.model then
		return
	end
	local base = b.model.PrimaryPart
	if base then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FarmPrompt"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 26
		prompt.RequiresLineOfSight = false
		prompt.Parent = base
		pcall(function()
			prompt.Triggered:Connect(function(player)
				onPrompt(n, b, player)
			end)
		end)
	end
	FarmService.refresh(b, true)
end

-- Grow every planted field (called from the economy tick).
function FarmService.tick(n: Nation, dt: number)
	for _, b in n.buildings do
		if b.def.farm and b.crop and not b.finishAt and not b.damaged then
			local crop = Crops.get(b.crop)
			if crop and (b.growth or 0) < 1 then
				local speed = math.max(b.eff or 0, 0.25) * (1 + boostFor(n, b))
				b.growth = math.min(1, (b.growth or 0) + dt * speed / crop.time)
				FarmService.refresh(b)
				if b.growth >= 1 then
					Nations.notify(n.player, ("%s is ready to harvest"):format(crop.name), "good")
				end
			end
		end
	end
end

-- Pay day: citizens eat. Fed nations get a happiness bonus.
function FarmService.payDay(n: Nation)
	local need = n.data.Population * Config.FoodPerCitizen
	n.stats.foodUse = need
	if need <= 0 then
		n.stats.fed = false
		return
	end
	if n.data.Food >= need then
		n.data.Food -= need
		n.stats.fed = true
	else
		n.data.Food = 0
		n.stats.fed = false
	end
end

local function onFarm(player: Player, uid: any, action: any, cropId: any)
	local n = Nations.get(player)
	if not n or not n.ready or typeof(uid) ~= "number" or typeof(action) ~= "string" then
		return { ok = false, err = "Invalid request" }
	end
	local b = n.buildings[uid]
	if not b or not b.def.farm then
		return { ok = false, err = "Not a farm field" }
	end
	local ok, err, yield
	if action == "plant" then
		ok, err = FarmService.plant(n, b, typeof(cropId) == "string" and cropId or nil)
	elseif action == "harvest" then
		ok, err, yield = FarmService.harvest(n, b)
	elseif action == "auto" then
		b.auto = not b.auto
		FarmService.refresh(b)
		ok = true
	elseif action == "clear" then
		b.crop = nil
		b.growth = 0
		FarmService.refresh(b)
		ok = true
	else
		return { ok = false, err = "Unknown action" }
	end
	S.StateService.push(n)
	return { ok = ok, err = err, yield = yield }
end

-- Harvest every ripe field at once.
local function onHarvestAll(player: Player)
	local n = Nations.get(player)
	if not n or not n.ready then
		return { ok = false }
	end
	local count, food = 0, 0
	for _, b in n.buildings do
		if b.def.farm and b.crop and (b.growth or 0) >= 1 then
			local ok, _, yield = FarmService.harvest(n, b)
			if ok then
				count += 1
				food += yield or 0
			end
		end
	end
	S.StateService.push(n)
	return { ok = count > 0, count = count, food = food, err = count == 0 and "No ripe fields" or nil }
end

local function onSellFood(player: Player, amount: any)
	local n = Nations.get(player)
	if not n or not n.ready then
		return { ok = false }
	end
	-- no amount = sell everything in storage
	local qty = typeof(amount) == "number" and math.clamp(math.floor(amount), 0, n.data.Food) or n.data.Food
	if qty < 1 then
		return { ok = false, err = "No food to sell" }
	end
	n.data.Food = math.max(0, n.data.Food - qty)
	local cash = math.floor(qty * Config.FoodPrice)
	n.data.Cash += cash
	S.StateService.push(n)
	return { ok = true, cash = cash, text = ("Sold %d food for %s"):format(math.floor(qty), Format.cash(cash)) }
end

function FarmService.init(services)
	S = services
end

function FarmService.start()
	Net.handle("FarmAction", onFarm, 10)
	Net.handle("HarvestAll", onHarvestAll, 2)
	Net.handle("SellFood", onSellFood, 2)
end

return FarmService
