--!strict
-- P10-02 recipe suite: two recipes, the line's recipe choice and its effect on purchase, saw, stations and sale.
-- In-memory atomic backend; no engine, remotes or external storage.
return function(State: any, Transfers: any, Persistence: any, Stations: any, Line: any, Purchases: any, Sales: any,
	RecipeChoice: any, Recipes: any, Profiles: any): any
	local passed: {string} = {}
	local failures: {{name: string, error: string}} = {}
	local function test(name: string, body: () -> ())
		local ok, problem = xpcall(function(): boolean body(); return true end, function(problem: any): string
			return debug.traceback(tostring(problem), 2)
		end)
		if ok then table.insert(passed, name) else table.insert(failures, {name = name, error = tostring(problem)}) end
	end
	local function copy(value: any): any
		if type(value) ~= "table" then return value end
		local result: any = {}
		for key, item in value do result[key] = copy(item) end
		return result
	end
	local function equal(left: any, right: any): boolean
		if type(left) ~= type(right) then return false end
		if type(left) ~= "table" then return left == right end
		for key, item in left do if not equal(item, right[key]) then return false end end
		for key in right do if left[key] == nil then return false end end
		return true
	end
	local function codes(events: any): string
		local parts: {string} = {}
		for _, event in events do table.insert(parts, event.stationId .. ":" .. event.code) end
		return table.concat(parts, ",")
	end

	local HOCKER, TISCH = "Hocker01", "Beistelltisch01"
	local ALL_STAGES = {"Holzpaket", "Bausatz", "Rohhocker", "Rohtisch", "Fertig", "Karton"}
	local A, B, HAND = "Vehicle.Quad1.SlotA", "Vehicle.Quad1.SlotB", "hand"
	local ACTOR = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = HAND, ready = true}
	local SLOTS = {supplierIds = {"Supplier.Slot1"}, rawIds = {"RawStore.Slot1"}}
	-- A workshop whose station places accept every registered recipe (what Recipe.bind builds).
	local function profile(oldLayout: boolean?): any
		local p = State.newProfile(101)
		p.money = 200
		for _, rule in State.STATIONS do
			local inputStages = if oldLayout then {rule.inputStage} else Recipes.acceptedStages(rule.id, "Input")
			local outputStages = if oldLayout then {rule.outputStage} else Recipes.acceptedStages(rule.id, "Output")
			p.locations[rule.input] = State.newLocation(rule.input, "StationInput", 1, inputStages)
			p.locations[rule.process] = State.newLocation(rule.process, "StationProcess", 1, inputStages)
			p.locations[rule.output] = State.newLocation(rule.output, "StationOutput", 1, outputStages)
		end
		p.locations[HAND] = State.newLocation(HAND, "Carrier", 1, ALL_STAGES)
		p.locations[A] = State.newLocation(A, "VehicleSlot", 1, {"Holzpaket", "Karton"})
		p.locations[B] = State.newLocation(B, "VehicleSlot", 1, {"Holzpaket", "Karton"})
		p.locations["Supplier.Slot1"] = State.newLocation("Supplier.Slot1", "Supplier", 1, {"Holzpaket"})
		p.locations["RawStore.Slot1"] = State.newLocation("RawStore.Slot1", "RawStore", 1, {"Holzpaket"})
		p.locations["FinishedStore.Slot1"] = State.newLocation("FinishedStore.Slot1", "FinishedStore", 1, {"Karton"})
		return p
	end
	local function harness(state: any, selected: string?): any
		local h: any = {now = 1000, writes = 0, drop = false, value = nil}
		h.backend = {
			read = function(_: string): any return copy(h.value) end,
			update = function(_: string, transform: any): any
				h.writes += 1
				local proposed = transform(copy(h.value))
				if proposed ~= nil then h.value = copy(proposed) end
				if h.drop then h.drop = false; error("simulated lost reply") end
				return copy(proposed)
			end,
		}
		function h.controller(token: string): any
			local c = Persistence.new(101, h.backend, function(): number return h.now end)
			local loaded = c.load(token, 600, function(): any
				local recipe = Recipes.get(selected or HOCKER)
				return {profileVersion = 1, state = copy(state),
					progress = {version = 1, selectedRecipeId = recipe.id, selectedRecipeVersion = recipe.version}}
			end)
			assert(loaded.ok, loaded.code)
			return c
		end
		h.c = h.controller("session/1")
		function h.state(): any return h.c.snapshot().confirmed.data.state end
		function h.progress(): any return h.c.snapshot().confirmed.data.progress end
		function h.store(): any return Transfers.new(h.state()) end
		function h.save(store: any)
			local data = h.c.snapshot().confirmed.data
			data.state = store.profile
			assert(h.c.save(data, 600).ok)
		end
		function h.move(store: any, batchId: string, from: string, to: string, id: string)
			local reserved = Transfers.reserve(store, ACTOR, {operationId = id .. "/r", expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, h.now, 5)
			assert(reserved.ok, reserved.code)
			local committed = Transfers.commit(store, ACTOR, {operationId = id .. "/c",
				expectedRevision = store.profile.revision, claimId = id .. "/r"}, h.now)
			assert(committed.ok, committed.code)
		end
		-- Carries one batch from a station output into the next station input through the hand.
		function h.carry(batchId: string, from: string, to: string, id: string)
			local store = h.store()
			h.move(store, batchId, from, HAND, id .. "/a")
			h.move(store, batchId, HAND, to, id .. "/b")
			h.save(store)
		end
		function h.select(recipeId: any): any
			return RecipeChoice.select(h.c, 101, h.state().revision, recipeId, h.now, 600)
		end
		function h.tick(seconds: number): string
			h.now += seconds
			return codes(Line.tick(h.c, h.now, 600))
		end
		function h.arrival(slot: string, batchId: string, buyer: string): any
			return {ownerUserId = 101, vehicleId = "Quad1", slotId = slot, batchId = batchId, destination = buyer,
				departedAt = 1, arrivedAt = 2, travelledStuds = 700}
		end
		return h
	end
	local function unchanged(h: any, code: string, result: any)
		assert(result.code == code and not result.ok, "expected " .. code .. " got " .. tostring(result.code))
	end

	test("01 the recipe list holds both recipes with frozen times, stages and values", function()
		assert(table.isfrozen(Recipes) and table.isfrozen(Recipes.LIST) and #Recipes.LIST == 2)
		local stool, table2 = Recipes.get(HOCKER), Recipes.get(TISCH)
		assert(stool and table2 and Recipes.DEFAULT_ID == HOCKER and table.isfrozen(stool) and table.isfrozen(table2.chain))
		assert(stool.price == 60 and stool.dealer == 100 and stool.privateMin == 80 and stool.privateMax == 120)
		assert(table2.price == 80 and table2.dealer == 140 and table2.privateMin == 112 and table2.privateMax == 168)
		assert(table.concat(stool.chain, ",") == "Holzpaket,Bausatz,Rohhocker,Fertig,Karton")
		assert(table.concat(table2.chain, ",") == "Holzpaket,Bausatz,Rohtisch,Fertig,Karton")
		assert(table.concat(stool.seconds, ",") == "6,8,6,4" and table.concat(table2.seconds, ",") == "8,14,8,5")
		local montage = Recipes.timing(TISCH, "Montage")
		assert(montage and montage.inputStage == "Bausatz" and montage.outputStage == "Rohtisch" and montage.durationSeconds == 14)
		assert(Recipes.timing(TISCH, "Lackierer") == nil and Recipes.timing("Regal01", "Saege") == nil)
		assert(Recipes.get(5) == nil and Recipes.get(nil) == nil and Recipes.get("Regal01") == nil)
		assert(Recipes.hasStage(TISCH, "Rohtisch") and not Recipes.hasStage(TISCH, "Rohhocker")
			and Recipes.hasStage(HOCKER, "Rohhocker") and not Recipes.hasStage(HOCKER, "Rohtisch"))
		assert(table.concat(Recipes.acceptedStages("Montage", "Output"), ",") == "Rohhocker,Rohtisch")
		assert(table.concat(Recipes.acceptedStages("Finish", "Input"), ",") == "Rohhocker,Rohtisch")
		assert(table.concat(Recipes.acceptedStages("Saege", "Input"), ",") == "Holzpaket")
		assert(table.concat(Recipes.acceptedStages("Packen", "Output"), ",") == "Karton")
	end)

	test("02 batches carry their recipe; a stage outside the recipe's chain is invalid", function()
		local p = profile()
		p.batches.tisch = State.newBatch("tisch", 101, "Rohtisch", "Finish.Input", TISCH)
		p.batches.hocker = State.newBatch("hocker", 101, "Rohhocker", "Montage.Output")
		assert(p.batches.tisch.recipeId == TISCH and p.batches.tisch.recipeVersion == 1 and p.batches.hocker.recipeId == HOCKER)
		assert(State.validate(p))
		assert(not pcall(State.newBatch, "x", 101, "Rohtisch", "Finish.Input"), "Rohtisch belongs to the table only")
		assert(not pcall(State.newBatch, "x", 101, "Rohhocker", "Finish.Input", TISCH))
		assert(not pcall(State.newBatch, "x", 101, "Holzpaket", "Saege.Input", "Regal01"))
		local function broken(change: (any) -> ()): string?
			local q = copy(p)
			change(q)
			local ok, code = State.validate(q)
			return if ok then nil else code
		end
		assert(broken(function(q: any) q.batches.tisch.stage = "Rohhocker" end) ~= nil)
		assert(broken(function(q: any) q.batches.hocker.stage = "Rohtisch" end) ~= nil)
		assert(broken(function(q: any) q.batches.tisch.recipeId = "Regal01" end) == "INVALID_RECIPE_STAGE")
		assert(broken(function(q: any) q.batches.tisch.recipeVersion = 2 end) == "INVALID_RECIPE_STAGE")
		assert(broken(function(q: any) q.batches.hocker.recipeId = TISCH end) ~= nil, "A table cannot sit at the raw stool stage")
	end)

	test("03 the default station rules stay; ruleFor answers the times of each recipe", function()
		assert(#State.STATIONS == 4 and State.STATIONS[2].durationSeconds == 8 and State.STATIONS[2].outputStage == "Rohhocker")
		local rule = State.ruleFor("Montage", TISCH)
		assert(rule and rule.durationSeconds == 14 and rule.inputStage == "Bausatz" and rule.outputStage == "Rohtisch"
			and rule.input == "Montage.Input" and rule.output == "Montage.Output" and table.isfrozen(rule))
		assert(State.ruleFor("Montage", HOCKER) ~= nil and State.ruleFor("Montage", "Regal01") == nil
			and State.ruleFor("Lackierer", TISCH) == nil)
	end)

	test("04 a profile selecting the table loads; an unknown recipe or a wrong version does not", function()
		local base = {profileVersion = 1, state = profile(), progress = {version = 1, selectedRecipeId = TISCH, selectedRecipeVersion = 1}}
		local function load(data: any): any return Profiles.load(101, function(_: string): any return copy(data) end) end
		local ok = load(base)
		assert(ok.ok and ok.data.progress.selectedRecipeId == TISCH, ok.code)
		for _, change in {
			function(d: any) d.progress.selectedRecipeId = "Regal01" end,
			function(d: any) d.progress.selectedRecipeVersion = 2 end,
			function(d: any) d.progress.selectedRecipeId = 7 end,
			function(d: any) d.progress.selectedRecipeId = nil end,
		} do
			local data = copy(base)
			change(data)
			assert(load(data).code == "INVALID_PROGRESS")
		end
		assert(Profiles.load(101, function(_: string): any return nil end).data.progress.selectedRecipeId == HOCKER,
			"A new profile starts with the first recipe")
	end)

	test("05 one table batch runs through all four stations with the table's own times and stages", function()
		local p = profile()
		p.batches.t = State.newBatch("t", 101, "Holzpaket", "Saege.Input", TISCH)
		local h = harness(p, TISCH)
		assert(h.tick(0) == "Saege:STARTED")
		assert(h.state().reservations["Saege.Output"].finishAt == h.now + 8)
		assert(h.tick(7) == "" and h.tick(1) == "Saege:FINISHED")
		assert(h.state().batches.t.stage == "Bausatz" and h.state().batches.t.recipeId == TISCH)
		h.carry("t", "Saege.Output", "Montage.Input", "m1")
		assert(h.tick(0) == "Montage:STARTED")
		assert(h.state().reservations["Montage.Output"].finishAt == h.now + 14)
		assert(h.tick(13) == "" and h.tick(1) == "Montage:FINISHED")
		assert(h.state().batches.t.stage == "Rohtisch" and h.state().batches.t.locationId == "Montage.Output")
		h.carry("t", "Montage.Output", "Finish.Input", "f1")
		assert(h.tick(0) == "Finish:STARTED" and h.tick(7) == "" and h.tick(1) == "Finish:FINISHED")
		assert(h.state().batches.t.stage == "Fertig" and h.state().batches.t.locationId == "Finish.Output")
		h.carry("t", "Finish.Output", "Packen.Input", "p1")
		assert(h.tick(0) == "Packen:STARTED" and h.tick(4) == "" and h.tick(1) == "Packen:FINISHED")
		local done = h.state().batches.t
		assert(done.stage == "Karton" and done.locationId == "Packen.Output" and done.recipeId == TISCH and done.quantity == 1)
		assert(State.validate(h.state()) and h.state().money == 200)
	end)

	test("06 the saw refuses a package of another recipe than the selected one and writes nothing", function()
		local p = profile()
		p.batches.t = State.newBatch("t", 101, "Holzpaket", "Saege.Input", TISCH)
		local h = harness(p, HOCKER)
		local writes, before = h.writes, h.state()
		unchanged(h, "WRONG_RECIPE", Stations.start(h.c, "Saege", h.now, 600))
		assert(h.tick(0) == "" and h.writes == writes and equal(h.state(), before))
		local status = Line.status(h.state(), h.now, false, HOCKER).Saege
		assert(status.code == "WRONG_RECIPE" and status.needed == HOCKER and status.recipeId == TISCH and status.inputWaiting)
		local free = Line.status(h.state(), h.now, false).Saege
		assert(free.code == "READY", "Without a selection the saw takes any recipe")
		-- Choosing the package's own recipe is allowed and starts the run.
		local chosen = h.select(TISCH)
		assert(chosen.ok and chosen.code == "SELECTED", chosen.code)
		assert(h.tick(0) == "Saege:STARTED")
	end)

	test("07 the choice is stored with the revision and survives a new session", function()
		local h = harness(profile(), HOCKER)
		local revision = h.state().revision
		local chosen = h.select(TISCH)
		assert(chosen.ok and chosen.code == "SELECTED" and chosen.recipeId == TISCH and chosen.message ~= "")
		assert(h.progress().selectedRecipeId == TISCH and h.progress().selectedRecipeVersion == 1)
		assert(h.state().revision == revision + 1 and State.validate(h.state()))
		h.now += 700
		local again = h.controller("session/2")
		assert(again.snapshot().confirmed.data.progress.selectedRecipeId == TISCH, "The new session sees the choice")
		local writes = h.writes
		local same = RecipeChoice.select(again, 101, again.snapshot().confirmed.data.state.revision, TISCH, h.now, 600)
		assert(same.ok and same.code == "ALREADY_SELECTED" and h.writes == writes)
		local back = RecipeChoice.select(again, 101, again.snapshot().confirmed.data.state.revision, HOCKER, h.now, 600)
		assert(back.ok and back.code == "SELECTED" and again.snapshot().confirmed.data.progress.selectedRecipeId == HOCKER)
	end)

	test("08 rejected choices change nothing and name their reason", function()
		local h = harness(profile(), HOCKER)
		local writes, before = h.writes, h.state()
		local revision = before.revision
		assert(RecipeChoice.select(h.c, 101, revision, "Regal01", h.now, 600).code == "UNKNOWN_RECIPE")
		assert(RecipeChoice.select(h.c, 101, revision, 5, h.now, 600).code == "UNKNOWN_RECIPE")
		assert(RecipeChoice.select(h.c, 101, revision + 1, TISCH, h.now, 600).code == "STALE_REVISION")
		assert(RecipeChoice.select(h.c, 202, revision, TISCH, h.now, 600).code == "NOT_AUTHORIZED")
		assert(RecipeChoice.select(h.c, 101, "x", TISCH, h.now, 600).code == "INVALID_REQUEST")
		assert(RecipeChoice.select(h.c, 101, -1, TISCH, h.now, 600).code == "INVALID_REQUEST")
		assert(RecipeChoice.select(h.c, 101, revision, TISCH, nil, 600).code == "INVALID_REQUEST")
		assert(RecipeChoice.select(h.c, 101, revision, HOCKER, h.now, 600).code == "ALREADY_SELECTED")
		assert(h.writes == writes and equal(h.state(), before) and h.progress().selectedRecipeId == HOCKER)
		h.drop = true
		local lost = h.select(TISCH)
		assert(not lost.ok and lost.code == "SAVE_FAILED" and lost.unknown)
		assert(RecipeChoice.select(h.c, 101, revision, TISCH, h.now, 600).code == "NOT_CONFIRMED", "An unclear save blocks the next change")
	end)

	test("09 a package of the old recipe at the saw input blocks the switch; its own recipe and expired claims do not", function()
		-- Waiting package.
		local p = profile()
		p.batches.w = State.newBatch("w", 101, "Holzpaket", "Saege.Input", HOCKER)
		local h = harness(p, HOCKER)
		local writes = h.writes
		unchanged(h, "INPUT_OCCUPIED", h.select(TISCH))
		assert(h.writes == writes and h.progress().selectedRecipeId == HOCKER)
		-- Return reservation while the package is carried.
		local q = profile()
		q.batches.w = State.newBatch("w", 101, "Holzpaket", "Saege.Input", HOCKER)
		local h2 = harness(q, HOCKER)
		local store = h2.store()
		h2.move(store, "w", "Saege.Input", HAND, "take")
		h2.save(store)
		assert(h2.state().reservations["Saege.Input"].kind == "Return")
		unchanged(h2, "INPUT_OCCUPIED", h2.select(TISCH))
		-- A live claim moving a package to the input.
		local r = profile()
		r.batches.w = State.newBatch("w", 101, "Holzpaket", "RawStore.Slot1", HOCKER)
		local h3 = harness(r, HOCKER)
		local claimStore = h3.store()
		h3.move(claimStore, "w", "RawStore.Slot1", HAND, "take3")
		local reserved = Transfers.reserve(claimStore, ACTOR, {operationId = "c1", expectedRevision = claimStore.profile.revision,
			batchId = "w", sourceId = HAND, targetId = "Saege.Input", quantity = 1}, h3.now, 5)
		assert(reserved.ok, reserved.code)
		h3.save(claimStore)
		unchanged(h3, "INPUT_OCCUPIED", h3.select(TISCH))
		h3.now += 6
		local expired = h3.select(TISCH)
		assert(expired.ok and expired.code == "SELECTED", "An expired claim does not hold the choice: " .. expired.code)
		-- The package already belongs to the recipe being chosen.
		local s = profile()
		s.batches.t = State.newBatch("t", 101, "Holzpaket", "Saege.Input", TISCH)
		local h4 = harness(s, HOCKER)
		assert(h4.select(TISCH).ok and h4.progress().selectedRecipeId == TISCH)
	end)

	test("10 a workshop whose places only know the first recipe cannot select the table", function()
		local h = harness(profile(true), HOCKER)
		local writes = h.writes
		unchanged(h, "LAYOUT_UNSUPPORTED", h.select(TISCH))
		assert(h.writes == writes and h.progress().selectedRecipeId == HOCKER)
	end)

	test("11 switching during a started saw run keeps both recipes apart through the whole line", function()
		local p = profile()
		p.batches.hw = State.newBatch("hw", 101, "Holzpaket", "Saege.Input", HOCKER)
		local h = harness(p, HOCKER)
		assert(h.tick(0) == "Saege:STARTED")
		local running = h.select(TISCH)
		assert(running.ok and running.code == "SELECTED", "A started run does not block the choice: " .. running.code)
		assert(h.state().batches.hw.locationId == "Saege.Process" and h.state().reservations["Saege.Output"].batchId == "hw")
		-- The new package waits at the saw input while the old run still works.
		local store = h.store()
		store.profile.batches.tw = State.newBatch("tw", 101, "Holzpaket", "Saege.Input", TISCH)
		store.profile.revision += 1
		h.save(store)
		assert(h.tick(5) == "")
		assert(h.tick(1) == "Saege:FINISHED", "The old run ends after its own 6 s")
		assert(h.state().batches.hw.stage == "Bausatz" and h.state().batches.hw.recipeId == HOCKER)
		assert(h.state().batches.tw.locationId == "Saege.Input", "The table package waits until the output is free")
		h.carry("hw", "Saege.Output", "Montage.Input", "m")
		assert(h.tick(0) == "Saege:STARTED,Montage:STARTED")
		local both = h.state()
		assert(both.reservations["Saege.Output"].batchId == "tw" and both.reservations["Saege.Output"].finishAt == h.now + 8,
			"The table package takes the table's 8 s at the saw, not the stool's 6 s")
		assert(both.reservations["Montage.Output"].batchId == "hw" and both.reservations["Montage.Output"].finishAt == h.now + 8,
			"The old batch keeps the stool time at assembly, not the table's 14 s")
		assert(h.tick(8) == "Saege:FINISHED,Montage:FINISHED")
		assert(h.state().batches.tw.stage == "Bausatz" and h.state().batches.tw.recipeId == TISCH)
		assert(h.state().batches.hw.stage == "Rohhocker" and h.state().batches.hw.recipeId == HOCKER)
		h.carry("hw", "Montage.Output", "Finish.Input", "f")
		h.carry("tw", "Saege.Output", "Montage.Input", "m2")
		assert(h.tick(0) == "Montage:STARTED,Finish:STARTED")
		local state = h.state()
		assert(state.reservations["Finish.Output"].finishAt == h.now + 6 and state.reservations["Montage.Output"].finishAt == h.now + 14)
		assert(h.tick(6) == "Finish:FINISHED" and h.state().batches.hw.stage == "Fertig")
		assert(h.tick(8) == "Montage:FINISHED" and h.state().batches.tw.stage == "Rohtisch")
		local final = h.state()
		assert(final.batches.hw.recipeId == HOCKER and final.batches.tw.recipeId == TISCH and State.validate(final))
	end)

	test("12 a purchase follows the selected recipe in package, price and message", function()
		local h = harness(profile(), TISCH)
		h.state()
		local start = h.state().revision
		local bought = Purchases.buy(h.c, ACTOR, {operationId = "buy/1", expectedRevision = start}, SLOTS, 600)
		assert(bought.ok and bought.receipt.price == 80, bought.code)
		assert(bought.receipt.message == "Tischholzpaket beim Lieferanten bereit.")
		local state = h.state()
		assert(state.money == 120 and state.batches["purchase/buy/1"].recipeId == TISCH
			and state.batches["purchase/buy/1"].stage == "Holzpaket" and State.validate(state))
		local writes = h.writes
		local replay = Purchases.buy(h.c, ACTOR, {operationId = "buy/1", expectedRevision = start}, SLOTS, 600)
		assert(replay.ok and replay.receipt.price == 80 and h.writes == writes and h.state().money == 120)
		-- Hocker price after the switch back; the package still waiting stays a table package.
		local poor = harness((function() local q = profile(); q.money = 79; return q end)(), TISCH)
		assert(Purchases.buy(poor.c, ACTOR, {operationId = "b", expectedRevision = poor.state().revision}, SLOTS, 600).code == "NOT_ENOUGH_MONEY")
		local cheap = harness((function() local q = profile(); q.money = 60; return q end)(), HOCKER)
		local stool = Purchases.buy(cheap.c, ACTOR, {operationId = "b", expectedRevision = cheap.state().revision}, SLOTS, 600)
		assert(stool.ok and stool.receipt.price == 60 and stool.receipt.message == "Holzpaket beim Lieferanten bereit.")
		assert(cheap.state().money == 0 and cheap.state().batches["purchase/b"].recipeId == HOCKER)
	end)

	test("13 the material advance stays the first recipe's package whatever is selected", function()
		local p = profile()
		p.money = 20
		local h = harness(p, TISCH)
		local granted = Purchases.advance(h.c, ACTOR, {operationId = "adv/1", expectedRevision = h.state().revision}, SLOTS, 600)
		assert(granted.ok and granted.receipt.amount == 60, granted.code)
		local state = h.state()
		assert(state.batches["advance/adv/1"].recipeId == HOCKER and state.advance.amount == 60 and State.validate(state))
	end)

	test("14 buyer values follow the recipe: dealer 140 and a private range of 112 to 168 for the table", function()
		for _, case in {{seed = 0, amount = 112}, {seed = 56, amount = 168}, {seed = 57, amount = 112}} do
			local p = profile()
			p.batches.box = State.newBatch("box", 101, "Karton", B, TISCH)
			local h = harness(p, HOCKER)
			local opened = Sales.open(h.c, ACTOR, {id = "sale/p", buyer = "Private", vehicleId = "Quad1", slotId = B, batchId = "box"},
				h.arrival(B, "box", "Private"), h.now, 600, case.seed)
			assert(opened.ok and opened.offer.quoteMin == 112 and opened.offer.quoteMax == 168 and opened.offer.dealerValue == 140)
			local sold = Sales.settle(h.c, ACTOR, "sale/p", 600)
			assert(sold.ok and sold.receipt.amount == case.amount, tostring(sold.receipt and sold.receipt.amount))
			assert(h.state().money == 200 + case.amount and State.validate(h.state()))
		end
		local p = profile()
		p.batches.box = State.newBatch("box", 101, "Karton", B, TISCH)
		p.batches.old = State.newBatch("old", 101, "Karton", A)
		local h = harness(p, TISCH)
		assert(Sales.open(h.c, ACTOR, {id = "sale/d", buyer = "Dealer", vehicleId = "Quad1", slotId = B, batchId = "box"},
			h.arrival(B, "box", "Dealer"), h.now, 600).ok)
		assert(Sales.settle(h.c, ACTOR, "sale/d", 600).receipt.amount == 140 and h.state().money == 340)
		assert(Sales.open(h.c, ACTOR, {id = "sale/s", buyer = "Dealer", vehicleId = "Quad1", slotId = A, batchId = "old"},
			h.arrival(A, "old", "Dealer"), h.now, 600).offer.dealerValue == 100, "The stool carton still sells for 100")
		assert(Sales.settle(h.c, ACTOR, "sale/s", 600).receipt.amount == 100 and h.state().money == 440)
	end)

	test("15 stock of the old recipe stays assigned after the choice changes back and forth", function()
		local p = profile()
		p.locations["RawStore.Slot2"] = State.newLocation("RawStore.Slot2", "RawStore", 1, {"Holzpaket"})
		p.batches.a = State.newBatch("a", 101, "Holzpaket", "RawStore.Slot1", HOCKER)
		p.batches.b = State.newBatch("b", 101, "Holzpaket", "RawStore.Slot2", TISCH)
		local h = harness(p, HOCKER)
		for _, target in {TISCH, HOCKER, TISCH, HOCKER} do
			local result = h.select(target)
			assert(result.ok and h.progress().selectedRecipeId == target, result.code)
		end
		local state = h.state()
		assert(state.batches.a.recipeId == HOCKER and state.batches.b.recipeId == TISCH and State.validate(state))
		assert(state.revision == 4 and state.money == 200 and next(state.claims) == nil and next(state.reservations) == nil)
	end)

	test("16 station feedback shows the recipe of its batch and, when empty, of the selection", function()
		local p = profile()
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input", TISCH)
		local h = harness(p, HOCKER)
		local empty = Line.status(h.state(), h.now, false, HOCKER)
		assert(empty.Finish.recipeId == HOCKER and empty.Finish.inputStage == "Rohhocker" and empty.Finish.code == "INPUT_MISSING")
		assert(empty.Montage.recipeId == TISCH and empty.Montage.inputWaiting and empty.Montage.outputStage == "Rohtisch")
		local chosen = Line.status(h.state(), h.now, false, TISCH)
		assert(chosen.Finish.recipeId == TISCH and chosen.Finish.inputStage == "Rohtisch" and chosen.Packen.recipeId == TISCH)
		assert(Line.status(h.state(), h.now).Finish.recipeId == HOCKER, "Without a selection the first recipe is shown")
		assert(h.tick(0) == "Montage:STARTED")
		local running = Line.status(h.state(), h.now + 3, false, HOCKER).Montage
		assert(running.code == "RUNNING" and running.recipeId == TISCH and running.remaining == 11 and running.outputStage == "Rohtisch")
	end)

	return {total = #passed + #failures, passed = passed, failures = failures}
end
