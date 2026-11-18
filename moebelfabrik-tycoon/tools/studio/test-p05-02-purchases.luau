--!strict
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0502Result"))
local result = Instance.new("StringValue")
result.Name = "P0502Result"
result.Parent = storage
local http = game:GetService("HttpService")
local scope = "P0502_" .. http:GenerateGUID(false):gsub("-", "")

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P05-02", checks = checks, scope = scope, store = "FactoryP0502_Test", economicReady = false}
	local ok, problem = xpcall(function()
		local factory = game:GetService("ServerScriptService").Factory
		local State = require(factory.State)
		local Persistence = require(factory.Persistence)
		local Transfers = require(factory.Transfers)
		local Recovery = require(factory.Recovery)
		local Purchases = require(factory.Purchases)
		local yard = workspace.CityGreybox.DeliveryYards.Holzlieferant
		local supplier = yard.P05Pickup
		local rawStore = workspace.P02Line.Stores.Rohstofflager
		local bound, err = Purchases.bind(supplier, rawStore)
		assert(bound, err)
		assert(#bound.slots.supplierIds == 4 and #bound.slots.rawIds == 4)
		assert(not Purchases.bind(rawStore, rawStore))
		local points = {}
		for id, point in bound.points do
			points[id] = point:GetFullName()
			if id:match("^Supplier") then
				local relative = yard.CFrame:PointToObjectSpace(point.WorldPosition)
				assert(math.abs(relative.X) < yard.Size.X / 2 and math.abs(relative.Z) < yard.Size.Z / 2)
				assert(point.Parent.Size.X > 0.60 * 25 / 7 and point.Parent.Size.Z > 0.45 * 25 / 7)
			end
		end
		table.insert(checks, "four marked supplier points and four physical raw slots bind to separate places")

		local function profile(money: number): any
			local p = State.newProfile(101)
			p.money = money
			p.locations = table.clone(bound.locations)
			p.locations.hand = State.newLocation("hand", "Carrier", 1, {"Holzpaket"})
			p.locations.trailer = State.newLocation("trailer", "VehicleSlot", 1, {"Holzpaket"})
			return p
		end
		local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "hand", ready = true}
		local request = {operationId = "buy-001", expectedRevision = 0}
		local function start(backend: any, state: any, token: string): any
			local controller = Persistence.new(101, backend)
			local loaded = controller.load(token .. "/" .. scope, 180, function(): any
				assert(state, "Unexpected seed")
				return {profileVersion = 1, state = state, progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
			end)
			assert(loaded.ok, loaded.code)
			return controller
		end
		local function rejects(state: any, reason: string)
			local value, writes = nil, 0
			local controller = start({read = function(): any return value end, update = function(_: string, transform: any): any
				writes += 1
				value = transform(value)
				return value
			end}, state, "reject")
			local checked = Purchases.buy(controller, actor, request, bound.slots, 180)
			assert(checked.code == reason and writes == 1 and value.data.state.money == state.money
				and value.data.state.revision == state.revision, checked.code)
		end
		rejects(profile(59), "NOT_ENOUGH_MONEY")
		local fullSupplier = profile(60)
		for i, id in bound.slots.supplierIds do fullSupplier.batches["held" .. i] = State.newBatch("held" .. i, 101, "Holzpaket", id) end
		rejects(fullSupplier, "SUPPLIER_FULL")
		local fullRaw = profile(60)
		for i, id in bound.slots.rawIds do fullRaw.batches["held" .. i] = State.newBatch("held" .. i, 101, "Holzpaket", id) end
		rejects(fullRaw, "RAW_STORE_FULL")
		table.insert(checks, "insufficient funds, a full supplier and full raw storage leave the confirmed balance unchanged")

		local real = Persistence.dataStore(game:GetService("DataStoreService"):GetDataStore(report.store, scope))
		local dropReply = false
		local writes = 0
		local controller = start({read = real.read, update = function(key: string, transform: any): any
			writes += 1
			local saved = real.update(key, transform)
			if dropReply then dropReply = false; error("simulated lost purchase response") end
			return saved
		end}, profile(60), "first")
		local foreign = table.clone(actor)
		foreign.ownerUserId = 102
		assert(Purchases.buy(controller, foreign, request, bound.slots, 180).code == "NOT_AUTHORIZED")
		local invalid = {operationId = request.operationId, expectedRevision = 0, price = 1}
		assert(Purchases.buy(controller, actor, invalid, bound.slots, 180).code == "INVALID_REQUEST" and writes == 1)
		table.insert(checks, "foreign actor and injected price cannot write")
		dropReply = true
		local pending = Purchases.buy(controller, actor, request, bound.slots, 180)
		assert(not pending.ok and pending.unknown and controller.snapshot().confirmed.data.state.money == 60)
		assert(not Purchases.buy(controller, actor, request, bound.slots, 180).ok and writes == 2)
		assert(controller.reconcile().ok)
		local receipt = Purchases.buy(controller, actor, request, bound.slots, 180).receipt
		assert(receipt.price == 60 and receipt.supplierId == "Supplier.Slot1" and receipt.rawSlotId == "RawStore.Slot1" and writes == 2)
		local saved = controller.snapshot().confirmed
		assert(saved.data.state.money == 0 and saved.data.state.revision == 1)
		assert(State.countAt(saved.data.state, receipt.supplierId) == 1 and State.countAt(saved.data.state, receipt.rawSlotId) == 0)
		assert(saved.data.state.reservations[receipt.rawSlotId].purchaseOperationId == request.operationId)
		local place = Recovery.plan(controller.snapshot(), 101, os.time(), points, {})
		assert(place.ok and place.placements[receipt.batchId].pointId == points[receipt.supplierId])
		assert(Purchases.buy(controller, actor, {operationId = request.operationId, expectedRevision = 1}, bound.slots, 180).code == "OPERATION_CONFLICT")
		table.insert(checks, "uncertain purchase reconciles to exactly one debit, supplier charge, delivery promise and receipt")

		local store = Transfers.new(saved.data.state)
		local time = os.time()
		local function move(from: string, to: string, name: string)
			local rid = name .. "/reserve"
			assert(Transfers.reserve(store, actor, {operationId = rid, expectedRevision = store.profile.revision,
				batchId = receipt.batchId, sourceId = from, targetId = to, quantity = 1}, time, 90).ok)
			assert(Transfers.commit(store, actor, {operationId = name .. "/commit", expectedRevision = store.profile.revision,
				claimId = rid}, time).ok)
		end
		move(receipt.supplierId, "hand", "load-a")
		move("hand", "trailer", "load-b")
		move("trailer", "hand", "unload-a")
		local wrong = Transfers.reserve(store, actor, {operationId = "wrong-raw-slot", expectedRevision = store.profile.revision,
			batchId = receipt.batchId, sourceId = "hand", targetId = "RawStore.Slot2", quantity = 1}, time, 90)
		assert(wrong.code == "DELIVERY_TARGET_REQUIRED")
		move("hand", receipt.rawSlotId, "unload-b")
		assert(not store.profile.reservations[receipt.rawSlotId] and store.profile.batches[receipt.batchId].locationId == receipt.rawSlotId)
		local nextData = saved.data
		nextData.state = store.profile
		assert(controller.save(nextData, 180).ok and controller.release().ok)
		local rejoined = start(real, nil, "second")
		local repeatResult = Purchases.buy(rejoined, actor, request, bound.slots, 180)
		assert(repeatResult.ok and repeatResult.receipt.batchId == receipt.batchId)
		local final = rejoined.snapshot().confirmed
		assert(final.data.state.money == 0 and State.countAt(final.data.state, receipt.rawSlotId) == 1)
		assert(final.data.state.receipts["unload-b/commit"] and rejoined.release().ok)
		table.insert(checks, "physical transfer path preserves the purchase history and consumes only its guaranteed raw slot")
		report.final = {money = 0, batchId = receipt.batchId, locationId = receipt.rawSlotId, stateRevision = final.data.state.revision,
			supplierPoint = points[receipt.supplierId], storageRevision = final.revision + 1}
	end, function(reason: any): string return debug.traceback(tostring(reason), 2) end)
	report.status, report.failure = if ok then "passed" else "failed", problem
	result.Value = http:JSONEncode(report)
end)
return {started = true, scope = scope}
