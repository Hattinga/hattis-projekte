--!strict
-- Server proof for the transient P05-03 demo. Start the demo in a fresh Studio Play first.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local player = game:GetService("Players"):GetPlayers()[1]
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart")
local humanoid = character:FindFirstChildOfClass("Humanoid")
assert(root and root:IsA("BasePart") and humanoid)
local hook = game:GetService("ServerStorage"):FindFirstChild("P0503HandTest")
assert(hook and hook:IsA("BindableFunction"))
local line = workspace.P02Line
local raw, saw, montage = line.Stores.Rohstofflager, line.Stations.Saege, line.Stations.Montage
local demo = workspace.P0503HandDemo
local checks: {string} = {}
local scale = 25 / 7
local saved, anchored = root.CFrame, root.Anchored
root.Anchored = true
local function position(stand: BasePart, point: Attachment, buffer: number)
	local toward = (point.WorldPosition - stand.Position) * Vector3.new(1, 0, 1)
	local foot = stand.Position - toward.Unit * buffer * scale
	local position = foot + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, position + toward.Unit)
end
local ok, problem = xpcall(function()
	assert(raw.Slot1.Transfer:FindFirstChild("P0503Hand") and saw.Input.Transfer:FindFirstChild("P0503Hand"))
	root.CFrame = CFrame.new(raw.Slot1.Transfer.WorldPosition + Vector3.new(12, 0, 0))
	local far = hook:Invoke("RawStore.Slot1", "Take")
	assert(far.result.code == "TOO_FAR" and far.revision == 0, far.result.code)
	local opposite = (raw.Slot1.Transfer.WorldPosition - raw.Standpoints.Slot1.Position) * Vector3.new(1, 0, 1)
	root.CFrame = CFrame.new(raw.Slot1.Transfer.WorldPosition + opposite.Unit * 3)
	local back = hook:Invoke("RawStore.Slot1", "Take")
	assert(back.result.code == "WRONG_SIDE" and back.revision == 0, back.result.code)
	table.insert(checks, "out of reach and the wrong side leave the inventory untouched")
	position(raw.Standpoints.Slot1, raw.Slot1.Transfer, 0.20)
	local took = hook:Invoke("RawStore.Slot1", "Take")
	assert(took.result.ok and took.held.id == "Holzpaket-1" and took.reservations["RawStore.Slot1"], took.result.code)
	assert(demo.StockViews["Holzpaket-1"]:FindFirstChildOfClass("WeldConstraint") and #demo.StockViews:GetChildren() == 2)
	assert(took.banner:find("In der Hand", 1, true))
	table.insert(checks, "wood is shown once on the avatar and holds its original place")
	position(montage.Standpoints.Input, montage.Input.Transfer, 0.15)
	local wrong = hook:Invoke("Montage.Input", "Put")
	assert(wrong.result.code == "WRONG_STAGE" and wrong.held.id == "Holzpaket-1" and wrong.revision == took.revision, wrong.result.code)
	table.insert(checks, "the assembly bench rejects raw wood and keeps it in the player's hand")
	position(saw.Standpoints.Input, saw.Input.Transfer, 0.15)
	local put = hook:Invoke("Saege.Input", "Put")
	assert(put.result.ok and not put.held and not put.reservations["RawStore.Slot1"], put.result.code)
	assert(put.batches["Holzpaket-1"].locationId == "Saege.Input" and #demo.StockViews:GetChildren() == 2)
	assert(demo.StockViews["Holzpaket-1"]:GetAttribute("SlotId") == "Saege.Input" and put.banner:find("Hand frei", 1, true))
	table.insert(checks, "the same wood is placed once on the saw intake and the hand is empty")
	position(raw.Standpoints.Slot2, raw.Slot2.Transfer, 0.20)
	assert(hook:Invoke("RawStore.Slot2", "Take").result.ok)
	position(saw.Standpoints.Input, saw.Input.Transfer, 0.15)
	local full = hook:Invoke("Saege.Input", "Put")
	assert(full.result.code == "TARGET_FULL" and full.held.id == "Holzpaket-2", full.result.code)
	position(raw.Standpoints.Slot2, raw.Slot2.Transfer, 0.20)
	local returned = hook:Invoke("RawStore.Slot2", "Put")
	assert(returned.result.ok and not returned.held and returned.batches["Holzpaket-2"].locationId == "RawStore.Slot2")
	table.insert(checks, "full intake keeps the second package carried until a successful physical return")
end, function(err: any): string return debug.traceback(tostring(err), 2) end)
root.CFrame, root.Anchored = saved, anchored
return {task = "P05-03", status = if ok then "passed" else "failed", checks = checks, failure = problem, storage = false}
