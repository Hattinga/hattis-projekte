--!strict
-- Start the P06 loading demo, run this proof, then run drive-p06-02-route in the same Play.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning())
local storage = game:GetService("ServerStorage")
local http = game:GetService("HttpService")
local lineTest = storage:FindFirstChild("P0509LineTest") :: BindableFunction
local lineState = storage:FindFirstChild("P0509LineState") :: BindableFunction
local purchase = storage:FindFirstChild("P060405Purchase") :: BindableFunction
assert(lineTest and lineState and purchase, "Start a fresh P06 loading demo first")
assert(not storage:FindFirstChild("P0608Result") and not storage:FindFirstChild("P0608Stop"), "P06-08 probe already active")

local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
assert(root and humanoid and not humanoid.SeatPart)
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local HandMoves = require(factory.HandMoves)
local Vehicles = require(factory.Vehicles)
local vehicle = workspace.P02Vehicle
local chassis = vehicle.Quad.Chassis :: BasePart
local seat = vehicle.Quad.Seat :: VehicleSeat
local binding = assert(Vehicles.bind(vehicle, "Quad1"))
local slotA, slotB = binding.slotIds[1], binding.slotIds[2]
local yards = workspace.CityGreybox.DeliveryYards
local zones = {Workshop = yards.Tischlerei_West.LoadZone.Volume, Supplier = yards.Holzlieferant.LoadZone.Volume,
	Dealer = yards.Moebelhandel.LoadZone.Volume}
local line = workspace.P02Line
local pickup = yards.Holzlieferant.P05Pickup
local wares = workspace.P0509LineDemo.Wares
local SCALE = 25 / 7
local FLAT = Vector3.new(1, 0, 1)
local buyer = "Dealer"

local initial = lineState:Invoke()
assert(initial.valid and initial.money == 180 and next(initial.batches) == nil and next(initial.reservations) == nil)
assert(Vehicles.zone(binding, zones) == "Workshop" and seat.Occupant == nil)
assert(vehicle:GetAttribute("OwnerUserId") == player.UserId)
local result = Instance.new("StringValue")
result.Name = "P0608Result"
result.Parent = storage
local stop = Instance.new("BindableFunction")
stop.Name = "P0608Stop"

type Transit = {
	slotId: string, stage: State.Stage, view: Model, relative: Vector3, revision: number, money: number,
	samples: number, distance: number, maxDrift: number, lastPoint: Vector3, lastSample: number,
}

local transit: Transit? = nil
local batchId = ""
local started = os.clock()
local savedRoot, savedAnchored = root.CFrame, root.Anchored
local stage = 0
local report: any = {status = "ready", checkpoints = {}, legs = {}, initialMoney = initial.money}

local function publish()
	result.Value = http:JSONEncode(report)
end

local function capture(name: string)
	if workspace:GetAttribute("P0608Capture") ~= true then return end
	report.capture = name
	publish()
	local deadline = os.clock() + 20
	repeat task.wait(0.1)
	until workspace:GetAttribute("P0608Captured") == name or os.clock() >= deadline
	report.capture = nil
	publish()
end

local function finish(status: string, failure: string?)
	if report.status == "passed" or report.status == "failed" then return end
	report.status, report.failure, report.seconds = status, failure, os.clock() - started
	root.CFrame, root.Anchored = savedRoot, savedAnchored
	publish()
end

local function batchAt(snapshot: any, locationId: string, wareStage: State.Stage)
	local batch = snapshot.batches[batchId]
	assert(snapshot.valid and batch and batch.locationId == locationId and batch.stage == wareStage,
		"Expected " .. wareStage .. " at " .. locationId)
	assert(batch.quantity == 1 and batch.ownerUserId == player.UserId)
	assert(next(snapshot.batches, batchId) == nil and next(snapshot.batches) == batchId, "Expected exactly one batch")
end

local function checkpoint(label: string, locationId: string, wareStage: State.Stage): any
	local snapshot = lineState:Invoke()
	batchAt(snapshot, locationId, wareStage)
	table.insert(report.checkpoints, {label = label, stage = wareStage, location = locationId,
		money = snapshot.money, revision = snapshot.revision})
	publish()
	return snapshot
end

local function stand(locationId: string)
	local mount = binding.mounts[locationId]
	if mount then
		local pad = mount.Parent :: BasePart
		local target = mount.WorldPosition
		for _, side in {1, -1} do
			local foot = target + pad.CFrame.RightVector * side * 3.5
			local position = Vector3.new(foot.X, target.Y - pad.Size.Y / 2 + 2.5, foot.Z)
			root.CFrame = CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
			if HandMoves.checkReach(player, {point = mount}, true) == nil then return end
		end
		error("Neither side of the parked trailer is reachable at " .. locationId)
	end
	local group, slot = locationId:match("^(%w+)%.(%w+)$")
	assert(group and slot, locationId)
	local place = if group == "Supplier" then pickup elseif group == "RawStore" then line.Stores.Rohstofflager
		elseif group == "FinishedStore" then line.Stores.Fertiglager else line.Stations[group]
	local marker = place.Standpoints[slot] :: BasePart
	local point = place[slot].Transfer :: Attachment
	local toward = ((point.WorldPosition - marker.Position) * FLAT).Unit
	local buffer = if group == "Supplier" or group == "RawStore" then 0.35
		elseif group == "FinishedStore" then 0.20 * SCALE else 0.15 * SCALE
	local position = marker.Position - toward * buffer + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, position + toward)
