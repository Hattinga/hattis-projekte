--!strict
-- Run directly in a fresh Play Server. Real transport APIs, marked world endpoints and an isolated RAM backend.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning())
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local Transfers = require(factory.Transfers)
local Recipe = require(factory.Recipe)
local HandMoves = require(factory.HandMoves)
local Persistence = require(factory.Persistence)
local Workers = require(factory.Workers)
local WorkerTransport = require(factory.WorkerTransport)
local Belts = require(factory.Belts)
local BeltTransport = require(factory.BeltTransport)

local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local stations = workspace.P02Line.Stations
local stationBinding = assert(Recipe.bind(stations))
local belt, worker = State.FIRST_BELT, State.FIRST_WORKER
local hand = "Demo.Hand"
local secondSource = "Test.SecondSaw.Output"
local lease = 60
local endpoints = {
	[belt.source] = {point = stationBinding.points[belt.source], stand = stations.Saege.Standpoints.Output},
	[belt.target] = {point = stationBinding.points[belt.target], stand = stations.Montage.Standpoints.Input},
}
local function face(id: string)
	local endpoint = endpoints[id]
	local position = endpoint.stand.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local point = endpoint.point.WorldPosition
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end

local function confirmed(controller: Persistence.Controller): any
	return assert(controller.snapshot().confirmed)
end

local function fixture(secondKit: boolean, finishedStool: boolean)
	local stored: any = nil
	local pauseNextSave = false
	local writes = 0
	local controller = Persistence.new(player.UserId, {
		read = function(): any return stored end,
		update = function(_, transform)
			if pauseNextSave then
				pauseNextSave = false
				task.wait(0.15)
			end
			local proposed = transform(stored)
			if proposed then
				stored = proposed
				writes += 1
			end
			return stored
		end,
	})
	assert(controller.load("P0907", lease, function()
		local state = State.newProfile(player.UserId)
		state.money = 400
		state.locations = table.clone(stationBinding.locations)
		state.locations[hand] = State.newLocation(hand, "Carrier", 1, {"Bausatz"})
		state.batches.Kit = State.newBatch("Kit", player.UserId, "Bausatz", belt.source)
		if secondKit then
			state.locations[secondSource] = State.newLocation(secondSource, "StationOutput", 1, {"Bausatz"})
			state.batches.OtherKit = State.newBatch("OtherKit", player.UserId, "Bausatz", secondSource)
		end
		if finishedStool then
			state.batches.Stool = State.newBatch("Stool", player.UserId, "Fertig", "Finish.Output")
		end
		return {profileVersion = 1, state = state,
			progress = {version = 1, selectedRecipeId = Recipe.id, selectedRecipeVersion = Recipe.version}}
	end).ok)
	assert(Workers.hire(controller, player.UserId, 0, lease).code == "HIRED")
	assert(Workers.assign(controller, player.UserId, 1, lease).code == "ASSIGNED")
	assert(Belts.install(controller, player.UserId, 2, lease).code == "BELT_INSTALLED")
	assert(not confirmed(controller).data.progress.firstBelt.stopped)
	return controller, function() pauseNextSave = true end, function() return writes end
end

local ownerActor = {ready = true, kind = "Player", ownerUserId = player.UserId,
	actorId = "Player/" .. string.format("%.0f", player.UserId), carrierLocationId = hand}
local function manual(controller: Persistence.Controller, location: string, direction: "Take" | "Put", id: string): string
	local snapshot = controller.snapshot()
	if snapshot.status ~= "Confirmed" or snapshot.inFlight then return "NOT_READY" end
	local data = assert(snapshot.confirmed).data
	local store = Transfers.new(data.state)
	local move = HandMoves.interact(store, player, true, hand, endpoints, location, direction, id, os.time(), nil)
	if not move.ok then return move.code end
	data.state = store.profile
	local saved = controller.save(data, lease)
	return if saved.ok then move.code else saved.code
end

