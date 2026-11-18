--!strict
-- P06-03 server proof: trailer slots A/B as inventory locations, capacity/stage limits and welded load views.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0603Result") and not workspace:FindFirstChild("P0603Probe"))
local result = Instance.new("StringValue")
result.Name = "P0603Result"
result.Parent = storage

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P06-03", checks = checks}
	local root = Instance.new("Folder")
	root.Name = "P0603Probe"
	root.Parent = workspace
	local vehicle = workspace.P02Vehicle
	local quad = vehicle.Quad
	local ok, failure = xpcall(function()
		local factory = game:GetService("ServerScriptService").Factory
		local State = require(factory.State)
		local Transfers = require(factory.Transfers)
		local Recipe = require(factory.Recipe)
		local Recovery = require(factory.Recovery)
		local Vehicles = require(factory.Vehicles)
		local LineView = require(factory.LineView)
		local S = 25 / 7
		-- 1. binding
		local bound = assert(Vehicles.bind(vehicle, vehicle:GetAttribute("VehicleId") :: string))
		assert(#bound.slotIds == 2 and bound.slotIds[1] == "Vehicle.Quad1.SlotA" and bound.slotIds[2] == "Vehicle.Quad1.SlotB")
		for _, id in bound.slotIds do
			local location = bound.locations[id]
			assert(location.kind == "VehicleSlot" and location.capacity == 1 and #location.acceptedStages == 2)
			assert(bound.mounts[id]:IsDescendantOf(vehicle.Trailer))
		end
		assert(select(2, Vehicles.bind(workspace.P02Line, "Quad1")) == "INVALID_VEHICLE")
		assert(select(2, Vehicles.bind(vehicle, "bad id")) == "INVALID_VEHICLE_ID")
		table.insert(checks, "the own trailer binds exactly two VehicleSlot locations (capacity 1, package or carton) with moving mounts")

		-- 2. capacity and stage limits through the shared transfer rules
		local raw = assert(Recipe.bindStore(workspace.P02Line.Stores.Rohstofflager, "RawStore", "Holzpaket"))
		local shelf = assert(Recipe.bindStore(workspace.P02Line.Stores.Fertiglager, "FinishedStore", "Karton"))
		local stations = assert(Recipe.bind(workspace.P02Line.Stations))
		local profile = State.newProfile(101)
		for _, binding in {raw, shelf, stations, bound} do for id, location in binding.locations do profile.locations[id] = location end end
		profile.locations.hand = State.newLocation("hand", "Carrier", 1, {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"})
		profile.batches.wood = State.newBatch("wood", 101, "Holzpaket", "RawStore.Slot1")
		profile.batches.box = State.newBatch("box", 101, "Karton", "FinishedStore.Slot1")
		profile.batches.box2 = State.newBatch("box2", 101, "Karton", "FinishedStore.Slot2")
		profile.batches.stool = State.newBatch("stool", 101, "Rohhocker", "Montage.Output")
		local store = Transfers.new(profile)
		local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "hand", ready = true}
		local now = os.time()
		local function reserve(batchId: string, from: string, to: string, id: string): any
			return Transfers.reserve(store, actor, {operationId = id, expectedRevision = store.profile.revision,
				batchId = batchId, sourceId = from, targetId = to, quantity = 1}, now, 5)
		end
		local function move(batchId: string, from: string, to: string, id: string)
			assert(reserve(batchId, from, to, id .. "/r").ok, id)
			assert(Transfers.commit(store, actor, {operationId = id .. "/c", expectedRevision = store.profile.revision, claimId = id .. "/r"}, now).ok, id)
		end
		local A, B = bound.slotIds[1], bound.slotIds[2]
		move("stool", "Montage.Output", "hand", "stool-take")
		local wrong = reserve("stool", "hand", A, "stool-to-trailer")
		assert(wrong.code == "WRONG_STAGE" and store.profile.batches.stool.locationId == "hand", wrong.code)
		move("stool", "hand", "Montage.Output", "stool-back")
		local direct = reserve("wood", "RawStore.Slot1", A, "store-to-trailer")
		assert(direct.code == "CARRIER_STEP_REQUIRED", direct.code)
		move("wood", "RawStore.Slot1", "hand", "wood-take"); move("wood", "hand", A, "wood-load")
		move("box", "FinishedStore.Slot1", "hand", "box-take"); move("box", "hand", B, "box-load")
		move("box2", "FinishedStore.Slot2", "hand", "box2-take")
		for _, slot in {A, B} do
			local full = reserve("box2", "hand", slot, "box2-" .. slot)
			assert(full.code == "TARGET_FULL" and store.profile.batches.box2.locationId == "hand", full.code)
		end
		move("box2", "hand", "FinishedStore.Slot2", "box2-back")
		local load = Vehicles.load(store.profile, bound.slotIds)
		assert(load.used == 2 and load.full and load.batches[A] == "wood" and load.batches[B] == "box")
		local overfull = Transfers.new(store.profile).profile
		overfull.batches.extra = State.newBatch("extra", 101, "Karton", A)
		assert(select(2, State.validate(overfull)) == "CAPACITY_EXCEEDED" and State.validate(store.profile))
		table.insert(checks, "a raw stool is refused, store-to-trailer needs the hand, a third ware finds both slots full and stays carried")

		-- 3. visible, fixed load from the inventory
		local places = {points = {}, mounts = bound.mounts, stationPads = {}}
		local views = LineView.syncWares(root, store.profile, places)
		local woodView, boxView = views.wood, views.box
		assert(woodView and boxView and not views.box2 and not views.stool)
		local slotPartA = bound.mounts[A].Parent :: BasePart
		local slotPartB = bound.mounts[B].Parent :: BasePart
		for _, pair in {{woodView, slotPartA}, {boxView, slotPartB}} do
			for _, part in (pair[1] :: Model):GetDescendants() do
				if part:IsA("BasePart") then
					local weld = part:FindFirstChildOfClass("WeldConstraint")
					assert(not part.Anchored and part.Massless and weld and weld.Part0 == pair[2], part:GetFullName())
				end
			end
		end
		local function offset(view: Model, mount: Attachment): Vector3
			local _, size = view:GetBoundingBox()
			local bottom = view:GetBoundingBox().Position - Vector3.new(0, size.Y / 2, 0)
			return mount.WorldCFrame:PointToObjectSpace(bottom)
		end
		local before = {wood = offset(woodView, bound.mounts[A]), box = offset(boxView, bound.mounts[B])}
		assert(before.wood.Magnitude < 0.05 and before.box.Magnitude < 0.05, tostring(before.wood) .. tostring(before.box))
		local start = quad.Chassis.Position
		quad:SetAttribute("TestThrottle", 0.45)
		task.wait(2.5)
		quad:SetAttribute("TestThrottle", 0)
		task.wait(2)
		local travelled = (quad.Chassis.Position - start).Magnitude / S
		local after = {wood = offset(woodView, bound.mounts[A]), box = offset(boxView, bound.mounts[B])}
		assert(travelled > 2 and (after.wood - before.wood).Magnitude < 0.05 and (after.box - before.box).Magnitude < 0.05)
		report.drive = {travelledM = math.floor(travelled * 100) / 100, woodDriftStuds = (after.wood - before.wood).Magnitude,
			boxDriftStuds = (after.box - before.box).Magnitude}
		table.insert(checks, "load is drawn from the inventory, welded massless to its slot and stays on it while the rig drives")

		-- 4. recovery places vehicle load at its slot mounts
		local points = {}
		for _, binding in {raw, shelf, stations} do for id, point in binding.points do points[id] = point:GetFullName() end end
		for id, mount in bound.mounts do points[id] = mount:GetFullName() end
		local snapshot = {ok = true, code = "SNAPSHOT", status = "Confirmed", inFlight = false, unknown = false,
			confirmed = {sessionId = "probe", expiresAt = now + 60, revision = 1, data = {state = store.profile}}}
		local plan = Recovery.plan(snapshot :: any, 101, now, points, {})
		assert(plan.ok and plan.placements.wood.pointId == points[A] and plan.placements.box.pointId == points[B], plan.code)
		table.insert(checks, "recovery maps the vehicle load to the trailer slot mounts")
	end, function(err: any): string return debug.traceback(tostring(err), 2) end)
	quad:SetAttribute("TestThrottle", 0)
	root:Destroy()
	report.status = if ok then "passed" else "failed"
	report.failure = failure
	result.Value = game:GetService("HttpService"):JSONEncode(report)
end)
return {started = true}