end

local function move(locationId: string, direction: "Take" | "Put")
	stand(locationId)
	local moveResult = lineTest:Invoke(locationId, direction).result
	assert(moveResult.ok, locationId .. " " .. direction .. " -> " .. moveResult.code)
end

local function waitFor(locationId: string, wareStage: State.Stage, seconds: number)
	local deadline = os.clock() + seconds
	repeat
		local snapshot = lineState:Invoke()
		local batch = snapshot.batches[batchId]
		if batch and batch.locationId == locationId and batch.stage == wareStage then return end
		task.wait(0.25)
	until os.clock() > deadline or report.status == "failed"
	error("Timed out waiting for " .. wareStage .. " at " .. locationId)
end

local function cargoView(slotId: string, wareStage: State.Stage): Model
	local mount = binding.mounts[slotId]
	local displayed: Model? = nil
	for _, view in wares:GetChildren() do
		assert(not displayed and view:IsA("Model") and view.Name == batchId, "Duplicate or unexpected cargo view")
		displayed = view
	end
	assert(displayed and displayed:GetAttribute("Signature") == wareStage .. "@" .. slotId, "Missing or stale cargo view")
	local strap = displayed:FindFirstChild("LoadStrapTop")
	assert(strap and strap:IsA("BasePart") and strap.Transparency < 1 and not strap.CanCollide,
		"Missing visible load strap")
	local visible = false
	for _, part in displayed:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		local weld = part:FindFirstChildWhichIsA("WeldConstraint")
		assert(not part.Anchored and weld and weld.Enabled and weld.Part0 == mount.Parent and weld.Part1 == part,
			"Cargo part is not welded to its confirmed trailer slot")
		visible = visible or part.Transparency < 1
	end
	assert(visible, "Cargo view has no visible parts")
	return displayed
end

local function armTransit(slotId: string, wareStage: State.Stage, snapshot: any)
	local view = cargoView(slotId, wareStage)
	transit = {slotId = slotId, stage = wareStage, view = view,
		relative = binding.mounts[slotId].WorldCFrame:PointToObjectSpace(view:GetPivot().Position),
		revision = snapshot.revision, money = snapshot.money, samples = 0, distance = 0, maxDrift = 0,
		lastPoint = chassis.Position * FLAT, lastSample = os.clock()}
	root.CFrame = savedRoot + Vector3.new(0, 20, 0) -- Keep the anchored test avatar out of the vehicle path.
end

local function sampleTravel(active: Transit)
	local snapshot = lineState:Invoke()
	batchAt(snapshot, active.slotId, active.stage)
	assert(snapshot.revision == active.revision and snapshot.money == active.money, "Travel changed the confirmed inventory")
	local _, serverOwned = Vehicles.motion(vehicle, binding, chassis)
	assert(serverOwned and not seat.Occupant, "Lost server physics or an avatar occupied the test seat")
	local view = cargoView(active.slotId, active.stage)
	assert(view == active.view, "Cargo was recreated during travel")
	local relative = binding.mounts[active.slotId].WorldCFrame:PointToObjectSpace(view:GetPivot().Position)
	active.maxDrift = math.max(active.maxDrift, (relative - active.relative).Magnitude)
	assert(active.maxDrift <= 0.05, "Cargo drifted off the mount")
	local point, now = chassis.Position * FLAT, os.clock()
	local distance, delta = (point - active.lastPoint).Magnitude, now - active.lastSample
	assert(delta <= 1.5 and distance <= 12 * SCALE * delta + 1.5, "Gap or position jump while hauling cargo")
	active.lastPoint, active.lastSample = point, now
	active.distance += distance
	active.samples += 1
end

local function finishTransit(leg: any): any
	local active = assert(transit, "Missing cargo observer")
	sampleTravel(active)
	assert(active.samples >= 10 and active.distance / SCALE >= 0.75 * leg.roadM, "Too little measured cargo travel")
	transit = nil
	return {batchId = batchId, slotId = active.slotId, stage = active.stage, revision = active.revision,
		money = active.money, distanceM = active.distance / SCALE, samples = active.samples, maxDriftStuds = active.maxDrift}
end

