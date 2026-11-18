--!strict
-- P04-03: artificial server-state transitions only. No yields or persistence.
local State=require(script.Parent.State)
local Actions=require(script.Parent.Actions)

export type Store = {profile: State.Profile}
export type Result = {ok: boolean, code: string, message: string, revision: number,
	claimId: string?, expiresAt: number?, batchId: string?, sourceId: string?, targetId: string?, expired: number?}
local Transfers={}
local MAX_INTEGER=9007199254740991
local ACTOR_KINDS: {[string]: boolean}={Player=true,Worker=true,Band=true}
local STORE_FIELDS={profile=true}
local RESERVE_FIELDS={operationId=true,expectedRevision=true,batchId=true,sourceId=true,targetId=true,quantity=true}
local CLAIM_FIELDS={operationId=true,expectedRevision=true,claimId=true}
local MESSAGES: {[string]: string}={
	RESERVED="Übergabe reserviert.",COMMITTED="Übergabe im Serverzustand verbucht.",
	CANCELLED="Unverbuchte Übergabe abgebrochen.",EXPIRED="Abgelaufene unverbuchte Reservierungen freigegeben.",
	INVALID_STORE="Der gemeinsame Zustandsbehälter ist nicht beschreibbar.",
	INVALID_STATE="Der Bestand kann gerade nicht geprüft werden.",
	NOT_READY="Der Spielstand ist noch nicht freigegeben.",
	NOT_AUTHORIZED="Du darfst diesen Bestand oder diese Reservierung nicht verändern.",
	INVALID_REQUEST="Die Aktion enthält ungültige Angaben.",
	INVALID_QUANTITY="Eine Übergabe bewegt genau eine vollständige Charge.",
	INVALID_TIME="Die Serverzeit oder Reservierungsdauer ist ungültig.",
	STALE_REVISION="Der Bestand hat sich geändert. Bitte erneut versuchen.",
	OPERATION_CONFLICT="Diese Vorgangs-ID gehört bereits zu anderen Angaben oder einem anderen Akteur.",
	REVISION_OVERFLOW="Die nächste Bestandsrevision kann nicht mehr sicher dargestellt werden.",
	SOURCE_RESERVED="Ware oder Quellplatz ist bereits reserviert.",
	TARGET_RESERVED="Der Zielplatz ist bereits reserviert.",
	CLAIM_NOT_FOUND="Diese unverbuchte Reservierung ist nicht mehr aktiv.",
	CLAIM_EXPIRED="Diese unverbuchte Reservierung ist abgelaufen.",
	RETURN_REQUIRED="Für die getragene Ware fehlt der garantierte Rückgabeplatz.",
	RETURN_MISMATCH="Die Rückgabe gehört zu einer anderen Charge oder einem anderen Träger.",
	OUTPUT_REQUIRES_RETURN="Ein Stationsausgang nimmt nur seine unveränderte Rückgabe an.",
	DELIVERY_TARGET_REQUIRED="Diese bezahlte Lieferung gehört auf ihren garantierten Rohstoffplatz.",
}

local function plain(value: any): boolean
	return type(value)=="table" and getmetatable(value)==nil
end
local function record(value: any, fields: {[string]: boolean}): boolean
	if not plain(value) then return false end
	for key in value do if not fields[key] then return false end end
	return true
end
local function finite(value: any, minimum: number): boolean
	return type(value)=="number" and value==value and value>=minimum and value<=MAX_INTEGER
end
local function integer(value: any, minimum: number): boolean
	return finite(value,minimum) and value%1==0
end
local function id(value: any): boolean
	return type(value)=="string" and #value>0 and #value<=128 and utf8.len(value)~=nil
end
-- Validated records have bounded depth and scalar keys; no metatables or cycles.
-- Small artificial profiles are copied in full instead of adding a path-copy framework.
local function copy(value: any): any
	if type(value)~="table" then return value end
	local result: any={}
	for key,item in value do result[key]=copy(item) end
	return result
end
local function result(code: string, revision: number): Result
	return {ok=code=="RESERVED" or code=="COMMITTED" or code=="CANCELLED" or code=="EXPIRED",
		code=code,message=MESSAGES[code] or code,revision=revision}
end
local function safeRevision(store: any): number
	if plain(store) and plain(store.profile) and integer(store.profile.revision,0) then return store.profile.revision end
	return 0
