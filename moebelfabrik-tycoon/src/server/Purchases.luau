--!strict
-- P05-02: one confirmed material purchase. The server supplies the actor and registered physical slots.
-- P07-07: a limited material advance for a workshop without money for material and without any stock.
local State = require(script.Parent.State)
local Recipes = require(script.Parent.Recipes)
local Persistence = require(script.Parent.Persistence)

export type Receipt = {ok: boolean, code: string, message: string, revision: number, batchId: string,
	supplierId: string, rawSlotId: string, price: number}
export type Result = {ok: boolean, code: string, receipt: Receipt?, unknown: boolean}
export type AdvanceReceipt = {ok: boolean, code: string, message: string, revision: number, batchId: string,
	supplierId: string, rawSlotId: string, amount: number}
export type AdvanceResult = {ok: boolean, code: string, receipt: AdvanceReceipt?, unknown: boolean}
export type Slots = {supplierIds: {string}, rawIds: {string}}
export type Binding = {slots: Slots, locations: {[string]: State.Location}, points: {[string]: Attachment}}

local Purchases = {}
Purchases.PRICE = assert(Recipes.get(Recipes.DEFAULT_ID)).price -- Prototype test economy (Hocker01); only new purchases use the current price.
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

local function rejected(code: string, unknown: boolean?): any
	return {ok = false, code = code, unknown = unknown == true}
end

local function firstFree(state: State.Profile, ids: {string}, kind: string, unavailable: {[string]: boolean}): string?
	for _, id in ids do
		local location = state.locations[id]
		if location and location.kind == kind and table.find(location.acceptedStages, "Holzpaket" :: State.Stage) and not unavailable[id] then
			return id
		end
	end
	return nil
end

type Opened = {candidate: any, state: State.Profile, operationId: string, revision: number}

-- Shared entry of buy and advance: ready own player, confirmed idle session, closed request, then replay.
-- A stored receipt of the same action answers before any current-state check.
local function open(controller: Persistence.Controller, actor: any, request: any, action: string, code: string,
	prefix: string): (Opened?, any)
	if type(actor) ~= "table" or getmetatable(actor) ~= nil or actor.ready ~= true then return nil, rejected("NOT_READY") end
	local snapshot = controller.snapshot()
	local confirmed = snapshot.confirmed
	if not confirmed or snapshot.status ~= "Confirmed" or snapshot.inFlight then
		return nil, rejected("NOT_CONFIRMED", snapshot.unknown)
	end
	local candidate = confirmed.data
	local state = candidate.state
	if actor.kind ~= "Player" or actor.ownerUserId ~= state.ownerUserId
		or actor.actorId ~= "Player/" .. string.format("%.0f", state.ownerUserId) then
		return nil, rejected("NOT_AUTHORIZED")
	end
	if type(request) ~= "table" or getmetatable(request) ~= nil then return nil, rejected("INVALID_REQUEST") end
	for key in request do
		if key ~= "operationId" and key ~= "expectedRevision" then return nil, rejected("INVALID_REQUEST") end
	end
	local operationId, revision = request.operationId, request.expectedRevision
	-- The batch ID "<prefix><operationId>" must stay within the 128-byte identifier limit.
	if type(operationId) ~= "string" or #operationId < 1 or #operationId > 128 - #prefix or utf8.len(operationId) == nil
		or type(revision) ~= "number" or revision % 1 ~= 0 or revision < 0 or revision > MAX_INTEGER then
		return nil, rejected("INVALID_REQUEST")
	end
	local replay = state.receipts[operationId]
	if replay then
		if replay.action ~= action or replay.actorId ~= actor.actorId or replay.request.expectedRevision ~= revision then
			return nil, rejected("OPERATION_CONFLICT")
		end
		return nil, {ok = true, code = code, receipt = replay.result, unknown = false}
	end
	return {candidate = candidate, state = state, operationId = operationId, revision = revision}, nil
end

-- The first free supplier pickup and raw slot. Old claims count as occupied until they are cleaned up.
local function freeSlots(state: State.Profile, operationId: string, slots: Slots): (string?, string?, string?)
	local unavailable: {[string]: boolean} = {}
	for locationId, reservation in state.reservations do
		if reservation.kind == "Delivery" and reservation.purchaseOperationId == operationId then
			return nil, nil, "OPERATION_CONFLICT"
		end
		unavailable[locationId] = true
	end
	for _, claim in state.claims do
		unavailable[claim.sourceId], unavailable[claim.targetId] = true, true
	end
	for _, batch in state.batches do unavailable[batch.locationId] = true end
	local supplierId = firstFree(state, slots.supplierIds, "Supplier", unavailable)
	if not supplierId then return nil, nil, "SUPPLIER_FULL" end
	local rawSlotId = firstFree(state, slots.rawIds, "RawStore", unavailable)
	if not rawSlotId then return nil, nil, "RAW_STORE_FULL" end
	return supplierId, rawSlotId, nil
end

