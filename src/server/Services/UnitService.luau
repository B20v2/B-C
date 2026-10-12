--[[
	UnitService
	Ground vehicles. Units are physics assemblies driven by AlignPosition /
	AlignOrientation (server-owned) so they glide smoothly on every client.
	They roll out at home, deploy to the mainland staging area through the
	"tunnel", move in formation and fight automatically on the mainland.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Grid = require(Shared.Util.Grid)
local Net = require(Shared.Net)
local Units = require(Shared.Catalog.Units)
local ModelBuilder = require(Shared.ModelBuilder)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

export type Unit = {
	uid: number,
	id: string,
	def: any,
	n: Nation,
	hp: number,
	model: Model,
	root: BasePart,
	align: AlignPosition,
	orient: AlignOrientation,
	location: string, -- "home" | "mainland"
	height: number,
	lastShot: number,
}

local UnitService = {}
local S: { [string]: any }
local folder: Folder
local all: { [Unit]: boolean } = {}

local HALF = Config.MainlandSize / 2

function UnitService.inMainland(pos: Vector3): boolean
	local d = pos - Config.MainlandOrigin
	return math.abs(d.X) <= HALF and math.abs(d.Z) <= HALF
end

function UnitService.stagingPos(n: Nation): Vector3
	return Config.MainlandOrigin + Vector3.new(-1050 + (n.plotIndex - 1) * 300, 0, HALF - 110)
end

function UnitService.cap(n: Nation): number
	local cap = 10 + (n.stats.depotCap or 0)
	if n.passes.VIP then
		cap += 10
	end
	if n.passes.ExtraQueue then
		cap += 20
	end
	return math.min(cap, Config.MaxUnitsPerPlayer + 20)
end

function UnitService.count(n: Nation): number
	local c = 0
	for _ in n.units do
		c += 1
	end
	return c
end

function UnitService.canAdd(n: Nation): boolean
	return UnitService.count(n) < UnitService.cap(n)
end

local function homePos(n: Nation, near: any?): Vector3
	local anchor: Vector3? = nil
	for _, b in n.buildings do
		if b.def.depot and Nations.isActive(b) then
			anchor = S.BuildService.worldCFrame(n, b).Position
			break
		end
	end
	if not anchor and near then
		anchor = S.BuildService.worldCFrame(n, near).Position
	end
	local base = anchor or (n.origin + Vector3.new(0, 0, Grid.PlotSize / 2 - 30))
	local rng = Random.new()
	local p = base + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-18, 18))
	-- keep inside the plot
	local half = Grid.PlotSize / 2 - 6
	local d = p - n.origin
	return n.origin + Vector3.new(math.clamp(d.X, -half, half), 0, math.clamp(d.Z, -half, half))
end

local function setTarget(u: Unit, pos: Vector3)
	local current = u.root.CFrame.Position
	local target = Vector3.new(pos.X, u.height, pos.Z)
	u.align.Position = target
	local flatDir = Vector3.new(target.X - current.X, 0, target.Z - current.Z)
	if flatDir.Magnitude > 1 then
		u.orient.CFrame = CFrame.lookAt(Vector3.zero, flatDir.Unit)
	end
	u.model:SetAttribute("Moving", true)
end

local function teleport(u: Unit, pos: Vector3)
	local cf = CFrame.new(pos.X, u.height, pos.Z) * u.root.CFrame.Rotation
	u.model:PivotTo(cf)
	u.root.AssemblyLinearVelocity = Vector3.zero
	u.align.Position = cf.Position
end

