--!strict
-- P08-03: two confirmed transfers through one worker carrier and one reserved destination.
local Persistence = require(script.Parent.Persistence)
local Profiles = require(script.Parent.Profiles)
local State = require(script.Parent.State)
local Transfers = require(script.Parent.Transfers)

local WorkerTransport = {}
local CARRIER = State.FIRST_WORKER.carrier
local CLAIM_SECONDS = 20

export type Result = {ok: boolean, code: string, claimId: string?, batchId: string?}

local function load(controller: Persistence.Controller): (Profiles.Envelope?, string?)
	local snapshot = controller.snapshot()
	local saved = snapshot.confirmed
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not saved then return nil, "NOT_CONFIRMED" end
	local profile = saved.data
	local worker = profile.progress.firstWorker
	if not worker or not worker.assigned then return nil, "NOT_ASSIGNED" end
	return profile, nil
end

-- P09-06: the assigned leg (the saw leg unless the profile moved the worker to Finish -> Packen).
local function legOf(profile: Profiles.Envelope): State.WorkerLeg
	local worker = profile.progress.firstWorker :: Profiles.WorkerHire
	return State.WORKER_ROUTES[worker.route or "Saw"]
end

local function actor(profile: Profiles.Envelope): any
	return {ready = true, ownerUserId = profile.state.ownerUserId, kind = "Worker",
		actorId = CARRIER, carrierLocationId = CARRIER}
end

local function save(controller: Persistence.Controller, profile: Profiles.Envelope, store: Transfers.Store,
	lease: number, success: Result): Result
	profile.state = store.profile
	local saved = controller.save(profile, lease)
	if not saved.ok then return {ok = false, code = saved.code} end
	return success
end

function WorkerTransport.reserve(controller: Persistence.Controller, id: string, now: number, lease: number): Result
	local profile, problem = load(controller)
	if not profile then return {ok = false, code = problem :: string} end
	local route = legOf(profile)
	local state = profile.state
	local batchId: string? = nil
	for stockId, batch in state.batches do
		if batch.locationId == route.source and batch.stage == route.stage then
			batchId = stockId
			break
		end
	end
	if not batchId then return {ok = false, code = "NO_MATERIAL"} end
	if not state.locations[route.carrier] then
		state.locations[route.carrier] = State.newLocation(route.carrier, "Carrier", 1, {route.stage})
	end
	local store = Transfers.new(state)
	local result = Transfers.reserve(store, actor(profile), {operationId = id, expectedRevision = state.revision,
		batchId = batchId, sourceId = route.source, targetId = route.carrier, nextTargetId = route.target,
		quantity = 1}, now, CLAIM_SECONDS)
	if not result.ok then return {ok = false, code = result.code, batchId = batchId} end
	return save(controller, profile, store, lease, {ok = true, code = result.code,
		claimId = result.claimId, batchId = batchId})
end

-- Pickup commits and opens the drop claim in the same candidate. Competing actors never see an unlocked target.
function WorkerTransport.take(controller: Persistence.Controller, claimId: string, now: number, lease: number): Result
	local profile, problem = load(controller)
	if not profile then return {ok = false, code = problem :: string} end
	local route = legOf(profile)
	local state = profile.state
	local claim = state.claims[claimId]
	if not claim or claim.nextTargetId ~= route.target then return {ok = false, code = "CLAIM_NOT_FOUND"} end
	local store = Transfers.new(state)
	local worker = actor(profile)
	local take = Transfers.commit(store, worker, {operationId = claimId .. "/take",
		expectedRevision = state.revision, claimId = claimId}, now)
	if not take.ok then return {ok = false, code = take.code} end
	local drop = Transfers.reserve(store, worker, {operationId = claimId .. "/put",
		expectedRevision = store.profile.revision, batchId = claim.batchId,
		sourceId = route.carrier, targetId = route.target, quantity = 1}, now, CLAIM_SECONDS)
	if not drop.ok then return {ok = false, code = drop.code} end
	return save(controller, profile, store, lease, {ok = true, code = "PICKED_UP",
		claimId = drop.claimId, batchId = claim.batchId})
end

