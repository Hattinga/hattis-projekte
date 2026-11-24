--!strict
-- P09-06: the worker whose saw leg the belt took over gets the Finish -> Packen leg.
-- Every server: P06LoadingDemo and P0906Funds (400 play money: hire 120 + belt 200), then ToolRun.LineDemo, then this probe.
-- full (in memory): also P0803WorkerStock and P0906FinishStock. Worker busy, belt missing, reassignment, repeat, delivery.
-- leave/return (the same fresh P0607ResumeScope in two servers): set P0906FinishStock and P0906PackenFull in the
--   first server only. leave: reassign while the packing input is taken, then release. return: the worker is restored on
--   the Finish leg and waits; free the packing output by hand; the worker delivers.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local phase = workspace:GetAttribute("P0906Case")
assert(phase == "full" or phase == "leave" or phase == "return")
assert((workspace:GetAttribute("P0607ResumeScope") ~= nil) == (phase ~= "full"))
local state = storage:WaitForChild("P0509LineState", 10) :: BindableFunction
local hire = storage.P0801Hire :: BindableFunction
local assign = storage.P0802Assign :: BindableFunction
local install = storage.P0901Belt :: BindableFunction
local reassign = storage.P0906Reassign :: BindableFunction
local hand = storage.P0509LineTest :: BindableFunction
local line = workspace.P02Line
local stations = line.Stations
local store = line.Stores.Fertiglager
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local function face(pad: Instance, stand: BasePart)
	local position = stand.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local point = (pad:FindFirstChild("Transfer") :: Attachment).WorldPosition
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
local function park()
	-- The two legs share their standpoints. Keep the test avatar out of the worker's aisle between actions.
	root.CFrame = original + Vector3.new(0, 15, 0)
end
local function await(label: string, predicate: (any) -> boolean, seconds: number?): any
	local expires = os.clock() + (seconds or 25)
	repeat
		local snapshot = state:Invoke()
		assert(snapshot.valid, "State became invalid")
		if predicate(snapshot) then return snapshot end
		task.wait(0.05)
	until os.clock() >= expires
	local last = state:Invoke()
	error(string.format("%s timed out, worker %s on %s, route %s", label, tostring(last.workerStatus), tostring(last.workerLeg),
		tostring(last.firstWorker and last.firstWorker.route)))
end
local function workerClaim(s: any): boolean
	for _, claim in s.claims do
		if claim.actorKind == "Worker" then return true end
	end
	return false
end
local function idle(s: any): boolean
	if workerClaim(s) then return false end
	for _, reservation in s.reservations do
		if reservation.kind == "Return" and reservation.carrierId == "Worker.First" then return false end
	end
	for _, batch in s.batches do
		if batch.locationId == "Worker.First" then return false end
	end
	return true
end
local function delivered(s: any, batchId: string, targetId: string): any
	for _, receipt in s.workerReceipts do
		if receipt.batchId == batchId and receipt.targetId == targetId then return receipt end
	end
	return nil
end

