--!strict
-- P07: one carton per sale. The world adapter observes arrival, reach and the buyer pad;
-- this module changes stock and money only through confirmed saves of the owner's profile.
local State = require(script.Parent.State)
local Profiles = require(script.Parent.Profiles)
local Persistence = require(script.Parent.Persistence)
local Transfers = require(script.Parent.Transfers)

export type Buyer = State.Buyer
export type Actor = {ready: boolean, kind: string, ownerUserId: number, actorId: string, carrierLocationId: string}
export type Request = {id: string, buyer: Buyer, vehicleId: string, slotId: string, batchId: string}
-- Server-observed arrival for exactly this owner, rig, slot, carton and buyer (see Trips.arrival).
export type Arrival = {ownerUserId: number, vehicleId: string, slotId: string, batchId: string, destination: string}
export type Offer = {saleId: string, buyer: Buyer, vehicleId: string, slotId: string, batchId: string, quantity: number,
	dealerValue: number, quoteMin: number, quoteMax: number}
export type Receipt = State.SaleResult
export type Result = {ok: boolean, code: string, message: string, unknown: boolean, offer: Offer?, receipt: Receipt?}
export type Price = {dealer: number, privateMin: number, privateMax: number}

local Sales = {}
-- Prototype test economy (ECONOMY.md): known dealer price per model, private range shown before binding.
local PRICES: {[string]: Price} = {Hocker01 = {dealer = 100, privateMin = 80, privateMax = 120}}
for _, price in PRICES do table.freeze(price) end
Sales.PRICES = table.freeze(PRICES)
local MAX_INTEGER = 9007199254740991
local REQUEST_FIELDS = {id = true, buyer = true, vehicleId = true, slotId = true, batchId = true}
local MESSAGES: {[string]: string} = {
	OPEN = "Karton übernommen. Bring ihn zur Annahme des Käufers.",
	CANCELLED = "Verkauf abgebrochen. Der Karton liegt wieder auf dem Anhänger.",
	SOLD = "Verkauf abgeschlossen.",
	NONE = "Kein offener Verkauf.",
	NOT_READY = "Der Spielstand ist noch nicht freigegeben.",
	NOT_AUTHORIZED = "Du darfst diese Ware nicht verkaufen.",
	NOT_CONFIRMED = "Speichern unklar – bitte warten.",
	INVALID_REQUEST = "Die Verkaufsanfrage ist ungültig.",
	INVALID_TIME = "Die Serverzeit ist ungültig.",
	NO_ARRIVAL = "Fahre den Karton auf dem Anhänger durchgehend bis in den Käuferhof.",
	CARTON_NOT_ON_SLOT = "Auf diesem Anhängerplatz liegt kein verkaufsfertiger Karton.",
	NO_PRICE = "Für dieses Möbel gibt es noch keinen Preis.",
	SALE_BUSY = "Schließe zuerst den offenen Verkauf ab.",
	SALE_NOT_FOUND = "Dieser Verkauf ist nicht mehr offen.",
	SALE_TRANSFER_PENDING = "Die Ware wird gerade übergeben. Bitte kurz warten.",
	OPERATION_CONFLICT = "Diese Verkaufs-ID gehört bereits zu anderen Angaben.",
	REVISION_OVERFLOW = "Der Bestand ist vorübergehend gesperrt.",
	MONEY_OVERFLOW = "Das Guthaben kann nicht weiter steigen.",
	INVALID_STATE = "Der Bestand kann gerade nicht geprüft werden.",
}

local function respond(ok: boolean, code: string, unknown: boolean?, offer: Offer?, receipt: Receipt?): Result
	return {ok = ok, code = code, message = MESSAGES[code] or "Verkauf gerade nicht möglich.", unknown = unknown == true,
		offer = offer, receipt = receipt}
end

local function rejected(code: string, unknown: boolean?): Result
	return respond(false, code, unknown)
end

local function identifier(value: any, maxLength: number): boolean
	return type(value) == "string" and #value > 0 and #value <= maxLength and utf8.len(value) ~= nil
end

local function integer(value: any, minimum: number, maximum: number): boolean
	return type(value) == "number" and value >= minimum and value <= maximum and value % 1 == 0
