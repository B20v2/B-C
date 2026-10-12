--[[
	ShopUI
	The store: Featured (starter pack + best sellers), Passes, Cash and
	Boosts. Prices are fetched live from Roblox; cash packs show exactly how
	much they will give right now (they scale with your income).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Products = require(Shared.Catalog.Products)
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

local ShopUI = {}

local player = Players.LocalPlayer
local priceCache: { [string]: number } = {}

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

local function robuxButton(price: number, owned: boolean, onClick: () -> (), props: { [string]: any }?): TextButton
	local p = {
		Text = owned and "OWNED" or ("R$ " .. Format.commas(price)),
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = owned and Theme.Color.Good or Color3.new(1, 1, 1),
		BackgroundColor3 = owned and Theme.Color.GoodSoft or Theme.Color.Good,
		Size = UDim2.new(1, 0, 0, 36),
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
	return Lib.button(p, { Lib.corner(7) })
end

local function passCard(parent: Instance, def, order: number)
	local owned = (ClientState.get("passes") or {})[def.key] == true
	local card = Lib.card({ LayoutOrder = order, Parent = parent }, { Lib.pad(0) })
	local head = New("Frame", {
		BackgroundColor3 = def.color,
		Size = UDim2.new(1, 0, 0, 58),
		Parent = card,
	}, { Lib.corner(8), New("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)), Rotation = 90 }) })
	New("Frame", { BackgroundColor3 = def.color, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -8), Size = UDim2.new(1, 0, 0, 8), Parent = head })
	Lib.text({ Text = def.name, TextColor3 = Color3.new(1, 1, 1), FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Title, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 26), Parent = head })
	Lib.text({ Text = def.desc, TextColor3 = Color3.fromRGB(240, 240, 240), TextSize = Theme.TextSize.Tiny, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 16), Parent = head })
	local perks = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 66), Size = UDim2.new(1, -24, 1, -116), Parent = card }, { Lib.list("y", 3) })
	for i, perk in def.perks do
		Lib.text({ Text = "•  " .. perk, TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.TextSoft, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i, Parent = perks })
	end
	local btnHolder = New("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 12, 1, -46), Size = UDim2.new(1, -24, 0, 36), Parent = card })
	robuxButton(livePrice("pass", def.id, def.robux), owned, function()
		ShopUI.buyPass(def.key)
	end).Parent = btnHolder
end

local function productCard(parent: Instance, def, order: number, valueText: string?)
	local card = Lib.card({ LayoutOrder = order, Parent = parent }, { Lib.pad(12) })
	if def.tag then
		Lib.chip(def.tag, Theme.Color.GoldSoft, Theme.Color.Amber, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Parent = card })
	end
	Lib.text({ Text = def.name, FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Body, Size = UDim2.new(1, -90, 0, 22), Parent = card })
	Lib.text({ Text = def.desc, TextSize = Theme.TextSize.Small, TextColor3 = Theme.Color.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 34), Parent = card })
	if valueText then
		Lib.text({ Text = valueText, FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Big, TextColor3 = Theme.Color.Good, Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 30), Parent = card })
	end
	local holder = New("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -36), Size = UDim2.new(1, 0, 0, 36), Parent = card })
	robuxButton(livePrice("product", def.id, def.robux), false, function()
		ShopUI.buyProduct(def.key)
	end).Parent = holder
end

local function starterHero(parent: Instance, order: number)
	local def = Products.product("StarterPack")
	if not def or ClientState.get("starter") then
		return
	end
	local hero = New("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, -6, 0, 132),
		LayoutOrder = order,
		Parent = parent,
	}, {
		Lib.corner(10),
		New("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(46, 120, 220), Color3.fromRGB(110, 70, 200)), Rotation = 0 }),
		Lib.pad(16, 20),
	})
	Lib.chip("ONE TIME OFFER", Color3.fromRGB(255, 220, 90), Color3.fromRGB(90, 60, 0), { Parent = hero })
	Lib.text({ Text = "Starter Pack", TextColor3 = Color3.new(1, 1, 1), FontFace = Theme.Font.Bold, TextSize = 28, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(0.6, 0, 0, 34), Parent = hero })
	Lib.text({ Text = "$150,000  ·  10 SRBM missiles  ·  30 min of 2x cash", TextColor3 = Color3.fromRGB(230, 236, 255), TextSize = Theme.TextSize.Body, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(0.65, 0, 0, 20), Parent = hero })
	Lib.text({ Text = "Worth over 10x the Robux of a cash pack", TextColor3 = Color3.fromRGB(255, 226, 120), FontFace = Theme.Font.Bold, TextSize = Theme.TextSize.Small, Position = UDim2.fromOffset(0, 84), Size = UDim2.new(0.65, 0, 0, 18), Parent = hero })
	robuxButton(livePrice("product", def.id, def.robux), false, function()
		ShopUI.buyProduct("StarterPack")
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(170, 48),
		BackgroundColor3 = Color3.fromRGB(255, 196, 40),
		TextColor3 = Color3.fromRGB(60, 40, 0),
		TextSize = 20,
		Parent = hero,
	})
