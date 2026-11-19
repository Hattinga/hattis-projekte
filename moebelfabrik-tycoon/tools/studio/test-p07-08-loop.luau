--!strict
-- P07-08 full loop, both channels. In a fresh Play server: P06LoadingDemo=true, start-p05-09-line-demo, this probe,
-- then drive-p06-02-route (Workshop -> Supplier -> Workshop -> Dealer -> Private).
-- Two purchased batches travel as wood, are made by hand into cartons, one is sold to the dealer and one privately,
-- and the proceeds buy new wood. Result: JSON in ServerStorage.P0708Result ("passed" or "failed").
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning())
local storage = game:GetService("ServerStorage")
local http = game:GetService("HttpService")
local lineTest = storage:FindFirstChild("P0509LineTest") :: BindableFunction
local lineState = storage:FindFirstChild("P0509LineState") :: BindableFunction
local purchase = storage:FindFirstChild("P060405Purchase") :: BindableFunction
local saleTest = storage:FindFirstChild("P07SaleTest") :: BindableFunction
assert(lineTest and lineState and purchase and saleTest, "Start a fresh P06 loading demo first")
assert(not storage:FindFirstChild("P0708Result") and not storage:FindFirstChild("P0708Stop"), "P07-08 probe already active")

local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
assert(root and humanoid and not humanoid.SeatPart)
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local HandMoves = require(factory.HandMoves)
local Vehicles = require(factory.Vehicles)
local vehicle = workspace.P02Vehicle
local chassis = vehicle.Quad.Chassis :: BasePart
local seat = vehicle.Quad.Seat :: VehicleSeat
local binding = assert(Vehicles.bind(vehicle, "Quad1"))
local slotA, slotB = binding.slotIds[1], binding.slotIds[2]
local yards = workspace.CityGreybox.DeliveryYards
local zones = {Workshop = yards.Tischlerei_West.LoadZone.Volume, Supplier = yards.Holzlieferant.LoadZone.Volume,
	Dealer = yards.Moebelhandel.LoadZone.Volume, Private = yards.Privatkunden.LoadZone.Volume}
local line = workspace.P02Line
local pickup = yards.Holzlieferant.P05Pickup
local wares = workspace.P0509LineDemo.Wares
local SCALE = 25 / 7
local FLAT = Vector3.new(1, 0, 1)
local HAND = "Demo.Hand"

local initial = lineState:Invoke()
assert(initial.valid and initial.money == 180 and next(initial.batches) == nil and next(initial.reservations) == nil)
assert(Vehicles.zone(binding, zones) == "Workshop" and seat.Occupant == nil)
local result = Instance.new("StringValue")
result.Name = "P0708Result"
result.Parent = storage
local stop = Instance.new("BindableFunction")
stop.Name = "P0708Stop"

type Transit = {slots: {[string]: string}, views: {[string]: Model}, relative: {[string]: Vector3}, stage: State.Stage,
	revision: number, money: number, samples: number, distance: number, maxDrift: number, lastPoint: Vector3, lastSample: number}
local transit: Transit? = nil
local batches: {string} = {}
local started = os.clock()
local savedRoot, savedAnchored = root.CFrame, root.Anchored
local stage = 0
local report: any = {status = "ready", checkpoints = {}, legs = {}, sales = {}, initialMoney = initial.money}

local function publish() result.Value = http:JSONEncode(report) end
local function finish(status: string, failure: string?)
	if report.status == "passed" or report.status == "failed" then return end
	report.status, report.failure, report.seconds = status, failure, os.clock() - started
	root.CFrame, root.Anchored = savedRoot, savedAnchored
	publish()
end
local function park() root.CFrame = savedRoot + Vector3.new(0, 20, 0) end

-- Every confirmed batch must be one of ours, at the expected place and stage.
local function checkpoint(label: string, expected: {[string]: {string}}): any
	local snapshot = lineState:Invoke()
	assert(snapshot.valid, "Invalid profile at " .. label)
	local count = 0
	for id, batch in snapshot.batches do
		count += 1
		local want = expected[id]
		assert(want and batch.locationId == want[1] and batch.stage == want[2] and batch.quantity == 1
			and batch.ownerUserId == player.UserId, label .. ": unexpected " .. id .. " at " .. batch.locationId)
	end
	local wanted = 0
	for _ in expected do wanted += 1 end
	assert(count == wanted, label .. ": expected " .. wanted .. " batches, found " .. count)
	table.insert(report.checkpoints, {label = label, money = snapshot.money, revision = snapshot.revision, batches = count})
	publish()
	return snapshot
