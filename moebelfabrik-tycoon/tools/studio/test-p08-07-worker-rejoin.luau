--!strict
-- Start LineDemo with P06LoadingDemo, P0803WorkerStock and the same dedicated resume scope in both Play Servers.
-- P0807Phase="carry" in the first server, "resume" in the second.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
assert(workspace:GetAttribute("P0607ResumeScope") ~= nil)
local storage = game:GetService("ServerStorage")
local state = storage.P0509LineState :: BindableFunction
local release = storage.P0607Release :: BindableFunction
local hire = storage.P0801Hire :: BindableFunction
local assign = storage.P0802Assign :: BindableFunction
local factory = game:GetService("ServerScriptService").Factory
local route = require(factory.State).FIRST_WORKER
local line = workspace.P02Line
local binding = require(factory.WorkerRoute).bind(line.Stations)
local phase = workspace:GetAttribute("P0807Phase")
assert(phase == "carry" or phase == "resume")
local player = assert(game:GetService("Players"):GetPlayers()[1])
local char = assert(player.Character)
local root = char.HumanoidRootPart :: BasePart
local humanoid = assert(char:FindFirstChildOfClass("Humanoid"))
local original, anchored = root.CFrame, root.Anchored
local stock = "Testbausatz"
local obstacle = Instance.new("Part")
obstacle.Anchored = true
obstacle.Size = Vector3.new(1.6, 3.5, 2)
local source = binding.source.stand.Position
obstacle.Position = Vector3.new(source.X + 2.5, 2.8, source.Z)
local function face(stand: Vector3, point: Vector3)
	local position = stand + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
local function await(label: string, predicate: (any) -> boolean): any
	local expires = os.clock() + 22
	repeat
		local s = state:Invoke()
		assert(s.valid and s.batches[stock])
		if predicate(s) then return s end
		task.wait(0.06)
	until os.clock() >= expires
	error(label .. " timed out: " .. tostring(state:Invoke().workerStatus))
end
root.Anchored = true
local ok, report = pcall(function()
	if phase == "carry" then
		assert(state:Invoke().firstWorker == nil)
		obstacle.Parent = workspace
		local shelf = line.Stores.Fertiglager
		face(shelf.Standpoints.Slot2.Position, shelf.Slot2.Transfer.WorldPosition)
		assert(hire:Invoke().code == "HIRED")
		face(source, binding.source.point.WorldPosition)
		assert(assign:Invoke().code == "ASSIGNED")
		root.CFrame = original + Vector3.new(0, 15, 0)
		await("pickup before server change", function(s) return s.batches[stock].locationId == route.carrier end)
	else
		root.CFrame = original + Vector3.new(0, 15, 0)
		await("returned after server change", function(s)
			return s.workerPaused and s.batches[stock].locationId == route.source and next(s.claims) == nil
		end)
	end
	local released = release:Invoke()
	assert(released.ok, released.code)
	local final = state:Invoke()
	local location = final.batches[stock].locationId
	assert(final.money == 60 and final.firstWorker.assigned and final.firstWorker.revision == 1)
	assert(location == (if phase == "carry" then route.carrier else route.source))
	if phase == "carry" then
		assert(final.reservations[route.source].kind == "Return")
	else
		assert(final.reservations[route.source] == nil)
	end
	for _, receipt in final.workerReceipts do assert(receipt.targetId ~= route.target, "Unexpected phantom delivery") end
	return {phase = phase, location = location, money = final.money, revision = final.revision, release = released.code}
end)
root.CFrame, root.Anchored = original, anchored
obstacle:Destroy()
assert(ok, report)
return report
