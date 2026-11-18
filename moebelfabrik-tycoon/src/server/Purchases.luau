--!strict
-- P05-02: one confirmed material purchase. The server supplies the actor and registered physical slots.
local State = require(script.Parent.State)
local Persistence = require(script.Parent.Persistence)

export type Receipt = {ok: boolean, code: string, message: string, revision: number, batchId: string,
	supplierId: string, rawSlotId: string, price: number}
export type Result = {ok: boolean, code: string, receipt: Receipt?, unknown: boolean}
export type Slots = {supplierIds: {string}, rawIds: {string}}
export type Binding = {slots: Slots, locations: {[string]: State.Location}, points: {[string]: Attachment}}

local Purchases = {}
local PRICE = 60 -- Prototype test economy; only new purchases use the current price.
local MAX_INTEGER = 9007199254740991

-- Build the trusted slot list from the physical fixtures, once per workshop.
function Purchases.bind(supplier: Instance, rawStore: Instance): (Binding?, string?)
	if supplier == rawStore then return nil, "INVALID_REGISTRY" end
	local binding: Binding = {slots = {supplierIds = {}, rawIds = {}}, locations = {}, points = {}}
	for _, spec in {{root = supplier, kind = "Supplier", ids = binding.slots.supplierIds},
		{root = rawStore, kind = "RawStore", ids = binding.slots.rawIds}} do
		for index = 1, 4 do
			local name = "Slot" .. index
			local id = spec.kind .. "." .. name
			local pad = spec.root:FindFirstChild(name)
			local point = if pad then pad:FindFirstChild("Transfer") else nil
			if not pad or not pad:IsA("BasePart") or pad:GetAttribute("Capacity") ~= 1
				or not point or not point:IsA("Attachment") then
				return nil, "INVALID_POINT:" .. id
			end
			table.insert(spec.ids, id)
			binding.locations[id] = State.newLocation(id, spec.kind, 1, {"Holzpaket"})
			binding.points[id] = point
		end
	end
	return binding, nil
end

local function rejected(code: string, unknown: boolean?): Result
	return {ok = false, code = code, unknown = unknown == true}
end

local function firstFree(state: State.Profile, ids: {string}, kind: string, unavailable: {[string]: boolean}): string?
	for _, id in ids do
		local location = state.locations[id]
		if location and location.kind == kind and table.find(location.acceptedStages, "Holzpaket") and not unavailable[id] then
			return id
		end
	end
	return nil
end

function Purchases.buy(controller: Persistence.Controller, actor: any, request: any, slots: Slots, ttlSeconds: number): Result
	if type(actor) ~= "table" or getmetatable(actor) ~= nil or actor.ready ~= true then return rejected("NOT_READY") end
	local snapshot = controller.snapshot()
	local confirmed = snapshot.confirmed
	if not confirmed or snapshot.status ~= "Confirmed" or snapshot.inFlight then
		return rejected("NOT_CONFIRMED", snapshot.unknown)
	end
	local candidate = confirmed.data
	local state = candidate.state
	if actor.kind ~= "Player" or actor.ownerUserId ~= state.ownerUserId
		or actor.actorId ~= "Player/" .. string.format("%.0f", state.ownerUserId) then
		return rejected("NOT_AUTHORIZED")
	end
	if type(request) ~= "table" or getmetatable(request) ~= nil then return rejected("INVALID_REQUEST") end
	for key in request do
		if key ~= "operationId" and key ~= "expectedRevision" then return rejected("INVALID_REQUEST") end
	end
	local operationId, revision = request.operationId, request.expectedRevision
	if type(operationId) ~= "string" or #operationId < 1 or #operationId > 119 or utf8.len(operationId) == nil
		or type(revision) ~= "number" or revision % 1 ~= 0 or revision < 0 or revision > MAX_INTEGER then
		return rejected("INVALID_REQUEST")
	end
	local replay = state.receipts[operationId]
	if replay then
		if replay.action ~= "Purchase" or replay.actorId ~= actor.actorId or replay.request.expectedRevision ~= revision then
			return rejected("OPERATION_CONFLICT")
		end
		return {ok = true, code = "PURCHASED", receipt = replay.result, unknown = false}
	end
	if revision ~= state.revision then return rejected("STALE_REVISION") end
	if revision == MAX_INTEGER then return rejected("REVISION_OVERFLOW") end
	local batchId = "purchase/" .. operationId
	if state.batches[batchId] then return rejected("OPERATION_CONFLICT") end
	if state.money < PRICE then return rejected("NOT_ENOUGH_MONEY") end
	local unavailable: {[string]: boolean} = {}
	for locationId, reservation in state.reservations do
		if reservation.kind == "Delivery" and reservation.purchaseOperationId == operationId then
			return rejected("OPERATION_CONFLICT")
		end
		unavailable[locationId] = true
	end
	for _, claim in state.claims do
		unavailable[claim.sourceId], unavailable[claim.targetId] = true, true
	end
	for _, batch in state.batches do unavailable[batch.locationId] = true end
	local supplierId = firstFree(state, slots.supplierIds, "Supplier", unavailable)
	if not supplierId then return rejected("SUPPLIER_FULL") end
	local rawSlotId = firstFree(state, slots.rawIds, "RawStore", unavailable)
	if not rawSlotId then return rejected("RAW_STORE_FULL") end

	local receipt: Receipt = {ok = true, code = "PURCHASED", message = "Holzpaket beim Lieferanten bereit.",
		revision = revision + 1, supplierId = supplierId, rawSlotId = rawSlotId, batchId = batchId, price = PRICE}
	state.money -= PRICE
	state.revision += 1
	state.batches[batchId] = State.newBatch(batchId, state.ownerUserId, "Holzpaket", supplierId)
	state.reservations[rawSlotId] = {kind = "Delivery", batchId = batchId, purchaseOperationId = operationId}
	state.receipts[operationId] = {actorId = actor.actorId, actorKind = "Player", ownerUserId = state.ownerUserId,
		action = "Purchase", request = {operationId = operationId, expectedRevision = revision}, result = receipt}

	local saved = controller.save(candidate, ttlSeconds)
	if not saved.ok then return rejected(saved.code, saved.unknown) end
	return {ok = true, code = "PURCHASED", receipt = receipt, unknown = false}
end

return table.freeze(Purchases)