local function race(controller: Persistence.Controller, pause: () -> (), writes: () -> number,
	first: () -> string, contenders: {[string]: () -> string}): (string, {[string]: string})
	local start, writeCount = confirmed(controller), writes()
	local outcome: {any}? = nil
	pause()
	task.spawn(function() outcome = table.pack(pcall(first)) end)
	local pending = controller.snapshot()
	assert(pending.inFlight and assert(pending.confirmed).revision == start.revision, "No competing save window")
	local results: {[string]: string} = {}
	for name, move in contenders do
		local code = move()
		assert(code == (if name == "Player" then "NOT_READY" else "NOT_CONFIRMED"), name .. ": " .. code)
		results[name] = code
	end
	assert(writes() == writeCount and confirmed(controller).data.state.revision == start.data.state.revision)
	local deadline = os.clock() + 5
	while not outcome and os.clock() < deadline do task.wait() end
	local settled = assert(outcome, "Save did not finish")
	assert(settled[1], settled[2])
	assert(writes() == writeCount + 1, "Expected one confirmed write")
	return settled[2], results
end

local function checkReplay(state: any, reserveId: string, commitId: string): number
	local store = Transfers.new(state)
	local before = store.profile
	for _, pair in {{reserveId, Transfers.reserve}, {commitId, Transfers.commit}} do
		local receipt = assert(before.receipts[pair[1]])
		local actor = {ready = true, kind = receipt.actorKind, actorId = receipt.actorId,
			ownerUserId = receipt.ownerUserId, carrierLocationId = receipt.carrierId}
		local result = pair[2](store, actor, receipt.request, os.time() + 120, 5)
		for field, value in receipt.result do assert(result[field] == value, field) end
		for field, value in result do assert(receipt.result[field] == value, field) end
		assert(result.ok and store.profile == before)
	end
	return 2
end

local function assertKit(state: any, id: string, location: string)
	local batch = assert(state.batches[id])
	assert(State.validate(state) and state.money == 80)
	assert(batch.ownerUserId == player.UserId and batch.stage == "Bausatz"
		and batch.quantity == 1 and batch.locationId == location and State.countAt(state, location) == 1)
end

local function sourceRace(winner: string): any
	local controller, pause, writes = fixture(false, winner == "Band")
	face(belt.source)
	local moves: {[string]: () -> string} = {
		Player = function() return manual(controller, belt.source, "Take", "player/source") end,
		Worker = function() return WorkerTransport.reserve(controller, "worker/source", os.time(), lease).code end,
		Band = function() return BeltTransport.reserve(controller, belt.source, "belt/source", os.time(), lease).code end,
	}
	local first = assert(moves[winner])
	moves[winner] = nil
	local before = confirmed(controller).data.state
	local code, during = race(controller, pause, writes, first, moves)
	assert(code == (if winner == "Worker" then "RESERVED" else "COMMITTED"), code)
	local afterReserve = confirmed(controller).data.state
	local after: {[string]: string} = {}
	local writeCount = writes()
	for name, move in moves do
		local refused = move()
		assert(refused == (if winner == "Worker" then "SOURCE_RESERVED" elseif name == "Player" then "EMPTY" else "NO_MATERIAL"), refused)
		after[name] = refused
	end
	assert(writes() == writeCount and confirmed(controller).data.state.revision == afterReserve.revision)
	if winner == "Worker" then
		assertKit(afterReserve, "Kit", belt.source)
		local picked = WorkerTransport.take(controller, "worker/source", os.time(), lease)
		assert(picked.ok, picked.code)
	end
	local state = confirmed(controller).data.state
	local carrier = if winner == "Worker" then worker.carrier elseif winner == "Band" then belt.carrier else hand
	assertKit(state, "Kit", carrier)
	assert(state.reservations[belt.source].carrierId == carrier)
	local pickups = 0
	for _, receipt in state.receipts do
		local result = receipt.result
		if receipt.action == "Commit" and result.batchId == "Kit" and result.sourceId == belt.source then pickups += 1 end
	end
	assert(pickups == 1)
	local reserveId = if winner == "Worker" then "worker/source" elseif winner == "Band" then "belt/source" else "player/source/reserve"
	local commitId = if winner == "Worker" then "worker/source/take" elseif winner == "Band" then "belt/source/commit" else "player/source/commit"
	local replays = checkReplay(state, reserveId, commitId)
	local secondLeg: any = nil
	if winner == "Band" then
		local exit = BeltTransport.reserve(controller, belt.carrier, "belt/deliver", os.time(), lease)
		assert(exit.ok and BeltTransport.finish(controller, assert(exit.claimId), os.time(), lease, true).ok)
		local ready = confirmed(controller).data.state
		assertKit(ready, "Kit", belt.target)
		assert(Workers.reassign(controller, player.UserId, ready.revision, lease).code == "REASSIGNED")
		local fetch = WorkerTransport.reserve(controller, "worker/finish", os.time(), lease)
		assert(fetch.ok and fetch.batchId == "Stool")
		local picked = WorkerTransport.take(controller, assert(fetch.claimId), os.time(), lease)
		assert(picked.ok and WorkerTransport.put(controller, assert(picked.claimId), os.time(), lease).ok)
		local moved = confirmed(controller).data.state
		assert(moved.batches.Stool.locationId == "Packen.Input" and moved.batches.Stool.quantity == 1)
		assert(State.validate(moved) and moved.money == 80 and next(moved.claims) == nil and next(moved.reservations) == nil)
		secondLeg = {route = "Finish", batch = "Stool", location = "Packen.Input", revision = moved.revision}
	end
	return {winner = winner, during = during, after = after, startRevision = before.revision,
		reservedRevision = afterReserve.revision, pickupRevision = state.revision, lot = "Kit", location = carrier,
		pickups = pickups, replays = replays, money = state.money, secondLeg = secondLeg}
