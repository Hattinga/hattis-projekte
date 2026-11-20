--!strict
-- Start the logistics demo in a fresh Play Server, then load this probe.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local assign = storage.P0802Assign :: BindableFunction
local hire = storage.P0801Hire :: BindableFunction
local state = storage.P0509LineState :: BindableFunction
local route = require(game:GetService("ServerScriptService").Factory.WorkerRoute)
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local line = workspace.P02Line
local binding = route.bind(line.Stations)
local source, target = binding.source.stand.Position, binding.target.stand.Position
local original, anchored = root.CFrame, root.Anchored
local block = Instance.new("Part")
block.Anchored = true
block.Size = Vector3.new(1.6, 3.5, 2)
block.Position = (source + target) / 2 + Vector3.new(0, 2, 0)
local function face(stand: Vector3, point: Vector3)
	local position = stand + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, Vector3.new(point.X, position.Y, point.Z))
end
root.Anchored = true
local ok, output = pcall(function()
	assert(not state:Invoke().firstWorker and not workspace.P0509LineDemo:FindFirstChild("Werkstattmitarbeiter"))
	face(source, binding.source.point.WorldPosition)
	assert(assign:Invoke().code == "NOT_HIRED")
	local shelf = line.Stores.Fertiglager
	face(shelf.Standpoints.Slot2.Position, shelf.Slot2.Transfer.WorldPosition)
	assert(hire:Invoke().code == "HIRED")
	face(source, binding.source.point.WorldPosition)
	assert(assign:Invoke().code == "ASSIGNED")
	assert(assign:Invoke().code == "ALREADY_ASSIGNED")
	root.CFrame = original + Vector3.new(0, 15, 0)
	local model = assert(workspace.P0509LineDemo:WaitForChild("Werkstattmitarbeiter", 15), "Missing hired worker") :: Model
	local actorRoot = model.HumanoidRootPart :: BasePart
	local rig = {model = model, root = actorRoot, humanoid = assert(model:FindFirstChildOfClass("Humanoid"))}
	local final = state:Invoke()
	assert(final.valid and final.money == 60 and final.revision == 2 and final.firstWorker.assigned == true)
	assert(route.clear(binding.rest, source, {model}) and route.clear(source, target, {model}))
	assert(actorRoot:GetNetworkOwner() == nil)
	assert(route.walk(rig, binding.rest, source), "Walk to source failed: " .. tostring(actorRoot.Position))
	block.Parent = workspace
	assert(not route.clear(source, target, {model}))
	assert(not route.walk(rig, source, target) and route.near(rig, source))
	block.Parent = nil
	local from = actorRoot.Position
	assert(route.walk(rig, source, target), "Walk to target failed: " .. tostring(actorRoot.Position))
	assert(route.near(rig, target) and (actorRoot.Position - from).Magnitude >= 2.5)
	return {status = "passed", distanceStuds = (target - source).Magnitude, money = final.money,
		revision = final.revision, source = tostring(source), target = tostring(target), actualEnd = tostring(actorRoot.Position)}
end)
root.CFrame, root.Anchored = original, anchored
block:Destroy()
assert(ok, output)
return output