root.Anchored = true
local ok, report = pcall(function()
	local result: any = {phase = phase}
	if phase ~= "return" then
		face(store.Slot2, store.Standpoints.Slot2)
		assert(hire:Invoke().code == "HIRED")
		face(stations.Saege.Output, stations.Saege.Standpoints.Output)
		assert(assign:Invoke().code == "ASSIGNED")
	end
	park()
	if phase == "full" then
		-- The worker takes the saw leg first. A reassignment while it works is refused and changes nothing.
		await("worker carrying on the saw leg", function(s)
			return workerClaim(s) and s.batches.Testbausatz.locationId == "Worker.First"
		end)
		face(stations.Finish.Output, stations.Finish.Standpoints.Output)
		local busy = reassign:Invoke()
		park()
		assert(busy.code == "WORKER_BUSY" and not busy.ok, "Busy worker was reassigned: " .. tostring(busy.code))
		local still = state:Invoke()
		assert(still.firstWorker.route == nil and still.workerLeg == "Saw" and still.workerLocation.acceptedStages[1] == "Bausatz")
		await("saw leg delivered", function(s) return delivered(s, "Testbausatz", "Montage.Input") ~= nil end, 60)
		local free = await("worker idle", idle)
		result.busyRevision = still.revision
		-- Without the belt the saw leg is still the worker's.
		face(stations.Finish.Output, stations.Finish.Standpoints.Output)
		local early = reassign:Invoke()
		assert(early.code == "BELT_NOT_INSTALLED" and not early.ok, "Reassigned without a belt: " .. tostring(early.code))
		assert(state:Invoke().firstWorker.route == nil)
		face(stations.Saege.Output, stations.Saege.Standpoints.Output)
		assert(install:Invoke().code == "BELT_INSTALLED")
		await("worker idle after the belt", idle)
		face(stations.Finish.Output, stations.Finish.Standpoints.Output)
		local before = state:Invoke()
		local moved = reassign:Invoke()
		assert(moved.code == "REASSIGNED" and moved.ok, "Reassignment failed: " .. tostring(moved.code))
		local after = state:Invoke()
		assert(after.firstWorker.route == "Finish" and after.workerLocation.acceptedStages[1] == "Fertig"
			and #after.workerLocation.acceptedStages == 1, "Reassignment not stored")
		assert(after.money == before.money and after.valid and after.revision > before.revision)
		local again = reassign:Invoke()
		park()
		assert(again.code == "ALREADY_REASSIGNED" and again.ok)
		-- The worker now carries the finished stool from the finishing output to the packing input.
		local done = await("second leg delivered", function(s) return delivered(s, "TestFertig", "Packen.Input") ~= nil end, 90)
		assert(done.workerLeg == "Finish", "Worker did not rebind: " .. tostring(done.workerLeg))
		local pickup = delivered(done, "TestFertig", "Worker.First")
		assert(pickup and pickup.sourceId == "Finish.Output", "No pickup at the finishing output")
		local puts, picks = 0, 0
		for _, receipt in done.workerReceipts do
			if receipt.batchId == "TestFertig" and receipt.targetId == "Packen.Input" then puts += 1 end
			if receipt.batchId == "TestFertig" and receipt.targetId == "Worker.First" then picks += 1 end
		end
		assert(puts == 1 and picks == 1, "Expected one pickup and one delivery")
		local final = await("worker idle on the second leg", idle)
		assert(next(final.claims) == nil or not workerClaim(final))
		assert(final.money == 80 and final.valid)
		result.moved = {revisionBefore = before.revision, revisionAfter = after.revision, money = final.money,
			receipts = {pickup = pickup, put = delivered(final, "TestFertig", "Packen.Input")}, free = free.revision}
		return result
	elseif phase == "leave" then
		face(stations.Saege.Output, stations.Saege.Standpoints.Output)
		assert(install:Invoke().code == "BELT_INSTALLED")
		await("worker idle after the belt", idle)
		face(stations.Finish.Output, stations.Finish.Standpoints.Output)
		assert(reassign:Invoke().code == "REASSIGNED")
		park()
		local waiting = await("second leg waits for the packing input", function(s)
			return s.workerLeg == "Finish" and s.workerStatus == "Packtisch-Eingang belegt" and not workerClaim(s)
				and s.batches.TestFertig.locationId == "Finish.Output" and s.batches.TestPackenInput.locationId == "Packen.Input"
		end)
		assert(waiting.money == 80 and idle(waiting))
		assert((storage.P0607Release :: BindableFunction):Invoke().ok)
		result.revision, result.money, result.route = waiting.revision, waiting.money, waiting.firstWorker.route
		return result
	end
	-- return: the new server restores the worker on the Finish leg; it waits until the packing output is cleared.
	local restored = await("worker restored on the second leg", function(s)
		return s.workerLeg == "Finish" and s.workerStatus == "Packtisch-Eingang belegt"
	end)
	assert(restored.firstWorker.route == "Finish" and restored.workerLocation.acceptedStages[1] == "Fertig")
	assert(restored.batches.TestFertig.locationId == "Finish.Output" and idle(restored))
	assert(restored.money == 80)
	local factory = game:GetService("ServerScriptService").Factory
	local rest = require(factory.WorkerRoute).bind(stations, "Finish").rest
	local worker = assert(workspace.P0509LineDemo:FindFirstChild("Werkstattmitarbeiter")) :: Model
	local restDistance = ((worker:GetPivot().Position - rest) * Vector3.new(1, 0, 1)).Magnitude
	assert(restDistance <= 1.05, "Restored worker is away from the Finish rest point")
	face(stations.Packen.Output, stations.Packen.Standpoints.Output)
	assert(hand:Invoke("Packen.Output", "Take").result.ok)
	face(store.Slot1, store.Standpoints.Slot1)
	assert(hand:Invoke("FinishedStore.Slot1", "Put").result.ok)
	park()
	local done = await("second leg delivered after the rejoin", function(s)
		return delivered(s, "TestFertig", "Packen.Input") ~= nil
	end, 90)
	local puts = 0
	for _, receipt in done.workerReceipts do
		if receipt.batchId == "TestFertig" and receipt.targetId == "Packen.Input" then puts += 1 end
	end
	assert(puts == 1 and done.money == 80 and done.valid)
	assert((storage.P0607Release :: BindableFunction):Invoke().ok)
	result.revision, result.money, result.route = done.revision, done.money, done.firstWorker.route
	result.restoredRevision, result.restDistance = restored.revision, restDistance
	return result
end)
root.CFrame, root.Anchored = original, anchored
assert(ok, report)
return report
