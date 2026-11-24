--!strict
-- P09-05: a taken assembly input stops the first belt, the backlog reaches the saw without consuming stock, and
-- everything resumes once the place is free.
-- Fresh Play server with P06LoadingDemo, P0901Funds, P0803WorkerStock, P0804WorkerTargetFull and P0905SawStock,
-- then ToolRun.LineDemo, then this probe. In memory only.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local state = storage.P0509LineState :: BindableFunction
local install = storage.P0901Belt :: BindableFunction
local power = storage.P0905Power :: BindableFunction
local hand = storage.P0509LineTest :: BindableFunction
local stations = workspace.P02Line.Stations
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local kit, wood = "Testbausatz", "TestHolz"
local function face(pad: Instance, stand: BasePart)
	local position = stand.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local point = (pad:FindFirstChild("Transfer") :: Attachment).WorldPosition
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
local function await(label: string, predicate: (any) -> boolean): any
	local expires = os.clock() + 25
	repeat
		local snapshot = state:Invoke()
		assert(snapshot.valid and snapshot.batches[kit] and snapshot.batches[wood])
		if predicate(snapshot) then return snapshot end
		task.wait(0.03)
	until os.clock() >= expires
	local last = state:Invoke()
	local saw, belt = last.signs.Status_Saege, last.signs.Status_Belt
	error(string.format("%s timed out, belt %s, saw sign %s, belt sign %s", label, tostring(last.beltStatus),
		saw and saw.code or "-", belt and belt.code or "-"))
end
local function sign(snapshot: any, name: string): any
	return snapshot.signs[name] or {code = "-", head = "-", detail = "-"}
end

root.Anchored = true
local ok, report = pcall(function()
	face(stations.Saege.Output, stations.Saege.Standpoints.Output)
	assert(install:Invoke().code == "BELT_INSTALLED")
	local backlog = await("backlog at saw and belt", function(s)
		-- The signs follow the confirmed stock at once; the belt reports "belegt" after the kit reached its buffer.
		return sign(s, "Status_Saege").code == "BACKLOG" and sign(s, "Status_Belt").code == "BACKLOG"
			and s.beltStatus == "Montageeingang belegt"
	end)
	assert(backlog.batches[kit].locationId == "Band.First" and backlog.batches[wood].locationId == "Saege.Input")
	assert(backlog.reservations["Saege.Output"].kind == "Return" and next(backlog.claims) == nil)
	assert(backlog.batches.TestMontageInput.locationId == "Montage.Input" and backlog.beltStatus == "Montageeingang belegt")
	assert(sign(backlog, "Status_Saege").head == "BACKLOG" and sign(backlog, "Status_Saege").detail == "ASSEMBLY INPUT FULL")
	assert(sign(backlog, "Status_Belt").head == "BACKLOG" and sign(backlog, "Status_Belt").detail == "ASSEMBLY INPUT FULL")

	-- Controlled backlog: no save, no claim, no material consumed while the place stays taken.
	local revision = backlog.revision
	task.wait(3)
	local held = state:Invoke()
	assert(held.revision == revision, "Backlog changed the stock")
	assert(held.batches[wood].locationId == "Saege.Input" and held.batches[kit].locationId == "Band.First")
	assert(held.reservations["Saege.Output"].kind == "Return" and next(held.claims) == nil)
	assert(sign(held, "Status_Saege").code == "BACKLOG" and sign(held, "Status_Belt").code == "BACKLOG")

	-- Switching the belt off changes the cause, switching it on restores the backlog. Stock stays put.
	assert(power:Invoke().code == "BELT_STOPPED")
	local stopped = await("stopped belt", function(s)
		return sign(s, "Status_Belt").code == "STOPPED" and sign(s, "Status_Saege").detail == "BELT STOPPED"
			and s.beltStatus == "Pausiert"
	end)
	assert(sign(stopped, "Status_Saege").code == "BACKLOG" and stopped.beltStatus == "Pausiert")
	assert(stopped.batches[kit].locationId == "Band.First" and stopped.batches[wood].locationId == "Saege.Input")
	assert(power:Invoke().code == "BELT_RUNNING")
	await("backlog after restart", function(s)
		return sign(s, "Status_Belt").code == "BACKLOG" and sign(s, "Status_Saege").detail == "ASSEMBLY INPUT FULL"
	end)

	-- Free the assembly: the belt delivers, the saw takes up its wood package.
	face(stations.Montage.Output, stations.Montage.Standpoints.Output)
	assert(hand:Invoke("Montage.Output", "Take").result.ok)
	face(stations.Finish.Input, stations.Finish.Standpoints.Input)
	assert(hand:Invoke("Finish.Input", "Put").result.ok)
	local delivered = await("delivery after the place is free", function(s)
		for _, receipt in s.beltReceipts do
			if receipt.batchId == kit and receipt.targetId == "Montage.Input" then return true end
		end
		return false
	end)
	local resumed = await("saw runs again", function(s)
		local lock = s.reservations["Saege.Output"]
		return lock ~= nil and lock.kind == "Production" and lock.batchId == wood and sign(s, "Status_Saege").code == "RUNNING"
	end)
	assert(resumed.batches[wood].locationId == "Saege.Process" and next(resumed.claims) == nil)
	assert(sign(resumed, "Status_Belt").code ~= "BACKLOG" and sign(resumed, "Status_Belt").code ~= "STOPPED")
	local pickups, drops = 0, 0
	for _, receipt in resumed.beltReceipts do
		if receipt.batchId == kit and receipt.targetId == "Band.First" then pickups += 1 end
		if receipt.batchId == kit and receipt.targetId == "Montage.Input" then drops += 1 end
	end
	assert(pickups == 1 and drops == 1 and delivered.money == 60 and resumed.money == 60)
	return {result = "RESUMED", backlogRevision = revision, heldRevision = held.revision,
		deliveredRevision = delivered.revision, resumedRevision = resumed.revision, money = resumed.money,
		signs = {backlog = {saw = sign(backlog, "Status_Saege"), belt = sign(backlog, "Status_Belt")},
			stopped = {saw = sign(stopped, "Status_Saege"), belt = sign(stopped, "Status_Belt")},
			resumed = {saw = sign(resumed, "Status_Saege"), belt = sign(resumed, "Status_Belt")}}}
end)
root.CFrame, root.Anchored = original, anchored
assert(ok, report)
return report
