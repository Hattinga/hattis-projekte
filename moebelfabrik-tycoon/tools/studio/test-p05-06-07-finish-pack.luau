--!strict
-- P05-06/P05-07 server proof: finish, pack and finished storage against an isolated real test DataStore record.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0506Result"))
local result = Instance.new("StringValue")
result.Name = "P0506Result"
result.Parent = storage
local http = game:GetService("HttpService")
local scope = "P0506_" .. http:GenerateGUID(false):gsub("-", "")

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P05-06/P05-07", checks = checks, scope = scope, store = "FactoryP0506_Test"}
	local ok, failure = xpcall(function()
		local factory = game:GetService("ServerScriptService").Factory
		local State = require(factory.State)
		local Transfers = require(factory.Transfers)
		local Persistence = require(factory.Persistence)
		local Recipe = require(factory.Recipe)
		local Recovery = require(factory.Recovery)
		local Stations = require(factory.Stations)
		local StoolView = require(factory.StoolView)
		local CartonView = require(factory.CartonView)
		local SCALE = 25 / 7
		local labels = game:GetService("LocalizationService"):FindFirstChild("FactoryLabels") :: LocalizationTable
		assert(labels and labels:IsA("LocalizationTable"))
		local german = labels:GetTranslator("de")
		local setup = assert(Recipe.bind(workspace.P02Line.Stations))
		local shelf = assert(Recipe.bindStore(workspace.P02Line.Stores.Fertiglager, "FinishedStore", "Karton"))
		assert(not Recipe.bindStore(workspace.P02Line.Stores.Rohstofflager, "FinishedStore", "Karton"))
		local points, pads = {}, {}
		for _, binding in {setup, shelf} do
			for id, point in binding.points do points[id] = point:GetFullName(); pads[id] = point end
		end
		local now = os.time()
		local envelope = {profileVersion = 1, state = State.newProfile(101),
			progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
		local initial = envelope.state
		initial.money = 17
		initial.locations = setup.locations
		for id, location in shelf.locations do initial.locations[id] = location end
		initial.locations["Test.Hand"] = State.newLocation("Test.Hand", "Carrier", 1, {"Rohhocker", "Fertig", "Karton"})
		initial.batches.a = State.newBatch("a", 101, "Rohhocker", "Finish.Input")
		initial.batches.b = State.newBatch("b", 101, "Rohhocker", "Montage.Output")
		for i = 1, 3 do
			initial.batches["old" .. i] = State.newBatch("old" .. i, 101, "Karton", "FinishedStore.Slot" .. i)
		end
		local real = Persistence.dataStore(game:GetService("DataStoreService"):GetDataStore(report.store, scope))
		local drop = false
		local function controller(token: string, seed: any?): any
			local c = Persistence.new(101, {
				read = real.read,
				update = function(key: string, transform: any): any
					local returned = real.update(key, transform)
					if drop then drop = false; error("Simulated lost finish save response") end
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
		local function state(): any return c.snapshot().confirmed.data.state end
		local function measure(model: Model, support: CFrame, padId: string): any
			local lowest, wood = math.huge, nil
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
					if part:GetAttribute("WoodPiece") == true then wood = part.Color end
				end
			end
			local pad = pads[padId].Parent :: BasePart
			local relative = pad.CFrame:PointToObjectSpace(support.Position)
			local sign = model:FindFirstChild("StufenLabel")
			local text = sign and sign:FindFirstChildOfClass("TextLabel")
			return {size = model:GetExtentsSize() / SCALE, gap = lowest - support.Position.Y, wood = wood,
				text = text and text.Text, german = text and german:Translate(text, text.Text),
				halfPad = Vector2.new(pad.Size.X / 2 - math.abs(relative.X), pad.Size.Z / 2 - math.abs(relative.Z)) / SCALE}
		end

		-- P05-06 group 1: one stored finish run after an uncertain start.
		local startedAt = now
		drop = true
		local pending = Stations.start(c, "Finish", now, 180)
		assert(not pending.ok and pending.unknown and state().batches.a.locationId == "Finish.Input")
		assert(Stations.start(c, "Finish", now, 180).code == "NOT_CONFIRMED")
		assert(c.reconcile().ok)
		assert(state().reservations["Finish.Output"].finishAt == startedAt + 6 and state().batches.a.locationId == "Finish.Process")
		assert(c.release().ok)
		c = controller("resume", nil)
		local plan = Recovery.plan(c.snapshot(), 101, now, points, {})
		assert(plan.ok and plan.placements.a.pointId == points["Finish.Process"]
			and plan.placements.old3.pointId == points["FinishedStore.Slot3"])
		now = startedAt + 5
		assert(Stations.finish(c, "Finish", "a", now, 180).code == "RUNNING")
		table.insert(checks, "P05-06: an uncertain finish start reconciles to one stored 6 s run that survives a reload")

		-- P05-06 group 2: visible finished surface, distinct from the raw stool.
		now = startedAt + 6
		assert(Stations.finish(c, "Finish", "a", now, 180).ok)
		assert(state().batches.a.stage == "Fertig" and state().batches.a.locationId == "Finish.Output" and state().money == 17)
		local rawSupport, doneSupport = pads["Finish.Input"].WorldCFrame, pads["Finish.Output"].WorldCFrame
		local rawView = StoolView.create(workspace, rawSupport, "compare", "Rohhocker")
		local doneView = StoolView.create(workspace, doneSupport, "a", "Fertig")
		local raw, done = measure(rawView, rawSupport, "Finish.Input"), measure(doneView, doneSupport, "Finish.Output")
		rawView:Destroy(); doneView:Destroy()
		local function luminance(color: Color3): number return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B end
		assert((done.size - Vector3.new(0.40, 0.45, 0.40)).Magnitude < 0.003 and (raw.size - done.size).Magnitude < 0.001)
		assert(math.abs(done.gap) < 0.001 and done.halfPad.X >= 0.20 and done.halfPad.Y >= 0.20)
		assert(math.abs(luminance(raw.wood) - luminance(done.wood)) > 0.2)
		assert(done.text == "FINISHED STOOL" and done.german == "FERTIGER HOCKER" and raw.text == "RAW STOOL" and raw.german == "ROHHOCKER")
		local store = Transfers.new(state())
		move(store, "b", "Montage.Output", "Test.Hand", "b-take")
		move(store, "b", "Test.Hand", "Finish.Input", "b-place")
		save(store)
		assert(Stations.start(c, "Finish", now, 180).code == "OUTPUT_BLOCKED" and state().batches.b.locationId == "Finish.Input")
		report.finish = {lumaRaw = luminance(raw.wood), lumaFinished = luminance(done.wood),
			sizeMeters = {done.size.X, done.size.Y, done.size.Z}}
		table.insert(checks, "P05-06: after 6 s one finished stool shows the recipe surface, EN/DE stage label and blocks the next stool")

		-- P05-07 group 3: pack, label and store the carton.
		store = Transfers.new(state())
		move(store, "a", "Finish.Output", "Test.Hand", "a-take")
		local wrong = reserve(store, "a", "Test.Hand", "FinishedStore.Slot4", "a-to-store")
		assert(wrong.code == "WRONG_STAGE" and store.profile.batches.a.locationId == "Test.Hand")
		move(store, "a", "Test.Hand", "Packen.Input", "a-place")
		save(store)
		local secondFinish = Stations.start(c, "Finish", now, 180)
		assert(secondFinish.ok and secondFinish.batchId == "b")
		local packed = Stations.start(c, "Packen", now, 180)
		assert(packed.ok and packed.finishAt == now + 4)
		assert(Stations.finish(c, "Packen", "a", now + 3, 180).code == "RUNNING")
		now += 4
		assert(Stations.finish(c, "Packen", "a", now, 180).ok)
		assert(state().batches.a.stage == "Karton" and state().batches.a.locationId == "Packen.Output")
		local cartonSupport = pads["Packen.Output"].WorldCFrame
		local carton = CartonView.create(workspace, cartonSupport, "a")
		local box = measure(carton, cartonSupport, "Packen.Output")
		local printed = {}
		for _, item in carton:GetDescendants() do
			if item:IsA("TextLabel") and item.Parent and item.Parent:IsA("SurfaceGui") then
				printed[item.Text] = item.AutoLocalize
			end
		end
		carton:Destroy()
		assert((box.size - Vector3.new(0.46, 0.51, 0.46)).Magnitude < 0.003 and math.abs(box.gap) < 0.001)
		assert(box.halfPad.X >= 0.23 and box.halfPad.Y >= 0.23)
		assert(box.text == "STOOL CARTON" and box.german == "HOCKERKARTON")
		assert(printed["1 STOOL"] == true and printed.BATCH == true and printed.a == false)
		assert(german:Translate(game, "1 STOOL") == "1 HOCKER")
		store = Transfers.new(state())
		move(store, "a", "Packen.Output", "Test.Hand", "carton-take")
		move(store, "a", "Test.Hand", "FinishedStore.Slot4", "carton-store")
		save(store)
		local stored = state()
		assert(stored.batches.a.locationId == "FinishedStore.Slot4" and not stored.reservations["Packen.Output"])
		local slotSupport = pads["FinishedStore.Slot4"].WorldCFrame
		carton = CartonView.create(workspace, slotSupport, "a")
		local shelfBox = measure(carton, slotSupport, "FinishedStore.Slot4")
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {carton}
		local clearance = workspace:GetPartBoundsInBox(slotSupport * CFrame.new(0, (0.255 + 0.001) * SCALE, 0),
			Vector3.new(0.46, 0.508, 0.46) * SCALE, params)
		carton:Destroy()
		assert(math.abs(shelfBox.gap) < 0.001 and shelfBox.halfPad.X >= 0.23 and shelfBox.halfPad.Y >= 0.23 and #clearance == 0)
		plan = Recovery.plan(c.snapshot(), 101, now, points, {})
		assert(plan.ok and plan.placements.a.pointId == points["FinishedStore.Slot4"])
		report.carton = {sizeMeters = {box.size.X, box.size.Y, box.size.Z}, shelfClear = #clearance == 0}
		table.insert(checks, "P05-07: after 4 s the same batch is one labelled carton; only the carton is accepted and stored in the finished store")

		-- P05-07 group 4: a full finished store leaves the next carton carried and the line backs up.
		now = assert(secondFinish.finishAt)
		assert(Stations.finish(c, "Finish", "b", now, 180).ok)
		store = Transfers.new(state())
		move(store, "b", "Finish.Output", "Test.Hand", "b2-take")
		move(store, "b", "Test.Hand", "Packen.Input", "b2-place")
		save(store)
		assert(Stations.start(c, "Packen", now, 180).ok)
		now += 4
		assert(Stations.finish(c, "Packen", "b", now, 180).ok)
		store = Transfers.new(state())
		move(store, "b", "Packen.Output", "Test.Hand", "b-carton-take")
		for i = 1, 4 do
			local full = reserve(store, "b", "Test.Hand", "FinishedStore.Slot" .. i, "b-store-" .. i)
			assert(full.code == "TARGET_FULL" and store.profile.batches.b.locationId == "Test.Hand", full.code)
		end
		save(store)
		assert(state().reservations["Packen.Output"].kind == "Return" and state().batches.b.locationId == "Test.Hand")
		move(store, "b", "Test.Hand", "Packen.Output", "b-carton-return")
		save(store)
		local final = c.release().confirmed
		local ending = final and final.data.state
		assert(ending and ending.batches.b.locationId == "Packen.Output" and ending.batches.b.stage == "Karton"
			and ending.batches.a.locationId == "FinishedStore.Slot4" and ending.money == 17 and State.validate(ending))
		for i = 1, 3 do assert(ending.batches["old" .. i].locationId == "FinishedStore.Slot" .. i) end
		table.insert(checks, "P05-07: with all four store slots full the carton stays carried, returns to the pack output and nothing is lost")
		report.final = {storageRevision = final.revision, stateRevision = ending.revision, money = ending.money,
			stored = 4, waitingAtPackOutput = "b"}
	end, function(err: any): string return debug.traceback(tostring(err), 2) end)
	report.status = if ok then "passed" else "failed"
	report.failure = failure
	result.Value = http:JSONEncode(report)
end)
return {started = true, scope = scope}
