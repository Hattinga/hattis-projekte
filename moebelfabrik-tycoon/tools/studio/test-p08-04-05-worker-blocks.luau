--!strict
-- Fresh logistics Play Server. P0805Case="before", "after", "trapped", "full", or "empty".
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local state = storage.P0509LineState :: BindableFunction
local hire = storage.P0801Hire :: BindableFunction
local assign = storage.P0802Assign :: BindableFunction
local hand = storage.P0509LineTest :: BindableFunction
local factory = game:GetService("ServerScriptService").Factory
local route = require(factory.State).FIRST_WORKER
local line = workspace.P02Line
local binding = require(factory.WorkerRoute).bind(line.Stations)
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local testCase = workspace:GetAttribute("P0805Case")
assert(testCase == "before" or testCase == "after" or testCase == "trapped" or testCase == "full" or testCase == "empty")
local stock = "Testbausatz"
local blocks: {BasePart} = {}
local function block(x: number, z: number, width: number)
	local obstruction = Instance.new("Part")
	obstruction.Name = "P0805TestBlock"
	obstruction.Anchored = true
	obstruction.Size = Vector3.new(width, 3.5, 2)
	obstruction.Position = Vector3.new(x, 2.8, z)
	obstruction.Parent = workspace
	table.insert(blocks, obstruction)
end
local function face(stand: Vector3, point: Vector3)
	local position = stand + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
local function park()
	root.CFrame = original + Vector3.new(0, 15, 0)
end
local function await(label: string, predicate: (any) -> boolean): any
	local expires = os.clock() + 16
	repeat
		local snapshot = state:Invoke()
		assert(snapshot.valid)
		if predicate(snapshot) then return snapshot end
		task.wait(0.04)
	until os.clock() >= expires
	local last = state:Invoke()
	error(string.format("%s timed out, worker %s batch %s", label, tostring(last.workerStatus),
		if last.batches[stock] then last.batches[stock].locationId else "none"))
end
local source = binding.source.stand.Position
root.Anchored = true
local ok, report = pcall(function()
	if testCase == "before" then block(source.X - 4, source.Z, 1.6) end
	if testCase == "after" or testCase == "trapped" then block(source.X + 2.5, source.Z, 1.6) end
	local shelf = line.Stores.Fertiglager
	face(shelf.Standpoints.Slot2.Position, shelf.Slot2.Transfer.WorldPosition)
	assert(hire:Invoke().code == "HIRED")
	face(source, binding.source.point.WorldPosition)
	assert(assign:Invoke().code == "ASSIGNED")
	park()
	if testCase == "empty" then
		local empty = await("no material", function(s)
			return s.workerStatus == "Material fehlt" and s.banner:find("Material fehlt", 1, true) ~= nil
		end)
		assert(next(empty.claims) == nil and next(empty.batches) == nil and empty.banner:find("Material fehlt", 1, true))
		return {test = testCase, status = empty.workerStatus, revision = empty.revision}
	end
	if testCase == "full" then
		local full = await("target full", function(s)
			return s.workerStatus == "Montageeingang belegt" and s.banner:find("Montageeingang belegt", 1, true) ~= nil
		end)
		assert(full.batches[stock].locationId == route.source and next(full.claims) == nil and full.revision == 2)
		assert(full.banner:find("Montageeingang belegt", 1, true))
		local stations = line.Stations
		face(stations.Montage.Standpoints.Output.Position, stations.Montage.Output.Transfer.WorldPosition)
		assert(hand:Invoke("Montage.Output", "Take").result.ok)
		face(stations.Finish.Standpoints.Input.Position, stations.Finish.Input.Transfer.WorldPosition)
		assert(hand:Invoke("Finish.Input", "Put").result.ok)
		park()
	elseif testCase == "trapped" then
		await("physical pickup", function(s) return s.batches[stock].locationId == route.carrier end)
		block(source.X + 1.13, source.Z + 1.45, 0.50)
		local trapped = await("recoverable carrier", function(s)
			return s.workerPaused and s.batches[stock].locationId == route.carrier
		end)
		assert(trapped.workerAttempts == 2 and next(trapped.claims) == nil and trapped.reservations[route.source])
		local recover = storage.P0805Recover :: BindableFunction
		assert(recover:Invoke().code == "TOO_FAR")
		local workerRoot = workspace.P0509LineDemo.Werkstattmitarbeiter.HumanoidRootPart :: BasePart
		local point = (workerRoot.WorkerRecoveryPoint :: Attachment).WorldPosition
		local position = point - Vector3.new(1.0, 0.25, 2.0)
		root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
		task.wait()
		local obstruction = Instance.new("Part")
		obstruction.Anchored = true
		obstruction.Size = Vector3.new(0.7, 0.7, 0.7)
		obstruction.Position = ((character.Head :: BasePart).Position + point) / 2
		obstruction.Parent = workspace
		table.insert(blocks, obstruction)
		assert(recover:Invoke().code == "OBSTRUCTED")
		obstruction:Destroy()
		local result = recover:Invoke()
		assert(result.ok and result.code == "RECOVERED", result.code)
		local after = state:Invoke()
		assert(after.batches[stock].locationId == "Demo.Hand" and after.reservations[route.source].carrierId == "Demo.Hand")
		return {test = testCase, status = result.code, revision = after.revision, location = after.batches[stock].locationId}
	else
		local blocked = await("blockage", function(s)
			return s.workerStatus == "Weg blockiert" and s.banner:find("Weg blockiert", 1, true) ~= nil
		end)
		assert(blocked.banner:find("Weg blockiert", 1, true))
		local paused = await("paused after two attempts", function(s) return s.workerPaused end)
		assert(paused.workerAttempts == 2 and next(paused.claims) == nil and paused.batches[stock].locationId == route.source)
		if testCase == "after" then
			assert(paused.workerStatus == "Ware am Sägeausgang" and paused.reservations[route.source] == nil)
			face(source, binding.source.point.WorldPosition)
			local manual = hand:Invoke(route.source, "Take")
			assert(manual.result.ok and manual.held.id == stock)
			return {test = testCase, status = paused.workerStatus, attempts = paused.workerAttempts, location = manual.held.locationId}
		end
		for _, part in blocks do part:Destroy() end
		face(source, binding.source.point.WorldPosition)
		assert(assign:Invoke().code == "ALREADY_ASSIGNED")
		park()
	end
	local delivered = await("delivered after clearing", function(s)
		for _, receipt in s.workerReceipts do
			if receipt.batchId == stock and receipt.targetId == route.target then return true end
		end
		return false
	end)
	return {test = testCase, status = "DELIVERED", revision = delivered.revision, location = delivered.batches[stock].locationId}
end)
root.CFrame, root.Anchored = original, anchored
for _, obstruction in blocks do obstruction:Destroy() end
assert(ok, report)
return report