end
local function current(store: any): (any, Result?)
	local revision=safeRevision(store)
	if not record(store,STORE_FIELDS) or table.isfrozen(store) then return nil,result("INVALID_STORE",revision) end
	if not State.validate(store.profile) then return nil,result("INVALID_STATE",revision) end
	return store.profile,nil
end
local function sameRequest(left: any, right: any): boolean
	for key,value in left do if right[key]~=value then return false end end
	for key,value in right do if left[key]~=value then return false end end
	return true
end

-- Replay precedes stale revision, current batch location, capacity and lease checks.
local function enter(store: any, actor: any, request: any, action: string): (any, Result?)
	local profile,problem=current(store)
	if problem then return nil,problem end
	local revision=profile.revision
	if not plain(actor) or actor.ready~=true then return nil,result("NOT_READY",revision) end
	if actor.ownerUserId~=profile.ownerUserId or not ACTOR_KINDS[actor.kind] or not id(actor.actorId) then
		return nil,result("NOT_AUTHORIZED",revision)
	end
	if not id(actor.carrierLocationId) then return nil,result("NOT_AUTHORIZED",revision) end
	if not plain(request) or not id(request.operationId) then return nil,result("INVALID_REQUEST",revision) end
	local receipt=profile.receipts[request.operationId]
	if receipt then
		if receipt.action~=action or receipt.actorId~=actor.actorId or receipt.actorKind~=actor.kind
			or receipt.ownerUserId~=actor.ownerUserId or receipt.carrierId~=actor.carrierLocationId
			or not sameRequest(request,receipt.request) then
			return nil,result("OPERATION_CONFLICT",revision)
		end
		return nil,copy(receipt.result)
	end
	local reserve=action=="Reserve"
	if not record(request,if reserve then RESERVE_FIELDS else CLAIM_FIELDS)
		or not integer(request.expectedRevision,0) then return nil,result("INVALID_REQUEST",revision) end
	if reserve then
		if not id(request.batchId) or not id(request.sourceId) or not id(request.targetId) then
			return nil,result("INVALID_REQUEST",revision)
		end
		if request.quantity~=1 then return nil,result("INVALID_QUANTITY",revision) end
	elseif not id(request.claimId) then
		return nil,result("INVALID_REQUEST",revision)
	end
	if request.expectedRevision~=revision then return nil,result("STALE_REVISION",revision) end
	return profile,nil
end

local function returnFor(profile: any, batchId: string): (string?, any)
	for locationId,reservation in profile.reservations do
		if reservation.kind=="Return" and reservation.batchId==batchId then return locationId,reservation end
	end
	return nil,nil
end
local function actionProblem(profile: any, actor: any, request: any, now: number, ownClaimId: string?): Result?
	local checked=Actions.checkTransfer(profile,actor,request,now,ownClaimId)
	if checked.ok then return nil end
	return {ok=false,code=checked.code,message=checked.message,revision=profile.revision}
end
local function addReceipt(candidate: any, actor: any, action: string, request: any, response: Result)
	candidate.receipts[request.operationId]={actorId=actor.actorId,actorKind=actor.kind,
		ownerUserId=actor.ownerUserId,carrierId=actor.carrierLocationId,action=action,
		request=copy(request),result=copy(response)}
end
local function publish(store: Store, candidate: any, response: Result): Result
	if not State.validate(candidate) then return result("INVALID_STATE",store.profile.revision) end
	-- No fallible user callback or yield between validation and this single publication.
	store.profile=candidate
	return copy(response)
end
local function claimActorMatches(claim: any, actor: any): boolean
	return claim.actorId==actor.actorId and claim.actorKind==actor.kind and claim.carrierId==actor.carrierLocationId
end

function Transfers.new(profile: any): Store
	assert(State.validate(profile),"Invalid artificial profile")
	return {profile=copy(profile)}
end

function Transfers.reserve(store: any, actor: any, request: any, now: any, ttlSeconds: any): Result
	local profile,problem=enter(store,actor,request,"Reserve")
	if problem then return problem end
	if not finite(now,0) or not finite(ttlSeconds,0) or ttlSeconds<=0
		or ttlSeconds>MAX_INTEGER-now or now+ttlSeconds<=now then return result("INVALID_TIME",profile.revision) end
	local checked=actionProblem(profile,actor,request,now,nil)
	if checked then return checked end
	if profile.revision==MAX_INTEGER then return result("REVISION_OVERFLOW",profile.revision) end
	local candidate=copy(profile)
	for claimId,claim in candidate.claims do
		if now>=claim.expiresAt then candidate.claims[claimId]=nil end
	end
	local expiresAt=now+ttlSeconds
	candidate.claims[request.operationId]={id=request.operationId,actorId=actor.actorId,actorKind=actor.kind,
		carrierId=actor.carrierLocationId,batchId=request.batchId,sourceId=request.sourceId,
		targetId=request.targetId,quantity=1,expiresAt=expiresAt}
	candidate.revision+=1
	local response=result("RESERVED",candidate.revision)
	response.claimId=request.operationId
	response.expiresAt=expiresAt
	addReceipt(candidate,actor,"Reserve",request,response)
	return publish(store,candidate,response)
