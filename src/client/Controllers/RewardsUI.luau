--[[
	RewardsUI
	Rewards hub with three tabs: DAILY (7-day streak calendar), GIFT
	(playtime gift with countdown) and CODES (codes + group reward), plus the
	welcome-back screen that shows offline earnings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
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
local C = Theme.Color

local RewardsUI = {}

local function daily(parent: Instance)
	local d = ClientState.get("daily") or { streak = 0, canClaim = false, next = 1, reward = 0 }
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), Parent = parent }, { Lib.list("x", 8) })
	local n = #Config.DailyRewards
	local nextDay = ((d.next - 1) % n) + 1
	local currentDay = ((math.max(d.streak, 1) - 1) % n) + 1
	for i, base in Config.DailyRewards do
		local isNext = d.canClaim and i == nextDay
		local claimed = (not d.canClaim and i <= currentDay and d.streak > 0) or (d.canClaim and i < nextDay)
		local card = Lib.card({
			Name = "Day" .. i,
			Size = UDim2.new(1 / n, -7, 1, 0),
			BackgroundColor3 = isNext and C.AccentSoft or (claimed and C.GoodSoft or C.Raised),
			LayoutOrder = i,
			Parent = row,
		}, { Lib.pad(10, 8) })
		if isNext then
			Lib.brackets(card, C.Accent, 8, 2, 3)
		end
		Lib.display({ Text = ("DAY %d"):format(i), TextSize = 13, TextColor3 = isNext and C.Accent or C.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Parent = card })
		local gift = Icons.gift(44, i == n and C.Gold or (claimed and C.Good or C.Military))
		gift.AnchorPoint = Vector2.new(0.5, 0)
		gift.Position = UDim2.new(0.5, 0, 0, 30)
		gift.Parent = card
		Lib.display({
			Text = (isNext and Format.cash(d.reward)) or (Format.cash(base) .. "+"),
			TextSize = 14,
			TextColor3 = C.Good,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 92),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = card,
		})
		Lib.display({
			Text = claimed and "CLAIMED" or (isNext and "TODAY" or "LOCKED"),
			TextSize = 10,
			TextColor3 = claimed and C.Good or (isNext and C.Accent or C.Faint),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 118),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = card,
		})
	end
	Lib.button({
		Name = "ClaimDaily",
		Variant = d.canClaim and "primary" or "ghost",
		Text = d.canClaim and ("CLAIM " .. Format.cash(d.reward)) or "COME BACK TOMORROW",
		TextSize = 15,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 184),
		Size = UDim2.fromOffset(300, 46),
		Parent = parent,
		Activated = function()
			local res = Net.request("ClaimDaily")
			if res.ok then
				Sounds.play("Success")
				Modal.close()
			elseif res.err then
				Notifications.show(res.err, "info")
			end
		end,
	})
	Lib.text({
		Text = ("Streak: %d day%s · rewards grow with your income · missing a day resets the streak"):format(d.streak, d.streak == 1 and "" or "s"),
		TextColor3 = C.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 238),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = parent,
	})
end

local function gift(parent: Instance): () -> ()
	local box = Lib.card({ Size = UDim2.new(1, 0, 0, 220), Parent = parent }, { Lib.pad(18) })
	local ic = Icons.gift(76, C.Premium)
	ic.Position = UDim2.fromOffset(6, 10)
	ic.Parent = box
	Lib.display({ Text = "PLAYTIME GIFT", TextSize = 22, Position = UDim2.fromOffset(110, 6), Size = UDim2.new(1, -110, 0, 26), Parent = box })
	Lib.text({ Text = "Every 10 minutes you play, a supply crate worth 1.5 pay days arrives.", TextSize = 13, TextColor3 = C.TextSoft, TextWrapped = true, Position = UDim2.fromOffset(110, 34), Size = UDim2.new(1, -110, 0, 36), Parent = box })
	local value = Lib.display({ Text = "", TextSize = 28, TextColor3 = C.Good, Position = UDim2.fromOffset(110, 74), Size = UDim2.new(1, -110, 0, 32), Parent = box })
	local timer = Lib.text({ Text = "", FontFace = Theme.Font.Mono, TextSize = 14, TextColor3 = C.Accent, Position = UDim2.fromOffset(110, 108), Size = UDim2.new(1, -110, 0, 18), Parent = box })
	local claim = Lib.button({
		Name = "ClaimGift",
		Variant = "primary",
		Text = "OPEN CRATE",
		TextSize = 15,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 110, 1, 0),
		Size = UDim2.fromOffset(240, 44),
		Parent = box,
		Activated = function()
			local res = Net.request("ClaimPlaytime")
			if res.ok then
				Sounds.play("Success")
			elseif res.err then
				Notifications.show(res.err, "info")
			end
		end,
	})
	return function()
		local d = ClientState.data
		local left = (d.giftAt or 0) - Lib.serverNow()
		value.Text = "+" .. Format.cash(d.giftReward or 0)
		timer.Text = left > 0 and ("NEXT CRATE IN " .. Format.clock(left)) or "READY TO OPEN"
		claim.Text = left > 0 and "NOT READY" or "OPEN CRATE"
		Lib.setButtonColor(claim, left > 0 and C.Raised or C.Accent)
		claim.TextColor3 = left > 0 and C.Muted or C.OnAccent
	end