end

local function targetRace(): any
	local controller, pause, writes = fixture(true, false)
	assert(BeltTransport.reserve(controller, belt.source, "target/buffer", os.time(), lease).ok)
	local data = confirmed(controller).data
	local store = Transfers.new(data.state)
	-- Seed a second kit from a separate artificial output. The disputed input is the actual Montage.Input.
	assert(Transfers.reserve(store, ownerActor, {operationId = "target/hand", expectedRevision = store.profile.revision,
		batchId = "OtherKit", sourceId = secondSource, targetId = hand, quantity = 1}, os.time(), 5).ok)
	assert(Transfers.commit(store, ownerActor, {operationId = "target/hand/commit", expectedRevision = store.profile.revision,
		claimId = "target/hand"}, os.time()).ok)
	data.state = store.profile
	assert(controller.save(data, lease).ok)
	face(belt.target)
	local before = confirmed(controller).data.state
	local function playerPut(): string return manual(controller, belt.target, "Put", "target/player") end
	local code, during = race(controller, pause, writes, function()
		return BeltTransport.reserve(controller, belt.carrier, "target/belt", os.time(), lease).code
	end, {Player = playerPut})
	assert(code == "RESERVED", code)
	local after = playerPut()
	assert(after == "TARGET_RESERVED", after)
	assert(BeltTransport.finish(controller, "target/belt", os.time(), lease, true).ok)
	local full = playerPut()
	assert(full == "TARGET_FULL", full)
	local done = confirmed(controller).data.state
	assertKit(done, "Kit", belt.target)
	assertKit(done, "OtherKit", hand)
	assert(next(done.claims) == nil and done.reservations[secondSource].batchId == "OtherKit"
		and done.reservations[secondSource].carrierId == hand and done.reservations[belt.source] == nil)
	assert(done.revision == before.revision + 2 and writes() == 8)
	return {during = during.Player, after = after, full = full, startRevision = before.revision,
		endRevision = done.revision, target = done.batches.Kit.locationId, other = done.batches.OtherKit.locationId,
		money = done.money, replays = checkReplay(done, "target/belt", "target/belt/commit")}
end

root.Anchored = true
local ok, report = pcall(function()
	return {sources = {sourceRace("Player"), sourceRace("Worker"), sourceRace("Band")}, target = targetRace()}
end)
root.CFrame, root.Anchored = original, anchored
assert(ok, report)
return report
