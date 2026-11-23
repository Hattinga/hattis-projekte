--!strict
-- P06LoadingDemo, P0901Funds and P0803WorkerStock. P0903Case full/carry/resume.
-- full also needs P0804WorkerTargetFull. carry/resume use one fresh isolated P0607ResumeScope.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local state = storage.P0509LineState :: BindableFunction
local install = storage.P0901Belt :: BindableFunction
local power = storage.P0905Power :: BindableFunction
local hand = storage.P0509LineTest :: BindableFunction
local line = workspace.P02Line
local stations = line.Stations
local phase = workspace:GetAttribute("P0903Case")
assert(phase == "full" or phase == "carry" or phase == "resume")
assert((workspace:GetAttribute("P0607ResumeScope") ~= nil) == (phase ~= "full"))
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local stock = "Testbausatz"
local function face(pad: Instance, stand: BasePart)
	local position = stand.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local point = (pad:FindFirstChild("Transfer") :: Attachment).WorldPosition
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
local function await(label: string, predicate: (any) -> boolean): any
	local expires = os.clock() + 25
	repeat
		local snapshot = state:Invoke()
		assert(snapshot.valid and snapshot.batches[stock])
		if predicate(snapshot) then return snapshot end
		task.wait(0.03)
	until os.clock() >= expires
	local last = state:Invoke()
	error(string.format("%s timed out, belt %s, stock %s", label, tostring(last.beltStatus), last.batches[stock].locationId))
end
local demo = workspace.P0509LineDemo
local function stockX(): number?
	local ware = demo.Wares:FindFirstChild(stock)
	if ware and ware:IsA("Model") and ware:GetAttribute("Signature") == "Bausatz@Band.First" then
		return ware:GetPivot().Position.X
	end
	return nil
end
root.Anchored = true
local ok, report = pcall(function()
	face(stations.Saege.Output, stations.Saege.Standpoints.Output)
	if phase ~= "resume" then assert(install:Invoke().code == "BELT_INSTALLED") end
	local model = assert(demo:FindFirstChild("Foerderband"))
	local bufferX = (model:FindFirstChild("Buffer", true) :: Attachment).WorldPosition.X
	local outputX = (model:FindFirstChild("Output", true) :: Attachment).WorldPosition.X
	if phase == "full" then
		local waiting = await("buffer when target full", function(s) return s.beltStatus == "Montageeingang belegt" end)
		assert(waiting.batches[stock].locationId == "Band.First" and waiting.reservations["Saege.Output"].batchId == stock)
		assert(waiting.batches.TestMontageInput.locationId == "Montage.Input" and next(waiting.claims) == nil)
		assert(math.abs((stockX() or 0) - bufferX) < 0.01)
		face(stations.Montage.Output, stations.Montage.Standpoints.Output)
		assert(hand:Invoke("Montage.Output", "Take").result.ok)
		face(stations.Finish.Input, stations.Finish.Standpoints.Input)
		assert(hand:Invoke("Finish.Input", "Put").result.ok)
	elseif phase == "carry" then
		await("physical outbound motion", function(s)
			local x = stockX()
			return s.beltStatus == "Zur Montage" and x ~= nil and x > bufferX + 0.25 and x < outputX - 0.25
				and s.batches[stock].locationId == "Band.First"
		end)
		assert(power:Invoke().code == "BELT_STOPPED")
		local stopped = await("cancelled exit and returned visual buffer", function(s)
			return s.beltStatus == "Pausiert" and next(s.claims) == nil and math.abs((stockX() or 0) - bufferX) < 0.01
		end)
		assert(stopped.firstBelt.stopped and stopped.batches[stock].locationId == "Band.First")
		assert((storage.P0607Release :: BindableFunction):Invoke().ok)
		return {phase = phase, result = "STOPPED", location = "Band.First", revision = stopped.revision, money = stopped.money}
	else
		local resumed = await("same stopped buffer after server change", function(s)
			return s.beltStatus == "Pausiert" and math.abs((stockX() or 0) - bufferX) < 0.01
		end)
		assert(resumed.firstBelt.stopped and resumed.batches[stock].locationId == "Band.First")
		assert(power:Invoke().code == "BELT_RUNNING")
	end
	local delivered = await("confirmed delivery", function(s)
		for _, receipt in s.beltReceipts do
			if receipt.batchId == stock and receipt.targetId == "Montage.Input" then return true end
		end
		return false
	end)
	local pickupCount, dropCount = 0, 0
	for _, receipt in delivered.beltReceipts do
		if receipt.batchId == stock and receipt.targetId == "Band.First" then pickupCount += 1 end
		if receipt.batchId == stock and receipt.targetId == "Montage.Input" then dropCount += 1 end
	end
	assert(pickupCount == 1 and dropCount == 1 and next(delivered.claims) == nil and delivered.reservations["Saege.Output"] == nil)
	assert(delivered.money == 60)
	if phase == "resume" then assert((storage.P0607Release :: BindableFunction):Invoke().ok) end
	return {phase = phase, result = "DELIVERED", location = delivered.batches[stock].locationId,
		revision = delivered.revision, money = delivered.money, receipts = delivered.beltReceipts}
end)
root.CFrame, root.Anchored = original, anchored
assert(ok, report)
return report
