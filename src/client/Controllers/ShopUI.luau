--[[
	ShopUI - Supply Depot (store)
	Left nav (Featured / Game Passes / Treasury / Boosts), a hero banner with
	a turntable 3D model, pass cards with model art and perk lists, cash packs
	that show their live value (they scale with income) and boosts.
	Prices come live from Roblox; in Studio, buys are granted for testing.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Products = require(Shared.Catalog.Products)
local Buildings = require(Shared.Catalog.Buildings)
local ModelBuilder = require(Shared.ModelBuilder)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)
local Modal = require(script.Parent.Modal)
local Notifications = require(script.Parent.Notifications)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New
local C = Theme.Color

local ShopUI = {}

local player = Players.LocalPlayer
local priceCache: { [string]: number } = {}

-- Model shown as card art for each pass.
local PASS_ART = {
	DoubleCash = { icon = "coin" },
	VIP = { icon = "star" },
	FastBuild = { model = "office" },
	EasternPack = { model = "s400" },
	EuropeanPack = { model = "samp_t" },
	ExtraQueue = { model = "large_military_factory" },
	Billboard = { model = "billboard" },
}

local function livePrice(kind: string, id: number, fallback: number): number
	if id == 0 then
		return fallback
	end
	local key = kind .. id
	if priceCache[key] then
		return priceCache[key]
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, kind == "pass" and Enum.InfoType.GamePass or Enum.InfoType.Product)
	end)
	if ok and info and info.PriceInRobux then
		priceCache[key] = info.PriceInRobux
		return info.PriceInRobux
	end
	return fallback
end

local function notConfigured()
	Notifications.show("This item isn't on sale yet (add its ID in Shared/Catalog/Products)", "bad")
end

function ShopUI.buyPass(key: string)
	local def = Products.pass(key)
	if not def then
		return
	end
	if (ClientState.get("passes") or {})[key] then
		Notifications.show("You already own " .. def.name, "info")
		return
	end
	if def.id ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, def.id)
	elseif RunService:IsStudio() and Config.StudioFreePurchases then
		Net.request("StudioPurchase", "pass", key)
	else
		notConfigured()
	end
end

function ShopUI.buyProduct(key: string)
	local def = Products.product(key)
	if not def then
		return
	end
	if def.oneTime and def.kind == "starter" and ClientState.get("starter") then
		Notifications.show("You already bought the Starter Pack", "info")
		return
	end
	if def.id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, def.id)
	elseif RunService:IsStudio() and Config.StudioFreePurchases then
		Net.request("StudioPurchase", "product", key)
	else
		notConfigured()
	end
end

local function cashValue(def): number
	local gross = ClientState.get("gross") or 0
	return math.floor(math.max(def.minCash or 0, gross * ((def.minutes or 10) * 60 / Config.PayInterval)))
end

local function priceButton(price: number, owned: boolean, onClick: () -> (), props: { [string]: any }?): TextButton
	local p = {
		Name = "Buy",
		Variant = owned and "good" or "primary",
		Text = owned and "OWNED" or ("R$ " .. Format.commas(price)),
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 38),
		Activated = function()
			if not owned then
				Sounds.play("Open")
				onClick()
			end
		end,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return Lib.button(p)
end

local function art(parent: Instance, spec, color: Color3, spin: number?)
	local box = Lib.inset({ Size = UDim2.new(1, 0, 0, 96), Parent = parent })
	New("UIGradient", { Color = ColorSequence.new(color:Lerp(C.Ink, 0.55), C.Ink), Rotation = 90, Parent = box })
	if spec and spec.model then
		local def = Buildings.get(spec.model)
		if def then
			Lib.viewport(ModelBuilder.building(def), { Parent = box }, 35, spin)
		end
	else
		local ic = Icons.get(spec and spec.icon or "star", 52, color)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = box
	end
	return box
end

