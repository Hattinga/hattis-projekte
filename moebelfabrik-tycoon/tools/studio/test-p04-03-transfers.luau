--!strict
-- P04-03 acceptance runner. Edit or Server in the private test place only.
-- Synthetic profiles; clones only the three server modules and always removes that copy.
-- This runner does not start play, touch real profiles, remotes or DataStores.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and (RunService:IsServer() or not RunService:IsRunning()), "Edit/Server only")
local ServerScriptService = game:GetService("ServerScriptService")
local Http = game:GetService("HttpService")
local source = ServerScriptService:FindFirstChild("Factory")
assert(source, "Factory is missing")
local testFolder = Instance.new("Folder")
testFolder.Name = "P0403TestCopy_" .. Http:GenerateGUID(false)
testFolder.Parent = ServerScriptService

local loaded, summary = xpcall(function(): any
	for _, name in {"State", "Actions", "Transfers"} do
		local module = source:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"), "Missing ModuleScript " .. name)
		module:Clone().Parent = testFolder
	end
	local State = require(testFolder:FindFirstChild("State") :: ModuleScript)
	local Actions = require(testFolder:FindFirstChild("Actions") :: ModuleScript)
	local Transfers = require(testFolder:FindFirstChild("Transfers") :: ModuleScript)
	assert(State.SCHEMA_VERSION == 2, "P04-03 requires schema 2")
	local MAX = 9007199254740991
	local passed: {string} = {}
	local failures: {any} = {}
	local calls = 0

	local function copy(value: any): any
		if type(value) ~= "table" then return value end
		local target = {}
		for key, item in value do target[key] = copy(item) end
		return target
	end
	local function equal(left: any, right: any): boolean
		if type(left) ~= type(right) then return false end
		if type(left) ~= "table" then return left == right end
		for key, item in left do if not equal(item, right[key]) then return false end end
		for key in right do if left[key] == nil then return false end end
		return true
	end
	local function size(map: any): number
		local count = 0
		for _ in map do count += 1 end
		return count
	end
	local function valid(profile: any): ()
		local ok, reason = State.validate(profile)
		assert(ok, "Invalid profile: " .. tostring(reason))
	end
	local function test(name: string, body: () -> ()): ()
		local ok, reason = xpcall(body, debug.traceback)
		if ok then table.insert(passed, name) else table.insert(failures, {name=name, error=tostring(reason)}) end
	end
	local function actor(kind: string?, carrier: string?, identity: string?): any
		return {ownerUserId=101, kind=kind or "Player", carrierLocationId=carrier or "hand",
			ready=true, actorId=identity or "Player/101"}
	end
	local function profile(sourceId: string?, stage: string?): any
		local p = State.newProfile(101)
		p.money = 123
		local all = {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"}
		for _, spec in {
			{"supplier/1", "Supplier", {"Holzpaket"}}, {"supplier/2", "Supplier", {"Holzpaket"}},
			{"raw/1", "RawStore", {"Holzpaket"}}, {"raw/2", "RawStore", {"Holzpaket"}},
			{"hand", "Carrier", all}, {"worker/1", "Carrier", all}, {"worker/2", "Carrier", all},
			{"band/1", "Band", {"Bausatz"}}, {"band/2", "Band", {"Bausatz"}},
			{"vehicle/1", "VehicleSlot", {"Holzpaket", "Karton"}},
			{"saw/output", "StationOutput", {"Bausatz"}}, {"assembly/input", "StationInput", {"Bausatz"}},
			{"finished/1", "FinishedStore", {"Karton"}}, {"recovery/1", "Recovery", all},
		} do
			p.locations[spec[1]] = State.newLocation(spec[1], spec[2], 1, spec[3])
		end
		p.batches.a = State.newBatch("a", 101, stage or "Holzpaket", sourceId or "raw/1")
		return p
	end
	local function fixture(sourceId: string?, stage: string?): any
		local p = profile(sourceId, stage)
		valid(p)
		local store = Transfers.new(p)
		assert(type(store) == "table" and store.profile, "new must return a shared profile wrapper")
		valid(store.profile)
		return store
	end
	local function request(store: any, operationId: string, batchId: string, from: string, to: string): any
		return {operationId=operationId, expectedRevision=store.profile.revision, batchId=batchId,
			sourceId=from, targetId=to, quantity=1}
	end
	local function invoke(method: string, store: any, who: any, payload: any, now: number, ttl: number?): any
		calls += 1
		local response
		if method == "reserve" then response = Transfers.reserve(store, who, payload, now, ttl or 10)
		elseif method == "commit" then response = Transfers.commit(store, who, payload, now)
		elseif method == "cancel" then response = Transfers.cancel(store, who, payload, now)
		else error("Unknown test method") end
		assert(type(response) == "table" and type(response.ok) == "boolean", "Missing result envelope")
		assert(type(response.code) == "string" and type(response.message) == "string" and #response.message > 0,
			"Missing result code/feedback")
		return response
	end
	local function success(method: string, store: any, who: any, payload: any, now: number, ttl: number?): any
		local before = store.profile
		local snapshot = copy(before)
		local revision = before.revision
		local response = invoke(method, store, who, payload, now, ttl)
		local code = if method == "reserve" then "RESERVED" elseif method == "commit" then "COMMITTED" else "CANCELLED"
		assert(response.ok and response.code == code, code .. " expected, got " .. tostring(response.code))
		assert(store.profile ~= before, "Successful new operation did not publish a candidate")
		assert(equal(before, snapshot), "Successful operation mutated the previous profile")
		assert(store.profile.revision == revision + 1 and response.revision == revision + 1, "Revision must advance once")
		assert(store.profile.money == snapshot.money, "Transfer changed money")
		assert(size(store.profile.batches) == size(snapshot.batches), "Transfer created/removed a batch")
		for batchId, batch in snapshot.batches do
			local current = store.profile.batches[batchId]
			for _, key in {"id", "ownerUserId", "recipeId", "recipeVersion", "stage", "quantity"} do
				assert(current[key] == batch[key], "Transfer changed batch " .. batchId .. "/" .. key)
			end
		end
		valid(store.profile)
		return response
	end
	local function rejected(method: string, store: any, who: any, payload: any, now: number, code: string?, ttl: number?): any
		local before = store.profile
		local snapshot = copy(before)
		local response = invoke(method, store, who, payload, now, ttl)
		assert(not response.ok, "Expected rejection, got " .. response.code)
		if code then assert(response.code == code, code .. " expected, got " .. response.code) end
		assert(store.profile == before and equal(before, snapshot), "Rejected operation changed profile/reference")
		return response
	end
	local function reserve(store: any, who: any, operationId: string, batchId: string, from: string, to: string,
		now: number?, ttl: number?): (any, any)
		local payload = request(store, operationId, batchId, from, to)
		local response = success("reserve", store, who, payload, now or 100, ttl)
		assert(response.claimId == operationId, "claimId must be the reserve operation ID")
		assert(store.profile.batches[batchId].locationId == from, "Reserve moved stock")
		assert(store.profile.claims[operationId], "Successful reserve has no claim")
		return response, payload
	end
	local function finish(store: any, who: any, operationId: string, claimId: string, now: number?): (any, any)
		local payload = {operationId=operationId, expectedRevision=store.profile.revision, claimId=claimId}
		return success("commit", store, who, payload, now or 101), payload
	end
	local function hop(store: any, who: any, operationId: string, batchId: string, from: string, to: string): ()
		reserve(store, who, operationId, batchId, from, to)
		finish(store, who, operationId .. "/commit", operationId)
		assert(store.profile.batches[batchId].locationId == to, "Commit did not move exactly to target")
		assert(store.profile.claims[operationId] == nil, "Commit did not consume its claim")
	end
	local function replay(method: string, store: any, who: any, payload: any, expected: any, now: number): any
		local before, snapshot = store.profile, copy(store.profile)
		local response = invoke(method, store, who, payload, now)
		assert(equal(response, expected), "Replay did not return the original result")
		assert(response ~= expected, "Replay returned the caller's original result object")
		assert(store.profile == before and equal(before, snapshot), "Replay changed stock/revision/reference")
		return response
	end
	local function sweep(store: any, now: number, count: number, rejectedOverflow: boolean?): any
		local before, snapshot = store.profile, copy(store.profile)
		calls += 1
		local response = Transfers.expireClaims(store, now)
		assert(type(response) == "table", "Sweep must return an EXPIRED result")
		if rejectedOverflow then
			assert(not response.ok, "Overflowing sweep succeeded")
			assert(store.profile == before and equal(before, snapshot), "Failed sweep mutated state")
		else
			assert(response.ok and response.code == "EXPIRED" and response.expired == count, "Wrong sweep count/result")
			assert(equal(before, snapshot), "Sweep changed previous profile")
			if count == 0 then
				assert(store.profile == before and response.revision == before.revision, "Empty sweep advanced/published state")
			else
				assert(store.profile ~= before and response.revision == snapshot.revision + 1
					and store.profile.revision == snapshot.revision + 1, "Sweep must advance revision once")
			end
			assert(equal(store.profile.batches, snapshot.batches) and equal(store.profile.reservations, snapshot.reservations)
				and equal(store.profile.receipts, snapshot.receipts), "Sweep changed stock, promises or receipts")
			valid(store.profile)
		end
		return response
	end
	local function deliveryProfile(): any
		local p = profile("supplier/1")
		p.reservations["raw/1"] = {kind="Delivery", batchId="a", purchaseOperationId="synthetic/purchase/a"}
		valid(p)
		return p
	end
	local function freezeDeep(value: any): ()
		if type(value) ~= "table" or table.isfrozen(value) then return end
		for _, item in value do freezeDeep(item) end
		table.freeze(value)
	end

	test("01 pickup/place: four revision steps and exact Return lifetime", function()
		local store, who = fixture(), actor()
		reserve(store, who, "normal/pick", "a", "raw/1", "hand")
		assert(State.countAt(store.profile, "raw/1") == 1 and State.countAt(store.profile, "hand") == 0)
		assert(size(store.profile.reservations) == 0)
		finish(store, who, "normal/pick/commit", "normal/pick")
		local promise = store.profile.reservations["raw/1"]
		assert(promise and promise.kind == "Return" and promise.batchId == "a"
			and promise.actorId == who.actorId and promise.carrierId == "hand")
		assert(State.countAt(store.profile, "raw/1") == 0 and State.countAt(store.profile, "hand") == 1)
		reserve(store, who, "normal/place", "a", "hand", "raw/2")
		assert(store.profile.reservations["raw/1"], "Place reservation removed Return early")
		finish(store, who, "normal/place/commit", "normal/place")
		assert(store.profile.batches.a.locationId == "raw/2" and store.profile.revision == 4)
		assert(size(store.profile.claims) == 0 and size(store.profile.reservations) == 0
			and size(store.profile.receipts) == 4)
	end)
	test("02 physical return to raw origin", function()
		local store, who = fixture(), actor()
		hop(store, who, "return/pick", "a", "raw/1", "hand")
		hop(store, who, "return/place", "a", "hand", "raw/1")
		assert(store.profile.batches.a.locationId == "raw/1" and size(store.profile.reservations) == 0)
	end)
	test("03 physical StationOutput return is precise", function()
		local store, who = fixture("saw/output", "Bausatz"), actor()
		hop(store, who, "output/pick", "a", "saw/output", "hand")
		hop(store, who, "output/return", "a", "hand", "saw/output")
		local other = fixture("assembly/input", "Bausatz")
		hop(other, who, "other/pick", "a", "assembly/input", "hand")
		rejected("reserve", other, who, request(other, "other/output", "a", "hand", "saw/output"), 102)
	end)
	test("04 concurrent source claims: only one wins", function()
		local store, first = fixture(), actor()
		local second = actor("Worker", "worker/1", "Worker/one")
		reserve(store, first, "source/one", "a", "raw/1", "hand")
		rejected("reserve", store, second, request(store, "source/two", "a", "raw/1", "worker/1"), 100)
		local stale = request(store, "source/stale", "a", "raw/1", "worker/1")
		stale.expectedRevision = 0
		rejected("reserve", store, second, stale, 100, "STALE_REVISION")
		assert(size(store.profile.claims) == 1 and store.profile.batches.a.locationId == "raw/1")
	end)
	test("05 concurrent sources cannot claim the same carrier", function()
		local p, who = profile(), actor()
		p.batches.b = State.newBatch("b", 101, "Holzpaket", "raw/2")
		local store = Transfers.new(p)
		reserve(store, who, "carrier/one", "a", "raw/1", "hand")
		rejected("reserve", store, who, request(store, "carrier/two", "b", "raw/2", "hand"), 100)
		assert(size(store.profile.claims) == 1 and store.profile.batches.b.locationId == "raw/2")
	end)
	test("06 two carried batches cannot claim one destination", function()
		local p, first = profile(), actor()
		p.batches.b = State.newBatch("b", 101, "Holzpaket", "raw/2")
		local store, second = Transfers.new(p), actor("Worker", "worker/1", "Worker/one")
		hop(store, first, "target/pick/a", "a", "raw/1", "hand")
		hop(store, second, "target/pick/b", "b", "raw/2", "worker/1")
		reserve(store, first, "target/one", "a", "hand", "recovery/1")
		rejected("reserve", store, second, request(store, "target/two", "b", "worker/1", "recovery/1"), 100)
		assert(size(store.profile.claims) == 1 and size(store.profile.reservations) == 2)
	end)
	test("07 stale commit retains claim; fresh retry succeeds", function()
		local store, who = fixture(), actor()
		reserve(store, who, "stale/pick", "a", "raw/1", "hand")
		rejected("commit", store, who, {operationId="stale/commit", expectedRevision=0, claimId="stale/pick"},
			101, "STALE_REVISION")
		assert(store.profile.claims["stale/pick"] and store.profile.receipts["stale/commit"] == nil)
		finish(store, who, "stale/fresh", "stale/pick")
	end)
	test("08 reserve/commit receipts replay before revision, location and TTL", function()
		local store, who = fixture(), actor()
		local reserved, reserveRequest = reserve(store, who, "replay/pick", "a", "raw/1", "hand")
		local committed, commitRequest = finish(store, who, "replay/pick/commit", "replay/pick")
		hop(store, who, "replay/place", "a", "hand", "raw/2")
		replay("reserve", store, who, reserveRequest, reserved, 1000)
		replay("commit", store, who, commitRequest, committed, 1000)
		assert(store.profile.batches.a.locationId == "raw/2" and size(store.profile.claims) == 0)
	end)
	test("09 payload conflicts outrank stale revision", function()
		local store, who = fixture(), actor()
		local _, original = reserve(store, who, "conflict/reserve", "a", "raw/1", "hand")
		for field, value in {batchId="b", sourceId="raw/2", targetId="worker/1", quantity=2, expectedRevision=50} do
			local changed = copy(original)
			changed[field] = value
			rejected("reserve", store, who, changed, 1000, "OPERATION_CONFLICT")
		end
		rejected("commit", store, who, {operationId=original.operationId, expectedRevision=0, claimId=original.operationId},
			1000, "OPERATION_CONFLICT")
		local _, committed = finish(store, who, "conflict/commit", original.operationId)
		for field, value in {claimId="missing/claim", expectedRevision=99} do
			local changed = copy(committed)
			changed[field] = value
			rejected("commit", store, who, changed, 1000, "OPERATION_CONFLICT")
		end
	end)
	test("10 actor identity/kind/carrier conflicts bind receipts", function()
		local store, who = fixture(), actor()
		local _, payload = reserve(store, who, "actor/reserve", "a", "raw/1", "hand")
		for field, value in {actorId="Player/another", kind="Worker", carrierLocationId="worker/1"} do
			local changed = copy(who)
			changed[field] = value
			rejected("reserve", store, changed, payload, 1000, "OPERATION_CONFLICT")
		end
		local foreign = copy(who)
		foreign.ownerUserId = 202
		rejected("reserve", store, foreign, payload, 1000, "NOT_AUTHORIZED")
		local blocked = copy(who)
		blocked.ready = false
		rejected("reserve", store, blocked, payload, 1000, "NOT_READY")
	end)
	test("11 cancel receipts replay; cancel never moves stock", function()
		local store, who = fixture(), actor()
		reserve(store, who, "cancel/pick", "a", "raw/1", "hand")
		local payload = {operationId="cancel/finish", expectedRevision=store.profile.revision, claimId="cancel/pick"}
		local cancelled = success("cancel", store, who, payload, 101)
		assert(store.profile.batches.a.locationId == "raw/1" and size(store.profile.claims) == 0)
		replay("cancel", store, who, payload, cancelled, 1000)
		local changed = copy(payload)
		changed.claimId = "different"
		rejected("cancel", store, who, changed, 1000, "OPERATION_CONFLICT")
	end)
	test("12 exact TTL boundary and idempotent sweep", function()
		local store, who = fixture(), actor()
		local reserved, payload = reserve(store, who, "ttl/pick", "a", "raw/1", "hand", 100, 10)
		assert(store.profile.claims["ttl/pick"].expiresAt == 110)
		sweep(store, 109.999, 0)
		rejected("commit", store, who, {operationId="ttl/at-boundary", expectedRevision=store.profile.revision,
			claimId="ttl/pick"}, 110)
		assert(store.profile.claims["ttl/pick"] and store.profile.batches.a.locationId == "raw/1")
		sweep(store, 110, 1)
		sweep(store, 110, 0)
		sweep(store, 1000, 0)
		replay("reserve", store, who, payload, reserved, 1000)
		assert(size(store.profile.claims) == 0)
		local beforeBoundary = fixture()
		reserve(beforeBoundary, who, "ttl/before", "a", "raw/1", "hand", 100, 10)
		finish(beforeBoundary, who, "ttl/before/commit", "ttl/before", 109.999)
	end)
	test("13 successful reserve replaces expired overlaps only", function()
		local store, who = fixture(), actor()
		reserve(store, who, "expired/old", "a", "raw/1", "hand", 100, 10)
		local bad = request(store, "expired/rejected", "a", "raw/1", "missing")
		rejected("reserve", store, who, bad, 110)
		assert(store.profile.claims["expired/old"], "Rejected reserve cleaned expired state")
		reserve(store, who, "expired/new", "a", "raw/1", "hand", 110, 10)
		assert(store.profile.claims["expired/old"] == nil and size(store.profile.claims) == 1)
		assert(store.profile.receipts["expired/old"], "Replacement removed old receipt")
	end)
	test("14 sweep removes multiple expired claims in one revision", function()
		local p = profile()
		p.batches.b = State.newBatch("b", 101, "Holzpaket", "raw/2")
		local store = Transfers.new(p)
		reserve(store, actor(), "sweep/a", "a", "raw/1", "hand", 100, 10)
		reserve(store, actor("Worker", "worker/1", "Worker/one"), "sweep/b", "b", "raw/2", "worker/1", 100, 10)
		sweep(store, 110, 2)
		assert(size(store.profile.claims) == 0)
	end)
	test("15 expired place claim preserves carried stock and Return", function()
		local store, who = fixture(), actor()
		hop(store, who, "carry/pick", "a", "raw/1", "hand")
		local promise = copy(store.profile.reservations["raw/1"])
		reserve(store, who, "carry/place", "a", "hand", "raw/2", 100, 10)
		sweep(store, 110, 1)
		assert(store.profile.batches.a.locationId == "hand" and equal(store.profile.reservations["raw/1"], promise))
		hop(store, who, "carry/return", "a", "hand", "raw/1")
	end)
	test("16 cancelled place and consumed pickup preserve Return", function()
		local store, who = fixture(), actor()
		hop(store, who, "abort/pick", "a", "raw/1", "hand")
		local promise = copy(store.profile.reservations["raw/1"])
		reserve(store, who, "abort/place", "a", "hand", "raw/2")
		success("cancel", store, who, {operationId="abort/cancel", expectedRevision=store.profile.revision,
			claimId="abort/place"}, 101)
		assert(store.profile.batches.a.locationId == "hand" and equal(store.profile.reservations["raw/1"], promise))
		for _, method in {"cancel", "commit"} do
			rejected(method, store, who, {operationId="abort/consumed/" .. method,
				expectedRevision=store.profile.revision, claimId="abort/pick"}, 102)
		end
	end)
	test("17 foreign stock/actor cannot occupy a Return promise", function()
		local p, first = profile(), actor()
		p.batches.b = State.newBatch("b", 101, "Holzpaket", "raw/2")
		local store, second = Transfers.new(p), actor("Worker", "worker/1", "Worker/one")
		hop(store, first, "blocked/a", "a", "raw/1", "hand")
		hop(store, second, "blocked/b", "b", "raw/2", "worker/1")
		rejected("reserve", store, second, request(store, "blocked/foreign-stock", "b", "worker/1", "raw/1"), 102)
		local impostor = actor("Player", "hand", "Player/different")
		rejected("reserve", store, impostor, request(store, "blocked/foreign-actor", "a", "hand", "raw/1"), 102)
		assert(size(store.profile.reservations) == 2)
	end)
	test("18 Delivery survives four hops and full finished store", function()
		local p, who = deliveryProfile(), actor()
		p.batches.finished = State.newBatch("finished", 101, "Karton", "finished/1")
		local store = Transfers.new(p)
		local promise = copy(store.profile.reservations["raw/1"])
		for index, pair in {{"supplier/1", "hand"}, {"hand", "vehicle/1"}, {"vehicle/1", "hand"}, {"hand", "raw/1"}} do
			hop(store, who, "delivery/hop/" .. index, "a", pair[1], pair[2])
			if index < 4 then assert(equal(store.profile.reservations["raw/1"], promise), "Delivery released early") end
		end
		assert(store.profile.batches.a.locationId == "raw/1" and store.profile.batches.finished.locationId == "finished/1")
		assert(size(store.profile.reservations) == 0 and size(store.profile.claims) == 0 and store.profile.revision == 8)
	end)
	test("19 Delivery allows only its designated raw slot and batch", function()
		local p, who = deliveryProfile(), actor()
		p.batches.b = State.newBatch("b", 101, "Holzpaket", "raw/2")
		local store, second = Transfers.new(p), actor("Worker", "worker/1", "Worker/one")
		hop(store, who, "delivery/pick", "a", "supplier/1", "hand")
		-- Free raw/2 physically; its Return still belongs to b, not the paid delivery a.
		hop(store, second, "delivery/other", "b", "raw/2", "worker/1")
		rejected("reserve", store, who, request(store, "delivery/wrong-slot", "a", "hand", "raw/2"), 102)
		rejected("reserve", store, second, request(store, "delivery/wrong-batch", "b", "worker/1", "raw/1"), 102)
		assert(store.profile.reservations["raw/1"].kind == "Delivery")
	end)
	test("20 Delivery wrong raw slot is denied even when unreserved and empty", function()
		local store, who = Transfers.new(deliveryProfile()), actor()
		hop(store, who, "designated/pick", "a", "supplier/1", "hand")
		assert(State.countAt(store.profile, "raw/2") == 0 and store.profile.reservations["raw/2"] == nil)
		rejected("reserve", store, who, request(store, "designated/wrong", "a", "hand", "raw/2"), 102)
	end)
	test("21 Delivery/Return survive place cancellation, expiry and physical return", function()
		local store, who = Transfers.new(deliveryProfile()), actor()
		hop(store, who, "promises/pick", "a", "supplier/1", "hand")
		local promises = copy(store.profile.reservations)
		reserve(store, who, "promises/place/cancel", "a", "hand", "vehicle/1")
		success("cancel", store, who, {operationId="promises/cancel", expectedRevision=store.profile.revision,
			claimId="promises/place/cancel"}, 101)
		assert(equal(store.profile.reservations, promises) and store.profile.batches.a.locationId == "hand")
		reserve(store, who, "promises/place/expire", "a", "hand", "vehicle/1", 100, 10)
		sweep(store, 110, 1)
		assert(equal(store.profile.reservations, promises) and store.profile.batches.a.locationId == "hand")
		hop(store, who, "promises/return", "a", "hand", "supplier/1")
		assert(size(store.profile.reservations) == 1 and store.profile.reservations["raw/1"].kind == "Delivery")
		assert(store.profile.batches.a.locationId == "supplier/1")
	end)
	test("22 missing/future claim and wrong claim actor fail atomically", function()
		local store, who = fixture(), actor()
		for _, method in {"commit", "cancel"} do
			rejected(method, store, who, {operationId="missing/" .. method, expectedRevision=0, claimId="missing"}, 100)
		end
		reserve(store, who, "wrong/claim", "a", "raw/1", "hand")
		for _, changed in {actor("Player", "hand", "Player/different"), actor("Worker", "worker/1", "Worker/one")} do
			for _, method in {"commit", "cancel"} do
				rejected(method, store, changed, {operationId="wrong/" .. changed.actorId .. "/" .. method,
					expectedRevision=store.profile.revision, claimId="wrong/claim"}, 101)
			end
		end
	end)
	test("23 malformed requests, quantities and server time fail atomically", function()
		local store, who = fixture(), actor()
		for _, payload in {false, "request", {}, {operationId="bad/only-id"},
			setmetatable(request(store, "bad/meta", "a", "raw/1", "hand"), {})} do
			rejected("reserve", store, who, payload, 100)
		end
		rejected("reserve", store, who, nil, 100)
		for _, quantity in {0, -1, 2, 0.5, 0/0, math.huge, "1"} do
			local payload = request(store, "bad/quantity", "a", "raw/1", "hand")
			payload.quantity = quantity
			rejected("reserve", store, who, payload, 100)
		end
		for _, now in {-1, 0/0, math.huge} do
			rejected("reserve", store, who, request(store, "bad/time", "a", "raw/1", "hand"), now)
		end
		for _, ttl in {-1, 0, 0/0, math.huge} do
			rejected("reserve", store, who, request(store, "bad/ttl", "a", "raw/1", "hand"), 100, nil, ttl)
		end
		rejected("reserve", store, who, request(store, "bad/overflow-time", "a", "raw/1", "hand"), MAX, nil, 1)
	end)
	test("24 full target, wrong stage and foreign owner fail atomically", function()
		local p, who = profile(), actor()
		p.batches.b = State.newBatch("b", 101, "Holzpaket", "raw/2")
		local store = Transfers.new(p)
		hop(store, who, "full/occupy", "b", "raw/2", "hand")
		rejected("reserve", store, who, request(store, "full/target", "a", "raw/1", "hand"), 100)
		store = fixture()
		hop(store, who, "stage/pick", "a", "raw/1", "hand")
		rejected("reserve", store, who, request(store, "stage/wrong", "a", "hand", "finished/1"), 102)
		local foreign = copy(who)
		foreign.ownerUserId = 202
		rejected("reserve", store, foreign, request(store, "owner/wrong", "a", "hand", "raw/1"), 102, "NOT_AUTHORIZED")
	end)
	test("25 mutated Return identity/material and malformed records are rejected", function()
		for field, value in {stage="Karton", recipeVersion=2, quantity=2} do
			local store, who = fixture(), actor()
			hop(store, who, "invalid/pick", "a", "raw/1", "hand")
			store.profile.batches.a[field] = value
			assert(not State.validate(store.profile), "Mismatched Return material remained valid")
			rejected("reserve", store, who, request(store, "invalid/return", "a", "hand", "raw/1"), 102)
		end
		local store, who = fixture(), actor()
		reserve(store, who, "invalid/claim", "a", "raw/1", "hand")
		store.profile.claims["invalid/claim"].extra = true
		assert(not State.validate(store.profile), "Claim record is not closed")
		rejected("commit", store, who, {operationId="invalid/commit", expectedRevision=store.profile.revision,
			claimId="invalid/claim"}, 101)
	end)
	test("26 returned results, requests and actors do not alias receipts/claims", function()
		local store, who = fixture(), actor()
		local response, payload = reserve(store, who, "copies/reserve", "a", "raw/1", "hand")
		local originalResponse, originalRequest, originalActor = copy(response), copy(payload), copy(who)
		local snapshot = copy(store.profile)
		response.code, response.revision, response.claimId = "tampered", -1, "tampered"
		payload.targetId, payload.expectedRevision, who.actorId = "worker/1", -1, "tampered"
		assert(equal(store.profile, snapshot), "Caller mutated stored receipt/claim through an alias")
		local repeated = replay("reserve", store, originalActor, originalRequest, originalResponse, 101)
		repeated.code, repeated.claimId = "tampered-again", "bad"
		replay("reserve", store, originalActor, originalRequest, originalResponse, 101)
		local committed, commitRequest = finish(store, originalActor, "copies/commit", "copies/reserve")
		local savedResponse, savedRequest = copy(committed), copy(commitRequest)
		snapshot = copy(store.profile)
		committed.code, commitRequest.claimId = "tampered", "tampered"
		assert(equal(store.profile, snapshot), "Commit result/request aliased stored receipt")
		replay("commit", store, originalActor, savedRequest, savedResponse, 1000)
	end)
	test("27 JSON roundtrip preserves active claims, promises and replay receipts", function()
		local store, who = Transfers.new(deliveryProfile()), actor()
		local reserved, payload = reserve(store, who, "json/pick", "a", "supplier/1", "hand")
		local decoded = Http:JSONDecode(Http:JSONEncode(store.profile))
		valid(decoded)
		store = Transfers.new(decoded)
		replay("reserve", store, who, payload, reserved, 101)
		local committed, commitRequest = finish(store, who, "json/commit", "json/pick")
		decoded = Http:JSONDecode(Http:JSONEncode(store.profile))
		valid(decoded)
		store = Transfers.new(decoded)
		replay("commit", store, who, commitRequest, committed, 1000)
		assert(store.profile.reservations["supplier/1"].kind == "Return"
			and store.profile.reservations["raw/1"].kind == "Delivery" and store.profile.batches.a.locationId == "hand")
	end)
	test("28 frozen old profile works; shared store exposes current state", function()
		local store, who = fixture(), actor()
		local otherObserver = store
		local previous = store.profile
		freezeDeep(previous)
		reserve(store, who, "frozen/pick", "a", "raw/1", "hand")
		assert(otherObserver.profile == store.profile and otherObserver.profile ~= previous)
		freezeDeep(store.profile)
		finish(otherObserver, who, "frozen/commit", "frozen/pick")
		assert(store.profile.batches.a.locationId == "hand" and previous.batches.a.locationId == "raw/1")
	end)
	test("29 frozen RuntimeStore is rejected before publication", function()
		local store, who = fixture(), actor()
		table.freeze(store)
		rejected("reserve", store, who, request(store, "frozen/store", "a", "raw/1", "hand"), 100)
	end)
	test("30 revision overflow rejects reserve, commit, cancel and nonempty sweep", function()
		local p, who = profile(), actor()
		p.revision = MAX
		local store = Transfers.new(p)
		rejected("reserve", store, who, request(store, "overflow/reserve", "a", "raw/1", "hand"), 100)
		sweep(store, 110, 0)
		p = profile()
		p.revision = MAX - 1
		store = Transfers.new(p)
		local reserved, reserveRequest = reserve(store, who, "overflow/last", "a", "raw/1", "hand", 100, 10)
		assert(store.profile.revision == MAX)
		for _, method in {"commit", "cancel"} do
			rejected(method, store, who, {operationId="overflow/" .. method, expectedRevision=MAX,
				claimId="overflow/last"}, 101)
		end
		sweep(store, 110, 1, true)
		replay("reserve", store, who, reserveRequest, reserved, 1000)
	end)
	test("31 Worker and Band share the exact commit path and assigned carrier", function()
		for _, spec in {{"Worker", "worker/1", "Worker/one", "raw/1", "Holzpaket", "raw/2"},
			{"Band", "band/1", "Band/one", "saw/output", "Bausatz", "assembly/input"}} do
			local store, who = fixture(spec[4], spec[5]), actor(spec[1], spec[2], spec[3])
			hop(store, who, "shared/" .. spec[1] .. "/pick", "a", spec[4], spec[2])
			local wrong = copy(who)
			wrong.carrierLocationId = if spec[1] == "Band" then "band/2" else "worker/2"
			rejected("reserve", store, wrong, request(store, "shared/wrong/" .. spec[1], "a", spec[2], spec[6]), 102)
			hop(store, who, "shared/" .. spec[1] .. "/place", "a", spec[2], spec[6])
			assert(store.profile.revision == 4 and size(store.profile.reservations) == 0)
		end
	end)
	test("32 shared Actions enforces claim locks, exact own claim and expiry without mutation", function()
		local store, who = fixture(), actor()
		reserve(store, who, "common/claim", "a", "raw/1", "hand", 100, 10)
		local before, snapshot = store.profile, copy(store.profile)
		local second = actor("Worker", "worker/1", "Worker/one")
		local other = request(store, "common/other", "a", "raw/1", "worker/1")
		assert(Actions.checkTransfer(before, second, other, 100).code == "SOURCE_RESERVED")
		assert(Actions.checkTransfer(before, second, other, 100, "common/claim").code == "SOURCE_RESERVED")
		local own = request(store, "common/commit", "a", "raw/1", "hand")
		assert(Actions.checkTransfer(before, who, own, 100, "common/claim").ok)
		assert(Actions.checkTransfer(before, second, other).code == "SOURCE_RESERVED")
		assert(Actions.checkTransfer(before, second, other, 110).ok)
		assert(store.profile == before and equal(before, snapshot), "Actions mutated claims")
	end)
	test("33 shared Actions enforces Return, Delivery and precise output return", function()
		local who = actor()
		local store = fixture("assembly/input", "Bausatz")
		hop(store, who, "common/output/pick", "a", "assembly/input", "hand")
		assert(Actions.checkTransfer(store.profile, who,
			request(store, "common/output/new", "a", "hand", "saw/output"), 102).code == "OUTPUT_REQUIRES_RETURN")
		local imposter = copy(who)
		imposter.actorId = "Player/other"
		assert(Actions.checkTransfer(store.profile, imposter,
			request(store, "common/output/wrong", "a", "hand", "assembly/input"), 102).code == "RETURN_MISMATCH")
		store = fixture("saw/output", "Bausatz")
		hop(store, who, "common/output/real", "a", "saw/output", "hand")
		assert(Actions.checkTransfer(store.profile, who,
			request(store, "common/output/return", "a", "hand", "saw/output"), 102).ok)
		store = Transfers.new(deliveryProfile())
		hop(store, who, "common/delivery/pick", "a", "supplier/1", "hand")
		assert(Actions.checkTransfer(store.profile, who,
			request(store, "common/delivery/wrong", "a", "hand", "raw/2"), 102).code == "DELIVERY_TARGET_REQUIRED")
		assert(Actions.checkTransfer(store.profile, who,
			request(store, "common/delivery/right", "a", "hand", "raw/1"), 102).ok)
		local p = profile("hand")
		assert(Actions.checkTransfer(p, who,
			{operationId="common/no-return",expectedRevision=0,batchId="a",sourceId="hand",targetId="raw/2",quantity=1},
			102).code == "RETURN_REQUIRED")
	end)
	test("34 forged completion hop and missing parent Reserve are rejected", function()
		for _, corruption in {"origin", "missing-parent", "actor"} do
			local store, who = fixture(), actor()
			reserve(store, who, "history/reserve", "a", "raw/1", "hand")
			local _, payload = finish(store, who, "history/commit", "history/reserve")
			local receipt = store.profile.receipts["history/commit"]
			if corruption == "origin" then receipt.result.sourceId = "raw/2"
			elseif corruption == "actor" then receipt.actorId = "Player/other"
			else receipt.request.claimId, receipt.result.claimId = "missing/reserve", "missing/reserve" end
			assert(not State.validate(store.profile), "Forged historical receipt accepted: " .. corruption)
			rejected("commit", store, who, payload, 1000, "INVALID_STATE")
		end
	end)
	test("35 cancelled claim cannot be resurrected and committed", function()
		local store, who = fixture(), actor()
		reserve(store, who, "history/cancel/reserve", "a", "raw/1", "hand")
		local claim = copy(store.profile.claims["history/cancel/reserve"])
		success("cancel", store, who, {operationId="history/cancel", expectedRevision=store.profile.revision,
			claimId=claim.id}, 101)
		store.profile.claims[claim.id] = claim
		assert(not State.validate(store.profile), "Cancelled claim remained active")
		rejected("commit", store, who, {operationId="history/after-cancel",expectedRevision=store.profile.revision,
			claimId=claim.id}, 102, "INVALID_STATE")
	end)
	test("36 completion ordering and one terminal receipt per claim are enforced", function()
		for _, corruption in {"before-reserve", "second-completion"} do
			local p, who = profile(), actor()
			p.revision = 5
			local store = Transfers.new(p)
			reserve(store, who, "history/order/reserve", "a", "raw/1", "hand")
			success("cancel", store, who, {operationId="history/order/cancel",expectedRevision=store.profile.revision,
				claimId="history/order/reserve"}, 101)
			local receipt = store.profile.receipts["history/order/cancel"]
			if corruption == "before-reserve" then receipt.request.expectedRevision, receipt.result.revision = 0, 1
			else
				local duplicate = copy(receipt)
				duplicate.request.operationId = "history/order/duplicate"
				duplicate.request.expectedRevision, duplicate.result.revision = 7, 8
				store.profile.revision = 8
				store.profile.receipts[duplicate.request.operationId] = duplicate
			end
			assert(not State.validate(store.profile), "Contradictory completion history accepted: " .. corruption)
		end
	end)
	return {task="P04-03", status=if #failures == 0 then "passed" else "failed", checks=#passed + #failures,
		passed=#passed, failed=#failures, calls=calls, passedCases=passed, failures=failures,
		profilesArtificial=true, dataStoreAccess=false, remotes=false, persisted=false}
end, debug.traceback)

testFolder:Destroy()
assert(loaded, tostring(summary))
return summary
