--[[
	Notifications
	Toast stack (top center) for server messages, plus the floating
	"+$12.4k" pay-day pop over the cash pill.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local UI = script.Parent.Parent.UI
local Lib = require(UI.Lib)
local Theme = require(UI.Theme)
local Sounds = require(script.Parent.Sounds)

local New = Lib.New

local Notifications = {}

local holder: Frame
local KIND_COLORS = {
	info = Theme.Color.Accent,
	good = Theme.Color.Good,
	bad = Theme.Color.Bad,
	pay = Theme.Color.Good,
	war = Theme.Color.Military,
}

local order = 0

function Notifications.show(text: string, kind: string?)
	local k = kind or "info"
	order += 1
	local accent = KIND_COLORS[k] or Theme.Color.Accent
	local toast = New("Frame", {
		BackgroundColor3 = Theme.Color.Card,
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = -order,
		Parent = holder,
	}, {
		Lib.corner(8),
		Lib.stroke(Theme.Color.CardStroke, 1, 1),
		Lib.pad(0, 16, 0, 14),
		Lib.list("x", 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		New("Frame", {
			Name = "Dot",
			BackgroundColor3 = accent,
			Size = UDim2.fromOffset(8, 8),
			BackgroundTransparency = 1,
		}, { Lib.round() }),
		Lib.text({
			Name = "Label",
			Text = text,
			FontFace = Theme.Font.Semi,
			TextSize = Theme.TextSize.Body,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextTruncate = Enum.TextTruncate.None,
			TextTransparency = 1,
		}),
	})
	local stroke = toast:FindFirstChildOfClass("UIStroke") :: UIStroke
	local dot = toast:FindFirstChild("Dot") :: Frame
	local label = toast:FindFirstChild("Label") :: TextLabel
	Lib.tween(toast, 0.15, { BackgroundTransparency = 0.04 })
	Lib.tween(stroke, 0.15, { Transparency = 0 })
	Lib.tween(dot, 0.15, { BackgroundTransparency = 0 })
	Lib.tween(label, 0.15, { TextTransparency = 0 })
	if k == "bad" then
		Sounds.play("Error")
	elseif k == "good" then
		Sounds.play("Click", 1.2)
	end
	-- keep at most 5 toasts
	local toasts = {}
	for _, c in holder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(toasts, c)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 6, #toasts do
		toasts[i]:Destroy()
	end
	task.delay(k == "war" and 6 or 4, function()
		if toast.Parent then
			Lib.tween(toast, 0.25, { BackgroundTransparency = 1 })
			Lib.tween(stroke, 0.25, { Transparency = 1 })
			Lib.tween(dot, 0.25, { BackgroundTransparency = 1 })
			Lib.tween(label, 0.25, { TextTransparency = 1 })
			task.wait(0.26)
			toast:Destroy()
		end
	end)
end

-- Floating text that rises from a screen position (pay day).
function Notifications.float(text: string, at: UDim2, color: Color3?)
	local label = Lib.text({
		Text = text,
		FontFace = Theme.Font.Bold,
		TextSize = 22,
		TextColor3 = color or Color3.fromRGB(120, 230, 140),
		TextStrokeTransparency = 0.6,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = at,
		Size = UDim2.fromOffset(200, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = holder.Parent,
	})
	Lib.tween(label, 1.4, { Position = at - UDim2.fromOffset(0, 50), TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(1.5, function()
		label:Destroy()
	end)
end

function Notifications.init(gui: GuiObject)
	holder = New("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 126),
		Size = UDim2.fromOffset(700, 260),
		Parent = gui,
	}, { Lib.list("y", 6, Enum.HorizontalAlignment.Center) })
	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		if kind == "pay" then
			Sounds.play("Pay", 1.4)
		end
		Notifications.show(text, kind)
	end)
end

return Notifications
