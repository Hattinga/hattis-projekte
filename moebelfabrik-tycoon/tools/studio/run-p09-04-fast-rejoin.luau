--!strict
-- P09-04: rejoin while the inherited exit claim is still valid. A real server change in Studio takes longer than
-- the 16 s claim, so a second session loads the same isolated DataStore scope in the same Play server.
-- Fresh Play server, then run this once. It sets P06LoadingDemo, P0901Funds, P0803WorkerStock and a new scope,
-- runs ToolRun.LineDemo with P0904MotionProbe (leave), removes everything the first session created and runs
-- fresh copies of both modules (return). Changes stay in the Play datamodel.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning())
local storage = game:GetService("ServerStorage")
local http = game:GetService("HttpService")
local player = assert(game:GetService("Players"):GetPlayers()[1])
local toolRun = storage.ToolRun
local function known(root: Instance, className: string): {[Instance]: boolean}
	local found = {}
	for _, item in root:GetDescendants() do
		if item:IsA(className) then found[item] = true end
	end
	return found
end
local prompts, hooks = known(workspace, "ProximityPrompt"), known(storage, "BindableFunction")
local scope = "P0607_" .. string.lower((http:GenerateGUID(false):gsub("-", "")))
for name, value in {P06LoadingDemo = true, P0901Funds = true, P0803WorkerStock = true, P0904Case = "leave",
	P0607ResumeScope = scope} do
	workspace:SetAttribute(name, value)
end
require(toolRun.LineDemo :: ModuleScript)
local left = require(toolRun.P0904MotionProbe :: ModuleScript)
-- The first session is released and closing; drop its folder, GUI, prompts and hooks before the second one.
workspace.P0509LineDemo:Destroy()
for _, name in {"P0509LineDemo", "P0509Facing"} do
	local item = (player:FindFirstChildOfClass("PlayerGui") :: PlayerGui):FindFirstChild(name)
	if item then item:Destroy() end
end
for _, prompt in workspace:GetDescendants() do
	if prompt:IsA("ProximityPrompt") and not prompts[prompt] then prompt:Destroy() end
end
for _, hook in storage:GetDescendants() do
	if hook:IsA("BindableFunction") and not hooks[hook] then hook:Destroy() end
end
for _, name in {"LineDemo", "P0904MotionProbe"} do
	local original = toolRun:FindFirstChild(name) :: ModuleScript
	local copy = original:Clone()
	original:Destroy()
	copy.Parent = toolRun
end
workspace:SetAttribute("P0904Case", "return")
workspace:SetAttribute("P0904InheritedClaim", left.inheritedClaim)
local gap = os.time() - left.releasedAt
local returned = require(toolRun.P0904MotionProbe :: ModuleScript)
return {scope = scope, leave = left, ["return"] = returned, claimSecondsLeftAtLeave = left.expiresAt - left.releasedAt,
	secondsBetweenSessions = gap}