local expectedStops = {"Supplier", "Workshop", buyer}
local expectedRoutes = {{"Tischlerei_West", "Holzlieferant"}, {"Holzlieferant", "Tischlerei_West"},
	{"Tischlerei_West", "Moebelhandel"}}
stop.OnInvoke = function(index: number, leg: any): boolean
	if report.status == "failed" or report.status == "passed" then return false end
	local ok, failure = xpcall(function()
		assert(index == stage + 1 and expectedStops[index], "Unexpected route stop")
		local route = expectedRoutes[index]
		assert(leg.from == route[1] and leg.to == route[2] and leg.roadM > 0 and leg.samples > 0, "Wrong road segment")
		assert(leg.zone.slotsInZone and leg.offPaved == 0 and leg.obstacleSamples == 0 and leg.zoneItemSamples == 0,
			"Route arrived with a missed zone or a contact")
		local still, serverOwned = Vehicles.motion(vehicle, binding, chassis)
		assert(still and serverOwned and Vehicles.zone(binding, zones) == expectedStops[index], "Rig is not parked in the expected zone")
		stage = index
		report.status = "running"
		table.insert(report.legs, {from = leg.from, to = leg.to, roadM = leg.roadM, seconds = leg.seconds,
			samples = leg.samples, zone = leg.zone, cargo = if index == 1 then nil else finishTransit(leg)})
		if index == 1 then
			stand("Supplier.Slot1")
			local buyResult = purchase:Invoke()
			assert(buyResult.ok, "Supplier purchase failed: " .. buyResult.code)
			local bought = lineState:Invoke()
			batchId = assert(next(bought.batches), "Purchase created no batch")
			local purchased = checkpoint("purchased", "Supplier.Slot1", "Holzpaket")
			assert(purchased.money == initial.money - 60, "Unexpected material debit")
			move("Supplier.Slot1", "Take")
			move(slotA, "Put")
			local loaded = checkpoint("wood loaded", slotA, "Holzpaket")
			capture("supplier")
			armTransit(slotA, "Holzpaket", loaded)
		elseif index == 2 then
			local snapshot = checkpoint("wood arrived", slotA, "Holzpaket")
			local rawSlot: string? = nil
			for id, reservation in snapshot.reservations do
				if reservation.kind == "Delivery" and reservation.batchId == batchId then rawSlot = id; break end
			end
			assert(rawSlot and rawSlot:match("^RawStore%.Slot"), "Missing paid delivery target")
			move(slotA, "Take")
			move(rawSlot, "Put")
			local delivered = checkpoint("wood unloaded", rawSlot, "Holzpaket")
			assert(next(delivered.reservations) == nil, "Delivery reservation did not release")
			capture("workshop")
			local from = rawSlot
			for _, rule in State.STATIONS do
				move(from, "Take")
				move(rule.input, "Put")
				waitFor(rule.output, rule.outputStage, rule.durationSeconds + 4)
				checkpoint(rule.id, rule.output, rule.outputStage)
				from = rule.output
			end
			local finishedSlot = "FinishedStore.Slot1"
			move(from, "Take")
			move(finishedSlot, "Put")
			checkpoint("carton stored", finishedSlot, "Karton")
			move(finishedSlot, "Take")
			move(slotB, "Put")
			armTransit(slotB, "Karton", checkpoint("carton loaded", slotB, "Karton"))
		else
			local snapshot = checkpoint("carton at buyer", slotB, "Karton")
			local arrival = snapshot.arrivals[slotB]
			assert(arrival and arrival.destination == buyer and arrival.batchId == batchId and arrival.slotId == slotB
				and arrival.vehicleId == binding.vehicleId and arrival.ownerUserId == player.UserId, "Missing confirmed buyer arrival")
			assert(next(snapshot.reservations) == nil and snapshot.money == initial.money - 60, "Final balance or reservations are wrong")
			report.arrival = arrival
			capture("buyer")
			finish("passed", nil)
		end
	end, function(message: any): string return debug.traceback(tostring(message), 2) end)
	if not ok then finish("failed", failure) end
	return ok and report.status ~= "failed"
end

root.Anchored = true
root.CFrame = savedRoot + Vector3.new(0, 20, 0)
stop.Parent = storage
publish()
task.spawn(function()
	while report.status == "ready" or report.status == "running" do
		task.wait(0.20)
		if report.status == "passed" or report.status == "failed" then break end
		if os.clock() - started > 240 then finish("failed", "P06-08 proof timed out"); break end
		local routeResult = storage:FindFirstChild("P0602Result")
		if routeResult and routeResult:IsA("StringValue") and routeResult.Value ~= "" then
			local legReport = http:JSONDecode(routeResult.Value)
			if legReport.status == "aborted" then finish("failed", "Physical route runner aborted"); break end
		end
		local active = transit
		if active then
			local ok, failure = pcall(sampleTravel, active)
			if not ok then finish("failed", tostring(failure)) end
		end
	end
end)

return {started = true, ready = true, result = result.Name}
