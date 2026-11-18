--!strict
-- Explicit isolated backend test only. Invoke manually in Studio Server-Play.
-- A fresh random scope prevents access to real player/profile keys.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsServer(),"Studio Server only")
local ServerStorage=game:GetService("ServerStorage")
assert(not ServerStorage:FindFirstChild("P0406BackendResult"),"Probe already started; do not duplicate")
local Http=game:GetService("HttpService")
local result=Instance.new("StringValue")
result.Name="P0406BackendResult"
result.Parent=ServerStorage
local scope="P0406_" .. Http:GenerateGUID(false):gsub("-","")
task.spawn(function(): ()
	local summary: any={task="P04-06",scope=scope,store="FactoryP0406_Test",key="Player_101",
		status="running",passed={},failures={},economicReady=false,syntheticProfile=true}
	local ok,problem=xpcall(function(): boolean
		local factory=game:GetService("ServerScriptService"):FindFirstChild("Factory")
		assert(factory,"Factory missing")
		local State=require(factory.State)
		local Sessions=require(factory.Sessions)
		local Persistence=require(factory.Persistence)
		local store=game:GetService("DataStoreService"):GetDataStore(summary.store,scope)
		local real=Persistence.dataStore(store)
		local dropReply=false
		local updates=0
		local backend={read=real.read,update=function(key: string, transform: any): any
			updates+=1
			local value=real.update(key,transform)
			if dropReply then dropReply=false;error("Synthetic lost response AFTER backend commit") end
			return value
		end}
		local controller=Persistence.new(101,backend)
		local function passed(name: string): () table.insert(summary.passed,name) end
		local function success(response: any): any
			assert(response.ok and response.ready==false and not response.unknown,response.code)
			assert(response.confirmed,"Missing confirmed record")
			return response.confirmed
		end
		local initialized=0
		local record=success(controller.load("backend/A/" .. scope,300,function(owner: number): any
			initialized+=1
			local state=State.newProfile(owner)
			state.money=321
			return {profileVersion=1,state=state,
				progress={version=1,selectedRecipeId="Hocker01",selectedRecipeVersion=1}}
		end))
		assert(initialized==1 and record.data.state.money==321 and record.revision==1)
		passed("atomic creation after fresh confirmed absence")
		local candidate=record.data
		candidate.state.money=456;candidate.state.revision+=1
		record=success(controller.save(candidate,300))
		assert(record.data.state.money==456 and record.revision==2)
		passed("confirmed real UpdateAsync save")
		local raw=real.read(summary.key)
		assert(raw.revision==record.revision and raw.data.state.money==456)
		passed("uncached backend read preserves confirmed save")
		candidate=record.data
		candidate.state.money=789;candidate.state.revision+=1
		dropReply=true
		local unknown=controller.save(candidate,300)
		assert(not unknown.ok and unknown.unknown and not unknown.ready)
		assert(unknown.confirmed.data.state.money==456,"Proposal replaced confirmed snapshot")
		local before=updates
		assert(not controller.save(candidate,300).ok and updates==before,"Unknown write retried")
		passed("lost reply keeps confirmed snapshot and blocks another write")
		record=success(controller.reconcile())
		assert(record.data.state.money==789 and record.revision==3)
		passed("fresh read reconciles real committed record after dropped reply")
		local oldRevision=record.revision
		local oldToken=record.sessionId
		success(controller.release())
		local rejoined=Persistence.new(101,real)
		record=success(rejoined.load("backend/B/" .. scope,300,function(): any
			error("Existing profile must not initialize")
		end))
		assert(record.data.state.money==789 and record.revision==5)
		passed("new controller loads last confirmed backend state without initialization")
		local rejected: any=nil
		real.update(summary.key,function(current: any): any
			rejected=Sessions.write(current,101,oldRevision,oldToken,os.time(),300,candidate)
			assert(not rejected.ok,"Old session unexpectedly wrote")
			return nil
		end)
		raw=real.read(summary.key)
		assert(raw.revision==record.revision and raw.data.state.money==789
			and raw.sessionId==record.sessionId)
		passed("late old-session callback cannot overwrite successor")
		success(rejoined.release())
		summary.finalRecord=real.read(summary.key)
		assert(summary.finalRecord.sessionId=="" and summary.finalRecord.revision==6)
		summary.updates=updates
		-- Keep the small released artificial record for reproducible inspection; no real key cleanup.
		return true
	end,function(failure: any): string return debug.traceback(tostring(failure),2) end)
	if not ok then table.insert(summary.failures,tostring(problem)) end
	summary.status=if ok then "passed" else "failed"
	summary.checks=#summary.passed
	result.Value=Http:JSONEncode(summary)
end)
return {started=true,scope=scope,store="FactoryP0406_Test",key="Player_101"}
