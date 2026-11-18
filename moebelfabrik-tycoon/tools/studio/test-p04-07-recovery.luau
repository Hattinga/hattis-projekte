--!strict
-- Runs manually in the private Studio Server. Uses a private in-memory backend and transient props.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local runService = game:GetService("RunService")
assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning(), "Studio Server only")
local factory = game:GetService("ServerScriptService"):FindFirstChild("Factory")
assert(factory, "Missing Factory")
local State = require(factory.State)
local Transfers = require(factory.Transfers)
local Persistence = require(factory.Persistence)
local Recovery = require(factory.Recovery)

local sourcePoint = workspace.P02Line.Stores.Rohstofflager.Slot1.Transfer
local targetPoint = workspace.P02Line.Stations.Saege.Input.Transfer
local recoveryPoint = workspace.P02Line.Stores.Fertiglager.Slot1.Transfer
assert(sourcePoint:IsA("Attachment") and targetPoint:IsA("Attachment") and recoveryPoint:IsA("Attachment"))
assert(sourcePoint ~= targetPoint and sourcePoint ~= recoveryPoint and targetPoint ~= recoveryPoint)
assert(not workspace:FindFirstChild("P0407Test"), "Test marker already exists")
local folder = Instance.new("Folder")
folder.Name = "P0407Test"
folder.Parent = workspace
local holder = Instance.new("Part")
holder.Name = "TestCarrier"
holder.Anchored = true
holder.CanCollide = false
holder.Transparency = 1
holder.CFrame = sourcePoint.WorldCFrame * CFrame.new(0, 0, 3)
holder.Parent = folder
local handPoint = Instance.new("Attachment")
handPoint.Parent = holder

local points = {
	[sourcePoint:GetFullName()] = sourcePoint,
	[targetPoint:GetFullName()] = targetPoint,
	[recoveryPoint:GetFullName()] = recoveryPoint,
	[handPoint:GetFullName()] = handPoint,
}
local original = {source = sourcePoint:GetFullName(), target = targetPoint:GetFullName(),
	hand = handPoint:GetFullName()}
local fallback = {finished = recoveryPoint:GetFullName()}
local checks: {string} = {}
local reached: {any} = {}
local function passed(name: string)
	table.insert(checks, name)
end
local function render(plan: any, batchId: string, expected: Attachment)
	local row = plan.placements[batchId]
	assert(points[row.pointId] == expected)
	local part = Instance.new("Part")
	part.Name = batchId
	part.Size = Vector3.new(1, 1, 1)
	part.Color = Color3.fromRGB(255, 184, 70)
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = expected.WorldCFrame * CFrame.new(0, 0.5, 0)
	part.Parent = folder
	assert((part.Position - (expected.WorldCFrame * CFrame.new(0, 0.5, 0)).Position).Magnitude < 0.001)
	table.insert(reached, {batchId = batchId, location = row.locationId, physical = row.pointId,
		recovery = row.atRecoveryPoint, storageRevision = plan.storageRevision, stateRevision = plan.stateRevision})
	part:Destroy()
end

