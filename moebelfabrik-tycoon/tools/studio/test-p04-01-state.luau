--!strict
-- Edit or Server. Pure artificial profiles; no DataStore access, money grants or active players.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
local testModule=game:GetService("ServerScriptService").Factory.State:Clone()
testModule.Name="StateTestCopy"
testModule.Parent=game:GetService("ServerScriptService").Factory
local loaded,State=pcall(require,testModule)
testModule:Destroy()
assert(loaded,tostring(State))
local Http=game:GetService("HttpService")
local checks=0
local function expect(condition: boolean, message: string): ()
	assert(condition,message);checks+=1
end
local function fixture(): any
	local p=State.newProfile(101)
	p.locations["raw/1"]=State.newLocation("raw/1","RawStore",1,{"Holzpaket"})
	p.locations["hand"]=State.newLocation("hand","Carrier",1,{"Holzpaket","Bausatz","Rohhocker","Fertig","Karton"})
	p.batches["101:test-1"]=State.newBatch("101:test-1",101,"Holzpaket","raw/1")
	return p
end
local function rejected(change: (any)->(), code: string): ()
	local p=fixture();change(p)
	local ok,reason=State.validate(p)
	expect(not ok and reason==code,code.." not rejected: "..tostring(reason))
end
local profile=fixture()
expect(State.validate(profile),"Normal fixture rejected")
expect(State.countAt(profile,"raw/1")==1 and State.countAt(profile,"hand")==0,"Incorrect single stock count")
local decoded=Http:JSONDecode(Http:JSONEncode(profile))
expect(State.validate(decoded) and decoded.batches["101:test-1"].id=="101:test-1","JSON roundtrip changed stable identity")
local separate=State.newProfile(202)
expect(next(separate.batches)==nil and separate.batches~=profile.batches,"Profiles share a mutable batch table")
rejected(function(p) p.ownerUserId=0 end,"INVALID_OWNER")
rejected(function(p) p.schemaVersion=99 end,"INVALID_SCHEMA")
rejected(function(p) p.revision=0.5 end,"INVALID_REVISION")
rejected(function(p) p.money=-1 end,"INVALID_MONEY")
rejected(function(p) p.money=0/0 end,"INVALID_MONEY")
rejected(function(p) p.money=math.huge end,"INVALID_MONEY")
rejected(function(p) p.money=0.5 end,"INVALID_MONEY")
rejected(function(p) p.batches["101:test-1"].ownerUserId=202 end,"FOREIGN_BATCH")
rejected(function(p) p.batches["101:test-1"].id="changed" end,"INVALID_BATCH_ID")
rejected(function(p) p.batches["101:test-1"].quantity=2 end,"INVALID_QUANTITY")
rejected(function(p) p.batches["101:test-1"].quantity=0 end,"INVALID_QUANTITY")
rejected(function(p) p.batches["101:test-1"].locationId="missing" end,"UNKNOWN_LOCATION")
rejected(function(p) p.batches["101:test-1"].stage="Karton" end,"WRONG_STAGE")
rejected(function(p) p.batches["101:test-1"].stage="invented" end,"INVALID_RECIPE_STAGE")
rejected(function(p) p.batches["101:test-2"]=State.newBatch("101:test-2",101,"Holzpaket","raw/1") end,"CAPACITY_EXCEEDED")
rejected(function(p) p.locations["raw/1"].capacity=0 end,"INVALID_CAPACITY")
rejected(function(p) p.locations["raw/1"].acceptedStages={} end,"INVALID_ACCEPTED_STAGES")
rejected(function(p) p.locations["raw/1"].id="other" end,"INVALID_LOCATION")
rejected(function(p) p.locations.hand.capacity=2 end,"INVALID_CAPACITY")
rejected(function(p) p.batches["101:test-1"].recipeVersion=nil end,"INVALID_RECIPE_STAGE")
rejected(function(p) p.loop=p end,"INVALID_PROFILE_SHAPE")
rejected(function(p) p.batches["101:test-1"].loop=p end,"INVALID_BATCH_ID")
rejected(function(p) setmetatable(p,{}) end,"INVALID_PROFILE_SHAPE")
rejected(function(p) setmetatable(p.locations,{}) end,"INVALID_COLLECTION")
rejected(function(p) p.locations["raw/1"].acceptedStages={[1]="Holzpaket",extra="Karton"} end,"INVALID_ACCEPTED_STAGES")
rejected(function(p) local id=string.char(255);p.batches[id]=p.batches["101:test-1"];p.batches["101:test-1"]=nil;p.batches[id].id=id end,"INVALID_BATCH_ID")
local stages={"Holzpaket","Bausatz","Rohhocker","Fertig","Karton"}
for _,stage in stages do
	local p=fixture();p.batches["101:test-1"].locationId="hand";p.batches["101:test-1"].stage=stage
	expect(State.validate(p) and State.countAt(p,"raw/1")==0 and State.countAt(p,"hand")==1,"Stage loses or duplicates a batch")
end
return {task="P04-01",status="passed",checks=checks,profilesArtificial=true,dataStoreAccess=false,
	automaticPlayerStartup=false,schemaVersion=State.SCHEMA_VERSION}