end

local function stand(locationId: string)
	local mount = binding.mounts[locationId]
	if mount then
		local pad = mount.Parent :: BasePart
		local target = mount.WorldPosition
		for _, side in {1, -1} do
			local foot = target + pad.CFrame.RightVector * side * 3.5
			local position = Vector3.new(foot.X, target.Y - pad.Size.Y / 2 + 2.5, foot.Z)
			root.CFrame = CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
			if HandMoves.checkReach(player, {point = mount}, true) == nil then return end
		end
		error("Neither side of the parked trailer is reachable at " .. locationId)
	end
	local group, slot = locationId:match("^(%w+)%.(%w+)$")
	assert(group and slot, locationId)
	local place = if group == "Supplier" then pickup elseif group == "RawStore" then line.Stores.Rohstofflager
		elseif group == "FinishedStore" then line.Stores.Fertiglager else line.Stations[group]
	local marker = place.Standpoints[slot] :: BasePart
	local point = place[slot].Transfer :: Attachment
	local toward = ((point.WorldPosition - marker.Position) * FLAT).Unit
	local buffer = if group == "Supplier" or group == "RawStore" then 0.35
		elseif group == "FinishedStore" then 0.20 * SCALE else 0.15 * SCALE
	local position = marker.Position - toward * buffer + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, position + toward)
end

local function standAtPad(yardName: string)
	local annahme = yards[yardName].Annahme
	local marker = annahme.Standpoint :: BasePart
	local point = annahme.Pad.Transfer :: Attachment
	local toward = ((point.WorldPosition - marker.Position) * FLAT).Unit
	local position = marker.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, position + toward)
end

local function move(locationId: string, direction: "Take" | "Put")
	stand(locationId)
	local moveResult = lineTest:Invoke(locationId, direction).result
	assert(moveResult.ok, locationId .. " " .. direction .. " -> " .. moveResult.code)
end

local function waitFor(batchId: string, locationId: string, wareStage: State.Stage, seconds: number)
	local deadline = os.clock() + seconds
	repeat
		local batch = lineState:Invoke().batches[batchId]
		if batch and batch.locationId == locationId and batch.stage == wareStage then return end
		task.wait(0.25)
	until os.clock() > deadline or report.status == "failed"
	error("Timed out waiting for " .. wareStage .. " at " .. locationId)
end

local function buy(): string
	stand("Supplier.Slot1")
	local before = lineState:Invoke()
	local bought = purchase:Invoke()
	assert(bought.ok, "Supplier purchase failed: " .. bought.code)
	local after = lineState:Invoke()
	assert(after.money == before.money - 60, "Unexpected material debit")
	for id in after.batches do if not before.batches[id] then return id end end
	error("Purchase created no batch")
end

local function cargoView(slotId: string, batchId: string, wareStage: State.Stage): Model
	local view = wares:FindFirstChild(batchId)
	assert(view and view:IsA("Model") and view:GetAttribute("Signature") == wareStage .. "@" .. slotId, "Missing cargo view")
	local strap = view:FindFirstChild("LoadStrapTop")
	assert(strap and strap:IsA("BasePart") and strap.Transparency < 1, "Missing visible load strap")
	for _, part in view:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = part:FindFirstChildWhichIsA("WeldConstraint")
			assert(not part.Anchored and weld and weld.Part0 == binding.mounts[slotId].Parent, "Cargo is not welded to its slot")
		end
	end
	return view
end

local function armTransit(slots: {[string]: string}, wareStage: State.Stage, snapshot: any)
	local views, relative = {}, {}
	for slotId, batchId in slots do
		local view = cargoView(slotId, batchId, wareStage)
		views[slotId] = view
		relative[slotId] = binding.mounts[slotId].WorldCFrame:PointToObjectSpace(view:GetPivot().Position)
	end
	transit = {slots = slots, views = views, relative = relative, stage = wareStage, revision = snapshot.revision,
		money = snapshot.money, samples = 0, distance = 0, maxDrift = 0, lastPoint = chassis.Position * FLAT, lastSample = os.clock()}
	park()
end

