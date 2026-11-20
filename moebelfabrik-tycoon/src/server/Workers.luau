--!strict
-- P08-01: the first worker is a permanent entitlement of one workshop.
local Persistence = require(script.Parent.Persistence)
local Profiles = require(script.Parent.Profiles)

type Result = {ok: boolean, code: string, hired: Profiles.WorkerHire?}

local Workers = {}
Workers.PRICE = 120
local MAX_REVISION = 9007199254740991

function Workers.hire(controller: Persistence.Controller, ownerUserId: any, expectedRevision: any, lease: number): Result
	local snapshot = controller.snapshot()
	local confirmed = snapshot.confirmed
	if not confirmed or snapshot.inFlight or snapshot.status ~= "Confirmed" then
		return {ok = false, code = "NOT_CONFIRMED"}
	end
	local profile = confirmed.data
	local state = profile.state
	if state.ownerUserId ~= ownerUserId then return {ok = false, code = "NOT_AUTHORIZED"} end
	if type(expectedRevision) ~= "number" or expectedRevision % 1 ~= 0
		or expectedRevision < 0 or expectedRevision > MAX_REVISION then
		return {ok = false, code = "INVALID_REQUEST"}
	end
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

return table.freeze(Workers)