local function passCard(parent: Instance, def, order: number)
	local owned = (ClientState.get("passes") or {})[def.key] == true
	local card = Lib.card({ Name = def.key, LayoutOrder = order, Parent = parent }, { Lib.pad(8) })
	if owned then
		Lib.stroke(C.Good, 1, 0.3).Parent = card
	end
	local a = art(card, PASS_ART[def.key], def.color)
	New("Frame", { BackgroundColor3 = def.color, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), Parent = a })
	Lib.display({ Text = string.upper(def.name), TextSize = 16, Position = UDim2.fromOffset(4, 104), Size = UDim2.new(1, -8, 0, 20), Parent = card })
	Lib.text({ Text = def.desc, TextSize = 12, TextColor3 = C.Muted, TextWrapped = true, Position = UDim2.fromOffset(4, 124), Size = UDim2.new(1, -8, 0, 30), TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
	local perks = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 156), Size = UDim2.new(1, -8, 1, -206), Parent = card }, { Lib.list("y", 3) })
	for i, perk in def.perks do
		local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = i, Parent = perks }, { Lib.list("x", 7, nil, Enum.VerticalAlignment.Center) })
		New("Frame", { BackgroundColor3 = C.Accent, Size = UDim2.fromOffset(5, 5), LayoutOrder = 1, Parent = row })
		Lib.text({ Text = perk, TextSize = 12, FontFace = Theme.Font.BodyBold, TextColor3 = C.TextSoft, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, Parent = row })
	end
	local holder = New("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -38), Size = UDim2.new(1, 0, 0, 38), Parent = card })
	priceButton(livePrice("pass", def.id, def.robux), owned, function()
		ShopUI.buyPass(def.key)
	end).Parent = holder
end

local function productCard(parent: Instance, def, order: number, valueText: string?, icon: string?, color: Color3?)
	local card = Lib.card({ Name = def.key, LayoutOrder = order, Parent = parent }, { Lib.pad(10) })
	local col = color or C.Accent
	local ic = Icons.get(icon or "coin", 30, col)
	ic.Position = UDim2.fromOffset(0, 2)
	ic.Parent = card
	if def.tag then
		Lib.chip(def.tag, C.GoldSoft, C.Gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = card })
	end
	Lib.display({ Text = string.upper(def.name), TextSize = 15, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -120, 0, 20), Parent = card })
	Lib.text({ Text = def.desc, TextSize = 12, TextColor3 = C.Muted, TextWrapped = true, Position = UDim2.fromOffset(40, 20), Size = UDim2.new(1, -40, 0, 30), TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
	if valueText then
		Lib.display({ Text = valueText, TextSize = 26, TextColor3 = C.Good, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 30), Parent = card })
	end
	local holder = New("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -38), Size = UDim2.new(1, 0, 0, 38), Parent = card })
	priceButton(livePrice("product", def.id, def.robux), false, function()
		ShopUI.buyProduct(def.key)
	end).Parent = holder
end

local function hero(parent: Instance, order: number)
	local starter = Products.product("StarterPack")
	local useStarter = starter ~= nil and not ClientState.get("starter")
	local passDef = Products.pass("DoubleCash")
	local banner = New("Frame", {
		Name = "Hero",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, -6, 0, 210),
		LayoutOrder = order,
		Parent = parent,
	}, {
		Lib.corner(6),
		New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(96, 64, 18), Color3.fromRGB(18, 22, 20)), Rotation = 0 }),
		Lib.stroke(C.Accent, 1, 0.3),
	})
	Lib.brackets(banner, C.Accent, 14, 2, 4)
	Lib.hazard({ Size = UDim2.new(0, 220, 0, 5), Parent = banner }, C.Accent, Color3.fromRGB(40, 30, 10), 9)
	local view = New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.42, 0, 1, 0), Parent = banner })
	local def = Buildings.get(useStarter and "hypersonic_launcher" or "s400")
	if def then
		Lib.viewport(ModelBuilder.building(def), { Parent = view }, 30, 18)
	end
	local textBox = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 18), Size = UDim2.new(0.56, 0, 1, -36), Parent = banner })
	Lib.chip(useStarter and "ONE-TIME OFFER" or "BEST SELLER", C.Accent, C.OnAccent, { Parent = textBox })
	Lib.display({
		Text = useStarter and "STARTER PACK" or "2X CASH · FOREVER",
		TextSize = 34,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = textBox,
	})
	Lib.text({
		Text = useStarter and "$150,000 treasury  ·  10 SRBM missiles  ·  30 min of 2x cash" or "Every pay day doubled. Offline earnings doubled. Stacks with boosts.",
		TextSize = 15,
		FontFace = Theme.Font.BodyBold,
		TextColor3 = C.TextSoft,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = textBox,
	})
	Lib.display({
		Text = useStarter and "OVER 10X THE VALUE OF A CASH PACK" or "THE #1 WAY TO GROW FASTER",
		TextSize = 12,
		TextColor3 = C.Gold,
		Position = UDim2.fromOffset(0, 114),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = textBox,
	})
	local price = useStarter and livePrice("product", (starter :: any).id, (starter :: any).robux) or livePrice("pass", passDef and passDef.id or 0, passDef and passDef.robux or 449)
	priceButton(price, false, function()
		if useStarter then
			ShopUI.buyProduct("StarterPack")
		else
			ShopUI.buyPass("DoubleCash")
		end
	end, {
		Name = "HeroBuy",
		Variant = "gold",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.fromOffset(220, 46),
		TextSize = 18,
		Parent = textBox,
	})
end

local TABS = {
	{ id = "Featured", label = "FEATURED", icon = "star" },
	{ id = "Passes", label = "GAME PASSES", icon = "shield" },
	{ id = "Cash", label = "TREASURY", icon = "coin" },
	{ id = "Boosts", label = "BOOSTS", icon = "bolt" },
}