local function sampleTravel(active: Transit)
	local snapshot = lineState:Invoke()
	assert(snapshot.revision == active.revision and snapshot.money == active.money, "Travel changed the confirmed inventory")
	for slotId, batchId in active.slots do
		local batch = snapshot.batches[batchId]
		assert(batch and batch.locationId == slotId and batch.stage == active.stage, "Cargo left its slot during travel")
		local view = cargoView(slotId, batchId, active.stage)
		assert(view == active.views[slotId], "Cargo was recreated during travel")
		local relative = binding.mounts[slotId].WorldCFrame:PointToObjectSpace(view:GetPivot().Position)
		active.maxDrift = math.max(active.maxDrift, (relative - active.relative[slotId]).Magnitude)
	end
	assert(active.maxDrift <= 0.05, "Cargo drifted off the mount")
	local _, serverOwned = Vehicles.motion(vehicle, binding, chassis)
	assert(serverOwned and not seat.Occupant, "Lost server physics or an avatar occupied the test seat")
	local point, now = chassis.Position * FLAT, os.clock()
	local distance, delta = (point - active.lastPoint).Magnitude, now - active.lastSample
	assert(delta <= 1.5 and distance <= 12 * SCALE * delta + 1.5, "Gap or position jump while hauling cargo")
	active.lastPoint, active.lastSample = point, now
	active.distance += distance
	active.samples += 1
end

local function finishTransit(leg: any): any
	local active = assert(transit, "Missing cargo observer")
	sampleTravel(active)
	assert(active.samples >= 10 and active.distance / SCALE >= 0.75 * leg.roadM, "Too little measured cargo travel")
	transit = nil
	return {stage = active.stage, revision = active.revision, money = active.money, distanceM = active.distance / SCALE,
		samples = active.samples, maxDriftStuds = active.maxDrift}
end

local function sell(slotId: string, buyer: string, yardName: string, amount: number, seed: number?): any
	stand(slotId)
	local opened = saleTest:Invoke("open", slotId, seed).result
	assert(opened.ok and opened.code == "OPEN", "Sale open at " .. buyer .. " -> " .. opened.code)
	local open = lineState:Invoke()
	local pending = open.pendingSale
	assert(pending and pending.buyer == buyer and pending.slotId == slotId, "Missing open sale")
	standAtPad(yardName)
	local sold = saleTest:Invoke("settle", buyer).result
	assert(sold.ok and sold.code == "SOLD", "Settlement at " .. buyer .. " -> " .. sold.code)
	local after = lineState:Invoke()
	local saleId, receipt = nil, nil
	for id, kept in after.saleReceipts do if kept.batchId == pending.batchId then saleId, receipt = id, kept end end
	assert(receipt and receipt.amount == amount and receipt.quantity == 1 and receipt.buyer == buyer
		and after.money == open.money + amount and after.batches[pending.batchId] == nil, "Wrong settlement at " .. buyer)
	table.insert(report.sales, {saleId = saleId, buyer = buyer, batchId = pending.batchId, slotId = slotId, amount = amount,
		quoteMin = receipt.quoteMin, quoteMax = receipt.quoteMax, dealerValue = receipt.dealerValue,
		moneyBefore = open.money, moneyAfter = after.money, revision = after.revision})
	publish()
	park()
	return after
end

local expectedStops = {"Supplier", "Workshop", "Dealer", "Private"}
local expectedRoutes = {{"Tischlerei_West", "Holzlieferant"}, {"Holzlieferant", "Tischlerei_West"},
	{"Tischlerei_West", "Moebelhandel"}, {"Moebelhandel", "Privatkunden"}}