function UnitService.spawn(n: Nation, id: string, hp: number?, near: any?, uid: number?): Unit?
	local def = Units.get(id)
	if not def then
		return nil
	end
	local model = ModelBuilder.unit(def)
	local root = model.PrimaryPart :: BasePart
	local height = root.Size.Y / 2
	-- weld everything to the root and make it a physics assembly
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			if p ~= root then
				p.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	local att = Instance.new("Attachment")
	att.Name = "Drive"
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxForce = 1e7
	align.MaxVelocity = def.speed
	align.Responsiveness = 30
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = att
	orient.MaxTorque = 1e7
	orient.Responsiveness = 18
	orient.Parent = root

	local unitUid = uid or n.nextUnitUid
	if unitUid >= n.nextUnitUid then
		n.nextUnitUid = unitUid + 1
	end
	model.Name = def.name
	model:SetAttribute("Unit", true)
	model:SetAttribute("UnitId", def.id)
	model:SetAttribute("Uid", unitUid)
	model:SetAttribute("OwnerId", n.userId)
	model:SetAttribute("OwnerName", n.player.DisplayName)
	model:SetAttribute("Hp", hp or def.hp)
	model:SetAttribute("MaxHp", def.hp)
	model:SetAttribute("Color", Config.NationColors[n.plotIndex] or Color3.new(1, 1, 1))

	local pos = homePos(n, near)
	model:PivotTo(CFrame.new(pos.X, height, pos.Z))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	align.Position = Vector3.new(pos.X, height, pos.Z)
	orient.CFrame = CFrame.new()
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local u: Unit = {
		uid = unitUid,
		id = id,
		def = def,
		n = n,
		hp = hp or def.hp,
		model = model,
		root = root,
		align = align,
		orient = orient,
		location = "home",
		height = height,
		lastShot = 0,
	}
	n.units[unitUid] = u
	all[u] = true
	return u
end

function UnitService.remove(u: Unit, exploded: boolean?)
	all[u] = nil
	u.n.units[u.uid] = nil
	if exploded then
		Net.event("Effect"):FireAllClients("Explosion", u.root.CFrame.Position, 1)
	end
	u.model:Destroy()
end

-- Returns true if destroyed.
function UnitService.damage(u: Unit, amount: number, attacker: Nation?): boolean
	if not all[u] then
		return false
	end
	u.hp -= amount
	u.model:SetAttribute("Hp", math.max(0, math.floor(u.hp)))
	if u.hp <= 0 then
		Nations.notify(u.n.player, ("Your %s was destroyed"):format(u.def.name), "bad")
		if attacker then
			attacker.data.Stats.Kills += 1
		end
		UnitService.remove(u, true)
		return true
	end
	return false
end

function UnitService.unitsNear(pos: Vector3, radius: number, excludeUserId: number?): { Unit }
	local out = {}
	for u in all do
		if u.n.userId ~= excludeUserId then
			local p = u.root.CFrame.Position
			local d = Vector2.new(p.X - pos.X, p.Z - pos.Z).Magnitude
			if d <= radius then
				table.insert(out, u)
			end
		end
	end
	return out
end

function UnitService.mainlandUnits(): { Unit }
	local out = {}
	for u in all do
		if u.location == "mainland" then
			table.insert(out, u)
		end
	end
	return out
end

function UnitService.loadNation(n: Nation)
	for _, s in n.data.Units do
		if UnitService.count(n) >= Config.MaxUnitsPerPlayer + 20 then
			break
		end
		UnitService.spawn(n, s.id, s.hp, nil, s.u)
	end
end

function UnitService.serialize(n: Nation)
	local out = {}
	for _, u in n.units do
		table.insert(out, { u = u.uid, id = u.id, hp = math.floor(u.hp) })
	end
	n.data.Units = out
end

function UnitService.clearNation(n: Nation)
	for _, u in n.units do
		UnitService.remove(u, false)
	end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function collect(n: Nation, uids: any, filter: ((Unit) -> boolean)?): { Unit }
	local out = {}
	if typeof(uids) == "table" then
		for i, uid in uids do
			if i > 100 then
				break
			end
			local u = typeof(uid) == "number" and n.units[uid] or nil
			if u and (not filter or filter(u)) then
				table.insert(out, u)
			end
		end
	else
		for _, u in n.units do
			if not filter or filter(u) then
				table.insert(out, u)
			end
		end
	end
	return out
end

local function deploy(n: Nation, u: Unit)
	local staging = UnitService.stagingPos(n)
	local rng = Random.new()
	teleport(u, staging + Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-20, 20)))
	u.location = "mainland"
	u.model:SetAttribute("Location", "mainland")
end