end

local TABS = { "Featured", "Passes", "Cash", "Boosts" }

function ShopUI.open(tabName: string?)
	local current = tabName or "Featured"
	local win = Modal.open("Store", "Support the game and grow faster", 920, 640)
	local ic = Icons.cart(38, Theme.Color.Gold)
	ic.Position = UDim2.fromOffset(6, 4)
	ic.Parent = win.iconHolder

	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = win.body }, { Lib.list("x", 8) })
	local content = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Faint,
		BorderSizePixel = 0,
		Parent = win.body,
	})

	local render
	local function renderTabs()
		Lib.clear(tabs)
		for i, t in TABS do
			Lib.button({
				Text = t,
				FontFace = Theme.Font.Semi,
				BackgroundColor3 = t == current and Theme.Color.TabActive or Theme.Color.Tab,
				Size = UDim2.fromOffset(110, 34),
				LayoutOrder = i,
				Parent = tabs,
				Activated = function()
					current = t
					renderTabs()
					render()
				end,
			}, { Lib.corner(6) })
		end
	end

	render = function()
		for _, c in content:GetChildren() do
			c:Destroy()
		end
		local function grid(cellH: number, cols: number, order: number): Frame
			return New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -6, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = order,
				Parent = content,
			}, { Lib.grid(UDim2.new(1 / cols, -8, 0, cellH), 8) })
		end
		Lib.list("y", 12).Parent = content
		if current == "Featured" then
			starterHero(content, 1)
			local g = grid(250, 3, 2)
			for i, key in { "DoubleCash", "VIP", "FastBuild" } do
				local def = Products.pass(key)
				if def then
					passCard(g, def, i)
				end
			end
			local g2 = grid(150, 3, 3)
			for i, key in { "Cash3", "Boost2x", "SupplyDrop" } do
				local def = Products.product(key)
				if def then
					productCard(g2, def, i, def.kind == "cash" and ("+" .. Format.cash(cashValue(def))) or nil)
				end
			end
		elseif current == "Passes" then
			local g = grid(250, 3, 1)
			for i, def in Products.Passes do
				passCard(g, def, i)
			end
		elseif current == "Cash" then
			Lib.text({ Text = "Cash packs scale with your income - the bigger your nation, the more you get.", TextColor3 = Theme.Color.Muted, TextSize = Theme.TextSize.Small, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0, Parent = content })
			local g = grid(160, 2, 1)
			local i = 0
			for _, def in Products.Developer do
				if def.kind == "cash" then
					i += 1
					productCard(g, def, i, "+" .. Format.cash(cashValue(def)))
				end
			end
		else
			local g = grid(150, 3, 1)
			local i = 0
			for _, def in Products.Developer do
				if def.kind ~= "cash" and def.kind ~= "starter" then
					i += 1
					productCard(g, def, i, nil)
				end
			end
		end
	end

	renderTabs()
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
	-- warm the price cache so the store opens instantly
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
