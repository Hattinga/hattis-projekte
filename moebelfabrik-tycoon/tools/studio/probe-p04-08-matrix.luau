--!strict
-- Manual, two-stage Studio-only probe. The second stage requires a fresh Studio server.
return function(phase: string, suppliedScope: string?): any
	assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
	local runService = game:GetService("RunService")
	assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning(), "Studio Server only")
	assert(phase == "A" or phase == "B", "Unknown probe phase")
	local storage = game:GetService("ServerStorage")
	local http = game:GetService("HttpService")
	assert(not storage:FindFirstChild("P0408Matrix"), "Start a fresh Server-Play for the next phase")
	local scope = if phase == "A" then "P0408_" .. http:GenerateGUID(false):gsub("-", "") else suppliedScope
	assert(type(scope) == "string" and #scope == 38 and scope:match("^P0408_%x+$"), "Invalid isolated scope")
	local result = Instance.new("StringValue")
	result.Name = "P0408Matrix"
	result.Parent = storage

	task.spawn(function()
		local checks: {string} = {}
		local summary: any = {task = "P04-08", phase = phase, store = "FactoryP0408_Test", scope = scope,
			key = "Player_101", syntheticProfile = true, economicReady = false, checks = checks}
		local function passed(name: string)
			table.insert(checks, name)
		end
		local ok, problem = xpcall(function()
			local factory = game:GetService("ServerScriptService"):FindFirstChild("Factory")
			assert(factory)
			local State = require(factory.State)
			local Actions = require(factory.Actions)
			local Transfers = require(factory.Transfers)
			local Sessions = require(factory.Sessions)
			local Persistence = require(factory.Persistence)
			local Recovery = require(factory.Recovery)
			local real = Persistence.dataStore(game:GetService("DataStoreService"):GetDataStore(summary.store, scope))
			local player = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "hand", ready = true}
			local worker = {kind = "Worker", actorId = "Worker/1", ownerUserId = 101, carrierLocationId = "worker", ready = true}
			local function hop(id: string, revision: number, batch: string, from: string, to: string): any
				return {operationId = id, expectedRevision = revision, batchId = batch, sourceId = from, targetId = to, quantity = 1}
			end
			local function confirm(response: any): any
				assert(response.ok and not response.ready and not response.unknown and response.confirmed, response.code)
				return response.confirmed
			end
			local function existing(): any
				error("Existing profile must not initialize")
			end
			local function save(current: any, profile: any): any
				local candidate = current.snapshot().confirmed.data
				candidate.state = profile
				return current.save(candidate, 180)
			end
			local initialToken = "A/" .. scope
			local modelPoints = {rawA = workspace.P02Line.Stores.Rohstofflager.Slot1.Transfer:GetFullName(),
				rawB = workspace.P02Line.Stores.Rohstofflager.Slot2.Transfer:GetFullName(),
				input = workspace.P02Line.Stations.Saege.Input.Transfer:GetFullName()}
			if phase == "A" then
				local initial = Persistence.new(101, real)
				local created = confirm(initial.load(initialToken, 180, function(owner: number): any
					local state = State.newProfile(owner)
					state.money = 61
					for id, kind in {rawA = "RawStore", rawB = "RawStore", hand = "Carrier", worker = "Carrier", input = "StationInput"} do
						state.locations[id] = State.newLocation(id, kind, 1, {"Holzpaket"})
					end
					state.batches.woodA = State.newBatch("woodA", owner, "Holzpaket", "rawA")
					state.batches.woodB = State.newBatch("woodB", owner, "Holzpaket", "rawB")
					return {profileVersion = 1, state = state,
						progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
				end))
				assert(created.revision == 1)
				local store = Transfers.new(created.data.state)
				local time = os.time()
				local first = hop("reserve-initial", 0, "woodA", "rawA", "hand")
				local otherSource = hop("reserve-target-conflict", 0, "woodB", "rawB", "hand")
				local otherHand = hop("reserve-source-conflict", 0, "woodA", "rawA", "worker")
				local foreign = table.clone(player)
				foreign.ownerUserId = 102
				local wrongQuantity = table.clone(first)
				wrongQuantity.quantity = 2
				local stale = table.clone(first)
				stale.expectedRevision = 1
				local full = Transfers.new(store.profile)
				full.profile.batches.woodB.locationId = "hand"
				local unchanged = store.profile
				assert(Transfers.reserve(store, foreign, first, time, 90).code == "NOT_AUTHORIZED")
				assert(Transfers.reserve(store, player, wrongQuantity, time, 90).code == "INVALID_QUANTITY")
				assert(Transfers.reserve(store, player, stale, time, 90).code == "STALE_REVISION")
				assert(Transfers.reserve(full, player, first, time, 90).code == "TARGET_FULL")
				assert(store.profile == unchanged and unchanged.money == 61 and unchanged.revision == 0)
				assert(real.read(summary.key).revision == 1)
				passed("QA-P04-01: four rejected requests leave confirmed state and revision unchanged")

				assert(Actions.checkTransfer(store.profile, player, first).ok)
				assert(Actions.checkTransfer(store.profile, player, otherSource).ok)
				assert(Actions.checkTransfer(store.profile, worker, otherHand).ok)
				assert(Transfers.reserve(store, player, first, time, 90).ok)
				assert(Transfers.reserve(store, player, otherSource, time, 90).code == "STALE_REVISION")
				assert(Transfers.reserve(store, worker, otherHand, time, 90).code == "STALE_REVISION")
				otherSource.expectedRevision = 1
				otherHand.expectedRevision = 1
				assert(Transfers.reserve(store, player, otherSource, time, 90).code == "TARGET_RESERVED")
				assert(Transfers.reserve(store, worker, otherHand, time, 90).code == "SOURCE_RESERVED")
				assert(store.profile.revision == 1 and store.profile.batches.woodA.locationId == "rawA")
				passed("QA-P04-02: one claim wins, competing source and target stay locked")

				assert(confirm(save(initial, store.profile)).revision == 2)
				assert(Transfers.commit(store, player, {operationId = "unsaved-pickup", expectedRevision = 1,
					claimId = "reserve-initial"}, os.time()).ok)
				assert(store.profile.batches.woodA.locationId == "hand")
				local released = confirm(initial.release())
				assert(released.revision == 3 and released.data.state.batches.woodA.locationId == "rawA"
					and not released.data.state.receipts["unsaved-pickup"])
				summary.saved = {location = "rawA", stateRevision = 1, storageRevision = 3, money = 61}
				passed("QA-P04-04: local pickup was discarded before shutdown")
				return
			end

			local failedUpdates, seeded = 0, 0
			local failed = Persistence.new(101, {
				read = function(): any error("synthetic read outage") end,
				update = function(): any failedUpdates += 1; error("unexpected backend write") end,
			})
			local failedLoad = failed.load("blocked/" .. scope, 180, function(): any seeded += 1; return nil end)
			assert(failedLoad.code == "LOAD_FAILED" and not failedLoad.ready and not failedLoad.confirmed)
			assert(failedUpdates == 0 and seeded == 0)
			local locked = table.clone(player)
			locked.ready = failedLoad.ready
			assert(Actions.checkTransfer(nil, locked, hop("blocked", 1, "woodA", "rawA", "hand")).code == "NOT_READY")
			passed("QA-P04-03: read outage blocks initialization, writes and economic actions")

			local loseReply = false
			local controller = Persistence.new(101, {read = real.read, update = function(key: string, transform: any): any
				local saved = real.update(key, transform)
				if loseReply then loseReply = false; error("simulated response loss after successful UpdateAsync") end
				return saved
			end})
			local base = confirm(controller.load("B/" .. scope, 180, existing))
			local state = base.data.state
			assert(base.revision == 4 and state.revision == 1 and state.money == 61)
			assert(state.claims["reserve-initial"] and not state.receipts["unsaved-pickup"])
			assert(State.countAt(state, "rawA") == 1 and State.countAt(state, "hand") == 0)
			local before = Recovery.plan(controller.snapshot(), 101, os.time(), modelPoints, {})
			assert(before.placements.woodA.pointId == modelPoints.rawA)
			passed("QA-P04-04: fresh Studio server restored the reserved source from the real backend")

			local store = Transfers.new(state)
			local time = os.time()
			assert(Transfers.expireClaims(store, time).ok)
			if store.profile.claims["reserve-initial"] then
				assert(Transfers.cancel(store, player, {operationId = "cancel-prior", expectedRevision = store.profile.revision,
					claimId = "reserve-initial"}, time).ok)
			end
			assert(Transfers.reserve(store, player, hop("pickup-reserve", store.profile.revision, "woodA", "rawA", "hand"), time, 90).ok)
			assert(Transfers.commit(store, player, {operationId = "pickup-complete", expectedRevision = store.profile.revision,
				claimId = "pickup-reserve"}, time).ok)
			local carrier = confirm(save(controller, store.profile))
			assert(carrier.data.state.reservations.rawA.kind == "Return")
			assert(real.read(summary.key).data.state.batches.woodA.locationId == "hand")
			assert(Transfers.reserve(store, player, hop("place-reserve", store.profile.revision, "woodA", "hand", "input"), time, 90).ok)
			local drop = {operationId = "place-complete", expectedRevision = store.profile.revision, claimId = "place-reserve"}
			assert(Transfers.commit(store, player, drop, time).ok)
			loseReply = true
			local uncertain = save(controller, store.profile)
			assert(uncertain.unknown and uncertain.confirmed.data.state.batches.woodA.locationId == "hand")
			assert(Recovery.plan(controller.snapshot(), 101, time, modelPoints, {}).code == "NOT_CONFIRMED")
			local reconciled = confirm(controller.reconcile())
			assert(reconciled.data.state.batches.woodA.locationId == "input" and not reconciled.data.state.reservations.rawA)
			passed("QA-P04-03: lost save response blocked placement until a fresh read confirmed the new location")

			local oldRejected = false
			real.update(summary.key, function(latest: any): any
				oldRejected = not Sessions.write(latest, 101, 2, initialToken, os.time(), 180, base.data).ok
				return nil
			end)
			assert(oldRejected and real.read(summary.key).revision == reconciled.revision)
			passed("QA-P04-03: old session cannot overwrite the recovered stand")
			confirm(controller.release())
			local rejoined = Persistence.new(101, real)
			local final = confirm(rejoined.load("C/" .. scope, 180, existing))
			local restored = Recovery.plan(rejoined.snapshot(), 101, os.time(), modelPoints, {})
			assert(restored.placements.woodA.pointId == modelPoints.input and restored.placements.woodB.pointId == modelPoints.rawB)
			local replayStore = Transfers.new(final.data.state)
			local same = replayStore.profile
			local replay = Transfers.commit(replayStore, player, drop, time)
			assert(replay.ok and replay.targetId == "input" and replay.revision == same.revision and replayStore.profile == same)
			assert(same.money == 61 and State.countAt(same, "input") == 1 and State.countAt(same, "hand") == 0)
			passed("QA-P04-02/-04: confirmed destination, charge and commit receipt survive a fresh load and exact replay")
			local last = confirm(rejoined.release())
			summary.saved = {location = "input", stateRevision = same.revision, storageRevision = last.revision,
				money = same.money, receipt = drop.operationId, physical = modelPoints.input}
		end, function(err: any): string return debug.traceback(tostring(err), 2) end)
		summary.status = if ok then "passed" else "failed"
		summary.failure = problem
		result.Value = http:JSONEncode(summary)
	end)
	return {phase = phase, scope = scope, started = true}
end
