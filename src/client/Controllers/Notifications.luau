--[[
	Notifications
	"Comms feed": tagged messages slide in on the right (PAY, ALERT, INTEL,
	WAR, OK) and fade out. Also the floating "+$12.4k" pay-day pop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local UI = script.Parent.Parent.UI
local Lib = require(UI.Lib)
local Theme = require(UI.Theme)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New
local C = Theme.Color

local Notifications = {}

local holder: Frame
local root: GuiObject

local KINDS = {
	info = { tag = "INTEL", color = C.Info },
	good = { tag = "OK", color = C.Good },
	bad = { tag = "ALERT", color = C.Bad },
	pay = { tag = "PAY", color = C.Gold },
	war = { tag = "WAR", color = C.Military },
}

local order = 0

function Notifications.show(text: string, kind: string?)
	local k = KINDS[kind or "info"] or KINDS.info
	order += 1
	local wrap = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = -order,
		Parent = holder,
	})
	local toast = New("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Position = UDim2.fromOffset(60, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = wrap,
	}, {
		Lib.corner(4),
		Lib.stroke(C.Line, 1, 0.4),
		Lib.pad(8, 12, 9, 16),
		New("Frame", { Name = "Bar", BackgroundColor3 = k.color, BorderSizePixel = 0, Position = UDim2.new(0, -16, 0, -8), Size = UDim2.new(0, 4, 1, 17) }),
		Lib.display({ Name = "Tag", Text = k.tag, TextSize = 11, TextColor3 = k.color, Size = UDim2.new(1, 0, 0, 13) }),
		Lib.text({
			Name = "Msg",
			Text = text,
			TextSize = 14,
			FontFace = Theme.Font.BodyBold,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(0, 15),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}),
	})
	Lib.tween(toast, 0.22, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	if kind == "bad" then
		Sounds.play("Error")
	elseif kind == "good" then
		Sounds.play("Click", 1.2)
	end
	-- cap the stack
	local items = {}
	for _, c in holder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 6, #items do
		items[i]:Destroy()
	end
	task.delay(kind == "war" and 6.5 or 4.5, function()
		if toast.Parent then
			Lib.tween(toast, 0.3, { Position = UDim2.fromOffset(80, 0), BackgroundTransparency = 1 })
			for _, d in toast:GetDescendants() do
				if d:IsA("TextLabel") then
					Lib.tween(d, 0.3, { TextTransparency = 1 })
				elseif d:IsA("Frame") then
					Lib.tween(d, 0.3, { BackgroundTransparency = 1 })
				elseif d:IsA("UIStroke") then
					Lib.tween(d, 0.3, { Transparency = 1 })
				end
			end
			task.wait(0.31)
			wrap:Destroy()
		end
	end)
end

-- Floating text that rises from a screen position (pay day).
function Notifications.float(text: string, at: UDim2, color: Color3?)
	local label = Lib.display({
		Text = text,
		TextSize = 24,
		TextColor3 = color or C.Good,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at,
		Size = UDim2.fromOffset(220, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})
	Lib.tween(label, 1.5, { Position = at + UDim2.fromOffset(0, 46), TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(1.6, function()
		label:Destroy()
	end)
end

function Notifications.init(gui: GuiObject)
	root = gui
	holder = New("Frame", {
		Name = "Comms",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 196),
		Size = UDim2.fromOffset(330, 420),
		Parent = gui,
	}, { Lib.list("y", 6) })
	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		if kind == "pay" then
			Sounds.play("Pay", 1.4)
		end
		Notifications.show(text, kind)
	end)
end

return Notifications