function WorkerTransport.put(controller: Persistence.Controller, claimId: string, now: number, lease: number): Result
	local profile, problem = load(controller)
	if not profile then return {ok = false, code = problem :: string} end
	local route = legOf(profile)
	local state = profile.state
	local claim = state.claims[claimId]
	if not claim or claim.sourceId ~= route.carrier or claim.targetId ~= route.target then
		return {ok = false, code = "CLAIM_NOT_FOUND"}
	end
	local store = Transfers.new(state)
	local placed = Transfers.commit(store, actor(profile), {operationId = claimId .. "/commit",
		expectedRevision = state.revision, claimId = claimId}, now)
	if not placed.ok then return {ok = false, code = placed.code} end
	return save(controller, profile, store, lease, {ok = true, code = "DELIVERED", batchId = claim.batchId})
end

function WorkerTransport.cancel(controller: Persistence.Controller, claimId: string, now: number, lease: number): Result
	local profile, problem = load(controller)
	if not profile then return {ok = false, code = problem :: string} end
	local store = Transfers.new(profile.state)
	local claim = store.profile.claims[claimId]
	if not claim then return {ok = true, code = "CLAIM_NOT_FOUND"} end
	if claim.carrierId ~= CARRIER or claim.actorId ~= CARRIER or claim.actorKind ~= "Worker" then
		return {ok = false, code = "NOT_AUTHORIZED"}
	end
	local cancelled
	if now >= claim.expiresAt then
		cancelled = Transfers.expireClaims(store, now)
	else
		cancelled = Transfers.cancel(store, actor(profile), {operationId = claimId .. "/cancel",
			expectedRevision = store.profile.revision, claimId = claimId}, now)
	end
	if not cancelled.ok then return {ok = false, code = cancelled.code} end
	return save(controller, profile, store, lease, {ok = true, code = cancelled.code})
end

-- After abandoning the destination, use the guaranteed physical return point.
function WorkerTransport.restore(controller: Persistence.Controller, operationId: string, now: number, lease: number): Result
	local profile, problem = load(controller)
	if not profile then return {ok = false, code = problem :: string} end
	local route = legOf(profile)
	local state = profile.state
	local held = state.reservations[route.source]
	if not held or held.kind ~= "Return" or held.carrierId ~= route.carrier or held.actorId ~= route.carrier then
		return {ok = false, code = "NOT_CARRYING"}
	end
	local store = Transfers.new(state)
	local worker = actor(profile)
	local claim = Transfers.reserve(store, worker, {operationId = operationId, expectedRevision = state.revision,
		batchId = held.batchId, sourceId = route.carrier, targetId = route.source, quantity = 1}, now, CLAIM_SECONDS)
	if not claim.ok then return {ok = false, code = claim.code} end
	local returned = Transfers.commit(store, worker, {operationId = operationId .. "/commit",
		expectedRevision = store.profile.revision, claimId = claim.claimId}, now)
	if not returned.ok then return {ok = false, code = returned.code} end
	return save(controller, profile, store, lease, {ok = true, code = "RETURNED", batchId = held.batchId})
end

-- Used only by the world adapter after checking the stopped worker and the owner's physical reach.
function WorkerTransport.recover(controller: Persistence.Controller, userId: number, hand: string,
	operationId: string, now: number, lease: number): Result
	local profile, problem = load(controller)
	if not profile then return {ok = false, code = problem :: string} end
	local route = legOf(profile)
	local state = profile.state
	if state.ownerUserId ~= userId then return {ok = false, code = "NOT_AUTHORIZED"} end
	local held = state.reservations[route.source]
	if not held or held.kind ~= "Return" or held.carrierId ~= route.carrier or held.actorId ~= route.carrier then
		return {ok = false, code = "NOT_CARRYING"}
	end
	local store = Transfers.new(state)
	local player = {ready = true, kind = "Player", ownerUserId = userId,
		actorId = "Player/" .. string.format("%.0f", userId), carrierLocationId = hand}
	local claim = Transfers.reserve(store, player, {operationId = operationId, expectedRevision = state.revision,
		batchId = held.batchId, sourceId = route.carrier, targetId = hand, recoverWorker = true, quantity = 1}, now, 5)
	if not claim.ok then return {ok = false, code = claim.code} end
	local taken = Transfers.commit(store, player, {operationId = operationId .. "/commit",
		expectedRevision = store.profile.revision, claimId = claim.claimId}, now)
	if not taken.ok then return {ok = false, code = taken.code} end
	return save(controller, profile, store, lease, {ok = true, code = "RECOVERED", batchId = held.batchId})
end

return table.freeze(WorkerTransport)