end

function Transfers.commit(store: any, actor: any, request: any, now: any): Result
	local profile,problem=enter(store,actor,request,"Commit")
	if problem then return problem end
	if not finite(now,0) then return result("INVALID_TIME",profile.revision) end
	local claim=profile.claims[request.claimId]
	if not claim then return result("CLAIM_NOT_FOUND",profile.revision) end
	if not claimActorMatches(claim,actor) then return result("NOT_AUTHORIZED",profile.revision) end
	if now>=claim.expiresAt then return result("CLAIM_EXPIRED",profile.revision) end
	local hop={operationId=request.operationId,expectedRevision=request.expectedRevision,batchId=claim.batchId,
		sourceId=claim.sourceId,targetId=claim.targetId,quantity=claim.quantity}
	local checked=actionProblem(profile,actor,hop,now,request.claimId)
	if checked then return checked end
	if profile.revision==MAX_INTEGER then return result("REVISION_OVERFLOW",profile.revision) end
	local candidate=copy(profile)
	local batch=candidate.batches[claim.batchId]
	if claim.targetId==actor.carrierLocationId then
		candidate.reservations[claim.sourceId]={kind="Return",batchId=batch.id,actorId=actor.actorId,
			actorKind=actor.kind,carrierId=actor.carrierLocationId,recipeId=batch.recipeId,
			recipeVersion=batch.recipeVersion,stage=batch.stage,quantity=batch.quantity}
	else
		local originId=returnFor(candidate,batch.id)
		candidate.reservations[originId :: string]=nil
		local hold=candidate.reservations[claim.targetId]
		if hold and hold.kind=="Delivery" and hold.batchId==batch.id then candidate.reservations[claim.targetId]=nil end
	end
	batch.locationId=claim.targetId
	candidate.claims[request.claimId]=nil
	candidate.revision+=1
	local response=result("COMMITTED",candidate.revision)
	response.claimId=request.claimId
	response.batchId=claim.batchId
	response.sourceId=claim.sourceId
	response.targetId=claim.targetId
	addReceipt(candidate,actor,"Commit",request,response)
	return publish(store,candidate,response)
end

function Transfers.cancel(store: any, actor: any, request: any, now: any): Result
	local profile,problem=enter(store,actor,request,"Cancel")
	if problem then return problem end
	if not finite(now,0) then return result("INVALID_TIME",profile.revision) end
	local claim=profile.claims[request.claimId]
	if not claim then return result("CLAIM_NOT_FOUND",profile.revision) end
	if not claimActorMatches(claim,actor) then return result("NOT_AUTHORIZED",profile.revision) end
	if now>=claim.expiresAt then return result("CLAIM_EXPIRED",profile.revision) end
	if profile.revision==MAX_INTEGER then return result("REVISION_OVERFLOW",profile.revision) end
	local candidate=copy(profile)
	candidate.claims[request.claimId]=nil
	candidate.revision+=1
	local response=result("CANCELLED",candidate.revision)
	response.claimId=request.claimId
	addReceipt(candidate,actor,"Cancel",request,response)
	return publish(store,candidate,response)
end

function Transfers.expireClaims(store: any, now: any): Result
	local profile,problem=current(store)
	if problem then return problem end
	if not finite(now,0) then return result("INVALID_TIME",profile.revision) end
	local expired=0
	for _,claim in profile.claims do if now>=claim.expiresAt then expired+=1 end end
	if expired==0 then
		local response=result("EXPIRED",profile.revision)
		response.expired=0
		return response
	end
	if profile.revision==MAX_INTEGER then return result("REVISION_OVERFLOW",profile.revision) end
	local candidate=copy(profile)
	for claimId,claim in candidate.claims do
		if now>=claim.expiresAt then candidate.claims[claimId]=nil end
	end
	candidate.revision+=1
	local response=result("EXPIRED",candidate.revision)
	response.expired=expired
	return publish(store,candidate,response)
end

return table.freeze(Transfers)
