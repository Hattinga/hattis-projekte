--!strict
-- Run A, B, C in separate Studio Play starts with the same isolated P0607 scope.
return function(phase: string, previous: any?): any
	assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
	local rs = game:GetService("RunService")
	assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning() and workspace:GetAttribute("P0607ResumeScope"))
	assert(phase == "A" or phase == "B" or phase == "C")
	local storage = game:GetService("ServerStorage")
	assert(not storage:FindFirstChild("P0607Result"))
	local result = Instance.new("StringValue")
	result.Name = "P0607Result"
	result.Parent = storage
	local http = game:GetService("HttpService")
	local user = game:GetService("Players"):GetPlayers()[1]
	local root = assert(user.Character):FindFirstChild("HumanoidRootPart") :: BasePart
	local vehicle = workspace.P02Vehicle
	local supplier = workspace.CityGreybox.DeliveryYards.Holzlieferant
	local factory = game:GetService("ServerScriptService").Factory
	local Vehicles = require(factory.Vehicles)
	local slots = assert(Vehicles.bind(vehicle, "Quad1"))
	local slotA, slotB = slots.slotIds[1], slots.slotIds[2]
	local read = storage.P0509LineState :: BindableFunction
	local move = storage.P0509LineTest :: BindableFunction
	local buy = storage.P060405Purchase :: BindableFunction
	local close = storage.P0607Release :: BindableFunction
	local supply = supplier.P05Pickup
	local flat = Vector3.new(1, 0, 1)
	local function at(point: Attachment, stand: BasePart?)
		local target = point.WorldPosition
		local mount = point.Parent :: BasePart
		local foot = if stand then stand.Position + ((stand.Position - target) * flat).Unit * 0.35
			else target + mount.CFrame.RightVector * 3.5
		local position = Vector3.new(foot.X, if stand then stand.Position.Y + 3 else 3.25, foot.Z)
		root.CFrame = CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
	end
	local function act(id: string, direction: "Take" | "Put", expected: string?, alternate: boolean?): any
		if alternate then
			local pad = (slots.mounts[id].Parent :: BasePart).Name
			local recovery = supplier.VehicleRecovery
			at(recovery[pad].Transfer, recovery.Standpoints[pad])
		elseif slots.mounts[id] then
			at(slots.mounts[id], nil)
		else
			local kind, name = id:match("^(%w+)%.(%w+)$")
			assert(name)
			local group = if kind == "Supplier" then supply else workspace.P02Line.Stores.Rohstofflager
			at(group[name].Transfer, group.Standpoints[name])
		end
		local before = read:Invoke()
		local reply = move:Invoke(id, direction, alternate)
		assert(if expected then reply.result.code == expected else reply.result.ok, id .. " " .. reply.result.code)
		if expected then assert(reply.revision == before.revision) end
		return reply
	end
	local function purchase(): string
		at(supply.Slot1.Transfer, supply.Standpoints.Slot1)
		local response = buy:Invoke()
		assert(response.ok, response.code)
		for id, batch in read:Invoke().batches do
			if batch.locationId == "Supplier.Slot1" then return id end
		end
		error("Missing purchased batch")
	end
	local function expectMount(id: string, slot: string)
		local model = workspace.P0509LineDemo.Wares:FindFirstChild(id)
		local view = if model then model:FindFirstChildWhichIsA("WeldConstraint", true) else nil
		assert(view and view.Part0 == slots.mounts[slot].Parent, "Missing attachment to " .. slot)
	end

	task.spawn(function()
		local report: any = {status = "running", phase = phase, checks = {}}
		local savedAnchor, savedPosition = root.Anchored, root.CFrame
		root.Anchored = true
		local ok, problem = xpcall(function()
			local zone = {Supplier = supplier.LoadZone.Volume}
			local a, b, loose
			if phase == "A" then
				assert(next(read:Invoke().batches) == nil, "Use a fresh test scope")
				local entry = supplier.LoadZone:GetAttribute("EntryLocal") :: Vector3
				local position = Vector3.new(supplier.Position.X, vehicle:GetPivot().Position.Y, supplier.Position.Z)
				vehicle:PivotTo(CFrame.lookAt(position, position + supplier.CFrame:VectorToWorldSpace(entry)))
				Vehicles.useServerPhysics(vehicle)
				a = purchase()
				act("Supplier.Slot1", "Take")
				act(slotA, "Put")
				b = purchase()
				act("Supplier.Slot1", "Take")
				act(slotB, "Put")
				loose = purchase()
				expectMount(a, slotA)
				expectMount(b, slotB)
				root.CFrame = savedPosition
				local chassis = vehicle.Quad.Chassis :: BasePart
				local start = chassis.Position
				local deadline = os.clock() + 10
				vehicle.Quad:SetAttribute("TestThrottle", 0.45)
				repeat task.wait(0.1) until not Vehicles.zone(slots, zone) or os.clock() > deadline
				vehicle.Quad:SetAttribute("TestThrottle", 0)
				assert(not Vehicles.zone(slots, zone), "The truck did not leave its start yard")
				report.travelledM = (chassis.Position - start).Magnitude * 7 / 25
				table.insert(report.checks, "loaded two paid packages, left the supplier yard and retained a third package at pickup")
			else
				assert(previous and previous.ids)
				a, b, loose = previous.ids.a, previous.ids.b, previous.ids.loose
				assert(Vehicles.zone(slots, zone) == "Supplier", "Restore must begin upstream")
				local view = read:Invoke()
				assert(view.revision == previous.stateRevision and view.money == 0)
				assert(view.batches[a].locationId == slotA and view.batches[loose].locationId == "Supplier.Slot1")
				assert(next(view.arrivals) == nil)
				if phase == "B" then
					assert(not view.recoverySlots and view.batches[b].locationId == slotB)
					expectMount(a, slotA)
					expectMount(b, slotB)
					table.insert(report.checks, "second server restored both exact trailer slots, supplier stock and purchase reservations")
					act(slotB, "Take")
				else
					assert(view.recoverySlots and view.batches[b].locationId == "Demo.Hand")
					assert(view.reservations[slotB].kind == "Return" and view.reservations[slotB].batchId == b)
					local shown = workspace.P0509LineDemo.Wares:FindFirstChild(a) :: Model
					local pad = supplier.VehicleRecovery.SlotA :: BasePart
					local position = shown:GetBoundingBox().Position
					assert(not view.views[a].carried and ((position - pad.Position) * flat).Magnitude < 0.05)
					act(slotB, "Put", nil, true) -- same promised pad remains available after rejoin
					act(slotB, "Take", nil, true)
					act(slotB, "Put")
					expectMount(b, slotB)
					act(slotA, "Take", "RECOVERY_REQUIRED")
					act(slotA, "Take", nil, true)
					local rawId = nil
					for id, reserve in read:Invoke().reservations do
						if reserve.kind == "Delivery" and reserve.batchId == a then rawId = id end
					end
					act(assert(rawId), "Put", "WRONG_LOADING_ROUTE")
					act(slotA, "Put")
					expectMount(a, slotA)
					assert(not read:Invoke().recoverySlots)
					table.insert(report.checks, "missing mount used an exclusive recovery pad; both packages physically returned to the replacement rig")
				end
			end
			local state = read:Invoke()
			local count, promises = 0, 0
			for _, batch in state.batches do
				count += 1
				assert(not batch.locationId:find("^RawStore"))
			end
			for _, reservation in state.reservations do
				if reservation.kind == "Delivery" then promises += 1 end
			end
			assert(state.valid and state.money == 0 and count == 3 and promises == 3 and next(state.arrivals) == nil)
			local released = close:Invoke()
			assert(released.ok and released.code == "RELEASED", released.code)
			report.ids = {a = a, b = b, loose = loose}
			report.stateRevision = state.revision
			report.storageRevision = released.confirmed.revision
			report.source = if phase == "A" then "road" else "supplier"
		end, function(err: any): string return debug.traceback(tostring(err), 2) end)
		vehicle.Quad:SetAttribute("TestThrottle", 0)
		root.CFrame, root.Anchored = savedPosition, savedAnchor
		report.status = if ok then "passed" else "failed"
		report.failure = problem
		result.Value = http:JSONEncode(report)
	end)
	return {phase = phase, started = true}
end
