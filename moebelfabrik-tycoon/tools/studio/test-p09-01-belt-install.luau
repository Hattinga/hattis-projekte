--!strict
-- After LineDemo in a fresh logistics server. P0901Phase is "install", "resume", or "poor".
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local state = storage.P0509LineState :: BindableFunction
local install = storage.P0901Belt :: BindableFunction
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character.HumanoidRootPart :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local phase = workspace:GetAttribute("P0901Phase")
assert(phase == "install" or phase == "resume" or phase == "poor")
assert((workspace:GetAttribute("P0607ResumeScope") ~= nil) == (phase ~= "poor"))
local demo = workspace.P0509LineDemo
local stations = workspace.P02Line.Stations
local stand = stations.Saege.Standpoints.Output.Position
local source = stations.Saege.Output.Transfer.WorldPosition
local target = stations.Montage.Input.Transfer.WorldPosition
local original, anchored = root.CFrame, root.Anchored
root.Anchored = true
local ok, result = pcall(function()
	local before = state:Invoke()
	root.CFrame = original + Vector3.new(0, 15, 0)
	assert(install:Invoke().code == "TOO_FAR")
	local position = stand + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, Vector3.new(source.X, position.Y, source.Z))
	local first = install:Invoke()
	local after = state:Invoke()
	assert(after.valid and next(after.batches) == nil)
	if phase == "poor" then
		assert(first.code == "NOT_ENOUGH_FOR_BELT" and not first.ok)
		assert(after.money == 180 and after.revision == 0 and not after.firstBelt and not demo:FindFirstChild("Foerderband"))
		return {phase = phase, money = after.money, code = first.code, revision = after.revision}
	end
	assert(after.money == 60 and after.revision == 1 and first.ok)
	if phase == "install" then
		assert(before.money == 260 and before.firstBelt == nil and first.code == "BELT_INSTALLED")
	else
		assert(before.money == 60 and before.firstBelt and first.code == "BELT_OWNED")
	end
	local belt = assert(after.firstBelt)
	assert(belt.sourceId == "Saege.Output" and belt.targetId == "Montage.Input" and belt.price == 200 and belt.revision == 1)
	local slot = assert(after.beltLocation)
	assert(slot.kind == "Band" and slot.capacity == 1 and #slot.acceptedStages == 1 and slot.acceptedStages[1] == "Bausatz")
	local model = assert(demo:FindFirstChild("Foerderband"))
	assert(model:FindFirstChild("Puffermarke", true))
	local input = model:FindFirstChild("Input", true) :: Attachment
	local output = model:FindFirstChild("Output", true) :: Attachment
	local buffer = model:FindFirstChild("Buffer", true) :: Attachment
	assert(input and output and buffer and (input.WorldPosition - source).Magnitude < 0.001
		and (output.WorldPosition - target).Magnitude < 0.001)
	assert(buffer.WorldPosition.X > source.X and buffer.WorldPosition.X < target.X)
	local WareView = require(game:GetService("ServerScriptService").Factory.WareView)
	local footprint = WareView.create(demo, buffer.WorldCFrame, "Band-Maßprobe", "Bausatz")
	local occupied = WareView.create(demo, output.WorldCFrame, "Ziel-Maßprobe", "Bausatz")
	local bufferedBox, bufferedSize = footprint:GetBoundingBox()
	local occupiedBox, occupiedSize = occupied:GetBoundingBox()
	local clearance = occupiedBox.Position.X - bufferedBox.Position.X - (bufferedSize.X + occupiedSize.X) / 2
	footprint:Destroy()
	occupied:Destroy()
	assert(clearance >= 0.20, "Buffered kit intersects an occupied destination")
	assert(math.abs(bufferedBox.Position.Y - bufferedSize.Y / 2 - buffer.WorldPosition.Y) < 0.01)
	local again = install:Invoke()
	assert(again.code == "BELT_OWNED" and state:Invoke().money == 60 and state:Invoke().revision == 1)
	local count = 0
	for _, child in demo:GetChildren() do if child.Name == model.Name then count += 1 end end
	assert(count == 1)
	local released = (storage.P0607Release :: BindableFunction):Invoke()
	assert(released.ok, released.code)
	return {phase = phase, money = after.money, code = first.code, revision = after.revision,
		input = tostring(input.WorldPosition), output = tostring(output.WorldPosition),
		buffer = tostring(buffer.WorldPosition), bufferClearanceStuds = clearance, released = released.code}
end)
root.CFrame, root.Anchored = original, anchored
assert(ok, result)
return result