local function recall(n: Nation, u: Unit)
	teleport(u, homePos(n))
	u.location = "home"
	u.model:SetAttribute("Location", "home")
end

local function onCommand(player: Player, uids: any, target: any)
	local n = Nations.get(player)
	if not n or typeof(target) ~= "Vector3" then
		return { ok = false, err = "Invalid request" }
	end
	local units = collect(n, uids)
	if #units == 0 then
		return { ok = false, err = "Select units first" }
	end
	local toMainland = UnitService.inMainland(target)
	local toHome = Grid.insidePlot(n.origin, target, 0)
	if not toMainland and not toHome then
		return { ok = false, err = "Units can only move on your land or the mainland" }
	end
	-- simple square formation around the target
	local cols = math.ceil(math.sqrt(#units))
	local spacing = 11
	for i, u in units do
		if toMainland and u.location ~= "mainland" then
			deploy(n, u)
		elseif toHome and u.location == "mainland" then
			recall(n, u)
		end
		local row = (i - 1) // cols
		local col = (i - 1) % cols
		local offset = Vector3.new((col - (cols - 1) / 2) * spacing, 0, (row - (cols - 1) / 2) * spacing)
		setTarget(u, target + offset)
	end
	return { ok = true, count = #units }
end

local function onDeploy(player: Player, uids: any)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local units = collect(n, uids, function(u)
		return u.location ~= "mainland"
	end)
	for _, u in units do
		deploy(n, u)
	end
	if #units > 0 then
		Nations.notify(player, ("%d units drove through the tunnel to the mainland"):format(#units), "good")
	end
	return { ok = #units > 0, count = #units, err = #units == 0 and "No units at home" or nil }
end

local function onRecall(player: Player, uids: any)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local units = collect(n, uids, function(u)
		return u.location ~= "home"
	end)
	for _, u in units do
		recall(n, u)
	end
	return { ok = #units > 0, count = #units, err = #units == 0 and "No units on the mainland" or nil }
end

---------------------------------------------------------------------------
-- Combat loop (mainland only)
---------------------------------------------------------------------------
local STEP = 0.5

local function combatStep()
	local now = os.clock()
	local units = UnitService.mainlandUnits()
	for _, u in units do
		if all[u] then
			-- arrival
			if u.model:GetAttribute("Moving") then
				local d = (u.align.Position - u.root.CFrame.Position) * Vector3.new(1, 0, 1)
				if d.Magnitude < 2 then
					u.model:SetAttribute("Moving", nil)
				end
			end
			if u.def.dps > 0 then
				local pos = u.root.CFrame.Position
				local best, bestD = nil, u.def.range
				for _, other in units do
					if other.n ~= u.n and all[other] then
						local d = (other.root.CFrame.Position - pos).Magnitude
						if d <= bestD then
							best, bestD = other, d
						end
					end
				end
				if best then
					if now - u.lastShot > 1 then
						u.lastShot = now
						Net.event("Effect"):FireAllClients("Shot", pos + Vector3.new(0, 2, 0), best.root.CFrame.Position, u.def.range > 150)
					end
					UnitService.damage(best, u.def.dps * STEP, u.n)
				else
					local point = S.ConquestService.enemyPointInRange(pos, u.def.range, u.n.userId)
					if point then
						if now - u.lastShot > 1.2 then
							u.lastShot = now
							Net.event("Effect"):FireAllClients("Shot", pos + Vector3.new(0, 2, 0), point.center + Vector3.new(0, 4, 0), u.def.range > 150)
						end
						S.ConquestService.damageGarrison(point, u.def.dps * STEP, u.n)
					end
				end
			end
		end
	end
end

-- exposed for automated tests
UnitService._combatStep = combatStep

function UnitService.init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Units"
	folder.Parent = workspace
end

function UnitService.start()
	Net.handle("CommandUnits", onCommand, 6)
	Net.handle("DeployUnits", onDeploy, 3)
	Net.handle("RecallUnits", onRecall, 3)
	task.spawn(function()
		while true do
			task.wait(STEP)
			local ok, err = pcall(combatStep)
			if not ok then
				warn("[Units] combat step failed: " .. tostring(err))
			end
		end
	end)
end

return UnitService
