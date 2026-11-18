--!strict
-- P04-05: pure atomic transforms and a local publication gate. No backend/startup.
-- Apply transforms INSIDE UpdateAsync; checking before SetAsync is not fencing.
local Profiles = require(script.Parent.Profiles)

export type Record = {sessionVersion: number, revision: number, sessionId: string,
	expiresAt: number, data: Profiles.Envelope}
export type Result = {ok: boolean, code: string, message: string, ready: boolean, record: Record?}
export type Gate = {
	read begin: (sessionId: any) -> (any?, Result),
	read publish: (ticket: any, saved: any, now: any) -> Result,
	read close: (ticket: any) -> Result,
	read snapshot: (now: any) -> Result,
}

local Sessions = {}
Sessions.VERSION = 1
local MAX_INTEGER = 9007199254740991
local FIELDS = {sessionVersion=true, revision=true, sessionId=true, expiresAt=true, data=true}
local MESSAGES: {[string]: string} = {
	ACQUIRED="Sitzungsbesitz übernommen; wirtschaftliche Freigabe steht noch aus.",
	WRITTEN="Schreibkandidat geprüft; Backend-Bestätigung steht außerhalb dieser Grenze.",
	RELEASED="Sitzungsbesitz freigegeben.",
	STARTED="Neuer lokaler Ladeversuch begonnen.",
	PUBLISHED="Sitzungsstand lokal übernommen; wirtschaftliche Freigabe steht noch aus.",
	CLOSED="Lokaler Sitzungsstand verworfen.",
	SNAPSHOT="Abgetrennten lokalen Sitzungsstand gelesen.",
	INVALID_OWNER="Die Eigentümerkennung ist ungültig.",
	INVALID_REQUEST="Sitzungskennung oder erwartete Speicherrevision ist ungültig.",
	INVALID_TIME="Sitzungszeit oder Laufzeit ist ungültig.",
	INVALID_RECORD="Der gespeicherte Sitzungsumschlag ist ungültig.",
	UNSUPPORTED_SESSION_VERSION="Diese Sitzungsumschlagversion wird noch nicht unterstützt.",
	INVALID_PROFILE="Das Profil ist ungültig oder gehört zu einem anderen Eigentümer.",
	INITIAL_DATA_REQUIRED="Ein bestätigtes Startmuster fehlt; es werden keine Ersatzdaten erzeugt.",
	STALE_REVISION="Die Speicherrevision hat sich geändert.",
	SESSION_BUSY="Eine andere Sitzung besitzt den Spielstand noch.",
	SESSION_LOST="Diese Sitzung besitzt den Spielstand nicht mehr.",
	SESSION_EXPIRED="Die Sitzung ist abgelaufen.",
	STALE_STATE="Der Bestandsstand ist älter oder bei gleicher Revision verändert.",
	REVISION_OVERFLOW="Die nächste Revision oder Ablaufzeit ist nicht sicher darstellbar.",
	STALE_ATTEMPT="Dieser lokale Ladeversuch wurde abgelöst.",
	NOT_LOADED="Es liegt kein gültiger lokaler Sitzungsstand vor.",
}

local function integer(value: any, minimum: number): boolean
	return type(value)=="number" and value==value and value>=minimum
		and value<=MAX_INTEGER and value%1==0
end
local function id(value: any): boolean
	return type(value)=="string" and #value>0 and #value<=128 and utf8.len(value)~=nil
end
local function plain(value: any): boolean
	return type(value)=="table" and getmetatable(value)==nil
end
local function result(code: string, saved: Record?): Result
	return {ok=code=="ACQUIRED" or code=="WRITTEN" or code=="RELEASED" or code=="STARTED"
		or code=="PUBLISHED" or code=="CLOSED" or code=="SNAPSHOT",
		code=code, message=MESSAGES[code], ready=false, record=saved}
end
local function same(left: any, right: any): boolean
	if type(left)~=type(right) then return false end
	if type(left)~="table" then return left==right end
	for key,value in left do if not same(value,right[key]) then return false end end
	for key in right do if left[key]==nil then return false end end
	return true
