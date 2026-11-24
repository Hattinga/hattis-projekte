--!strict
-- P04-03: closed, server-only schema. No startup, grants, remotes or persistence.
local runService = game:GetService("RunService")
assert(runService:IsServer() or (runService:IsStudio() and not runService:IsRunning()),
	"Factory state is server-only")

export type Stage = "Holzpaket" | "Bausatz" | "Rohhocker" | "Fertig" | "Karton"
export type Location = {id: string, kind: string, capacity: number, acceptedStages: {Stage}}
export type Batch = {id: string, ownerUserId: number, recipeId: string, recipeVersion: number, stage: Stage,
	quantity: number, locationId: string}
export type Claim = {id: string, actorId: string, actorKind: string, carrierId: string, batchId: string,
	sourceId: string, targetId: string, nextTargetId: string?, recoverWorker: boolean?, quantity: number, expiresAt: number}
export type ReturnReservation = {kind: "Return", batchId: string, actorId: string, actorKind: string,
	carrierId: string, recipeId: string, recipeVersion: number, stage: Stage, quantity: number}
export type DeliveryReservation = {kind: "Delivery", batchId: string, purchaseOperationId: string}
export type ProductionReservation = {kind: "Production", batchId: string, finishAt: number}
export type Reservation = ReturnReservation | DeliveryReservation | ProductionReservation
export type Receipt = {actorId: string, actorKind: string, ownerUserId: number, carrierId: string?,
	action: string, request: any, result: any}
-- P07: at most one open sale. Its carton is in the player's hand with an exact Return to its trailer slot.
export type Buyer = "Dealer" | "Private"
export type PendingSale = {id: string, buyer: Buyer, vehicleId: string, slotId: string, batchId: string,
	carrierId: string, quoteMin: number, quoteMax: number, dealerValue: number, seed: number}
-- An advance sale records the repayment and the confirmed balance before crediting the net proceeds.
export type SaleResult = {ok: boolean, code: string, message: string, revision: number, buyer: Buyer,
	vehicleId: string, slotId: string, batchId: string, quantity: number, amount: number,
	quoteMin: number, quoteMax: number, dealerValue: number, repaid: number?, balanceBefore: number?}
-- P07-07: at most one open material advance. Only the sale of exactly its batch repays and clears it.
export type Advance = {operationId: string, batchId: string, amount: number}
export type Profile = {schemaVersion: number, ownerUserId: number, revision: number, money: number,
	locations: {[string]: Location}, batches: {[string]: Batch}, claims: {[string]: Claim},
	reservations: {[string]: Reservation}, receipts: {[string]: Receipt}, pendingSale: PendingSale?,
	advance: Advance?}

export type StationRule = {read id: string, read input: string, read process: string, read output: string,
	read inputStage: Stage, read outputStage: Stage, read durationSeconds: number}

local State = {}
State.SCHEMA_VERSION = 2
local function stationRule(id: string, inputStage: Stage, outputStage: Stage, durationSeconds: number): StationRule
	return table.freeze({id=id, input=id..".Input", process=id..".Process", output=id..".Output",
		inputStage=inputStage, outputStage=outputStage, durationSeconds=durationSeconds})
end
-- Hocker01 v1: one run per station, one batch in, the same batch out at the next stage.
State.STATIONS = table.freeze({
	stationRule("Saege", "Holzpaket", "Bausatz", 6),
	stationRule("Montage", "Bausatz", "Rohhocker", 8),
	stationRule("Finish", "Rohhocker", "Fertig", 6),
	stationRule("Packen", "Fertig", "Karton", 4),
})
local stationById: {[string]: StationRule} = {}
local stationByOutput: {[string]: StationRule} = {}
for _, rule in State.STATIONS do
	stationById[rule.id] = rule
	stationByOutput[rule.output] = rule
end
State.STATION_BY_ID = table.freeze(stationById)
State.SAW = State.STATIONS[1]
export type WorkerLeg = {read carrier: string, read source: string, read target: string, read stage: Stage}
State.FIRST_WORKER = table.freeze({carrier="Worker.First",source=State.SAW.output,
	target=stationById.Montage.input,stage=State.SAW.outputStage})
-- P09-06: the legs the first worker can be assigned to. They share one carrier; the profile selects one
-- (progress.firstWorker.route, nil = Saw). Finish -> Packen is the next same-row hand leg after the belt took over the saw leg.
local workerRoutes: {[string]: WorkerLeg} = {
	Saw=State.FIRST_WORKER,
	Finish=table.freeze({carrier="Worker.First",source=stationById.Finish.output,
		target=stationById.Packen.input,stage=stationById.Finish.outputStage}),
}
State.WORKER_ROUTES = table.freeze(workerRoutes)
State.FIRST_BELT = table.freeze({carrier="Band.First",source=State.SAW.output,
	target=stationById.Montage.input,stage=State.SAW.outputStage})
