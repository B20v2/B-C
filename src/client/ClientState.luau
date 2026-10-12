--[[
	ClientState
	Holds the latest state the server sent for the local player and lets
	controllers subscribe to changes. Also tracks the client "mode":
	  "play"  - walking around your nation
	  "build" - build menu open / placing / deleting / moving
	  "war"   - strategic camera (Travel): aim weapons, command units
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local ClientState = {}

ClientState.data = {} :: { [string]: any }
ClientState.mode = "play"
ClientState.player = Players.LocalPlayer

local keyListeners: { [string]: { (any) -> () } } = {}
local anyListeners: { (patch: { [string]: any }) -> () } = {}
local modeListeners: { (string, string) -> () } = {}

local function fire(patch: { [string]: any })
	for k, v in patch do
		ClientState.data[k] = v
	end
	for k, v in patch do
		local list = keyListeners[k]
		if list then
			for _, fn in list do
				task.spawn(fn, v)
			end
		end
	end
	for _, fn in anyListeners do
		task.spawn(fn, patch)
	end
end

-- Subscribe to one key; called immediately if a value already exists.
function ClientState.on(key: string, fn: (any) -> ())
	keyListeners[key] = keyListeners[key] or {}
	table.insert(keyListeners[key], fn)
	if ClientState.data[key] ~= nil then
		task.spawn(fn, ClientState.data[key])
	end
end

-- Returns a function that unsubscribes.
function ClientState.onAny(fn: (patch: { [string]: any }) -> ()): () -> ()
	table.insert(anyListeners, fn)
	return function()
		local i = table.find(anyListeners, fn)
		if i then
			table.remove(anyListeners, i)
		end
	end
end

function ClientState.get(key: string): any
	return ClientState.data[key]
end

function ClientState.setMode(mode: string)
	local old = ClientState.mode
	if old == mode then
		return
	end
	ClientState.mode = mode
	for _, fn in modeListeners do
		task.spawn(fn, mode, old)
	end
end

function ClientState.onMode(fn: (string, string) -> ())
	table.insert(modeListeners, fn)
end

function ClientState.start()
	Net.event("State").OnClientEvent:Connect(fire)
	task.spawn(function()
		for _ = 1, 60 do
			local snap = Net.request("GetSnapshot")
			if type(snap) == "table" and snap.cash ~= nil then
				fire(snap)
				return
			end
			task.wait(1)
		end
	end)
end

return ClientState
