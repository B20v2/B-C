--[[
	Net
	Every remote the game uses is declared here. The server creates them on
	boot, the client waits for them. Using a fixed list means a typo is caught
	immediately instead of silently creating a dead remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- Client -> server requests that return a result ({ ok, err, ... }).
Net.Functions = {
	"PlaceBuilding",
	"PlaceMany",
	"DeleteBuilding",
	"MoveBuilding",
	"Undo",
	"RepairBuilding",
	"RepairAll",
	"SetFuelDestination",
	"QueueProduction",
	"CancelProduction",
	"StartResearch",
	"LaunchWeapon",
	"SetPvp",
	"CommandUnits",
	"DeployUnits",
	"RecallUnits",
	"ClaimDaily",
	"ClaimPlaytime",
	"ClaimQuest",
	"ClaimGroup",
	"RedeemCode",
	"SetBillboard",
	"SetNation",
	"GetSnapshot",
	"StudioPurchase",
}

-- Server -> client pushes.
Net.Events = {
	"State", -- partial state patch for the local player
	"Notify", -- toast message
	"Projectile", -- a missile / drone launched (all clients)
	"ProjectileEnd", -- impact or interception (all clients)
	"Effect", -- one-shot visual effect
	"PurchaseDone", -- a product / pass purchase was granted
}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	local result: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing then
			result = existing :: Folder
		else
			local f = Instance.new("Folder")
			f.Name = "Remotes"
			for _, name in Net.Functions do
				local rf = Instance.new("RemoteFunction")
				rf.Name = name
				rf.Parent = f
			end
			for _, name in Net.Events do
				local re = Instance.new("RemoteEvent")
				re.Name = name
				re.Parent = f
			end
			f.Parent = ReplicatedStorage
			result = f
		end
	else
		result = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	folder = result
	return result
end

function Net.fn(name: string): RemoteFunction
	assert(table.find(Net.Functions, name), "Unknown remote function " .. name)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Net.event(name: string): RemoteEvent
	assert(table.find(Net.Events, name), "Unknown remote event " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

-- Server helper: bind a request handler with per-player rate limiting and
-- error isolation so one bad request can never break the remote.
function Net.handle(name: string, handler: (Player, ...any) -> any, maxPerSecond: number?)
	local remote = Net.fn(name)
	local limit = maxPerSecond or 8
	local buckets: { [Player]: { t: number, n: number } } = {}
	remote.OnServerInvoke = function(player: Player, ...)
		local now = os.clock()
		local b = buckets[player]
		if not b or now - b.t >= 1 then
			b = { t = now, n = 0 }
			buckets[player] = b
		end
		b.n += 1
		if b.n > limit then
			return { ok = false, err = "Slow down!" }
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(("[Net] %s failed for %s: %s"):format(name, player.Name, tostring(result)))
			return { ok = false, err = "Something went wrong" }
		end
		return result
	end
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

-- Client helper: invoke a request safely.
function Net.request(name: string, ...): any
	local ok, result = pcall(Net.fn(name).InvokeServer, Net.fn(name), ...)
	if not ok then
		return { ok = false, err = "Connection problem" }
	end
	return result or { ok = false }
end

return Net
