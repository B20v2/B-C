--[[
	RewardsUI
	Daily login streak, codes + group reward, and the welcome-back popup
	that shows offline earnings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local RewardsUI = {}

function RewardsUI.openDaily()
	local win = Modal.open("Daily Rewards", "Log in every day to build your streak", 760, 360)
	local ic = Icons.calendar(38, Theme.Color.Military)
	ic.Position = UDim2.fromOffset(6, 4)
	ic.Parent = win.iconHolder
	local daily = ClientState.get("daily") or { streak = 0, canClaim = false, next = 1, reward = 0 }
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), Parent = win.body }, { Lib.list("x", 8) })
	local nextDay = ((daily.next - 1) % #Config.DailyRewards) + 1
	local currentDay = ((math.max(daily.streak, 1) - 1) % #Config.DailyRewards) + 1
	for i, base in Config.DailyRewards do
		local isNext = daily.canClaim and i == nextDay
		local claimed = (not daily.canClaim and i <= currentDay and daily.streak > 0) or (daily.canClaim and i < nextDay)
		local card = Lib.card({
			Size = UDim2.new(1 / #Config.DailyRewards, -7, 1, 0),
			BackgroundColor3 = isNext and Theme.Color.GoldSoft or (claimed and Theme.Color.GoodSoft or Theme.Color.Card),
			LayoutOrder = i,
			Parent = row,
		}, { Lib.pad(10, 8) })
		if isNext then
			local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Color = Theme.Color.Gold
			stroke.Thickness = 2
		end
		Lib.caption("Day " .. i, { TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
		local gift = Icons.gift(40, i == 7 and Theme.Color.Gold or Theme.Color.Military)
		gift.AnchorPoint = Vector2.new(0.5, 0)
		gift.Position = UDim2.new(0.5, 0, 0, 24)
		gift.Parent = card
		Lib.text({
			Text = i == nextDay and daily.canClaim and Format.cash(daily.reward) or Format.cash(base) .. "+",
			FontFace = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.Good,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 76),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = card,
		})
		Lib.text({
			Text = claimed and "CLAIMED" or (isNext and "TODAY" or ""),
			FontFace = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = claimed and Theme.Color.Good or Theme.Color.Amber,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = card,
		})
	end
	Lib.button({
		Text = daily.canClaim and ("Claim " .. Format.cash(daily.reward)) or "Come back tomorrow",
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = daily.canClaim and Theme.Color.Good or Theme.Color.Faint,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 166),
		Size = UDim2.fromOffset(260, 44),
		Parent = win.body,
		Activated = function()
			local res = Net.request("ClaimDaily")
			if res.ok then
				Sounds.play("Success")
				Modal.close()
			elseif res.err then
				Notifications.show(res.err, "info")
			end
		end,
	}, { Lib.corner(8) })
	Lib.text({
		Text = ("Current streak: %d day%s. Rewards grow with your income."):format(daily.streak, daily.streak == 1 and "" or "s"),
		TextColor3 = Theme.Color.Muted,
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 220),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = win.body,
	})
end

function RewardsUI.openCodes()
	local win = Modal.open("Codes & Rewards", "Redeem codes from our socials", 520, 360)
	local ic = Icons.ticket(38, Theme.Color.Civil)
	ic.Position = UDim2.fromOffset(6, 4)
	ic.Parent = win.iconHolder
	local box = New("TextBox", {
		Text = "",
		PlaceholderText = "Enter code",
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Color.Text,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -150, 0, 46),
		Parent = win.body,
	}, { Lib.corner(8), Lib.stroke(), Lib.pad(0, 12) })
	Lib.button({
		Text = "Redeem",
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Color.Accent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(140, 46),
		Parent = win.body,
		Activated = function()
			local res = Net.request("RedeemCode", box.Text)
			if res.ok then
				Sounds.play("Success")
				box.Text = ""
			elseif res.err then
				Notifications.show(res.err, "bad")
			end
		end,
	}, { Lib.corner(8) })

	local group = Lib.card({ Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 96), Parent = win.body }, { Lib.pad(12, 14) })
	Lib.text({ Text = "Group Reward", FontFace = Theme.Font.Bold, Size = UDim2.new(1, -160, 0, 22), Parent = group })
	local claimed = ClientState.get("groupClaimed") == true
	local hasGroup = (ClientState.get("groupId") or 0) ~= 0
	Lib.text({
		Text = hasGroup and ("Join our Roblox group for a free %s and updates."):format(Format.cash(Config.GroupRewardCash)) or "No group reward set up yet.",
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, -160, 0, 40),
		Parent = group,
	})
	Lib.button({
		Text = claimed and "CLAIMED" or "Claim",
		FontFace = Theme.Font.Bold,
		TextColor3 = claimed and Theme.Color.Good or Color3.new(1, 1, 1),
		BackgroundColor3 = claimed and Theme.Color.GoodSoft or Theme.Color.Good,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(140, 40),
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
	}, { Lib.corner(8) })
end

function RewardsUI.showWelcome(amount: number, away: number)
	task.wait(2) -- let the HUD settle first
	local win = Modal.open("Welcome back!", "Your nation kept working while you were away", 480, 300)
	local ic = Icons.coin(40, Theme.Color.Good)
	ic.Position = UDim2.fromOffset(6, 4)
	ic.Parent = win.iconHolder
	Lib.text({
		Text = ("You were away for %s"):format(Format.duration(away)),
		TextColor3 = Theme.Color.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = win.body,
	})
	Lib.text({
		Text = "+" .. Format.money(amount),
		FontFace = Theme.Font.Bold,
		TextSize = 40,
		TextColor3 = Theme.Color.Good,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 50),
		Parent = win.body,
	})
	local vip = (ClientState.get("passes") or {}).VIP
	Lib.text({
		Text = vip and "VIP doubled your offline time!" or "VIP doubles offline time, 2x Cash doubles the amount.",
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = win.body,
	})
	Lib.button({
		Text = "Collect",
		FontFace = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Theme.Color.Good,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(220, 44),
		Parent = win.body,
		Activated = function()
			Sounds.play("Success")
			Modal.close()
		end,
	}, { Lib.corner(8) })
end

function RewardsUI.init()
	Hub.openDaily = RewardsUI.openDaily
	Hub.openCodes = RewardsUI.openCodes
	Hub.showWelcome = function(amount, away)
		task.spawn(RewardsUI.showWelcome, amount, away)
	end
end

return RewardsUI
