--!strict
-- P04-03: shared read-only hop/claim/promise checks. Actor context comes from the server.
-- No remotes or active profiles; caller must later enforce reach/zone and persistence readiness.
local State=require(script.Parent.State)
export type Result={ok: boolean,code: string,message: string}
local Actions={}
local MESSAGES={
	OK="Übergabe zulässig.",NOT_READY="Der Spielstand ist noch nicht freigegeben.",
	NOT_AUTHORIZED="Du darfst diesen Bestand nicht verändern.",
	INVALID_STATE="Der Bestand kann gerade nicht geprüft werden.",
	INVALID_REQUEST="Die Aktion enthält ungültige Angaben.",
	INVALID_QUANTITY="Eine Übergabe bewegt genau eine vollständige Charge.",
	STALE_REVISION="Der Bestand hat sich geändert. Bitte erneut versuchen.",
	UNKNOWN_BATCH="Diese Charge ist nicht mehr verfügbar.",
	SOURCE_CHANGED="Die Ware liegt inzwischen an einem anderen Ort.",
	UNKNOWN_LOCATION="Der Übergabeplatz ist nicht verfügbar.",
	SAME_LOCATION="Die Ware liegt bereits dort.",
	PROCESS_SLOT="Der Arbeitsbereich wird von der Maschine belegt.",
	WRONG_CARRIER="Verwende den zugeordneten Träger.",
	CARRIER_STEP_REQUIRED="Ware muss über den zugeordneten Träger bewegt werden.",
	WRONG_STAGE="Diese Ware passt nicht auf den Zielplatz.",
	TARGET_FULL="Der Zielplatz ist belegt.",
	INVALID_TIME="Die Serverzeit ist ungültig.",
	SOURCE_RESERVED="Ware oder Quellplatz ist bereits reserviert.",
	TARGET_RESERVED="Der Zielplatz ist bereits reserviert.",
	RETURN_REQUIRED="Für die getragene Ware fehlt der garantierte Rückgabeplatz.",
	RETURN_MISMATCH="Die Rückgabe gehört zu einer anderen Charge oder einem anderen Träger.",
	OUTPUT_REQUIRES_RETURN="Ein Stationsausgang nimmt nur seine unveränderte Rückgabe an.",
	DELIVERY_TARGET_REQUIRED="Diese bezahlte Lieferung gehört auf ihren garantierten Rohstoffplatz.",
}
local REQUEST_FIELDS={operationId=true,expectedRevision=true,batchId=true,sourceId=true,targetId=true,
	nextTargetId=true,quantity=true}
local ACTOR_KINDS={Player=true,Worker=true,Band=true}
local function result(code: string): Result
	return {ok=code=="OK",code=code,message=MESSAGES[code]}
end
local function id(value: any): boolean
	return type(value)=="string" and #value>0 and #value<=128 and utf8.len(value)~=nil
end
local function accepts(location: any, stage: string): boolean
	if (location.kind=="Supplier" or location.kind=="RawStore") and stage~="Holzpaket" then return false end
	if location.kind=="FinishedStore" and stage~="Karton" then return false end
	if location.kind=="VehicleSlot" and stage~="Holzpaket" and stage~="Karton" then return false end
	return table.find(location.acceptedStages,stage)~=nil
end

