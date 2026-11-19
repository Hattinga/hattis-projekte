--!strict
-- P06-06: read-only arrival evidence from a server-owned rig's continuous physical motion.
local State = require(script.Parent.State)
local Vehicles = require(script.Parent.Vehicles)

export type Binding = {
	vehicle: Model, chassis: BasePart, slots: Vehicles.Binding, zones: {[string]: BasePart},
	recoveryPoints: {[string]: Attachment}?,
}
export type Arrival = {
	ownerUserId: number, vehicleId: string, slotId: string, batchId: string, destination: string,
	departedAt: number, arrivedAt: number, travelledStuds: number,
}
type Trace = {batchId: string, departedAt: number?, travelled: number, stoppedAt: number?, arrival: Arrival?}
export type Tracker = {
	binding: Binding, traces: {[string]: Trace}, previousPosition: Vector2?, previousTime: number?, ownerUserId: number?,
}

local Trips = {}
local SCALE = 25 / 7
local MAX_SPEED = 12 * SCALE -- The quad motor tops out near 8.4 m/s.
local MAX_GAP = 1 -- Stale observations cannot form a continuous trip.
local SETTLE_TIME = 0.5

local function flat(position: Vector3): Vector2
	return Vector2.new(position.X, position.Z)
end

function Trips.new(binding: Binding): Tracker
	return {binding = binding, traces = {}}
end

function Trips.sample(tracker: Tracker, profile: State.Profile, now: number)
	local binding = tracker.binding
	local still, serverOwned = Vehicles.motion(binding.vehicle, binding.slots, binding.chassis)
	local owner = profile.ownerUserId
	if still == nil or not serverOwned or binding.vehicle:GetAttribute("OwnerUserId") ~= owner then
		table.clear(tracker.traces)
		tracker.previousPosition, tracker.previousTime, tracker.ownerUserId = nil, nil, nil
		return
	end
	local position = flat(binding.chassis.Position)
	local priorPosition, priorTime = tracker.previousPosition, tracker.previousTime
	local travelled = if priorPosition then (position - priorPosition).Magnitude else 0
	local elapsed = if priorTime then now - priorTime else 0
	if tracker.ownerUserId ~= owner or elapsed < 0 or elapsed > MAX_GAP
		or travelled > MAX_SPEED * elapsed + 1 then
		table.clear(tracker.traces)
		travelled = 0
	end
	tracker.previousPosition, tracker.previousTime, tracker.ownerUserId = position, now, owner
	local zone = Vehicles.zone(binding.slots, binding.zones)
	local origin = binding.zones.Workshop
	local target = if zone == "Dealer" or zone == "Private" then binding.zones[zone] else nil
	local minimumTravel = if origin and target then (flat(origin.Position) - flat(target.Position)).Magnitude
		- (flat(origin.Size).Magnitude + flat(target.Size).Magnitude) / 2 - 2 * SCALE else math.huge
	local cargo = Vehicles.load(profile, binding.slots.slotIds).batches

	for _, slotId in binding.slots.slotIds do
		local batch = profile.batches[cargo[slotId]]
		local trace = tracker.traces[slotId]
		if not batch or batch.stage ~= "Karton" or batch.ownerUserId ~= owner
			or (binding.recoveryPoints and binding.recoveryPoints[slotId]) then
			tracker.traces[slotId] = nil
			continue
		end
		if zone == "Workshop" and still then
			tracker.traces[slotId] = {batchId = batch.id, travelled = 0}
			continue
		end
		if not trace or trace.batchId ~= batch.id then
			tracker.traces[slotId] = nil
			continue
		end
		if zone ~= "Workshop" and not trace.departedAt then trace.departedAt = now end
		local departed = trace.departedAt
		if not departed then continue end
		trace.travelled += travelled
		if not (still and target and zone and trace.travelled >= minimumTravel) then
			trace.stoppedAt, trace.arrival = nil, nil
			continue
		end
		local stopped = trace.stoppedAt or now
		trace.stoppedAt = stopped
		if now - stopped >= SETTLE_TIME and not trace.arrival then
			trace.arrival = {ownerUserId = owner, vehicleId = binding.slots.vehicleId, slotId = slotId,
				batchId = batch.id, destination = zone, departedAt = departed, arrivedAt = now, travelledStuds = trace.travelled}
		end
	end
end

-- The next sale step can use only the current evidence for its requested slot and buyer.
function Trips.arrival(tracker: Tracker, profile: State.Profile, slotId: string, destination: string, now: number): Arrival?
	local trace = tracker.traces[slotId]
	local arrival = if trace then trace.arrival else nil
	local previous = tracker.previousTime
	if not arrival or arrival.destination ~= destination or arrival.ownerUserId ~= profile.ownerUserId
		or not previous or now < previous or now - previous > MAX_GAP then return nil end
	local batch = profile.batches[arrival.batchId]
	local binding = tracker.binding
	if not batch or batch.stage ~= "Karton" or batch.locationId ~= slotId or batch.ownerUserId ~= arrival.ownerUserId
		or (binding.recoveryPoints and binding.recoveryPoints[slotId])
		or binding.vehicle:GetAttribute("OwnerUserId") ~= arrival.ownerUserId then return nil end
	local still, serverOwned = Vehicles.motion(binding.vehicle, binding.slots, binding.chassis)
	if still and serverOwned and Vehicles.zone(binding.slots, binding.zones) == destination then
		return table.clone(arrival)
	end
	return nil
end

return table.freeze(Trips)
