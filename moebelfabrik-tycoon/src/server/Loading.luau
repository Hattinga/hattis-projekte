--!strict
-- P06-04/05: server-side vehicle and destination checks for physical hand moves.
local State = require(script.Parent.State)
local Vehicles = require(script.Parent.Vehicles)

type Unload = {batchId: string, slotId: string, destinationKind: string}
export type Binding = {
	vehicle: Model,
	slots: Vehicles.Binding,
	chassis: BasePart,
	zones: {[string]: BasePart},
	destinations: {[string]: Attachment},
	unloads: {[string]: Unload}, -- current hand unload per carrier, until the next vehicle pickup
	recoveryPoints: {[string]: Attachment}?,
}

local Loading = {}

local function parkedIn(binding: Binding?, slotId: string, userId: number): (string?, string?)
	if not binding or not binding.slots.mounts[slotId] then
		return nil, "UNKNOWN_LOCATION"
	end
	if binding.vehicle:GetAttribute("OwnerUserId") ~= userId then return nil, "NOT_VEHICLE_OWNER" end
	local still = Vehicles.motion(binding.vehicle, binding.slots, binding.chassis)
	if still == nil then return nil, "UNKNOWN_LOCATION" end
	if not still then return nil, "VEHICLE_MOVING" end
	local zone = Vehicles.zone(binding.slots, binding.zones)
	return zone, if zone then nil else "WRONG_ZONE"
end

local function unloadKind(zone: string, stage: State.Stage): string?
	if zone == "Supplier" and stage == "Holzpaket" then return "Supplier" end
	if zone == "Workshop" then
		if stage == "Holzpaket" then return "RawStore" end
		if stage == "Karton" then return "FinishedStore" end
	end
	return nil
end

local function hasFreeTarget(
	profile: State.Profile,
	batch: State.Batch,
	kind: string,
	points: {[string]: Attachment},
	now: number
): boolean
	local deliveryTarget: string? = nil
	for id, reservation in profile.reservations do
		if reservation.kind == "Delivery" and reservation.batchId == batch.id then deliveryTarget = id end
	end
	for id, point in points do
		local target = profile.locations[id]
		if not target or target.kind ~= kind or not point:IsDescendantOf(workspace)
			or not table.find(target.acceptedStages, batch.stage) or State.countAt(profile, id) >= target.capacity
			or (kind == "RawStore" and deliveryTarget and deliveryTarget ~= id) then continue end
		local promise = profile.reservations[id]
		if promise and (promise.kind ~= "Delivery" or promise.batchId ~= batch.id) then continue end
		local claimed = false
		for _, claim in profile.claims do
			if now < claim.expiresAt and (claim.sourceId == id or claim.targetId == id) then
				claimed = true
				break
			end
		end
		if not claimed then return true end
	end
	return false
end

function Loading.check(
	binding: Binding?,
	profile: State.Profile,
	location: State.Location,
	point: Attachment,
	carrierId: string,
	batch: State.Batch,
	direction: "Take" | "Put",
	now: number
): (string?, string?)
	local originId: string? = nil
	local originKind: string? = nil
	if direction == "Put" then
		for id, reservation in profile.reservations do
			if reservation.kind == "Return" and reservation.batchId == batch.id then
				originId, originKind = id, profile.locations[id].kind
				break
			end
		end
	end

	if location.kind == "VehicleSlot" then
		if not binding then return "UNKNOWN_LOCATION", nil end
		local recoveryPoint = if binding.recoveryPoints then binding.recoveryPoints[location.id] else nil
		if recoveryPoint == point then
			if direction == "Take" or originId == location.id then return nil, nil end
			return "WRONG_LOADING_ROUTE", nil
		end
		if binding.slots.mounts[location.id] ~= point then return "UNKNOWN_LOCATION", nil end
		if recoveryPoint and (direction == "Take" or originId ~= location.id) then return "RECOVERY_REQUIRED", nil end
		local zone, problem = parkedIn(binding, location.id, profile.ownerUserId)
		if not zone then return problem, nil end
		if direction == "Take" then
			local kind = unloadKind(zone, batch.stage)
			if not kind then return "WRONG_ZONE", nil end
			if not hasFreeTarget(profile, batch, kind, binding.destinations, now) then return "NO_FREE_TARGET", nil end
			return nil, kind
		elseif not table.find(location.acceptedStages, batch.stage) then
			return "WRONG_STAGE", nil
		elseif originId == location.id then
			return nil, nil -- Return the hand load to its own slot.
		elseif not ((zone == "Supplier" and originKind == "Supplier" and batch.stage == "Holzpaket")
			or (zone == "Workshop" and originKind == "FinishedStore" and batch.stage == "Karton")) then
			return "WRONG_LOADING_ROUTE", nil
		end
	elseif originKind == "VehicleSlot" and originId then
		local unload = if binding then binding.unloads[carrierId] else nil
		if not unload or unload.batchId ~= batch.id or unload.slotId ~= originId or unload.destinationKind ~= location.kind then
			return "WRONG_LOADING_ROUTE", nil
		end
	elseif originKind == "Supplier" and location.id ~= originId then
		return "WRONG_LOADING_ROUTE", nil -- A supplier pickup must go by vehicle or return to its own pad.
	end
	return nil, nil
end

return table.freeze(Loading)
