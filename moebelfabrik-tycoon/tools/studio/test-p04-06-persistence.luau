--!strict
-- Install pure suite temporarily as ServerStorage.P0406Suite, then run in Edit/Server.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
local RunService=game:GetService("RunService")
assert(RunService:IsStudio() and (RunService:IsServer() or not RunService:IsRunning()),"Edit/Server only")
local source=game:GetService("ServerScriptService"):FindFirstChild("Factory")
local suite=game:GetService("ServerStorage"):FindFirstChild("P0406Suite")
assert(source and suite and suite:IsA("ModuleScript"),"Factory or temporary suite missing")
local folder=Instance.new("Folder")
folder.Name="P0406TestCopy_" .. game:GetService("HttpService"):GenerateGUID(false)
folder.Parent=game:GetService("ServerScriptService")
local ok,summary=xpcall(function(): any
	for _,name in {"State","Actions","Transfers","Profiles","Sessions","Persistence"} do
		local module=source:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"),"Missing " .. name)
		module:Clone().Parent=folder
	end
	local suiteCopy=suite:Clone();suiteCopy.Parent=folder
	local Persistence=require(folder.Persistence)
	local run=require(suiteCopy)
	local report=run(require(folder.State),require(folder.Profiles),require(folder.Sessions),require(folder.Transfers),Persistence)
	local optionsSeen: {any}={}
	local ids={101}
	local metadata={fixture="P04-06"}
	local accepted: any=nil
	local current={fixture=true}
	local backend=Persistence.dataStore({
		GetAsync=function(_: any,key: string,options: any): any
			assert(key=="Player_101" and options:IsA("DataStoreGetOptions") and not options.UseCache)
			table.insert(optionsSeen,options)
			return current
		end,
		UpdateAsync=function(_: any,key: string,transform: any): any
			assert(key=="Player_101")
			local value,userIds,keyMetadata=transform(current,{
				GetUserIds=function(): any return ids end,
				GetMetadata=function(): any return metadata end,
			})
			if value~=nil then assert(userIds==ids and keyMetadata==metadata);accepted=value end
			return value
		end,
	})
	assert(backend.read("Player_101")==current and backend.read("Player_101")==current)
	assert(optionsSeen[1]~=optionsSeen[2],"Read options were shared")
	table.insert(report.passed,"wrapper: real engine read options bypass cache and are fresh per read")
	local candidate={accepted=true}
	assert(backend.update("Player_101",function(value: any): any assert(value==current);return candidate end)==candidate
		and accepted==candidate)
	table.insert(report.passed,"wrapper: UpdateAsync preserves user associations and metadata")
	accepted=nil
	assert(backend.update("Player_101",function(): any return nil end)==nil and accepted==nil)
	table.insert(report.passed,"wrapper: nil transform abort remains nil")
	report.wrapperChecks=3
	report.total+=3
	report.task="P04-06"
	report.status=if #report.failures==0 then "passed" else "failed"
	report.storageAccess=false
	report.economicReady=false
	return report
end,function(problem: any): string return debug.traceback(tostring(problem),2) end)
folder:Destroy()
assert(ok,tostring(summary))
return summary
