--!strict
-- Start the logistics demo in a fresh Play Server. For hire/rejoin use a new P0607ResumeScope.
-- P0801HirePhase: "hire", "rejoin", or "poor" (with P0707Broke=true and no DataStore).
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local state = storage.P0509LineState :: BindableFunction
local hire = storage.P0801Hire :: BindableFunction
local phase = workspace:GetAttribute("P0801HirePhase")
assert(phase == "hire" or phase == "rejoin" or phase == "poor")
assert((workspace:GetAttribute("P0607ResumeScope") ~= nil) == (phase ~= "poor"))
local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = assert(character:FindFirstChildOfClass("Humanoid"))
local shelf = workspace.P02Line.Stores.Fertiglager
local stand = shelf.Standpoints.Slot2.Position
local transfer = shelf.Slot2.Transfer.WorldPosition
local original = root.CFrame
local anchored = root.Anchored
root.Anchored = true
local ok, result = pcall(function()
	local before = state:Invoke()
	assert(before.valid and next(before.batches) == nil)
	root.CFrame = original + Vector3.new(0, 12, 0)
	assert(hire:Invoke().code == "TOO_FAR")
	local position = stand + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, Vector3.new(transfer.X, position.Y, transfer.Z))
	local first = hire:Invoke()
	local after = state:Invoke()
	assert(after.valid and next(after.batches) == nil)
	if phase == "poor" then
		assert(before.money == 0 and not first.ok and first.code == "NOT_ENOUGH_MONEY")
		assert(after.money == 0 and after.revision == before.revision and after.firstWorker == nil)
		return {phase = phase, result = first.code, money = after.money, revision = after.revision}
	end
	assert(first.ok and after.money == 60 and after.firstWorker.price == 120 and after.firstWorker.revision == 1)
	if phase == "hire" then
		assert(before.money == 180 and before.firstWorker == nil and first.code == "HIRED")
	else
		assert(before.money == 60 and before.firstWorker.revision == 1 and first.code == "ALREADY_HIRED")
	end
	local repeated = hire:Invoke()
	local final = state:Invoke()
	assert(repeated.code == "ALREADY_HIRED" and final.money == 60 and final.revision == 1 and final.valid)
	local release = (storage.P0607Release :: BindableFunction):Invoke()
	assert(release.ok, release.code)
	return {phase = phase, result = first.code, repeated = repeated.code, money = final.money,
		revision = final.revision, hire = final.firstWorker, released = release.code}
end)
root.CFrame, root.Anchored = original, anchored
assert(ok, result)
return result
