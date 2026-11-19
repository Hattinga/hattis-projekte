--!strict
-- P07 Studio proof. In a fresh Play server: set P06LoadingDemo=true and P07SaleStock=true, run
-- start-p05-09-line-demo, then this probe, then drive-p06-02-route (Workshop -> Dealer -> Private).
-- Result: JSON in ServerStorage.P07Result (poll until status is "passed" or "failed").
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
assert(runService:IsStudio() and runService:IsServer() and runService:IsRunning())
local storage = game:GetService("ServerStorage")
local http = game:GetService("HttpService")
local lineTest = storage:FindFirstChild("P0509LineTest") :: BindableFunction
local lineState = storage:FindFirstChild("P0509LineState") :: BindableFunction
local saleTest = storage:FindFirstChild("P07SaleTest") :: BindableFunction
assert(lineTest and lineState and saleTest, "Start a fresh P07 sale demo first")
assert(not storage:FindFirstChild("P07Result") and not storage:FindFirstChild("P07Stop"), "P07 probe already active")

local player = assert(game:GetService("Players"):GetPlayers()[1])
local character = assert(player.Character)
local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
assert(root and humanoid and not humanoid.SeatPart)
local factory = game:GetService("ServerScriptService").Factory
local HandMoves = require(factory.HandMoves)
local Vehicles = require(factory.Vehicles)
local vehicle = workspace.P02Vehicle
local binding = assert(Vehicles.bind(vehicle, "Quad1"))
local slotA, slotB = binding.slotIds[1], binding.slotIds[2]
local yards = workspace.CityGreybox.DeliveryYards
local pads = {Dealer = yards.Moebelhandel.Annahme, Private = yards.Privatkunden.Annahme}
local FLAT = Vector3.new(1, 0, 1)
local HAND = "Demo.Hand"

local initial = lineState:Invoke()
assert(initial.valid and initial.money == 180 and next(initial.reservations) == nil and initial.pendingSale == nil)
assert(initial.batches["Testkarton-1"].locationId == slotA and initial.batches["Testkarton-2"].locationId == slotB,
	"Expected P07SaleStock on both trailer slots")

local result = Instance.new("StringValue")
result.Name = "P07Result"
result.Parent = storage
local stop = Instance.new("BindableFunction")
stop.Name = "P07Stop"
local report: any = {status = "ready", checks = {}, initialMoney = initial.money}
local started = os.clock()
local savedRoot, savedAnchored = root.CFrame, root.Anchored
local stage = 0

local function publish()
	result.Value = http:JSONEncode(report)
end

local function finish(status: string, failure: string?)
	if report.status == "passed" or report.status == "failed" then return end
	report.status, report.failure, report.seconds = status, failure, os.clock() - started
	root.CFrame, root.Anchored = savedRoot, savedAnchored
	publish()
end

local function check(label: string, condition: any, detail: any?)
	assert(condition, label .. (if detail ~= nil then " -> " .. tostring(detail) else ""))
	table.insert(report.checks, label)
	publish()
end

local function park()
	root.CFrame = savedRoot + Vector3.new(0, 20, 0) -- Out of reach and out of the vehicle path.
end

local function standAtSlot(slotId: string)
	local mount = binding.mounts[slotId]
	local pad = mount.Parent :: BasePart
	local target = mount.WorldPosition
	for _, side in {1, -1} do
		local foot = target + pad.CFrame.RightVector * side * 3.5
		local position = Vector3.new(foot.X, target.Y - pad.Size.Y / 2 + 2.5, foot.Z)
		root.CFrame = CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
		if HandMoves.checkReach(player, {point = mount}, true) == nil then return end
	end
	error("Neither side of the parked trailer is reachable at " .. slotId)
end

local function standAtPad(buyer: string)
	local annahme = pads[buyer]
	local marker = annahme.Standpoint :: BasePart
	local point = annahme.Pad.Transfer :: Attachment
	local toward = ((point.WorldPosition - marker.Position) * FLAT).Unit
	local position = marker.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	root.CFrame = CFrame.lookAt(position, position + toward)
