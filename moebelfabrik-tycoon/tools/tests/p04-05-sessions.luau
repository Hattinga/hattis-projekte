--!strict
-- Pure P04-05 suite. Inject the same modules in Studio or the official Luau CLI.
return function(State: any, Profiles: any, Sessions: any, Transfers: any): any
	local passed: {string}={}
	local failures: {{name: string, error: string}}={}
	local messages: {[string]: string}={}
	local successCodes={ACQUIRED=true,WRITTEN=true,RELEASED=true,STARTED=true,
		PUBLISHED=true,CLOSED=true,SNAPSHOT=true}
	local maximum=9007199254740991
	local function test(name: string, body: () -> ()): ()
		local ok,problem=xpcall(function(): boolean
			body()
			return true
		end,function(problem: any): string
			return debug.traceback(tostring(problem),2)
		end)
		if ok then table.insert(passed,name)
		else table.insert(failures,{name=name,error=tostring(problem)}) end
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
		for key,item in left do if not equal(item,right[key]) then return false end end
		for key in right do if left[key]==nil then return false end end
		return true
	end
	local function freeze(value: any): ()
		if type(value)~="table" or table.isfrozen(value) then return end
		for _,item in value do freeze(item) end
		table.freeze(value)
	end
	local function check(response: any, code: string?): any
		assert(type(response)=="table" and type(response.ok)=="boolean","Missing result")
		assert(response.ready==false,"P04-05 must never authorize economic actions")
		assert(type(response.code)=="string" and type(response.message)=="string"
			and #response.message>0 and utf8.len(response.message)~=nil,"Missing code/message")
		assert(response.ok==(successCodes[response.code]==true),"Inconsistent success code")
		if messages[response.code] then assert(messages[response.code]==response.message,"Unstable message") end
		messages[response.code]=response.message
		if not response.ok then assert(response.record==nil,"Failure leaked a proposed record") end
		if code then assert(response.code==code,"Expected " .. code .. ", got " .. response.code) end
		return response.record
	end
	local function seed(owner: number?): any
		local user=owner or 101
		local loaded=Profiles.load(user,function(): any return nil end)
		assert(loaded.ok and not loaded.ready and loaded.origin=="Absent" and loaded.data)
		local data=loaded.data
		data.state.money=321
		data.state.revision=10
		data.state.locations.raw=State.newLocation("raw","RawStore",1,{"Holzpaket"})
		data.state.locations.hand=State.newLocation("hand","Carrier",1,{"Holzpaket"})
		data.state.batches.a=State.newBatch("a",user,"Holzpaket","raw")
		assert(State.validate(data.state),"Invalid test fixture")
		return data
	end
	local function acquired(token: string?): any
		return check(Sessions.acquire(nil,101,0,token or "session/A",100,20,seed()),"ACQUIRED")
	end
	local function changed(saved: any): any
		local data=copy(saved.data)
		data.state.revision+=1
		data.state.money+=50
		return data
	end
	local function begin(gate: any, token: any): any
		local ticket,response=gate.begin(token)
		check(response,"STARTED")
		assert(ticket~=nil)
		return ticket
	end

	test("01 acquisition creates a versioned fenced copy without activating economy",function()
		local original=seed()
		local before=copy(original)
		local saved=check(Sessions.acquire(nil,101,0,"session/A",100,20,original),"ACQUIRED")
		assert(saved.sessionVersion==Sessions.VERSION and saved.revision==1)
		assert(saved.sessionId=="session/A" and saved.expiresAt==120 and equal(saved.data,before))
		assert(equal(original,before))
		saved.data.state.money=0
		assert(original.state.money==321)
	end)
	test("02 confirmed absence requires explicit initial data and matching zero revision",function()
		check(Sessions.acquire(nil,101,0,"session/A",100,20),"INITIAL_DATA_REQUIRED")
		check(Sessions.acquire(nil,101,1,"session/A",100,20,seed()),"STALE_REVISION")
		check(Sessions.acquire(nil,101,0,"session/A",100,20,{}),"INVALID_PROFILE")
	end)
	test("03 an atomic current profile wins over a stale initialization snapshot",function()
		local latest=acquired()
		latest.data.state.money=700
		latest.data.state.revision=11
		local stale=seed()
		local saved=check(Sessions.acquire(latest,101,1,"session/B",120,20,stale),"ACQUIRED")
		assert(saved.data.state.money==700 and saved.data.state.revision==11 and saved.revision==2)
		assert(stale.state.money==321 and latest.sessionId=="session/A")
	end)
	test("04 first atomic creator wins a competing missing-profile acquisition",function()
		local first=acquired()
		local before=copy(first)
		check(Sessions.acquire(first,101,0,"session/B",100,20,seed()),"STALE_REVISION")
		assert(equal(first,before))
	end)
	test("05 active ownership rejects takeover even with its current revision",function()
		local saved=acquired()
		check(Sessions.acquire(saved,101,1,"session/B",119,20),"SESSION_BUSY")
		check(Sessions.acquire(saved,101,1,"session/A",119,20),"SESSION_BUSY")
	end)
	test("06 a valid state change advances storage and State revisions separately",function()
		local current=acquired()
		local candidate=changed(current)
		local before=copy(current)
		local saved=check(Sessions.write(current,101,1,"session/A",101,20,candidate),"WRITTEN")
		assert(saved.revision==2 and saved.data.state.revision==11 and saved.data.state.money==371)
		assert(saved.expiresAt==121 and equal(current,before))
		saved.data.state.batches.a.locationId="hand"
		assert(candidate.state.batches.a.locationId=="raw" and current.data.state.batches.a.locationId=="raw")
	end)
	test("07 unchanged renewal advances only storage revision and never shortens lease",function()
		local current=acquired()
		local saved=check(Sessions.write(current,101,1,"session/A",101,1,current.data),"WRITTEN")
		assert(saved.revision==2 and saved.data.state.revision==10 and saved.expiresAt==120)
		assert(equal(saved.data,current.data))
	end)
	test("08 release retains exact data and a monotonic storage revision",function()
		local current=acquired()
		local released=check(Sessions.release(current,101,1,"session/A",101),"RELEASED")
		assert(released.revision==2 and released.sessionId=="" and released.expiresAt==0)
		assert(equal(released.data,current.data) and current.sessionId=="session/A")
	end)
	test("09 released records can be acquired without resetting durable revision",function()
		local free=check(Sessions.release(acquired(),101,1,"session/A",101),"RELEASED")
		local nextSession=check(Sessions.acquire(free,101,2,"session/B",102,20),"ACQUIRED")
		assert(nextSession.revision==3 and nextSession.sessionId=="session/B")
		assert(nextSession.data.state.revision==10 and nextSession.data.state.money==321)
	end)
	test("10 takeover at the exact expiry fences old writes and old release",function()
		local old=acquired()
		local current=check(Sessions.acquire(old,101,1,"session/B",120,20),"ACQUIRED")
		local before=copy(current)
		check(Sessions.write(current,101,1,"session/A",121,20,changed(old)),"STALE_REVISION")
		check(Sessions.release(current,101,1,"session/A",121),"STALE_REVISION")
		check(Sessions.write(current,101,2,"session/A",121,20,changed(old)),"SESSION_LOST")
		check(Sessions.release(current,101,2,"session/A",121),"SESSION_LOST")
		assert(equal(current,before))
	end)
	test("11 expired owners cannot renew write or release before a successor arrives",function()
		local old=acquired()
		check(Sessions.write(old,101,1,"session/A",120,20,old.data),"SESSION_EXPIRED")
		check(Sessions.release(old,101,1,"session/A",120),"SESSION_EXPIRED")
	end)
	test("12 two writes from one revision cannot overwrite each other",function()
		local old=acquired()
		local first=check(Sessions.write(old,101,1,"session/A",101,20,changed(old)),"WRITTEN")
		local competitor=changed(old)
		competitor.state.money=999
		check(Sessions.write(first,101,1,"session/A",102,20,competitor),"STALE_REVISION")
		assert(first.data.state.money==371)
	end)
	test("13 acquire release acquire ABA is fenced even when a token is reused",function()
		local first=acquired()
		local free=check(Sessions.release(first,101,1,"session/A",101),"RELEASED")
		local current=check(Sessions.acquire(free,101,2,"session/A",102,20),"ACQUIRED")
		check(Sessions.write(current,101,1,"session/A",103,20,changed(first)),"STALE_REVISION")
		check(Sessions.release(current,101,1,"session/A",103),"STALE_REVISION")
		assert(current.revision==3 and current.data.state.revision==10)
	end)
	test("14 same State revision cannot conceal changed money or changed location",function()
		local current=acquired()
		local money=copy(current.data)
		money.state.money+=1
		check(Sessions.write(current,101,1,"session/A",101,20,money),"STALE_STATE")
		local moved=copy(current.data)
		moved.state.batches.a.locationId="hand"
		assert(State.validate(moved.state))
		check(Sessions.write(current,101,1,"session/A",101,20,moved),"STALE_STATE")
	end)
	test("15 lower State revision is rejected even with valid newer storage ownership",function()
		local current=acquired()
		local older=copy(current.data)
		older.state.revision=9
		check(Sessions.write(current,101,1,"session/A",101,20,older),"STALE_STATE")
	end)
	test("16 foreign and unsupported candidate envelopes fail without altering current",function()
		local current=acquired()
		local before=copy(current)
		check(Sessions.write(current,101,1,"session/A",101,20,seed(102)),"INVALID_PROFILE")
		for _,field in {"profileVersion","progress","state"} do
			local candidate=changed(current)
			if field=="profileVersion" then candidate.profileVersion=2
			elseif field=="progress" then candidate.progress.selectedRecipeId="Other"
			else candidate.state.schemaVersion=999 end
			check(Sessions.write(current,101,1,"session/A",101,20,candidate),"INVALID_PROFILE")
		end
		assert(equal(current,before))
	end)
	test("17 missing malformed and future session records are never replaced by seed",function()
		check(Sessions.write(nil,101,0,"session/A",100,20,seed()),"INVALID_RECORD")
		check(Sessions.release(nil,101,0,"session/A",100),"INVALID_RECORD")
		for _,bad in {false,123,"bad",{},seed()} do
			check(Sessions.acquire(bad,101,0,"session/A",100,20,seed()),"INVALID_RECORD")
		end
		local future=acquired()
		future.sessionVersion=2
		check(Sessions.acquire(future,101,1,"session/B",120,20,seed()),"UNSUPPORTED_SESSION_VERSION")
	end)
	test("18 closed record validation rejects absent and extra fields",function()
		for _,field in {"sessionVersion","revision","sessionId","expiresAt","data"} do
			local bad=acquired()
			bad[field]=nil
			local response=Sessions.release(bad,101,1,"session/A",101)
			check(response)
			assert(not response.ok)
		end
		local bad=acquired()
		bad.extra=true
		check(Sessions.release(bad,101,1,"session/A",101),"INVALID_RECORD")
	end)
	test("19 inconsistent free and active lease records are invalid",function()
		for _,spec in {{"",120},{"session/A",0},{false,120},{"session/A",-1}} do
			local bad=acquired()
			bad.sessionId=spec[1]
			bad.expiresAt=spec[2]
			check(Sessions.release(bad,101,1,"session/A",101),"INVALID_RECORD")
		end
	end)
	test("20 cyclic profiles and metatables fail before recursive copy",function()
		local cyclic=acquired()
		cyclic.data.state.locations=cyclic.data.state
		check(Sessions.release(cyclic,101,1,"session/A",101),"INVALID_PROFILE")
		local extraCycle=acquired()
		extraCycle.loop=extraCycle
		check(Sessions.release(extraCycle,101,1,"session/A",101),"INVALID_RECORD")
		local meta=setmetatable(acquired(),{__index=function(): any error("Metamethod evaluated") end})
		check(Sessions.release(meta,101,1,"session/A",101),"INVALID_RECORD")
	end)
	test("21 frozen valid current and candidate are accepted without mutation",function()
		local current=acquired()
		local candidate=changed(current)
		freeze(current)
		freeze(candidate)
		local saved=check(Sessions.write(current,101,1,"session/A",101,20,candidate),"WRITTEN")
		assert(saved.data.state.money==371 and current.data.state.money==321)
		assert(not table.isfrozen(saved) and not table.isfrozen(saved.data.state))
	end)
	test("22 owner validation rejects unsafe identities at every atomic entry",function()
		for _,owner in {0,-1,1.5,math.huge,0/0,"101",maximum+1} do
			check(Sessions.acquire(nil,owner,0,"session/A",100,20,seed()),"INVALID_OWNER")
			check(Sessions.write(acquired(),owner,1,"session/A",101,20,seed()),"INVALID_OWNER")
			check(Sessions.release(acquired(),owner,1,"session/A",101),"INVALID_OWNER")
		end
	end)
	test("23 session token validation rejects empty long and invalid UTF8 identifiers",function()
		for _,token in {"",string.rep("x",129),string.char(255),123,{}} do
			check(Sessions.acquire(nil,101,0,token,100,20,seed()),"INVALID_REQUEST")
			check(Sessions.write(acquired(),101,1,token,101,20,seed()),"INVALID_REQUEST")
			check(Sessions.release(acquired(),101,1,token,101),"INVALID_REQUEST")
		end
	end)
	test("24 expected storage revision rejects fractions negatives infinities and NaN",function()
		for _,revision in {-1,0.5,math.huge,0/0,"1",maximum+1} do
			check(Sessions.acquire(nil,101,revision,"session/A",100,20,seed()),"INVALID_REQUEST")
			check(Sessions.write(acquired(),101,revision,"session/A",101,20,seed()),"INVALID_REQUEST")
			check(Sessions.release(acquired(),101,revision,"session/A",101),"INVALID_REQUEST")
		end
	end)
	test("25 invalid time and lease duration cannot create or extend ownership",function()
		for _,now in {-1,0.5,math.huge,0/0,"100",maximum+1} do
			check(Sessions.acquire(nil,101,0,"session/A",now,20,seed()),"INVALID_TIME")
			check(Sessions.write(acquired(),101,1,"session/A",now,20,seed()),"INVALID_TIME")
			check(Sessions.release(acquired(),101,1,"session/A",now),"INVALID_TIME")
		end
		for _,ttl in {0,-1,0.5,math.huge,0/0,"20"} do
			check(Sessions.acquire(nil,101,0,"session/A",100,ttl,seed()),"INVALID_TIME")
			check(Sessions.write(acquired(),101,1,"session/A",101,ttl,seed()),"INVALID_TIME")
		end
	end)
	test("26 storage revision and expiry overflow never wrap or mutate data",function()
		local current=acquired()
		current.revision=maximum
		local before=copy(current)
		check(Sessions.write(current,101,maximum,"session/A",101,20,current.data),"REVISION_OVERFLOW")
		check(Sessions.release(current,101,maximum,"session/A",101),"REVISION_OVERFLOW")
		check(Sessions.acquire(current,101,maximum,"session/B",120,20),"REVISION_OVERFLOW")
		check(Sessions.acquire(nil,101,0,"session/A",maximum,1,seed()),"REVISION_OVERFLOW")
		assert(equal(current,before))
	end)
	test("27 replaying a pure transform has no side effects on the input snapshot",function()
		local current=acquired()
		local candidate=changed(current)
		local one=check(Sessions.write(current,101,1,"session/A",101,20,candidate),"WRITTEN")
		local two=check(Sessions.write(current,101,1,"session/A",101,20,candidate),"WRITTEN")
		assert(equal(one,two) and current.revision==1)
		one.data.state.money=0
		assert(two.data.state.money==371 and candidate.state.money==371)
	end)
	test("28 gate publishes only the matching token and keeps detached private state",function()
		local gate=Sessions.newGate(101)
		local ticket=begin(gate,"session/A")
		local source=acquired()
		local published=check(gate.publish(ticket,source,101),"PUBLISHED")
		published.data.state.money=0
		source.data.state.money=1
		local first=check(gate.snapshot(101),"SNAPSHOT")
		assert(first.data.state.money==321)
		first.data.state.money=2
		assert(check(gate.snapshot(101),"SNAPSHOT").data.state.money==321)
	end)
	test("29 a replaced attempt cannot publish or close a newer attempt",function()
		local gate=Sessions.newGate(101)
		local old=begin(gate,"session/A")
		local current=begin(gate,"session/B")
		check(gate.publish(current,acquired("session/B"),101),"PUBLISHED")
		check(gate.publish(old,acquired(),102),"STALE_ATTEMPT")
		check(gate.close(old),"STALE_ATTEMPT")
		assert(check(gate.snapshot(102),"SNAPSHOT").sessionId=="session/B")
	end)
	test("30 coroutine-delayed load completion cannot replace a newer session",function()
		local gate=Sessions.newGate(101)
		local old=begin(gate,"session/A")
		local late=coroutine.create(function(): ()
			local loaded=Profiles.load(101,function(): any
				coroutine.yield("reader paused")
				return seed()
			end)
			assert(loaded.ok and loaded.ready==false)
			check(gate.publish(old,acquired(),102),"STALE_ATTEMPT")
		end)
		local resumed,signal=coroutine.resume(late)
		assert(resumed and signal=="reader paused")
		local current=begin(gate,"session/B")
		check(gate.publish(current,acquired("session/B"),101),"PUBLISHED")
		local completed,problem=coroutine.resume(late)
		assert(completed,tostring(problem))
		assert(coroutine.status(late)=="dead")
		assert(check(gate.snapshot(102),"SNAPSHOT").sessionId=="session/B")
	end)
	test("31 attempt identity blocks ABA even when the same token is reused locally",function()
		local gate=Sessions.newGate(101)
		local old=begin(gate,"session/A")
		local current=begin(gate,"session/A")
		assert(old~=current)
		check(gate.publish(old,acquired(),101),"STALE_ATTEMPT")
		check(gate.publish(current,acquired(),101),"PUBLISHED")
	end)
	test("32 publication rejects foreign tokens and foreign-owner data",function()
		local gate=Sessions.newGate(101)
		local ticket=begin(gate,"session/A")
		check(gate.publish(ticket,acquired("session/B"),101),"SESSION_LOST")
		local foreign=acquired()
		foreign.data=seed(102)
		check(gate.publish(ticket,foreign,101),"INVALID_PROFILE")
		check(gate.snapshot(101),"NOT_LOADED")
	end)
	test("33 reversed save completions never move the gate to an older storage revision",function()
		local gate=Sessions.newGate(101)
		local ticket=begin(gate,"session/A")
		local first=acquired()
		local second=check(Sessions.write(first,101,1,"session/A",101,20,changed(first)),"WRITTEN")
		local third=check(Sessions.write(second,101,2,"session/A",102,20,changed(second)),"WRITTEN")
		check(gate.publish(ticket,third,103),"PUBLISHED")
		check(gate.publish(ticket,second,103),"STALE_REVISION")
		check(gate.publish(ticket,third,103),"STALE_REVISION")
		assert(check(gate.snapshot(103),"SNAPSHOT").data.state.money==421)
	end)
	test("34 newer storage metadata cannot hide lower or changed equal State revision",function()
		local gate=Sessions.newGate(101)
		local ticket=begin(gate,"session/A")
		local current=acquired()
		check(gate.publish(ticket,current,101),"PUBLISHED")
		local lower=copy(current)
		lower.revision=2
		lower.data.state.revision=9
		check(gate.publish(ticket,lower,102),"STALE_STATE")
		local altered=copy(current)
		altered.revision=2
		altered.data.state.money=999
		check(gate.publish(ticket,altered,102),"STALE_STATE")
		assert(check(gate.snapshot(102),"SNAPSHOT").data.state.money==321)
	end)
	test("35 expiry blocks initial publication and previously published snapshots",function()
		local gate=Sessions.newGate(101)
		local ticket=begin(gate,"session/A")
		local current=acquired()
		check(gate.publish(ticket,current,120),"SESSION_EXPIRED")
		check(gate.snapshot(119),"NOT_LOADED")
		check(gate.publish(ticket,current,119),"PUBLISHED")
		check(gate.snapshot(120),"SESSION_EXPIRED")
	end)
	test("36 close invalidates published state and all later completions",function()
		local gate=Sessions.newGate(101)
		local ticket=begin(gate,"session/A")
		check(gate.publish(ticket,acquired(),101),"PUBLISHED")
		check(gate.close(ticket),"CLOSED")
		check(gate.snapshot(101),"NOT_LOADED")
		check(gate.publish(ticket,acquired(),101),"STALE_ATTEMPT")
		check(gate.close(ticket),"STALE_ATTEMPT")
	end)
	test("37 invalid begin does not replace a valid attempt or expose a ticket",function()
		local gate=Sessions.newGate(101)
		local ticket=begin(gate,"session/A")
		local invalid,response=gate.begin("")
		check(response,"INVALID_REQUEST")
		assert(invalid==nil)
		check(gate.publish(ticket,acquired(),101),"PUBLISHED")
	end)
	test("38 gates reject forged tickets malformed records and invalid times",function()
		local gate=Sessions.newGate(101)
		check(gate.publish(nil,acquired(),101),"STALE_ATTEMPT")
		check(gate.close(nil),"STALE_ATTEMPT")
		local ticket=begin(gate,"session/A")
		check(gate.publish({},acquired(),101),"STALE_ATTEMPT")
		check(gate.publish(ticket,{},101),"INVALID_RECORD")
		check(gate.publish(ticket,acquired(),0/0),"INVALID_TIME")
		check(gate.snapshot(-1),"INVALID_TIME")
		check(gate.snapshot(101),"NOT_LOADED")
	end)
	test("39 independent gates share neither attempts nor mutable session data",function()
		local left,right=Sessions.newGate(101),Sessions.newGate(101)
		local leftTicket,rightTicket=begin(left,"session/A"),begin(right,"session/A")
		check(left.publish(rightTicket,acquired(),101),"STALE_ATTEMPT")
		check(right.publish(leftTicket,acquired(),101),"STALE_ATTEMPT")
		check(left.publish(leftTicket,acquired(),101),"PUBLISHED")
		check(right.snapshot(101),"NOT_LOADED")
		check(right.publish(rightTicket,acquired(),101),"PUBLISHED")
		check(left.close(leftTicket),"CLOSED")
		check(right.snapshot(101),"SNAPSHOT")
	end)
	test("40 frozen gate API rejects invalid owner construction",function()
		assert(table.isfrozen(Sessions.newGate(101)))
		for _,owner in {0,-1,1.5,"101",math.huge,0/0} do
			local ok=pcall(Sessions.newGate,owner)
			assert(not ok,"Invalid gate owner accepted")
		end
	end)
	test("41 active claims promises and historical transfer receipts survive session changes",function()
		local data=seed()
		data.state.locations.raw2=State.newLocation("raw2","RawStore",1,{"Holzpaket"})
		data.state.locations.supplier=State.newLocation("supplier","Supplier",1,{"Holzpaket"})
		data.state.locations.worker=State.newLocation("worker","Carrier",1,{"Holzpaket"})
		data.state.batches.b=State.newBatch("b",101,"Holzpaket","supplier")
		data.state.reservations.raw2={kind="Delivery",batchId="b",purchaseOperationId="synthetic/purchase/b"}
		local store=Transfers.new(data.state)
		local player={ownerUserId=101,actorId="Player/101",kind="Player",carrierLocationId="hand",ready=true}
		local worker={ownerUserId=101,actorId="Worker/one",kind="Worker",carrierLocationId="worker",ready=true}
		assert(Transfers.reserve(store,player,{operationId="pickup/reserve",expectedRevision=10,batchId="a",
			sourceId="raw",targetId="hand",quantity=1},100,20).ok)
		assert(Transfers.commit(store,player,{operationId="pickup/commit",expectedRevision=11,
			claimId="pickup/reserve"},101).ok)
		assert(Transfers.reserve(store,worker,{operationId="pending/reserve",expectedRevision=12,batchId="b",
			sourceId="supplier",targetId="worker",quantity=1},101,20).ok)
		data.state=store.profile
		assert(State.validate(data.state))
		local loaded=Profiles.load(101,function(): any return data end)
		assert(loaded.ok and loaded.ready==false)
		local current=check(Sessions.acquire(nil,101,0,"session/A",102,20,loaded.data),"ACQUIRED")
		local saved=check(Sessions.write(current,101,1,"session/A",103,20,current.data),"WRITTEN")
		local free=check(Sessions.release(saved,101,2,"session/A",104),"RELEASED")
		local nextSession=check(Sessions.acquire(free,101,3,"session/B",105,20),"ACQUIRED")
		assert(equal(nextSession.data,data) and nextSession.data.state.revision==13)
		assert(nextSession.data.state.batches.a.locationId=="hand")
		assert(nextSession.data.state.reservations.raw.kind=="Return")
		assert(nextSession.data.state.reservations.raw2.kind=="Delivery")
		assert(nextSession.data.state.claims["pending/reserve"].expiresAt==121)
		assert(nextSession.data.state.receipts["pickup/commit"].result.revision==12)
		nextSession.data.state.claims["pending/reserve"].expiresAt=999
		assert(data.state.claims["pending/reserve"].expiresAt==121 and current.data.state.claims["pending/reserve"].expiresAt==121)
	end)

	return {total=#passed+#failures,passed=passed,failures=failures}
end
