--!strict
-- P05-09 automated chain (QA-P05-02, QA-P05-03 parts) on the transient demo. Start start-p05-09-line-demo first.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local hook = storage:FindFirstChild("P0509LineTest") :: BindableFunction
local reader = storage:FindFirstChild("P0509LineState") :: BindableFunction
assert(hook and reader and not storage:FindFirstChild("P0509Result"), "Start the demo in a fresh Play first")
local result = Instance.new("StringValue")
result.Name = "P0509Result"
result.Parent = storage
local player = game:GetService("Players"):GetPlayers()[1]
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
local line = workspace.P02Line
local scale = 25 / 7

task.spawn(function()
	local checks: {string} = {}
	local report: any = {task = "P05-09", checks = checks, storage = false}
	local started = os.clock()
	local saved, anchored = root.CFrame, root.Anchored
	root.Anchored = true
	local ok, failure = xpcall(function()
		local function stand(id: string): (BasePart, Attachment, number)
			local owner, slot = id:match("^(%w+)%.(%w+)$")
			assert(owner and slot, id)
			if owner == "RawStore" or owner == "FinishedStore" then
				local store = if owner == "RawStore" then line.Stores.Rohstofflager else line.Stores.Fertiglager
				return store.Standpoints[slot], store[slot].Transfer, 0.20
			end
			local station = line.Stations[owner]
			return station.Standpoints[slot], station[slot].Transfer, 0.15
		end
		local function act(id: string, direction: string): any
			local marker, point, buffer = stand(id)
			local toward = (point.WorldPosition - marker.Position) * Vector3.new(1, 0, 1)
			local foot = marker.Position - toward.Unit * buffer * scale
			local position = foot + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
			root.CFrame = CFrame.lookAt(position, position + toward.Unit)
			return hook:Invoke(id, direction)
		end
		local function done(id: string, direction: string)
			local response = act(id, direction)
			assert(response.result.ok, id .. " " .. direction .. " " .. response.result.code)
		end
		local function waitFor(batchId: string, stage: string, locationId: string, timeout: number): any
			local deadline = os.clock() + timeout
			while os.clock() < deadline do
				local view = reader:Invoke()
				local batch = view.batches[batchId]
				if batch.stage == stage and batch.locationId == locationId then return view end
				task.wait(0.25)
			end
			error(string.format("Timeout: %s never reached %s at %s", batchId, stage, locationId))
		end

		-- QA-P05-02 start: two marked wood packages; wrong bench keeps the wood in the hand.
		local view = reader:Invoke()
		assert(view.batches["Testholz-1"].locationId == "RawStore.Slot1" and view.batches["Testholz-2"].locationId == "RawStore.Slot2")
		done("RawStore.Slot1", "Take")
		view = reader:Invoke()
		assert(view.views["Testholz-1"].carried and view.banner:find("In der Hand: Holzpaket", 1, true))
		local wrong = act("Montage.Input", "Put")
		assert(wrong.result.code == "WRONG_STAGE" and wrong.held and wrong.held.id == "Testholz-1", wrong.result.code)
		done("Saege.Input", "Put")
		waitFor("Testholz-1", "Holzpaket", "Saege.Process", 3)
		done("RawStore.Slot2", "Take")
		done("Saege.Input", "Put")
		table.insert(checks, "wood is carried by hand, a wrong bench keeps it in the hand, the saw starts by itself and accepts the next package")

		-- Backpressure at the saw: the finished kit blocks the waiting second package (QA-P05-03).
		view = waitFor("Testholz-1", "Bausatz", "Saege.Output", 10)
		assert(view.signs.Status_Saege.code == "OUTPUT_FULL" and view.signs.Status_Saege.head == "OUTPUT FULL")
		task.wait(2)
		view = reader:Invoke()
		assert(view.batches["Testholz-2"].locationId == "Saege.Input" and view.batches["Testholz-2"].stage == "Holzpaket")
		done("Saege.Output", "Take")
		local misplaced = act("Finish.Input", "Put")
		assert(misplaced.result.code == "WRONG_STAGE" and misplaced.held.id == "Testholz-1", misplaced.result.code)
		done("Montage.Input", "Put")
		waitFor("Testholz-2", "Holzpaket", "Saege.Process", 3)
		table.insert(checks, "a waiting kit blocks the saw without consuming the next package; a kit at the finish input is refused and stays carried")

		-- Rest of the chain for both batches.
		waitFor("Testholz-1", "Rohhocker", "Montage.Output", 12)
		done("Montage.Output", "Take"); done("Finish.Input", "Put")
		waitFor("Testholz-2", "Bausatz", "Saege.Output", 10)
		done("Saege.Output", "Take"); done("Montage.Input", "Put")
		waitFor("Testholz-1", "Fertig", "Finish.Output", 10)
		done("Finish.Output", "Take"); done("Packen.Input", "Put")
		waitFor("Testholz-2", "Rohhocker", "Montage.Output", 12)
		done("Montage.Output", "Take"); done("Finish.Input", "Put")
		waitFor("Testholz-1", "Karton", "Packen.Output", 8)
		done("Packen.Output", "Take"); done("FinishedStore.Slot1", "Put")
		waitFor("Testholz-2", "Fertig", "Finish.Output", 10)
		done("Finish.Output", "Take"); done("Packen.Input", "Put")
		view = waitFor("Testholz-2", "Karton", "Packen.Output", 8)
		done("Packen.Output", "Take"); done("FinishedStore.Slot2", "Put")
		view = reader:Invoke()
		assert(view.batches["Testholz-1"].locationId == "FinishedStore.Slot1" and view.batches["Testholz-2"].locationId == "FinishedStore.Slot2")
		assert(view.views["Testholz-1"].signature == "Karton@FinishedStore.Slot1" and not view.views["Testholz-2"].carried)
		assert(next(view.reservations) == nil and view.valid and view.money == 0)
		assert(view.banner:find("Hand frei", 1, true) and view.banner:find("Fertiglager 2/4", 1, true))
		assert(view.signs.Status_Saege.code == "INPUT_MISSING" and view.signs.Status_Saege.head == "WOOD PACKAGE MISSING")
		assert(view.signs.Status_Store.code == "STORE_OPEN")
		table.insert(checks, "both batches pass saw, bench, finish and packing in order and end as two stored cartons without any order")
		report.final = {stored = {"Testholz-1", "Testholz-2"}, ticks = view.ticks}
	end, function(err: any): string return debug.traceback(tostring(err), 2) end)
	root.CFrame, root.Anchored = saved, anchored
	report.seconds = math.floor((os.clock() - started) * 10) / 10
	report.status = if ok then "passed" else "failed"
	report.failure = failure
	result.Value = game:GetService("HttpService"):JSONEncode(report)
end)
return {started = true}
