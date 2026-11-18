--!strict
-- P04-07: derive physical placement from a fresh persistence snapshot, without moving stock.
local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)

export type Placement = {locationId: string, pointId: string, atRecoveryPoint: boolean}
export type Plan = {
	ok: boolean,
	code: string,
	ready: boolean,
	storageRevision: number?,
	stateRevision: number?,
	placements: {[string]: Placement}?,
}

local Recovery = {}
local MAX_INTEGER = 9007199254740991

local function integer(value: number): boolean
	return value >= 0 and value <= MAX_INTEGER and value % 1 == 0
end

local function rejected(code: string): Plan
	return {ok = false, code = code, ready = false}
end

-- Both registries are assembled by the server from present, reachable, distinct world points.
-- A recovery point represents the same logical slot within its transfer zone.
-- Claim expiry and all stock mutations belong to Transfers and Persistence.
function Recovery.plan(
	snapshot: Persistence.Result,
	ownerUserId: number,
	now: number,
	originalPoints: {[string]: string},
	recoveryPoints: {[string]: string}
): Plan
	local saved = snapshot.confirmed
	if not snapshot.ok or snapshot.code ~= "SNAPSHOT" or snapshot.status ~= "Confirmed"
		or snapshot.inFlight or snapshot.unknown or not saved or saved.sessionId == "" then
		return rejected("NOT_CONFIRMED")
	end
	if not integer(now) or not integer(saved.expiresAt) or now >= saved.expiresAt then
		return rejected("SESSION_UNAVAILABLE")
	end
	local state = saved.data.state
	if state.ownerUserId ~= ownerUserId or not State.validate(state) then
		return rejected("INVALID_STATE")
	end

	local placements: {[string]: Placement} = {}
	local allocated: {[string]: string} = {}

	local function bind(locationId: string, pointId: string): boolean
		if pointId == "" or (allocated[pointId] and allocated[pointId] ~= locationId) then
			return false
		end
		allocated[pointId] = locationId
		return true
	end

	-- An empty but registered slot must never share the substitute point of another slot.
	for locationId in state.locations do
		local point = originalPoints[locationId]
		if point and not bind(locationId, point) then return rejected("POINT_CONFLICT") end
	end
	for locationId in state.reservations do
		if originalPoints[locationId] == nil then return rejected("PROMISED_POINT_MISSING") end
	end
	for batchId, batch in state.batches do
		local locationId = batch.locationId
		local original = originalPoints[locationId]
		local point = original or recoveryPoints[locationId]
		local kind = state.locations[locationId].kind
		if not original and (kind == "Carrier" or kind == "Band") then
			return rejected("CARRIER_MISSING")
		end
		if not original and (kind == "StationProcess" or kind == "Machine") then
			return rejected("PROCESS_SLOT_MISSING")
		end
		if not point then return rejected("POINT_MISSING") end
		if not bind(locationId, point) then return rejected("POINT_CONFLICT") end
		placements[batchId] = {locationId = locationId, pointId = point, atRecoveryPoint = original == nil}
	end

	return {ok = true, code = "PLANNED", ready = false, storageRevision = saved.revision,
		stateRevision = state.revision, placements = placements}
end

return table.freeze(Recovery)
