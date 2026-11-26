--!strict
-- P10-03 overview suite: stock by place and recipe, vehicle load, free places and bottlenecks from plain profiles.
-- No backend, engine or remotes; the overview must stay read-only.
return function(State: any, Recipes: any, Line: any, Overview: any): any
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

	local HOCKER, TISCH = "Hocker01", "Beistelltisch01"
	local ALL_STAGES = {"Holzpaket", "Bausatz", "Rohhocker", "Rohtisch", "Fertig", "Karton"}
	local A, B, HAND = "Vehicle.Quad1.SlotA", "Vehicle.Quad1.SlotB", "hand"
	-- Stores, stations, vehicle slots and a hand like the real workshop binds them. `vehicle=false` leaves the slots out.
	local function workshop(money: number, vehicle: boolean?): any
		local p = State.newProfile(101)
		p.money = money
		for _, rule in State.STATIONS do
			p.locations[rule.input] = State.newLocation(rule.input, "StationInput", 1, Recipes.acceptedStages(rule.id, "Input"))
			p.locations[rule.process] = State.newLocation(rule.process, "StationProcess", 1, Recipes.acceptedStages(rule.id, "Input"))
			p.locations[rule.output] = State.newLocation(rule.output, "StationOutput", 1, Recipes.acceptedStages(rule.id, "Output"))
		end
		p.locations[HAND] = State.newLocation(HAND, "Carrier", 1, ALL_STAGES)
		p.locations["Band.First"] = State.newLocation("Band.First", "Band", 1, {"Bausatz"})
		if vehicle ~= false then
			p.locations[A] = State.newLocation(A, "VehicleSlot", 1, {"Holzpaket", "Karton"})
			p.locations[B] = State.newLocation(B, "VehicleSlot", 1, {"Holzpaket", "Karton"})
		end
		p.locations["Supplier.Slot1"] = State.newLocation("Supplier.Slot1", "Supplier", 1, {"Holzpaket"})
		for i = 1, 2 do
			p.locations["RawStore.Slot" .. i] = State.newLocation("RawStore.Slot" .. i, "RawStore", 1, {"Holzpaket"})
		end
		for i = 1, 4 do
			p.locations["FinishedStore.Slot" .. i] = State.newLocation("FinishedStore.Slot" .. i, "FinishedStore", 1, {"Karton"})
		end
		return p
	end
	local function put(p: any, id: string, stage: string, at: string, recipeId: string?)
		p.batches[id] = State.newBatch(id, 101, stage, at, recipeId)
	end
	local NOW = 1000
	local function codes(overview: any): string
		local parts: {string} = {}
		for _, item in overview.bottlenecks do table.insert(parts, item.code) end
		return table.concat(parts, ",")
	end
	local function find(overview: any, code: string): any
		for _, item in overview.bottlenecks do if item.code == code then return item end end
		return nil
	end
	local function rowOf(overview: any, label: string): string?
		for _, row in Overview.rows(overview) do if row.label == label then return row.value end end
		return nil
	end

	test("01 an empty workshop with money reports no stock and asks for wood at the selected price", function()
		local p = workshop(200)
		assert(State.validate(p))
		local o = Overview.compute(p, HOCKER, NOW)
		assert(o.money == 200 and o.wood.total == 0 and o.cartons.total == 0 and o.inProgress == 0 and #o.stock == 0)
		assert(o.recipe.id == HOCKER and o.recipe.price == 60 and o.recipe.dealer == 100)
		assert(o.places.raw.capacity == 2 and o.places.store.capacity == 4 and o.places.vehicle.capacity == 2)
		assert(o.places.raw.free == 2 and o.places.store.used == 0 and not o.places.vehicle.full)
		local missing = find(o, "NO_WOOD")
		assert(missing and missing.severity == "stop" and missing.message == "Kein Holz: Kaufe beim Lieferanten ein Holzpaket für 60.", missing and missing.message)
		assert(Overview.primary(o).code == "NO_WOOD")
		assert(rowOf(o, "Guthaben") == "200" and rowOf(o, "Holz") == "0" and rowOf(o, "Kartons") == "0")
	end)

	test("02 wood is counted by place: store, supplier, vehicle, line and hand", function()
		local p = workshop(200)
		put(p, "w1", "Holzpaket", "RawStore.Slot1")
		put(p, "w2", "Holzpaket", "Supplier.Slot1")
		put(p, "w3", "Holzpaket", A)
		put(p, "w4", "Holzpaket", "Saege.Input")
		put(p, "w5", "Holzpaket", HAND, TISCH)
		assert(State.validate(p))
		local o = Overview.compute(p, HOCKER, NOW)
		local where = o.wood.where
		assert(o.wood.total == 5 and where.raw == 1 and where.supplier == 1 and where.vehicle == 1 and where.line == 1 and where.carried == 1 and where.store == 0)
		assert(rowOf(o, "Holz") == "5 (Rohstofflager 1, Lieferant 1, Anhänger 1, Linie 1, unterwegs 1)", rowOf(o, "Holz"))
		assert(find(o, "NO_WOOD") == nil, "Wood in stock must not be reported as missing")
	end)

	test("03 the stock lists every recipe's stages with the recipe's own names, in list and chain order", function()
		local p = workshop(200)
		put(p, "t1", "Holzpaket", "RawStore.Slot1", TISCH)
		put(p, "h1", "Karton", "FinishedStore.Slot1")
		put(p, "h2", "Karton", "FinishedStore.Slot2")
		put(p, "h3", "Holzpaket", "RawStore.Slot2")
		put(p, "t2", "Rohtisch", "Finish.Input", TISCH)
		local o = Overview.compute(p, TISCH, NOW)
		local names: {string} = {}
		for _, entry in o.stock do table.insert(names, entry.count .. " " .. entry.name) end
		assert(table.concat(names, "|") == "1 Holzpaket|2 Hockerkarton|1 Tischholzpaket|1 Rohtisch", table.concat(names, "|"))
		assert(o.inProgress == 1 and o.wood.total == 2 and o.cartons.total == 2)
	end)

	test("04 free places count a promised place as used and show the vehicle load", function()
		local p = workshop(200)
		put(p, "k1", "Karton", "FinishedStore.Slot1")
		put(p, "k2", "Karton", "FinishedStore.Slot2")
		put(p, "k3", "Karton", A)
		p.reservations[B] = {kind = "Return", batchId = "k9", carrierId = HAND, expiresAt = 0}
		local o = Overview.compute(p, HOCKER, NOW)
		assert(o.places.store.used == 2 and o.places.store.free == 2 and not o.places.store.full)
		assert(o.places.vehicle.used == 2 and o.places.vehicle.free == 0 and o.places.vehicle.full)
		assert(o.cartons.where.store == 2 and o.cartons.where.vehicle == 1)
		assert(rowOf(o, "Fertiglager") == "2/4 belegt" and rowOf(o, "Anhänger") == "2/2 belegt · 0 frei", rowOf(o, "Anhänger"))
		local full = find(o, "VEHICLE_FULL")
		assert(full and full.severity == "limit" and full.message:find("2/2", 1, true))
		assert(find(o, "STORE_FULL") == nil)
	end)

	test("05 a full finished store is a limit that names the way out", function()
		local p = workshop(200)
		for i = 1, 4 do put(p, "k" .. i, "Karton", "FinishedStore.Slot" .. i) end
		local o = Overview.compute(p, HOCKER, NOW)
		local full = find(o, "STORE_FULL")
		assert(full and full.severity == "limit" and full.message == "Fertiglager voll (4/4): Kartons verladen und verkaufen.", full and full.message)
		assert(o.places.store.full and find(o, "CARTONS_IN_STORE") ~= nil)
	end)

	test("06 no money asks for an advance only in an empty workshop, otherwise for a sale", function()
		local empty = Overview.compute(workshop(10), HOCKER, NOW)
		local advance = find(empty, "NO_MONEY")
		assert(advance and advance.severity == "stop" and advance.message:find("Materialvorschuss", 1, true) and find(empty, "NO_WOOD") == nil)
		local p = workshop(10)
		p.advance = {operationId = "a", batchId = "advance/a", amount = 60}
		put(p, "k1", "Karton", "FinishedStore.Slot1")
		local sell = Overview.compute(p, HOCKER, NOW)
		local item = find(sell, "NO_MONEY")
		assert(item and item.severity == "hint" and item.message == "Kein Geld für Holz (60): Verkaufe zuerst fertige Ware.", item and item.message)
		assert(rowOf(sell, "Guthaben") == "10 · Vorschuss 60 offen", rowOf(sell, "Guthaben"))
		local waiting = workshop(10)
		put(waiting, "k1", "Bausatz", "Montage.Input")
		local idle = Overview.compute(waiting, HOCKER, NOW)
		assert(find(idle, "NO_MONEY").severity == "hint" and not find(idle, "NO_MONEY").message:find("Materialvorschuss", 1, true))
	end)

	test("07 a station with a finished ware at its output stops the line and names ware and station", function()
		local p = workshop(200)
		put(p, "t1", "Rohtisch", "Montage.Output", TISCH)
		put(p, "h1", "Karton", "Packen.Output")
		put(p, "w1", "Holzpaket", "RawStore.Slot1")
		local o = Overview.compute(p, HOCKER, NOW)
		local first = o.bottlenecks[1]
		assert(first.code == "OUTPUT_FULL" and first.severity == "stop" and first.stationId == "Montage", first.code)
		assert(first.message == "Montagebank: Rohtisch am Ausgang abholen.", first.message)
		local last = find(o, "OUTPUT_FULL")
		local count = 0
		for _, item in o.bottlenecks do if item.code == "OUTPUT_FULL" then count += 1 end end
		assert(count == 2 and last ~= nil)
		for _, item in o.bottlenecks do
			if item.stationId == "Packen" then assert(item.message == "Packtisch: Hockerkarton am Ausgang abholen.", item.message) end
		end
		assert(Overview.primary(o).code == "OUTPUT_FULL")
	end)

	test("08 a backlog at the first belt reports its cause, a stopped belt reports the switch", function()
		local p = workshop(200)
		put(p, "k", "Bausatz", "Band.First")
		p.reservations["Saege.Output"] = {kind = "Return", batchId = "k", carrierId = "Band.First", expiresAt = 0}
		put(p, "m", "Bausatz", "Montage.Input")
		local taken = Overview.compute(p, HOCKER, NOW)
		local item = find(taken, "BACKLOG")
		assert(item and item.severity == "limit" and item.stationId == "Saege" and item.message == "Band wartet: Der Montageeingang ist belegt.", item and item.message)
		local stopped = Overview.compute(p, HOCKER, NOW, true)
		assert(find(stopped, "BACKLOG").message == "Förderband angehalten: Der Bausatz wartet am Sägeausgang.")
		p.batches.m = nil
		assert(find(Overview.compute(p, HOCKER, NOW), "BACKLOG") == nil, "A free assembly input ends the backlog")
	end)

	test("09 wood that waits somewhere names the next step for that place", function()
		local p = workshop(200)
		put(p, "w1", "Holzpaket", "Supplier.Slot1")
		put(p, "w2", "Holzpaket", A)
		put(p, "w3", "Holzpaket", "RawStore.Slot1")
		local o = Overview.compute(p, HOCKER, NOW)
		assert(find(o, "WOOD_AT_SUPPLIER").message == "1 Holzpaket liegt beim Lieferanten: auf den Anhänger laden.", find(o, "WOOD_AT_SUPPLIER").message)
		assert(find(o, "WOOD_ON_VEHICLE").message == "1 Holzpaket auf dem Anhänger: im Rohstofflager entladen.")
		assert(find(o, "WOOD_IN_STORE").message == "1 Holzpaket im Rohstofflager: zur Säge tragen.")
		put(p, "w4", "Holzpaket", "Saege.Input")
		assert(find(Overview.compute(p, HOCKER, NOW), "WOOD_IN_STORE") == nil, "Wood at the saw is no store hint")
		local without = workshop(200, false)
		put(without, "w1", "Holzpaket", "Supplier.Slot1")
		assert(find(Overview.compute(without, HOCKER, NOW), "WOOD_AT_SUPPLIER") == nil, "Without a vehicle nothing is loaded")
	end)

	test("10 finished cartons point to the sale; an open sale replaces those hints by its own step", function()
		local p = workshop(200)
		put(p, "k1", "Karton", "FinishedStore.Slot1", TISCH)
		put(p, "k2", "Karton", A, TISCH)
		local o = Overview.compute(p, TISCH, NOW)
		assert(find(o, "CARTONS_IN_STORE").message == "1 Karton im Fertiglager: auf den Anhänger laden und verkaufen.")
		assert(find(o, "CARTONS_ON_VEHICLE").message == "1 Karton auf dem Anhänger: zum Händler (140) oder Privatkunden fahren.", find(o, "CARTONS_ON_VEHICLE").message)
		p.pendingSale = {id = "s", buyer = "Dealer", vehicleId = "Quad1", slotId = A, batchId = "k2", carrierId = HAND,
			quoteMin = 140, quoteMax = 140, dealerValue = 140, seed = 1}
		local open = Overview.compute(p, TISCH, NOW)
		assert(open.saleOpen and find(open, "SALE_OPEN").severity == "action")
		assert(find(open, "CARTONS_IN_STORE") == nil and find(open, "CARTONS_ON_VEHICLE") == nil)
	end)

	test("11 the slowest station of the selected recipe sets the pace", function()
		local stool = Overview.compute(workshop(200), HOCKER, NOW)
		assert(stool.recipe.takt == "Montagebank bestimmt den Takt: 8 s je Hocker.", stool.recipe.takt)
		local side = Overview.compute(workshop(200), TISCH, NOW)
		assert(side.recipe.takt == "Montagebank bestimmt den Takt: 14 s je Beistelltisch.", side.recipe.takt)
		assert(find(side, "TAKT").severity == "info" and find(side, "TAKT").stationId == "Montage")
		local unknown = Overview.compute(workshop(200), "Regal01", NOW)
		assert(unknown.recipe.id == HOCKER, "An unknown choice shows the first recipe")
		local missing = Overview.compute(workshop(200), nil, NOW)
		assert(missing.recipe.id == HOCKER)
	end)

	test("12 the selected recipe decides price, package and dealer value in messages and rows", function()
		local o = Overview.compute(workshop(200), TISCH, NOW)
		assert(find(o, "NO_WOOD").message == "Kein Holz: Kaufe beim Lieferanten ein Tischholzpaket für 80.", find(o, "NO_WOOD").message)
		assert(rowOf(o, "Rezept") == "Beistelltisch · Einkauf 80 · Händler 140", rowOf(o, "Rezept"))
		local broke = Overview.compute(workshop(70), TISCH, NOW)
		assert(find(broke, "NO_MONEY") and find(Overview.compute(workshop(70), HOCKER, NOW), "NO_WOOD"), "70 buys a stool package but not a table package")
		-- The price itself is enough, one less is not.
		assert(find(Overview.compute(workshop(60), HOCKER, NOW), "NO_WOOD") and find(Overview.compute(workshop(60), HOCKER, NOW), "NO_MONEY") == nil)
		assert(find(Overview.compute(workshop(59), HOCKER, NOW), "NO_MONEY") and find(Overview.compute(workshop(59), HOCKER, NOW), "NO_WOOD") == nil)
		assert(find(Overview.compute(workshop(80), TISCH, NOW), "NO_WOOD") and find(Overview.compute(workshop(79), TISCH, NOW), "NO_MONEY"))
	end)

	test("13 bottlenecks are ordered stop, action, limit, hint, info and keep the order the rules found them", function()
		local p = workshop(200)
		for i = 1, 4 do put(p, "k" .. i, "Karton", "FinishedStore.Slot" .. i) end
		put(p, "s", "Karton", A)
		put(p, "t", "Rohhocker", "Montage.Output")
		p.pendingSale = {id = "s", buyer = "Dealer", vehicleId = "Quad1", slotId = B, batchId = "s", carrierId = HAND,
			quoteMin = 100, quoteMax = 100, dealerValue = 100, seed = 1}
		local o = Overview.compute(p, HOCKER, NOW)
		local order: {number} = {}
		for _, item in o.bottlenecks do table.insert(order, Overview.SEVERITY_ORDER[item.severity]) end
		for i = 2, #order do assert(order[i - 1] <= order[i], "Out of order at " .. i .. ": " .. codes(o)) end
		assert(o.bottlenecks[1].code == "OUTPUT_FULL" and o.bottlenecks[2].code == "SALE_OPEN" and o.bottlenecks[3].code == "STORE_FULL", codes(o))
		assert(o.bottlenecks[#o.bottlenecks].code == "TAKT")
		assert(equal(codes(Overview.compute(p, HOCKER, NOW)), codes(o)), "The order must be repeatable")
	end)

	test("14 a running line with wood and free places has no bottleneck, only the pace note", function()
		local p = workshop(200)
		put(p, "w1", "Holzpaket", "Saege.Process")
		p.reservations["Saege.Output"] = {kind = "Production", batchId = "w1", finishAt = NOW + 4}
		put(p, "w2", "Holzpaket", "RawStore.Slot1")
		put(p, "w3", "Holzpaket", "Saege.Input")
		local o = Overview.compute(p, HOCKER, NOW)
		assert(Overview.primary(o) == nil, codes(o))
		assert(codes(o) == "TAKT", codes(o))
		assert(rowOf(o, "Engpass") == "keiner")
	end)

	test("15 a workshop without vehicle slots has no vehicle places, row or hint", function()
		local p = workshop(200, false)
		put(p, "k1", "Karton", "FinishedStore.Slot1")
		local o = Overview.compute(p, HOCKER, NOW)
		assert(o.places.vehicle == nil and o.places.store.used == 1)
		assert(rowOf(o, "Anhänger") == nil and rowOf(o, "Fertiglager") == "1/4 belegt")
		assert(find(o, "CARTONS_IN_STORE").message == "1 Karton im Fertiglager: verkaufen.", find(o, "CARTONS_IN_STORE").message)
	end)

	test("16 computing the overview never changes the profile", function()
		local p = workshop(200)
		put(p, "w1", "Holzpaket", "RawStore.Slot1", TISCH)
		put(p, "t", "Rohtisch", "Montage.Output", TISCH)
		p.pendingSale = {id = "s", buyer = "Private", vehicleId = "Quad1", slotId = A, batchId = "x", carrierId = HAND,
			quoteMin = 112, quoteMax = 168, dealerValue = 140, seed = 5}
		p.advance = {operationId = "a", batchId = "advance/a", amount = 60}
		local before = copy(p)
		Overview.compute(p, TISCH, NOW, true)
		Overview.rows(Overview.compute(p, HOCKER, NOW))
		assert(equal(before, p), "The profile changed")
		assert(table.isfrozen(Overview) and table.isfrozen(Overview.SEVERITY_ORDER))
	end)

	test("17 recipe stage names come from Recipes and stay in step with Recipe.stageNameFor", function()
		assert(Recipes.stageName("Karton", HOCKER) == "Hockerkarton" and Recipes.stageName("Karton", TISCH) == "Tischkarton")
		assert(Recipes.stageName("Rohtisch", TISCH) == "Rohtisch" and Recipes.stageName("Bausatz", TISCH) == "Bausatz · 10 Teile")
		assert(Recipes.stageName("Karton", nil) == "Hockerkarton" and Recipes.stageName("Karton", "Regal01") == "Hockerkarton")
		assert(Recipes.stageName("Unbekannt", TISCH) == "Unbekannt", "An unknown stage answers with its id")
	end)

	return {total = #passed + #failures, passed = passed, failures = failures}
end
