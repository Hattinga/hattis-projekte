--!strict
-- P05-05 station-run suite. In-memory atomic backend; no engine or external storage.
return function(State: any, Transfers: any, Persistence: any, Stations: any, Sawmill: any): any
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

	local STAGES = {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"}
	local function profile(): any
		local p = State.newProfile(101)
		p.money = 17
		for i, rule in State.STATIONS do
			p.locations[rule.input] = State.newLocation(rule.input, "StationInput", 1, {STAGES[i]})
			p.locations[rule.process] = State.newLocation(rule.process, "StationProcess", 1, {STAGES[i]})
			p.locations[rule.output] = State.newLocation(rule.output, "StationOutput", 1, {STAGES[i + 1]})
		end
		p.locations.hand = State.newLocation("hand", "Carrier", 1, STAGES)
		return p
	end
	local function harness(state: any): any
		local h: any = {now = 1000, writes = 0, drop = false, value = nil}
		h.backend = {
			read = function(_: string): any return copy(h.value) end,
			update = function(_: string, transform: any): any
				h.writes += 1
				local proposed = transform(copy(h.value))
				if proposed ~= nil then h.value = copy(proposed) end
				if h.drop then h.drop = false; error("simulated lost station reply") end
				return copy(proposed)
			end,
		}
		function h.controller(token: string): any
			local c = Persistence.new(101, h.backend, function(): number return h.now end)
			local loaded = c.load(token, 600, function(): any
				return {profileVersion = 1, state = copy(state),
					progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
			end)
			assert(loaded.ok, loaded.code)
			return c
		end
		h.c = h.controller("session/1")
		function h.state(): any return h.c.snapshot().confirmed.data.state end
		function h.store(): any return Transfers.new(h.state()) end
		function h.save(store: any)
			local data = h.c.snapshot().confirmed.data
			data.state = store.profile
			assert(h.c.save(data, 600).ok)
		end
		local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "hand", ready = true}
		function h.move(store: any, batchId: string, from: string, to: string, id: string)
			local reserved = Transfers.reserve(store, actor, {operationId = id .. "/r", expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, h.now, 5)
			assert(reserved.ok, reserved.code)
			local committed = Transfers.commit(store, actor, {operationId = id .. "/c",
				expectedRevision = store.profile.revision, claimId = id .. "/r"}, h.now)
			assert(committed.ok, committed.code)
		end
		function h.reserve(store: any, batchId: string, from: string, to: string, id: string): any
			return Transfers.reserve(store, actor, {operationId = id, expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, h.now, 5)
		end
		return h
	end
	local function unchanged(h: any, code: string, result: any)
		assert(result.code == code and not result.ok, "expected " .. code .. " got " .. tostring(result.code))
	end

	test("01 four frozen station rules chain the five Hocker01 stages", function()
		assert(#State.STATIONS == 4 and table.isfrozen(State.STATIONS) and State.SAW == State.STATIONS[1])
		local durations = {6, 8, 6, 4}
		local ids = {"Saege", "Montage", "Finish", "Packen"}
		for i, rule in State.STATIONS do
			assert(table.isfrozen(rule) and rule.id == ids[i] and rule.durationSeconds == durations[i])
			assert(rule.inputStage == STAGES[i] and rule.outputStage == STAGES[i + 1])
			assert(rule.input == ids[i] .. ".Input" and rule.process == ids[i] .. ".Process" and rule.output == ids[i] .. ".Output")
			assert(State.STATION_BY_ID[ids[i]] == rule)
		end
		assert(State.validate(profile()))
	end)

	test("02 unknown station, missing input and invalid time never write", function()
		local h = harness(profile())
		local writes = h.writes
		unchanged(h, "UNKNOWN_STATION", Stations.start(h.c, "Lackierer", h.now, 600))
		unchanged(h, "UNKNOWN_STATION", Stations.finish(h.c, "Lackierer", "x", h.now, 600))
		unchanged(h, "INPUT_REQUIRED", Stations.start(h.c, "Montage", h.now, 600))
		unchanged(h, "INVALID_TIME", Stations.start(h.c, "Montage", 0.5, 600))
		unchanged(h, "NO_ACTIVE_RUN", Stations.finish(h.c, "Montage", "x", h.now, 600))
		assert(h.writes == writes)
	end)

	test("03 assembly reserves its output, keeps the kit in work and yields one raw stool after 8 s", function()
		local p = profile()
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		local before = copy(h.state().batches.kit)
		local started = Stations.start(h.c, "Montage", h.now, 600)
		assert(started.ok and started.code == "STARTED" and started.batchId == "kit" and started.finishAt == h.now + 8)
		local working = h.state()
		assert(working.batches.kit.locationId == "Montage.Process" and working.batches.kit.stage == "Bausatz")
		assert(equal(working.reservations["Montage.Output"], {kind = "Production", batchId = "kit", finishAt = h.now + 8}))
		assert(State.validate(working) and State.countAt(working, "Montage.Output") == 0)
		unchanged(h, "ALREADY_RUNNING", Stations.start(h.c, "Montage", h.now, 600))
		h.now += 7
		unchanged(h, "RUNNING", Stations.finish(h.c, "Montage", "kit", h.now, 600))
		unchanged(h, "STALE_RUN", Stations.finish(h.c, "Montage", "other", h.now + 1, 600))
		unchanged(h, "NO_ACTIVE_RUN", Stations.finish(h.c, "Saege", "kit", h.now + 1, 600))
		h.now += 1
		local done = Stations.finish(h.c, "Montage", "kit", h.now, 600)
		assert(done.ok and done.code == "FINISHED")
		local final = h.state()
		local stool = final.batches.kit
		assert(stool.locationId == "Montage.Output" and stool.stage == "Rohhocker" and not final.reservations["Montage.Output"])
		assert(stool.id == before.id and stool.ownerUserId == before.ownerUserId and stool.recipeId == before.recipeId
			and stool.recipeVersion == before.recipeVersion and stool.quantity == 1)
		assert(final.money == 17 and State.validate(final))
		local writes = h.writes
		unchanged(h, "NO_ACTIVE_RUN", Stations.finish(h.c, "Montage", "kit", h.now, 600))
		assert(h.writes == writes)
	end)

	test("04 saw and assembly run side by side without touching each other's run", function()
		local p = profile()
		p.batches.wood = State.newBatch("wood", 101, "Holzpaket", "Saege.Input")
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		assert(Sawmill.start(h.c, h.now, 600).ok)
		assert(Stations.start(h.c, "Montage", h.now, 600).ok)
		local both = h.state()
		assert(State.validate(both) and both.reservations["Saege.Output"].batchId == "wood"
			and both.reservations["Montage.Output"].batchId == "kit")
		unchanged(h, "STALE_RUN", Stations.finish(h.c, "Saege", "kit", h.now + 8, 600))
		unchanged(h, "STALE_RUN", Sawmill.finish(h.c, "kit", h.now + 8, 600))
		h.now += 6
		assert(Sawmill.finish(h.c, "wood", h.now, 600).ok)
		unchanged(h, "RUNNING", Stations.finish(h.c, "Montage", "kit", h.now, 600))
		h.now += 2
		assert(Stations.finish(h.c, "Montage", "kit", h.now, 600).ok)
		local final = h.state()
		assert(final.batches.wood.locationId == "Saege.Output" and final.batches.wood.stage == "Bausatz")
		assert(final.batches.kit.locationId == "Montage.Output" and final.batches.kit.stage == "Rohhocker")
	end)

	test("05 validation binds every production lock to its own station and running batch", function()
		local function rejected(change: (any) -> (), code: string)
			local p = profile()
			p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Process")
			p.reservations["Montage.Output"] = {kind = "Production", batchId = "kit", finishAt = 1008}
			assert(State.validate(p))
			change(p)
			local ok, reason = State.validate(p)
			assert(not ok and reason == code, code .. " got " .. tostring(reason))
		end
		rejected(function(p) p.reservations["Montage.Output"] = nil end, "MISSING_PRODUCTION_RESERVATION")
		rejected(function(p) p.reservations["Montage.Output"].finishAt = 7 end, "INVALID_PRODUCTION_RESERVATION")
		rejected(function(p) p.reservations["Montage.Output"].extra = true end, "INVALID_PRODUCTION_RESERVATION")
		rejected(function(p)
			p.batches.kit.locationId = "Saege.Process"; p.batches.kit.stage = "Holzpaket"
		end, "INVALID_PRODUCTION_RESERVATION")
		rejected(function(p)
			p.reservations["Finish.Output"] = p.reservations["Montage.Output"]
			p.reservations["Montage.Output"] = nil
		end, "INVALID_PRODUCTION_RESERVATION")
		rejected(function(p)
			p.locations.shelf = State.newLocation("shelf", "FinishedStore", 1, {"Karton"})
			p.reservations.shelf = {kind = "Production", batchId = "kit", finishAt = 1008}
		end, "INVALID_PRODUCTION_RESERVATION")
	end)

	test("06 a waiting raw stool blocks the next run and leaves the next kit unconsumed", function()
		local p = profile()
		p.batches.stool = State.newBatch("stool", 101, "Rohhocker", "Montage.Output")
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		local writes = h.writes
		unchanged(h, "OUTPUT_BLOCKED", Stations.start(h.c, "Montage", h.now, 600))
		assert(h.writes == writes and h.state().batches.kit.locationId == "Montage.Input")
		local store = h.store()
		h.move(store, "stool", "Montage.Output", "hand", "take-stool")
		h.save(store)
		unchanged(h, "OUTPUT_BLOCKED", Stations.start(h.c, "Montage", h.now, 600))
		assert(h.state().reservations["Montage.Output"].kind == "Return")
		store = h.store()
		h.move(store, "stool", "hand", "Finish.Input", "place-stool")
		h.save(store)
		local next = Stations.start(h.c, "Montage", h.now, 600)
		assert(next.ok and next.batchId == "kit")
		assert(h.state().batches.stool.locationId == "Finish.Input" and h.state().batches.stool.stage == "Rohhocker")
	end)

	test("07 a returned stool takes back its output and still blocks until it leaves", function()
		local p = profile()
		p.batches.stool = State.newBatch("stool", 101, "Rohhocker", "Montage.Output")
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		local store = h.store()
		h.move(store, "stool", "Montage.Output", "hand", "take")
		h.move(store, "stool", "hand", "Montage.Output", "return")
		h.save(store)
		local state = h.state()
		assert(state.batches.stool.locationId == "Montage.Output" and not state.reservations["Montage.Output"])
		unchanged(h, "OUTPUT_BLOCKED", Stations.start(h.c, "Montage", h.now, 600))
	end)

	test("08 an active input claim blocks the start; an expired one is swept in the same save", function()
		local p = profile()
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		local store = h.store()
		local claim = h.reserve(store, "kit", "Montage.Input", "hand", "hold")
		assert(claim.ok)
		h.save(store)
		local writes = h.writes
		unchanged(h, "SLOT_RESERVED", Stations.start(h.c, "Montage", h.now, 600))
		assert(h.writes == writes)
		h.now = claim.expiresAt
		local started = Stations.start(h.c, "Montage", h.now, 600)
		assert(started.ok and not h.state().claims.hold and h.state().receipts.hold)
		assert(State.validate(h.state()))
	end)

	test("09 a lost start reply locks the station until reconciliation proves exactly one run", function()
		local p = profile()
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		h.drop = true
		local pending = Stations.start(h.c, "Montage", h.now, 600)
		assert(not pending.ok and pending.unknown and pending.code == "WRITE_UNKNOWN")
		assert(h.c.snapshot().confirmed.data.state.batches.kit.locationId == "Montage.Input")
		local writes = h.writes
		unchanged(h, "NOT_CONFIRMED", Stations.start(h.c, "Montage", h.now, 600))
		unchanged(h, "NOT_CONFIRMED", Stations.finish(h.c, "Montage", "kit", h.now + 8, 600))
		assert(h.writes == writes)
		assert(h.c.reconcile().ok)
		local state = h.state()
		assert(state.batches.kit.locationId == "Montage.Process" and state.reservations["Montage.Output"].batchId == "kit")
		unchanged(h, "ALREADY_RUNNING", Stations.start(h.c, "Montage", h.now, 600))
	end)

	test("10 a lost finish reply reconciles to one raw stool and no second completion", function()
		local p = profile()
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		assert(Stations.start(h.c, "Montage", h.now, 600).ok)
		h.now += 8
		h.drop = true
		local pending = Stations.finish(h.c, "Montage", "kit", h.now, 600)
		assert(not pending.ok and pending.unknown)
		assert(h.c.reconcile().ok)
		local state = h.state()
		assert(state.batches.kit.stage == "Rohhocker" and state.batches.kit.locationId == "Montage.Output")
		unchanged(h, "NO_ACTIVE_RUN", Stations.finish(h.c, "Montage", "kit", h.now, 600))
		assert(State.countAt(state, "Montage.Output") == 1)
	end)

	test("11 a fresh session resumes the stored run with its original finish time", function()
		local p = profile()
		p.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		local h = harness(p)
		local started = Stations.start(h.c, "Montage", h.now, 600)
		assert(h.c.release().ok)
		h.c = h.controller("session/2")
		unchanged(h, "ALREADY_RUNNING", Stations.start(h.c, "Montage", h.now, 600))
		unchanged(h, "RUNNING", Stations.finish(h.c, "Montage", "kit", started.finishAt - 1, 600))
		h.now = started.finishAt
		assert(Stations.finish(h.c, "Montage", "kit", h.now, 600).ok)
	end)

	test("12 the saw wrapper keeps its P05-04 contract", function()
		local p = profile()
		p.batches.wood = State.newBatch("wood", 101, "Holzpaket", "Saege.Input")
		local h = harness(p)
		local started = Sawmill.start(h.c, h.now, 600)
		assert(started.ok and started.finishAt == h.now + 6)
		unchanged(h, "RUNNING", Sawmill.finish(h.c, "wood", h.now + 5, 600))
		assert(Sawmill.finish(h.c, "wood", h.now + 6, 600).ok)
		assert(h.state().batches.wood.stage == "Bausatz")
	end)

	return {total = #passed + #failures, passed = passed, failures = failures}
end
