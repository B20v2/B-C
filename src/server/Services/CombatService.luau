--[[
	CombatService
	Missile / drone strikes, air-defense interception, damage and PvP rules.

	A strike is resolved deterministically at launch: the server picks the
	launcher, rolls every air defense covering the target, and broadcasts one
	"Projectile" event with the full flight description. All clients animate
	the same flight (Ballistics module) and the server applies the result
	when the flight time elapses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Unlocks = require(Shared.Util.Unlocks)
local Weapons = require(Shared.Catalog.Weapons)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation
type BRuntime = Nations.BRuntime

local CombatService = {}
local S: { [string]: any }
local nextId = 0

local function flatDist(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

function CombatService.isShielded(n: Nation): boolean
	return os.time() < n.shieldUntil
end

-- Launchers of a family: total, ready count, the first ready one, next ready time.
function CombatService.launcherState(n: Nation, family: string, now: number): (number, number, BRuntime?, number)
	local total, ready, first, nextReady = 0, 0, nil, math.huge
	for _, b in n.buildings do
		if b.def.launcher == family and Nations.isActive(b) then
			total += 1
			if b.reloadUntil <= now then
				ready += 1
				first = first or b
			else
				nextReady = math.min(nextReady, b.reloadUntil)
			end
		end
	end
	return total, ready, first, nextReady
end

local function radarBonus(n: Nation): number
	for _, b in n.buildings do
		if b.def.radar and Nations.isActive(b) then
			return b.def.radar
		end
	end
	return 0
end

-- Air defenses (buildings of `defender`) that can engage a strike on `target`.
local function defensesFor(defender: Nation, target: Vector3, arrival: number): { BRuntime }
	local out = {}
	local bonus = 1 + radarBonus(defender)
	for _, b in defender.buildings do
		local ad = b.def.airDefense
		if ad and Nations.isActive(b) and b.eff > 0.3 and b.reloadUntil <= arrival then
			local pos = S.BuildService.worldCFrame(defender, b).Position
			if flatDist(pos, target) <= ad.range * bonus then
				table.insert(out, b)
			end
		end
	end
	table.sort(out, function(a, c)
		return a.def.airDefense.chance > c.def.airDefense.chance
	end)
	return out
end

local function classifyTarget(attacker: Nation, target: Vector3): (string?, Nation?, string?)
	if S.UnitService.inMainland(target) then
		return "mainland", nil, nil
	end
	local owner = S.PlotService.ownerAt(target)
	if not owner then
		return nil, nil, "Pick a target on the mainland or an enemy nation"
	end
	if owner == attacker.player then
		return nil, nil, "You can't strike your own nation"
	end
	local defender = Nations.get(owner)
	if not defender or not defender.ready then
		return nil, nil, "That nation isn't ready"
	end
	if not attacker.data.Pvp then
		return nil, nil, "Turn PvP ON to attack other nations"
	end
	if not defender.data.Pvp then
		return nil, nil, owner.DisplayName .. " has PvP OFF"
	end
	if CombatService.isShielded(defender) then
		return nil, nil, owner.DisplayName .. " is protected by the new-nation shield"
	end
	return "nation", defender, nil
end

local function impact(attacker: Nation, weapon, target: Vector3, defender: Nation?, kind: string): (number, number)
	local dealtTotal, value = 0, 0
	local cluster = weapon.id == "CLUSTER"
	local function falloff(d: number): number
		if cluster then
			return 1
		end
		return 1 - 0.5 * math.clamp(d / weapon.radius, 0, 1)
	end

	if kind == "nation" and defender then
		local damagedNames = {}
		for _, b in defender.buildings do
			local center = S.BuildService.worldCFrame(defender, b).Position
			local halfSize = math.min(b.def.size[1], b.def.size[2]) * Config.CellSize / 2
			local d = math.max(0, flatDist(center, target) - halfSize)
			if d <= weapon.radius then
				local wasDamaged = b.damaged
				local dealt = S.BuildService.damage(defender, b, weapon.damage * falloff(d))
				if dealt > 0 then
					dealtTotal += dealt
					value += b.def.cost * (dealt / b.def.hp)
					if b.damaged and not wasDamaged then
						table.insert(damagedNames, b.def.name)
					end
				end
			end
		end
		for _, u in S.UnitService.unitsNear(target, weapon.radius, attacker.userId) do
			if u.n == defender then
				dealtTotal += weapon.damage
				S.UnitService.damage(u, weapon.damage, attacker)
			end
		end
		if dealtTotal > 0 then
			local msg = ("%s's %s hit your nation"):format(attacker.player.DisplayName, weapon.short)
			if #damagedNames > 0 then
				msg ..= (" — %s knocked out"):format(table.concat(damagedNames, ", ", 1, math.min(3, #damagedNames)))
			end
			Nations.notify(defender.player, msg, "bad")
		end
	else
		for _, u in S.UnitService.unitsNear(target, weapon.radius, attacker.userId) do
			dealtTotal += weapon.damage
			S.UnitService.damage(u, weapon.damage * falloff(flatDist(u.root.CFrame.Position, target)), attacker)
		end
		S.FobService.damageNear(target, weapon.radius, weapon.damage * 2, attacker)
		local point = S.ConquestService.pointNear(target, weapon.radius)
		if point then
			-- warheads are very effective against garrisons
			dealtTotal += S.ConquestService.damageGarrison(point, weapon.damage * 2.5, attacker)
		end
	end
	return dealtTotal, value
end

local function launch(attacker: Nation, weaponId: string, target: Vector3): (boolean, string?)
	local weapon = Weapons.get(weaponId)
	if not weapon then
		return false, "Unknown weapon"
	end
	local ok, reason = Unlocks.check(weapon, S.BuildService.access(attacker))
	if not ok then
		return false, reason
	end
	local stock = attacker.data.Inventory[weaponId] or 0
	if stock <= 0 then
		return false, "No " .. weapon.short .. " in stock - build some in a military factory"
	end
	local now = Nations.now()
	local total, _, launcher, nextReady = CombatService.launcherState(attacker, weapon.family, now)
	if total == 0 then
		return false, "Build a launcher for " .. weapon.short
	end
	if not launcher then
		return false, ("All %s launchers reloading (%ds)"):format(weapon.short, math.ceil(nextReady - now))
	end
	local kind, defender, err = classifyTarget(attacker, target)
	if not kind then
		return false, err
	end

	-- commit
	attacker.data.Inventory[weaponId] = stock - 1
	launcher.reloadUntil = now + (launcher.def.reload or 20)
	if launcher.model then
		launcher.model:SetAttribute("ReloadUntil", launcher.reloadUntil)
	end
	attacker.data.Stats.Launches += 1
	if kind == "nation" then
		attacker.pvpLockUntil = now + Config.PvpToggleCooldown
		attacker.shieldUntil = 0 -- attacking ends your own new-nation shield
	end

	local from = S.BuildService.worldCFrame(attacker, launcher).Position + Vector3.new(0, 8, 0)
	local target0 = Vector3.new(target.X, 0, target.Z)
	local dist = flatDist(from, target0)
	local flight = weapon.flight * math.clamp(dist / 1600, 0.7, 1.5)
	local apex = weapon.apex * math.clamp(dist / 1600, 0.6, 1.4)
	if weapon.apex < 60 then
		apex = weapon.apex
	end

	-- interception
	local interceptAt: number? = nil
	local interceptFrom: Vector3? = nil
	local interceptorName: string? = nil
	local arrival = now + flight * Config.InterceptAt
	if defender then
		for _, ad in defensesFor(defender, target0, arrival) do
			ad.reloadUntil = arrival + ad.def.airDefense.reload
			if math.random() < ad.def.airDefense.chance * weapon.interceptMod then
				interceptAt = Config.InterceptAt
				interceptFrom = S.BuildService.worldCFrame(defender, ad).Position + Vector3.new(0, 5, 0)
				interceptorName = ad.def.name
				break
			end
		end
	else
		for _, u in S.UnitService.unitsNear(target0, 140, attacker.userId) do
			if u.def.antiAir and math.random() < u.def.antiAir * weapon.interceptMod then
				interceptAt = Config.InterceptAt
				interceptFrom = u.root.CFrame.Position + Vector3.new(0, 3, 0)
				interceptorName = u.def.name
				break
			end
		end
	end

	nextId += 1
	local id = nextId
	Net.event("Projectile"):FireAllClients({
		id = id,
		w = weaponId,
		from = from,
		to = target0,
		t0 = now,
		flight = flight,
		apex = apex,
		kind = weapon.kind,
		ic = interceptAt,
		icFrom = interceptFrom,
		owner = attacker.userId,
	})

	local resolveIn = flight * (interceptAt or 1)
	task.delay(resolveIn, function()
		if interceptAt then
			Net.event("ProjectileEnd"):FireAllClients({ id = id, intercepted = true })
			if attacker.player.Parent then
				Nations.notify(attacker.player, ("Your %s was intercepted by a %s"):format(weapon.short, interceptorName or "defense"), "bad")
			end
			if defender and defender.player.Parent then
				Nations.notify(defender.player, ("Your %s intercepted %s's %s"):format(interceptorName or "defense", attacker.player.DisplayName, weapon.short), "good")
			end
			return
		end
		local stillDefender = defender
		if defender and not defender.player.Parent then
			stillDefender = nil
		end
		local dealt, value = 0, 0
		if attacker.player.Parent then
			dealt, value = impact(attacker, weapon, target0, stillDefender, kind)
		end
		Net.event("ProjectileEnd"):FireAllClients({ id = id, intercepted = false, hit = dealt > 0, pos = target0, w = weaponId })
		if dealt > 0 and attacker.player.Parent then
			attacker.data.Stats.Hits += 1
			local loot = math.floor(value * Config.StrikeLootRate)
			attacker.data.Cash += loot
			Nations.notify(attacker.player, ("Direct hit!%s"):format(loot > 0 and (" +" .. Format.cash(loot) .. " war spoils") or ""), "good")
			S.StateService.push(attacker)
		end
	end)
	return true, nil
end

local function onLaunch(player: Player, weaponId: any, target: any)
	local n = Nations.get(player)
	if not n or not n.ready or typeof(weaponId) ~= "string" or typeof(target) ~= "Vector3" then
		return { ok = false, err = "Invalid request" }
	end
	if target.X ~= target.X or math.abs(target.X) > 1e5 or math.abs(target.Z) > 1e5 then
		return { ok = false, err = "Invalid target" }
	end
	local ok, err = launch(n, weaponId, target)
	S.StateService.push(n)
	return { ok = ok, err = err }
end

local function onSetPvp(player: Player, on: any)
	local n = Nations.get(player)
	if not n or typeof(on) ~= "boolean" then
		return { ok = false }
	end
	if not on and Nations.now() < n.pvpLockUntil then
		return { ok = false, err = ("You attacked recently. PvP stays ON for %ds"):format(math.ceil(n.pvpLockUntil - Nations.now())) }
	end
	n.data.Pvp = on
	player:SetAttribute("Pvp", on)
	S.StateService.push(n)
	return { ok = true }
end

function CombatService.init(services)
	S = services
end

function CombatService.start()
	Net.handle("LaunchWeapon", onLaunch, 6)
	Net.handle("SetPvp", onSetPvp, 2)
end

return CombatService
