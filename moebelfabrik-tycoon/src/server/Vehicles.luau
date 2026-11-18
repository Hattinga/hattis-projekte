--!strict
-- P06-03: the own vehicle's fixed load slots as inventory locations (LOGISTICS: trailer A/B, 1 package or 1 carton each).
local State = require(script.Parent.State)
local Vehicles = {}
Vehicles.SLOTS = table.freeze({"SlotA", "SlotB"})
Vehicles.STAGES = table.freeze({"Holzpaket", "Karton"}) :: {State.Stage}

export type Binding = {vehicleId: string, slotIds: {string}, locations: {[string]: State.Location}, mounts: {[string]: Attachment}}
export type Load = {used: number, capacity: number, full: boolean, batches: {[string]: string}}

function Vehicles.slotId(vehicleId: string, slot: string): string
	return "Vehicle." .. vehicleId .. "." .. slot
end

-- Binds the physical slots of one vehicle model. Mounts move with the trailer; views are welded to them.
function Vehicles.bind(vehicle: Instance, vehicleId: string): (Binding?, string?)
	if #vehicleId == 0 or #vehicleId > 32 or vehicleId:find("[^%w_]") then return nil, "INVALID_VEHICLE_ID" end
	local trailer = vehicle:FindFirstChild("Trailer")
	local slots = if trailer then trailer:FindFirstChild("Slots") else nil
	if not slots then return nil, "INVALID_VEHICLE" end
	local binding: Binding = {vehicleId = vehicleId, slotIds = {}, locations = {}, mounts = {}}
	for _, name in Vehicles.SLOTS do
		local pad = slots:FindFirstChild(name)
		local mount = if pad then pad:FindFirstChild("Transfer") else nil
		if not pad or not pad:IsA("BasePart") or pad.Anchored or not mount or not mount:IsA("Attachment") then
			return nil, "INVALID_SLOT:" .. name
		end
		local id = Vehicles.slotId(vehicleId, name)
		table.insert(binding.slotIds, id)
		binding.locations[id] = State.newLocation(id, "VehicleSlot", 1, Vehicles.STAGES)
		binding.mounts[id] = mount
	end
	return binding, nil
end

-- A slot counts as used while it holds a batch or is promised to one (Return reservation).
function Vehicles.load(state: State.Profile, slotIds: {string}): Load
	local used = 0
	local batches: {[string]: string} = {}
	for _, id in slotIds do
		local occupied = false
		for _, batch in state.batches do
			if batch.locationId == id then occupied = true; batches[id] = batch.id end
		end
		if occupied or state.reservations[id] then used += 1 end
	end
	return {used = used, capacity = #slotIds, full = used >= #slotIds, batches = batches}
end

return table.freeze(Vehicles)