local MAX_INTEGER = 9007199254740991
local STAGES: {[string]: boolean} = {Holzpaket=true,Bausatz=true,Rohhocker=true,Fertig=true,Karton=true}
local KINDS: {[string]: boolean} = {Supplier=true,RawStore=true,FinishedStore=true,Carrier=true,
	StationInput=true,StationProcess=true,StationOutput=true,Machine=true,VehicleSlot=true,
	Band=true,Recovery=true}
local ACTOR_KINDS: {[string]: boolean} = {Player=true,Worker=true,Band=true}
local PROFILE_FIELDS = {schemaVersion=true,ownerUserId=true,revision=true,money=true,locations=true,
	batches=true,claims=true,reservations=true,receipts=true,pendingSale=true,advance=true}
State.MAX_SALE_SEED = 16777215
State.MAX_SALE_ID_LENGTH = 88 -- Leaves room for the derived transfer operation IDs.
local BUYERS: {[string]: boolean} = {Dealer=true,Private=true}
local PENDING_SALE_FIELDS = {id=true,buyer=true,vehicleId=true,slotId=true,batchId=true,carrierId=true,
	quoteMin=true,quoteMax=true,dealerValue=true,seed=true}
local SALE_RESULT_FIELDS = {ok=true,code=true,message=true,revision=true,buyer=true,vehicleId=true,slotId=true,
	batchId=true,quantity=true,amount=true,quoteMin=true,quoteMax=true,dealerValue=true,repaid=true,balanceBefore=true}
local ADVANCE_FIELDS = {operationId=true,batchId=true,amount=true}
local LOCATION_FIELDS = {id=true,kind=true,capacity=true,acceptedStages=true}
local BATCH_FIELDS = {id=true,ownerUserId=true,recipeId=true,recipeVersion=true,stage=true,quantity=true,locationId=true}
local CLAIM_FIELDS = {id=true,actorId=true,actorKind=true,carrierId=true,batchId=true,sourceId=true,
	targetId=true,nextTargetId=true,recoverWorker=true,quantity=true,expiresAt=true}
local RETURN_FIELDS = {kind=true,batchId=true,actorId=true,actorKind=true,carrierId=true,recipeId=true,
	recipeVersion=true,stage=true,quantity=true}
local DELIVERY_FIELDS = {kind=true,batchId=true,purchaseOperationId=true}
local PRODUCTION_FIELDS = {kind=true,batchId=true,finishAt=true}
local RECEIPT_FIELDS = {actorId=true,actorKind=true,ownerUserId=true,carrierId=true,action=true,request=true,result=true}
local RESERVE_REQUEST_FIELDS = {operationId=true,expectedRevision=true,batchId=true,sourceId=true,targetId=true,
	nextTargetId=true,recoverWorker=true,quantity=true}
local CLAIM_REQUEST_FIELDS = {operationId=true,expectedRevision=true,claimId=true}
local PURCHASE_REQUEST_FIELDS = {operationId=true,expectedRevision=true}
local PURCHASE_RESULT_FIELDS = {ok=true,code=true,message=true,revision=true,batchId=true,supplierId=true,rawSlotId=true,price=true}
local ADVANCE_RESULT_FIELDS = {ok=true,code=true,message=true,revision=true,batchId=true,supplierId=true,rawSlotId=true,amount=true}
local RESERVE_RESULT_FIELDS = {ok=true,code=true,message=true,revision=true,claimId=true,expiresAt=true}
local COMMIT_RESULT_FIELDS = {ok=true,code=true,message=true,revision=true,claimId=true,batchId=true,sourceId=true,targetId=true}
local CANCEL_RESULT_FIELDS = {ok=true,code=true,message=true,revision=true,claimId=true}

local function plainTable(value: any): boolean
	return type(value)=="table" and getmetatable(value)==nil
end
local function record(value: any, fields: {[string]: boolean}): boolean
	if not plainTable(value) then return false end
	for key in value do if not fields[key] then return false end end
	return true
end
local function finite(value: any, minimum: number): boolean
	return type(value)=="number" and value==value and value>=minimum and value<=MAX_INTEGER
end
local function integer(value: any, minimum: number): boolean
	return finite(value,minimum) and value%1==0
