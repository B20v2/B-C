--[[
	Sounds
	UI and world sounds. Uses sounds that ship with the Roblox client so the
	game works out of the box; swap any id for your own uploaded audio.
]]

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.Ids = {
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Place = "rbxasset://sounds/snap.wav",
	Error = "rbxasset://sounds/clickfast.wav",
	Pay = "rbxasset://sounds/electronicpingshort.wav",
	Success = "rbxasset://sounds/victory.wav",
	Launch = "rbxasset://sounds/Rocket shot.wav",
	Whoosh = "rbxasset://sounds/swoosh.wav",
	Open = "rbxasset://sounds/button.wav",
}

local cache: { [string]: Sound } = {}

function Sounds.get(name: string): Sound
	local s = cache[name]
	if s then
		return s
	end
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.SoundId = Sounds.Ids[name] or ""
	snd.Volume = name == "Click" and 0.25 or 0.5
	snd.Parent = SoundService
	cache[name] = snd
	return snd
end

function Sounds.play(name: string, pitch: number?)
	local s = Sounds.get(name)
	s.PlaybackSpeed = pitch or 1
	s:Play()
end

-- Positional one-shot (explosions, launches).
function Sounds.at(name: string, position: Vector3, volume: number?)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = position
	holder.Parent = workspace
	local snd = Instance.new("Sound")
	snd.SoundId = Sounds.Ids[name] or ""
	snd.Volume = volume or 0.8
	snd.RollOffMaxDistance = 1500
	snd.Parent = holder
	snd:Play()
	task.delay(6, function()
		holder:Destroy()
	end)
end

return Sounds
