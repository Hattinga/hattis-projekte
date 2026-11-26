--!strict
-- P10-04 server proof on the management demo (P06LoadingDemo). Three fresh Play servers, chosen by workspace attribute
-- P1004Mode, each followed by ToolRun.LineDemo and then this probe (require ToolRun.P1004Probe):
--   plain   (with P0803WorkerStock) the offer before the purchase and an assembly run without the jig,
--   jig     (with P0803WorkerStock) buying, the visible model, the translated sign, the replay and a run with the jig,
--   advance (no stock) the empty workshop after the purchase: balance 30, material advance, no deadlock.
-- In memory only. Result as JSON returned directly and kept in ServerStorage.P1004Result.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
local state = storage:FindFirstChild("P0509LineState") :: BindableFunction
local hand = storage:FindFirstChild("P0509LineTest") :: BindableFunction
local equip = storage:FindFirstChild("P1004Equip") :: BindableFunction
local advance = storage:FindFirstChild("P0707Advance") :: BindableFunction
local purchase = storage:FindFirstChild("P060405Purchase") :: BindableFunction
assert(state and hand and equip and advance and purchase and not storage:FindFirstChild("P1004Result"), "Start the logistics demo in a fresh Play first")
local mode = workspace:GetAttribute("P1004Mode")
assert(mode == "plain" or mode == "jig" or mode == "advance", "Set P1004Mode to plain, jig or advance")
local player = assert(game:GetService("Players"):GetPlayers()[1])
local gui = assert(player.PlayerGui:FindFirstChild("BetriebHud"), "The HUD is missing") :: ScreenGui
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
local stations = workspace.P02Line.Stations
local JIG = "Montagevorrichtung"
local report: any = {task = "P10-04", mode = mode, checks = {}}
local http = game:GetService("HttpService")
local function note(text: string) table.insert(report.checks, text) end
local function toast(): any
	return {kind = gui:GetAttribute("ToastKind"), title = gui:GetAttribute("ToastTitle"), detail = gui:GetAttribute("ToastDetail")}
end
local function rowText(label: string): string?
	for _, child in (gui.Panel.Body :: Instance):GetChildren() do
		if child:IsA("TextLabel") and child.Text:find("<b>" .. label .. "</b>", 1, true) then
			return (child.Text:gsub("<b>.-</b>%s*", ""))
		end
	end
	return nil
end
local function face(pad: Instance, stand: BasePart)
	local position = stand.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local point = (pad:FindFirstChild("Transfer") :: Attachment).WorldPosition
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
local function jigModel(): Instance?
	local demo = workspace:FindFirstChild("P0509LineDemo")
	local shelf = demo and demo:FindFirstChild("Equipment")
	return if shelf then shelf:FindFirstChild(JIG) else nil
end
-- Carries the test kit from the saw output to the assembly input and returns the seconds until the assembly finishes.
local function assemblyRun(): number
	local before = state:Invoke()
	assert(before.batches.Testbausatz and before.batches.Testbausatz.locationId == "Saege.Output", "Expected the P0803WorkerStock kit at the saw output")
	face(stations.Saege.Output, stations.Saege.Standpoints.Output)
	assert(hand:Invoke("Saege.Output", "Take").result.ok)
	face(stations.Montage.Input, stations.Montage.Standpoints.Input)
	local putAt = os.time()
	assert(hand:Invoke("Montage.Input", "Put").result.ok)
	local deadline = os.clock() + 8
	local lock
	repeat
		task.wait(0.1)
		lock = state:Invoke().reservations["Montage.Output"]
	until (lock and lock.kind == "Production") or os.clock() > deadline
	assert(lock and lock.kind == "Production", "The assembly never started")
	return lock.finishAt - putAt
end