end
local function identifier(value: any): boolean
	return type(value)=="string" and #value>0 and #value<=128 and utf8.len(value)~=nil
end
local function message(value: any): boolean
	return type(value)=="string" and #value>0 and #value<=1024 and utf8.len(value)~=nil
end
local function carrierMatches(profile: any, carrierId: any, actorKind: any): boolean
	if not identifier(carrierId) or not ACTOR_KINDS[actorKind] then return false end
	local carrier=profile.locations[carrierId]
	return carrier~=nil and carrier.kind==(if actorKind=="Band" then "Band" else "Carrier")
end
local function sameReturn(reservation: any, claim: any, batch: any): boolean
	return reservation.kind=="Return" and reservation.batchId==batch.id
		and reservation.actorId==claim.actorId and reservation.actorKind==claim.actorKind
		and reservation.carrierId==claim.carrierId and reservation.recipeId==batch.recipeId
		and reservation.recipeVersion==batch.recipeVersion and reservation.stage==batch.stage
		and reservation.quantity==batch.quantity
end

local function saleIdentifier(value: any): boolean
	return identifier(value) and #value<=State.MAX_SALE_ID_LENGTH
end
local function vehicleSlotOf(profile: any, vehicleId: any, slotId: any): boolean
	if not identifier(vehicleId) or #vehicleId>32 or not identifier(slotId) then return false end
	local slot=profile.locations[slotId]
	local prefix="Vehicle."..vehicleId.."."
	return slot~=nil and slot.kind=="VehicleSlot" and slotId:sub(1,#prefix)==prefix
end
local function quote(buyer: any, quoteMin: any, quoteMax: any, dealerValue: any): boolean
	return BUYERS[buyer]==true and integer(quoteMin,0) and integer(quoteMax,0) and quoteMin<=quoteMax
		and integer(dealerValue,0) and (buyer~="Dealer" or (quoteMin==dealerValue and quoteMax==dealerValue))
end
local function playerActor(profile: any): string
	return "Player/"..string.format("%.0f",profile.ownerUserId)
end

-- The registered worker leg from `sourceId` to `targetId`, nil when there is none.
function State.workerLeg(sourceId: any, targetId: any): WorkerLeg?
	for _,leg in State.WORKER_ROUTES do
		if leg.source==sourceId and leg.target==targetId then return leg end
	end
	return nil
end

function State.isFirstWorkerPickup(actorKind: string, carrierId: string, sourceId: string, targetId: string,
	nextTargetId: string): boolean
	local leg=State.workerLeg(sourceId,nextTargetId)
	return actorKind=="Worker" and leg~=nil and carrierId==leg.carrier and targetId==leg.carrier
end

function State.isWorkerRecovery(profile: Profile, actorKind: string, actorId: string, carrierId: string,
	sourceId: string, targetId: string): boolean
	return actorKind=="Player" and actorId==playerActor(profile) and sourceId==State.FIRST_WORKER.carrier
		and targetId==carrierId and sourceId~=targetId and profile.locations[sourceId].kind=="Carrier"
end

-- Used after the ordinary stock and Return invariants have been checked.
function State.hasWorkerRecoveryReturn(profile: Profile, batch: Batch): boolean
	for _,route in State.WORKER_ROUTES do
		local origin=profile.locations[route.source]
		local reservation=profile.reservations[route.source]
		if batch.locationId==route.carrier and batch.stage==route.stage and origin~=nil
			and origin.kind=="StationOutput" and reservation~=nil and reservation.kind=="Return"
			and reservation.batchId==batch.id and reservation.actorKind=="Worker"
			and reservation.actorId==route.carrier and reservation.carrierId==route.carrier then
			return true
		end
	end
	return false
end

-- The station output whose Return reservation the worker holds for `batchId` (the saw output if there is none).
function State.workerReturnOrigin(profile: Profile, batchId: string): string
	for _,route in State.WORKER_ROUTES do
		local reservation=profile.reservations[route.source]
		if reservation~=nil and reservation.kind=="Return" and reservation.batchId==batchId
			and reservation.actorKind=="Worker" then
			return route.source
		end
	end
	return State.FIRST_WORKER.source
end

function State.claimTouches(claim: Claim, locationId: string): boolean
	return claim.sourceId==locationId or claim.targetId==locationId or claim.nextTargetId==locationId
end

-- Empty artificial schema specimen. P04-04 must confirm absence before any real new profile.
function State.newProfile(ownerUserId: number): Profile
	assert(integer(ownerUserId,1),"Invalid owner")
	return {schemaVersion=State.SCHEMA_VERSION,ownerUserId=ownerUserId,revision=0,money=0,
		locations={},batches={},claims={},reservations={},receipts={}}
end

function State.newLocation(id: string, kind: string, capacity: number, acceptedStages: {Stage}): Location
	assert(identifier(id) and KINDS[kind],"Invalid location")
	assert(capacity==1,"Each location represents one physical slot")
	assert(plainTable(acceptedStages) and #acceptedStages>0,"Missing accepted stages")
	local stages: {Stage} = {}
	local stageCount=0
	for index,stage in acceptedStages do
		assert(integer(index,1) and index<=#acceptedStages and STAGES[stage],"Invalid stage")
		stages[index]=stage
		stageCount+=1
	end
	assert(stageCount==#acceptedStages,"Invalid stage list")
	return {id=id,kind=kind,capacity=capacity,acceptedStages=stages}
end

function State.newBatch(id: string, ownerUserId: number, stage: Stage, locationId: string): Batch
	assert(identifier(id) and identifier(locationId),"Invalid batch identity or location")
	assert(integer(ownerUserId,1) and STAGES[stage],"Invalid owner or stage")
	return {id=id,ownerUserId=ownerUserId,recipeId="Hocker01",recipeVersion=1,stage=stage,quantity=1,locationId=locationId}
end

-- The batch's locationId is the only stock membership record.
function State.countAt(profile: Profile, locationId: string): number
	local count=0
	for _,batch in profile.batches do
		if batch.locationId==locationId then count+=batch.quantity end
	end
	return count
end

-- Set aside enough proceeds for one regular purchase before booking the repayment.
function State.advanceRepayment(balance: number, gross: number, advanced: number): number
	local needed = math.max(0, advanced - balance)
	return math.clamp(gross - needed, 0, advanced)
end

function State.validate(profile: any): (boolean, string?)
	if not record(profile,PROFILE_FIELDS) then return false,"INVALID_PROFILE_SHAPE" end
	if profile.schemaVersion~=State.SCHEMA_VERSION then return false,"INVALID_SCHEMA" end
	if not integer(profile.ownerUserId,1) then return false,"INVALID_OWNER" end
	if not integer(profile.revision,0) then return false,"INVALID_REVISION" end
	if not integer(profile.money,0) then return false,"INVALID_MONEY" end
	if not plainTable(profile.locations) or not plainTable(profile.batches) or not plainTable(profile.claims)
		or not plainTable(profile.reservations) or not plainTable(profile.receipts) then
		return false,"INVALID_COLLECTION"
	end
	local counts: {[string]: number} = {}
	for id,location in profile.locations do
		if not identifier(id) or not record(location,LOCATION_FIELDS) or location.id~=id or not KINDS[location.kind] then
			return false,"INVALID_LOCATION"
		end
		if location.capacity~=1 then return false,"INVALID_CAPACITY" end
		if not plainTable(location.acceptedStages) or #location.acceptedStages==0 then return false,"INVALID_ACCEPTED_STAGES" end
		local stageCount=0
		for index,stage in location.acceptedStages do
			if not integer(index,1) or index>#location.acceptedStages or not STAGES[stage] then
				return false,"INVALID_ACCEPTED_STAGES"
			end
			stageCount+=1
		end
		if stageCount~=#location.acceptedStages then return false,"INVALID_ACCEPTED_STAGES" end
		counts[id]=0
	end
	for id,batch in profile.batches do
		if not identifier(id) or not record(batch,BATCH_FIELDS) or batch.id~=id then return false,"INVALID_BATCH_ID" end
		if batch.ownerUserId~=profile.ownerUserId then return false,"FOREIGN_BATCH" end
		if batch.recipeId~="Hocker01" or batch.recipeVersion~=1 or not STAGES[batch.stage] then return false,"INVALID_RECIPE_STAGE" end
		if batch.quantity~=1 then return false,"INVALID_QUANTITY" end
		if not identifier(batch.locationId) or profile.locations[batch.locationId]==nil then return false,"UNKNOWN_LOCATION" end
		if not table.find(profile.locations[batch.locationId].acceptedStages,batch.stage) then return false,"WRONG_STAGE" end
		counts[batch.locationId]+=1
		if counts[batch.locationId]>1 then return false,"CAPACITY_EXCEEDED" end
	end
	local returnsByBatch: {[string]: any} = {}
	local deliveriesByBatch: {[string]: string} = {}
	local deliveriesByOperation: {[string]: string} = {}
	for locationId,reservation in profile.reservations do
		if not identifier(locationId) or not plainTable(reservation) then return false,"INVALID_RESERVATION" end
		local location=profile.locations[locationId]
		if not location or counts[locationId]~=0 then return false,"INVALID_RESERVED_LOCATION" end
		if not identifier(reservation.batchId) then return false,"INVALID_RESERVATION_BATCH" end
		local batch=profile.batches[reservation.batchId]
		if not batch then return false,"INVALID_RESERVATION_BATCH" end
		if reservation.kind=="Return" then
			if not record(reservation,RETURN_FIELDS) or not identifier(reservation.actorId)
				or not carrierMatches(profile,reservation.carrierId,reservation.actorKind)
				or batch.locationId~=reservation.carrierId or reservation.recipeId~=batch.recipeId
				or reservation.recipeVersion~=batch.recipeVersion or reservation.stage~=batch.stage
				or reservation.quantity~=batch.quantity or not table.find(location.acceptedStages,batch.stage)
				or location.kind=="Carrier" or location.kind=="Band" or returnsByBatch[batch.id] then
				return false,"INVALID_RETURN_RESERVATION"
			end
			returnsByBatch[batch.id]=reservation
		elseif reservation.kind=="Delivery" then
			local batchLocation=profile.locations[batch.locationId]
			if not record(reservation,DELIVERY_FIELDS) or not identifier(reservation.purchaseOperationId)
				or location.kind~="RawStore" or batch.stage~="Holzpaket"
				or not table.find(location.acceptedStages,"Holzpaket") or deliveriesByBatch[batch.id]
				or (batchLocation.kind~="Supplier" and batchLocation.kind~="Carrier"
					and batchLocation.kind~="Band" and batchLocation.kind~="VehicleSlot") then
				return false,"INVALID_DELIVERY_RESERVATION"
			end
			deliveriesByBatch[batch.id]=reservation.purchaseOperationId
			if deliveriesByOperation[reservation.purchaseOperationId] then return false,"INVALID_DELIVERY_RESERVATION" end
			deliveriesByOperation[reservation.purchaseOperationId]=locationId
		elseif reservation.kind=="Production" then
			local rule=stationByOutput[locationId]
			if not rule then return false,"INVALID_PRODUCTION_RESERVATION" end
			local input,process=profile.locations[rule.input],profile.locations[rule.process]
			if not record(reservation,PRODUCTION_FIELDS) or not integer(reservation.finishAt,rule.durationSeconds)
				or location.kind~="StationOutput"
				or not input or input.kind~="StationInput" or not table.find(input.acceptedStages,rule.inputStage)
				or not process or process.kind~="StationProcess" or batch.locationId~=rule.process
				or batch.stage~=rule.inputStage or not table.find(location.acceptedStages,rule.outputStage) then
				return false,"INVALID_PRODUCTION_RESERVATION"
			end
		else
			return false,"INVALID_RESERVATION_KIND"
		end
	end
	for _,rule in State.STATIONS do
		local running=profile.reservations[rule.output]
		if counts[rule.process]==1 and (not running or running.kind~="Production") then
			return false,"MISSING_PRODUCTION_RESERVATION"
		end
	end
	local receiptRevisions: {[number]: boolean} = {}
	-- Purchases and material advances both deliver a new batch to a promised raw slot: one validation path.
	local suppliesByBatch: {[string]: any} = {}
	local deliveriesCompleted: {[string]: boolean} = {}
	-- A sold carton leaves the stock; its earlier purchase, advance and transfer receipts stay valid history.
	local soldBatches: {[string]: string} = {}
	local advancedBatches: {[string]: any} = {} -- Each receipt is checked below.
	for operationId,receipt in profile.receipts do
		if plainTable(receipt) and receipt.action=="Sale" and plainTable(receipt.result)
			and identifier(receipt.result.batchId) then
			if soldBatches[receipt.result.batchId] then return false,"DUPLICATE_SALE" end
			soldBatches[receipt.result.batchId]=operationId
		elseif plainTable(receipt) and receipt.action=="Advance" and plainTable(receipt.result)
			and identifier(receipt.result.batchId) then
			advancedBatches[receipt.result.batchId]=receipt.result
		end
	end
	local function known(batchId: any): boolean
		return profile.batches[batchId]~=nil or soldBatches[batchId]~=nil
	end
	for operationId,receipt in profile.receipts do
		if not identifier(operationId) or not record(receipt,RECEIPT_FIELDS)
			or not identifier(receipt.actorId) or receipt.ownerUserId~=profile.ownerUserId then
			return false,"INVALID_RECEIPT"
		end
		local request,result=receipt.request,receipt.result
		local purchase=receipt.action=="Purchase"
		local advance=receipt.action=="Advance"
		local supply=purchase or advance
		local sale=receipt.action=="Sale"
		if supply then
			if receipt.actorKind~="Player" or receipt.carrierId~=nil
				or receipt.actorId~="Player/"..string.format("%.0f",profile.ownerUserId) then
				return false,"INVALID_RECEIPT"
			end
		elseif sale then
			if receipt.actorKind~="Player" or receipt.actorId~=playerActor(profile) or not saleIdentifier(operationId)
				or not carrierMatches(profile,receipt.carrierId,"Player") or deliveriesByOperation[operationId] then
				return false,"INVALID_RECEIPT"
			end
		elseif not carrierMatches(profile,receipt.carrierId,receipt.actorKind) or deliveriesByOperation[operationId] then
			return false,"INVALID_RECEIPT"
		end
		local reserve=receipt.action=="Reserve"
		local commit=receipt.action=="Commit"
		if not supply and not sale and not reserve and not commit and receipt.action~="Cancel" then
			return false,"INVALID_RECEIPT_ACTION"
		end
		if not record(request,if supply or sale then PURCHASE_REQUEST_FIELDS elseif reserve then RESERVE_REQUEST_FIELDS else CLAIM_REQUEST_FIELDS)
			or request.operationId~=operationId or not integer(request.expectedRevision,0)
			or request.expectedRevision==MAX_INTEGER then return false,"INVALID_RECEIPT_REQUEST" end
		if reserve then
			if not identifier(request.batchId) or not identifier(request.sourceId) or not identifier(request.targetId)
				or request.sourceId==request.targetId or request.quantity~=1
				or not profile.locations[request.sourceId] or not profile.locations[request.targetId]
				or not known(request.batchId)
				or (request.sourceId~=receipt.carrierId and request.targetId~=receipt.carrierId) then
				return false,"INVALID_RECEIPT_REQUEST"
			end
			if request.nextTargetId~=nil then
				if not State.isFirstWorkerPickup(receipt.actorKind,receipt.carrierId,request.sourceId,request.targetId,
					request.nextTargetId) then return false,"INVALID_RECEIPT_REQUEST" end
				local nextTarget=profile.locations[request.nextTargetId]
				local leg=State.workerLeg(request.sourceId,request.nextTargetId)
				if profile.locations[request.sourceId].kind~="StationOutput" or not nextTarget or not leg
					or nextTarget.kind~="StationInput" or not table.find(nextTarget.acceptedStages,leg.stage) then
					return false,"INVALID_RECEIPT_REQUEST"
				end
			end
			if request.recoverWorker~=nil and (request.recoverWorker~=true or request.nextTargetId~=nil
				or not State.isWorkerRecovery(profile,receipt.actorKind,receipt.actorId,receipt.carrierId,
					request.sourceId,request.targetId)) then return false,"INVALID_RECEIPT_REQUEST" end
		elseif not supply and not sale and not identifier(request.claimId) then
			return false,"INVALID_RECEIPT_REQUEST"
		end
		local fields=if purchase then PURCHASE_RESULT_FIELDS elseif advance then ADVANCE_RESULT_FIELDS
			elseif sale then SALE_RESULT_FIELDS elseif reserve then RESERVE_RESULT_FIELDS
			elseif commit then COMMIT_RESULT_FIELDS else CANCEL_RESULT_FIELDS
		local code=if purchase then "PURCHASED" elseif advance then "ADVANCED" elseif sale then "SOLD"
			elseif reserve then "RESERVED" elseif commit then "COMMITTED" else "CANCELLED"
		if not record(result,fields) or result.ok~=true or result.code~=code or not message(result.message)
			or not integer(result.revision,1) or result.revision~=request.expectedRevision+1
			or result.revision>profile.revision or receiptRevisions[result.revision] then
			return false,"INVALID_RECEIPT_RESULT"
		end
		receiptRevisions[result.revision]=true
		if supply then
			if not identifier(result.batchId) or not identifier(result.supplierId) or not identifier(result.rawSlotId)
				or result.batchId~=(if purchase then "purchase/" else "advance/")..operationId or not known(result.batchId)
				or not integer(if purchase then result.price else result.amount,1)
				or not profile.locations[result.supplierId] or profile.locations[result.supplierId].kind~="Supplier"
				or not profile.locations[result.rawSlotId] or profile.locations[result.rawSlotId].kind~="RawStore" then
				return false,"INVALID_RECEIPT_RESULT"
			end
			local promised=deliveriesByOperation[operationId]
			local batchPromise=deliveriesByBatch[result.batchId]
			if (batchPromise and batchPromise~=operationId)
				or (promised and (promised~=result.rawSlotId or profile.reservations[promised].batchId~=result.batchId)) then
				return false,"INVALID_DELIVERY_RESERVATION"
			end
			suppliesByBatch[result.batchId]={receipt=receipt, promised=promised~=nil}
		elseif sale then
			if not vehicleSlotOf(profile,result.vehicleId,result.slotId) or not identifier(result.batchId)
				or profile.batches[result.batchId] or soldBatches[result.batchId]~=operationId or result.quantity~=1
				or not quote(result.buyer,result.quoteMin,result.quoteMax,result.dealerValue)
				or not integer(result.amount,result.quoteMin) or result.amount>result.quoteMax then
				return false,"INVALID_RECEIPT_RESULT"
			end
			local advanced=advancedBatches[result.batchId]
			if advanced then
				if not integer(advanced.amount,1) or not integer(advanced.revision,1)
					or advanced.revision>=result.revision or not integer(result.balanceBefore,0)
					or not integer(result.repaid,0)
					or result.repaid~=State.advanceRepayment(result.balanceBefore,result.amount,advanced.amount)
					or result.balanceBefore>MAX_INTEGER-(result.amount-result.repaid) then
					return false,"INVALID_RECEIPT_RESULT"
				end
			elseif result.balanceBefore~=nil or (result.repaid~=nil and result.repaid~=0) then
				return false,"INVALID_RECEIPT_RESULT"
			end
		elseif reserve then
			if result.claimId~=operationId or not finite(result.expiresAt,0) or result.expiresAt==0 then
				return false,"INVALID_RECEIPT_RESULT"
			end
		elseif result.claimId~=request.claimId then
			return false,"INVALID_RECEIPT_RESULT"
		end
		if commit and (not identifier(result.batchId) or not identifier(result.sourceId) or not identifier(result.targetId)
			or result.sourceId==result.targetId or not known(result.batchId)
			or not profile.locations[result.sourceId] or not profile.locations[result.targetId]
			or (result.sourceId~=receipt.carrierId and result.targetId~=receipt.carrierId)) then
			return false,"INVALID_RECEIPT_RESULT"
		end
	end
	-- Historical completions bind the original Reserve, not today's stock location.
	local completedClaims: {[string]: boolean} = {}
	for _,receipt in profile.receipts do
		if receipt.action=="Reserve" or receipt.action=="Purchase" or receipt.action=="Advance"
			or receipt.action=="Sale" then continue end
		local claimId=receipt.request.claimId
		local reserved=profile.receipts[claimId]
		if not reserved or reserved.action~="Reserve" or reserved.actorId~=receipt.actorId
			or reserved.actorKind~=receipt.actorKind or reserved.carrierId~=receipt.carrierId
			or reserved.ownerUserId~=receipt.ownerUserId
			or reserved.result.revision>receipt.request.expectedRevision or completedClaims[claimId] then
			return false,"INVALID_RECEIPT_CLAIM"
		end
		if receipt.action=="Commit" and (receipt.result.batchId~=reserved.request.batchId
			or receipt.result.sourceId~=reserved.request.sourceId or receipt.result.targetId~=reserved.request.targetId) then
			return false,"INVALID_RECEIPT_RESULT"
		end
		completedClaims[claimId]=true
		if receipt.action=="Commit" then
			local supplied=suppliesByBatch[receipt.result.batchId]
			if supplied and receipt.result.targetId==supplied.receipt.result.rawSlotId
				and receipt.result.revision>supplied.receipt.result.revision then
				deliveriesCompleted[receipt.result.batchId]=true
			end
		end
	end
	for batchId,supplied in suppliesByBatch do
		if supplied.promised==(deliveriesCompleted[batchId]==true) then return false,"INVALID_DELIVERY_HISTORY" end
	end
	local lockedSlots: {[string]: boolean} = {}
	for claimId,claim in profile.claims do
		if not identifier(claimId) or not record(claim,CLAIM_FIELDS) or claim.id~=claimId
			or not identifier(claim.actorId) or not carrierMatches(profile,claim.carrierId,claim.actorKind)
			or not identifier(claim.batchId) or not identifier(claim.sourceId) or not identifier(claim.targetId)
			or claim.sourceId==claim.targetId or claim.quantity~=1
			or not finite(claim.expiresAt,0) or claim.expiresAt==0 then return false,"INVALID_CLAIM" end
		if completedClaims[claimId] then return false,"CLAIM_ALREADY_COMPLETED" end
		local batch=profile.batches[claim.batchId]
		local source,target=profile.locations[claim.sourceId],profile.locations[claim.targetId]
		if not batch or batch.locationId~=claim.sourceId or not source or not target
			or source.kind=="StationProcess" or target.kind=="StationProcess"
			or source.kind=="Machine" or target.kind=="Machine"
			or (source.id~=claim.carrierId and target.id~=claim.carrierId)
			or ((source.kind=="Carrier" or source.kind=="Band") and source.id~=claim.carrierId and claim.recoverWorker~=true)
			or ((target.kind=="Carrier" or target.kind=="Band") and target.id~=claim.carrierId)
			or counts[target.id]~=0 or not table.find(target.acceptedStages,batch.stage)
			or lockedSlots[source.id] or lockedSlots[target.id] then return false,"INVALID_CLAIM_LOCATIONS" end
		local hold=profile.reservations[target.id]
		if hold and (hold.batchId~=batch.id or (hold.kind=="Return" and not sameReturn(hold,claim,batch))) then
			return false,"INVALID_CLAIM_RESERVATION"
		end
		if target.kind=="StationOutput" and (not hold or hold.kind~="Return" or source.id~=claim.carrierId) then
			return false,"INVALID_CLAIM_OUTPUT"
		end
		local receipt=profile.receipts[claimId]
		if not receipt or receipt.action~="Reserve" or receipt.actorId~=claim.actorId
			or receipt.actorKind~=claim.actorKind or receipt.carrierId~=claim.carrierId
			or receipt.request.batchId~=claim.batchId or receipt.request.sourceId~=claim.sourceId
			or receipt.request.targetId~=claim.targetId or receipt.request.quantity~=claim.quantity
			or receipt.request.nextTargetId~=claim.nextTargetId
			or receipt.request.recoverWorker~=claim.recoverWorker
			or receipt.result.expiresAt~=claim.expiresAt then return false,"INVALID_CLAIM_RECEIPT" end
		if claim.recoverWorker and not State.hasWorkerRecoveryReturn(profile,batch) then
			return false,"INVALID_CLAIM_RESERVATION"
		end
		local nextTargetId=claim.nextTargetId
		if nextTargetId~=nil then
			local leg=State.workerLeg(claim.sourceId,nextTargetId)
			if not leg or batch.stage~=leg.stage or counts[nextTargetId]~=0 or lockedSlots[nextTargetId]
				or profile.reservations[nextTargetId] then return false,"INVALID_CLAIM_LOCATIONS" end
			lockedSlots[nextTargetId]=true
		end
		lockedSlots[source.id]=true
		lockedSlots[target.id]=true
	end
	local sale=profile.pendingSale
	if sale~=nil then
		if not record(sale,PENDING_SALE_FIELDS) or not saleIdentifier(sale.id) or profile.receipts[sale.id]
			or not vehicleSlotOf(profile,sale.vehicleId,sale.slotId)
			or not quote(sale.buyer,sale.quoteMin,sale.quoteMax,sale.dealerValue)
			or not integer(sale.seed,0) or sale.seed>State.MAX_SALE_SEED then
			return false,"INVALID_PENDING_SALE"
		end
		local batch=profile.batches[sale.batchId]
		local promise=profile.reservations[sale.slotId]
		if not carrierMatches(profile,sale.carrierId,"Player") or not batch or batch.stage~="Karton"
			or batch.locationId~=sale.carrierId or not promise or promise.kind~="Return" or promise.batchId~=batch.id
			or promise.carrierId~=sale.carrierId or promise.actorKind~="Player" or promise.actorId~=playerActor(profile) then
			return false,"INVALID_PENDING_SALE"
		end
	end
	-- P07-07: the open advance names its validated receipt and its unsold batch. While an advanced batch is in
	-- stock its advance stays open, so its sale always repays it; at most one advanced batch is in stock.
	local open=profile.advance
	if open~=nil then
		local granted=if record(open,ADVANCE_FIELDS) and identifier(open.operationId)
			then profile.receipts[open.operationId] else nil
		if not granted or granted.action~="Advance" or granted.result.batchId~=open.batchId
			or granted.result.amount~=open.amount or not profile.batches[open.batchId] or soldBatches[open.batchId] then
			return false,"INVALID_ADVANCE"
		end
	end
	for batchId in advancedBatches do
		if profile.batches[batchId] and (open==nil or open.batchId~=batchId) then return false,"INVALID_ADVANCE" end
	end
	return true,nil
end

return table.freeze(State)
