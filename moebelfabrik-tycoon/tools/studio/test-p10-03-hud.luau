--!strict
-- P10-03 server proof on the management demo: HUD structure and touch sizes, overview rows from the confirmed state,
-- recipe choice by the HUD path, and the confirmations for purchase, refused purchase and refused advance.
-- Fresh Play server: set P06LoadingDemo=true, run ToolRun.LineDemo, then require this probe. In memory only.
-- Result: JSON returned directly (short run) and kept in ServerStorage.P1003Result.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
local state = storage:FindFirstChild("P0509LineState") :: BindableFunction
local choose = storage:FindFirstChild("P1003Select") :: BindableFunction
local purchase = storage:FindFirstChild("P060405Purchase") :: BindableFunction
local advance = storage:FindFirstChild("P0707Advance") :: BindableFunction
assert(state and choose and purchase and advance and not storage:FindFirstChild("P1003Result"), "Start the logistics demo in a fresh Play first")
local player = assert(game:GetService("Players"):GetPlayers()[1])
local gui = assert(player.PlayerGui:FindFirstChild("BetriebHud"), "The HUD is missing") :: ScreenGui
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
local report: any = {task = "P10-03", checks = {}}
local function note(text: string) table.insert(report.checks, text) end
local function toast(): any
	return {kind = gui:GetAttribute("ToastKind"), title = gui:GetAttribute("ToastTitle"), detail = gui:GetAttribute("ToastDetail"),
		id = gui:GetAttribute("ToastId")}
end
local function rowText(label: string): string?
	for _, child in (gui.Panel.Body :: Instance):GetChildren() do
		if child:IsA("TextLabel") and child.Text:find("<b>" .. label .. "</b>", 1, true) then
			return (child.Text:gsub("<b>.-</b>%s*", ""))
		end
	end
	return nil
end
local function header(): string return (gui.Panel.Header :: TextButton).Text end
local function standAt(pad: Instance, stand: BasePart)
	local position = stand.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local point = (pad:FindFirstChild("Transfer") :: Attachment).WorldPosition
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end

