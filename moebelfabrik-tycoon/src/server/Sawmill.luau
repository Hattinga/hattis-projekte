--!strict
-- P05-04: a confirmed input, a persisted output reservation, and one completed batch.
local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)
local saw = State.SAW
local Sawmill = {}
local MAX_INTEGER = 9007199254740991

export type Result = {ok: boolean, code: string, unknown: boolean, batchId: string?, finishAt: number?}

local function reject(code: string, unknown: boolean?): Result
	return {ok = false, code = code, unknown = unknown == true}
end

local function validTime(now: number): boolean
	return now >= 0 and now <= MAX_INTEGER and now % 1 == 0
end

function Sawmill.start(controller: Persistence.Controller, now: number, ttlSeconds: number): Result
	if not validTime(now) or now > MAX_INTEGER - saw.durationSeconds then return reject("INVALID_TIME") end
	local snapshot = controller.snapshot()
	local confirmed = snapshot.confirmed
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not confirmed then
		return reject("NOT_CONFIRMED", snapshot.unknown)
	end
	local candidate = confirmed.data -- detached from the controller
	local state = candidate.state
	local input, process, output = state.locations[saw.input], state.locations[saw.process], state.locations[saw.output]
	if not input or input.kind ~= "StationInput" or not process or process.kind ~= "StationProcess"
		or not output or output.kind ~= "StationOutput"
		or not table.find(process.acceptedStages, saw.inputStage) or not table.find(output.acceptedStages, saw.outputStage) then
		return reject("STATION_UNAVAILABLE")
	end
	local lock = state.reservations[saw.output]
	if lock and lock.kind == "Production" then return reject("ALREADY_RUNNING") end
	if lock or State.countAt(state, saw.output) ~= 0 then return reject("OUTPUT_BLOCKED") end
	if State.countAt(state, saw.process) ~= 0 or state.reservations[saw.process] then return reject("PROCESS_BLOCKED") end
	local inputBatch: State.Batch? = nil
	for _, batch in state.batches do
		if batch.locationId == saw.input then inputBatch = batch; break end
	end
	if not inputBatch or inputBatch.stage ~= saw.inputStage then return reject("INPUT_REQUIRED") end
	if state.revision >= MAX_INTEGER - 1 then return reject("REVISION_OVERFLOW") end
	for id, claim in state.claims do
		if claim.sourceId == saw.input or claim.targetId == saw.input or claim.sourceId == saw.output or claim.targetId == saw.output then
			if claim.expiresAt > now then return reject("SLOT_RESERVED") end
			state.claims[id] = nil
		end
	end
	local finishAt = now + saw.durationSeconds
	inputBatch.locationId = saw.process
	state.reservations[saw.output] = {kind = "Production", batchId = inputBatch.id, finishAt = finishAt}
	state.revision += 1
	local saved = controller.save(candidate, ttlSeconds)
	if not saved.ok then return reject(saved.code, saved.unknown) end
	return {ok = true, code = "STARTED", unknown = false, batchId = inputBatch.id, finishAt = finishAt}
end

function Sawmill.finish(controller: Persistence.Controller, batchId: string, now: number, ttlSeconds: number): Result
	if not validTime(now) then return reject("INVALID_TIME") end
	local snapshot = controller.snapshot()
	local confirmed = snapshot.confirmed
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not confirmed then
		return reject("NOT_CONFIRMED", snapshot.unknown)
	end
	local candidate = confirmed.data
	local state = candidate.state
	local lock = state.reservations[saw.output]
	if not lock or lock.kind ~= "Production" then return reject("NO_ACTIVE_RUN") end
	if lock.batchId ~= batchId then return reject("STALE_RUN") end
	if now < lock.finishAt then return reject("RUNNING") end
	if state.revision == MAX_INTEGER then return reject("REVISION_OVERFLOW") end
	local batch = state.batches[batchId]
	batch.locationId, batch.stage = saw.output, saw.outputStage
	state.reservations[saw.output] = nil
	state.revision += 1
	local saved = controller.save(candidate, ttlSeconds)
	if not saved.ok then return reject(saved.code, saved.unknown) end
	return {ok = true, code = "FINISHED", unknown = false, batchId = batchId}
end

return table.freeze(Sawmill)