-- With no server time, conservatively keep every unswept claim locked.
-- A commit may ignore only its own exact, actor-bound claim, never an arbitrary slot lock.
function Actions.checkTransfer(profile: any, actor: any, request: any, now: number?, ownClaimId: string?): Result
	if type(actor)~="table" or getmetatable(actor)~=nil or actor.ready~=true then return result("NOT_READY") end
	if not State.validate(profile) then return result("INVALID_STATE") end
	if actor.ownerUserId~=profile.ownerUserId or not ACTOR_KINDS[actor.kind] then return result("NOT_AUTHORIZED") end
	if type(request)~="table" or getmetatable(request)~=nil then return result("INVALID_REQUEST") end
	for key in request do if not REQUEST_FIELDS[key] then return result("INVALID_REQUEST") end end
	if not id(request.operationId) or not id(request.batchId) or not id(request.sourceId) or not id(request.targetId)
		or type(request.expectedRevision)~="number" or request.expectedRevision%1~=0
		or request.expectedRevision<0 or request.expectedRevision>9007199254740991 then
		return result("INVALID_REQUEST")
	end
	if request.quantity~=1 then return result("INVALID_QUANTITY") end
	if request.expectedRevision~=profile.revision then return result("STALE_REVISION") end
	local batch=profile.batches[request.batchId]
	if not batch then return result("UNKNOWN_BATCH") end
	if batch.locationId~=request.sourceId then return result("SOURCE_CHANGED") end
	local source,target=profile.locations[request.sourceId],profile.locations[request.targetId]
	if not source or not target then return result("UNKNOWN_LOCATION") end
	if source.id==target.id then return result("SAME_LOCATION") end
	if source.kind=="StationProcess" or target.kind=="StationProcess" or source.kind=="Machine" or target.kind=="Machine" then
		return result("PROCESS_SLOT")
	end
	if not id(actor.carrierLocationId) then return result("WRONG_CARRIER") end
	local carrier=profile.locations[actor.carrierLocationId]
	local carrierKind=actor.kind=="Band" and "Band" or "Carrier"
	if not carrier or carrier.kind~=carrierKind then return result("WRONG_CARRIER") end
	for _,location in {source,target} do
		if (location.kind=="Carrier" or location.kind=="Band") and location.id~=carrier.id then
			return result("WRONG_CARRIER")
		end
	end
	if source.id~=carrier.id and target.id~=carrier.id then return result("CARRIER_STEP_REQUIRED") end
	if not accepts(source,batch.stage) or not accepts(target,batch.stage) then return result("WRONG_STAGE") end
	if State.countAt(profile,target.id)>=target.capacity then return result("TARGET_FULL") end
	local nextTargetId=request.nextTargetId
	if nextTargetId~=nil then
		if not State.isFirstWorkerPickup(actor.kind,carrier.id,source.id,target.id,nextTargetId) then
			return result("INVALID_REQUEST")
		end
		local nextTarget=profile.locations[nextTargetId]
		if source.kind~="StationOutput" or not nextTarget or nextTarget.kind~="StationInput" then
			return result("UNKNOWN_LOCATION")
		end
		if batch.stage~=State.FIRST_WORKER.stage or not accepts(nextTarget,batch.stage) then return result("WRONG_STAGE") end
		if State.countAt(profile,nextTargetId)>=nextTarget.capacity then return result("TARGET_FULL") end
		if profile.reservations[nextTargetId] then return result("TARGET_RESERVED") end
	end
	if now~=nil and (type(now)~="number" or now~=now or now<0 or now>9007199254740991) then
		return result("INVALID_TIME")
	end
	for claimId,claim in profile.claims do
		local own=claimId==ownClaimId and claim.actorId==actor.actorId and claim.actorKind==actor.kind
			and claim.carrierId==carrier.id and claim.batchId==batch.id
			and claim.sourceId==source.id and claim.targetId==target.id and claim.quantity==request.quantity
			and claim.nextTargetId==nextTargetId
		if not own and (now==nil or now<claim.expiresAt) then
			if State.claimTouches(claim,source.id) then return result("SOURCE_RESERVED") end
			if State.claimTouches(claim,target.id) or (nextTargetId~=nil and State.claimTouches(claim,nextTargetId)) then
				return result("TARGET_RESERVED")
			end
		end
	end
	local returnLocationId,returnReservation=nil,nil
	for locationId,reservation in profile.reservations do
		if reservation.kind=="Return" and reservation.batchId==batch.id then
			returnLocationId,returnReservation=locationId,reservation
		end
		if reservation.kind=="Delivery" and reservation.batchId==batch.id
			and target.id~=carrier.id and target.id~=locationId
			and target.kind~="Supplier" and target.kind~="VehicleSlot" then
			return result("DELIVERY_TARGET_REQUIRED")
		end
	end
	if source.id==carrier.id then
		if not returnReservation then return result("RETURN_REQUIRED") end
		if returnReservation.actorId~=actor.actorId or returnReservation.actorKind~=actor.kind
			or returnReservation.carrierId~=carrier.id then return result("RETURN_MISMATCH") end
	end
	local hold=profile.reservations[target.id]
	if hold and (hold.batchId~=batch.id or (hold.kind=="Return"
		and (source.id~=carrier.id or target.id~=returnLocationId))) then return result("TARGET_RESERVED") end
	if target.kind=="StationOutput" and (not hold or hold.kind~="Return" or source.id~=carrier.id) then
		return result("OUTPUT_REQUIRES_RETURN")
	end
	return result("OK")
end

return table.freeze(Actions)
