--[[
	MonetizationService
	Game passes, developer products (ProcessReceipt) and Roblox Premium.

	  * Receipts are idempotent: every granted PurchaseId is remembered in the
	    player's data, and we only return PurchaseGranted after granting.
	  * Cash packs scale with the player's income so they stay worth buying at
	    every stage of the game (with a floor for brand new players).
	  * In Studio (Config.StudioFreePurchases) the store's buy buttons grant
	    items directly so every perk can be tested without publishing.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Products = require(Shared.Catalog.Products)
local Weapons = require(Shared.Catalog.Weapons)
local Unlocks = require(Shared.Util.Unlocks)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

local MonetizationService = {}
local S: { [string]: any }

local function isPremium(player: Player): boolean
	local ok, premium = pcall(function()
		return player.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and premium == true
end

local function applyPassPerks(n: Nation)
	n.player:SetAttribute("VIP", n.passes.VIP == true)
end

function MonetizationService.grantPass(n: Nation, key: string)
	if n.passes[key] then
		return
	end
	n.passes[key] = true
	applyPassPerks(n)
	local def = Products.pass(key)
	Nations.notify(n.player, ("%s unlocked! Thank you for supporting the game"):format(def and def.name or key), "good")
	Net.event("PurchaseDone"):FireClient(n.player, "pass", key)
	S.StateService.push(n)
end

function MonetizationService.loadPasses(n: Nation)
	for _, def in Products.Passes do
		if def.id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, n.userId, def.id)
			if ok and owns then
				n.passes[def.key] = true
			end
		end
		-- passes bought in Studio test sessions are remembered in data while testing
		if RunService:IsStudio() and n.data.Flags["StudioPass_" .. def.key] then
			n.passes[def.key] = true
		end
	end
	n.premium = isPremium(n.player)
	applyPassPerks(n)
end

-- Returns true when the product was granted.
function MonetizationService.grantProduct(n: Nation, def): boolean
	local data = n.data
	local kind = def.kind
	if kind == "cash" then
		local amount = math.max(def.minCash or 0, S.EconomyService.incomeFor(n, def.minutes or 10))
		amount = math.floor(amount)
		data.Cash += amount
		Nations.notify(n.player, ("+%s added to your treasury"):format(Format.cash(amount)), "pay")
	elseif kind == "boost" then
		data.BoostUntil = math.max(os.time(), data.BoostUntil) + (def.minutes or 30) * 60
		Nations.notify(n.player, "2x Cash boost active!", "good")
	elseif kind == "instantBuild" then
		S.BuildService.finishAll(n)
		Nations.notify(n.player, "All construction finished!", "good")
	elseif kind == "instantResearch" then
		if data.ActiveResearch then
			S.ResearchService.complete(n)
		else
			-- nothing running: bank the value as research points instead
			data.ResearchPoints += 500
			Nations.notify(n.player, "No research running - +500 RP instead", "good")
		end
	elseif kind == "supply" then
		local access = S.BuildService.access(n)
		for _, w in Weapons.all() do
			if Unlocks.check(w, access) then
				data.Inventory[w.id] = math.max(data.Inventory[w.id] or 0, w.stockCap)
			end
		end
		Nations.notify(n.player, "Supply drop delivered: stockpiles full!", "good")
	elseif kind == "repair" then
		local count = S.BuildService.repairAll(n, true)
		Nations.notify(n.player, ("%d buildings repaired"):format(count), "good")
	elseif kind == "starter" then
		data.Cash += 150000
		data.Inventory.SRBM = (data.Inventory.SRBM or 0) + 10
		data.BoostUntil = math.max(os.time(), data.BoostUntil) + 30 * 60
		data.Flags.StarterPack = true
		Nations.notify(n.player, "Starter Pack: +$150k, 10 SRBMs and 30 min of 2x cash!", "good")
	else
		return false
	end
	Net.event("PurchaseDone"):FireClient(n.player, "product", def.key)
	S.StateService.push(n)
	return true
end

local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local n = Nations.get(player)
	if not n or not n.ready then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts = n.data.Receipts
	if table.find(receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local def = Products.productById(info.ProductId)
	if not def then
		warn("[Monetization] Unknown product id " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(MonetizationService.grantProduct, n, def)
	if not ok or not granted then
		warn("[Monetization] Grant failed: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(receipts, info.PurchaseId)
	while #receipts > 60 do
		table.remove(receipts, 1)
	end
	S.DataService.save(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onStudioPurchase(player: Player, kind: any, key: any)
	if not (RunService:IsStudio() and Config.StudioFreePurchases) then
		return { ok = false, err = "Purchases go through Roblox" }
	end
	local n = Nations.get(player)
	if not n or typeof(key) ~= "string" then
		return { ok = false }
	end
	if kind == "pass" then
		if not Products.pass(key) then
			return { ok = false }
		end
		n.data.Flags["StudioPass_" .. key] = true
		MonetizationService.grantPass(n, key)
		return { ok = true }
	elseif kind == "product" then
		local def = Products.product(key)
		if not def then
			return { ok = false }
		end
		return { ok = MonetizationService.grantProduct(n, def) }
	end
	return { ok = false }
end

function MonetizationService.init(services)
	S = services
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local n = Nations.get(player)
		if not n then
			return
		end
		for _, def in Products.Passes do
			if def.id == passId and def.id ~= 0 then
				MonetizationService.grantPass(n, def.key)
			end
		end
	end)
	Players.PlayerMembershipChanged:Connect(function(player)
		local n = Nations.get(player)
		if n then
			n.premium = isPremium(player)
		end
	end)
	Net.handle("StudioPurchase", onStudioPurchase, 3)
end

return MonetizationService
