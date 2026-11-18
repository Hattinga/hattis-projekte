--!strict
-- P04-06 independent fault-injection suite. No external storage or engine dependencies.
return function(State: any, Profiles: any, Sessions: any, Transfers: any, Persistence: any): any
	local passed: {string}={}
	local failures: {{name: string,error: string}}={}
	local messages: {[string]: string}={}
	local function test(name: string,body: () -> ()): ()
		local ok,problem=xpcall(function(): boolean body();return true end,function(problem: any): string
			return debug.traceback(tostring(problem),2)
		end)
		if ok then table.insert(passed,name) else table.insert(failures,{name=name,error=tostring(problem)}) end
	end
	local function copy(value: any): any
		if type(value)~="table" then return value end
		local result: any={}
		for key,item in value do result[key]=copy(item) end
		return result
	end
	local function equal(left: any,right: any): boolean
		if type(left)~=type(right) then return false end
		if type(left)~="table" then return left==right end
		for key,item in left do if not equal(item,right[key]) then return false end end
		for key in right do if left[key]==nil then return false end end
		return true
	end
	local function freeze(value: any): ()
		if type(value)~="table" or table.isfrozen(value) then return end
		for _,item in value do freeze(item) end
		table.freeze(value)
	end
	local function check(response: any,code: string?,status: string?): any
		assert(type(response)=="table" and type(response.ok)=="boolean","Missing result")
		assert(response.ready==false,"Persistence must not authorize economic actions")
		assert(type(response.code)=="string" and type(response.message)=="string" and #response.message>0,
			"Missing code/message")
		assert(response.key=="Player_101","Wrong profile key")
		assert(type(response.unknown)=="boolean" and type(response.inFlight)=="boolean","Missing write-state flags")
		assert(response.unknown==(response.status=="Unknown"),"Unknown flag disagrees with status")
		assert(response.status=="Empty" or response.status=="Confirmed" or response.status=="Released"
			or response.status=="Unknown","Unknown controller status")
		if messages[response.code] then assert(messages[response.code]==response.message,"Unstable result message") end
		messages[response.code]=response.message
		if code then assert(response.code==code,"Expected " .. code .. ", got " .. response.code) end
		if status then assert(response.status==status,"Expected status " .. status .. ", got " .. response.status) end
		return response.confirmed
	end
	local function seed(owner: number?): any
		local user=owner or 101
		local loaded=Profiles.load(user,function(): any return nil end)
		assert(loaded.ok and loaded.ready==false and loaded.data)
		local data=loaded.data
		data.state.money=321
		data.state.revision=10
		data.state.locations.raw=State.newLocation("raw","RawStore",1,{"Holzpaket"})
		data.state.locations.hand=State.newLocation("hand","Carrier",1,{"Holzpaket"})
		data.state.batches.a=State.newBatch("a",user,"Holzpaket","raw")
		assert(State.validate(data.state))
		return data
	end
	local function session(token: string?,now: number?): any
		local acquired=Sessions.acquire(nil,101,0,token or "session/A",now or 100,20,seed())
		assert(acquired.ok and acquired.record)
		return acquired.record
	end
	local function freeRecord(): any
		local released=Sessions.release(session(),101,1,"session/A",101)
		assert(released.ok and released.record)
		return released.record
	end
	local function changed(saved: any): any
		local data=copy(saved.data)
		data.state.revision+=1
		data.state.money+=50
		return data
	end
	-- A minimal atomic backend whose failures are explicitly placed before/after application.
	local function fake(initial: any): any
		local state: any={value=copy(initial),reads=0,updates=0,callbacks=0,mode="normal",readMode="normal"}
		state.backend={
			read=function(key: string): any
				assert(key=="Player_101")
				state.reads+=1
				local onRead=state.onRead
				if type(onRead)=="function" then (onRead :: any)() end
				if state.readMode=="throw" then error("synthetic read failure") end
				if state.readMode=="override" then return copy(state.readOverride) end
				return copy(state.value)
			end,
			update=function(key: string,transform: (any) -> any): any
				assert(key=="Player_101")
				state.updates+=1
				local onUpdate=state.onUpdate
				if type(onUpdate)=="function" then (onUpdate :: any)() end
				if state.mode=="throwBefore" then error("request outcome unknown before callback") end
				if state.mode=="noCallback" then return copy(state.value) end
				state.callbacks+=1
				local proposed=transform(copy(state.value))
				if state.mode=="retry" then
					local onRetry=state.onRetry
					if type(onRetry)=="function" then onRetry() end
					state.value=copy(state.retryValue)
					state.callbacks+=1
					proposed=transform(copy(state.value))
				end
				state.lastProposed=copy(proposed)
				if proposed==nil then return nil end
				state.value=copy(proposed)
				if state.mode=="throwAfter" then error("response lost after application") end
				if state.mode=="nilAfter" then return nil end
				if state.mode=="override" then return copy(state.returnOverride) end
				return copy(state.value)
			end,
		}
		return state
	end
	local function newController(initial: any): (any,any,any)
		local storage=fake(initial)
		local time={now=102}
		local controller=Persistence.new(101,storage.backend,function(): number return time.now end)
		return controller,storage,time
	end
	local function loaded(initial: any?): (any,any,any,any)
		local controller,storage,time=newController(initial or freeRecord())
		local response=controller.load("session/A",20,function(): any return seed() end)
		local confirmed=check(response,"LOADED","Confirmed")
		assert(response.ok and not response.unknown and not response.inFlight and confirmed)
		return controller,storage,time,confirmed
	end

	test("01 empty controller exposes no fabricated confirmed profile",function()
		local controller,storage=newController(nil)
		local response=controller.snapshot()
		assert(check(response,"SNAPSHOT","Empty")==nil and response.ok)
		check(controller.save(seed(),20),"NOT_LOADED","Empty")
		check(controller.release(),"NOT_LOADED","Empty")
		assert(storage.reads==0 and storage.updates==0)
	end)
	test("02 absent profile initializes once and confirms only the atomic result",function()
		local controller,storage=newController(nil)
		local initialized=0
		local saved=check(controller.load("session/A",20,function(owner: number): any
			initialized+=1
			assert(owner==101)
			return seed()
		end),"LOADED","Confirmed")
		assert(initialized==1 and storage.updates==1 and storage.callbacks==1)
		assert(saved.revision==1 and saved.sessionId=="session/A" and saved.expiresAt==122)
		assert(equal(saved,storage.value) and saved.data.state.money==321)
	end)
	test("03 existing released data loads without invoking initial data creation",function()
		local source=freeRecord()
		source.data.state.money=700
		local controller,storage=newController(source)
		local saved=check(controller.load("session/A",20,function(): any error("Existing data must not initialize") end),
			"LOADED","Confirmed")
		assert(saved.data.state.money==700 and saved.revision==source.revision+1)
		assert(source.sessionId=="" and storage.updates==1)
	end)
	test("04 normal save and release advance confirmed storage together",function()
		local controller,storage,_,base=loaded()
		local saved=check(controller.save(changed(base),20),"SAVED","Confirmed")
		assert(saved.revision==base.revision+1 and saved.data.state.money==371)
		assert(equal(saved,storage.value))
		local released=check(controller.release(),"RELEASED","Released")
		assert(released.revision==saved.revision+1 and released.sessionId=="" and released.expiresAt==0)
		assert(equal(released.data,saved.data) and equal(released,storage.value))
	end)
	test("05 crash restoration observes the last confirmed save not unsaved work",function()
		local controller,storage,time,base=loaded()
		local unsaved=changed(base)
		unsaved.state.money=999
		assert(check(controller.snapshot(),"SNAPSHOT","Confirmed").data.state.money==321)
		local saved=check(controller.save(changed(base),20),"SAVED","Confirmed")
		time.now=123
		local nextController=Persistence.new(101,storage.backend,function(): number return time.now end)
		local restored=check(nextController.load("session/B",20),"LOADED","Confirmed")
		assert(restored.data.state.money==saved.data.state.money and restored.data.state.money==371)
		assert(restored.data.state.money~=unsaved.state.money)
	end)
	test("06 load failure cannot initialize or enable any economic action",function()
		local controller,storage=newController(nil)
		storage.readMode="throw"
		local initialized=0
		check(controller.load("session/A",20,function(): any initialized+=1;return seed() end),"LOAD_FAILED","Empty")
		assert(initialized==0 and storage.updates==0)
		assert(check(controller.snapshot(),"SNAPSHOT","Empty")==nil)
	end)
	test("07 malformed existing data never receives fallback starter data",function()
		for _,source in {false,"bad",{},seed()} do
			local controller,storage=newController(source)
			local initialized=0
			local response=controller.load("session/A",20,function(): any initialized+=1;return seed() end)
			check(response,nil,"Empty")
			assert(not response.ok and initialized==0 and storage.updates==0)
		end
	end)
	test("08 future foreign and corrupt profiles remain closed without replacement",function()
		local future=freeRecord();future.sessionVersion=999
		local foreign=freeRecord();foreign.data=seed(102)
		local corrupt=freeRecord();corrupt.data.state.batches.a.locationId="missing"
		for _,source in {future,foreign,corrupt} do
			local controller,storage=newController(source)
			local response=controller.load("session/A",20)
			check(response,nil,"Empty")
			assert(not response.ok and storage.updates==0 and equal(storage.value,source))
		end
	end)
	test("09 failed or invalid initialization never attempts a write",function()
		for _,initialize in {
			function(): any error("initializer failed") end,
			function(): any return {} end,
			function(): any return seed(102) end,
			123,
		} do
			local controller,storage=newController(nil)
			local response=controller.load("session/A",20,initialize)
			check(response,nil,"Empty")
			assert(not response.ok and storage.updates==0 and storage.value==nil)
		end
	end)
	test("10 a live foreign session blocks load without claiming its data",function()
		local source=session("session/other",100)
		local controller,storage=newController(source)
		local response=controller.load("session/A",20)
		check(response,"SESSION_BUSY","Empty")
		assert(not response.ok and equal(storage.value,source))
	end)
	test("11 already-loaded controllers reject reacquisition without extra reads or writes",function()
		local controller,storage=loaded()
		local reads,updates=storage.reads,storage.updates
		check(controller.load("session/B",20),"ALREADY_LOADED","Confirmed")
		assert(storage.reads==reads and storage.updates==updates)
	end)
	test("12 apply-then-throw preserves the old confirmed state and blocks all new writes",function()
		local controller,storage,_,base=loaded()
		storage.mode="throwAfter"
		local response=controller.save(changed(base),20)
		assert(not response.ok)
		assert(equal(check(response,"WRITE_UNKNOWN","Unknown"),base))
		assert(storage.value.data.state.money==371 and response.unknown)
		local reads,updates=storage.reads,storage.updates
		check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
		check(controller.release(),"WRITE_UNKNOWN","Unknown")
		check(controller.load("session/B",20),"WRITE_UNKNOWN","Unknown")
		assert(storage.reads==reads and storage.updates==updates)
		assert(equal(check(controller.snapshot(),"SNAPSHOT","Unknown"),base))
	end)
	test("13 exact fresh read reconciles an applied save without reissuing its write",function()
		local controller,storage,_,base=loaded()
		storage.mode="throwAfter"
		check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
		local updates=storage.updates
		storage.mode="normal"
		local confirmed=check(controller.reconcile(),"RECONCILED","Confirmed")
		assert(confirmed.data.state.money==371 and equal(confirmed,storage.value) and storage.updates==updates)
		local nextSaved=check(controller.save(changed(confirmed),20),"SAVED","Confirmed")
		assert(nextSaved.data.state.money==421)
	end)
	test("14 a throw before callback remains unknown despite reading the unchanged base",function()
		local controller,storage,_,base=loaded()
		storage.mode="throwBefore"
		local callbacks=storage.callbacks
		check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
		assert(storage.callbacks==callbacks and equal(storage.value,base))
		check(controller.reconcile(),"RECONCILE_UNKNOWN","Unknown")
		check(controller.reconcile(),"RECONCILE_UNKNOWN","Unknown")
		assert(equal(check(controller.snapshot(),"SNAPSHOT","Unknown"),base))
	end)
	test("15 read failure during reconciliation never discards the unresolved proposal",function()
		local controller,storage,_,base=loaded()
		storage.mode="throwAfter"
		check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
		storage.readMode="throw"
		check(controller.reconcile(),"RECONCILE_UNKNOWN","Unknown")
		storage.readMode="normal"
		check(controller.reconcile(),"RECONCILED","Confirmed")
	end)
	test("16 a foreign or merely similar read cannot confirm an unknown write",function()
		local controller,storage,_,base=loaded()
		storage.mode="throwAfter"
		check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
		local exact=copy(storage.value)
		storage.readMode="override"
		local similar=copy(exact);similar.data.state.money+=1
		storage.readOverride=similar
		check(controller.reconcile(),"RECONCILE_UNKNOWN","Unknown")
		local foreign=copy(exact);foreign.sessionId="session/B"
		storage.readOverride=foreign
		check(controller.reconcile(),"RECONCILE_UNKNOWN","Unknown")
		storage.readMode="normal"
		assert(equal(check(controller.reconcile(),"RECONCILED","Confirmed"),exact))
	end)
	test("17 nil or mismatched backend success responses are never accepted as confirmation",function()
		for _,mode in {"nilAfter","override"} do
			local controller,storage,_,base=loaded()
			storage.mode=mode
			storage.returnOverride=copy(base)
			check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
			assert(equal(check(controller.snapshot(),"SNAPSHOT","Unknown"),base))
			storage.mode="normal"
			check(controller.reconcile(),"RECONCILED","Confirmed")
		end
	end)
	test("18 unknown acquisition can reconcile only its own exact submitted record",function()
		local controller,storage=newController(nil)
		storage.mode="throwAfter"
		assert(check(controller.load("session/A",20,function(): any return seed() end),"WRITE_UNKNOWN","Unknown")==nil)
		assert(storage.value and storage.value.revision==1)
		storage.mode="normal"
		local confirmed=check(controller.reconcile(),"RECONCILED","Confirmed")
		assert(confirmed.sessionId=="session/A" and confirmed.data.state.money==321)
	end)
	test("19 unknown release preserves the last owned confirmation until exact reconciliation",function()
		local controller,storage,_,base=loaded()
		storage.mode="throwAfter"
		assert(equal(check(controller.release(),"WRITE_UNKNOWN","Unknown"),base))
		assert(storage.value.sessionId=="")
		storage.mode="normal"
		local released=check(controller.reconcile(),"RECONCILED","Released")
		assert(released.sessionId=="" and released.revision==base.revision+1)
	end)
	test("20 invalid save candidates are rejected without any backend update",function()
		local controller,storage,_,base=loaded()
		local badVersion=changed(base);badVersion.profileVersion=999
		local alteredSame=copy(base.data);alteredSame.state.money+=1
		for _,candidate in {false,{},seed(102),badVersion,alteredSame} do
			local updates=storage.updates
			local response=controller.save(candidate,20)
			check(response,nil,"Confirmed")
			assert(not response.ok and storage.updates==updates and equal(storage.value,base))
		end
	end)
	test("21 fresh callback time rejects a lease that expired while backend yielded",function()
		local controller,storage,time,base=loaded()
		storage.onUpdate=function(): () time.now=base.expiresAt end
		local response=controller.save(changed(base),20)
		check(response,"SESSION_EXPIRED","Confirmed")
		assert(not response.ok and not response.unknown and equal(storage.value,base))
	end)
	test("22 each callback retry reevaluates time and latest current ownership",function()
		local controller,storage,time,base=loaded()
		storage.mode="retry"
		storage.retryValue=copy(base)
		storage.onRetry=function(): () time.now=base.expiresAt end
		local callbacks=storage.callbacks
		check(controller.save(changed(base),20),"SESSION_EXPIRED","Confirmed")
		assert(storage.callbacks==callbacks+2 and equal(storage.value,base))
	end)
	test("23 atomic retry cannot overwrite a successor session",function()
		local controller,storage,time,base=loaded()
		local successor=Sessions.acquire(base,101,base.revision,"session/B",base.expiresAt,20)
		assert(successor.ok and successor.record)
		storage.mode="retry"
		storage.retryValue=successor.record
		storage.onRetry=function(): () time.now=base.expiresAt+1 end
		local response=controller.save(changed(base),20)
		check(response,"STALE_REVISION","Confirmed")
		assert(not response.ok and equal(storage.value,successor.record))
		assert(equal(check(controller.snapshot(),"SNAPSHOT","Confirmed"),base))
	end)
	test("24 reentrant calls see BUSY and cannot overlap a write",function()
		local controller,storage,_,base=loaded()
		local reentries=0
		storage.onUpdate=function(): ()
			for _,response in {controller.save(changed(base),20),controller.release(),
				controller.load("session/B",20),controller.reconcile()} do
				check(response,"BUSY","Confirmed")
				assert(response.inFlight and not response.ok)
				reentries+=1
			end
			local snapshot=controller.snapshot()
			check(snapshot,"SNAPSHOT","Confirmed")
			assert(snapshot.inFlight)
		end
		check(controller.save(changed(base),20),"SAVED","Confirmed")
		assert(reentries==4 and storage.updates==2)
	end)
	test("25 a yielded save detaches caller input before another task can mutate it",function()
		local controller,storage,_,base=loaded()
		local candidate=changed(base)
		storage.onUpdate=function(): () coroutine.yield("update paused") end
		local response: any=nil
		local pending=coroutine.create(function(): () response=controller.save(candidate,20) end)
		local started,signal=coroutine.resume(pending)
		assert(started and signal=="update paused")
		candidate.state.money=999
		candidate.state.batches.a.locationId="hand"
		check(controller.save(changed(base),20),"BUSY","Confirmed")
		local resumed,problem=coroutine.resume(pending)
		assert(resumed,tostring(problem))
		local saved=check(response,"SAVED","Confirmed")
		assert(saved.data.state.money==371 and saved.data.state.batches.a.locationId=="raw")
		assert(storage.value.data.state.money==371)
	end)
	test("26 load read yields keep single flight and prevent competing initialization",function()
		local controller,storage=newController(nil)
		storage.onRead=function(): () coroutine.yield("read paused") end
		local response: any=nil
		local initialized=0
		local pending=coroutine.create(function(): () response=controller.load("session/A",20,function(): any
			initialized+=1;return seed()
		end) end)
		local started,signal=coroutine.resume(pending)
		assert(started and signal=="read paused")
		check(controller.load("session/B",20),"BUSY","Empty")
		check(controller.save(seed(),20),"BUSY","Empty")
		assert(initialized==0)
		local resumed,problem=coroutine.resume(pending)
		assert(resumed,tostring(problem))
		check(response,"LOADED","Confirmed")
		assert(initialized==1 and storage.updates==1)
	end)
	test("27 returned confirmations snapshots and backend values share no mutable aliases",function()
		local controller,storage,_,base=loaded()
		base.data.state.money=1
		storage.value.data.state.money=2
		local snapshot=check(controller.snapshot(),"SNAPSHOT","Confirmed")
		assert(snapshot.data.state.money==321)
		snapshot.data.state.money=3
		assert(check(controller.snapshot(),"SNAPSHOT","Confirmed").data.state.money==321)
	end)
	test("28 freeze-safe save preserves transport data and consumes no extra retry",function()
		local controller,storage,_,base=loaded()
		local candidate=changed(base)
		freeze(candidate)
		local calls=storage.callbacks
		local saved=check(controller.save(candidate,20),"SAVED","Confirmed")
		assert(saved.data.state.batches.a.locationId=="raw" and storage.callbacks==calls+1)
		assert(not table.isfrozen(saved.data.state))
	end)
	test("29 invalid tokens lease durations and clock readings cannot start a write",function()
		for _,token in {"",123,string.char(255),string.rep("a",129)} do
			local controller,storage=newController(nil)
			local response=controller.load(token,20)
			check(response,nil,"Empty")
			assert(not response.ok and storage.updates==0)
		end
		for _,duration in {0,-1,0.5,math.huge,0/0,"20"} do
			local controller,storage=newController(nil)
			local response=controller.load("session/A",duration)
			check(response,nil,"Empty")
			assert(not response.ok and storage.updates==0)
		end
		local controller,storage,time=newController(nil)
		time.now=-1
		local response=controller.load("session/A",20)
		check(response,nil,"Empty")
		assert(not response.ok and storage.updates==0)
	end)
	test("30 constructor rejects malformed owner and backend capabilities",function()
		for _,owner in {0,-1,0.5,math.huge,0/0,"101"} do
			assert(not pcall(Persistence.new,owner,fake(nil).backend),"Invalid owner accepted")
		end
		for _,backend in {false,{}, {read=function(): any return nil end},
			{update=function(): any return nil end}} do
			assert(not pcall(Persistence.new,101,backend),"Incomplete backend accepted")
		end
	end)
	test("31 reloading a released controller preserves money and uses a new session token",function()
		local controller,storage,_,base=loaded()
		check(controller.save(changed(base),20),"SAVED","Confirmed")
		local released=check(controller.release(),"RELEASED","Released")
		local reacquired=check(controller.load("session/B",20),"LOADED","Confirmed")
		assert(reacquired.revision==released.revision+1 and reacquired.sessionId=="session/B")
		assert(reacquired.data.state.money==371 and equal(reacquired,storage.value))
	end)
	test("32 historical claims and promises survive a confirmed backend roundtrip",function()
		local data=seed()
		local store=Transfers.new(data.state)
		local actor={ownerUserId=101,actorId="Player/101",kind="Player",carrierLocationId="hand",ready=true}
		assert(Transfers.reserve(store,actor,{operationId="carry/reserve",expectedRevision=10,batchId="a",
			sourceId="raw",targetId="hand",quantity=1},100,20).ok)
		assert(Transfers.commit(store,actor,{operationId="carry/commit",expectedRevision=11,claimId="carry/reserve"},101).ok)
		data.state=store.profile
		local controller,storage=newController(nil)
		local confirmed=check(controller.load("session/A",20,function(): any return data end),"LOADED","Confirmed")
		local saved=check(controller.save(confirmed.data,20),"SAVED","Confirmed")
		assert(equal(saved.data,data) and equal(storage.value.data,data))
		assert(saved.data.state.reservations.raw.kind=="Return"
			and saved.data.state.receipts["carry/commit"].result.revision==12)
	end)
	test("33 a concurrent creator between fresh read and atomic update wins unchanged",function()
		local controller,storage=newController(nil)
		local winner=session("session/B",102)
		winner.data.state.money=777
		storage.onUpdate=function(): () storage.value=copy(winner) end
		local initialized=0
		local response=controller.load("session/A",20,function(): any initialized+=1;return seed() end)
		check(response,"STALE_REVISION","Empty")
		assert(not response.ok and initialized==1 and equal(storage.value,winner))
		assert(check(controller.snapshot(),"SNAPSHOT","Empty")==nil)
	end)
	test("34 a yielded reconciliation keeps every mutating method single flight",function()
		local controller,storage,_,base=loaded()
		storage.mode="throwAfter"
		check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
		storage.onRead=function(): () coroutine.yield("reconcile paused") end
		local response: any=nil
		local pending=coroutine.create(function(): () response=controller.reconcile() end)
		local started,signal=coroutine.resume(pending)
		assert(started and signal=="reconcile paused")
		for _,blocked in {controller.save(changed(base),20),controller.load("session/B",20),
			controller.release(),controller.reconcile()} do
			check(blocked,"BUSY","Unknown")
			assert(blocked.inFlight and blocked.unknown and not blocked.ok)
		end
		local snapshot=controller.snapshot()
		check(snapshot,"SNAPSHOT","Unknown")
		assert(snapshot.inFlight and equal(snapshot.confirmed,base))
		local resumed,problem=coroutine.resume(pending)
		assert(resumed,tostring(problem))
		check(response,"RECONCILED","Confirmed")
	end)
	test("35 backend return without executing the transform cannot claim confirmation",function()
		local controller,storage,_,base=loaded()
		storage.mode="noCallback"
		local callbacks=storage.callbacks
		check(controller.save(changed(base),20),"WRITE_UNKNOWN","Unknown")
		assert(storage.callbacks==callbacks and equal(storage.value,base))
		assert(equal(check(controller.snapshot(),"SNAPSHOT","Unknown"),base))
		check(controller.reconcile(),"RECONCILE_UNKNOWN","Unknown")
	end)

	return {total=#passed+#failures,passed=passed,failures=failures}
end