-- P10-02: the line's selected recipe decides which package the supplier sells and what it costs.
local function selectedRecipe(candidate: any): Recipes.Recipe
	local progress = candidate.progress
	return Recipes.get(if progress then progress.selectedRecipeId else nil) or assert(Recipes.get(Recipes.DEFAULT_ID))
end

-- New Holzpaket at the supplier, Delivery promise to the raw slot and the receipt, as one candidate.
local function supply(opened: Opened, actor: any, action: string, batchId: string, supplierId: string,
	rawSlotId: string, receipt: any, recipeId: string)
	local state, operationId = opened.state, opened.operationId
	state.revision += 1
	state.batches[batchId] = State.newBatch(batchId, state.ownerUserId, "Holzpaket", supplierId, recipeId)
	state.reservations[rawSlotId] = {kind = "Delivery", batchId = batchId, purchaseOperationId = operationId}
	state.receipts[operationId] = {actorId = actor.actorId, actorKind = "Player", ownerUserId = state.ownerUserId,
		action = action, request = {operationId = operationId, expectedRevision = opened.revision}, result = receipt}
end

function Purchases.buy(controller: Persistence.Controller, actor: any, request: any, slots: Slots, ttlSeconds: number): Result
	local opened, answer = open(controller, actor, request, "Purchase", "PURCHASED", "purchase/")
	if not opened then return answer end
	local state, operationId, revision = opened.state, opened.operationId, opened.revision
	if revision ~= state.revision then return rejected("STALE_REVISION") end
	if revision == MAX_INTEGER then return rejected("REVISION_OVERFLOW") end
	local batchId = "purchase/" .. operationId
	if state.batches[batchId] then return rejected("OPERATION_CONFLICT") end
	local recipe = selectedRecipe(opened.candidate)
	if state.money < recipe.price then return rejected("NOT_ENOUGH_MONEY") end
	local supplierId, rawSlotId, problem = freeSlots(state, operationId, slots)
	if not supplierId or not rawSlotId then return rejected(problem :: string) end

	local receipt: Receipt = {ok = true, code = "PURCHASED", message = recipe.packageName .. " beim Lieferanten bereit.",
		revision = revision + 1, supplierId = supplierId, rawSlotId = rawSlotId, batchId = batchId, price = recipe.price}
	state.money -= recipe.price
	supply(opened, actor, "Purchase", batchId, supplierId, rawSlotId, receipt, recipe.id)

	local saved = controller.save(opened.candidate, ttlSeconds)
	if not saved.ok then return rejected(saved.code, saved.unknown) end
	return {ok = true, code = "PURCHASED", receipt = receipt, unknown = false}
end

-- One Holzpaket worth the current material price, without any money. It is always the first recipe's package (ECONOMY). Only for an owner whose money is below
-- the price and who has no batch anywhere (supplier, hand, vehicle, line or stores), no open sale and no open
-- advance. The sale of exactly this batch repays it (Sales.settle). A second claim while it is open is refused.
function Purchases.advance(controller: Persistence.Controller, actor: any, request: any, slots: Slots,
	ttlSeconds: number): AdvanceResult
	local opened, answer = open(controller, actor, request, "Advance", "ADVANCED", "advance/")
	if not opened then return answer end
	local state, operationId, revision = opened.state, opened.operationId, opened.revision
	-- The limit does not depend on the revision a client saw: an open advance always refuses the next claim.
	if state.advance then return rejected("ADVANCE_OPEN") end
	if revision ~= state.revision then return rejected("STALE_REVISION") end
	if revision == MAX_INTEGER then return rejected("REVISION_OVERFLOW") end
	local batchId = "advance/" .. operationId
	if state.batches[batchId] then return rejected("OPERATION_CONFLICT") end
	if state.pendingSale then return rejected("SALE_OPEN") end
	if state.money >= Purchases.PRICE then return rejected("MONEY_AVAILABLE") end
	if next(state.batches) ~= nil then return rejected("STOCK_AVAILABLE") end
	local supplierId, rawSlotId, problem = freeSlots(state, operationId, slots)
	if not supplierId or not rawSlotId then return rejected(problem :: string) end

	local receipt: AdvanceReceipt = {ok = true, code = "ADVANCED",
		message = "Materialvorschuss: 1 Holzpaket abholbereit. Beim Verkauf bleibt Geld für den nächsten Einkauf.",
		revision = revision + 1, supplierId = supplierId, rawSlotId = rawSlotId, batchId = batchId, amount = Purchases.PRICE}
	supply(opened, actor, "Advance", batchId, supplierId, rawSlotId, receipt, Recipes.DEFAULT_ID)
	state.advance = {operationId = operationId, batchId = batchId, amount = Purchases.PRICE}

	local saved = controller.save(opened.candidate, ttlSeconds)
	if not saved.ok then return rejected(saved.code, saved.unknown) end
	return {ok = true, code = "ADVANCED", receipt = receipt, unknown = false}
end

return table.freeze(Purchases)
