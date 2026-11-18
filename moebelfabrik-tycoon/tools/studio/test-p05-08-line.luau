--!strict
-- P05-08 server proof: continuous line, views, signs and backpressure on an isolated real test DataStore record.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0508Result") and not workspace:FindFirstChild("P0508LineProbe"))
local result = Instance.new("StringValue")
result.Name = "P0508Result"
result.Parent = storage
local http = game:GetService("HttpService")
local scope = "P0508_" .. http:GenerateGUID(false):gsub("-", "")

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P05-08", checks = checks, scope = scope, store = "FactoryP0508_Test"}
	local root = Instance.new("Folder")
	root.Name = "P0508LineProbe"
	root.Parent = workspace
	local ok, failure = xpcall(function()
		local factory = game:GetService("ServerScriptService").Factory
		local State = require(factory.State)
		local Transfers = require(factory.Transfers)
		local Persistence = require(factory.Persistence)
		local Recipe = require(factory.Recipe)
		local Line = require(factory.Line)
		local LineView = require(factory.LineView)
		local SCALE = 25 / 7
		local german = (game:GetService("LocalizationService"):FindFirstChild("FactoryLabels") :: LocalizationTable):GetTranslator("de")
		local line = workspace.P02Line
		local setup = assert(Recipe.bind(line.Stations))
		local shelf = assert(Recipe.bindStore(line.Stores.Fertiglager, "FinishedStore", "Karton"))
		local rawStore = assert(Recipe.bindStore(line.Stores.Rohstofflager, "RawStore", "Holzpaket"))
		local hold = Instance.new("Part")
		hold.Name = "TestCarrier"
		hold.Anchored, hold.CanCollide, hold.CanQuery, hold.Transparency = true, false, false, 1
		hold.Size = Vector3.one
		hold.CFrame = line.Stations.Montage.Input.CFrame * CFrame.new(0, 4, 4)
		hold.Parent = root
		local places = {points = {}, carriers = {["Test.Hand"] = hold}, stationPads = {}, storeSlots = {}, storePad = line.Stores.Fertiglager.Slot2}
		local envelope = {profileVersion = 1, state = State.newProfile(101),
			progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
		local initial = envelope.state
		initial.money = 17
		for _, binding in {setup, shelf, rawStore} do
			for id, location in binding.locations do initial.locations[id] = location end
			for id, point in binding.points do places.points[id] = point end
		end
		for _, rule in State.STATIONS do places.stationPads[rule.id] = line.Stations[rule.id].Process end
		for i = 1, 4 do table.insert(places.storeSlots, "FinishedStore.Slot" .. i) end
		initial.locations["Test.Hand"] = State.newLocation("Test.Hand", "Carrier", 1, {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"})
		initial.locations["Test.Trailer"] = State.newLocation("Test.Trailer", "VehicleSlot", 1, {"Karton"})
		local function batch(id: string, stage: any, at: string) initial.batches[id] = State.newBatch(id, 101, stage, at) end
		batch("raw1", "Holzpaket", "RawStore.Slot1"); batch("raw2", "Holzpaket", "RawStore.Slot2")
		batch("w", "Holzpaket", "Saege.Input"); batch("k", "Bausatz", "Montage.Input")
		batch("r1", "Rohhocker", "Finish.Input"); batch("f2", "Fertig", "Finish.Output")
		batch("f1", "Fertig", "Packen.Input"); batch("box", "Karton", "Packen.Output")
		for i = 1, 4 do batch("old" .. i, "Karton", "FinishedStore.Slot" .. i) end
		local real = Persistence.dataStore(game:GetService("DataStoreService"):GetDataStore(report.store, scope))
		local writes = 0
		local now = os.time()
		local c = Persistence.new(101, {read = real.read, update = function(key: string, transform: any): any
			writes += 1
			return real.update(key, transform)
		end}, function(): number return now end)
		assert(c.load("line/" .. scope, 300, function(): any return envelope end).ok)
		local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "Test.Hand", ready = true}
		local function state(): any return c.snapshot().confirmed.data.state end
		local function carry(batchId: string, from: string, to: string, id: string)
			local store = Transfers.new(state())
			assert(Transfers.reserve(store, actor, {operationId = id .. "/r", expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, now, 5).ok, id)
			assert(Transfers.commit(store, actor, {operationId = id .. "/c", expectedRevision = store.profile.revision,
				claimId = id .. "/r"}, now).ok, id)
			local proposal = c.snapshot().confirmed.data
			proposal.state = store.profile
			assert(c.save(proposal, 300).ok, id)
		end
		local function tick(): string
			local list = {}
			for _, event in Line.tick(c, now, 300) do table.insert(list, event.stationId .. ":" .. event.code) end
			return table.concat(list, ",")
		end
		local function render(): ({[string]: Model}, {[string]: any})
			local current = state()
			return LineView.syncWares(root, current, places), LineView.syncSigns(root, current, now, places)
		end
		local function signText(name: string): (string, string, string, string)
			local board = root.Signs:FindFirstChild("Status_" .. name) :: BillboardGui
			local head, detail = board:FindFirstChild("Head") :: TextLabel, board:FindFirstChild("Detail") :: TextLabel
			return board:GetAttribute("StatusCode") :: string, head.Text, detail.Text, german:Translate(head, head.Text)
		end
		local function viewAt(batchId: string, locationId: string, stage: string): boolean
			local view = root.Wares:FindFirstChild(batchId)
			if not view or view:GetAttribute("Stage") ~= stage or view:GetAttribute("Signature") ~= stage .. "@" .. locationId then return false end
			local point = places.points[locationId]
			if not point then return view:IsA("Model") end
			local pivot = (view :: Model):GetBoundingBox().Position
			local offset = point.WorldCFrame:PointToObjectSpace(pivot)
			return math.abs(offset.X) < 0.01 and math.abs(offset.Z) < 0.01 and offset.Y > 0
		end

		-- Group 1: ready stations start on their own; full outputs and a full store start nothing.
		local t0 = now
		assert(tick() == "Saege:STARTED,Montage:STARTED")
		local views = render()
		local count = 0
		for _ in views do count += 1 end
		assert(count == 12 and viewAt("w", "Saege.Process", "Holzpaket") and viewAt("k", "Montage.Process", "Bausatz"))
		assert(viewAt("box", "Packen.Output", "Karton") and viewAt("old4", "FinishedStore.Slot4", "Karton"))
		local code, head, detail, de = signText("Saege")
		assert(code == "RUNNING" and head == "CUTTING" and detail == "6 s" and de == "ZUSCHNITT")
		code, head, detail = signText("Finish")
		assert(code == "OUTPUT_FULL" and head == "OUTPUT FULL" and detail == "COLLECT FINISHED STOOL")
		code, head, detail, de = signText("Store")
		assert(code == "STORE_FULL" and head == "STORE FULL – FREE A SLOT" and detail == "4 / 4" and de == "FERTIGLAGER VOLL – PLATZ FREIMACHEN")
		now = t0 + 6
		assert(tick() == "Saege:FINISHED")
		now = t0 + 8
		assert(tick() == "Montage:FINISHED")
		render()
		assert(viewAt("w", "Saege.Output", "Bausatz") and viewAt("k", "Montage.Output", "Rohhocker"))
		code, head, detail, de = signText("Saege")
		assert(code == "OUTPUT_FULL" and detail == "COLLECT PARTS KIT")
		table.insert(checks, "ready stations start and finish by themselves; every batch is shown at its confirmed place, the run on its process pad")

		-- Group 2: backpressure; waiting input is never consumed and no save happens.
		local before = writes
		for _, later in {30, 60, 120} do
			now = t0 + later
			assert(tick() == "")
		end
		local blocked = state()
		assert(writes == before and blocked.batches.r1.locationId == "Finish.Input" and blocked.batches.f1.locationId == "Packen.Input")
		assert(blocked.batches.raw1.locationId == "RawStore.Slot1" and State.validate(blocked))
		table.insert(checks, "with full outputs and a full store, repeated ticks consume no waiting input and write nothing")

		-- Group 3: freeing a store slot and the pack output resumes the line on the next tick.
		carry("old1", "FinishedStore.Slot1", "Test.Hand", "load-old1")
		render()
		assert(viewAt("old1", "Test.Hand", "Karton"))
		carry("old1", "Test.Hand", "Test.Trailer", "stow-old1")
		render()
		code, head, detail = signText("Store")
		assert(code == "STORE_OPEN" and head == "FINISHED STORE" and detail == "3 / 4" and not root.Wares:FindFirstChild("old1"))
		carry("box", "Packen.Output", "Test.Hand", "take-box")
		assert(tick() == "")
		render()
		code, head, detail = signText("Packen")
		assert(code == "OUTPUT_RESERVED" and head == "TRANSPORT RUNNING" and viewAt("box", "Test.Hand", "Karton"))
		carry("box", "Test.Hand", "FinishedStore.Slot1", "store-box")
		assert(tick() == "Packen:STARTED")
		render()
		code, head, detail = signText("Packen")
		assert(code == "RUNNING" and head == "PACKING" and detail == "4 s" and viewAt("f1", "Packen.Process", "Fertig"))
		now += 4
		assert(tick() == "Packen:FINISHED")
		render()
		code = signText("Store")
		assert(code == "STORE_FULL" and viewAt("f1", "Packen.Output", "Karton") and viewAt("box", "FinishedStore.Slot1", "Karton"))
		table.insert(checks, "taking one carton out and storing the pack output lets packing resume on the next tick")

		-- Group 4: missing raw material is shown; physical supply restarts the saw.
		carry("w", "Saege.Output", "Test.Hand", "take-kit")
		carry("w", "Test.Hand", "Montage.Input", "place-kit")
		assert(tick() == "")
		render()
		code, head, detail, de = signText("Saege")
		assert(code == "INPUT_MISSING" and head == "WOOD PACKAGE MISSING" and de == "HOLZPAKET FEHLT" and detail == "")
		code = signText("Montage")
		assert(code == "OUTPUT_FULL" and state().batches.w.locationId == "Montage.Input")
		carry("raw1", "RawStore.Slot1", "Test.Hand", "take-raw")
		carry("raw1", "Test.Hand", "Saege.Input", "place-raw")
		assert(tick() == "Saege:STARTED")
		render()
		code = signText("Saege")
		assert(code == "RUNNING" and viewAt("raw1", "Saege.Process", "Holzpaket"))
		local final = c.release().confirmed
		local ending = final and final.data.state
		assert(ending and ending.money == 17 and State.validate(ending))
		local cartons = 0
		for _, item in ending.batches do if item.stage == "Karton" then cartons += 1 end end
		assert(cartons == 6)
		table.insert(checks, "a missing wood package is announced in EN/DE; carrying one from the raw store restarts the saw")
		report.final = {storageRevision = final.revision, stateRevision = ending.revision, money = ending.money,
			cartons = cartons, writes = writes}
	end, function(err: any): string return debug.traceback(tostring(err), 2) end)
	root:Destroy()
	report.status = if ok then "passed" else "failed"
	report.failure = failure
	result.Value = http:JSONEncode(report)
end)
return {started = true, scope = scope}
