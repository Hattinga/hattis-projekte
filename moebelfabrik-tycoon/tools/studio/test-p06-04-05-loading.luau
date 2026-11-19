--!strict
-- Run on a fresh P06-loading demo in Studio Server mode.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning())
local storage = game:GetService("ServerStorage")
local interact = storage:FindFirstChild("P0509LineTest") :: BindableFunction
local reader = storage:FindFirstChild("P0509LineState") :: BindableFunction
local buy = storage:FindFirstChild("P060405Purchase") :: BindableFunction
assert(interact and reader and buy and not storage:FindFirstChild("P060405Result"))
local report = Instance.new("StringValue")
report.Name = "P060405Result"
report.Parent = storage

local player = game:GetService("Players"):GetPlayers()[1]
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local vehicle = workspace.P02Vehicle
local chassis = vehicle.Quad.Chassis :: BasePart
local yards = workspace.CityGreybox.DeliveryYards
local pickup = yards.Holzlieferant.P05Pickup
local stores = workspace.P02Line.Stores
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local Transfers = require(factory.Transfers)
local Recipe = require(factory.Recipe)
local HandMoves = require(factory.HandMoves)
local Loading = require(factory.Loading)
local Vehicles = require(factory.Vehicles)
local slots = assert(Vehicles.bind(vehicle, "Quad1"))
local slotA, slotB = slots.slotIds[1], slots.slotIds[2]
local savedPivot, savedRoot, savedAnchored = vehicle:GetPivot(), root.CFrame, root.Anchored
local savedOwner = vehicle:GetAttribute("OwnerUserId")
local flat = Vector3.new(1, 0, 1)

local function standAt(point: Attachment, marker: BasePart?)
	local target = point.WorldPosition
	local pad = point.Parent :: BasePart
	local foot = if marker then marker.Position + ((marker.Position - target) * flat).Unit * 0.35
		else target + pad.CFrame.RightVector * 3.5
	local height = if marker then marker.Position.Y + 3 else 3.25
	local position = Vector3.new(foot.X, height, foot.Z)
	root.CFrame = CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

local function moveVehicle(pivot: CFrame)
	vehicle:PivotTo(pivot)
	for _, item in vehicle:GetDescendants() do
		if item:IsA("BasePart") then
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function park(yard: BasePart)
	local at = Vector3.new(yard.Position.X, savedPivot.Position.Y, yard.Position.Z)
	moveVehicle(CFrame.new(at) * (savedPivot - savedPivot.Position))
end

local function act(id: string, direction: "Take" | "Put", expected: string?): any
	local mount = slots.mounts[id]
	if mount then
		standAt(mount, nil)
	else
		local kind, name = id:match("^(%w+)%.(%w+)$")
		assert(name, id)
		local group = if kind == "Supplier" then pickup else stores.Rohstofflager
		standAt(group[name].Transfer, group.Standpoints[name])
	end
	local before = reader:Invoke()
	local result = interact:Invoke(id, direction)
	assert(if expected then result.result.code == expected else result.result.ok,
		id .. " " .. direction .. ": " .. result.result.code)
	if expected then assert(result.revision == before.revision and reader:Invoke().money == before.money) end
	return result
end

