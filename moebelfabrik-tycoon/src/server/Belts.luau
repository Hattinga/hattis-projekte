--!strict
-- P09-01: a confirmed unlock for the first fixed conveyor section.
local Persistence = require(script.Parent.Persistence)
local State = require(script.Parent.State)

local Belts = {}
Belts.PRICE = 200
local MAX_REVISION = 9007199254740991

function Belts.install(controller: Persistence.Controller, userId: number, revision: number, lease: number): {ok: boolean, code: string}
	local snapshot = controller.snapshot()
	local saved = snapshot.confirmed
	if not saved or snapshot.status ~= "Confirmed" or snapshot.inFlight then return {ok = false, code = "NOT_CONFIRMED"} end
	local profile = saved.data
	local state = profile.state
	if state.ownerUserId ~= userId then return {ok = false, code = "NOT_AUTHORIZED"} end
	if profile.progress.firstBelt then return {ok = true, code = "BELT_OWNED"} end
	if state.revision ~= revision then return {ok = false, code = "STALE_REVISION"} end
	if state.revision == MAX_REVISION then return {ok = false, code = "REVISION_OVERFLOW"} end
	if state.money < Belts.PRICE then return {ok = false, code = "NOT_ENOUGH_FOR_BELT"} end
	state.money -= Belts.PRICE
	state.revision += 1
	state.locations[State.FIRST_BELT.carrier] = State.newLocation(State.FIRST_BELT.carrier, "Band", 1, {State.FIRST_BELT.stage})
	profile.progress.firstBelt = {revision = state.revision, price = Belts.PRICE,
		sourceId = State.FIRST_BELT.source, targetId = State.FIRST_BELT.target}
	local result = controller.save(profile, lease)
	return {ok = result.ok, code = if result.ok then "BELT_INSTALLED" else result.code}
end

function Belts.toggle(controller: Persistence.Controller, userId: number, revision: number, lease: number): {ok: boolean, code: string}
	local snapshot = controller.snapshot()
	local saved = snapshot.confirmed
	if not saved or snapshot.status ~= "Confirmed" or snapshot.inFlight then return {ok = false, code = "NOT_CONFIRMED"} end
	local profile = saved.data
	local state = profile.state
	if state.ownerUserId ~= userId then return {ok = false, code = "NOT_AUTHORIZED"} end
	local belt = profile.progress.firstBelt
	if not belt then return {ok = false, code = "BELT_NOT_INSTALLED"} end
	if state.revision ~= revision then return {ok = false, code = "STALE_REVISION"} end
	if state.revision == MAX_REVISION then return {ok = false, code = "REVISION_OVERFLOW"} end
	belt.stopped = if belt.stopped then nil else true
	state.revision += 1
	local result = controller.save(profile, lease)
	return {ok = result.ok, code = if not result.ok then result.code elseif belt.stopped then "BELT_STOPPED" else "BELT_RUNNING"}
end

return table.freeze(Belts)
