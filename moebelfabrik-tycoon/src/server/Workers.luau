--!strict
-- P08-01: the first worker is a permanent entitlement of one workshop.
local Persistence = require(script.Parent.Persistence)
local Profiles = require(script.Parent.Profiles)
local State = require(script.Parent.State)

type Result = {ok: boolean, code: string, hired: Profiles.WorkerHire?}

local Workers = {}
Workers.PRICE = 120
local MAX_REVISION = 9007199254740991

local function current(controller: Persistence.Controller, ownerUserId: any, expectedRevision: any): (Profiles.Envelope?, string?)
	local snapshot = controller.snapshot()
	local confirmed = snapshot.confirmed
	if not confirmed or snapshot.inFlight or snapshot.status ~= "Confirmed" then
		return nil, "NOT_CONFIRMED"
	end
	local profile = confirmed.data
	if profile.state.ownerUserId ~= ownerUserId then return nil, "NOT_AUTHORIZED" end
	if type(expectedRevision) ~= "number" or expectedRevision % 1 ~= 0
		or expectedRevision < 0 or expectedRevision > MAX_REVISION then
		return nil, "INVALID_REQUEST"
	end
	return profile, nil
end

function Workers.hire(controller: Persistence.Controller, ownerUserId: any, expectedRevision: any, lease: number): Result
	local profile, problem = current(controller, ownerUserId, expectedRevision)
	if not profile then return {ok = false, code = problem :: string} end
	local state = profile.state
	local hired = profile.progress.firstWorker
	if hired then return {ok = true, code = "ALREADY_HIRED", hired = hired} end
	if state.revision ~= expectedRevision then return {ok = false, code = "STALE_REVISION"} end
	if state.revision == MAX_REVISION then return {ok = false, code = "REVISION_OVERFLOW"} end
	if state.money < Workers.PRICE then return {ok = false, code = "NOT_ENOUGH_MONEY"} end

	state.money -= Workers.PRICE
	state.revision += 1
	hired = {revision = state.revision, price = Workers.PRICE}
	profile.progress.firstWorker = hired
	local saved = controller.save(profile, lease)
	if not saved.ok then return {ok = false, code = saved.code} end
	return {ok = true, code = "HIRED", hired = hired}
end

function Workers.assign(controller: Persistence.Controller, ownerUserId: any, expectedRevision: any, lease: number): Result
	local profile, problem = current(controller, ownerUserId, expectedRevision)
	if not profile then return {ok = false, code = problem :: string} end
	local hired = profile.progress.firstWorker
	if not hired then return {ok = false, code = "NOT_HIRED"} end
	if hired.assigned then return {ok = true, code = "ALREADY_ASSIGNED", hired = hired} end
	if profile.state.revision ~= expectedRevision then return {ok = false, code = "STALE_REVISION"} end
	if profile.state.revision == MAX_REVISION then return {ok = false, code = "REVISION_OVERFLOW"} end
	hired.assigned = true
	profile.state.revision += 1
	local saved = controller.save(profile, lease)
	if not saved.ok then return {ok = false, code = saved.code} end
	return {ok = true, code = "ASSIGNED", hired = hired}
end

-- P09-06: after the belt took over the saw leg, the same worker gets the next hand leg, Finish -> Packen.
-- Only an idle worker can change legs: no open claim, nothing carried, no return reservation.
function Workers.reassign(controller: Persistence.Controller, ownerUserId: any, expectedRevision: any, lease: number): Result
	local profile, problem = current(controller, ownerUserId, expectedRevision)
	if not profile then return {ok = false, code = problem :: string} end
	local hired = profile.progress.firstWorker
	if not hired then return {ok = false, code = "NOT_HIRED"} end
	if not hired.assigned then return {ok = false, code = "NOT_ASSIGNED"} end
	if hired.route == "Finish" then return {ok = true, code = "ALREADY_REASSIGNED", hired = hired} end
	local state = profile.state
	if state.revision ~= expectedRevision then return {ok = false, code = "STALE_REVISION"} end
	local carrier = State.FIRST_WORKER.carrier
	for _, claim in state.claims do
		if claim.actorKind == "Worker" then return {ok = false, code = "WORKER_BUSY"} end
	end
	for _, batch in state.batches do
		if batch.locationId == carrier then return {ok = false, code = "WORKER_BUSY"} end
	end
	for _, hold in state.reservations do
		if hold.kind == "Return" and hold.carrierId == carrier then return {ok = false, code = "WORKER_BUSY"} end
	end
	if not profile.progress.firstBelt then return {ok = false, code = "BELT_NOT_INSTALLED"} end
	if state.revision == MAX_REVISION then return {ok = false, code = "REVISION_OVERFLOW"} end
	hired.route = "Finish"
	state.locations[carrier] = State.newLocation(carrier, "Carrier", 1, {State.WORKER_ROUTES.Finish.stage})
	state.revision += 1
	local saved = controller.save(profile, lease)
	if not saved.ok then return {ok = false, code = saved.code} end
	return {ok = true, code = "REASSIGNED", hired = hired}
end

return table.freeze(Workers)