task.spawn(function()
	local checks: {string} = {}
	root.Anchored = true
	local ok, failure = xpcall(function()
		local initial = reader:Invoke()
		assert(initial.money == 180 and next(initial.batches) == nil, "Start with a fresh P06 demo")
		assert(buy:Invoke().code == "TOO_FAR")
		standAt(pickup.Slot1.Transfer, pickup.Standpoints.Slot1)
		assert(buy:Invoke().ok)
		local purchased = reader:Invoke()
		local batchId = assert(next(purchased.batches))
		assert(purchased.money == 120 and purchased.revision == initial.revision + 1)
		assert(purchased.batches[batchId].locationId == "Supplier.Slot1" and purchased.reservations["RawStore.Slot1"].batchId == batchId)
		act("Supplier.Slot1", "Take")
		act("RawStore.Slot1", "Put", "WRONG_LOADING_ROUTE")
		table.insert(checks, "purchase at the physical supplier saves one package, one debit and its exact raw slot; direct walking delivery is refused")

		park(yards.Holzlieferant)
		vehicle:SetAttribute("OwnerUserId", player.UserId + 1)
		act(slotA, "Put", "NOT_VEHICLE_OWNER")
		vehicle:SetAttribute("OwnerUserId", savedOwner)
		chassis.AssemblyLinearVelocity = Vector3.new(8, 0, 0)
		act(slotA, "Put", "VEHICLE_MOVING")
		park(yards.Holzlieferant)
		local volume = yards.Holzlieferant.LoadZone.Volume :: BasePart
		local a, b = slots.mounts[slotA].WorldPosition, slots.mounts[slotB].WorldPosition
		local midpoint = (a + b) / 2
		local edge = volume.CFrame:PointToWorldSpace(Vector3.new(volume.Size.X / 2, 0, 0))
		moveVehicle(vehicle:GetPivot() + Vector3.new(edge.X - midpoint.X, 0, edge.Z - midpoint.Z))
		act(slotA, "Put", "WRONG_ZONE")
		park(yards.Tischlerei_West)
		act(slotA, "Put", "WRONG_LOADING_ROUTE")
		park(yards.Holzlieferant)
		local loaded = act(slotA, "Put")
		assert(loaded.batches[batchId].locationId == slotA)
		local view = workspace.P0509LineDemo.Wares[batchId]
		local weld = view:FindFirstChildWhichIsA("WeldConstraint", true)
		assert(weld and weld.Part0 == slots.mounts[slotA].Parent)
		table.insert(checks, "wrong owner, movement, split zone and wrong load yard leave stock unchanged; accepted load is welded to A")

		park(yards.Moebelhandel)
		act(slotA, "Take", "WRONG_ZONE")
		park(yards.Tischlerei_West)
		act(slotA, "Take")
		park(yards.Moebelhandel)
		act("RawStore.Slot2", "Put", "DELIVERY_TARGET_REQUIRED")
		act("RawStore.Slot1", "Put")
		park(yards.Tischlerei_West)
		act(slotA, "Take", "EMPTY")
		local delivered = reader:Invoke()
		assert(delivered.batches[batchId].locationId == "RawStore.Slot1" and delivered.reservations["RawStore.Slot1"] == nil)
		assert(delivered.money == 120 and delivered.valid)
		table.insert(checks, "dealer yard is refused; a started unload can finish after the vehicle leaves; exact delivery consumes its promise once")

		-- An isolated synthetic full-shelf setup exercises the same hand API in the actual workshop.
		local shelf = assert(Recipe.bindStore(stores.Fertiglager, "FinishedStore", "Karton"))
		local endpoints: {[string]: HandMoves.Endpoint} = {[slotB] = {point = slots.mounts[slotB]}}
		local profile = State.newProfile(player.UserId)
		for id, loc in slots.locations do profile.locations[id] = loc end
		for id, loc in shelf.locations do
			profile.locations[id] = loc
			local point = shelf.points[id]
			endpoints[id] = {point = point, stand = stores.Fertiglager.Standpoints[(point.Parent :: BasePart).Name]}
			profile.batches[id] = State.newBatch(id, player.UserId, "Karton", id)
		end
		profile.locations.hand = State.newLocation("hand", "Carrier", 1, {"Karton"})
		local loading: Loading.Binding = {vehicle = vehicle, slots = slots, chassis = chassis,
			zones = {Workshop = yards.Tischlerei_West.LoadZone.Volume}, destinations = shelf.points, unloads = {}}
		local store = Transfers.new(profile)
		local function doMove(id: string, direction: "Take" | "Put", op: string): HandMoves.Result
			local endpoint = endpoints[id]
			standAt(endpoint.point, endpoint.stand)
			return HandMoves.interact(store, player, true, "hand", endpoints, id, direction, op, os.time(), loading)
		end
		local source = "FinishedStore.Slot1"
		assert(doMove(source, "Take", "pick-carton").ok)
		local cartonLoad = doMove(slotB, "Put", "load-carton")
		assert(cartonLoad.ok, cartonLoad.code)
		store.profile.batches.fill = State.newBatch("fill", player.UserId, "Karton", source)
		assert(State.validate(store.profile))
		local fullRevision = store.profile.revision
		assert(doMove(slotB, "Take", "try-unload").code == "NO_FREE_TARGET")
		assert(store.profile.revision == fullRevision and store.profile.batches[source].locationId == slotB)
		table.insert(checks, "carton loads at the workshop and stays on B when all four finished-store destinations are occupied")
	end, function(problem: any): string return debug.traceback(tostring(problem), 2) end)
	vehicle:SetAttribute("OwnerUserId", savedOwner)
	moveVehicle(savedPivot)
	root.CFrame, root.Anchored = savedRoot, savedAnchored
	report.Value = game:GetService("HttpService"):JSONEncode({status = if ok then "passed" else "failed", checks = checks, failure = failure})
end)
return {started = true}
