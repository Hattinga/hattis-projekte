--!strict
-- Install tools/tests/p04-05-sessions.luau temporarily as ServerStorage.P0405Suite.
-- Synthetic atomic transforms only; no backend, economic activation, startup or remotes.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
local RunService=game:GetService("RunService")
assert(RunService:IsStudio() and (RunService:IsServer() or not RunService:IsRunning()),"Edit/Server only")
local ServerScriptService=game:GetService("ServerScriptService")
local source=ServerScriptService:FindFirstChild("Factory")
local suite=game:GetService("ServerStorage"):FindFirstChild("P0405Suite")
assert(source and suite and suite:IsA("ModuleScript"),"Factory or temporary suite is missing")
local folder=Instance.new("Folder")
folder.Name="P0405TestCopy_" .. game:GetService("HttpService"):GenerateGUID(false)
folder.Parent=ServerScriptService
local ok,summary=xpcall(function(): any
	for _,name in {"State","Actions","Transfers","Profiles","Sessions"} do
		local module=source:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"),"Missing ModuleScript " .. name)
		module:Clone().Parent=folder
	end
	local suiteCopy=suite:Clone()
	suiteCopy.Parent=folder
	local run=require(suiteCopy)
	local report=run(require(folder.State),require(folder.Profiles),require(folder.Sessions),require(folder.Transfers))
	report.task="P04-05"
	report.status=if #report.failures==0 then "passed" else "failed"
	report.storageAccess=false
	report.economicReady=false
	return report
end,function(problem: any): string return debug.traceback(tostring(problem),2) end)
folder:Destroy()
assert(ok,tostring(summary))
return summary