local saved, anchored = root.CFrame, root.Anchored
root.Anchored = true
local ok, failure = xpcall(function()
	if mode == "plain" then
		-- The offer before the purchase.
		task.wait(0.5)
		local equipButton = gui.Panel.Equip :: TextButton
		assert(equipButton.Visible and equipButton.Text == "Montagevorrichtung · 150" and equipButton.Size.Y.Offset >= 44, equipButton.Text)
		assert(gui:GetAttribute("OfferId") == JIG and not (gui.EquipCard :: GuiObject).Visible)
		local title, detail = (gui.EquipCard.Title :: TextLabel).Text, (gui.EquipCard.Detail :: TextLabel).Text
		assert(title == "Montagevorrichtung kaufen?", title)
		assert(detail:find("Montagebank: Hocker von 8 auf 6 s, Beistelltisch von 14 auf 10 s", 1, true), detail)
		assert(detail:find("Takt Hocker: von 8 auf 6 s", 1, true) and detail:find("Preis 150 · danach bleiben 30 Spielgeld.", 1, true), detail)
		assert(detail:find("Danach reicht das Guthaben (30) nicht für Holz (60)", 1, true), detail)
		assert(rowText("Ausrüstung") == "keine" and jigModel() == nil)
		assert((gui.EquipCard.Confirm :: GuiObject).Size.Y.Offset >= 44 and (gui.EquipCard.Cancel :: GuiObject).Size.Y.Offset >= 44)
		report.offer = {button = equipButton.Text, title = title, detail = detail}
		note("1 the offer names price 150, benefit for both recipes, the pace 8 -> 6 s and that 30 is left, which is less than wood costs")
		local seconds = assemblyRun()
		assert(seconds >= 8 and seconds <= 9, "Without the jig the assembly takes 8 s, measured " .. seconds)
		report.plainSeconds = seconds
		note("2 without the jig the stool assembly takes 8 s (measured " .. seconds .. ")")
	elseif mode == "jig" then
		local start = state:Invoke()
		assert(start.valid and start.money == 180 and jigModel() == nil)
		local bought = equip:Invoke(JIG)
		assert(bought.ok and bought.code == "BOUGHT", bought.code)
		task.wait(0.5)
		local after = state:Invoke()
		assert(after.valid and after.money == 30 and after.revision == start.revision + 1, after.money .. "/" .. after.revision)
		local model = jigModel()
		assert(model and #model:GetChildren() == 7, "The jig model shows posts, crossbar, arm, press and sign")
		local sign = model:FindFirstChild("EquipmentLabel") :: BillboardGui
		local label = sign:FindFirstChildOfClass("TextLabel") :: TextLabel
		local german = (game:GetService("LocalizationService"):FindFirstChild("FactoryLabels") :: LocalizationTable):GetTranslator("de")
		assert(label.Text == "ASSEMBLY JIG" and german:Translate(label, label.Text) == "MONTAGEVORRICHTUNG", label.Text)
		for _, piece in model:GetDescendants() do
			if piece:IsA("BasePart") then assert(piece.Anchored and not piece.CanCollide and not piece.CanQuery and not piece.CanTouch) end
		end
		local pad = stations.Montage.Process :: BasePart
		local bar = model:FindFirstChild("Crossbar") :: BasePart
		assert((bar.Position - pad.Position).Magnitude < 4, "The jig stands at the assembly work place")
		assert(not (gui.Panel.Equip :: GuiObject).Visible and gui:GetAttribute("OfferId") == nil, "Nothing is offered once everything is owned")
		assert(rowText("Ausrüstung") == "Montagevorrichtung" and rowText("Guthaben") == "30", tostring(rowText("Ausrüstung")))
		note("3 buying costs 150 (balance 30, revision +1), the jig stands at the assembly bench without collision, its sign is translated, the offer is gone")
		local again = equip:Invoke(JIG)
		assert(again.ok and again.code == "OWNED", again.code)
		local replay = state:Invoke()
		assert(replay.money == 30 and replay.revision == after.revision, "A second request charges nothing")
		note("4 a second request answers OWNED and changes nothing")
		local seconds = assemblyRun()
		assert(seconds >= 6 and seconds <= 7, "With the jig the assembly takes 6 s, measured " .. seconds)
		report.jigSeconds = seconds
		note("5 with the jig the stool assembly takes 6 s (measured " .. seconds .. ")")
	else
		-- Empty workshop, balance 180: the jig leaves 30, less than one wood package.
		local start = state:Invoke()
		assert(start.valid and start.money == 180 and next(start.batches) == nil)
		local bought = equip:Invoke(JIG)
		assert(bought.ok and bought.code == "BOUGHT", bought.code)
		task.wait(0.5)
		local poor = state:Invoke()
		assert(poor.valid and poor.money == 30)
		assert(gui.Panel.Header.Text:find("Materialvorschuss", 1, true), gui.Panel.Header.Text)
		local pickup = workspace.CityGreybox.DeliveryYards.Holzlieferant.P05Pickup
		face(pickup.Slot1, pickup.Standpoints.Slot1 :: BasePart)
		task.wait(0.5)
		local refused = purchase:Invoke()
		assert(not refused.ok and refused.code == "NOT_ENOUGH_MONEY", refused.code)
		local granted = advance:Invoke()
		assert(granted.ok, granted.code)
		task.wait(0.5)
		local after = state:Invoke()
		assert(after.valid and after.money == 30 and after.advance and after.advance.amount == 60)
		local package
		for _, batch in after.batches do if batch.stage == "Holzpaket" and batch.locationId:find("Supplier") then package = batch end end
		assert(package, "The advance puts one wood package at the supplier")
		assert(not (gui.Panel.Header.Text :: string):find("Materialvorschuss", 1, true), gui.Panel.Header.Text)
		assert(toast().kind == "ok" and toast().title == "Materialvorschuss erhalten", http:JSONEncode(toast()))
		report.advance = {money = after.money, advance = after.advance.amount, toast = toast()}
		note("6 after a high spend (balance 30) the regular buy is refused, the advance gives one wood package, the header no longer asks for it and the jig stays")
	end
end, function(problem: any): string return debug.traceback(tostring(problem), 2) end)
root.CFrame, root.Anchored = saved, anchored
report.ok = ok
if not ok then report.failure = failure end
local value = Instance.new("StringValue")
value.Name = "P1004Result"
value.Value = http:JSONEncode(report)
value.Parent = storage
return value.Value