end

local function sale(action: string, arg: any, seed: number?): any
	return saleTest:Invoke(action, arg, seed)
end

local function same(left: any, right: any): boolean
	if type(left) ~= type(right) then return false end
	if type(left) ~= "table" then return left == right end
	for key, item in left do if not same(item, right[key]) then return false end end
	for key in right do if left[key] == nil then return false end end
	return true
end
-- Rejections must leave stock, money and revision exactly as they were.
local function unchanged(label: string, before: any)
	local after = lineState:Invoke()
	check(label, after.valid and after.revision == before.revision and after.money == before.money
		and same(after.batches, before.batches) and same(after.reservations, before.reservations), after.revision)
end

local function openSale(slotId: string, buyer: string, seed: number?): any
	standAtSlot(slotId)
	local opened = sale("open", slotId, seed).result
	check("open " .. slotId .. " at " .. buyer, opened.ok and opened.code == "OPEN", opened.code)
	local snapshot = lineState:Invoke()
	local pending = snapshot.pendingSale
	local held = nil
	for id, batch in snapshot.batches do if batch.locationId == HAND then held = id end end
	check("carton in hand with return to " .. slotId, snapshot.valid and pending and pending.buyer == buyer
		and pending.slotId == slotId and held == pending.batchId and snapshot.reservations[slotId]
		and snapshot.reservations[slotId].kind == "Return", held)
	return snapshot
end

local function settled(buyer: string, before: any, amount: number): any
	standAtPad(buyer)
	local sold = sale("settle", buyer)
	check("settle at " .. buyer .. " pad", sold.result.ok and sold.result.code == "SOLD"
		and sold.result.message:find("für " .. amount, 1, true) ~= nil, sold.result.message)
	local after = lineState:Invoke()
	local saleId, receipt = nil, nil
	for id, kept in after.saleReceipts do
		if kept.batchId == before.pendingSale.batchId then saleId, receipt = id, kept end
	end
	check(buyer .. " credited once", after.valid and after.money == before.money + amount and after.pendingSale == nil
		and after.batches[before.pendingSale.batchId] == nil and next(after.reservations) == nil
		and receipt and receipt.amount == amount and receipt.quantity == 1 and receipt.buyer == buyer, after.money)
	return after, saleId
end

