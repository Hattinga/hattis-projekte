--!strict
-- P09-04: the kit's visible pose follows the confirmed belt transport, also across a server change.
-- Every server: P06LoadingDemo, P0901Funds and P0803WorkerStock.
-- track: in memory with P0904SaveDelay=0.8. Load ToolRun.LineDemo, then this probe. A second writer saves
--   while the kit reaches the exit; the kit must wait there until its delivery is confirmed.
-- leave/return: the same fresh P0607ResumeScope in two servers. leave: LineDemo, then this probe; it releases
--   the session in the middle of the exit. return: set P0904InheritedClaim from the leave report; this probe
--   starts its frame sampler and then loads ToolRun.LineDemo itself, so the first restored pose is recorded.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local phase = workspace:GetAttribute("P0904Case")
assert(phase == "track" or phase == "leave" or phase == "return")
assert((workspace:GetAttribute("P0607ResumeScope") ~= nil) == (phase ~= "track"))
assert((workspace:GetAttribute("P0904SaveDelay") ~= nil) == (phase == "track"))
local inherited = workspace:GetAttribute("P0904InheritedClaim")
assert((phase == "return") == (type(inherited) == "string"))
local stock = "Testbausatz"
local ON_BELT = "Bausatz@Band.First"
local LOAD_SECONDS, EXIT_SECONDS = 0.7, 1.25

type Sample = {t: number, x: number, signature: string}
local samples: {Sample} = {}
local sampler = rs.Heartbeat:Connect(function()
	local demo = workspace:FindFirstChild("P0509LineDemo")
	local wares = demo and demo:FindFirstChild("Wares")
	local ware = wares and wares:FindFirstChild(stock)
	if ware and ware:IsA("Model") then
		table.insert(samples, {t = os.clock(), x = ware:GetPivot().Position.X,
			signature = tostring(ware:GetAttribute("Signature"))})
	end
end)
if phase == "return" then require(storage.ToolRun.LineDemo :: ModuleScript) end

local state = storage:WaitForChild("P0509LineState", 10) :: BindableFunction
local line = workspace.P02Line
local stations = line.Stations
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local demo = workspace.P0509LineDemo
local function face(pad: Instance, stand: BasePart)
	local position = stand.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local point = (pad:FindFirstChild("Transfer") :: Attachment).WorldPosition
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
-- The inherited claim is tracked from the first poll, so motion can be ordered against its release.
local lastInherited = -math.huge
local function read(): any
	local snapshot = state:Invoke()
	if phase == "return" and snapshot.claims[inherited] then lastInherited = os.clock() end
	return snapshot
end
local function await(label: string, predicate: (any) -> boolean): any
	local expires = os.clock() + 25
	repeat
		local snapshot = read()
		assert(snapshot.valid and snapshot.batches[stock])
		if predicate(snapshot) then return snapshot end
		task.wait(0.03)
	until os.clock() >= expires
	local last = read()
	error(string.format("%s timed out, belt %s, stock %s", label, tostring(last.beltStatus), last.batches[stock].locationId))
end
local function stockX(): number?
	local ware = demo.Wares:FindFirstChild(stock)
	if ware and ware:IsA("Model") and ware:GetAttribute("Signature") == ON_BELT then return ware:GetPivot().Position.X end
	return nil
end

local function analyse(list: {Sample}, inputX: number, bufferX: number, outputX: number): any
	local speed = math.max((bufferX - inputX) / LOAD_SECONDS, (outputX - bufferX) / EXIT_SECONDS) * 1.05
	local report = {runs = 0, samples = 0, maxBack = 0, maxJump = 0, outside = 0}
	local previous: Sample? = nil
	for _, sample in list do
		local before = previous
		if sample.signature == ON_BELT then
			report.samples += 1
			if not before or before.signature ~= ON_BELT then
				report.runs += 1
				report.firstX, report.firstT = sample.x, sample.t
				report.beforeSignature = if before then before.signature else nil
				report.beforeX = if before then before.x else nil
			else
				local dx = sample.x - before.x
				report.maxBack = math.max(report.maxBack, -dx)
				report.maxJump = math.max(report.maxJump, dx - speed * (sample.t - before.t))
			end
			if sample.x < inputX - 0.01 or sample.x > outputX + 0.01 then report.outside += 1 end
			if not report.arrivalT and sample.x >= outputX - 0.005 then report.arrivalT = sample.t end
			if not report.moveT and sample.x > bufferX + 0.005 and (phase == "return" or report.restT) then
				report.moveT = sample.t
			end
			if not report.restT and math.abs(sample.x - bufferX) < 0.005 then report.restT = sample.t end
			report.lastX, report.lastT = sample.x, sample.t
		elseif before and before.signature == ON_BELT and not report.afterSignature then
			report.afterSignature, report.afterX, report.afterT = sample.signature, sample.x, sample.t
		end
		previous = sample
	end
	return report
end

