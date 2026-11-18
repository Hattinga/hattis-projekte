--!strict
-- P04-06: explicit storage calls, confirmed snapshots and fail-closed unknown outcomes.
-- Nothing starts automatically; even a confirmed storage call never sets ready=true.
local Profiles = require(script.Parent.Profiles)
local Sessions = require(script.Parent.Sessions)

export type Backend = {
	read read: (key: string) -> any,
	read update: (key: string, transform: (current: any) -> any) -> any,
}
export type Result = {ok: boolean, code: string, message: string, ready: boolean,
	key: string, status: string, confirmed: Sessions.Record?, unknown: boolean, inFlight: boolean}
export type Controller = {
	read load: (sessionId: any, ttlSeconds: any, initialize: any?) -> Result,
	read save: (candidate: any, ttlSeconds: any) -> Result,
	read release: () -> Result,
	read reconcile: () -> Result,
	read snapshot: () -> Result,
}

local Persistence = {}
local MAX_INTEGER = 9007199254740991
local RECORD_FIELDS = {sessionVersion=true, revision=true, sessionId=true, expiresAt=true, data=true}
local MESSAGES: {[string]: string} = {
	LOADED="Sitzungsbesitz und Profil wurden vom Speicher bestätigt; noch keine wirtschaftliche Freigabe.",
	SAVED="Dieser Profilstand wurde vom Speicher bestätigt.",
	RELEASED="Die Freigabe des Sitzungsbesitzes wurde vom Speicher bestätigt.",
	RECONCILED="Der zuvor unklare Schreibkandidat wurde durch frisches Rücklesen bestätigt.",
	SNAPSHOT="Letzten bestätigten Speicherstand gelesen.",
	BUSY="Ein Speicherzugriff läuft bereits. Sein Ergebnis muss zuerst feststehen.",
	ALREADY_LOADED="Diese Steuerung besitzt bereits einen bestätigten Sitzungsstand.",
	NOT_LOADED="Ein bestätigter Sitzungsbesitz fehlt.",
	NOT_PENDING="Es liegt kein unklarer Schreibvorgang vor.",
	LOAD_FAILED="Der Spielstand konnte nicht frisch gelesen werden. Es entstehen keine Ersatzstartdaten.",
	WRITE_UNKNOWN="Der Schreibausgang ist unklar. Weitere Schreibvorgänge bleiben bis zur Klärung gesperrt.",
	RECONCILE_UNKNOWN="Das frische Rücklesen bestätigt den eingereichten Kandidaten nicht. Der Ausgang bleibt unklar.",
	INVALID_REQUEST="Sitzungskennung oder Laufzeit ist ungültig.",
	INVALID_TIME="Die serverseitige UTC-Zeit ist ungültig.",
	INVALID_RECORD="Der gespeicherte Sitzungsumschlag ist ungültig.",
	UNSUPPORTED_SESSION_VERSION="Diese Sitzungsumschlagversion wird noch nicht unterstützt.",
	INVALID_PROFILE="Das Profil ist ungültig oder gehört einem anderen Eigentümer.",
	REVISION_OVERFLOW="Die nächste Ablaufzeit ist nicht sicher darstellbar.",
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
local function same(left: any, right: any): boolean
	if type(left)~=type(right) then return false end
	if type(left)~="table" then return left==right end
	for key,value in left do if not same(value,right[key]) then return false end end
	for key in right do if left[key]==nil then return false end end
	return true
end

-- Validate backend responses independently of the write decision. Sessions' record validator
-- is private; use its closed outer contract and reuse Profiles for every inner validation/copy.
local function record(saved: any, ownerUserId: number): (Sessions.Record?, string?)
	if not plain(saved) then return nil,"INVALID_RECORD" end
	for key in saved do if not RECORD_FIELDS[key] then return nil,"INVALID_RECORD" end end
	if not integer(saved.sessionVersion,1) then return nil,"INVALID_RECORD" end
	if saved.sessionVersion~=Sessions.VERSION then return nil,"UNSUPPORTED_SESSION_VERSION" end
	if not integer(saved.revision,1) or not integer(saved.expiresAt,0) then return nil,"INVALID_RECORD" end
	if saved.sessionId=="" then
		if saved.expiresAt~=0 then return nil,"INVALID_RECORD" end
	elseif not id(saved.sessionId) or saved.expiresAt==0 then return nil,"INVALID_RECORD" end
	if saved.data==nil then return nil,"INVALID_PROFILE" end
	local loaded=Profiles.load(ownerUserId,function(): any return saved.data end)
	if not loaded.ok or not loaded.data then return nil,"INVALID_PROFILE" end
	return {sessionVersion=Sessions.VERSION,revision=saved.revision,sessionId=saved.sessionId,
		expiresAt=saved.expiresAt,data=loaded.data},nil
end

-- The only engine-facing wrapper. The injected GlobalDataStore is selected by the caller.
-- A fresh options object avoids both GetAsync's cache and shared mutable read options.
function Persistence.dataStore(store: any): Backend
	assert(store~=nil and type(store.GetAsync)=="function" and type(store.UpdateAsync)=="function",
		"Expected a DataStore with GetAsync and UpdateAsync")
	local getAsync: any=store.GetAsync
	local updateAsync: any=store.UpdateAsync
	local backend: Backend={
		read=function(key: string): any
			local options=Instance.new("DataStoreGetOptions")
			options.UseCache=false
			return getAsync(store,key,options)
		end,
		update=function(key: string, transform: (current: any) -> any): any
			return updateAsync(store,key,function(current: any, keyInfo: any): (any, any?, any?)
				local updated=transform(current)
				if updated==nil then return nil end
				-- Returning these unchanged preserves existing backend metadata/user associations.
				if keyInfo then return updated,keyInfo:GetUserIds(),keyInfo:GetMetadata() end
				return updated
			end)
		end,
	}
	return table.freeze(backend)
end

-- One controller per owner and server session. Every injected callback is server-owned.
-- Backend.update must implement Roblox UpdateAsync semantics: atomic transform on the latest
-- value, nil transform return aborts, and successful return is the committed value (not a proposal).
-- The clock must be non-yielding integer UTC seconds, fresh on every invocation. Tokens are
-- unique per acquisition and generated outside transform retries. No module-global registry.
function Persistence.new(ownerUserId: any, backend: any, clock: any?): Controller
	assert(integer(ownerUserId,1),"Invalid persistence owner")
	assert(plain(backend) and type(backend.read)=="function" and type(backend.update)=="function",
		"Invalid persistence backend")
	assert(clock==nil or type(clock)=="function","Invalid persistence clock")
	local readProfile: (string) -> any=backend.read
	local updateProfile: (string,(any) -> any) -> any=backend.update
	local utc: () -> any=clock or function(): number return os.time() end
	local key="Player_" .. string.format("%.0f",ownerUserId)
	local status="Empty"
	local busy=false
	local confirmed: Sessions.Record?=nil
	local sessionToken: string?=nil
	local pending: {kind: string, proposal: Sessions.Record?}?=nil

	local function reply(code: string, ok: boolean, message: string?): Result
		local detached: Sessions.Record?=nil
		if confirmed then detached=record(confirmed,ownerUserId) end
		return {ok=ok,code=code,message=MESSAGES[code] or message or code,ready=false,
			key=key,status=status,confirmed=detached,unknown=status=="Unknown",inFlight=busy}
	end
	local function finish(code: string, ok: boolean, message: string?): Result
		busy=false
		return reply(code,ok,message)
	end
	local function now(): number
		local value=utc()
		assert(integer(value,0),"Invalid server UTC time")
		return value
	end
	local function preflightTime(ttlSeconds: any?): (number?, string?)
		local ok,value=pcall(now)
		if not ok then return nil,"INVALID_TIME" end
		if ttlSeconds~=nil then
			if not integer(ttlSeconds,1) then return nil,"INVALID_REQUEST" end
			if ttlSeconds>MAX_INTEGER-value then return nil,"REVISION_OVERFLOW" end
		end
		return value,nil
	end
	local function accept(saved: Sessions.Record): ()
		confirmed=record(saved,ownerUserId)
		assert(confirmed)
		sessionToken=if saved.sessionId=="" then nil else saved.sessionId
		status=if saved.sessionId=="" then "Released" else "Confirmed"
		pending=nil
	end

	-- This call performs exactly one backend update. Roblox may repeat the callback; each
	-- invocation uses fresh UTC and the same expected revision/token/detached data candidate.
	local function atomic(kind: string, expectedRevision: number, token: string,
		ttlSeconds: number?, candidate: Profiles.Envelope?): Result
		local proposal: Sessions.Record?=nil
		local lastDecision: Sessions.Result?=nil
		local updateOk,returned=pcall(updateProfile,key,function(current: any): any
			local decision: Sessions.Result
			if kind=="Acquire" then
				decision=Sessions.acquire(current,ownerUserId,expectedRevision,token,now(),ttlSeconds,candidate)
			elseif kind=="Write" then
				decision=Sessions.write(current,ownerUserId,expectedRevision,token,now(),ttlSeconds,candidate)
			else
				decision=Sessions.release(current,ownerUserId,expectedRevision,token,now())
			end
			lastDecision=decision
			if not decision.ok or not decision.record then return nil end
			-- Keep a private copy: neither backend aliases nor its returned value can mutate it.
			proposal=record(decision.record,ownerUserId)
			return decision.record
		end)
		if updateOk and returned==nil and lastDecision and not lastDecision.ok then
			-- A completed UpdateAsync with its last callback returning nil is a confirmed abort.
			return finish(lastDecision.code,false,lastDecision.message)
		end
		local saved: Sessions.Record?=nil
		if updateOk then saved=record(returned,ownerUserId) end
		if updateOk and saved and proposal and lastDecision and lastDecision.ok and same(saved,proposal) then
			accept(saved)
			return finish(if kind=="Acquire" then "LOADED" elseif kind=="Write" then "SAVED" else "RELEASED",true,nil)
		end
		-- Throw, missing callback or mismatched response is not proof that nothing was stored.
		-- Never copy a returned foreign/malformed value into the last-confirmed snapshot.
		status="Unknown"
		pending={kind=kind,proposal=proposal}
		return finish("WRITE_UNKNOWN",false,nil)
	end

	local controller: Controller={
		load=function(token: any, ttlSeconds: any, initialize: any?): Result
			if busy then return reply("BUSY",false,nil) end
			if status=="Unknown" then return reply("WRITE_UNKNOWN",false,nil) end
			if status=="Confirmed" then return reply("ALREADY_LOADED",false,nil) end
			if not id(token) or not integer(ttlSeconds,1) then return reply("INVALID_REQUEST",false,nil) end
			busy=true
			local timestamp,timeProblem=preflightTime(ttlSeconds)
			if not timestamp then return finish(timeProblem :: string,false,nil) end
			local readOk,raw=pcall(readProfile,key)
			if not readOk then return finish("LOAD_FAILED",false,nil) end
			local expectedRevision=0
			local seed: Profiles.Envelope?=nil
			if raw==nil then
				-- Only a successful fresh nil read enters the initializer, exactly once here.
				local loaded=Profiles.load(ownerUserId,function(): any return nil end,initialize)
				if not loaded.ok then return finish(loaded.code,false,loaded.message) end
				seed=loaded.data
			else
				local saved,problem=record(raw,ownerUserId)
				if not saved then return finish(problem :: string,false,nil) end
				expectedRevision=saved.revision
			end
			-- A concurrent create/update after the read wins at this CAS. No fallback/retry.
			return atomic("Acquire",expectedRevision,token,ttlSeconds,seed)
		end,
		save=function(candidate: any, ttlSeconds: any): Result
			if busy then return reply("BUSY",false,nil) end
			if status=="Unknown" then return reply("WRITE_UNKNOWN",false,nil) end
			local base=confirmed
			local token=sessionToken
			if status~="Confirmed" or not base or not token then return reply("NOT_LOADED",false,nil) end
			if not integer(ttlSeconds,1) then return reply("INVALID_REQUEST",false,nil) end
			busy=true
			local timestamp,timeProblem=preflightTime(ttlSeconds)
			if not timestamp then return finish(timeProblem :: string,false,nil) end
			-- Validate and detach before the first backend yield; callers cannot change retries.
			local checked=Sessions.write(base,ownerUserId,base.revision,token,timestamp,ttlSeconds,candidate)
			if not checked.ok or not checked.record then return finish(checked.code,false,checked.message) end
			return atomic("Write",base.revision,token,ttlSeconds,checked.record.data)
		end,
		release=function(): Result
			if busy then return reply("BUSY",false,nil) end
			if status=="Unknown" then return reply("WRITE_UNKNOWN",false,nil) end
			local base=confirmed
			local token=sessionToken
			if status~="Confirmed" or not base or not token then return reply("NOT_LOADED",false,nil) end
			busy=true
			local timestamp,timeProblem=preflightTime(nil)
			if not timestamp then return finish(timeProblem :: string,false,nil) end
			local checked=Sessions.release(base,ownerUserId,base.revision,token,timestamp)
			if not checked.ok then return finish(checked.code,false,checked.message) end
			return atomic("Release",base.revision,token,nil,nil)
		end,
		reconcile=function(): Result
			if busy then return reply("BUSY",false,nil) end
			local unresolved=pending
			if status~="Unknown" or not unresolved then return reply("NOT_PENDING",false,nil) end
			busy=true
			local readOk,raw=pcall(readProfile,key)
			local saved: Sessions.Record?=nil
			if readOk then saved=record(raw,ownerUserId) end
			if saved and unresolved.proposal and same(saved,unresolved.proposal) then
				accept(saved)
				return finish("RECONCILED",true,nil)
			end
			-- Seeing the base unchanged does NOT fence a delayed write. Seeing a newer/foreign
			-- value also does not prove this candidate's exact history. Stay blocked in both cases.
			return finish("RECONCILE_UNKNOWN",false,nil)
		end,
		snapshot=function(): Result
			return reply("SNAPSHOT",true,nil)
		end,
	}
	return table.freeze(controller)
end

return table.freeze(Persistence)
