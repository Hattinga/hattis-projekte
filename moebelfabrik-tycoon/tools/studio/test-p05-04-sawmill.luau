--!strict
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0504Result"))
local result = Instance.new("StringValue")
result.Name = "P0504Result"
result.Parent = storage
local http = game:GetService("HttpService")
local scope = "P0504_" .. http:GenerateGUID(false):gsub("-", "")

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P05-04", checks = checks, scope = scope, store = "FactoryP0504_Test"}
	local ok, failure = xpcall(function()
		local factory = game:GetService("ServerScriptService").Factory
		local State = require(factory.State)
		local Actions = require(factory.Actions)
		local Transfers = require(factory.Transfers)
		local Persistence = require(factory.Persistence)
		local Recipe = require(factory.Recipe)
		local Recovery = require(factory.Recovery)
		local Sawmill = require(factory.Sawmill)
		local KitView = require(factory.KitView)
		local saw = State.SAW
		local setup = assert(Recipe.bind(workspace.P02Line.Stations))
		local points = {}
		for id, point in setup.points do points[id] = point:GetFullName() end
		local raw = workspace.P02Line.Stores.Rohstofflager.Slot1.Transfer
		points["Test.Raw"] = raw:GetFullName()
		local now = os.time()
		local envelope = {profileVersion = 1, state = State.newProfile(101),
			progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
		local initial = envelope.state
		initial.money = 17
		initial.locations = setup.locations
		initial.locations["Test.Raw"] = State.newLocation("Test.Raw", "RawStore", 1, {"Holzpaket"})
		initial.locations["Test.Hand"] = State.newLocation("Test.Hand", "Carrier", 1, {"Holzpaket", "Bausatz"})
		initial.batches.first = State.newBatch("first", 101, "Holzpaket", saw.input)
		initial.batches.next = State.newBatch("next", 101, "Holzpaket", "Test.Raw")
		local real = Persistence.dataStore(game:GetService("DataStoreService"):GetDataStore(report.store, scope))
		local drop = false
		local function clock(): number return now end
		local function controller(token: string, seed: any?): any
			local c = Persistence.new(101, {
				read = real.read,
				update = function(key: string, transform: any): any
					local returned = real.update(key, transform)
					if drop then drop = false; error("Simulated lost production save response") end
					return returned
				end,
			}, clock)
			assert(c.load(token .. "/" .. scope, 180, function(): any
				assert(seed, "Unexpected initial profile")
				return seed
			end).ok)
			return c
		end
		local c = controller("first", envelope)
		local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "Test.Hand", ready = true}
		local function reserve(store: any, batchId: string, from: string, to: string, id: string): any
			return Transfers.reserve(store, actor, {operationId = id, expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, now, 5)
		end
		local function move(store: any, batchId: string, from: string, to: string, id: string)
			assert(reserve(store, batchId, from, to, id .. "/r").ok)
			assert(Transfers.commit(store, actor, {operationId = id .. "/c", expectedRevision = store.profile.revision,
				claimId = id .. "/r"}, now).ok)
		end
		local function save(store: any)
			local proposal = c.snapshot().confirmed.data
			proposal.state = store.profile
			assert(c.save(proposal, 180).ok)
		end
		local store = Transfers.new(c.snapshot().confirmed.data.state)
		local claimed = reserve(store, "first", saw.input, "Test.Hand", "input-hold")
		assert(claimed.ok)
		save(store)
		assert(Sawmill.start(c, now, 180).code == "SLOT_RESERVED")
		now = claimed.expiresAt
		drop = true
		local pending = Sawmill.start(c, now, 180)
		assert(not pending.ok and pending.unknown and c.snapshot().confirmed.data.state.batches.first.locationId == saw.input)
		assert(Sawmill.start(c, now, 180).code == "NOT_CONFIRMED")
		assert(c.reconcile().ok)
		local working = c.snapshot().confirmed.data.state
		local lock = working.reservations[saw.output]
		assert(lock.kind == "Production" and lock.batchId == "first" and lock.finishAt == now + 6)
		assert(working.batches.first.locationId == saw.process and not working.claims["input-hold"])
		table.insert(checks, "an active input claim blocks start; an uncertain save recovers exactly one persisted run")
		local bad = Transfers.new(working).profile
		bad.reservations[saw.output] = nil
		local valid, reason = State.validate(bad)
		assert(not valid and reason == "MISSING_PRODUCTION_RESERVATION")
		local blocked = Actions.checkTransfer(working, actor, {operationId = "blocked-work", expectedRevision = working.revision,
			batchId = "first", sourceId = saw.process, targetId = "Test.Hand", quantity = 1}, now)
		assert(blocked.code == "PROCESS_SLOT")
		assert(c.release().ok)
		c = controller("resume", nil)
		assert(Sawmill.start(c, now, 180).code == "ALREADY_RUNNING")
		local plan = Recovery.plan(c.snapshot(), 101, now, points, {})
		assert(plan.ok and plan.placements.first.pointId == points[saw.process])
		assert(Sawmill.finish(c, "next", now + 6, 180).code == "STALE_RUN")
		now = lock.finishAt - 1
		assert(Sawmill.finish(c, "first", now, 180).code == "RUNNING")
		table.insert(checks, "reload restores the same input on the physical process point and guards the timer")

		store = Transfers.new(c.snapshot().confirmed.data.state)
		move(store, "next", "Test.Raw", "Test.Hand", "next-take")
		move(store, "next", "Test.Hand", saw.input, "next-place")
		save(store)
		now = lock.finishAt
		assert(Sawmill.finish(c, "first", now, 180).ok)
		assert(Sawmill.finish(c, "first", now, 180).code == "NO_ACTIVE_RUN")
		assert(Sawmill.start(c, now, 180).code == "OUTPUT_BLOCKED")
		local done = c.snapshot().confirmed.data.state
		assert(done.batches.first.stage == "Bausatz" and done.batches.first.locationId == saw.output
			and done.batches.next.locationId == saw.input and done.money == 17 and State.countAt(done, saw.output) == 1)
		local rendered = KitView.create(workspace, setup.points[saw.output].WorldCFrame, "first")
		local pieceCount = 0
		for _, part in rendered:GetChildren() do if part:GetAttribute("WoodPiece") == true then pieceCount += 1 end end
		local size = rendered:GetExtentsSize()
		local label = rendered:FindFirstChild("BausatzLabel")
		rendered:Destroy()
		assert(pieceCount == 9 and label and (size - Vector3.new(0.60, 0.18, 0.50) * (25 / 7)).Magnitude < 0.01)
		table.insert(checks, "after six seconds one batch becomes a measured visible kit with nine pieces")

		store = Transfers.new(done)
		move(store, "first", saw.output, "Test.Hand", "kit-take")
		save(store)
		assert(Sawmill.start(c, now, 180).code == "OUTPUT_BLOCKED")
		move(store, "first", "Test.Hand", "Montage.Input", "kit-place")
		save(store)
		local second = Sawmill.start(c, now, 180)
		assert(second.ok and second.batchId == "next")
		assert(Sawmill.finish(c, "first", now + 7, 180).code == "STALE_RUN")
		now = assert(second.finishAt)
		assert(Sawmill.finish(c, "next", now, 180).ok)
		local final = c.release().confirmed
		assert(final and final.data.state.batches.first.locationId == "Montage.Input"
			and final.data.state.batches.next.locationId == saw.output and final.data.state.money == 17)
		table.insert(checks, "Return blocks the next run until delivery; an old completion cannot affect the second batch")
		report.final = {storageRevision = final.revision, stateRevision = final.data.state.revision,
			money = 17, first = "Montage.Input", second = saw.output, woodPieces = pieceCount}
	end, function(err: any): string return debug.traceback(tostring(err), 2) end)
	report.status = if ok then "passed" else "failed"
	report.failure = failure
	result.Value = http:JSONEncode(report)
end)
return {started = true, scope = scope}
