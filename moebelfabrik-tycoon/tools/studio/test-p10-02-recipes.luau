--!strict
-- P10-02 server proof in a Studio play server: both recipes on the real workshop model. Binding, ware views and their
-- measured hulls, signs (EN and DE), the table chain, a recipe switch during a started run and a purchase. In-memory
-- persistence only; nothing is written to a DataStore. Result as JSON in ServerStorage.P1002Result.
-- Run in a fresh Studio play server: require(ServerStorage.ToolRun.P1002Probe), then poll the result.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P1002Result") and not workspace:FindFirstChild("P1002Probe"), "Probe already ran")
local result = Instance.new("StringValue")
result.Name = "P1002Result"
result.Parent = storage

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P10-02", checks = checks}
	local root = Instance.new("Folder")
	root.Name = "P1002Probe"
	root.Parent = workspace
	local ok, failure = xpcall(function()
		local factory = game:GetService("ServerScriptService").Factory
		local State = require(factory.State)
		local Recipes = require(factory.Recipes)
		local RecipeChoice = require(factory.RecipeChoice)
		local Transfers = require(factory.Transfers)
		local Persistence = require(factory.Persistence)
		local Recipe = require(factory.Recipe)
		local Line = require(factory.Line)
		local LineView = require(factory.LineView)
		local Purchases = require(factory.Purchases)
		local SCALE = 25 / 7
		local HOCKER, TISCH = "Hocker01", "Beistelltisch01"
		local german = (game:GetService("LocalizationService"):FindFirstChild("FactoryLabels") :: LocalizationTable):GetTranslator("de")
		local function note(text: string) table.insert(checks, text) end
		local function near(value: number, expected: number, tolerance: number): boolean return math.abs(value - expected) <= tolerance end

		local line = workspace.P02Line
		local setup = assert(Recipe.bind(line.Stations))
		local shelf = assert(Recipe.bindStore(line.Stores.Fertiglager, "FinishedStore", "Karton"))
		local rawStore = assert(Recipe.bindStore(line.Stores.Rohstofflager, "RawStore", "Holzpaket"))
		local pickup = workspace.CityGreybox.DeliveryYards.Holzlieferant.P05Pickup
		local purchase = assert(Purchases.bind(pickup, line.Stores.Rohstofflager))
		local hold = Instance.new("Part")
		hold.Name = "TestCarrier"
		hold.Anchored, hold.CanCollide, hold.CanQuery, hold.Transparency = true, false, false, 1
		hold.Size = Vector3.one
		hold.CFrame = line.Stations.Montage.Input.CFrame * CFrame.new(0, 4, 4)
		hold.Parent = root
		local places: any = {points = {}, carriers = {["Test.Hand"] = hold}, stationPads = {}, storeSlots = {}, storePad = line.Stores.Fertiglager.Slot2}
		local locations: {[string]: State.Location} = {}
		for _, binding in {setup, shelf, rawStore} do
			for id, location in binding.locations do locations[id] = location end
			for id, point in binding.points do places.points[id] = point end
		end
		for id, point in purchase.points do places.points[id] = point end
		for _, rule in State.STATIONS do places.stationPads[rule.id] = line.Stations[rule.id].Process end
		for i = 1, 4 do table.insert(places.storeSlots, "FinishedStore.Slot" .. i) end

		-- Group 1: the bound places accept both recipes.
		local function accepts(id: string, stage: string): boolean return table.find(locations[id].acceptedStages, stage :: State.Stage) ~= nil end
		assert(accepts("Montage.Output", "Rohtisch") and accepts("Montage.Output", "Rohhocker")
			and accepts("Finish.Input", "Rohtisch") and accepts("Finish.Process", "Rohtisch") and accepts("Finish.Input", "Rohhocker"))
		assert(accepts("Saege.Input", "Holzpaket") and not accepts("Saege.Input", "Rohtisch") and accepts("Packen.Input", "Fertig")
			and accepts("Packen.Output", "Karton") and not accepts("Finish.Output", "Rohtisch"))
		note("1 station places accept the stages of both recipes")

		local function envelope(selected: string, money: number): any
			local state = State.newProfile(101)
			state.money = money
			for id, location in locations do state.locations[id] = location end
			state.locations["Test.Hand"] = State.newLocation("Test.Hand", "Carrier", 1,
				{"Holzpaket", "Bausatz", "Rohhocker", "Rohtisch", "Fertig", "Karton"})
			return {profileVersion = 1, state = state, progress = {version = 1, selectedRecipeId = selected, selectedRecipeVersion = 1}}
		end
		local function copy(value: any): any
			if type(value) ~= "table" then return value end
			local out: any = {}
			for key, item in value do out[key] = copy(item) end
			return out
		end
		local now = os.time()
		local function controllerFor(data: any, token: string): any
			local saved: any = nil
			local backend = {read = function(_: string): any return copy(saved) end,
				update = function(_: string, transform: any): any
					local proposed = transform(copy(saved))
					if proposed ~= nil then saved = copy(proposed) end
					return copy(proposed)
				end}
			local c = Persistence.new(101, backend, function(): number return now end)
			assert(c.load(token, 600, function(): any return data end).ok)
			return c
		end
		local function stateOf(c: any): any return c.snapshot().confirmed.data.state end
		local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "Test.Hand", ready = true}
		local function carry(c: any, batchId: string, from: string, to: string, id: string)
			local store = Transfers.new(stateOf(c))
			assert(Transfers.reserve(store, actor, {operationId = id .. "/r", expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, now, 5).ok, id)
			assert(Transfers.commit(store, actor, {operationId = id .. "/c", expectedRevision = store.profile.revision,
				claimId = id .. "/r"}, now).ok, id)
			local proposal = c.snapshot().confirmed.data
			proposal.state = store.profile
			assert(c.save(proposal, 600).ok, id)
		end
		local function move(c: any, batchId: string, from: string, to: string, id: string)
			carry(c, batchId, from, "Test.Hand", id .. "/a")
			carry(c, batchId, "Test.Hand", to, id .. "/b")
		end
		local function tick(c: any): string
			local list = {}
			for _, event in Line.tick(c, now, 600) do table.insert(list, event.stationId .. ":" .. event.code) end
			return table.concat(list, ",")
		end
		-- Hull of a ware view in metres, measured in the object space of its support.
		local function hull(model: Instance, support: CFrame): Vector3
			local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					local half = part.Size / 2
					for _, sx in {-1, 1} do
						for _, sy in {-1, 1} do
							for _, sz in {-1, 1} do
								local corner = support:PointToObjectSpace((part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)))
								lo, hi = lo:Min(corner), hi:Max(corner)
							end
						end
					end
				end
			end
			return (hi - lo) / SCALE
		end
		local function view(batchId: string): Instance return assert(root.Wares:FindFirstChild(batchId), "No view " .. batchId) end
		local function smallestPart(model: Instance): number
			local smallest = math.huge
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then smallest = math.min(smallest, part.Size.X, part.Size.Y, part.Size.Z) end
			end
			return smallest
		end
		local function signTexts(name: string): (string, string, string, string, string)
			local board = root.Signs:FindFirstChild(name) :: BillboardGui
			local head, detail = board:FindFirstChild("Head") :: TextLabel, board:FindFirstChild("Detail") :: TextLabel
			return board:GetAttribute("StatusCode") :: string, head.Text, detail.Text,
				german:Translate(head, head.Text), if detail.Text ~= "" then german:Translate(detail, detail.Text) else ""
		end

		-- Group 2: every table stage and its stool counterpart on the real supports, measured against TABLE.md.
		local data = envelope(TISCH, 200)
		local s = data.state
		local function put(id: string, stage: any, at: string, recipe: string?) s.batches[id] = State.newBatch(id, 101, stage, at, recipe) end
		put("tPack", "Holzpaket", "RawStore.Slot1", TISCH); put("tKit", "Bausatz", "Montage.Input", TISCH)
		put("tRaw", "Rohtisch", "Finish.Input", TISCH); put("tFin", "Fertig", "Packen.Input", TISCH)
		put("tBox", "Karton", "FinishedStore.Slot1", TISCH)
		put("sPack", "Holzpaket", "RawStore.Slot2"); put("sKit", "Bausatz", "Saege.Output")
		put("sRaw", "Rohhocker", "Montage.Output"); put("sFin", "Fertig", "Finish.Output")
		put("sBox", "Karton", "FinishedStore.Slot2")
		assert(State.validate(s))
		local c = controllerFor(data, "views/" .. tostring(os.clock()))
		LineView.syncWares(root, stateOf(c), places)
		LineView.syncSigns(root, stateOf(c), now, places)
		local expected = {
			tPack = {0.60, 0.15, 0.50}, tKit = {0.60, 0.18, 0.50}, tRaw = {0.42, 0.48, 0.42}, tFin = {0.42, 0.48, 0.42},
			tBox = {0.48, 0.54, 0.48}, sPack = {0.60, 0.15, 0.45}, sKit = {0.60, 0.18, 0.50}, sRaw = {0.40, 0.45, 0.40},
			sFin = {0.40, 0.45, 0.40}, sBox = {0.46, 0.51, 0.46},
		}
		local measured: any = {}
		for id, size in expected do
			local batch = stateOf(c).batches[id]
			local support = places.points[batch.locationId].WorldCFrame
			local model = view(id)
			local got = hull(model, support)
			measured[id] = string.format("%.3f x %.3f x %.3f", got.X, got.Y, got.Z)
			assert(near(got.X, size[1], 0.0025) and near(got.Y, size[2], 0.0025) and near(got.Z, size[3], 0.0025),
				id .. " hull " .. measured[id])
			assert(model:GetAttribute("Stage") == batch.stage and model:GetAttribute("RecipeId") == batch.recipeId, id .. " attributes")
			assert(smallestPart(model) >= 0.05 - 1e-6, id .. " has a part below the 0.05 stud limit")
		end
		report.hulls = measured
		note("2 ten views match their TABLE.md or DIMENSIONS hulls within 2.5 mm; no part below 0.05 studs; recipe and stage attributes set")
		assert(view("tFin"):GetAttribute("Stage") == "Fertig" and view("tBox"):GetAttribute("RecipeId") == TISCH)
		local tableParts, stoolParts = 0, 0
		for _, part in view("tKit"):GetChildren() do if part:GetAttribute("WoodPiece") == true then tableParts += 1 end end
		for _, part in view("sKit"):GetChildren() do if part:GetAttribute("WoodPiece") == true then stoolParts += 1 end end
		assert(stoolParts == 9 and tableParts == 11, "kit pieces stool " .. stoolParts .. " table " .. tableParts)
		report.kitPieces = {stool = stoolParts, table = tableParts}
		note("2b the table kit shows 11 wood meshes (10 parts, the shelf as a cross of two boards), the stool kit 9")

		-- Group 3: recipe sign, refusal sign and stage texts in English and German.
		places.selectedRecipeId = TISCH
		LineView.syncSigns(root, stateOf(c), now, places)
		local code, head, detail, deHead, deDetail = signTexts("Recipe")
		assert(head == "RECIPE: SIDE TABLE" and detail == "NEXT: TABLE WOOD PACKAGE"
			and deHead == "REZEPT: BEISTELLTISCH" and deDetail == "NÄCHSTES: TISCHHOLZPAKET", head .. "|" .. detail .. "|" .. deHead)
		code, head, detail, deHead = signTexts("Status_Packen")
		assert(code == "READY" or code == "RUNNING" or code == "OUTPUT_FULL" or code == "INPUT_MISSING")
		note("3 the recipe sign names the choice and the next wood in EN and DE")
		local empty = controllerFor(envelope(TISCH, 200), "signs/" .. tostring(os.clock()))
		for _, child in root.Wares:GetChildren() do child:Destroy() end
		LineView.syncWares(root, stateOf(empty), places)
		LineView.syncSigns(root, stateOf(empty), now, places)
		code, head, detail, deHead = signTexts("Status_Saege")
		assert(code == "INPUT_MISSING" and head == "TABLE WOOD MISSING" and deHead == "TISCHHOLZ FEHLT", head)
		code, head, detail, deHead = signTexts("Status_Finish")
		assert(head == "RAW TABLE MISSING" and deHead == "ROHTISCH FEHLT", head)
		code, head, detail, deHead = signTexts("Status_Packen")
		assert(head == "FINISHED TABLE MISSING" and deHead == "FERTIGER TISCH FEHLT", head)
		places.selectedRecipeId = HOCKER
		LineView.syncSigns(root, stateOf(empty), now, places)
		code, head, detail, deHead = signTexts("Status_Packen")
		assert(head == "FINISHED STOOL MISSING" and deHead == "FERTIGER HOCKER FEHLT", head)
		code, head, detail, deHead = signTexts("Recipe")
		assert(head == "RECIPE: STOOL" and deHead == "REZEPT: HOCKER")
		note("3b empty stations name the selected recipe's ware: table texts for the table, stool texts for the stool")

		-- A table package at the saw while the stool is selected is simply worked: the choice only steers purchases.
		local mixed = envelope(HOCKER, 200)
		mixed.state.batches.tw = State.newBatch("tw", 101, "Holzpaket", "Saege.Input", TISCH)
		local w = controllerFor(mixed, "mixed/" .. tostring(os.clock()))
		for _, child in root.Wares:GetChildren() do child:Destroy() end
		places.selectedRecipeId = HOCKER
		LineView.syncWares(root, stateOf(w), places)
		LineView.syncSigns(root, stateOf(w), now, places)
		code, head, detail, deHead = signTexts("Status_Saege")
		assert(code == "READY" and head == "CUTTING" and deHead == "ZUSCHNITT", code .. head)
		assert(view("tw"):GetAttribute("RecipeId") == TISCH)
		code, head, detail, deHead = signTexts("Recipe")
		assert(head == "RECIPE: STOOL" and deHead == "REZEPT: HOCKER", "The recipe sign still names the choice")
		assert(tick(w) == "Saege:STARTED")
		assert(stateOf(w).reservations["Saege.Output"].finishAt == now + 8, "The table package takes the table's 8 s")
		note("3c a table package at the saw under the stool choice is worked with the table's time; the choice only steers purchases")

		-- Group 4: one table batch through the four real stations, each stage shown with the table model.
		local run = controllerFor(envelope(TISCH, 200), "chain/" .. tostring(os.clock()))
		do
			local store = Transfers.new(stateOf(run))
			store.profile.batches.t = State.newBatch("t", 101, "Holzpaket", "Saege.Input", TISCH)
			store.profile.revision += 1
			local proposal = run.snapshot().confirmed.data
			proposal.state = store.profile
			assert(run.save(proposal, 600).ok)
		end
		local timeline = {}
		local function show(expectStage: string, expectAt: string)
			local current = stateOf(run)
			local batch = current.batches.t
			assert(batch.stage == expectStage and batch.locationId == expectAt and batch.recipeId == TISCH, batch.stage .. "@" .. batch.locationId)
			for _, child in root.Wares:GetChildren() do child:Destroy() end
			LineView.syncWares(root, current, places)
			local model = view("t")
			assert(model:GetAttribute("Stage") == expectStage and model:GetAttribute("RecipeId") == TISCH)
			table.insert(timeline, expectStage .. "@" .. expectAt)
		end
		places.selectedRecipeId = TISCH
		local t0 = now
		assert(tick(run) == "Saege:STARTED"); now = t0 + 7; assert(tick(run) == ""); now = t0 + 8
		assert(tick(run) == "Saege:FINISHED"); show("Bausatz", "Saege.Output")
		move(run, "t", "Saege.Output", "Montage.Input", "m1")
		assert(tick(run) == "Montage:STARTED"); local m0 = now; now = m0 + 13; assert(tick(run) == ""); now = m0 + 14
		assert(tick(run) == "Montage:FINISHED"); show("Rohtisch", "Montage.Output")
		move(run, "t", "Montage.Output", "Finish.Input", "f1")
		assert(tick(run) == "Finish:STARTED"); local f0 = now; now = f0 + 8
		assert(tick(run) == "Finish:FINISHED"); show("Fertig", "Finish.Output")
		move(run, "t", "Finish.Output", "Packen.Input", "p1")
		assert(tick(run) == "Packen:STARTED"); local p0 = now; now = p0 + 5
		assert(tick(run) == "Packen:FINISHED"); show("Karton", "Packen.Output")
		assert(State.validate(stateOf(run)) and stateOf(run).money == 200)
		report.timeline = timeline
		note("4 one table batch took 8 + 14 + 8 + 5 seconds through the real stations and showed the table model at every stage")

		-- Group 5: a switch during a started stool run leaves both batches with their own recipe and view.
		now = os.time()
		local mix = envelope(HOCKER, 200)
		mix.state.batches.hw = State.newBatch("hw", 101, "Holzpaket", "Saege.Input")
		local mc = controllerFor(mix, "mix/" .. tostring(os.clock()))
		assert(tick(mc) == "Saege:STARTED")
		local started = now
		local switched = RecipeChoice.select(mc, 101, stateOf(mc).revision, TISCH, 600)
		assert(switched.ok and switched.code == "SELECTED", switched.code)
		do
			local store = Transfers.new(stateOf(mc))
			store.profile.batches.tw = State.newBatch("tw", 101, "Holzpaket", "Saege.Input", TISCH)
			store.profile.revision += 1
			local proposal = mc.snapshot().confirmed.data
			proposal.state = store.profile
			assert(mc.save(proposal, 600).ok)
		end
		now = started + 6
		assert(tick(mc) == "Saege:FINISHED")
		for _, child in root.Wares:GetChildren() do child:Destroy() end
		places.selectedRecipeId = TISCH
		LineView.syncWares(root, stateOf(mc), places)
		LineView.syncSigns(root, stateOf(mc), now, places)
		assert(view("hw"):GetAttribute("RecipeId") == HOCKER and view("hw"):GetAttribute("Stage") == "Bausatz")
		assert(view("tw"):GetAttribute("RecipeId") == TISCH and view("tw"):GetAttribute("Stage") == "Holzpaket")
		assert(near(hull(view("tw"), places.points["Saege.Input"].WorldCFrame).Z, 0.50, 0.0025))
		code, head, detail = signTexts("Status_Saege")
		assert(code == "OUTPUT_FULL" and detail == "COLLECT PARTS KIT", code .. "|" .. detail)
		note("5 after the switch during a started run the old stool kit and the waiting table package each keep their own view and recipe")

		-- Group 6: the purchase follows the choice, with the real supplier binding.
		local buyData = envelope(TISCH, 200)
		for id, location in purchase.locations do buyData.state.locations[id] = location end
		local bc = controllerFor(buyData, "buy/" .. tostring(os.clock()))
		local buyer = {kind = "Player", actorId = "Player/101", ownerUserId = 101, ready = true}
		local bought = Purchases.buy(bc, buyer, {operationId = "p1002-buy", expectedRevision = stateOf(bc).revision}, purchase.slots, 600)
		assert(bought.ok and bought.receipt.price == 80 and bought.receipt.message == "Tischholzpaket beim Lieferanten bereit.", bought.code)
		local after = stateOf(bc)
		assert(after.money == 120 and after.batches["purchase/p1002-buy"].recipeId == TISCH)
		for _, child in root.Wares:GetChildren() do child:Destroy() end
		places.selectedRecipeId = TISCH
		LineView.syncWares(root, after, places)
		local supplierId = bought.receipt.supplierId
		local packageView = view("purchase/p1002-buy")
		local size = hull(packageView, places.points[supplierId].WorldCFrame)
		assert(packageView:GetAttribute("RecipeId") == TISCH and near(size.X, 0.60, 0.0025) and near(size.Z, 0.50, 0.0025))
		report.purchase = {price = bought.receipt.price, message = bought.receipt.message, money = after.money, package = string.format("%.3f x %.3f x %.3f", size.X, size.Y, size.Z)}
		note("6 buying with the table selected costs 80, delivers a table package and shows it at the supplier slot")
	end, function(problem: any): string return debug.traceback(tostring(problem), 2) end)
	report.ok = ok
	if not ok then report.failure = failure end
	root:Destroy()
	result.Value = game:GetService("HttpService"):JSONEncode(report)
end)
return "P10-02 probe started"
