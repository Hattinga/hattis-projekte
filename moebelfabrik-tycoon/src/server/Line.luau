--!strict
-- P05-08: continuous station operation on the confirmed inventory. No automatic transport between stations.
local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)
local Stations = require(script.Parent.Stations)
local Line = {}

export type Event = {stationId: string, code: string, ok: boolean, unknown: boolean, batchId: string?}
-- RUNNING > OUTPUT_FULL > OUTPUT_RESERVED > READY > INPUT_MISSING (PRODUCTION "Stoppfälle").
-- BACKLOG (P09-05) replaces OUTPUT_RESERVED while the first belt holds this station's output and cannot move on.
export type Status = {stationId: string, code: string, inputStage: State.Stage, outputStage: State.Stage,
	remaining: number?, batchId: string?, inputWaiting: boolean, cause: string?}
export type StoreStatus = {used: number, capacity: number, full: boolean}
export type BeltStatus = {code: string, cause: string?, batchId: string?}

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

-- P09-05: why the first belt cannot move its kit on: "stopped" (switched off) or "assembly" (the target is taken by
-- stock, a reservation or another actor's open claim). nil while the belt has an open claim of its own or is free to go.
local function beltCause(state: State.Profile, now: number, stopped: boolean): string?
	local belt = State.FIRST_BELT
	if stopped then return "stopped" end
	for _, claim in state.claims do
		if claim.actorKind == "Band" and claim.actorId == belt.carrier and claim.expiresAt > now then return nil end
	end
	if State.countAt(state, belt.target) ~= 0 or state.reservations[belt.target] then return "assembly" end
	for _, claim in state.claims do
		if claim.expiresAt > now and State.claimTouches(claim, belt.target) then return "assembly" end
	end
	return nil
end

-- Read-only belt feedback for its sign; never changes stock.
function Line.beltStatus(state: State.Profile, now: number, stopped: boolean): BeltStatus
	local belt = State.FIRST_BELT
	local onBelt: string? = nil
	local waiting: string? = nil
	for id, batch in state.batches do
		if batch.locationId == belt.carrier then
			onBelt = id
		elseif batch.locationId == belt.source and batch.stage == belt.stage then
			waiting = id
		end
	end
	if stopped then return {code = "STOPPED", cause = "stopped", batchId = onBelt or waiting} end
	if onBelt then
		local cause = beltCause(state, now, false)
		if cause then return {code = "BACKLOG", cause = cause, batchId = onBelt} end
		return {code = "RUNNING", batchId = onBelt}
	end
	if waiting then return {code = "RUNNING", batchId = waiting} end
	return {code = "IDLE"}
end

-- Read-only station feedback for signs and HUD; never changes stock. `beltStopped` marks the first belt as switched off.
function Line.status(state: State.Profile, now: number, beltStopped: boolean?): {[string]: Status}
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
			local carried = state.batches[lock.batchId]
			if rule.output == State.FIRST_BELT.source and lock.kind == "Return" and lock.carrierId == State.FIRST_BELT.carrier
				and carried and carried.locationId == State.FIRST_BELT.carrier then
				local cause = beltCause(state, now, beltStopped == true)
				if cause then status.code, status.cause = "BACKLOG", cause end
			end
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