stop.OnInvoke = function(index: number, leg: any): boolean
	if report.status == "failed" or report.status == "passed" then return false end
	local ok, failure = xpcall(function()
		assert(index == stage + 1, "Unexpected route stop")
		local expected = if index == 1 then "Dealer" else "Private"
		assert(leg.zone.slotsInZone and leg.offPaved == 0 and leg.obstacleSamples == 0, "Route arrived with a contact")
		assert(Vehicles.zone(binding, {Dealer = yards.Moebelhandel.LoadZone.Volume,
			Private = yards.Privatkunden.LoadZone.Volume}) == expected, "Rig is not parked at " .. expected)
		stage = index
		report.status = "running"
		table.insert(report.legs, {from = leg.from, to = leg.to, roadM = leg.roadM, seconds = leg.seconds,
			zone = leg.zone})
		task.wait(0.75) -- Let the observed stop settle into an arrival.
		if index == 1 then
			local before = lineState:Invoke()
			park()
			check("a sale from out of reach is refused", sale("open", slotB).result.code == "TOO_FAR")
			unchanged("distant attempt leaves stock and money", before)
			local open = openSale(slotB, "Dealer")
			local pending = open.pendingSale
			check("dealer offer before binding", pending.quoteMin == 100 and pending.quoteMax == 100
				and pending.dealerValue == 100 and open.money == 180, pending.quoteMin)
			check("offer shown in HUD and on the dealer pad", open.banner:find("Möbelhandel: 1 Hocker · Erlös 100", 1, true)
				and open.sellPrompts.Dealer.enabled and not open.sellPrompts.Private.enabled, open.banner)
			check("a second sale while carrying is refused", sale("open", slotA).result.code == "HANDS_FULL")
			unchanged("busy attempt leaves stock", open)
			check("settling away from the pad is refused", sale("settle", "Dealer").result.code == "TOO_FAR")
			standAtPad("Private")
			check("the other buyer's pad is refused", sale("settle", "Private").result.code == "WRONG_BUYER")
			unchanged("refused settlements pay nothing", open)
			standAtSlot(slotB)
			local cancelled = lineTest:Invoke(slotB, "Put").result
			check("cancel returns the carton to its slot", cancelled.ok and cancelled.code == "CANCELLED", cancelled.code)
			local back = lineState:Invoke()
			check("cancel keeps money and stock", back.valid and back.money == 180 and back.pendingSale == nil
				and back.batches["Testkarton-2"].locationId == slotB and next(back.reservations) == nil
				and not back.sellPrompts.Dealer.enabled, back.money)
			task.wait(1.0)
			local again = openSale(slotB, "Dealer")
			local after, saleId = settled("Dealer", again, 100)
			check("dealer receipt is shown only after the confirmed save", after.banner:find("für 100", 1, true), after.banner)
			check("a repeated confirmation pays nothing", sale("settle", "Dealer").result.code == "SALE_NOT_FOUND"
				and lineState:Invoke().money == 280)
			local replay = sale("replay", saleId).result
			check("the stored receipt answers a replay", replay.ok and replay.receipt.amount == 100
				and lineState:Invoke().money == 280, replay.code)
			report.dealer = {saleId = saleId, receipt = after.saleReceipts[saleId], money = after.money, revision = after.revision}
			park()
		else
			local open = openSale(slotA, "Private", 40)
			local pending = open.pendingSale
			check("private offer shows range and dealer value", pending.quoteMin == 80 and pending.quoteMax == 120
				and pending.dealerValue == 100 and open.banner:find("Privatkunde: 1 Hocker · 80–120 (Händler 100)", 1, true)
				and not open.banner:find("für 120", 1, true), open.banner)
			local after, saleId = settled("Private", open, 120)
			check("private price appears after the confirmed save", after.banner:find("für 120", 1, true), after.banner)
			check("the private price stays bound", sale("replay", saleId).result.receipt.amount == 120
				and lineState:Invoke().money == 400)
			report.private = {saleId = saleId, receipt = after.saleReceipts[saleId], money = after.money, revision = after.revision}
			local final = lineState:Invoke()
			local receipts = 0
			for _ in final.saleReceipts do receipts += 1 end
			check("both cartons sold once", final.valid and next(final.batches) == nil and receipts == 2
				and final.money == 400, receipts)
			report.final = {money = final.money, revision = final.revision}
			finish("passed", nil)
		end
	end, function(message: any): string return debug.traceback(tostring(message), 2) end)
	if not ok then finish("failed", failure) end
	return ok and report.status ~= "failed"
end

report.legs = {}
root.Anchored = true
standAtSlot(slotB)
local early = sale("open", slotB).result
check("no sale in the workshop yard", early.code == "NOT_AT_BUYER", early.code)
unchanged("workshop attempt leaves stock", initial)
park()
stop.Parent = storage
publish()
task.spawn(function()
	while report.status == "ready" or report.status == "running" do
		task.wait(0.5)
		if os.clock() - started > 200 then finish("failed", "P07 proof timed out"); break end
		local routeResult = storage:FindFirstChild("P0602Result")
		if routeResult and routeResult:IsA("StringValue") and routeResult.Value ~= "" then
			local legReport = http:JSONDecode(routeResult.Value)
			if legReport.status == "aborted" then finish("failed", "Physical route runner aborted"); break end
		end
	end
end)
return {started = true, result = result.Name}
