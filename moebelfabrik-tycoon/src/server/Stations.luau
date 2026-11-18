--!strict
-- P05-04/P05-05: one station run = confirmed input, persisted output reservation, one completed batch.
local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)
local Stations = {}
local MAX_INTEGER = 9007199254740991

export type Result = {ok: boolean, code: string, unknown: boolean, batchId: string?, finishAt: number?}

local function reject(code: string, unknown: boolean?): Result
	return {ok = false, code = code, unknown = unknown == true}
end

local function validTime(now: number): boolean
	return now >= 0 and now <= MAX_INTEGER and now % 1 == 0
end

-- Returns a detached copy of the confirmed save, or a rejection while a save is open or unclear.
local function confirmedCopy(controller: Persistence.Controller): (any?, Result?)
	local snapshot = controller.snapshot()
	local confirmed = snapshot.confirmed
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not confirmed then
		return nil, reject("NOT_CONFIRMED", snapshot.unknown)
	end
	return confirmed.data, nil
end

function Stations.start(controller: Persistence.Controller, stationId: string, now: number, ttlSeconds: number): Result
	local rule = State.STATION_BY_ID[stationId]
	if not rule then return reject("UNKNOWN_STATION") end
	if not validTime(now) or now > MAX_INTEGER - rule.durationSeconds then return reject("INVALID_TIME") end
	local candidate, problem = confirmedCopy(controller)
	if not candidate then return assert(problem) end
	local state = candidate.state
	local input, process, output = state.locations[rule.input], state.locations[rule.process], state.locations[rule.output]
	if not input or input.kind ~= "StationInput" or not process or process.kind ~= "StationProcess"
		or not output or output.kind ~= "StationOutput"
		or not table.find(process.acceptedStages, rule.inputStage) or not table.find(output.acceptedStages, rule.outputStage) then
		return reject("STATION_UNAVAILABLE")
	end
	local lock = state.reservations[rule.output]
	if lock and lock.kind == "Production" then return reject("ALREADY_RUNNING") end
	if lock or State.countAt(state, rule.output) ~= 0 then return reject("OUTPUT_BLOCKED") end
	if State.countAt(state, rule.process) ~= 0 or state.reservations[rule.process] then return reject("PROCESS_BLOCKED") end
	local inputBatch: State.Batch? = nil
	for _, batch in state.batches do
		if batch.locationId == rule.input then inputBatch = batch; break end
	end
	if not inputBatch or inputBatch.stage ~= rule.inputStage then return reject("INPUT_REQUIRED") end
	if state.revision >= MAX_INTEGER - 1 then return reject("REVISION_OVERFLOW") end
	for id, claim in state.claims do
		if claim.sourceId == rule.input or claim.targetId == rule.input
			or claim.sourceId == rule.output or claim.targetId == rule.output then
			if claim.expiresAt > now then return reject("SLOT_RESERVED") end
			state.claims[id] = nil
		end
	end
	local finishAt = now + rule.durationSeconds
	inputBatch.locationId = rule.process
	state.reservations[rule.output] = {kind = "Production", batchId = inputBatch.id, finishAt = finishAt}
	state.revision += 1
	local saved = controller.save(candidate, ttlSeconds)
	if not saved.ok then return reject(saved.code, saved.unknown) end
	return {ok = true, code = "STARTED", unknown = false, batchId = inputBatch.id, finishAt = finishAt}
end

function Stations.finish(controller: Persistence.Controller, stationId: string, batchId: string, now: number,
	ttlSeconds: number): Result
	local rule = State.STATION_BY_ID[stationId]
	if not rule then return reject("UNKNOWN_STATION") end
	if not validTime(now) then return reject("INVALID_TIME") end
	local candidate, problem = confirmedCopy(controller)
	if not candidate then return assert(problem) end
	local state = candidate.state
	local lock = state.reservations[rule.output]
	if not lock or lock.kind ~= "Production" then return reject("NO_ACTIVE_RUN") end
	if lock.batchId ~= batchId then return reject("STALE_RUN") end
	if now < lock.finishAt then return reject("RUNNING") end
	if state.revision == MAX_INTEGER then return reject("REVISION_OVERFLOW") end
	local batch = state.batches[batchId]
	batch.locationId, batch.stage = rule.output, rule.outputStage
	state.reservations[rule.output] = nil
	state.revision += 1
	local saved = controller.save(candidate, ttlSeconds)
	if not saved.ok then return reject(saved.code, saved.unknown) end
	return {ok = true, code = "FINISHED", unknown = false, batchId = batchId}
end

return table.freeze(Stations)
