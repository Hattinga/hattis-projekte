--!strict
-- Edit or Server; synthetic profiles, no mutations, remotes or DataStore access.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
local folder=game:GetService("ServerScriptService").Factory
local testFolder=folder:Clone();testFolder.Name="P0402TestCopy";testFolder.Parent=folder.Parent
local loaded,Actions=pcall(require,testFolder.Actions)
local State=require(testFolder.State)
testFolder:Destroy();assert(loaded,tostring(Actions))
local Http=game:GetService("HttpService")
local checks=0
local function fixture(): (any,any,any)
	local p=State.newProfile(101)
	local stages={"Holzpaket","Bausatz","Rohhocker","Fertig","Karton"}
	for _,spec in {{"raw/1","RawStore",{"Holzpaket"}},{"raw/2","RawStore",{"Holzpaket"}},
		{"hand","Carrier",stages},{"worker","Carrier",stages},{"vehicle/A","VehicleSlot",{"Holzpaket","Karton"}},
		{"finished/1","FinishedStore",{"Karton"}},{"band","Band",{"Bausatz"}},
		{"saw/output","StationOutput",{"Bausatz"}},{"assembly/input","StationInput",{"Bausatz"}}} do
		p.locations[spec[1]]=State.newLocation(spec[1],spec[2],1,spec[3])
	end
	p.batches.a=State.newBatch("a",101,"Holzpaket","raw/1")
	return p,{ownerUserId=101,actorId="Player/101",kind="Player",carrierLocationId="hand",ready=true},
		{operationId="test:pickup",expectedRevision=0,batchId="a",sourceId="raw/1",targetId="hand",quantity=1}
end
local function case(change: (any,any,any)->(), expected: string): ()
	local p,a,r=fixture();change(p,a,r)
	local before=Http:JSONEncode(p)
	local response=Actions.checkTransfer(p,a,r)
	assert(response.code==expected and response.ok==(expected=="OK"),expected.." got "..response.code)
	assert(type(response.message)=="string" and #response.message>0,"Missing user feedback")
	assert(Http:JSONEncode(p)==before,"Read-only check changed stock")
	checks+=1
end
case(function() end,"OK")
case(function(p,a,r) a.ready=false end,"NOT_READY")
case(function(p,a,r) a.ready=nil end,"NOT_READY")
case(function(p,a,r) a.ownerUserId=202 end,"NOT_AUTHORIZED")
case(function(p,a,r) a.kind="ClientClaim" end,"NOT_AUTHORIZED")
case(function(p,a,r) r.actor={ownerUserId=101} end,"INVALID_REQUEST")
for _,quantity in {0,-1,2,0.5,0/0,math.huge,"1"} do
	case(function(p,a,r) r.quantity=quantity end,"INVALID_QUANTITY")
end
case(function(p,a,r) r.expectedRevision=1 end,"STALE_REVISION")
case(function(p,a,r) r.expectedRevision=0/0 end,"INVALID_REQUEST")
case(function(p,a,r) r.expectedRevision="0" end,"INVALID_REQUEST")
case(function(p,a,r) r.operationId="" end,"INVALID_REQUEST")
case(function(p,a,r) r.batchId="missing" end,"UNKNOWN_BATCH")
case(function(p,a,r) r.sourceId="raw/2" end,"SOURCE_CHANGED")
case(function(p,a,r) r.targetId="missing" end,"UNKNOWN_LOCATION")
case(function(p,a,r) r.targetId="raw/1" end,"SAME_LOCATION")
case(function(p,a,r) r.targetId="worker" end,"WRONG_CARRIER")
case(function(p,a,r) a.carrierLocationId="raw/1" end,"WRONG_CARRIER")
case(function(p,a,r) r.targetId="raw/2" end,"CARRIER_STEP_REQUIRED")
case(function(p,a,r) r.targetId="vehicle/A" end,"CARRIER_STEP_REQUIRED")
case(function(p,a,r) p.batches.b=State.newBatch("b",101,"Holzpaket","hand") end,"TARGET_FULL")
case(function(p,a,r) p.batches.a.locationId="hand";r.sourceId="hand";r.targetId="finished/1" end,"WRONG_STAGE")
case(function(p,a,r) a.kind="Worker";a.carrierLocationId="worker";r.targetId="worker" end,"OK")
case(function(p,a,r)
	p.batches.a.locationId="hand";r.sourceId="hand";r.targetId="vehicle/A"
	p.reservations["raw/1"]={kind="Return",batchId="a",actorId=a.actorId,actorKind=a.kind,
		carrierId="hand",recipeId="Hocker01",recipeVersion=1,stage="Holzpaket",quantity=1}
end,"OK")
case(function(p,a,r)
	p.batches.a.locationId="hand";p.batches.a.stage="Bausatz";r.sourceId="hand";r.targetId="vehicle/A"
	p.locations["vehicle/A"].acceptedStages={"Bausatz"}
end,"WRONG_STAGE")
case(function(p,a,r)
	p.batches.a.locationId="saw/output";p.batches.a.stage="Bausatz"
	a.kind="Band";a.carrierLocationId="band";r.sourceId="saw/output";r.targetId="band"
end,"OK")
case(function(p,a,r)
	p.batches.a.locationId="band";p.batches.a.stage="Bausatz"
	a.kind="Band";a.carrierLocationId="band";r.sourceId="band";r.targetId="assembly/input"
	p.reservations["saw/output"]={kind="Return",batchId="a",actorId=a.actorId,actorKind=a.kind,
		carrierId="band",recipeId="Hocker01",recipeVersion=1,stage="Bausatz",quantity=1}
end,"OK")
case(function(p,a,r) p.money=-1 end,"INVALID_STATE")
local p,a=fixture()
assert(Actions.checkTransfer(p,a,nil).code=="INVALID_REQUEST");checks+=1
assert(Actions.checkTransfer(p,nil,{}).code=="NOT_READY");checks+=1
return {task="P04-02",status="passed",checks=checks,profilesArtificial=true,
	mutations=false,dataStoreAccess=false,remotes=false}
