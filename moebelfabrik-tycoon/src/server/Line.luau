--!strict
-- P05-08: continuous station operation on the confirmed inventory. No automatic transport between stations.
local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)
local Stations = require(script.Parent.Stations)
local Line = {}

export type Event = {stationId: string, code: string, ok: boolean, unknown: boolean, batchId: string?}
-- RUNNING > OUTPUT_FULL > OUTPUT_RESERVED > READY > INPUT_MISSING (PRODUCTION "Stoppfälle").
export type Status = {stationId: string, code: string, inputStage: State.Stage, outputStage: State.Stage,
	remaining: number?, batchId: string?, inputWaiting: boolean}
export type StoreStatus = {used: number, capacity: number, full: boolean}

local function confirmedState(controller: Persistence.Controller): any?
	local snapshot = controller.snapshot()
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not snapshot.confirmed then return nil end
	return snapshot.confirmed.data.state
end

-- One pass: finish every due run, then start every station whose input, process and output allow it.
-- Each change is its own confirmed save; an unconfirmed or unclear save stops the pass.
function Line.tick(controller: Persistence.Controller, now: number, ttlSeconds: number): {Event}
	local events: {Event} = {}
	local state = confirmedState(controller)
	if not state then
		table.insert(events, {stationId = "", code = "NOT_CONFIRMED", ok = false, unknown = controller.snapshot().unknown})
		return events
	end
	for _, rule in State.STATIONS do
		local lock = state.reservations[rule.output]
		if lock and lock.kind == "Production" and now >= lock.finishAt then
			local result = Stations.finish(controller, rule.id, lock.batchId, now, ttlSeconds)
			table.insert(events, {stationId = rule.id, code = result.code, ok = result.ok, unknown = result.unknown,
				batchId = lock.batchId})
			if not result.ok then return events end
		end
	end
	for _, rule in State.STATIONS do
		local result = Stations.start(controller, rule.id, now, ttlSeconds)
		if result.ok or result.unknown or result.code == "NOT_CONFIRMED" then
			table.insert(events, {stationId = rule.id, code = result.code, ok = result.ok, unknown = result.unknown,
				batchId = result.batchId})
			if not result.ok then return events end
		end
	end
	return events
end

-- Read-only station feedback for signs and HUD; never changes stock.
function Line.status(state: State.Profile, now: number): {[string]: Status}
	local result: {[string]: Status} = {}
	for _, rule in State.STATIONS do
		local inputBatch: State.Batch? = nil
		local outputBatch: State.Batch? = nil
		for _, batch in state.batches do
			if batch.locationId == rule.input then inputBatch = batch end
			if batch.locationId == rule.output then outputBatch = batch end
		end
		local waiting = inputBatch ~= nil and inputBatch.stage == rule.inputStage
		local lock = state.reservations[rule.output]
		local status: Status = {stationId = rule.id, code = "INPUT_MISSING", inputStage = rule.inputStage,
			outputStage = rule.outputStage, inputWaiting = waiting}
		if lock and lock.kind == "Production" then
			status.code, status.batchId = "RUNNING", lock.batchId
			status.remaining = math.max(0, lock.finishAt - now)
		elseif outputBatch then
			status.code, status.batchId = "OUTPUT_FULL", outputBatch.id
		elseif lock then
			status.code, status.batchId = "OUTPUT_RESERVED", lock.batchId
		elseif waiting then
			status.code = "READY"
		end
		result[rule.id] = status
	end
	return result
end

function Line.storeStatus(state: State.Profile, slotIds: {string}): StoreStatus
	local used = 0
	for _, id in slotIds do
		if State.countAt(state, id) > 0 or state.reservations[id] then used += 1 end
	end
	return {used = used, capacity = #slotIds, full = used >= #slotIds}
end

return table.freeze(Line)