local PRODUCT_ICON = {
	boost = { "bolt", C.Good },
	instantBuild = { "hammer", C.Info },
	instantResearch = { "flask", C.Teal },
	supply = { "rocket", C.Military },
	repair = { "shield", C.Gold },
}

function ShopUI.open(tabName: string?)
	local current = tabName or "Featured"
	local win = Modal.open("Supply Depot", "Support the game · grow your nation faster", 1180, 700)
	local ic = Icons.cart(34, C.Gold)
	ic.Position = UDim2.fromOffset(9, 7)
	ic.Parent = win.iconHolder

	local nav = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 190, 1, 0), Parent = win.body }, { Lib.list("y", 6) })
	local content = Lib.scroll({ Position = UDim2.fromOffset(206, 0), Size = UDim2.new(1, -206, 1, 0), Parent = win.body })

	local render
	local function renderNav()
		Lib.clear(nav)
		for i, t in TABS do
			local active = t.id == current
			local b = Lib.button({
				Name = t.id,
				Size = UDim2.new(1, 0, 0, 46),
				BackgroundColor3 = active and C.AccentSoft or C.Raised,
				LayoutOrder = i,
				Parent = nav,
				Activated = function()
					current = t.id
					renderNav()
					render()
				end,
			}, { Lib.corner(4), Lib.stroke(active and C.Accent or C.LineSoft, 1, active and 0.2 or 0) })
			local icn = Icons.get(t.icon, 18, active and C.Accent or C.TextSoft)
			icn.Position = UDim2.fromOffset(12, 14)
			icn.Parent = b
			Lib.display({ Text = t.label, TextSize = 13, TextColor3 = active and C.Accent or C.Text, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -46, 1, 0), Parent = b })
		end
		local note = Lib.text({
			Text = "Purchases support development. Cash packs scale with your income.",
			TextSize = 11,
			TextColor3 = C.Faint,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = 99,
			Parent = nav,
		})
		local _ = note
	end

	render = function()
		for _, c in content:GetChildren() do
			c:Destroy()
		end
		Lib.list("y", 12).Parent = content
		Lib.pad(0, 6, 8, 0).Parent = content
		local function grid(cellH: number, cols: number, order: number): Frame
			return New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = order,
				Parent = content,
			}, { Lib.grid(UDim2.new(1 / cols, -8, 0, cellH), 8) })
		end
		if current == "Featured" then
			hero(content, 1)
			Lib.caption("Most popular", { LayoutOrder = 2, Parent = content })
			local g = grid(290, 3, 3)
			for i, key in { "DoubleCash", "VIP", "FastBuild" } do
				local def = Products.pass(key)
				if def then
					passCard(g, def, i)
				end
			end
			Lib.caption("Quick supplies", { LayoutOrder = 4, Parent = content })
			local g2 = grid(140, 3, 5)
			for i, key in { "Cash3", "Boost2x", "SupplyDrop" } do
				local def = Products.product(key)
				if def then
					local spec = PRODUCT_ICON[def.kind]
					productCard(g2, def, i, def.kind == "cash" and ("+" .. Format.cash(cashValue(def))) or nil, spec and spec[1] or "coin", spec and spec[2] or C.Good)
				end
			end
		elseif current == "Passes" then
			local g = grid(290, 3, 1)
			for i, def in Products.Passes do
				passCard(g, def, i)
			end
		elseif current == "Cash" then
			Lib.text({ Text = "Cash packs scale with your income - the bigger your nation, the more you get.", TextColor3 = C.Muted, TextSize = 13, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0, Parent = content })
			local g = grid(150, 2, 1)
			local i = 0
			for _, def in Products.Developer do
				if def.kind == "cash" then
					i += 1
					productCard(g, def, i, "+" .. Format.cash(cashValue(def)), "coin", C.Good)
				end
			end
		else
			local g = grid(140, 3, 1)
			local i = 0
			for _, def in Products.Developer do
				if def.kind ~= "cash" and def.kind ~= "starter" then
					i += 1
					local spec = PRODUCT_ICON[def.kind]
					productCard(g, def, i, nil, spec and spec[1] or "star", spec and spec[2] or C.Accent)
				end
			end
		end
	end

	renderNav()
	render()
	local unsubscribe = ClientState.onAny(function(patch)
		if patch.passes or patch.starter then
			render()
		end
	end)
	win.onClose(unsubscribe)
end

function ShopUI.init()
	Hub.openShop = ShopUI.open
	Hub.buyProduct = ShopUI.buyProduct
	Hub.buyPass = ShopUI.buyPass
	Net.event("PurchaseDone").OnClientEvent:Connect(function()
		Sounds.play("Success")
	end)
	task.spawn(function()
		for _, def in Products.Passes do
			livePrice("pass", def.id, def.robux)
		end
		for _, def in Products.Developer do
			livePrice("product", def.id, def.robux)
		end
	end)
end

return ShopUI
