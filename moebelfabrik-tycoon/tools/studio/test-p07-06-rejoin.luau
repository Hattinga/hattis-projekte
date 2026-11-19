--!strict
-- P07-06: sales across a server change. Run A and B in separate Studio Play starts with the same new
-- P0607ResumeScope. A additionally needs P07SaleStock=true and the route runner (drive-p06-02-route) after it.
-- Before each phase: P06LoadingDemo=true, the scope attribute, then start-p05-09-line-demo.
-- Result: JSON in ServerStorage.P0706Result (status "passed" or "failed"); pass A's result table into B.
return function(phase: string, previous: any?): any
	assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
	local rs = game:GetService("RunService")
	assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning() and workspace:GetAttribute("P0607ResumeScope"))
	assert(phase == "A" or (phase == "B" and type(previous) == "table"))
	local storage = game:GetService("ServerStorage")
	assert(not storage:FindFirstChild("P0706Result") and not storage:FindFirstChild("P07Stop"))
	local http = game:GetService("HttpService")
	local result = Instance.new("StringValue")
	result.Name = "P0706Result"
	result.Parent = storage
	local player = assert(game:GetService("Players"):GetPlayers()[1])
	local root = assert(player.Character):FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
	local factory = game:GetService("ServerScriptService").Factory
	local HandMoves = require(factory.HandMoves)
	local Vehicles = require(factory.Vehicles)
	local vehicle = workspace.P02Vehicle
	local binding = assert(Vehicles.bind(vehicle, "Quad1"))
	local slotA, slotB = binding.slotIds[1], binding.slotIds[2]
	local yards = workspace.CityGreybox.DeliveryYards
	local read = storage.P0509LineState :: BindableFunction
	local move = storage.P0509LineTest :: BindableFunction
	local sale = storage.P07SaleTest :: BindableFunction
	local release = storage.P0607Release :: BindableFunction
	local FLAT = Vector3.new(1, 0, 1)
	local HAND = "Demo.Hand"
	local function same(left: any, right: any): boolean
		if type(left) ~= type(right) then return false end
		if type(left) ~= "table" then return left == right end
		for key, item in left do if not same(item, right[key]) then return false end end
		for key in right do if left[key] == nil then return false end end
		return true
	end
	local report: any = {phase = phase, status = "running", checks = {}}
	local savedRoot, savedAnchored = root.CFrame, root.Anchored
	local function publish() result.Value = http:JSONEncode(report) end
	local function check(label: string, condition: any, detail: any?)
		assert(condition, label .. (if detail ~= nil then " -> " .. tostring(detail) else ""))
		table.insert(report.checks, label)
		publish()
	end
	local function finish(status: string, failure: string?)
		if report.status ~= "running" then return end
		report.status, report.failure = status, failure
		root.CFrame, root.Anchored = savedRoot, savedAnchored
		publish()
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
	local function standAtPad(yardName: string)
		local annahme = yards[yardName].Annahme
		local marker = annahme.Standpoint :: BasePart
		local point = annahme.Pad.Transfer :: Attachment
		local toward = ((point.WorldPosition - marker.Position) * FLAT).Unit
		local position = marker.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
		root.CFrame = CFrame.lookAt(position, position + toward)
	end
	local function heldId(snapshot: any): string?
		for id, batch in snapshot.batches do if batch.locationId == HAND then return id end end
		return nil
	end
	local function guarded(body: () -> ())
		local ok, failure = xpcall(body, function(message: any): string return debug.traceback(tostring(message), 2) end)
		if not ok then finish("failed", failure) end
	end
	root.Anchored = true

	if phase == "A" then
		local initial = read:Invoke()
		check("fresh scope starts with two test cartons", initial.valid and initial.money == 180 and initial.pendingSale == nil
			and initial.batches["Testkarton-1"].locationId == slotA and initial.batches["Testkarton-2"].locationId == slotB)
		root.CFrame = savedRoot + Vector3.new(0, 20, 0)
		local stop = Instance.new("BindableFunction")
		stop.Name = "P07Stop"
		stop.OnInvoke = function(index: number, leg: any): any
			if index ~= 1 or report.status ~= "running" then return false end
			guarded(function()
				assert(leg.to == "Moebelhandel" and leg.zone.slotsInZone and leg.offPaved == 0 and leg.obstacleSamples == 0)
				task.wait(0.75)
				standAtSlot(slotB)
				check("open the first carton at the dealer", sale:Invoke("open", slotB).result.code == "OPEN")
				standAtPad("Moebelhandel")
				local sold = sale:Invoke("settle", "Dealer").result
				check("first carton paid", sold.ok and sold.code == "SOLD", sold.code)
				local paid = read:Invoke()
				local paidId, receipt = next(paid.saleReceipts)
				check("paid state", paid.valid and paid.money == 280 and receipt and receipt.amount == 100, paid.money)
				standAtSlot(slotA)
				check("open the second carton", sale:Invoke("open", slotA, 7).result.code == "OPEN")
				local open = read:Invoke()
				check("second sale open with the carton in hand", open.valid and open.pendingSale
					and heldId(open) == "Testkarton-1" and open.reservations[slotA] and open.money == 280)
				local released = release:Invoke()
				check("session released for the server change", released.ok and released.status == "Released", released.code)
				report.paidSaleId, report.paidReceipt = paidId, receipt
				report.openSale = open.pendingSale
				report.money, report.revision = open.money, open.revision
				finish("passed", nil)
			end)
			return if report.status == "passed" then "stop" else false
		end
		stop.Parent = storage
		publish()
		return {started = true, phase = "A"}
	end

	guarded(function()
		local prior = previous :: any
		local snapshot = read:Invoke()
		local kept = snapshot.pendingSale
		check("open sale restored with the same hidden roll and quote", snapshot.valid and kept and kept.id == prior.openSale.id
			and kept.seed == prior.openSale.seed and kept.quoteMin == 100 and kept.slotId == slotA, kept and kept.id)
		check("carton restored in the hand with its return", heldId(snapshot) == "Testkarton-1"
			and snapshot.reservations[slotA] and snapshot.reservations[slotA].kind == "Return")
		check("paid sale and money kept", snapshot.money == prior.money and snapshot.revision == prior.revision
			and snapshot.batches["Testkarton-2"] == nil
			and same(snapshot.saleReceipts[prior.paidSaleId], prior.paidReceipt), snapshot.money)
		check("HUD names the open sale", snapshot.banner:find("Offener Verkauf", 1, true) ~= nil, snapshot.banner)
		standAtPad("Moebelhandel")
		local blocked = sale:Invoke("settle", "Dealer").result
		check("a restored hand load cannot be settled without a new delivery", blocked.code == "PICKUP_REQUIRED", blocked.code)
		local replay = sale:Invoke("replay", prior.paidSaleId).result
		check("the paid sale answers with its stored receipt", replay.ok and replay.code == "SOLD"
			and same(replay.receipt, prior.paidReceipt), replay.code)
		local unchangedState = read:Invoke()
		check("no second payout", unchangedState.money == prior.money and unchangedState.revision == prior.revision)
		standAtSlot(slotA)
		local returned = move:Invoke(slotA, "Put").result
		check("the carton goes back onto its trailer slot", returned.ok and returned.code == "CANCELLED", returned.code)
		local final = read:Invoke()
		check("cancel after the server change keeps stock and money", final.valid and final.pendingSale == nil
			and final.batches["Testkarton-1"].locationId == slotA and next(final.reservations) == nil
			and final.money == prior.money, final.money)
		local released = release:Invoke()
		check("session released", released.ok, released.code)
		report.money, report.revision = final.money, final.revision
		finish("passed", nil)
	end)
	return report
end