local ok, problem = xpcall(function()
	local profile = State.newProfile(101)
	profile.money = 17
	profile.locations.source = State.newLocation("source", "RawStore", 1, {"Holzpaket"})
	profile.locations.target = State.newLocation("target", "StationInput", 1, {"Holzpaket"})
	profile.locations.hand = State.newLocation("hand", "Carrier", 1, {"Holzpaket"})
	profile.locations.finished = State.newLocation("finished", "FinishedStore", 1, {"Karton"})
	profile.locations.empty = State.newLocation("empty", "FinishedStore", 1, {"Karton"})
	profile.batches.wood = State.newBatch("wood", 101, "Holzpaket", "source")
	profile.batches.carton = State.newBatch("carton", 101, "Karton", "finished")
	local now = 100
	local value: any
	local backend = {
		read = function(): any return value end,
		update = function(_: string, transform: (any) -> any): any
			local proposed = transform(value)
			if proposed ~= nil then value = proposed end
			return proposed
		end,
	}
	local controller = Persistence.new(101, backend, function(): number return now end)
	assert(Recovery.plan(controller.snapshot(), 101, now, original, fallback).code == "NOT_CONFIRMED")
	passed("empty persistence controller exposes no placement")
	assert(controller.load("test/01", 30, function(): any
		return {profileVersion = 1, state = profile,
			progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
	end).ok)
	local function plan(current: any, normal: any?, alternatives: any?): any
		return Recovery.plan(current.snapshot(), 101, now, normal or original, alternatives or fallback)
	end
	local function rejoin(index: number): any
		now = value.expiresAt
		local new = Persistence.new(101, backend, function(): number return now end)
		assert(new.load("test/" .. index, 30, function(): any error("Existing profile must not initialize") end).ok)
		return new
	end
	local function save(current: any, candidate: any)
		local data = current.snapshot().confirmed.data
		data.state = candidate
		assert(current.save(data, 30).ok)
	end
	local actor = {kind = "Player", actorId = "Player/101", ownerUserId = 101, carrierLocationId = "hand", ready = true}
	local function reserve(store: any, id: string, from: string, to: string): any
		return Transfers.reserve(store, actor, {operationId = id, expectedRevision = store.profile.revision,
			batchId = "wood", sourceId = from, targetId = to, quantity = 1}, now, 15)
	end
	local function commit(store: any, id: string, claimId: string): any
		return Transfers.commit(store, actor, {operationId = id, expectedRevision = store.profile.revision,
			claimId = claimId}, now)
	end
	local store = Transfers.new(controller.snapshot().confirmed.data.state)
	assert(reserve(store, "reserve-pickup", "source", "hand").ok)
	save(controller, store.profile)
	assert(commit(store, "unsaved-pickup", "reserve-pickup").ok)
	controller = rejoin(2)
	local confirmed = controller.snapshot().confirmed
	assert(confirmed.data.state.claims["reserve-pickup"] and confirmed.data.state.batches.wood.locationId == "source")
	assert(State.countAt(confirmed.data.state, "source") == 1 and State.countAt(confirmed.data.state, "hand") == 0)
	render(plan(controller), "wood", sourcePoint)
	passed("restart before confirmed pickup restores the source exactly once")
	local repeated = plan(controller)
	assert(repeated.placements.wood.pointId == original.source and repeated.placements.carton.atRecoveryPoint)
	render(repeated, "carton", recoveryPoint)
	assert(value.data.state.batches.carton.locationId == "finished" and value.data.state.money == 17)
	assert(repeated.storageRevision == value.revision and repeated.stateRevision == value.data.state.revision and not repeated.ready)
	passed("exclusive physical recovery point keeps the confirmed logical slot and balance")

	local collision = table.clone(original)
	collision.empty = fallback.finished
	local blocked = plan(controller, collision)
	assert(blocked.code == "POINT_CONFLICT" and not blocked.placements)
	assert(plan(controller, original, {}).code == "POINT_MISSING")
	assert(Recovery.plan(controller.snapshot(), 999, now, original, fallback).code == "INVALID_STATE")
	passed("occupied or registered point collision, absent point and wrong owner block all placement")
	assert(Recovery.plan(controller.snapshot(), 101, value.expiresAt, original, fallback).code == "SESSION_UNAVAILABLE")
	local pending = controller.snapshot()
	pending.inFlight = true
	assert(Recovery.plan(pending, 101, now, original, fallback).code == "NOT_CONFIRMED")
	pending.inFlight, pending.unknown = false, true
	assert(Recovery.plan(pending, 101, now, original, fallback).code == "NOT_CONFIRMED")
	passed("expired, in-flight and unknown saves cannot authorize placement")

	store = Transfers.new(confirmed.data.state)
	assert(Transfers.expireClaims(store, now).expired == 1)
	assert(store.profile.receipts["reserve-pickup"] and store.profile.batches.wood.locationId == "source")
	assert(reserve(store, "pickup-again", "source", "hand").ok and commit(store, "pickup", "pickup-again").ok)
	save(controller, store.profile)
	controller = rejoin(3)
	local picked = controller.snapshot().confirmed.data.state
	assert(picked.reservations.source.kind == "Return" and State.countAt(picked, "source") == 0)
	render(plan(controller), "wood", handPoint)
	passed("confirmed pickup preserves the same carrier and guaranteed Return")
	local noHand = table.clone(original)
	noHand.hand = nil
	assert(plan(controller, noHand, {finished = fallback.finished, hand = fallback.finished}).code == "CARRIER_MISSING")
	local noReturn = table.clone(original)
	noReturn.source = nil
	assert(plan(controller, noReturn).code == "PROMISED_POINT_MISSING")
	passed("missing carrier or Return point cannot spill onto a generic pickup point")

	store = Transfers.new(picked)
	assert(reserve(store, "place-reserve", "hand", "target").ok and commit(store, "place", "place-reserve").ok)
	save(controller, store.profile)
	controller = rejoin(4)
	confirmed = controller.snapshot().confirmed
	assert(not confirmed.data.state.reservations.source and State.countAt(confirmed.data.state, "hand") == 0)
	assert(confirmed.data.state.batches.wood.stage == "Holzpaket" and confirmed.data.state.batches.wood.quantity == 1)
	render(plan(controller), "wood", targetPoint)
	assert(confirmed.data.state.money == 17 and confirmed.data.state.receipts.place)
	passed("confirmed placement restores only the destination and preserves stage and history")
end, function(failure: any): string return debug.traceback(tostring(failure), 2) end)
folder:Destroy()
return {task = "P04-07", status = if ok then "passed" else "failed", checks = checks, problem = problem,
	placements = reached, dataStoreAccess = false, economicReady = false, runtimeOverlayRemoved = not workspace:FindFirstChild("P0407Test")}
