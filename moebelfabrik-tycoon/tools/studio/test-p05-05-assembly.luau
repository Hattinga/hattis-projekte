--!strict
-- P05-05 server proof: assembly run against an isolated real test DataStore record.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0505Result"))
local result = Instance.new("StringValue")
result.Name = "P0505Result"
result.Parent = storage
local http = game:GetService("HttpService")
local scope = "P0505_" .. http:GenerateGUID(false):gsub("-", "")

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P05-05", checks = checks, scope = scope, store = "FactoryP0505_Test"}
	local ok, failure = xpcall(function()
		local factory = game:GetService("ServerScriptService").Factory
		local State = require(factory.State)
		local Transfers = require(factory.Transfers)
		local Persistence = require(factory.Persistence)
		local Recipe = require(factory.Recipe)
		local Recovery = require(factory.Recovery)
		local Stations = require(factory.Stations)
		local Sawmill = require(factory.Sawmill)
		local StoolView = require(factory.StoolView)
		local SCALE = 25 / 7
		local setup = assert(Recipe.bind(workspace.P02Line.Stations))
		local points = {}
		for id, point in setup.points do points[id] = point:GetFullName() end
		local now = os.time()
		local envelope = {profileVersion = 1, state = State.newProfile(101),
			progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
		local initial = envelope.state
		initial.money = 17
		initial.locations = setup.locations
		initial.locations["Test.Hand"] = State.newLocation("Test.Hand", "Carrier", 1, {"Bausatz", "Rohhocker"})
		initial.batches.kit = State.newBatch("kit", 101, "Bausatz", "Montage.Input")
		initial.batches.wood = State.newBatch("wood", 101, "Holzpaket", "Saege.Input")
		local real = Persistence.dataStore(game:GetService("DataStoreService"):GetDataStore(report.store, scope))
		local drop = false
		local function controller(token: string, seed: any?): any
			local c = Persistence.new(101, {
				read = real.read,
				update = function(key: string, transform: any): any
					local returned = real.update(key, transform)
					if drop then drop = false; error("Simulated lost assembly save response") end
					return returned
				end,
			}, function(): number return now end)
			assert(c.load(token .. "/" .. scope, 180, function(): any
				assert(seed, "Unexpected initial profile")
				return seed
			end).ok)
			return c
		end
		local c = controller("first", envelope)
		local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "Test.Hand", ready = true}
		local function move(store: any, batchId: string, from: string, to: string, id: string)
			assert(Transfers.reserve(store, actor, {operationId = id .. "/r", expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, now, 5).ok)
			assert(Transfers.commit(store, actor, {operationId = id .. "/c", expectedRevision = store.profile.revision,
				claimId = id .. "/r"}, now).ok)
		end
		local function save(store: any)
			local proposal = c.snapshot().confirmed.data
			proposal.state = store.profile
			assert(c.save(proposal, 180).ok)
		end

		assert(Stations.start(c, "Lackierer", now, 180).code == "UNKNOWN_STATION")
		assert(Stations.start(c, "Finish", now, 180).code == "INPUT_REQUIRED")
		local startedAt = now
		drop = true
		local pending = Stations.start(c, "Montage", now, 180)
		assert(not pending.ok and pending.unknown and c.snapshot().confirmed.data.state.batches.kit.locationId == "Montage.Input")
		assert(Stations.start(c, "Montage", now, 180).code == "NOT_CONFIRMED")
		assert(c.reconcile().ok)
		assert(Sawmill.start(c, now, 180).ok)
		local working = c.snapshot().confirmed.data.state
		local lock = working.reservations["Montage.Output"]
		assert(lock.kind == "Production" and lock.batchId == "kit" and lock.finishAt == startedAt + 8)
		assert(working.batches.kit.locationId == "Montage.Process" and working.reservations["Saege.Output"].batchId == "wood")
		assert(State.validate(working))
		table.insert(checks, "an uncertain assembly start reconciles to exactly one stored run beside an independent saw run")

		assert(c.release().ok)
		c = controller("resume", nil)
		assert(Stations.start(c, "Montage", now, 180).code == "ALREADY_RUNNING")
		local plan = Recovery.plan(c.snapshot(), 101, now, points, {})
		assert(plan.ok and plan.placements.kit.pointId == points["Montage.Process"]
			and plan.placements.wood.pointId == points["Saege.Process"])
		assert(Stations.finish(c, "Montage", "wood", now + 8, 180).code == "STALE_RUN")
		now = startedAt + 6
		assert(Sawmill.finish(c, "wood", now, 180).ok)
		assert(Stations.finish(c, "Montage", "kit", now, 180).code == "RUNNING")
		table.insert(checks, "reload keeps both work pieces on their process points and the 8 s assembly timer")

		now = startedAt + 8
		assert(Stations.finish(c, "Montage", "kit", now, 180).ok)
		assert(Stations.finish(c, "Montage", "kit", now, 180).code == "NO_ACTIVE_RUN")
		local done = c.snapshot().confirmed.data.state
		assert(done.batches.kit.stage == "Rohhocker" and done.batches.kit.locationId == "Montage.Output"
			and done.batches.kit.recipeId == "Hocker01" and done.money == 17 and State.countAt(done, "Montage.Output") == 1)
		local support = setup.points["Montage.Output"].WorldCFrame
		local stool = StoolView.create(workspace, support, "kit", "Rohhocker")
		local wood, joints, lowest = 0, 0, math.huge
		for _, part in stool:GetChildren() do
			if part:IsA("BasePart") then
				if part:GetAttribute("WoodPiece") == true then wood += 1 else joints += 1 end
				lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
			end
		end
		local size = stool:GetExtentsSize()
		local label = stool:FindFirstChild("StufenLabel")
		local text = label and label:FindFirstChildOfClass("TextLabel")
		local pad = setup.points["Montage.Output"].Parent :: BasePart
		local relative = pad.CFrame:PointToObjectSpace(support.Position)
		stool:Destroy()
		assert(wood == 9 and joints == 8 and text and text.Text == "Rohhocker")
		assert((size - Vector3.new(0.40, 0.45, 0.40) * SCALE).Magnitude < 0.01, tostring(size / SCALE))
		assert(math.abs(lowest - support.Position.Y) < 0.001)
		assert(math.abs(relative.X) + 0.20 * SCALE <= pad.Size.X / 2 and math.abs(relative.Z) + 0.20 * SCALE <= pad.Size.Z / 2)
		report.stool = {wood = wood, joints = joints, sizeMeters = {size.X / SCALE, size.Y / SCALE, size.Z / SCALE},
			padMeters = {pad.Size.X / SCALE, pad.Size.Z / SCALE}}
		table.insert(checks, "after 8 s the same batch is one measured raw stool standing on its own output pad")

		local store = Transfers.new(done)
		move(store, "wood", "Saege.Output", "Test.Hand", "kit2-take")
		move(store, "wood", "Test.Hand", "Montage.Input", "kit2-place")
		save(store)
		assert(Stations.start(c, "Montage", now, 180).code == "OUTPUT_BLOCKED")
		assert(c.snapshot().confirmed.data.state.batches.wood.locationId == "Montage.Input")
		store = Transfers.new(c.snapshot().confirmed.data.state)
		move(store, "kit", "Montage.Output", "Test.Hand", "stool-take")
		save(store)
		assert(Stations.start(c, "Montage", now, 180).code == "OUTPUT_BLOCKED")
		move(store, "kit", "Test.Hand", "Finish.Input", "stool-place")
		save(store)
		local second = Stations.start(c, "Montage", now, 180)
		assert(second.ok and second.batchId == "wood" and second.finishAt == now + 8)
		now = assert(second.finishAt)
		assert(Stations.finish(c, "Montage", "wood", now, 180).ok)
		local final = c.release().confirmed
		local state = final and final.data.state
		assert(state and state.batches.kit.locationId == "Finish.Input" and state.batches.kit.stage == "Rohhocker"
			and state.batches.wood.locationId == "Montage.Output" and state.batches.wood.stage == "Rohhocker"
			and state.money == 17 and State.validate(state))
		table.insert(checks, "a waiting stool blocks the next kit unconsumed; after delivery the second kit becomes a raw stool")
		report.final = {storageRevision = final.revision, stateRevision = state.revision, money = state.money,
			first = "Finish.Input", second = "Montage.Output"}
	end, function(err: any): string return debug.traceback(tostring(err), 2) end)
	report.status = if ok then "passed" else "failed"
	report.failure = failure
	result.Value = http:JSONEncode(report)
end)
return {started = true, scope = scope}