end

local function copy(value: any): any
	if type(value) ~= "table" then return value end
	local result: any = {}
	for key, item in value do result[key] = copy(item) end
	return result
end

-- Only a ready player acting on their own confirmed, idle session.
local function loaded(controller: Persistence.Controller, actor: Actor, reconcile: boolean?): (Profiles.Envelope?, Result?)
	if type(actor) ~= "table" or getmetatable(actor) or actor.ready ~= true then return nil, rejected("NOT_READY") end
	if actor.kind ~= "Player" or not integer(actor.ownerUserId, 1, MAX_INTEGER)
		or not identifier(actor.carrierLocationId, 128) then return nil, rejected("NOT_AUTHORIZED") end
	local owner = string.format("%.0f", actor.ownerUserId)
	local snapshot = controller.snapshot()
	if actor.actorId ~= "Player/" .. owner or snapshot.key ~= "Player_" .. owner then
		return nil, rejected("NOT_AUTHORIZED")
	end
	if reconcile and snapshot.unknown and not snapshot.inFlight then
		snapshot = controller.reconcile()
		if not snapshot.ok then return nil, rejected(snapshot.code, snapshot.unknown) end
	end
	local record = snapshot.confirmed
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not record then
		return nil, rejected("NOT_CONFIRMED", snapshot.unknown)
	end
	if record.data.state.ownerUserId ~= actor.ownerUserId then return nil, rejected("NOT_AUTHORIZED") end
	return record.data, nil
end

local function save(controller: Persistence.Controller, candidate: Profiles.Envelope, lease: number, response: Result): Result
	if not State.validate(candidate.state) then return rejected("INVALID_STATE") end
	local saved = controller.save(candidate, lease)
	if not saved.ok then return rejected(saved.code, saved.unknown) end
	return response
end

local function offerOf(sale: State.PendingSale): Offer
	return {saleId = sale.id, buyer = sale.buyer, vehicleId = sale.vehicleId, slotId = sale.slotId, batchId = sale.batchId,
		quantity = 1, dealerValue = sale.dealerValue, quoteMin = sale.quoteMin, quoteMax = sale.quoteMax}
end

local function matches(kept: any, request: Request): boolean
	return kept.buyer == request.buyer and kept.vehicleId == request.vehicleId
		and kept.slotId == request.slotId and kept.batchId == request.batchId
end

-- Completed sales answer with their stored receipt before any current stock check.
local function replay(state: State.Profile, actor: Actor, saleId: string, request: Request?): Result?
	local receipt = state.receipts[saleId]
	if not receipt then return nil end
	if receipt.action ~= "Sale" or receipt.actorId ~= actor.actorId or (request and not matches(receipt.result, request)) then
		return rejected("OPERATION_CONFLICT")
	end
	return respond(true, "SOLD", false, nil, copy(receipt.result))
end

-- The hidden roll belongs to the carton and buyer, not to an attempt: cancelling and reopening, a rejoin or a
-- new delivery of the same carton to the same buyer always reveal the same amount. FNV-1a over a server-only key.
local SEED_SALT = "Moebelfabrik/P07/1"
function Sales.seedFor(batchId: string, buyer: Buyer): number
	local text = SEED_SALT .. "|" .. batchId .. "|" .. buyer
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (bit32.lshift(hash, 24) + hash * 403) % 4294967296
	end
	return hash % (State.MAX_SALE_SEED + 1)
end

local function transferActor(actor: Actor): any
	return {ready = true, kind = "Player", ownerUserId = actor.ownerUserId, actorId = actor.actorId,
		carrierLocationId = actor.carrierLocationId}
end

