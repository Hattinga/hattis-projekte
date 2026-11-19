--!strict
-- Start in a fresh Studio Server, then run drive-p06-02-route.luau when P0606TripResult is ready.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning())
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0606TripResult") and not storage:FindFirstChild("P0602Result"))
local result = Instance.new("StringValue")
result.Name = "P0606TripResult"
result.Parent = storage
local http = game:GetService("HttpService")
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local Trips = require(factory.Trips)
local Vehicles = require(factory.Vehicles)
local LineView = require(factory.LineView)
local vehicle = workspace.P02Vehicle
local chassis = vehicle.Quad.Chassis :: BasePart
local yards = workspace.CityGreybox.DeliveryYards
local zones = {Workshop = yards.Tischlerei_West.LoadZone.Volume, Dealer = yards.Moebelhandel.LoadZone.Volume,
	Private = yards.Privatkunden.LoadZone.Volume}
local original = vehicle:GetPivot()
local slots = assert(Vehicles.bind(vehicle, "Quad1"))
local slotA, slotB = slots.slotIds[1], slots.slotIds[2]
local profile = State.newProfile(101)
profile.money = 120
profile.locations = slots.locations
profile.batches.testA = State.newBatch("testA", 101, "Karton", slotA)
profile.batches.testB = State.newBatch("testB", 101, "Karton", slotB)
assert(State.validate(profile))
vehicle:SetAttribute("OwnerUserId", 101)
local trip = Trips.new({vehicle = vehicle, chassis = chassis, slots = slots, zones = zones})
local viewRoot = Instance.new("Folder")
viewRoot.Name = "P0606TripWares"
viewRoot.Parent = workspace
local places = {points = {}, mounts = slots.mounts, stationPads = {}}
local views = LineView.syncWares(viewRoot, profile, places)
Vehicles.useServerPhysics(vehicle)

local function zeroMotion()
	for _, item in vehicle:GetDescendants() do
		if item:IsA("BasePart") then
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

task.spawn(function()
	local report: any = {status = "running", checks = {}}
	local ok, failure = xpcall(function()
		local function sample()
			Trips.sample(trip, profile, os.clock())
		end
		local function arrival(slot: string, destination: string): Trips.Arrival?
			return Trips.arrival(trip, profile, slot, destination, os.clock())
		end
		assert(Vehicles.zone(slots, zones) == "Workshop")
		sample()
		assert(not arrival(slotA, "Dealer"))
		local dealer = zones.Dealer.Position
		vehicle:PivotTo(CFrame.new(dealer.X, original.Position.Y, dealer.Z) * (original - original.Position))
		zeroMotion()
		Vehicles.useServerPhysics(vehicle)
		local still, serverOwned = Vehicles.motion(vehicle, slots, chassis)
		assert(still and serverOwned)
		assert(Vehicles.zone(slots, zones) == "Dealer")
		for _ = 1, 8 do task.wait(0.1); sample() end
		assert(not arrival(slotA, "Dealer"))
		table.insert(report.checks, "direct reposition into Dealer failed with both slots inside and a standstill")

		vehicle:PivotTo(original)
		zeroMotion()
		Vehicles.useServerPhysics(vehicle)
		local view = assert(views.testA)
		local mount = slots.mounts[slotA]
		local relative = mount.WorldCFrame:ToObjectSpace(view:GetPivot())
		sample()
		workspace:SetAttribute("P0606TripProbe", true)
		report.status = "ready"
		result.Value = http:JSONEncode(report)
		local deadline = os.clock() + 100
		local approved: Trips.Arrival? = nil
		repeat
			task.wait(0.1)
			sample()
			approved = arrival(slotA, "Dealer")
		until approved or os.clock() > deadline
		assert(approved, "Physical route did not establish a complete trip")
		assert(approved.batchId == "testA" and approved.ownerUserId == 101 and approved.vehicleId == "Quad1")
		assert(arrival(slotB, "Dealer") and not arrival(slotA, "Private"))
		report.dealerArrival = approved

		local privateArrival: Trips.Arrival? = nil
		repeat
			task.wait(0.1)
			sample()
			privateArrival = arrival(slotA, "Private")
		until privateArrival or os.clock() > deadline
		assert(privateArrival and privateArrival.batchId == "testA", "The second buyer had no valid arrival")
		assert(arrival(slotB, "Private") and not arrival(slotA, "Dealer"))
		assert(profile.money == 120 and profile.revision == 0 and profile.batches.testA.locationId == slotA)
		local drift = (mount.WorldCFrame:ToObjectSpace(view:GetPivot()).Position - relative.Position).Magnitude
		assert(drift < 0.05, tostring(drift))
		report.privateArrival = privateArrival
		report.driftStuds = drift
		table.insert(report.checks, "loaded A/B arrived at both buyers by continuous motion; only the current buyer was eligible and stock and money stayed the same")

		assert(not Trips.arrival(trip, profile, slotA, "Private", os.clock() - 1))
		assert(not Trips.arrival(trip, State.newProfile(102), slotA, "Private", os.clock()))
		assert(arrival(slotA, "Private") and arrival(slotB, "Private"))
		local removed = profile.batches.testA
		profile.batches.testA = nil
		LineView.syncWares(viewRoot, profile, places)
		Vehicles.useServerPhysics(vehicle)
		sample()
		assert(not arrival(slotA, "Private") and arrival(slotB, "Private"))
		profile.batches.testA = removed
		assert(not arrival(slotA, "Private"), "Putting the same batch back cannot restore old evidence")
		chassis.AssemblyLinearVelocity = Vector3.new(8, 0, 0)
		assert(not arrival(slotB, "Private"), "Moving again must clear current eligibility")
		zeroMotion()
		vehicle:SetAttribute("OwnerUserId", 102)
		sample()
		assert(not arrival(slotB, "Private") and next(trip.traces) == nil)
		table.insert(report.checks, "cargo removal, movement and owner change invalidated the relevant evidence")
	end, function(problem: any): string return debug.traceback(tostring(problem), 2) end)
	workspace:SetAttribute("P0606TripProbe", nil)
	vehicle:PivotTo(original)
	zeroMotion()
	viewRoot:Destroy()
	report.status = if ok then "passed" else "failed"
	report.failure = failure
	result.Value = http:JSONEncode(report)
end)
return {started = true}
