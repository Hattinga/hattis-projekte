--!strict
-- P07 sales suite. In-memory atomic backend; no engine, remotes or external storage.
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
	local ACTOR = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = HAND, ready = true}
	local function profile(): any
		local p = State.newProfile(101)
		p.money = 120
		p.locations[HAND] = State.newLocation(HAND, "Carrier", 1, {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"})
		p.locations[A] = State.newLocation(A, "VehicleSlot", 1, {"Holzpaket", "Karton"})
		p.locations[B] = State.newLocation(B, "VehicleSlot", 1, {"Holzpaket", "Karton"})
		p.locations["Supplier.Slot1"] = State.newLocation("Supplier.Slot1", "Supplier", 1, {"Holzpaket"})
		p.locations["RawStore.Slot1"] = State.newLocation("RawStore.Slot1", "RawStore", 1, {"Holzpaket"})
		p.locations["FinishedStore.Slot1"] = State.newLocation("FinishedStore.Slot1", "FinishedStore", 1, {"Karton"})
		p.batches.box = State.newBatch("box", 101, "Karton", B)
		p.batches.wood = State.newBatch("wood", 101, "Holzpaket", A)
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
				if h.drop then h.drop = false; error("simulated lost sale reply") end
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
		function h.arrival(slot: string, batchId: string, buyer: string): any
			return {ownerUserId = 101, vehicleId = "Quad1", slotId = slot, batchId = batchId, destination = buyer,
				departedAt = 1, arrivedAt = 2, travelledStuds = 700}
		end
		function h.open(id: string, buyer: string, seed: number?): any
			return Sales.open(h.c, ACTOR, {id = id, buyer = buyer, vehicleId = "Quad1", slotId = B, batchId = "box"},
				h.arrival(B, "box", buyer), h.now, 600, seed)
		end
		return h
	end
	local function unchanged(h: any, before: any)
		local after = h.state()
		assert(equal(after, before), "Rejected sale changed the confirmed profile")
	end

	test("01 without matching arrival, from a foreign actor or for wood, nothing is reserved or paid", function()
		local h = harness(profile())
		local before = h.state()
		local writes = h.writes
		local request = {id = "sale/1", buyer = "Dealer", vehicleId = "Quad1", slotId = B, batchId = "box"}
		assert(Sales.open(h.c, ACTOR, request, nil, h.now, 600).code == "NO_ARRIVAL")
		for _, wrong in {h.arrival(B, "box", "Private"), h.arrival(A, "box", "Dealer"), h.arrival(B, "wood", "Dealer"),
			{ownerUserId = 202, vehicleId = "Quad1", slotId = B, batchId = "box", destination = "Dealer"}} do
			assert(Sales.open(h.c, ACTOR, request, wrong, h.now, 600).code == "NO_ARRIVAL")
		end
		local foreign = table.clone(ACTOR); foreign.ownerUserId = 202; foreign.actorId = "Player/202"
		assert(Sales.open(h.c, foreign, request, h.arrival(B, "box", "Dealer"), h.now, 600).code == "NOT_AUTHORIZED")
		local notReady = table.clone(ACTOR); notReady.ready = false
		assert(Sales.open(h.c, notReady, request, h.arrival(B, "box", "Dealer"), h.now, 600).code == "NOT_READY")
		local wood = {id = "sale/2", buyer = "Dealer", vehicleId = "Quad1", slotId = A, batchId = "wood"}
		assert(Sales.open(h.c, ACTOR, wood, h.arrival(A, "wood", "Dealer"), h.now, 600).code == "CARTON_NOT_ON_SLOT")
		local extra = table.clone(request); (extra :: any).price = 1
		assert(Sales.open(h.c, ACTOR, extra :: any, h.arrival(B, "box", "Dealer"), h.now, 600).code == "INVALID_REQUEST")
		assert(h.writes == writes)
		unchanged(h, before)
	end)

	test("02 a confirmed arrival moves exactly the slot's carton into the hand and shows the dealer value", function()
		local h = harness(profile())
		local opened = h.open("sale/1", "Dealer")
		assert(opened.ok and opened.code == "OPEN", opened.code)
		local offer = opened.offer
		assert(offer.quantity == 1 and offer.dealerValue == 100 and offer.quoteMin == 100 and offer.quoteMax == 100)
		assert(offer.seed == nil and offer.amount == nil, "The offer must not reveal the hidden roll")
		local state = h.state()
		assert(State.validate(state))
		assert(state.batches.box.locationId == HAND and state.batches.wood.locationId == A and state.money == 120)
		local promise = state.reservations[B]
		assert(promise and promise.kind == "Return" and promise.batchId == "box" and promise.carrierId == HAND)
		assert(state.pendingSale and state.pendingSale.id == "sale/1" and next(state.claims) == nil)
	end)

	test("03 double open replays the offer; a second sale or changed request is refused", function()
		local h = harness(profile())
		local first = h.open("sale/1", "Dealer")
		local writes, before = h.writes, h.state()
		local again = h.open("sale/1", "Dealer")
		assert(again.ok and again.code == "OPEN" and equal(again.offer, first.offer) and h.writes == writes)
		assert(Sales.open(h.c, ACTOR, {id = "sale/2", buyer = "Dealer", vehicleId = "Quad1", slotId = A, batchId = "wood"},
			h.arrival(A, "wood", "Dealer"), h.now, 600).code == "SALE_BUSY")
		assert(h.open("sale/1", "Private").code == "OPERATION_CONFLICT")
		unchanged(h, before)
	end)

	test("04 cancel before binding returns the carton to its slot without any payment", function()
		local h = harness(profile())
		local opened = h.open("sale/p", "Private", 7)
		assert(opened.offer.quoteMin == 80 and opened.offer.quoteMax == 120 and opened.offer.dealerValue == 100)
		local cancelled = Sales.cancel(h.c, ACTOR, "sale/p", h.now, 600)
		assert(cancelled.ok and cancelled.code == "CANCELLED", cancelled.code)
		local state = h.state()
		assert(state.batches.box.locationId == B and state.reservations[B] == nil and state.pendingSale == nil)
		assert(state.money == 120 and State.validate(state))
		local writes = h.writes
		assert(Sales.cancel(h.c, ACTOR, "sale/p", h.now, 600).code == "CANCELLED" and h.writes == writes)
		assert(Sales.settle(h.c, ACTOR, "sale/p", 600).code == "SALE_NOT_FOUND")
		local reopened = h.open("sale/q", "Dealer")
		assert(reopened.ok and h.state().batches.box.locationId == HAND, "The returned carton stays sellable")
	end)

	test("05 dealer settlement removes one carton, credits 100 once and keeps the receipt", function()
		local h = harness(profile())
		h.open("sale/d", "Dealer")
		local sold = Sales.settle(h.c, ACTOR, "sale/d", 600)
		assert(sold.ok and sold.code == "SOLD", sold.code)
		local receipt = sold.receipt
		assert(receipt.buyer == "Dealer" and receipt.quantity == 1 and receipt.amount == 100 and receipt.batchId == "box")
		assert(receipt.repaid == 0, "Without a material advance nothing is repaid")
		local state = h.state()
		assert(state.money == 220 and state.batches.box == nil and state.reservations[B] == nil and state.pendingSale == nil)
		assert(state.receipts["sale/d"].action == "Sale" and State.validate(state))
		local writes = h.writes
		local replay = Sales.settle(h.c, ACTOR, "sale/d", 600)
		assert(replay.ok and equal(replay.receipt, receipt) and h.writes == writes and h.state().money == 220)
		assert(Sales.cancel(h.c, ACTOR, "sale/d", h.now, 600).code == "SOLD" and h.writes == writes)
		assert(h.open("sale/d", "Dealer").code == "SOLD" and h.state().money == 220)
		assert(h.open("sale/e", "Dealer").code == "CARTON_NOT_ON_SLOT", "Sold ware is not sellable again")
	end)

	test("06 forced private rolls give 80 and 120 in two separate runs; the price stays bound", function()
		for _, case in {{seed = 0, amount = 80}, {seed = 40, amount = 120}, {seed = 41, amount = 80}} do
			local h = harness(profile())
			local opened = h.open("sale/p", "Private", case.seed)
			assert(opened.offer.quoteMin == 80 and opened.offer.quoteMax == 120)
			local sold = Sales.settle(h.c, ACTOR, "sale/p", 600)
			assert(sold.ok and sold.receipt.amount == case.amount, tostring(sold.receipt and sold.receipt.amount))
			assert(h.state().money == 120 + case.amount)
			assert(h.open("sale/p", "Dealer").code == "OPERATION_CONFLICT", "No switch to the dealer after the reveal")
			assert(Sales.settle(h.c, ACTOR, "sale/p", 600).receipt.amount == case.amount, "No new roll on repeat")
		end
	end)

	test("07 an unclear settlement is clarified before anything else and pays exactly once", function()
		local h = harness(profile())
		h.open("sale/u", "Private", 25)
		h.drop = true
		local lost = Sales.settle(h.c, ACTOR, "sale/u", 600)
		assert(not lost.ok and lost.unknown, lost.code)
		assert(Sales.settle(h.c, ACTOR, "sale/u", 600).code == "NOT_CONFIRMED")
		assert(Sales.cancel(h.c, ACTOR, "sale/u", h.now, 600).code == "NOT_CONFIRMED")
		local resumed = Sales.resume(h.c, ACTOR, "sale/u")
		assert(resumed.ok and resumed.code == "SOLD" and resumed.receipt.amount == 105, resumed.code)
		local state = h.state()
		assert(state.money == 225 and state.batches.box == nil and State.validate(state))
		assert(Sales.settle(h.c, ACTOR, "sale/u", 600).receipt.amount == 105 and h.state().money == 225)
	end)

	test("08 a new session resumes the open sale with the same quote and hidden roll", function()
		local h = harness(profile())
		local opened = h.open("sale/r", "Private", 33)
		assert(h.c.release().ok)
		h.c = h.controller("session/2")
		local resumed = Sales.resume(h.c, ACTOR)
		assert(resumed.ok and resumed.code == "OPEN" and equal(resumed.offer, opened.offer))
		assert(h.state().pendingSale.seed == 33)
		assert(Sales.open(h.c, ACTOR, {id = "sale/x", buyer = "Dealer", vehicleId = "Quad1", slotId = A, batchId = "wood"},
			h.arrival(A, "wood", "Dealer"), h.now, 600).code == "SALE_BUSY")
		local sold = Sales.settle(h.c, ACTOR, "sale/r", 600)
		assert(sold.ok and sold.receipt.amount == 113 and h.state().money == 233)
		assert(Sales.resume(h.c, ACTOR).code == "NONE")
		assert(Sales.resume(h.c, ACTOR, "sale/r").receipt.amount == 113)
	end)

	test("09 the sale carton cannot leave the hand by an ordinary transfer, and settlement waits for claims", function()
		local h = harness(profile())
		h.open("sale/c", "Dealer")
		local store = Transfers.new(h.state())
		local claim = Transfers.reserve(store, ACTOR, {operationId = "back/r", expectedRevision = store.profile.revision,
			batchId = "box", sourceId = HAND, targetId = B, quantity = 1}, h.now, 5)
		assert(claim.ok, claim.code)
		local committed = Transfers.commit(store, ACTOR, {operationId = "back/c", expectedRevision = store.profile.revision,
			claimId = "back/r"}, h.now)
		assert(not committed.ok and committed.code == "INVALID_STATE", committed.code)
		local data = h.c.snapshot().confirmed.data
		data.state = store.profile
		assert(h.c.save(data, 600).ok)
		assert(Sales.settle(h.c, ACTOR, "sale/c", 600).code == "SALE_TRANSFER_PENDING")
		assert(h.state().money == 120 and h.state().batches.box.locationId == HAND)
	end)

	test("10 sold batches keep their purchase and transfer history valid", function()
		local p = profile()
		p.batches.box = nil
		local h = harness(p)
		local bought = Purchases.buy(h.c, ACTOR, {operationId = "buy/1", expectedRevision = h.state().revision},
			{supplierIds = {"Supplier.Slot1"}, rawIds = {"RawStore.Slot1"}}, 600)
		assert(bought.ok, bought.code)
		local id = bought.receipt.batchId
		local store = Transfers.new(h.state())
		local function move(from: string, to: string, op: string)
			assert(Transfers.reserve(store, ACTOR, {operationId = op .. "/r", expectedRevision = store.profile.revision,
				batchId = id, sourceId = from, targetId = to, quantity = 1}, h.now, 5).ok, op)
			assert(Transfers.commit(store, ACTOR, {operationId = op .. "/c", expectedRevision = store.profile.revision,
				claimId = op .. "/r"}, h.now).ok, op)
		end
		move("Supplier.Slot1", HAND, "pick"); move(HAND, "RawStore.Slot1", "deliver")
		local finished = copy(store.profile) -- Stand-in for the four station runs, which keep the batch ID.
		finished.batches[id].stage = "Karton"; finished.batches[id].locationId = "FinishedStore.Slot1"
		finished.revision += 1
		store = Transfers.new(finished)
		move("FinishedStore.Slot1", HAND, "store-take"); move(HAND, B, "load")
		local data = h.c.snapshot().confirmed.data
		data.state = store.profile
		assert(h.c.save(data, 600).ok)
		local opened = Sales.open(h.c, ACTOR, {id = "sale/h", buyer = "Dealer", vehicleId = "Quad1", slotId = B, batchId = id},
			h.arrival(B, id, "Dealer"), h.now, 600)
		assert(opened.ok, opened.code)
		local sold = Sales.settle(h.c, ACTOR, "sale/h", 600)
		assert(sold.ok, sold.code)
		local state = h.state()
		assert(state.batches[id] == nil and state.receipts["buy/1"] and state.receipts["load/c"])
		local valid, code = State.validate(state)
		assert(valid, code)
		assert(state.money == 120 - 60 + 100)
	end)

	test("11 the validator rejects broken sale records", function()
		local h = harness(profile())
		h.open("sale/v", "Private", 5)
		local open = h.state()
		local function rejects(mutate: (any) -> (), expected: string)
			local candidate = copy(open)
			mutate(candidate)
			local valid, code = State.validate(candidate)
			assert(not valid and code == expected, tostring(code) .. " expected " .. expected)
		end
		rejects(function(p) p.pendingSale.seed = State.MAX_SALE_SEED + 1 end, "INVALID_PENDING_SALE")
		rejects(function(p) p.pendingSale.buyer = "Dealer" end, "INVALID_PENDING_SALE")
		rejects(function(p) p.pendingSale.extra = true end, "INVALID_PENDING_SALE")
		rejects(function(p) p.pendingSale.slotId = A end, "INVALID_PENDING_SALE")
		rejects(function(p) p.batches.box.locationId = B; p.reservations[B] = nil end, "INVALID_PENDING_SALE")
		local sold = Sales.settle(h.c, ACTOR, "sale/v", 600)
		assert(sold.ok)
		local final = h.state()
		local function rejectsSold(mutate: (any) -> (), expected: string)
			local candidate = copy(final)
			mutate(candidate)
			local valid, code = State.validate(candidate)
			assert(not valid and code == expected, tostring(code) .. " expected " .. expected)
		end
		rejectsSold(function(p) p.receipts["sale/v"].result.amount = 121 end, "INVALID_RECEIPT_RESULT")
		rejectsSold(function(p) p.receipts["sale/v"].result.buyer = "Dealer" end, "INVALID_RECEIPT_RESULT")
		rejectsSold(function(p) p.receipts["sale/v"].result.repaid = 1 end, "INVALID_RECEIPT_RESULT")
		rejectsSold(function(p) p.batches.box = State.newBatch("box", 101, "Karton", B) end, "INVALID_RECEIPT_RESULT")
		rejectsSold(function(p)
			local twin = copy(p.receipts["sale/v"]); twin.request.operationId = "sale/w"
			p.receipts["sale/w"] = twin
		end, "DUPLICATE_SALE")
		rejectsSold(function(p) p.receipts["sale/v"].actorId = "Player/202" end, "INVALID_RECEIPT")
		assert(State.validate(final))
	end)

	test("12 reopening the same carton for the same buyer never draws a new private roll", function()
		local h = harness(profile())
		local first = h.open("sale/a", "Private")
		assert(first.ok, first.code)
		local seed = h.state().pendingSale.seed
		assert(seed == Sales.seedFor("box", "Private") and seed >= 0 and seed <= State.MAX_SALE_SEED)
		assert(Sales.cancel(h.c, ACTOR, "sale/a", h.now, 600).ok)
		assert(h.open("sale/b", "Private").ok and h.state().pendingSale.seed == seed, "Cancel and reopen rerolled")
		assert(h.c.release().ok)
		h.c = h.controller("session/2")
		assert(Sales.cancel(h.c, ACTOR, "sale/b", h.now, 600).ok)
		assert(h.open("sale/c", "Private").ok and h.state().pendingSale.seed == seed, "Rejoin and redelivery rerolled")
		local sold = Sales.settle(h.c, ACTOR, "sale/c", 600)
		assert(sold.ok and sold.receipt.amount == 80 + seed % 41)
		assert(Sales.seedFor("box", "Dealer") ~= seed or Sales.seedFor("other", "Private") ~= seed)
		local spread: {[number]: boolean} = {}
		for index = 1, 200 do spread[80 + Sales.seedFor("purchase/" .. index, "Private") % 41] = true end
		local values = 0
		for _ in spread do values += 1 end
		assert(values >= 38, "Private amounts cover only " .. values .. " of 41 values") -- 200 cartons, 41 values
	end)

	return {total = #passed + #failures, passed = passed, failures = failures}
end
