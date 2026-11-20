--!strict
-- P07-07 material advance suite. In-memory atomic backend; no engine, remotes or external storage.
return function(State: any, Transfers: any, Persistence: any, Purchases: any, Sales: any): any
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

	local A, B, HAND = "Vehicle.Quad1.SlotA", "Vehicle.Quad1.SlotB", "Demo.Hand"
	local SUPPLIER, RAW1, RAW2, SHELF = "Supplier.Slot1", "RawStore.Slot1", "RawStore.Slot2", "FinishedStore.Slot1"
	local SLOTS = {supplierIds = {SUPPLIER}, rawIds = {RAW1, RAW2}}
	local ACTOR = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = HAND, ready = true}
	-- An empty workshop: no wood or ware anywhere.
	local function profile(money: number): any
		local p = State.newProfile(101)
		p.money = money
		p.locations[HAND] = State.newLocation(HAND, "Carrier", 1, {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"})
		p.locations[A] = State.newLocation(A, "VehicleSlot", 1, {"Holzpaket", "Karton"})
		p.locations[B] = State.newLocation(B, "VehicleSlot", 1, {"Holzpaket", "Karton"})
		p.locations[SUPPLIER] = State.newLocation(SUPPLIER, "Supplier", 1, {"Holzpaket"})
		p.locations[RAW1] = State.newLocation(RAW1, "RawStore", 1, {"Holzpaket"})
		p.locations[RAW2] = State.newLocation(RAW2, "RawStore", 1, {"Holzpaket"})
		p.locations[SHELF] = State.newLocation(SHELF, "FinishedStore", 1, {"Karton"})
		return p
	end
	local function harness(state: any): any
		-- drop: the write lands but its reply is lost. lose: the write never lands. during: runs while the save is in flight.
		local h: any = {now = 1000, writes = 0, drop = false, lose = false, during = nil, value = nil}
		h.backend = {
			read = function(_: string): any return copy(h.value) end,
			update = function(_: string, transform: any): any
				h.writes += 1
				if h.lose then h.lose = false; error("simulated write that never landed") end
				local during = h.during
				h.during = nil
				if during then during() end
				local proposed = transform(copy(h.value))
				if proposed ~= nil then h.value = copy(proposed) end
				if h.drop then h.drop = false; error("simulated lost advance reply") end
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
		function h.advance(operationId: string, revision: number?): any
			return Purchases.advance(h.c, ACTOR, {operationId = operationId, expectedRevision = revision or h.state().revision},
				SLOTS, 600)
		end
		function h.buy(operationId: string): any
			return Purchases.buy(h.c, ACTOR, {operationId = operationId, expectedRevision = h.state().revision}, SLOTS, 600)
		end
		function h.save(next: any)
			local data = h.c.snapshot().confirmed.data
			data.state = next
			local saved = h.c.save(data, 600)
			assert(saved.ok, saved.code)
		end
		function h.arrival(slot: string, batchId: string, buyer: string): any
			return {ownerUserId = 101, vehicleId = "Quad1", slotId = slot, batchId = batchId, destination = buyer,
				departedAt = 1, arrivedAt = 2, travelledStuds = 700}
		end
		return h
	end
	local function batchCount(state: any): number
		local count = 0
		for _ in state.batches do count += 1 end
		return count
	end
	local function move(store: any, id: string, from: string, to: string, op: string)
		local reserved = Transfers.reserve(store, ACTOR, {operationId = op .. "/r", expectedRevision = store.profile.revision,
			batchId = id, sourceId = from, targetId = to, quantity = 1}, 1000, 5)
		assert(reserved.ok, op .. ": " .. reserved.code)
		local committed = Transfers.commit(store, ACTOR, {operationId = op .. "/c", expectedRevision = store.profile.revision,
			claimId = op .. "/r"}, 1000)
		assert(committed.ok, op .. ": " .. committed.code)
	end
	-- Supplier pickup -> hand -> promised raw slot, through the ordinary delivery logistics.
	local function deliver(h: any, id: string, rawSlotId: string)
		local store = Transfers.new(h.state())
		move(store, id, SUPPLIER, HAND, id .. "/pick")
		move(store, id, HAND, rawSlotId, id .. "/deliver")
		h.save(store.profile)
	end
	-- Stand-in for the four station runs (they keep the batch ID, see p07-sales test 10), then onto trailer slot B.
	local function finish(h: any, id: string)
		local finished = copy(h.state())
		finished.batches[id].stage = "Karton"
		finished.batches[id].locationId = SHELF
		finished.revision += 1
		local store = Transfers.new(finished)
		move(store, id, SHELF, HAND, id .. "/take")
		move(store, id, HAND, B, id .. "/load")
		h.save(store.profile)
	end
	local function sell(h: any, saleId: string, id: string, buyer: string, seed: number?): any
		local opened = Sales.open(h.c, ACTOR, {id = saleId, buyer = buyer, vehicleId = "Quad1", slotId = B, batchId = id},
			h.arrival(B, id, buyer), h.now, 600, seed)
		assert(opened.ok, opened.code)
		return Sales.settle(h.c, ACTOR, saleId, 600)
	end
	local function rejects(base: any, mutate: (any) -> (), expected: string)
		local candidate = copy(base)
		mutate(candidate)
		local valid, code = State.validate(candidate)
		assert(not valid and code == expected, tostring(code) .. " expected " .. expected)
	end

	test("01 every refusal leaves the confirmed profile, money and stock unchanged", function()
		local function refuses(h: any, expected: string, request: any, actor: any?, slots: any?)
			local before, writes = h.state(), h.writes
			local result = Purchases.advance(h.c, actor or ACTOR, request, slots or SLOTS, 600)
			assert(not result.ok and result.code == expected and result.receipt == nil,
				tostring(result.code) .. " expected " .. expected)
			assert(h.writes == writes, expected .. " wrote")
			assert(equal(h.state(), before), expected .. " changed the profile")
		end
		local h = harness(profile(0))
		local r = h.state().revision
		local notReady = table.clone(ACTOR); notReady.ready = false
		refuses(h, "NOT_READY", {operationId = "adv/1", expectedRevision = r}, notReady)
		local foreign = table.clone(ACTOR); foreign.ownerUserId = 202; foreign.actorId = "Player/202"
		refuses(h, "NOT_AUTHORIZED", {operationId = "adv/1", expectedRevision = r}, foreign)
		refuses(h, "INVALID_REQUEST", {operationId = "adv/1", expectedRevision = r, amount = 999})
		refuses(h, "INVALID_REQUEST", {operationId = string.rep("x", 121), expectedRevision = r})
		refuses(h, "INVALID_REQUEST", {operationId = "adv/1", expectedRevision = -1})
		refuses(h, "STALE_REVISION", {operationId = "adv/1", expectedRevision = r + 1})
		refuses(h, "SUPPLIER_FULL", {operationId = "adv/1", expectedRevision = r}, nil, {supplierIds = {}, rawIds = {RAW1}})
		refuses(h, "RAW_STORE_FULL", {operationId = "adv/1", expectedRevision = r}, nil, {supplierIds = {SUPPLIER}, rawIds = {}})
		local rich = harness(profile(Purchases.PRICE))
		refuses(rich, "MONEY_AVAILABLE", {operationId = "adv/1", expectedRevision = rich.state().revision})
		-- Any batch anywhere blocks the advance: supplier pickup, hand, trailer, raw and finished store.
		for _, place in {SUPPLIER, HAND, A, RAW1, SHELF} do
			local p = profile(0)
			p.batches.left = State.newBatch("left", 101, if place == SHELF then "Karton" else "Holzpaket", place)
			local stocked = harness(p)
			refuses(stocked, "STOCK_AVAILABLE", {operationId = "adv/1", expectedRevision = stocked.state().revision})
		end
		local p = profile(0)
		p.batches.box = State.newBatch("box", 101, "Karton", B)
		local selling = harness(p)
		assert(Sales.open(selling.c, ACTOR, {id = "sale/1", buyer = "Dealer", vehicleId = "Quad1", slotId = B, batchId = "box"},
			selling.arrival(B, "box", "Dealer"), selling.now, 600).ok)
		refuses(selling, "SALE_OPEN", {operationId = "adv/1", expectedRevision = selling.state().revision})
		-- An operation ID that already names another receipt.
		local spent = harness(profile(Purchases.PRICE))
		assert(spent.buy("op/1").ok)
		refuses(spent, "OPERATION_CONFLICT", {operationId = "op/1", expectedRevision = 0})
		refuses(spent, "STOCK_AVAILABLE", {operationId = "op/2", expectedRevision = spent.state().revision})
		assert(spent.state().money == 0)
	end)

	test("02 a broke, empty workshop gets exactly one Holzpaket at the supplier and no money", function()
		local h = harness(profile(Purchases.PRICE - 1))
		local before = h.state()
		local result = h.advance("adv/1")
		assert(result.ok and result.code == "ADVANCED" and not result.unknown, result.code)
		local receipt = result.receipt
		assert(receipt.batchId == "advance/adv/1" and receipt.supplierId == SUPPLIER and receipt.rawSlotId == RAW1
			and receipt.amount == 60 and receipt.revision == before.revision + 1 and receipt.price == nil)
		local state = h.state()
		local valid, code = State.validate(state)
		assert(valid, code)
		assert(state.money == 59 and state.revision == before.revision + 1 and batchCount(state) == 1)
		local batch = state.batches[receipt.batchId]
		assert(batch.stage == "Holzpaket" and batch.locationId == SUPPLIER and batch.quantity == 1)
		local promise = state.reservations[RAW1]
		assert(promise.kind == "Delivery" and promise.batchId == batch.id and promise.purchaseOperationId == "adv/1")
		assert(equal(state.advance, {operationId = "adv/1", batchId = batch.id, amount = 60}))
		local kept = state.receipts["adv/1"]
		assert(kept.action == "Advance" and kept.actorId == "Player/101" and kept.actorKind == "Player" and kept.carrierId == nil)
		assert(equal(kept.request, {operationId = "adv/1", expectedRevision = before.revision}) and equal(kept.result, receipt))
		-- No money flows: a regular purchase stays impossible.
		assert(h.buy("buy/1").code == "NOT_ENOUGH_MONEY" and h.state().money == 59)
	end)

	test("03 a repeated claim replays the stored receipt; a changed request conflicts", function()
		local h = harness(profile(0))
		local r = h.state().revision
		local first = h.advance("adv/1", r)
		assert(first.ok, first.code)
		local writes, after = h.writes, h.state()
		local again = h.advance("adv/1", r)
		assert(again.ok and again.code == "ADVANCED" and equal(again.receipt, first.receipt), again.code)
		assert(h.advance("adv/1", r + 1).code == "OPERATION_CONFLICT")
		assert(Purchases.buy(h.c, ACTOR, {operationId = "adv/1", expectedRevision = r}, SLOTS, 600).code == "OPERATION_CONFLICT")
		assert(h.writes == writes and equal(h.state(), after) and batchCount(after) == 1)
	end)

	test("04 while the advance is open every further claim is refused without extra ware", function()
		local h = harness(profile(0))
		local granted = h.advance("adv/1")
		local id = granted.receipt.batchId
		local function refused(label: string)
			local before, writes = h.state(), h.writes
			local result = h.advance("adv/" .. label)
			assert(not result.ok and result.code == "ADVANCE_OPEN", label .. ": " .. result.code)
			assert(h.writes == writes and equal(h.state(), before) and batchCount(before) == 1, label)
		end
		refused("at-supplier")
		refused("stale-view")
		deliver(h, id, granted.receipt.rawSlotId)
		refused("in-raw-store")
		finish(h, id)
		refused("on-trailer")
		assert(Sales.open(h.c, ACTOR, {id = "sale/1", buyer = "Dealer", vehicleId = "Quad1", slotId = B, batchId = id},
			h.arrival(B, id, "Dealer"), h.now, 600).ok)
		refused("open-sale")
		assert(h.state().advance.batchId == id and h.state().money == 0)
	end)

	test("05 two claims racing on the same revision create one batch", function()
		local h = harness(profile(0))
		local r = h.state().revision
		local first = h.advance("race/a", r)
		local second = h.advance("race/b", r)
		assert(first.ok and not second.ok and second.code == "ADVANCE_OPEN", second.code)
		assert(batchCount(h.state()) == 1 and h.state().receipts["race/b"] == nil)
		-- A claim arriving while the first save is still in flight is refused before it reads any state.
		local g = harness(profile(0))
		local nested: any = nil
		g.during = function()
			nested = Purchases.advance(g.c, ACTOR, {operationId = "race/d", expectedRevision = r}, SLOTS, 600)
		end
		local outer = g.advance("race/c", r)
		assert(outer.ok, outer.code)
		assert(nested and not nested.ok and nested.code == "NOT_CONFIRMED", nested and nested.code)
		assert(batchCount(g.state()) == 1 and g.state().advance.operationId == "race/c")
		assert(g.advance("race/d", r).code == "ADVANCE_OPEN" and batchCount(g.state()) == 1)
	end)

	test("06 a full dealer cycle repays 60 from exactly that batch, credits 40 and reopens regular purchases", function()
		local h = harness(profile(20))
		local granted = h.advance("adv/1")
		local id = granted.receipt.batchId
		deliver(h, id, granted.receipt.rawSlotId)
		finish(h, id)
		local sold = sell(h, "sale/1", id, "Dealer")
		assert(sold.ok and sold.code == "SOLD", sold.code)
		assert(sold.receipt.amount == 100 and sold.receipt.repaid == 60, tostring(sold.receipt.repaid))
		local state = h.state()
		assert(state.money == 20 + 40 and state.advance == nil and state.batches[id] == nil and next(state.reservations) == nil)
		local valid, code = State.validate(state)
		assert(valid, code)
		assert(state.receipts["adv/1"].action == "Advance" and state.receipts[id .. "/deliver/c"]
			and equal(state.receipts["sale/1"].result, sold.receipt))
		-- Replays answer from the receipts and neither pay nor advance twice.
		local writes = h.writes
		local replay = Sales.settle(h.c, ACTOR, "sale/1", 600)
		assert(replay.ok and equal(replay.receipt, sold.receipt) and h.writes == writes and h.state().money == 60)
		local again = h.advance("adv/1", granted.receipt.revision - 1)
		assert(again.ok and equal(again.receipt, granted.receipt) and h.writes == writes)
		-- With 60 the regular purchase works again.
		assert(h.advance("adv/2").code == "MONEY_AVAILABLE")
		local bought = h.buy("buy/1")
		assert(bought.ok and bought.code == "PURCHASED", bought.code)
		local final = h.state()
		assert(final.money == 0 and final.advance == nil and batchCount(final) == 1 and State.validate(final))
		assert(h.advance("adv/3").code == "STOCK_AVAILABLE")
	end)

	test("07 from zero both channels leave enough for the next regular purchase", function()
		for _, scenario in {{buyer = "Dealer", gross = 100, repaid = 40},
			{buyer = "Private", gross = 80, repaid = 20}, {buyer = "Private", gross = 120, repaid = 60}} do
			local h = harness(profile(0))
			assert(h.buy("before").code == "NOT_ENOUGH_MONEY")
			local granted = h.advance("adv/1")
			local id = granted.receipt.batchId
			deliver(h, id, granted.receipt.rawSlotId)
			finish(h, id)
			local sold = sell(h, "sale/1", id, scenario.buyer, scenario.gross - 80)
			assert(sold.ok and sold.receipt.amount == scenario.gross and sold.receipt.repaid == scenario.repaid
				and sold.receipt.balanceBefore == 0, sold.code)
			local state = h.state()
			assert(state.money == 60 and state.advance == nil and next(state.batches) == nil and State.validate(state))
			assert(h.advance("adv/2").code == "MONEY_AVAILABLE")
			assert(h.buy("buy/1").ok and h.state().money == 0)
			assert(h.advance("adv/3").code == "STOCK_AVAILABLE")
		end
	end)

	test("08 an unclear advance write is clarified by reconcile and never yields two batches", function()
		local h = harness(profile(0))
		local r = h.state().revision
		h.drop = true -- The write lands, its reply is lost.
		local lost = h.advance("adv/u", r)
		assert(not lost.ok and lost.unknown and lost.code == "WRITE_UNKNOWN", lost.code)
		local writes = h.writes
		for _, op in {"adv/u", "adv/v"} do
			local blocked = h.advance(op, r)
			assert(not blocked.ok and blocked.code == "NOT_CONFIRMED" and blocked.unknown, blocked.code)
		end
		assert(h.buy("buy/x").code == "NOT_CONFIRMED" and h.writes == writes)
		local clarified = h.c.reconcile()
		assert(clarified.ok and clarified.code == "RECONCILED", clarified.code)
		local replay = h.advance("adv/u", r)
		assert(replay.ok and replay.code == "ADVANCED" and replay.receipt.batchId == "advance/adv/u", replay.code)
		assert(h.advance("adv/v").code == "ADVANCE_OPEN")
		local state = h.state()
		assert(batchCount(state) == 1 and state.money == 0 and state.advance.operationId == "adv/u" and h.writes == writes)
		-- The write never landed: reconcile stays unclear and nothing is claimed until a new session.
		local g = harness(profile(0))
		g.lose = true
		local missing = g.advance("adv/l")
		assert(not missing.ok and missing.unknown, missing.code)
		local unclear = g.c.reconcile()
		assert(not unclear.ok and unclear.code == "RECONCILE_UNKNOWN", unclear.code)
		assert(next(g.value.data.state.batches) == nil and g.value.data.state.advance == nil)
		assert(g.advance("adv/m").code == "NOT_CONFIRMED")
		g.now += 601 -- The old lease has run out.
		g.c = g.controller("session/2")
		local fresh = g.advance("adv/m")
		assert(fresh.ok, fresh.code)
		assert(batchCount(g.state()) == 1 and g.state().advance.operationId == "adv/m")
		assert(g.advance("adv/l").code == "ADVANCE_OPEN" and batchCount(g.state()) == 1)
	end)

	test("09 the validator rejects broken advance records and repayments", function()
		local h = harness(profile(0))
		local granted = h.advance("adv/1")
		local id = granted.receipt.batchId
		local open = h.state()
		rejects(open, function(p) p.advance.amount = 59 end, "INVALID_ADVANCE")
		rejects(open, function(p) p.advance.extra = true end, "INVALID_ADVANCE")
		rejects(open, function(p) p.advance.operationId = "adv/none" end, "INVALID_ADVANCE")
		rejects(open, function(p) p.advance.batchId = "other" end, "INVALID_ADVANCE")
		rejects(open, function(p) p.advance = nil end, "INVALID_ADVANCE") -- The batch would escape repayment.
		rejects(open, function(p) p.receipts["adv/1"].result.amount = 0; p.advance.amount = 0 end, "INVALID_RECEIPT_RESULT")
		rejects(open, function(p) p.receipts["adv/1"].result.batchId = "purchase/adv/1" end, "INVALID_RECEIPT_RESULT")
		rejects(open, function(p) p.receipts["adv/1"].result.price = 60 end, "INVALID_RECEIPT_RESULT")
		rejects(open, function(p) p.receipts["adv/1"].result.code = "PURCHASED" end, "INVALID_RECEIPT_RESULT")
		rejects(open, function(p) p.receipts["adv/1"].carrierId = HAND end, "INVALID_RECEIPT")
		rejects(open, function(p) p.receipts["adv/1"].actorId = "Player/202" end, "INVALID_RECEIPT")
		rejects(open, function(p) p.reservations[RAW2] = p.reservations[RAW1]; p.reservations[RAW1] = nil end,
			"INVALID_DELIVERY_RESERVATION")
		rejects(open, function(p) p.reservations[RAW1] = nil end, "INVALID_DELIVERY_HISTORY")
		deliver(h, id, RAW1)
		finish(h, id)
		assert(sell(h, "sale/1", id, "Dealer").ok)
		local final = h.state()
		local valid, code = State.validate(final)
		assert(valid, code)
		for _, repaid in {0, 59, 61, 101, 1.5, -1, "60"} do
			rejects(final, function(p) p.receipts["sale/1"].result.repaid = repaid end, "INVALID_RECEIPT_RESULT")
		end
		rejects(final, function(p) p.receipts["sale/1"].result.repaid = nil end, "INVALID_RECEIPT_RESULT")
		rejects(final, function(p) p.receipts["sale/1"].result.balanceBefore = nil end, "INVALID_RECEIPT_RESULT")
		rejects(final, function(p) p.receipts["sale/1"].result.balanceBefore = 1 end, "INVALID_RECEIPT_RESULT")
		rejects(final, function(p) p.receipts["adv/1"] = nil end, "INVALID_RECEIPT_RESULT") -- Repaid without an advance.
		rejects(final, function(p) p.advance = copy(open.advance) end, "INVALID_ADVANCE") -- A sold batch stays closed.
		-- A sale without an advance repays nothing.
		local plain = harness(profile(Purchases.PRICE))
		local bought = plain.buy("buy/1")
		deliver(plain, bought.receipt.batchId, bought.receipt.rawSlotId)
		finish(plain, bought.receipt.batchId)
		local sold = sell(plain, "sale/1", bought.receipt.batchId, "Dealer")
		assert(sold.ok and sold.receipt.repaid == 0 and plain.state().money == 100)
		rejects(plain.state(), function(p) p.receipts["sale/1"].result.repaid = 60 end, "INVALID_RECEIPT_RESULT")
	end)

	test("10 a P07-06 receipt without repayment fields loads and replays in a new session", function()
		local p = profile(0)
		p.batches.box = State.newBatch("box", 101, "Karton", B)
		local h = harness(p)
		assert(sell(h, "sale/old", "box", "Dealer").ok)
		assert(h.c.release().ok)
		local legacy = h.value.data.state
		legacy.receipts["sale/old"].result.repaid = nil
		assert(State.validate(legacy))
		h.c = h.controller("session/2")
		local writes = h.writes
		local replay = Sales.settle(h.c, ACTOR, "sale/old", 600)
		assert(replay.ok and replay.receipt.repaid == nil and replay.receipt.amount == 100)
		assert(h.writes == writes and h.state().money == 100)
	end)

	test("11 an open advance survives rejoin and an uncertain settlement credits its net proceeds only once", function()
		local h = harness(profile(0))
		local granted = h.advance("adv/1")
		assert(granted.ok)
		local id = granted.receipt.batchId
		assert(h.c.release().ok)
		h.c = h.controller("session/2")
		assert(h.state().advance.batchId == id and h.advance("adv/2").code == "ADVANCE_OPEN")
		deliver(h, id, granted.receipt.rawSlotId)
		finish(h, id)
		local opened = Sales.open(h.c, ACTOR, {id = "sale/u", buyer = "Private", vehicleId = "Quad1", slotId = B, batchId = id},
			h.arrival(B, id, "Private"), h.now, 600, 0)
		assert(opened.ok, opened.code)
		h.drop = true
		local lost = Sales.settle(h.c, ACTOR, "sale/u", 600)
		assert(not lost.ok and lost.unknown and lost.code == "WRITE_UNKNOWN", lost.code)
		local writes = h.writes
		assert(h.state().money == 0 and h.state().advance.batchId == id)
		assert(Sales.settle(h.c, ACTOR, "sale/u", 600).code == "NOT_CONFIRMED")
		assert(h.c.reconcile().ok)
		local replay = Sales.settle(h.c, ACTOR, "sale/u", 600)
		assert(replay.ok and replay.receipt.amount == 80 and replay.receipt.repaid == 20)
		assert(h.writes == writes and h.state().money == 60 and h.state().advance == nil)
	end)

	return {total = #passed + #failures, passed = passed, failures = failures}
end