end
-- Reuse the closed Profiles/State validator and copy; the private reader never yields.
local function profile(data: any, ownerUserId: number): Profiles.Envelope?
	if data==nil then return nil end -- nil must not enter Profiles' initializer branch.
	local loaded=Profiles.load(ownerUserId,function(): any return data end)
	return if loaded.ok then loaded.data else nil
end
local function record(saved: any, ownerUserId: number): (Record?, string?)
	if not plain(saved) then return nil,"INVALID_RECORD" end
	for key in saved do if not FIELDS[key] then return nil,"INVALID_RECORD" end end
	if not integer(saved.sessionVersion,1) then return nil,"INVALID_RECORD" end
	if saved.sessionVersion~=Sessions.VERSION then return nil,"UNSUPPORTED_SESSION_VERSION" end
	if not integer(saved.revision,1) or not integer(saved.expiresAt,0) then return nil,"INVALID_RECORD" end
	if saved.sessionId=="" then
		if saved.expiresAt~=0 then return nil,"INVALID_RECORD" end
	elseif not id(saved.sessionId) or saved.expiresAt==0 then return nil,"INVALID_RECORD" end
	local data=profile(saved.data,ownerUserId)
	if not data then return nil,"INVALID_PROFILE" end
	return {sessionVersion=Sessions.VERSION, revision=saved.revision, sessionId=saved.sessionId,
		expiresAt=saved.expiresAt, data=data},nil
end
local function request(ownerUserId: any, expectedRevision: any, sessionId: any, now: any): string?
	if not integer(ownerUserId,1) then return "INVALID_OWNER" end
	if not integer(expectedRevision,0) or not id(sessionId) then return "INVALID_REQUEST" end
	if not integer(now,0) then return "INVALID_TIME" end
	return nil
end
local function expiry(now: number, ttlSeconds: any): (number?, string?)
	if not integer(ttlSeconds,1) then return nil,"INVALID_TIME" end
	if ttlSeconds>MAX_INTEGER-now then return nil,"REVISION_OVERFLOW" end
	return now+ttlSeconds,nil
end
local function owned(current: any, ownerUserId: number, expectedRevision: number,
	sessionId: string, now: number): (Record?, string?)
	local saved,problem=record(current,ownerUserId)
	if not saved then return nil,problem end
	if saved.revision~=expectedRevision then return nil,"STALE_REVISION" end
	if saved.sessionId~=sessionId then return nil,"SESSION_LOST" end
	if now>=saved.expiresAt then return nil,"SESSION_EXPIRED" end
	if saved.revision==MAX_INTEGER then return nil,"REVISION_OVERFLOW" end
	return saved,nil
end

-- current is the latest value supplied by the atomic backend transform, never GetAsync cache.
-- Recompute trusted integer UTC now INSIDE every callback invocation/retry, after any backend yield.
-- seed is a prevalidated P04-04 result's data; it is considered ONLY at atomic confirmed absence.
-- Tokens must be unique per acquisition and generated by the server outside transform retries.
function Sessions.acquire(current: any, ownerUserId: any, expectedRevision: any, sessionId: any,
	now: any, ttlSeconds: any, seed: any?): Result
	local problem=request(ownerUserId,expectedRevision,sessionId,now)
	if problem then return result(problem,nil) end
	local expiresAt,timeProblem=expiry(now,ttlSeconds)
	if not expiresAt then return result(timeProblem :: string,nil) end
	local saved: Record?
	if current==nil then
		if expectedRevision~=0 then return result("STALE_REVISION",nil) end
		if seed==nil then return result("INITIAL_DATA_REQUIRED",nil) end
		local data=profile(seed,ownerUserId)
		if not data then return result("INVALID_PROFILE",nil) end
		saved={sessionVersion=Sessions.VERSION,revision=0,sessionId="",expiresAt=0,data=data}
	else
		saved,problem=record(current,ownerUserId)
		if not saved then return result(problem :: string,nil) end
		if saved.revision~=expectedRevision then return result("STALE_REVISION",nil) end
		if saved.sessionId~="" and now<saved.expiresAt then return result("SESSION_BUSY",nil) end
	end
	assert(saved)
	if saved.revision==MAX_INTEGER then return result("REVISION_OVERFLOW",nil) end
	saved.revision+=1
	saved.sessionId=sessionId
	saved.expiresAt=expiresAt
	return result("ACQUIRED",saved)