end

local function codes(parent: Instance)
	Lib.caption("Redeem a code", { Parent = parent })
	local box = Lib.textbox({ Name = "CodeBox", PlaceholderText = "ENTER CODE", FontFace = Theme.Font.Display, TextSize = 20, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, -170, 0, 48), Parent = parent })
	Lib.button({
		Name = "Redeem",
		Variant = "primary",
		Text = "REDEEM",
		TextSize = 15,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 20),
		Size = UDim2.fromOffset(160, 48),
		Parent = parent,
		Activated = function()
			local res = Net.request("RedeemCode", box.Text)
			if res.ok then
				Sounds.play("Success")
				box.Text = ""
			elseif res.err then
				Notifications.show(res.err, "bad")
			end
		end,
	})
	local group = Lib.card({ Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 100), Parent = parent }, { Lib.pad(14) })
	local claimed = ClientState.get("groupClaimed") == true
	local hasGroup = (ClientState.get("groupId") or 0) ~= 0
	Lib.display({ Text = "JOIN THE GROUP", TextSize = 17, Size = UDim2.new(1, -170, 0, 22), Parent = group })
	Lib.text({
		Text = hasGroup and ("Join our Roblox group for a free %s and update news."):format(Format.cash(Config.GroupRewardCash)) or "No group reward is set up yet.",
		TextSize = 13,
		TextColor3 = C.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, -170, 0, 40),
		Parent = group,
	})
	Lib.button({
		Name = "ClaimGroup",
		Variant = claimed and "good" or (hasGroup and "primary" or "ghost"),
		Text = claimed and "CLAIMED" or "CLAIM",
		TextSize = 14,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(150, 42),
		Parent = group,
		Activated = function()
			if claimed or not hasGroup then
				return
			end
			local res = Net.request("ClaimGroup")
			if res.ok then
				Sounds.play("Success")
				Modal.close()
			elseif res.err then
				Notifications.show(res.err, "info")
			end
		end,
	})
end

function RewardsUI.open(tab: string?)
	local current = tab or "Daily"
	local win = Modal.open("Rewards", "Daily streak · playtime crates · codes", 820, 420)
	local ic = Icons.gift(34, C.Premium)
	ic.Position = UDim2.fromOffset(9, 7)
	ic.Parent = win.iconHolder
	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = win.body }, { Lib.list("x", 6) })
	local content = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), Parent = win.body })
	local ticker: (() -> ())? = nil
	local function render()
		Lib.clear(tabs)
		Lib.clear(content)
		ticker = nil
		for i, t in { "Daily", "Gift", "Codes" } do
			Lib.button({
				Name = t,
				Variant = t == current and "primary" or "secondary",
				Text = string.upper(t),
				TextSize = 13,
				Size = UDim2.fromOffset(120, 34),
				LayoutOrder = i,
				Parent = tabs,
				Activated = function()
					current = t
					render()
				end,
			})
		end
		if current == "Daily" then
			daily(content)
		elseif current == "Gift" then
			local tick = gift(content)
			ticker = tick
			tick()
		else
			codes(content)
		end
	end
	render()
	local acc = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc > 0.25 then
			acc = 0
			if ticker then
				ticker()
			end
		end
	end)
	win.onClose(function()
		conn:Disconnect()
	end)
end

function RewardsUI.showWelcome(amount: number, away: number)
	task.wait(2.5)
	local win = Modal.open("Welcome back, commander", "Your nation kept working while you were away", 560, 330)
	local ic = Icons.coin(36, C.Good)
	ic.Position = UDim2.fromOffset(8, 6)
	ic.Parent = win.iconHolder
	Lib.text({ Text = ("You were away for %s"):format(Format.duration(away)), TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Parent = win.body })
	Lib.display({ Text = "+" .. Format.money(amount), TextSize = 46, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 56), Parent = win.body })
	local vip = (ClientState.get("passes") or {}).VIP
	Lib.text({
		Text = vip and "VIP doubled your offline time." or "VIP doubles offline time · 2x Cash doubles the amount",
		TextSize = 13,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = win.body,
	})
	Lib.button({
		Name = "Collect",
		Variant = "primary",
		Text = "COLLECT",
		TextSize = 16,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(240, 48),
		Parent = win.body,
		Activated = function()
			Sounds.play("Success")
			Modal.close()
		end,
	})
end

function RewardsUI.init()
	Hub.openRewards = RewardsUI.open
	Hub.openDaily = function()
		RewardsUI.open("Daily")
	end
	Hub.openCodes = function()
		RewardsUI.open("Codes")
	end
	Hub.showWelcome = function(amount, away)
		task.spawn(RewardsUI.showWelcome, amount, away)
	end
end

return RewardsUI
