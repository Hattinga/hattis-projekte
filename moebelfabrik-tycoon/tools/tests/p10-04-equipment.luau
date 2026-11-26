--!strict
-- P10-04 equipment suite: the assembly jig as the first purchasable equipment, its price and benefit before the purchase,
-- the confirmed purchase, the effect on station run times, saved ownership and the material supply after a high spend.
-- In-memory atomic backend; no engine, remotes or external storage.
return function(State: any, Persistence: any, Stations: any, Line: any, Purchases: any, Recipes: any, Profiles: any,
	Equipment: any, Overview: any): any
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

	local HOCKER, TISCH, JIG = "Hocker01", "Beistelltisch01", "Montagevorrichtung"
	local ALL_STAGES = {"Holzpaket", "Bausatz", "Rohhocker", "Rohtisch", "Fertig", "Karton"}
	local HAND = "hand"
	local ACTOR = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = HAND, ready = true}
	local SLOTS = {supplierIds = {"Supplier.Slot1"}, rawIds = {"RawStore.Slot1"}}
	local function profile(money: number): any
		local p = State.newProfile(101)
		p.money = money
		for _, rule in State.STATIONS do
			p.locations[rule.input] = State.newLocation(rule.input, "StationInput", 1, Recipes.acceptedStages(rule.id, "Input"))
			p.locations[rule.process] = State.newLocation(rule.process, "StationProcess", 1, Recipes.acceptedStages(rule.id, "Input"))
			p.locations[rule.output] = State.newLocation(rule.output, "StationOutput", 1, Recipes.acceptedStages(rule.id, "Output"))
		end
		p.locations[HAND] = State.newLocation(HAND, "Carrier", 1, ALL_STAGES)
		p.locations["Supplier.Slot1"] = State.newLocation("Supplier.Slot1", "Supplier", 1, {"Holzpaket"})
		p.locations["RawStore.Slot1"] = State.newLocation("RawStore.Slot1", "RawStore", 1, {"Holzpaket"})
		p.locations["FinishedStore.Slot1"] = State.newLocation("FinishedStore.Slot1", "FinishedStore", 1, {"Karton"})
		return p
	end
	local function harness(state: any, progressOverride: any?): any
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
				return {profileVersion = 1, state = copy(state),
					progress = progressOverride or {version = 1, selectedRecipeId = HOCKER, selectedRecipeVersion = 1}}
			end)
			assert(loaded.ok, loaded.code)
			return c
		end
		h.c = h.controller("session/1")
		function h.state(): any return h.c.snapshot().confirmed.data.state end
		function h.progress(): any return h.c.snapshot().confirmed.data.progress end
		function h.buy(id: any?): any return Equipment.buy(h.c, 101, h.state().revision, id or JIG, 600) end
		function h.tick(seconds: number): string
			h.now += seconds
			return codes(Line.tick(h.c, h.now, 600))
		end
		return h
	end
	-- A batch waiting at the assembly input.
	local function kitAtAssembly(money: number, recipeId: string): any
		local p = profile(money)
		p.batches.k = State.newBatch("k", 101, "Bausatz", "Montage.Input", recipeId)
		return p
	end

	test("01 the equipment list is frozen and every item shortens every recipe by whole seconds", function()
		assert(table.isfrozen(Equipment) and table.isfrozen(Equipment.LIST) and #Equipment.LIST == 1)
		local jig = Equipment.get(JIG)
		assert(jig and jig.price == 150 and jig.stationId == "Montage" and table.isfrozen(jig) and table.isfrozen(jig.seconds))
		for _, recipe in Recipes.LIST do
			local base = Recipes.timing(recipe.id, "Montage").durationSeconds
			assert(jig.seconds[recipe.id] < base and jig.seconds[recipe.id] % 1 == 0 and jig.seconds[recipe.id] > 0)
		end
		assert(Equipment.get("Regal") == nil and Equipment.get(5) == nil and Equipment.get(nil) == nil)
		assert(not Equipment.owned(nil, JIG) and not Equipment.owned({}, JIG) and not Equipment.owned({equipment = 5}, JIG))
		assert(Equipment.owned({equipment = {[JIG] = {revision = 1, price = 150}}}, JIG))
	end)

	test("02 the offer names price, benefit per recipe, the pace before and after, and what is left", function()
		local progress = {version = 1, selectedRecipeId = HOCKER, selectedRecipeVersion = 1}
		local offer = Equipment.offer(progress, 180, HOCKER, 60)
		assert(offer and offer.id == JIG and offer.price == 150 and offer.canAfford and offer.remaining == 30)
		assert(offer.benefit == "Montagebank: Hocker von 8 auf 6 s, Beistelltisch von 14 auf 10 s", offer.benefit)
		assert(offer.pace == "Takt Hocker: von 8 auf 6 s", offer.pace)
		assert(Equipment.offer(progress, 180, TISCH, 60).pace == "Takt Beistelltisch: von 14 auf 10 s")
		assert(offer.aftermath and offer.aftermath:find("Danach reicht das Guthaben (30) nicht für Holz (60)", 1, true), offer.aftermath)
		assert(Equipment.offer(progress, 300, HOCKER, 60).aftermath == nil, "Enough is left for wood")
		-- Exactly one package is left: no warning, one less: warning.
		assert(Equipment.offer(progress, 210, HOCKER, 60).aftermath == nil and Equipment.offer(progress, 209, HOCKER, 60).aftermath ~= nil)
		assert(Equipment.offer(progress, 150, HOCKER, 60).canAfford and not Equipment.offer(progress, 149, HOCKER, 60).canAfford)
		assert(Equipment.offer(progress, 100, HOCKER, 60).aftermath == nil, "An offer the player cannot afford needs no aftermath")
		assert(Equipment.offer({equipment = {[JIG] = {revision = 1, price = 150}}}, 500, HOCKER, 60) == nil, "Owned equipment is not offered")
	end)

	test("03 buying takes the price and saves ownership with the revision once", function()
		local h = harness(profile(200))
		local before = h.state()
		local bought = h.buy()
		assert(bought.ok and bought.code == "BOUGHT" and bought.equipmentId == JIG and not bought.unknown, bought.code)
		local state, progress = h.state(), h.progress()
		assert(state.money == 50 and state.revision == before.revision + 1 and State.validate(state))
		assert(progress.equipment[JIG].price == 150 and progress.equipment[JIG].revision == state.revision)
		assert(Equipment.owned(progress, JIG) and h.writes >= 1)
		local again = h.buy()
		assert(again.ok and again.code == "OWNED" and h.state().money == 50 and h.state().revision == state.revision,
			"A second request answers OWNED and charges nothing")
	end)

	test("04 rejected purchases change nothing and name their reason", function()
		local h = harness(profile(149))
		local before, writes = h.state(), h.writes
		local revision = before.revision
		assert(Equipment.buy(h.c, 101, revision, JIG, 600).code == "NOT_ENOUGH_MONEY")
		assert(Equipment.buy(h.c, 101, revision + 1, JIG, 600).code == "STALE_REVISION")
		assert(Equipment.buy(h.c, 202, revision, JIG, 600).code == "NOT_AUTHORIZED")
		assert(Equipment.buy(h.c, 101, revision, "Regal", 600).code == "UNKNOWN_EQUIPMENT")
		assert(Equipment.buy(h.c, 101, revision, 5, 600).code == "INVALID_REQUEST")
		assert(Equipment.buy(h.c, 101, "x", JIG, 600).code == "INVALID_REQUEST")
		assert(Equipment.buy(h.c, 101, -1, JIG, 600).code == "INVALID_REQUEST")
		assert(Equipment.buy(h.c, 101, 0.5, JIG, 600).code == "INVALID_REQUEST")
		assert(h.writes == writes and equal(h.state(), before) and h.progress().equipment == nil)
		local rich = harness(profile(150))
		assert(rich.buy().ok and rich.state().money == 0, "The exact price is enough")
		-- A lost reply leaves the outcome unclear and blocks the next purchase until the save is confirmed again.
		local lost = harness(profile(400))
		lost.drop = true
		local unclear = lost.buy()
		assert(not unclear.ok and unclear.code == "SAVE_FAILED" and unclear.unknown)
		assert(lost.buy().code == "NOT_CONFIRMED", "An unclear save blocks the next purchase")
	end)

	test("05 the jig shortens the assembly run for both recipes and leaves the other stations alone", function()
		for _, case in {{recipe = HOCKER, plain = 8, fitted = 6, stage = "Rohhocker"}, {recipe = TISCH, plain = 14, fitted = 10, stage = "Rohtisch"}} do
			local plain = harness(kitAtAssembly(200, case.recipe))
			assert(plain.tick(0) == "Montage:STARTED" and plain.state().reservations["Montage.Output"].finishAt == plain.now + case.plain)
			local fitted = harness(kitAtAssembly(200, case.recipe))
			assert(fitted.buy().ok)
			assert(fitted.tick(0) == "Montage:STARTED" and fitted.state().reservations["Montage.Output"].finishAt == fitted.now + case.fitted)
			assert(fitted.tick(case.fitted - 1) == "" and fitted.tick(1) == "Montage:FINISHED", "The shorter run finishes in time")
			assert(fitted.state().batches.k.stage == case.stage and State.validate(fitted.state()))
		end
		-- Unchanged stations keep the recipe's own seconds.
		assert(Equipment.seconds({equipment = {[JIG] = {revision = 1, price = 150}}}, "Saege", HOCKER, 6) == 6)
		assert(Equipment.seconds({equipment = {[JIG] = {revision = 1, price = 150}}}, "Finish", TISCH, 8) == 8)
		assert(Equipment.seconds({equipment = {[JIG] = {revision = 1, price = 150}}}, "Montage", TISCH, 14) == 10)
		assert(Equipment.seconds(nil, "Montage", TISCH, 14) == 14)
	end)

	test("06 a run that has started keeps its time, the next run uses the jig", function()
		local p = kitAtAssembly(200, HOCKER)
		local h = harness(p)
		assert(h.tick(0) == "Montage:STARTED")
		local finishAt = h.state().reservations["Montage.Output"].finishAt
		assert(finishAt == h.now + 8)
		assert(h.tick(1) == "" and h.buy().ok, "Buying during a run is allowed")
		assert(h.state().reservations["Montage.Output"].finishAt == finishAt, "The running run is not shortened")
		assert(h.tick(5) == "", "Still running after 6 s")
		assert(h.tick(2) == "Montage:FINISHED")
		assert(h.state().batches.k.stage == "Rohhocker")
	end)

	test("07 owned equipment survives a new session and an invalid record does not load", function()
		local h = harness(kitAtAssembly(200, HOCKER))
		assert(h.buy().ok)
		h.now += 700 -- the first session's lease has run out
		local again = h.controller("session/2")
		assert(Equipment.owned(again.snapshot().confirmed.data.progress, JIG))
		local base = {profileVersion = 1, state = profile(100), progress = {version = 1, selectedRecipeId = HOCKER, selectedRecipeVersion = 1}}
		base.state.revision = 5
		local function load(data: any): any return Profiles.load(101, function(_: string): any return copy(data) end) end
		local good = copy(base)
		good.progress.equipment = {[JIG] = {revision = 3, price = 150}}
		assert(load(good).ok, load(good).code)
		for _, change in {
			function(d: any) d.progress.equipment = 5 end,
			function(d: any) d.progress.equipment = {Regal = {revision = 3, price = 150}} end,
			function(d: any) d.progress.equipment[JIG].revision = 6 end,
			function(d: any) d.progress.equipment[JIG].revision = 0 end,
			function(d: any) d.progress.equipment[JIG].price = 0 end,
			function(d: any) d.progress.equipment[JIG].price = 1.5 end,
			function(d: any) d.progress.equipment[JIG].extra = true end,
			function(d: any) d.progress.equipment[JIG] = "yes" end,
		} do
			local bad = copy(good)
			change(bad)
			assert(load(bad).code == "INVALID_PROGRESS", "An invalid equipment record must not load")
		end
	end)

	test("08 the overview shows the equipment and the faster pace", function()
		local progress = {version = 1, selectedRecipeId = HOCKER, selectedRecipeVersion = 1}
		local owned = {version = 1, selectedRecipeId = HOCKER, selectedRecipeVersion = 1, equipment = {[JIG] = {revision = 1, price = 150}}}
		local function row(overview: any, label: string): string?
			for _, entry in Overview.rows(overview) do if entry.label == label then return entry.value end end
			return nil
		end
		local plain = Overview.compute(profile(200), HOCKER, 1000, false, progress)
		assert(plain.recipe.takt == "Montagebank bestimmt den Takt: 8 s je Hocker." and row(plain, "Ausrüstung") == "keine", plain.recipe.takt)
		local fitted = Overview.compute(profile(200), HOCKER, 1000, false, owned)
		assert(fitted.recipe.takt == "Säge bestimmt den Takt: 6 s je Hocker." and row(fitted, "Ausrüstung") == "Montagevorrichtung", fitted.recipe.takt)
		local table2 = Overview.compute(profile(200), TISCH, 1000, false, owned)
		assert(table2.recipe.takt == "Montagebank bestimmt den Takt: 10 s je Beistelltisch.", table2.recipe.takt)
		assert(Overview.compute(profile(200), HOCKER, 1000).recipe.takt == plain.recipe.takt, "Without progress nothing is owned")
	end)

	test("09 after a high spend the workshop is not stuck: the material advance restarts it", function()
		local h = harness(profile(180))
		assert(h.buy().ok and h.state().money == 30)
		local progress = h.progress()
		local o = Overview.compute(h.state(), HOCKER, h.now, false, progress)
		local item: any = nil
		for _, entry in o.bottlenecks do if entry.code == "NO_MONEY" then item = entry end end
		assert(item and item.severity == "stop" and item.message:find("Materialvorschuss", 1, true), item and item.message)
		local granted = Purchases.advance(h.c, ACTOR, {operationId = "adv/1", expectedRevision = h.state().revision}, SLOTS, 600)
		assert(granted.ok and granted.receipt.amount == 60, granted.code)
		local state = h.state()
		assert(state.money == 30 and state.advance.amount == 60 and state.batches["advance/adv/1"].stage == "Holzpaket" and State.validate(state))
		assert(Equipment.owned(h.progress(), JIG), "The advance keeps the equipment")
		local after = Overview.compute(state, HOCKER, h.now, false, h.progress())
		for _, entry in after.bottlenecks do assert(entry.code ~= "NO_MONEY" and entry.code ~= "NO_WOOD", entry.code) end
	end)

	return {total = #passed + #failures, passed = passed, failures = failures}
end
