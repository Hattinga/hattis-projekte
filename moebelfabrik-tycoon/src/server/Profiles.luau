--!strict
-- P04-04: pure versioned loading boundary. No active registry, startup or storage access.
-- A trusted reader returns the raw saved value (nil only for confirmed absence), or throws.
local State = require(script.Parent.State)
local Recipes = require(script.Parent.Recipes)

export type WorkerHire = {revision: number, price: number, assigned: boolean?, route: string?}
export type BeltPermit = {revision: number, price: number, sourceId: string, targetId: string, stopped: boolean?}
export type Progress = {version: number, selectedRecipeId: string, selectedRecipeVersion: number,
	firstWorker: WorkerHire?, firstBelt: BeltPermit?}
export type Envelope = {profileVersion: number, state: State.Profile, progress: Progress}
export type Result = {ok: boolean, code: string, message: string, ready: boolean,
	key: string?, origin: string?, data: Envelope?}

local Profiles = {}
Profiles.VERSION = 1
Profiles.PROGRESS_VERSION = 1
local MAX_INTEGER = 9007199254740991
local ENVELOPE_FIELDS = {profileVersion=true, state=true, progress=true}
local PROGRESS_FIELDS = {version=true, selectedRecipeId=true, selectedRecipeVersion=true, firstWorker=true, firstBelt=true}
local WORKER_HIRE_FIELDS = {revision=true, price=true, assigned=true, route=true}
local BELT_PERMIT_FIELDS = {revision=true, price=true, sourceId=true, targetId=true, stopped=true}
local MESSAGES: {[string]: string} = {
	LOADED="Gespeichertes Profil geladen; wirtschaftliche Freigabe steht noch aus.",
	INITIALIZED="Fehlendes Profil bestätigt und Startmuster erstellt; noch nicht gespeichert oder freigegeben.",
	INVALID_OWNER="Die Eigentümerkennung ist ungültig.",
	INVALID_READER="Der serverseitige Lesezugriff fehlt.",
	LOAD_FAILED="Der Spielstand konnte nicht geladen werden. Wirtschaftliche Aktionen bleiben gesperrt.",
	INVALID_PROFILE="Das gespeicherte Profil hat ein ungültiges Format.",
	UNSUPPORTED_PROFILE_VERSION="Diese Profilversion wird noch nicht unterstützt.",
	UNSUPPORTED_STATE_VERSION="Diese Bestandsversion wird noch nicht unterstützt.",
	INVALID_PROGRESS="Der gespeicherte Werkstattfortschritt ist ungültig.",
	INVALID_STATE="Der gespeicherte Warenbestand ist ungültig.",
	OWNER_MISMATCH="Das gespeicherte Profil gehört zu einem anderen Eigentümer.",
	INVALID_INITIALIZER="Die serverseitige Startdatenerzeugung ist ungültig.",
	INITIALIZATION_FAILED="Die Startdaten konnten nicht erstellt werden. Wirtschaftliche Aktionen bleiben gesperrt.",
}

local function positiveInteger(value: any): boolean
	return type(value)=="number" and value==value and value>=1 and value<=MAX_INTEGER and value%1==0
end
local function plain(value: any): boolean
	return type(value)=="table" and getmetatable(value)==nil
end
local function record(value: any, fields: {[string]: boolean}): boolean
	if not plain(value) then return false end
	for key in value do if not fields[key] then return false end end
	return true
end
local function response(code: string, key: string?, origin: string?): Result
	return {ok=code=="LOADED" or code=="INITIALIZED", code=code, message=MESSAGES[code],
		ready=false, key=key, origin=origin}
end
local function validate(data: any, ownerUserId: number): string?
	if not record(data, ENVELOPE_FIELDS) or not positiveInteger(data.profileVersion) then return "INVALID_PROFILE" end
	if data.profileVersion~=Profiles.VERSION then return "UNSUPPORTED_PROFILE_VERSION" end
	local progress=data.progress
	-- P10-02: any registered recipe may be selected; its version must match the registered one.
	local selected=if type(progress)=="table" then Recipes.get(progress.selectedRecipeId) else nil
	if not record(progress, PROGRESS_FIELDS) or progress.version~=Profiles.PROGRESS_VERSION
		or not selected or progress.selectedRecipeVersion~=selected.version then
		return "INVALID_PROGRESS"
	end
	if not plain(data.state) then return "INVALID_STATE" end
	if data.state.schemaVersion~=State.SCHEMA_VERSION then return "UNSUPPORTED_STATE_VERSION" end
	if data.state.ownerUserId~=ownerUserId then return "OWNER_MISMATCH" end
	if not State.validate(data.state) then return "INVALID_STATE" end
	local worker=progress.firstWorker
	if worker~=nil and (not record(worker, WORKER_HIRE_FIELDS) or not positiveInteger(worker.price)
		or not positiveInteger(worker.revision) or worker.revision>data.state.revision
		or (worker.assigned~=nil and worker.assigned~=true)
		or (worker.assigned==true and worker.revision==data.state.revision)
		-- P09-06: only the Finish leg can replace the saw leg, and only once the belt exists.
		or (worker.route~=nil and (worker.route~="Finish" or worker.assigned~=true or progress.firstBelt==nil))) then
		return "INVALID_PROGRESS"
	end
	local belt=progress.firstBelt
	if belt~=nil and (not record(belt, BELT_PERMIT_FIELDS) or not positiveInteger(belt.price)
		or not positiveInteger(belt.revision) or belt.revision>data.state.revision
		or (belt.stopped~=nil and belt.stopped~=true)
		or belt.sourceId~=State.FIRST_BELT.source or belt.targetId~=State.FIRST_BELT.target) then
		return "INVALID_PROGRESS"
	end
	return nil
end
-- Validation bounds every record's depth and rejects metatables/cycles before this copy.
-- ponytail: full copies suit small profiles; review size/receipt policy before real profile activation.
local function copy(value: any): any
	if type(value)~="table" then return value end
	local result: any={}
	for key, item in value do result[key]=copy(item) end
	return result
end
local function initialData(ownerUserId: number): Envelope
	-- A non-economic schema specimen, not balanced game start data or a durable creation.
	return {profileVersion=Profiles.VERSION, state=State.newProfile(ownerUserId),
		progress={version=Profiles.PROGRESS_VERSION, selectedRecipeId=Recipes.DEFAULT_ID, selectedRecipeVersion=1}}
end

function Profiles.load(ownerUserId: any, readProfile: any, initialize: any?): Result
	if not positiveInteger(ownerUserId) then return response("INVALID_OWNER", nil, nil) end
	-- Fixed decimal formatting prevents scientific notation for large safe integer keys.
	local key="Player_" .. string.format("%.0f", ownerUserId)
	if type(readProfile)~="function" then return response("INVALID_READER", key, nil) end
	local readOk, data=pcall(readProfile, key)
	if not readOk then return response("LOAD_FAILED", key, nil) end
	local absent=data==nil
	local origin=if absent then "Absent" else "Existing"
	if absent then
		if initialize~=nil and type(initialize)~="function" then return response("INVALID_INITIALIZER", key, origin) end
		local createOk, created=pcall(initialize or initialData, ownerUserId)
		if not createOk then return response("INITIALIZATION_FAILED", key, origin) end
		data=created
	end
	local invalid=validate(data, ownerUserId)
	if invalid then return response(invalid, key, origin) end
	local loaded=response(if absent then "INITIALIZED" else "LOADED", key, origin)
	-- No yield/callback between validation and detachment; never publish into a caller's live store.
	loaded.data=copy(data)
	return loaded
end

return table.freeze(Profiles)