end

-- Also serves as lease renewal: unchanged data keeps State revision, but storage revision advances.
-- A changed envelope must have a newer State revision, including changes to progress.
function Sessions.write(current: any, ownerUserId: any, expectedRevision: any, sessionId: any,
	now: any, ttlSeconds: any, candidate: any): Result
	local problem=request(ownerUserId,expectedRevision,sessionId,now)
	if problem then return result(problem,nil) end
	local expiresAt,timeProblem=expiry(now,ttlSeconds)
	if not expiresAt then return result(timeProblem :: string,nil) end
	local saved,ownershipProblem=owned(current,ownerUserId,expectedRevision,sessionId,now)
	if not saved then return result(ownershipProblem :: string,nil) end
	local data=profile(candidate,ownerUserId)
	if not data then return result("INVALID_PROFILE",nil) end
	if data.state.revision<saved.data.state.revision
		or (data.state.revision==saved.data.state.revision and not same(data,saved.data)) then
		return result("STALE_STATE",nil)
	end
	saved.revision+=1
	saved.expiresAt=math.max(saved.expiresAt,expiresAt)
	saved.data=data
	return result("WRITTEN",saved)
end

-- Save before release when needed. Release itself never accepts a caller's stale data snapshot.
function Sessions.release(current: any, ownerUserId: any, expectedRevision: any,
	sessionId: any, now: any): Result
	local problem=request(ownerUserId,expectedRevision,sessionId,now)
	if problem then return result(problem,nil) end
	local saved,ownershipProblem=owned(current,ownerUserId,expectedRevision,sessionId,now)
	if not saved then return result(ownershipProblem :: string,nil) end
	saved.revision+=1
	saved.sessionId=""
	saved.expiresAt=0
	return result("RELEASED",saved)
end

-- Per-owner local gate; opaque attempt identity survives yield/reentrancy without a global registry.
-- The later P04-06 adapter must feed confirmed backend results, never a merely proposed transform.
function Sessions.newGate(ownerUserId: any): Gate
	assert(integer(ownerUserId,1),"Invalid gate owner")
	local attempt: any=nil
	local token: string?=nil
	local active: Record?=nil
	local gate: Gate={
		begin=function(sessionId: any): (any?, Result)
			if not id(sessionId) then return nil,result("INVALID_REQUEST",nil) end
			attempt=table.freeze({})
			token=sessionId
			active=nil
			return attempt,result("STARTED",nil)
		end,
		publish=function(ticket: any, saved: any, now: any): Result
			if attempt==nil or ticket~=attempt then return result("STALE_ATTEMPT",nil) end
			if not integer(now,0) then return result("INVALID_TIME",nil) end
			local data,problem=record(saved,ownerUserId)
			if not data then return result(problem :: string,nil) end
			if data.sessionId~=token then return result("SESSION_LOST",nil) end
			if now>=data.expiresAt then return result("SESSION_EXPIRED",nil) end
			if active and data.revision<=active.revision then return result("STALE_REVISION",nil) end
			if active and (data.data.state.revision<active.data.state.revision
				or (data.data.state.revision==active.data.state.revision and not same(data.data,active.data))) then
				return result("STALE_STATE",nil)
			end
			active=data
			-- Detach the returned record too; callers cannot mutate the gate's private copy.
			local detached=record(data,ownerUserId)
			return result("PUBLISHED",detached)
		end,
		close=function(ticket: any): Result
			if attempt==nil or ticket~=attempt then return result("STALE_ATTEMPT",nil) end
			attempt=nil
			token=nil
			active=nil
			return result("CLOSED",nil)
		end,
		snapshot=function(now: any): Result
			if not integer(now,0) then return result("INVALID_TIME",nil) end
			if not active then return result("NOT_LOADED",nil) end
			if now>=active.expiresAt then return result("SESSION_EXPIRED",nil) end
			local detached=record(active,ownerUserId)
			return result("SNAPSHOT",detached)
		end,
	}
	return table.freeze(gate)
end

return table.freeze(Sessions)
