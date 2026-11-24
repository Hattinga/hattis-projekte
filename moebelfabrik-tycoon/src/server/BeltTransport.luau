--!strict
-- P09-03: one shared-stock buffer between the two registered positions.
local Persistence = require(script.Parent.Persistence)
local Profiles = require(script.Parent.Profiles)
local State = require(script.Parent.State)
local Transfers = require(script.Parent.Transfers)

local BeltTransport = {}
local route = State.FIRST_BELT
local CLAIM_SECONDS = 16
export type Result = {ok: boolean, code: string, claimId: string?, batchId: string?}

local function confirmed(controller: Persistence.Controller): (Profiles.Envelope?, string?)
	local snapshot = controller.snapshot()
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not snapshot.confirmed then
		return nil, "NOT_CONFIRMED"
	end
	local profile = snapshot.confirmed.data
	if not profile.progress.firstBelt then return nil, "BELT_NOT_INSTALLED" end
	return profile, nil
end

local function actor(data: Profiles.Envelope): any
	return {ownerUserId = data.state.ownerUserId, kind = "Band", ready = true,
		actorId = route.carrier, carrierLocationId = route.carrier}
end

local function save(controller: Persistence.Controller, data: Profiles.Envelope, store: Transfers.Store,
	lease: number, result: Transfers.Result, batchId: string): Result
	if not result.ok then return {ok = false, code = result.code, batchId = batchId} end
	data.state = store.profile
	local persisted = controller.save(data, lease)
	if not persisted.ok then return {ok = false, code = persisted.code, batchId = batchId} end
	return {ok = true, code = result.code, claimId = result.claimId, batchId = batchId}
end

function BeltTransport.reserve(controller: Persistence.Controller, source: string, operationId: string, now: number,
	lease: number): Result
	local data, problem = confirmed(controller)
	if not data then return {ok = false, code = problem :: string} end
	if source ~= route.source and source ~= route.carrier then return {ok = false, code = "WRONG_BELT_SOURCE"} end
	local batchId: string? = nil
	for id, batch in data.state.batches do
		if batch.locationId == source and batch.stage == route.stage then
			batchId = id
			break
		end
	end
	if not batchId then return {ok = false, code = "NO_MATERIAL"} end
	local store = Transfers.new(data.state)
	local belt = actor(data)
	local result = Transfers.reserve(store, belt, {operationId = operationId, expectedRevision = data.state.revision,
		batchId = batchId, sourceId = source, targetId = if source == route.source then route.carrier else route.target,
		quantity = 1}, now, CLAIM_SECONDS)
	if not result.ok or source == route.carrier then return save(controller, data, store, lease, result, batchId) end
	-- At the flush input the belt can accept a kit immediately, even when its exit is occupied.
	local loaded = Transfers.commit(store, belt, {operationId = operationId .. "/commit",
		expectedRevision = store.profile.revision, claimId = result.claimId}, now)
	return save(controller, data, store, lease, loaded, batchId)
end

function BeltTransport.finish(controller: Persistence.Controller, claimId: string, now: number, lease: number,
	deliver: boolean): Result
	local data, problem = confirmed(controller)
	if not data then return {ok = false, code = problem :: string} end
	local claim = data.state.claims[claimId]
	if not claim or claim.sourceId ~= route.carrier or claim.targetId ~= route.target or claim.actorId ~= route.carrier
		or claim.actorKind ~= "Band" then return {ok = false, code = "CLAIM_NOT_FOUND"} end
	-- P09-04: a stopped belt never delivers; its exit claim can only be released.
	if deliver and (data.progress.firstBelt :: Profiles.BeltPermit).stopped then
		return {ok = false, code = "BELT_STOPPED", batchId = claim.batchId}
	end
	local store = Transfers.new(data.state)
	local result
	if deliver then
		result = Transfers.commit(store, actor(data), {operationId = claimId .. "/commit",
			expectedRevision = data.state.revision, claimId = claimId}, now)
	elseif now >= claim.expiresAt then
		result = Transfers.expireClaims(store, now)
	else
		result = Transfers.cancel(store, actor(data), {operationId = claimId .. "/cancel",
			expectedRevision = data.state.revision, claimId = claimId}, now)
	end
	return save(controller, data, store, lease, result, claim.batchId)
end

return table.freeze(BeltTransport)