local saved, anchored = root.CFrame, root.Anchored
root.Anchored = true
local ok, failure = xpcall(function()
	-- Group 1: structure and touch sizes. Every pressable element is at least 44 px high.
	local pressable = {gui.Panel.Header, gui.Bar.Recipe, gui.Bar.Buy, gui.Bar.Sell, gui.Card.Confirm, gui.Card.Cancel}
	for _, item in pressable do
		assert((item :: GuiButton):IsA("GuiButton") and (item :: GuiObject).Size.Y.Offset >= 44, item.Name .. " is too small for touch")
	end
	assert(gui:FindFirstChild("HudClient") and gui:FindFirstChild("Action") and gui.DisplayOrder == -1)
	assert(not (gui.Panel.Body :: GuiObject).Visible and not (gui.Card :: GuiObject).Visible, "Body and card start closed")
	assert((gui.Panel :: GuiObject).Size.X.Offset <= 260 and (gui.Card :: GuiObject).Size.X.Offset <= 340, "Panels must fit 800 px logical width")
	assert(not (gui.Bar.Sell :: GuiObject).Visible, "The sell button only shows while a sale is open")
	note("1 header, recipe, buy and sell buttons and the card buttons are at least 44 px high; the sell button starts hidden; panel 250 px and card 330 px wide; HUD sits below touch controls")

	-- Group 2: the overview rows follow the confirmed state.
	task.wait(0.5)
	local start = state:Invoke()
	assert(start.valid and start.money == 180)
	assert(rowText("Guthaben") == "180" and rowText("Holz") == "0" and rowText("Kartons") == "0", tostring(rowText("Guthaben")))
	assert(rowText("Rezept") == "Hocker · Einkauf 60 · Händler 100" and rowText("Fertiglager") == "0/4 belegt")
	assert(rowText("Anhänger") == "0/2 belegt · 2 frei", tostring(rowText("Anhänger")))
	assert(header():find("Kein Holz: Kaufe beim Lieferanten ein Holzpaket für 60.", 1, true), header())
	assert(gui:GetAttribute("FollowingId") == "Beistelltisch01")
	assert((gui.Bar.Recipe :: TextButton).Text == "Rezept: Hocker  ⇄  Beistelltisch" and (gui.Bar.Buy :: TextButton).Text == "Kaufen\nHolzpaket · 60",
		(gui.Bar.Buy :: TextButton).Text)
	note("2 rows show balance 180, stock 0, stores 0/4 and trailer 0/2 free 2; the header names the missing wood at the stool price")

	-- Group 3: the recipe choice by the HUD path (the card's confirm reaches the same function).
	local before = toast().id
	local nothing = choose:Invoke("Regal01")
	assert(not nothing.ok and nothing.code == "UNKNOWN_RECIPE", nothing.code)
	local changed = state:Invoke()
	assert(changed.revision == start.revision and changed.money == 180, "A refused choice changes nothing")
	local picked = choose:Invoke("Beistelltisch01")
	assert(picked.ok and picked.code == "SELECTED", picked.code)
	task.wait(0.3)
	local after = state:Invoke()
	assert(after.revision == start.revision + 1 and after.valid and after.money == 180)
	assert(header():find("Tischholzpaket für 80.", 1, true), header())
	assert(rowText("Rezept") == "Beistelltisch · Einkauf 80 · Händler 140", tostring(rowText("Rezept")))
	assert(gui:GetAttribute("FollowingId") == "Hocker01" and (gui.Bar.Recipe :: TextButton).Text == "Rezept: Beistelltisch  ⇄  Hocker")
	assert((gui.Card.Title :: TextLabel).Text == "Zu Hocker wechseln?")
	assert(((gui.Card.Detail :: TextLabel).Text):find("Einkauf 60 · Händler 100 · Montage 8 s", 1, true), (gui.Card.Detail :: TextLabel).Text)
	assert(toast().id == before, "The hook path itself does not toast; the card path and the prompt do")
	note("3 an unknown recipe is refused without a change; the choice saves once (revision +1), header, rows, button and card follow")

	-- Group 4: purchase confirmation with price and balance, then the refusal when the balance is short.
	local pickup = workspace.CityGreybox.DeliveryYards.Holzlieferant.P05Pickup
	standAt(pickup.Slot1, pickup.Standpoints.Slot1 :: BasePart) -- the standpoint of the slot the purchase uses
	task.wait(0.5)
	local first = purchase:Invoke()
	assert(first.ok and first.code == "PURCHASED", first.code)
	task.wait(0.3)
	local t1 = toast()
	assert(t1.kind == "ok" and t1.title == "Gekauft: Tischholzpaket" and t1.detail == "−80 · Guthaben 100", game:GetService("HttpService"):JSONEncode(t1))
	assert(rowText("Guthaben") == "100" and rowText("Holz") == "1 (Lieferant 1)", tostring(rowText("Holz")))
	assert(header():find("1 Holzpaket liegt beim Lieferanten: auf den Anhänger laden.", 1, true), header())
	local second = purchase:Invoke()
	assert(second.ok, second.code)
	task.wait(0.3)
	assert(toast().title == "Gekauft: Tischholzpaket" and toast().detail == "−80 · Guthaben 20" and toast().id == t1.id + 1)
	local third = purchase:Invoke()
	assert(not third.ok and third.code == "NOT_ENOUGH_MONEY", third.code)
	task.wait(0.3)
	local t3 = toast()
	assert(t3.kind == "warn" and t3.title == "Kauf nicht möglich" and t3.detail:find("kostet 80 Spielgeld", 1, true), game:GetService("HttpService"):JSONEncode(t3))
	local poor = state:Invoke()
	assert(poor.valid and poor.money == 20, "A refused purchase costs nothing")
	note("4 the purchase toast names package, price and new balance (100, then 20); the third buy is refused with a warning and no cost")

	-- Group 5: the advance is refused while a regular purchase is still possible or stock exists.
	local refused = advance:Invoke()
	assert(not refused.ok, refused.code)
	task.wait(0.3)
	local t4 = toast()
	assert(t4.kind == "warn" and t4.title == "Vorschuss nicht möglich", game:GetService("HttpService"):JSONEncode(t4))
	assert(rowText("Holz") == "2 (Lieferant 2)" and rowText("Guthaben") == "20")
	note("5 a refused advance warns in the HUD and changes nothing")
	report.toasts = {purchase = t1, refusal = t3, advance = t4}
end, function(problem: any): string return debug.traceback(tostring(problem), 2) end)
root.CFrame, root.Anchored = saved, anchored
report.ok = ok
if not ok then report.failure = failure end
local value = Instance.new("StringValue")
value.Name = "P1003Result"
value.Value = game:GetService("HttpService"):JSONEncode(report)
value.Parent = storage
return value.Value
