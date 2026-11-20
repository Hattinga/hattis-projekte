--!strict
-- P06-07: place the confirmed vehicle and its cargo at an upstream restart or collection point.
local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)
local Recovery = require(script.Parent.Recovery)
local Vehicles = require(script.Parent.Vehicles)

export type Rig = {model: Model, slots: Vehicles.Binding, replaced: boolean}
export type RecoveryPoint = {point: Attachment, stand: BasePart}

local VehicleRecovery = {}

function VehicleRecovery.rig(current: Instance?, template: Model): Rig
	local vehicleId = template:GetAttribute("VehicleId") :: string
	if current and current:IsA("Model") and current:GetAttribute("VehicleId") == vehicleId then
		local existing = Vehicles.bind(current, vehicleId)
		if existing then return {model = current, slots = existing, replaced = false} end
	end
	local replacement = template:Clone()
	local binding = assert(Vehicles.bind(replacement, vehicleId))
	if current then current.Parent = template.Parent end
	replacement.Name = "P02Vehicle"
	replacement.Parent = workspace
	return {model = replacement, slots = binding, replaced = true}
end

local function upstream(state: State.Profile): string
	for _, batch in state.batches do
		if batch.stage == "Holzpaket" and state.locations[batch.locationId].kind == "VehicleSlot" then
			return "Holzlieferant"
		end
	end
	for id, reservation in state.reservations do
		if reservation.kind == "Return" and reservation.stage == "Holzpaket" and state.locations[id].kind == "VehicleSlot" then
			return "Holzlieferant"
		end
	end
	return "Tischlerei_West"
end

function VehicleRecovery.restore(
	snapshot: Persistence.Result,
	ownerUserId: number,
	now: number,
	rig: Rig,
	yards: Instance,
	fixedPoints: {[string]: Attachment},
	carrier: BasePart,
	carrierId: string,
	workerCarrier: BasePart?
): ({[string]: RecoveryPoint}?, string)
	local saved = snapshot.confirmed
	if not snapshot.ok or snapshot.status ~= "Confirmed" or snapshot.inFlight or snapshot.unknown or not saved then
		return nil, "NOT_CONFIRMED"
	end
	local state = saved.data.state
	if state.ownerUserId ~= ownerUserId or not State.validate(state) then return nil, "INVALID_STATE" end
	local yard = yards:FindFirstChild(upstream(state))
	if not yard or not yard:IsA("BasePart") then return nil, "YARD_MISSING" end
	local zone = yard:FindFirstChild("LoadZone")
	local volume = if zone then zone:FindFirstChild("Volume") else nil
	local entry = if zone then zone:GetAttribute("EntryLocal") else nil
	local pads = yard:FindFirstChild("VehicleRecovery")
	local stands = if pads then pads:FindFirstChild("Standpoints") else nil
	if not volume or not volume:IsA("BasePart") or typeof(entry) ~= "Vector3" or not pads or not stands then
		return nil, "RECOVERY_FIXTURE_MISSING"
	end
	local original: {[string]: string} = {[carrierId] = carrier:GetFullName()}
	if workerCarrier and workerCarrier:IsDescendantOf(workspace) then
		original[State.FIRST_WORKER.carrier] = workerCarrier:GetFullName()
	end
	for id, point in fixedPoints do
		if point:IsDescendantOf(workspace) then original[id] = point:GetFullName() end
	end
	local alternatives: {[string]: string} = {}
	local endpoints: {[string]: RecoveryPoint} = {}
	for _, id in rig.slots.slotIds do
		local mount = rig.slots.mounts[id]
		if not rig.replaced then
			original[id] = mount:GetFullName()
			continue
		end
		local part = mount.Parent
		local pad = if part then pads:FindFirstChild(part.Name) else nil
		local walk = if part then stands:FindFirstChild(part.Name) else nil
		local point = if pad then pad:FindFirstChild("Transfer") else nil
		if not point or not point:IsA("Attachment") or not walk or not walk:IsA("BasePart") then
			return nil, "RECOVERY_FIXTURE_MISSING"
		end
		alternatives[id] = point:GetFullName()
		endpoints[id] = {point = point, stand = walk}
	end
	local plan = Recovery.plan(snapshot, ownerUserId, now, original, alternatives)
	if not plan.ok or not plan.placements then return nil, plan.code end
	local active: {[string]: RecoveryPoint} = {}
	for _, placement in plan.placements do
		if placement.atRecoveryPoint then active[placement.locationId] = endpoints[placement.locationId] end
	end
	for id in state.reservations do
		if endpoints[id] then active[id] = endpoints[id] end
	end

	local position = Vector3.new(yard.Position.X, rig.model:GetPivot().Position.Y, yard.Position.Z)
	rig.model:PivotTo(CFrame.lookAt(position, position + yard.CFrame:VectorToWorldSpace(entry)))
	Vehicles.useServerPhysics(rig.model)
	if not Vehicles.zone(rig.slots, {Start = volume}) then return nil, "UNSAFE_RESTART" end
	return active, yard.Name
end

return table.freeze(VehicleRecovery)
