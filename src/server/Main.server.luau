--[[
	Forge & Frontline - server bootstrap.
	Initialises every service, then creates a runtime Nation for each player
	once their data has loaded, and tears it down (after saving) on leave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local Services = script.Parent.Services
local Nations = require(Services.Nations)

local S = {
	DataService = require(Services.DataService),
	PlotService = require(Services.PlotService),
	StateService = require(Services.StateService),
	BuildService = require(Services.BuildService),
	EconomyService = require(Services.EconomyService),
	LogisticsService = require(Services.LogisticsService),
	ProductionService = require(Services.ProductionService),
	ResearchService = require(Services.ResearchService),
	UnitService = require(Services.UnitService),
	ConquestService = require(Services.ConquestService),
	CombatService = require(Services.CombatService),
	MonetizationService = require(Services.MonetizationService),
	RewardService = require(Services.RewardService),
	NationService = require(Services.NationService),
	WorldService = require(Services.WorldService),
}

local ORDER = {
	"DataService",
	"PlotService",
	"StateService",
	"BuildService",
	"EconomyService",
	"LogisticsService",
	"ProductionService",
	"ResearchService",
	"UnitService",
	"ConquestService",
	"CombatService",
	"MonetizationService",
	"RewardService",
	"NationService",
	"WorldService",
}

-- Make sure every remote exists before any client asks for it.
for _, name in Net.Functions do
	Net.fn(name)
end

for _, name in ORDER do
	S[name].init(S)
end

local function setupLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = "$0"
	cash.Parent = stats
	local pop = Instance.new("StringValue")
	pop.Name = "Population"
	pop.Value = "0"
	pop.Parent = stats
	local power = Instance.new("IntValue")
	power.Name = "Power"
	power.Parent = stats
	stats.Parent = player
end

local Format = require(ReplicatedStorage.Shared.Util.Format)

local function updateLeaderstats(n: Nations.Nation)
	local ls = n.player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash") :: StringValue?
		local pop = ls:FindFirstChild("Population") :: StringValue?
		if cash then
			cash.Value = Format.cash(n.data.Cash)
		end
		if pop then
			pop.Value = Format.short(n.data.Population)
		end
		local power = ls:FindFirstChild("Power") :: IntValue?
		if power and n.stats.rank then
			power.Value = n.stats.rank.power
		end
	end
end

local function onLoaded(player: Player, data: { [string]: any })
	local plot = S.PlotService.claim(player)
	if not plot then
		player:Kick("This server is full. Please join another server.")
		return
	end
	local now = Nations.now()
	local n: Nations.Nation = {
		player = player,
		userId = player.UserId,
		data = data,
		plotIndex = plot.index,
		origin = plot.origin,
		frame = plot.frame,
		folder = plot.buildings,
		buildings = {},
		grid = {},
		stats = {},
		passes = {},
		premium = false,
		joinAt = now,
		nextPayAt = now + Config.PayInterval,
		giftAt = now + Config.PlaytimeGiftInterval,
		pvpLockUntil = 0,
		shieldUntil = data.FirstJoin + Config.NewPlayerShield,
		undo = {},
		units = {},
		nextUnitUid = 1,
		sent = {},
		ready = false,
	}
	Nations.add(n)
	if player.Character then
		player.Character:PivotTo(S.PlotService.spawnCFrame(plot.index))
	end
	player:SetAttribute("Pvp", data.Pvp)
	player:SetAttribute("NationColor", Config.NationColors[plot.index])
	S.MonetizationService.loadPasses(n)
	S.BuildService.loadNation(n)
	if not player.Parent then
		if S.PlotService.get(player) == nil then
			n.folder:ClearAllChildren()
		end
		return
	end
	S.EconomyService.compute(n, 0)
	S.UnitService.loadNation(n)
	S.RewardService.onJoin(n)
	S.NationService.onJoin(n)
	n.ready = true
	S.StateService.push(n, true)
	updateLeaderstats(n)
end

S.DataService.beforeSave(function(player, _data)
	local n = Nations.get(player)
	if n and n.ready then
		S.BuildService.serialize(n)
		S.UnitService.serialize(n)
	end
end)

for _, name in ORDER do
	S[name].start()
end

Players.PlayerAdded:Connect(setupLeaderstats)
for _, p in Players:GetPlayers() do
	setupLeaderstats(p)
end

S.DataService.onLoaded(onLoaded)

Players.PlayerRemoving:Connect(function(player)
	-- serialize + save first (runs synchronously up to the first yield)
	S.DataService.release(player)
	local n = Nations.get(player)
	if n then
		n.ready = false
		S.UnitService.clearNation(n)
		Nations.remove(player)
	end
	S.PlotService.release(player)
end)

-- Leaderboard refresh
task.spawn(function()
	while true do
		task.wait(5)
		for _, n in Nations.all() do
			if n.ready then
				updateLeaderstats(n)
			end
		end
	end
end)

print(("[%s] server ready"):format(Config.GameName))