stop.OnInvoke = function(index: number, leg: any): any
	if report.status == "failed" or report.status == "passed" then return false end
	local ok, failure = xpcall(function()
		assert(index == stage + 1 and expectedStops[index], "Unexpected route stop")
		local route = expectedRoutes[index]
		assert(leg.from == route[1] and leg.to == route[2], "Wrong road segment")
		assert(leg.zone.slotsInZone and leg.offPaved == 0 and leg.obstacleSamples == 0 and leg.zoneItemSamples == 0,
			"Route arrived with a missed zone or a contact")
		local still, serverOwned = Vehicles.motion(vehicle, binding, chassis)
		assert(still and serverOwned and Vehicles.zone(binding, zones) == expectedStops[index], "Rig is not parked in the expected zone")
		stage = index
		report.status = "running"
		local cargo = if transit then finishTransit(leg) else nil
		table.insert(report.legs, {from = leg.from, to = leg.to, roadM = leg.roadM, seconds = leg.seconds, zone = leg.zone, cargo = cargo})
		local one, two = batches[1], batches[2]
		if index == 1 then
			batches[1], batches[2] = buy(), buy()
			one, two = batches[1], batches[2]
			checkpoint("two purchases at the supplier", {[one] = {"Supplier.Slot1", "Holzpaket"}, [two] = {"Supplier.Slot2", "Holzpaket"}})
			move("Supplier.Slot1", "Take"); move(slotA, "Put")
			move("Supplier.Slot2", "Take"); move(slotB, "Put")
			armTransit({[slotA] = one, [slotB] = two}, "Holzpaket",
				checkpoint("wood loaded", {[one] = {slotA, "Holzpaket"}, [two] = {slotB, "Holzpaket"}}))
		elseif index == 2 then
			local arrived = checkpoint("wood at the workshop", {[one] = {slotA, "Holzpaket"}, [two] = {slotB, "Holzpaket"}})
			local raw: {[string]: string} = {}
			for id, reservation in arrived.reservations do
				if reservation.kind == "Delivery" then raw[reservation.batchId] = id end
			end
			assert(raw[one] and raw[two], "Missing paid delivery targets")
			move(slotA, "Take"); move(raw[one], "Put")
			move(slotB, "Take"); move(raw[two], "Put")
			local unloaded = checkpoint("wood unloaded", {[one] = {raw[one], "Holzpaket"}, [two] = {raw[two], "Holzpaket"}})
			assert(next(unloaded.reservations) == nil, "Delivery reservations did not release")
			local shelf = {[one] = "FinishedStore.Slot1", [two] = "FinishedStore.Slot2"}
			for _, batchId in {one, two} do
				local from = raw[batchId]
				for _, rule in State.STATIONS do
					move(from, "Take")
					move(rule.input, "Put")
					waitFor(batchId, rule.output, rule.outputStage, rule.durationSeconds + 4)
					from = rule.output
				end
				move(from, "Take")
				move(shelf[batchId], "Put")
			end
			checkpoint("two cartons stored", {[one] = {shelf[one], "Karton"}, [two] = {shelf[two], "Karton"}})
			move(shelf[one], "Take"); move(slotA, "Put")
			move(shelf[two], "Take"); move(slotB, "Put")
			armTransit({[slotA] = one, [slotB] = two}, "Karton",
				checkpoint("cartons loaded", {[one] = {slotA, "Karton"}, [two] = {slotB, "Karton"}}))
		elseif index == 3 then
			checkpoint("cartons at the dealer", {[one] = {slotA, "Karton"}, [two] = {slotB, "Karton"}})
			task.wait(0.75)
			local after = sell(slotA, "Dealer", "Moebelhandel", 100)
			armTransit({[slotB] = two}, "Karton", after)
		else
			checkpoint("carton at the private buyer", {[two] = {slotB, "Karton"}})
			task.wait(0.75)
			sell(slotB, "Private", "Privatkunden", 80, 0)
			checkpoint("everything sold", {})
			local again = buy()
			local final = checkpoint("new wood bought from the proceeds", {[again] = {"Supplier.Slot1", "Holzpaket"}})
			report.final = {money = final.money, revision = final.revision, newBatch = again}
			assert(final.money == 180 - 120 + 100 + 80 - 60, "Unexpected final balance")
			finish("passed", nil)
		end
	end, function(message: any): string return debug.traceback(tostring(message), 2) end)
	if not ok then finish("failed", failure) end
	return ok and report.status ~= "failed"
end

root.Anchored = true
park()
stop.Parent = storage
publish()
task.spawn(function()
	while report.status == "ready" or report.status == "running" do
		task.wait(0.20)
		if report.status == "passed" or report.status == "failed" then break end
		if os.clock() - started > 360 then finish("failed", "P07-08 proof timed out"); break end
		local routeResult = storage:FindFirstChild("P0602Result")
		if routeResult and routeResult:IsA("StringValue") and routeResult.Value ~= "" then
			local legReport = http:JSONDecode(routeResult.Value)
			if legReport.status == "aborted" then finish("failed", "Physical route runner aborted"); break end
		end
		local active = transit
		if active then
			local ok, failure = pcall(sampleTravel, active)
			if not ok then finish("failed", tostring(failure)) end
		end
	end
end)
return {started = true, ready = true, result = result.Name}