root.Anchored = true
local ok, report = pcall(function()
	face(stations.Saege.Output, stations.Saege.Standpoints.Output)
	if phase ~= "return" then assert((storage.P0901Belt :: BindableFunction):Invoke().code == "BELT_INSTALLED") end
	local model = assert(demo:FindFirstChild("Foerderband"))
	local inputX = (model:FindFirstChild("Input", true) :: Attachment).WorldPosition.X
	local bufferX = (model:FindFirstChild("Buffer", true) :: Attachment).WorldPosition.X
	local outputX = (model:FindFirstChild("Output", true) :: Attachment).WorldPosition.X
	assert(inputX < bufferX and bufferX < outputX, "Belt is expected to run along +X")
	local span = outputX - bufferX
	local renewal: any = nil
	if phase == "leave" then
		local mid = await("middle of the exit", function(s)
			local x = stockX()
			return s.beltStatus == "Zur Montage" and x ~= nil and x > bufferX + 0.2 * span and x < bufferX + 0.7 * span
				and next(s.claims) ~= nil
		end)
		local claimId = next(mid.claims) :: string
		local leftX = stockX()
		assert((storage.P0607Release :: BindableFunction):Invoke().ok)
		local after = read()
		sampler:Disconnect()
		local claim = after.claims[claimId]
		assert(claim and claim.actorKind == "Band" and claim.targetId == "Montage.Input", "Exit claim was not saved open")
		assert(after.batches[stock].locationId == "Band.First" and after.reservations["Saege.Output"].kind == "Return")
		local motion = analyse(samples, inputX, bufferX, outputX)
		assert(motion.runs == 1 and motion.maxBack <= 1e-3 and motion.maxJump <= 0.02 and motion.outside == 0)
		assert(motion.beforeSignature == "Bausatz@Saege.Output" and math.abs(motion.beforeX - inputX) <= 0.01)
		assert(math.abs(motion.firstX - inputX) <= 0.02, "Loaded kit must appear at the belt input")
		return {phase = phase, inheritedClaim = claimId, expiresAt = claim.expiresAt, releasedAt = os.time(),
			leftX = leftX, bufferX = bufferX, outputX = outputX, revision = after.revision, motion = motion}
	elseif phase == "track" then
		await("late part of the exit", function(s)
			local x = stockX()
			return s.beltStatus == "Zur Montage" and x ~= nil and x >= bufferX + 0.6 * span and x < outputX - 0.02
		end)
		local renew = storage.P0904Renew :: BindableFunction
		local code, startedAt, endedAt
		repeat
			startedAt = os.clock()
			code = renew:Invoke()
			endedAt = os.clock()
			if code == "BUSY" then task.wait() end
		until code ~= "BUSY" or (stockX() or outputX) >= outputX - 0.005
		assert(code == "SAVED", "Second writer did not save: " .. tostring(code))
		renewal = {startedAt = startedAt, endedAt = endedAt}
	end
	local delivered = await("confirmed delivery", function(s)
		for _, receipt in s.beltReceipts do
			if receipt.batchId == stock and receipt.targetId == "Montage.Input" then return true end
		end
		return false
	end)
	task.wait(1)
	sampler:Disconnect()
	local motion = analyse(samples, inputX, bufferX, outputX)
	assert(motion.runs == 1, "Belt view was interrupted " .. motion.runs .. " times")
	assert(motion.maxBack <= 1e-3, "Kit moved backwards by " .. motion.maxBack)
	assert(motion.maxJump <= 0.02, "Kit jumped forwards by " .. motion.maxJump)
	assert(motion.outside == 0 and motion.arrivalT and motion.lastX >= outputX - 0.005)
	if motion.afterSignature == "Bausatz@Montage.Input" then
		assert(math.abs(motion.afterX - outputX) <= 0.01, "Handover moved the kit")
	end
	local pickups, drops, dropClaim = 0, 0, nil
	for _, receipt in delivered.beltReceipts do
		if receipt.batchId == stock and receipt.targetId == "Band.First" then pickups += 1 end
		if receipt.batchId == stock and receipt.targetId == "Montage.Input" then
			drops += 1
			dropClaim = receipt.claimId
		end
	end
	assert(pickups == 1 and drops == 1 and next(delivered.claims) == nil and delivered.reservations["Saege.Output"] == nil)
	assert(delivered.money == 60)
	local result: any = {phase = phase, revision = delivered.revision, money = delivered.money,
		inputX = inputX, bufferX = bufferX, outputX = outputX, samples = #samples, motion = motion,
		hold = motion.lastT - motion.arrivalT}
	if phase == "track" then
		assert(motion.beforeSignature == "Bausatz@Saege.Output" and math.abs(motion.beforeX - inputX) <= 0.01)
		assert(math.abs(motion.firstX - inputX) <= 0.02, "Loaded kit must appear at the belt input")
		-- The second save covered the arrival, so the delivery had to wait with the kit at the exit.
		assert(renewal.startedAt < motion.arrivalT and renewal.endedAt > motion.arrivalT + 0.1, "Collision not exercised")
		assert(motion.lastT >= renewal.endedAt, "Delivery shown before the second save finished")
		result.renewal = {beforeArrival = motion.arrivalT - renewal.startedAt, afterArrival = renewal.endedAt - motion.arrivalT}
	else
		assert(math.abs(motion.firstX - bufferX) <= 0.01, "Restored kit must appear on the confirmed buffer")
		assert(dropClaim ~= inherited, "Delivery used the inherited claim")
		assert(motion.moveT and motion.moveT > lastInherited, "Kit moved before the inherited claim was released")
		local cancel = delivered.beltActions[inherited .. "/cancel"]
		result.inheritedClaim = if cancel then "CANCELLED" else "EXPIRED"
		result.inheritedSeenUntil = if lastInherited > -math.huge then motion.moveT - lastInherited else nil
		assert((storage.P0607Release :: BindableFunction):Invoke().ok)
	end
	return result
end)
sampler:Disconnect()
root.CFrame, root.Anchored = original, anchored
assert(ok, report)
return report
