--!strict
-- P04-04: synthetic reader/initializer callbacks only; no storage, startup or remotes.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608, "Wrong test place")
local RunService=game:GetService("RunService")
assert(RunService:IsStudio() and (RunService:IsServer() or not RunService:IsRunning()), "Edit/Server only")
local ServerScriptService=game:GetService("ServerScriptService")
local Http=game:GetService("HttpService")
local source=ServerScriptService:FindFirstChild("Factory")
assert(source, "Factory is missing")
local folder=Instance.new("Folder")
folder.Name="P0404TestCopy_" .. Http:GenerateGUID(false)
folder.Parent=ServerScriptService

local loaded, summary=xpcall(function(): any
	for _,name in {"State", "Actions", "Transfers", "Profiles"} do
		local module=source:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"), "Missing ModuleScript " .. name)
		module:Clone().Parent=folder
	end
	local State=require(folder:FindFirstChild("State") :: ModuleScript)
	local Actions=require(folder:FindFirstChild("Actions") :: ModuleScript)
	local Transfers=require(folder:FindFirstChild("Transfers") :: ModuleScript)
	local Profiles=require(folder:FindFirstChild("Profiles") :: ModuleScript)
	assert(State.SCHEMA_VERSION==2 and Profiles.VERSION==1 and Profiles.PROGRESS_VERSION==1, "Unexpected schema")
	local passed: {string}={}
	local failures: {any}={}
	local calls=0
	local function test(name: string, body: () -> ()): ()
		local ok, problem=xpcall(body, debug.traceback)
		if ok then table.insert(passed, name) else table.insert(failures, {name=name,error=tostring(problem)}) end
	end
	local function copy(value: any): any
		if type(value)~="table" then return value end
		local result: any={}
		for key,item in value do result[key]=copy(item) end
		return result
	end
	local function equal(left: any, right: any): boolean
		if type(left)~=type(right) then return false end
		if type(left)~="table" then return left==right end
		for key,value in left do if not equal(value, right[key]) then return false end end
		for key in right do if left[key]==nil then return false end end
		return true
	end
	local function freeze(value: any): ()
		if type(value)~="table" or table.isfrozen(value) then return end
		for _,item in value do freeze(item) end
		table.freeze(value)
	end
	local function envelope(state: any): any
		return {profileVersion=1,state=state,
			progress={version=1,selectedRecipeId="Hocker01",selectedRecipeVersion=1}}
	end
	local function invoke(ownerUserId: any, reader: any, initialize: any?): any
		calls+=1
		local result=Profiles.load(ownerUserId, reader, initialize)
		assert(type(result)=="table" and type(result.ok)=="boolean" and result.ready==false, "Missing safe result")
		assert(type(result.code)=="string" and type(result.message)=="string" and #result.message>0,
			"Missing stable code/feedback")
		return result
	end
	local function savedFixture(): any
		local state=State.newProfile(101)
		state.money=321
		for _,spec in {{"raw/1","RawStore"},{"raw/2","RawStore"},{"supplier/1","Supplier"},
			{"hand","Carrier"},{"worker/1","Carrier"}} do
			state.locations[spec[1]]=State.newLocation(spec[1],spec[2],1,{"Holzpaket"})
		end
		state.batches.a=State.newBatch("a",101,"Holzpaket","raw/1")
		state.batches.b=State.newBatch("b",101,"Holzpaket","supplier/1")
		state.reservations["raw/2"]={kind="Delivery",batchId="b",purchaseOperationId="synthetic/purchase/b"}
		local store=Transfers.new(state)
		local player={ownerUserId=101,actorId="Player/101",kind="Player",carrierLocationId="hand",ready=true}
		local worker={ownerUserId=101,actorId="Worker/one",kind="Worker",carrierLocationId="worker/1",ready=true}
		assert(Transfers.reserve(store,player,{operationId="pick/reserve",expectedRevision=0,batchId="a",
			sourceId="raw/1",targetId="hand",quantity=1},100,10).ok)
		assert(Transfers.commit(store,player,{operationId="pick/commit",expectedRevision=1,claimId="pick/reserve"},101).ok)
		assert(Transfers.reserve(store,worker,{operationId="pending/reserve",expectedRevision=2,batchId="b",
			sourceId="supplier/1",targetId="worker/1",quantity=1},100,10).ok)
		assert(State.validate(store.profile), "Invalid saved fixture")
		return envelope(store.profile)
	end
	local function expectRejected(saved: any, code: string): any
		local reads,initialized=0,0
		local result=invoke(101,function(key: string): any
			reads+=1
			assert(key=="Player_101", "Wrong key")
			return saved
		end,function(): any
			initialized+=1
			return envelope(State.newProfile(101))
		end)
		assert(not result.ok and result.code==code and result.data==nil, code .. " expected, got " .. result.code)
		assert(reads==1 and initialized==0, "Rejected saved data invoked initializer or repeated read")
		return result
	end

	test("01 saved money, transport progress, promises and receipts survive unchanged",function()
		local saved=savedFixture()
		local before=copy(saved)
		local reads,initialized=0,0
		local result=invoke(101,function(key: string): any reads+=1;assert(key=="Player_101");return saved end,
			function(): any initialized+=1;error("Existing profile must not initialize") end)
		assert(result.ok and result.code=="LOADED" and result.origin=="Existing" and result.key=="Player_101")
		assert(reads==1 and initialized==0 and equal(result.data,before) and equal(saved,before))
		assert(result.data.state.money==321 and result.data.state.revision==3)
		assert(result.data.state.batches.a.locationId=="hand" and result.data.state.batches.b.locationId=="supplier/1")
		assert(result.data.state.reservations["raw/1"].kind=="Return"
			and result.data.state.reservations["raw/2"].kind=="Delivery")
		assert(result.data.state.claims["pending/reserve"].expiresAt==110
			and result.data.state.receipts["pick/commit"].result.revision==2)
	end)
	test("02 JSON envelope roundtrip preserves recipe selection and complete transport records",function()
		local saved=savedFixture()
		local decoded=Http:JSONDecode(Http:JSONEncode(saved))
		local result=invoke(101,function(): any return decoded end)
		assert(result.ok and equal(saved,result.data) and State.validate(result.data.state))
		assert(result.data.progress.version==1 and result.data.progress.selectedRecipeId=="Hocker01"
			and result.data.progress.selectedRecipeVersion==1)
	end)
	test("03 loaded results are detached from source and other load calls",function()
		local saved=savedFixture()
		local first=invoke(101,function(): any return saved end)
		local second=invoke(101,function(): any return saved end)
		first.data.state.money=7
		first.data.state.claims["pending/reserve"].expiresAt=900
		first.data.state.receipts["pick/commit"].result.sourceId="tampered"
		first.data.progress.selectedRecipeId="tampered"
		assert(saved.state.money==321 and second.data.state.money==321)
		assert(saved.state.claims["pending/reserve"].expiresAt==110
			and second.data.state.receipts["pick/commit"].result.sourceId=="raw/1")
		assert(saved.progress.selectedRecipeId=="Hocker01" and second.data.progress.selectedRecipeId=="Hocker01")
		saved.state.money=999
		assert(second.data.state.money==321, "Source later mutated loaded result")
	end)
	test("04 deeply frozen saved records load without mutation and produce mutable detached data",function()
		local saved=savedFixture()
		freeze(saved)
		local result=invoke(101,function(): any return saved end)
		assert(result.ok and equal(result.data,saved) and not table.isfrozen(result.data.state))
		result.data.state.money=0
		assert(saved.state.money==321)
	end)
	test("05 successful absence alone produces a distinct zero/empty non-economic schema",function()
		local reads=0
		local function reader(key: string): any reads+=1;assert(key=="Player_101");return nil end
		local first=invoke(101,reader)
		local second=invoke(101,reader)
		assert(reads==2 and first.ok and first.code=="INITIALIZED" and first.origin=="Absent")
		assert(first.data.state.money==0 and first.data.state.revision==0 and next(first.data.state.batches)==nil)
		assert(next(first.data.state.locations)==nil and next(first.data.state.receipts)==nil)
		assert(State.validate(first.data.state) and equal(first.data.progress,second.data.progress))
		assert(first.data~=second.data and first.data.state~=second.data.state)
	end)
	test("06 custom initializer runs exactly once and only after confirmed absence",function()
		local order={}
		local created=envelope(State.newProfile(101))
		created.state.money=17
		local result=invoke(101,function(): any table.insert(order,"read");return nil end,
			function(owner: number): any assert(owner==101);table.insert(order,"initialize");return created end)
		assert(result.ok and result.origin=="Absent" and result.code=="INITIALIZED")
		assert(#order==2 and order[1]=="read" and order[2]=="initialize" and result.data.state.money==17)
		result.data.state.money=18
		assert(created.state.money==17, "Factory result aliases loaded output")
	end)
	test("07 a thrown read error never initializes or returns partial data",function()
		local reads,initialized=0,0
		local result=invoke(101,function(): any reads+=1;error("synthetic read failure") end,
			function(): any initialized+=1;return envelope(State.newProfile(101)) end)
		assert(not result.ok and result.code=="LOAD_FAILED" and result.data==nil and result.origin==nil)
		assert(reads==1 and initialized==0)
	end)
	test("08 malformed saved values and raw State2 never become absence or migrate implicitly",function()
		for _,saved in {false,true,"",123,{},State.newProfile(101),setmetatable(savedFixture(),{})} do
			expectRejected(saved,"INVALID_PROFILE")
		end
	end)
	test("09 unsupported envelope/state versions fail closed without initialization",function()
		local future=savedFixture()
		future.profileVersion=2
		expectRejected(future,"UNSUPPORTED_PROFILE_VERSION")
		future=savedFixture();future.state.schemaVersion=3
		expectRejected(future,"UNSUPPORTED_STATE_VERSION")
		future=savedFixture();future.profileVersion="1"
		expectRejected(future,"INVALID_PROFILE")
		future=savedFixture();future.profileVersion=nil
		expectRejected(future,"INVALID_PROFILE")
	end)
	test("10 invalid or cyclic recipe progress is rejected before deep copying",function()
		for _,change in {
			function(p: any): () p.progress=nil end,
			function(p: any): () p.progress.version=2 end,
			function(p: any): () p.progress.selectedRecipeId="OtherRecipe" end,
			function(p: any): () p.progress.selectedRecipeVersion=2 end,
			function(p: any): () p.progress.selectedRecipeId=p.progress end,
			function(p: any): () p.progress.loop=p.progress end,
			function(p: any): () setmetatable(p.progress,{}) end,
		} do
			local saved=savedFixture();change(saved)
			expectRejected(saved,"INVALID_PROGRESS")
		end
	end)
	test("11 a valid foreign owner record is not adopted or replaced",function()
		expectRejected(envelope(State.newProfile(202)),"OWNER_MISMATCH")
	end)
	test("12 invalid owners reject before reader and initializer",function()
		local reads,initialized=0,0
		local function reader(): any reads+=1;return nil end
		local function initializer(): any initialized+=1;return envelope(State.newProfile(101)) end
		for _,owner in {0,-1,0.5,0/0,math.huge,9007199254740992,"101",false,{}} do
			local result=invoke(owner,reader,initializer)
			assert(not result.ok and result.code=="INVALID_OWNER" and result.key==nil and result.data==nil)
		end
		assert(invoke(nil,reader,initializer).code=="INVALID_OWNER")
		assert(reads==0 and initialized==0)
	end)
	test("13 maximum safe owner uses a stable decimal key without scientific notation",function()
		local result=invoke(9007199254740991,function(key: string): any
			assert(key=="Player_9007199254740991");return nil
		end)
		assert(result.ok and result.key=="Player_9007199254740991"
			and result.data.state.ownerUserId==9007199254740991)
	end)
	test("14 invalid reader is rejected without trying an initializer",function()
		local initialized=0
		for _,reader in {false,101,"reader",{}} do
			local result=invoke(101,reader,function(): any initialized+=1;return envelope(State.newProfile(101)) end)
			assert(result.code=="INVALID_READER" and result.data==nil)
		end
		assert(invoke(101,nil).code=="INVALID_READER" and initialized==0)
	end)
	test("15 a failing initializer does not retry, default or publish",function()
		local reads,initialized=0,0
		local result=invoke(101,function(): any reads+=1;return nil end,
			function(): any initialized+=1;error("synthetic initializer failure") end)
		assert(result.code=="INITIALIZATION_FAILED" and not result.ok and result.data==nil)
		assert(reads==1 and initialized==1)
	end)
	test("16 initializer output must validate, including owner and current schema",function()
		for _,created in {false,{},State.newProfile(101),envelope(State.newProfile(202))} do
			local initialized=0
			local result=invoke(101,function(): any return nil end,
				function(): any initialized+=1;return created end)
			assert(not result.ok and result.data==nil and initialized==1)
		end
		assert(invoke(101,function(): any return nil end,function(): any return nil end).code=="INVALID_PROFILE")
		local future=envelope(State.newProfile(101));future.profileVersion=99
		assert(invoke(101,function(): any return nil end,function(): any return future end).code=="UNSUPPORTED_PROFILE_VERSION")
	end)
	test("17 existing saved profile ignores initializer entirely",function()
		local result=invoke(101,function(): any return savedFixture() end,function(): any error("Must never run") end)
		assert(result.ok and result.code=="LOADED")
		assert(invoke(101,function(): any return savedFixture() end,"unused invalid initializer").ok)
	end)
	test("18 even a successful load cannot mark its economic actor ready",function()
		local result=invoke(101,function(): any return savedFixture() end)
		local state=result.data.state
		local before=copy(state)
		local actor={ownerUserId=101,actorId="Worker/one",kind="Worker",carrierLocationId="worker/1",ready=result.ready}
		local request={operationId="blocked/after-load",expectedRevision=state.revision,batchId="b",
			sourceId="supplier/1",targetId="worker/1",quantity=1}
		assert(Actions.checkTransfer(state,actor,request,101).code=="NOT_READY")
		local store={profile=state}
		assert(Transfers.reserve(store,actor,request,101,10).code=="NOT_READY")
		assert(store.profile==state and equal(state,before))
	end)
	test("19 a yielding older load cannot overwrite a newer result or caller store",function()
		local older=savedFixture()
		local newer=copy(older);newer.state.money=999;newer.state.revision=4
		local oldResult: any=nil
		local thread=coroutine.create(function(): ()
			oldResult=invoke(101,function(key: string): any
				assert(key=="Player_101");coroutine.yield("reader-pending");return older
			end)
		end)
		local started,signal=coroutine.resume(thread)
		assert(started and signal=="reader-pending" and oldResult==nil)
		local freshResult=invoke(101,function(): any return newer end)
		local callerStore={profile=freshResult.data.state}
		assert(coroutine.resume(thread) and coroutine.status(thread)=="dead")
		assert(oldResult.ok and oldResult.data.state.money==321 and freshResult.data.state.money==999)
		assert(callerStore.profile==freshResult.data.state and callerStore.profile.revision==4,
			"Load published into another caller's store")
	end)
	test("20 a reentrant load has independent output and no shared registry",function()
		local nested: any=nil
		local outer=invoke(101,function(): any
			nested=invoke(101,function(): any return envelope(State.newProfile(101)) end)
			return savedFixture()
		end)
		assert(outer.ok and nested.ok and outer.data.state.money==321 and nested.data.state.money==0)
		assert(outer.data.state~=nested.data.state)
	end)
	test("21 a yielding initializer failure still produces no partial profile",function()
		local result: any=nil
		local thread=coroutine.create(function(): ()
			result=invoke(101,function(): any return nil end,function(): any
				coroutine.yield("initializer-pending");error("synthetic delayed failure")
			end)
		end)
		local started,signal=coroutine.resume(thread)
		assert(started and signal=="initializer-pending" and result==nil)
		assert(coroutine.resume(thread) and coroutine.status(thread)=="dead")
		assert(result.code=="INITIALIZATION_FAILED" and result.data==nil and not result.ready)
	end)
	test("22 corrupted historical receipt fails state validation without new data",function()
		local saved=savedFixture()
		saved.state.receipts["pick/commit"].result.sourceId="raw/2"
		expectRejected(saved,"INVALID_STATE")
	end)
	test("23 invalid initializer type is rejected only after confirmed absence",function()
		local reads=0
		local result=invoke(101,function(): any reads+=1;return nil end,"not a function")
		assert(result.code=="INVALID_INITIALIZER" and result.origin=="Absent" and result.data==nil and reads==1)
	end)
	test("24 extra envelope/state fields and cycles reject without recursive-copy failure",function()
		local saved=savedFixture();saved.extra=saved
		expectRejected(saved,"INVALID_PROFILE")
		saved=savedFixture();saved.state.loop=saved.state
		expectRejected(saved,"INVALID_STATE")
		saved=savedFixture();saved.progress.selectedRecipeVersion=nil
		expectRejected(saved,"INVALID_PROGRESS")
	end)
	return {task="P04-04",status=if #failures==0 then "passed" else "failed",checks=#passed+#failures,
		passed=#passed,failed=#failures,calls=calls,passedCases=passed,failures=failures,profileVersion=1,
		stateSchemaVersion=State.SCHEMA_VERSION,progressVersion=1,profilesArtificial=true,storageAccess=false,
		dataStoreAccess=false,memoryStoreAccess=false,remotes=false,automaticPlayerStartup=false,
		economicReady=false,persisted=false}
end,debug.traceback)

folder:Destroy()
assert(loaded,tostring(summary))
return summary