-- Opening takes the arrived carton from its trailer slot into the player's hand. The caller must have checked
-- the player's reach to that moving slot. seedOverride is a server-only test input, never a player value.
function Sales.open(controller: Persistence.Controller, actor: Actor, request: Request, arrival: Arrival?, now: number,
	lease: number, seedOverride: number?): Result
	if type(request) ~= "table" or getmetatable(request) then return rejected("INVALID_REQUEST") end
	for key in (request :: any) do if not (REQUEST_FIELDS :: any)[key] then return rejected("INVALID_REQUEST") end end
	if not identifier(request.id, State.MAX_SALE_ID_LENGTH) or not identifier(request.vehicleId, 32)
		or not identifier(request.slotId, 128) or not identifier(request.batchId, 128)
		or not (request.buyer == "Dealer" or request.buyer == "Private")
		or (seedOverride ~= nil and not integer(seedOverride, 0, State.MAX_SALE_SEED)) then
		return rejected("INVALID_REQUEST")
	end
	if not integer(now, 0, MAX_INTEGER) then return rejected("INVALID_TIME") end
	local candidate, problem = loaded(controller, actor)
	if not candidate then return problem :: Result end
	local state = candidate.state
	local done = replay(state, actor, request.id, request)
	if done then return done end
	local pending = state.pendingSale
	if pending then
		if pending.id ~= request.id then return rejected("SALE_BUSY") end
		if pending.carrierId ~= actor.carrierLocationId or not matches(pending, request) then
			return rejected("OPERATION_CONFLICT")
		end
		return respond(true, "OPEN", false, offerOf(pending))
	end
	if type(arrival) ~= "table" or arrival.ownerUserId ~= actor.ownerUserId or arrival.vehicleId ~= request.vehicleId
		or arrival.slotId ~= request.slotId or arrival.batchId ~= request.batchId or arrival.destination ~= request.buyer then
		return rejected("NO_ARRIVAL")
	end
	local batch, slot = state.batches[request.batchId], state.locations[request.slotId]
	local prefix = "Vehicle." .. request.vehicleId .. "."
	if not batch or batch.stage ~= "Karton" or batch.quantity ~= 1 or batch.locationId ~= request.slotId
		or batch.ownerUserId ~= actor.ownerUserId or not slot or slot.kind ~= "VehicleSlot"
		or request.slotId:sub(1, #prefix) ~= prefix then
		return rejected("CARTON_NOT_ON_SLOT")
	end
	local price = PRICES[batch.recipeId]
	if not price then return rejected("NO_PRICE") end
	if state.revision > MAX_INTEGER - 2 then return rejected("REVISION_OVERFLOW") end
	local store = Transfers.new(state)
	local mover = transferActor(actor)
	local reserved = Transfers.reserve(store, mover, {operationId = request.id .. "/open/reserve",
		expectedRevision = state.revision, batchId = batch.id, sourceId = request.slotId,
		targetId = actor.carrierLocationId, quantity = 1}, now, 5)
	if not reserved.ok then return rejected(reserved.code) end
	local committed = Transfers.commit(store, mover, {operationId = request.id .. "/open/commit",
		expectedRevision = store.profile.revision, claimId = reserved.claimId}, now)
	if not committed.ok then return rejected(committed.code) end
	local private = request.buyer == "Private"
	local sale: State.PendingSale = {id = request.id, buyer = request.buyer, vehicleId = request.vehicleId,
		slotId = request.slotId, batchId = batch.id, carrierId = actor.carrierLocationId,
		quoteMin = if private then price.privateMin else price.dealer,
		quoteMax = if private then price.privateMax else price.dealer,
		dealerValue = price.dealer, seed = seedOverride or Sales.seedFor(batch.id, request.buyer)}
	store.profile.pendingSale = sale
	candidate.state = store.profile
	return save(controller, candidate, lease, respond(true, "OPEN", false, offerOf(sale)))
end

-- Abort before binding: the carton goes back onto its own trailer slot. The caller checks reach to that slot.
function Sales.cancel(controller: Persistence.Controller, actor: Actor, saleId: string, now: number, lease: number): Result
	if not identifier(saleId, State.MAX_SALE_ID_LENGTH) then return rejected("INVALID_REQUEST") end
	if not integer(now, 0, MAX_INTEGER) then return rejected("INVALID_TIME") end
	local candidate, problem = loaded(controller, actor)
	if not candidate then return problem :: Result end
	local state = candidate.state
	local done = replay(state, actor, saleId)
	if done then return done end
	local sale = state.pendingSale
	if not sale or sale.id ~= saleId then
		local returned = state.receipts[saleId .. "/cancel/commit"]
		if returned and returned.actorId == actor.actorId then return respond(true, "CANCELLED") end
		return rejected("SALE_NOT_FOUND")
	end
	if sale.carrierId ~= actor.carrierLocationId then return rejected("NOT_AUTHORIZED") end
	if state.revision > MAX_INTEGER - 2 then return rejected("REVISION_OVERFLOW") end
	state.pendingSale = nil
	local store = Transfers.new(state)
	local mover = transferActor(actor)
	local reserved = Transfers.reserve(store, mover, {operationId = saleId .. "/cancel/reserve",
		expectedRevision = state.revision, batchId = sale.batchId, sourceId = sale.carrierId,
		targetId = sale.slotId, quantity = 1}, now, 5)
	if not reserved.ok then return rejected(reserved.code) end
	local committed = Transfers.commit(store, mover, {operationId = saleId .. "/cancel/commit",
		expectedRevision = store.profile.revision, claimId = reserved.claimId}, now)
	if not committed.ok then return rejected(committed.code) end
	candidate.state = store.profile
	return save(controller, candidate, lease, respond(true, "CANCELLED"))
end

-- Binding handoff at the buyer pad: removes the carton and its Return, credits once and stores the receipt,
-- all in one profile change. The private amount comes from the seed fixed when the sale was opened.
function Sales.settle(controller: Persistence.Controller, actor: Actor, saleId: string, lease: number): Result
	if not identifier(saleId, State.MAX_SALE_ID_LENGTH) then return rejected("INVALID_REQUEST") end
	local candidate, problem = loaded(controller, actor)
	if not candidate then return problem :: Result end
	local state = candidate.state
	local done = replay(state, actor, saleId)
	if done then return done end
	local sale = state.pendingSale
	if not sale or sale.id ~= saleId then return rejected("SALE_NOT_FOUND") end
	if sale.carrierId ~= actor.carrierLocationId then return rejected("NOT_AUTHORIZED") end
	for _, claim in state.claims do
		if claim.batchId == sale.batchId or claim.sourceId == sale.slotId or claim.targetId == sale.slotId
			or claim.sourceId == sale.carrierId or claim.targetId == sale.carrierId then
			return rejected("SALE_TRANSFER_PENDING")
		end
	end
	if state.revision == MAX_INTEGER then return rejected("REVISION_OVERFLOW") end
	local amount = sale.quoteMin + sale.seed % (sale.quoteMax - sale.quoteMin + 1)
	if state.money > MAX_INTEGER - amount then return rejected("MONEY_OVERFLOW") end
	local revision = state.revision
	state.revision += 1
	state.money += amount
	state.batches[sale.batchId] = nil
	state.reservations[sale.slotId] = nil
	state.pendingSale = nil
	local receipt: Receipt = {ok = true, code = "SOLD", message = MESSAGES.SOLD, revision = state.revision,
		buyer = sale.buyer, vehicleId = sale.vehicleId, slotId = sale.slotId, batchId = sale.batchId, quantity = 1,
		amount = amount, quoteMin = sale.quoteMin, quoteMax = sale.quoteMax, dealerValue = sale.dealerValue}
	state.receipts[saleId] = {action = "Sale", ownerUserId = actor.ownerUserId, actorId = actor.actorId,
		actorKind = "Player", carrierId = sale.carrierId,
		request = {operationId = saleId, expectedRevision = revision}, result = receipt}
	return save(controller, candidate, lease, respond(true, "SOLD", false, nil, copy(receipt)))
end

-- Resume after a reconnect or an unclear save: clarifies the last write first, then reports the kept state.
function Sales.resume(controller: Persistence.Controller, actor: Actor, saleId: string?): Result
	if saleId ~= nil and not identifier(saleId, State.MAX_SALE_ID_LENGTH) then return rejected("INVALID_REQUEST") end
	local candidate, problem = loaded(controller, actor, true)
	if not candidate then return problem :: Result end
	local state = candidate.state
	if saleId then
		local done = replay(state, actor, saleId)
		if done then return done end
	end
	local sale = state.pendingSale
	if sale and (saleId == nil or sale.id == saleId) then return respond(true, "OPEN", false, offerOf(sale)) end
	return respond(true, "NONE")
end

return table.freeze(Sales)
