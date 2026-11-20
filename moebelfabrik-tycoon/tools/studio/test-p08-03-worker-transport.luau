--!strict
-- Play Server with P06LoadingDemo and P0803WorkerStock set before requiring LineDemo.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and RunService:IsServer() and RunService:IsRunning())
assert(workspace:GetAttribute("P0607ResumeScope") == nil)
local storage = game:GetService("ServerStorage")
local state = storage.P0509LineState :: BindableFunction
local hire = storage.P0801Hire :: BindableFunction
local assign = storage.P0802Assign :: BindableFunction
local hand = storage.P0509LineTest :: BindableFunction
local factory = game:GetService("ServerScriptService").Factory
local route = require(factory.State).FIRST_WORKER
local binding = require(factory.WorkerRoute).bind(workspace.P02Line.Stations)
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local stock = "Testbausatz"
local function face(stand: Vector3, point: Vector3)
	local position = stand + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
local function park()
	root.CFrame = original + Vector3.new(0, 15, 0)
end
local function awaitState(label: string, predicate: (any) -> boolean): any
	local expires = os.clock() + 10
	repeat
		local snapshot = state:Invoke()
		assert(snapshot.valid and snapshot.batches[stock], "Lost the batch")
		if predicate(snapshot) then return snapshot end
		task.wait(0.04)
	until os.clock() >= expires
	local last = state:Invoke()
	error(string.format("%s timed out, worker %s batch %s", label, tostring(last.workerStatus), last.batches[stock].locationId))
end
root.Anchored = true
local ok, report = pcall(function()
	assert(state:Invoke().batches[stock].locationId == route.source)
	local shelf = workspace.P02Line.Stores.Fertiglager
	face(shelf.Standpoints.Slot2.Position, shelf.Slot2.Transfer.WorldPosition)
	assert(hire:Invoke().code == "HIRED")
	face(binding.source.stand.Position, binding.source.point.WorldPosition)
	assert(assign:Invoke().code == "ASSIGNED")
	park()
	local reserved = awaitState("reservation", function(snapshot)
		for _, claim in snapshot.claims do
			if claim.nextTargetId == route.target and claim.batchId == stock then return true end
		end
		return false
	end)
	assert(reserved.batches[stock].locationId == route.source and reserved.workerStatus == "Zur Säge unterwegs")
	face(binding.source.stand.Position, binding.source.point.WorldPosition)
	local competing = hand:Invoke(route.source, "Take")
	park()
	assert(not competing.result.ok and competing.result.code == "SOURCE_RESERVED", competing.result.code)
	local carried = awaitState("pickup", function(snapshot)
		local view = snapshot.views[stock]
		return snapshot.batches[stock].locationId == route.carrier and view and view.carried
	end)
	assert(carried.reservations[route.source].kind == "Return")
	local destinationLocked = false
	for _, claim in carried.claims do
		if claim.sourceId == route.carrier and claim.targetId == route.target and claim.batchId == stock then
			destinationLocked = true
		end
	end
	assert(destinationLocked and carried.workerStatus == "Zur Montage unterwegs")
	local delivered = awaitState("delivery", function(snapshot)
		local count = 0
		for _, receipt in snapshot.workerReceipts do
			if receipt.batchId == stock and receipt.targetId == route.target then count += 1 end
		end
		return count == 1
	end)
	assert(next(delivered.claims) == nil and delivered.reservations[route.source] == nil)
	assert(delivered.money == 60 and delivered.batches[stock].locationId ~= route.carrier)
	return {status = "passed", money = delivered.money, revision = delivered.revision,
		manual = competing.result.code, receipts = delivered.workerReceipts, batchLocation = delivered.batches[stock].locationId}
end)
root.CFrame, root.Anchored = original, anchored
assert(ok, report)
return report
