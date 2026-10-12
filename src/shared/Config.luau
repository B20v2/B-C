--[[
	Config
	Global tuning for Forge & Frontline. Every balance number that is not tied
	to a single building / weapon / unit lives here so the game can be tuned
	from one place.
]]

local Config = {}

Config.GameName = "Forge & Frontline"
Config.DataStoreName = "FF_PlayerData_v1"
Config.DataVersion = 1

-- Set to true while testing in Studio: game passes count as owned and
-- developer products are granted without a real purchase.
Config.StudioFreePurchases = true

-- Roblox group that gives the "Join group" bonus. 0 disables the reward.
Config.GroupId = 0

---------------------------------------------------------------------------
-- World / grid
---------------------------------------------------------------------------
Config.CellSize = 4 -- studs per grid cell
Config.PlotCells = 100 -- plot is PlotCells x PlotCells cells (400 x 400 studs)
Config.PlotGap = 140 -- sand + sea between plots
Config.MaxPlots = 8
Config.PlotRowLength = 4
Config.HomelandOrigin = Vector3.new(0, 0, 0)
Config.MainlandOrigin = Vector3.new(0, 0, 3200)
Config.MainlandSize = 2400

---------------------------------------------------------------------------
-- Economy
---------------------------------------------------------------------------
Config.StartCash = 60000
Config.PayInterval = 60 -- seconds between pay days
Config.TaxPerCitizen = 15 -- $ per citizen per pay at 100% tax efficiency
Config.UpkeepRate = 0.0025 -- fraction of build cost charged every pay day
Config.SellRefund = 0.5 -- refund when deleting a finished building
Config.RepairCostRate = 0.25 -- fraction of build cost to repair a damaged building
Config.BaseResourceCap = 2000 -- oil / steel stored nationally before tanks & warehouses
Config.PopulationGrowth = 0.012 -- fraction of free housing filled each second
Config.PopulationMinGrowth = 1
Config.HappinessBase = 50
Config.OfflineEarningsHours = 2 -- max hours of offline pay
Config.OfflineEarningsRate = 0.3 -- 30% of pay while away (VIP doubles)
Config.PremiumIncomeBonus = 0.1 -- Roblox Premium members earn +10%

---------------------------------------------------------------------------
-- Construction / logistics
---------------------------------------------------------------------------
Config.TruckCapacity = 250
Config.TruckSpeed = 28 -- studs per second
Config.UndoWindow = 45 -- seconds an action can be undone for a full refund
Config.MaxQueuePerFactory = 5

---------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------
Config.PvpToggleCooldown = 180 -- after attacking you must wait before going PvP OFF
Config.NewPlayerShield = 20 * 60 -- seconds of protection for brand new nations
Config.StrikeLootRate = 0.03 -- attacker earns this fraction of the value they damage
Config.InterceptAt = 0.72 -- fraction of a flight at which interceptions happen

---------------------------------------------------------------------------
-- Conquest
---------------------------------------------------------------------------
Config.CaptureRadius = 70
Config.CaptureTime = 100 -- capture points needed (units add their capture power per second)
Config.GarrisonRegen = 4 -- garrison HP regenerated per second
Config.MaxUnitsPerPlayer = 40

-- Colour used for each plot slot's nation on the war map.
Config.NationColors = {
	Color3.fromRGB(64, 140, 230),
	Color3.fromRGB(226, 84, 74),
	Color3.fromRGB(80, 184, 96),
	Color3.fromRGB(236, 170, 40),
	Color3.fromRGB(150, 96, 216),
	Color3.fromRGB(40, 190, 196),
	Color3.fromRGB(236, 116, 180),
	Color3.fromRGB(150, 150, 150),
}

---------------------------------------------------------------------------
-- Rewards / retention
---------------------------------------------------------------------------
Config.DailyRewards = { 5000, 10000, 20000, 35000, 50000, 75000, 150000 }
Config.PlaytimeGiftInterval = 10 * 60
Config.PlaytimeGiftPays = 1.5 -- gift = 1.5 pay days of income (min 5k)
Config.GroupRewardCash = 25000

Config.Codes = {
	FORGE = 25000,
	FRONTLINE = 50000,
	RELEASE = 100000,
}

---------------------------------------------------------------------------
-- Nation identity, ranks and world
---------------------------------------------------------------------------
Config.NationNameMin = 3
Config.NationNameMax = 20

-- Power = population + building value / 100 + techs * 150 + vehicles * 80
-- + strategic points * 600. Crossing a threshold pays the reward once.
Config.Ranks = {
	{ name = "Outpost", power = 0, reward = 0 },
	{ name = "Township", power = 500, reward = 10000 },
	{ name = "City-State", power = 2500, reward = 30000 },
	{ name = "Republic", power = 10000, reward = 80000 },
	{ name = "Federation", power = 40000, reward = 200000 },
	{ name = "Superpower", power = 150000, reward = 500000 },
}

Config.DayLength = 16 * 60 -- seconds for a full day + night
Config.NightShare = 0.3 -- fraction of the cycle spent at night

return Config
