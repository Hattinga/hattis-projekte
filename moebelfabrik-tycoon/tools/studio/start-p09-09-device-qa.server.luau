--!strict
-- Install under ServerScriptService with TesterUserId configured. StudioTrial opts into a Studio smoke test.
if game.PlaceId ~= 79033653140107 or game.GameId ~= 10776116608 then return end
local runService = game:GetService("RunService")
if runService:IsStudio() and script:GetAttribute("StudioTrial") ~= true then return end
local testerId = script:GetAttribute("TesterUserId")
if type(testerId) ~= "number" or testerId <= 0 or testerId % 1 ~= 0 then return end
local players = game:GetService("Players")
local storage = game:GetService("ServerStorage")
local http = game:GetService("HttpService")
local template = script:FindFirstChild("WorkshopRunner")
assert(template and template:IsA("ModuleScript"), "Missing device workshop runner")
local running = false

local function launch(player: Player)
	if running or player.UserId ~= testerId then return end
	running = true
	task.spawn(function()
		while player.Parent == players do
			local character = player.Character
			if character and character:FindFirstChild("HumanoidRootPart") and character:FindFirstChildOfClass("Humanoid") then
				break
			end
			task.wait(0.25)
		end
		if player.Parent == players then
			local runner = template:Clone()
			local marker = Instance.new("ObjectValue")
			marker.Name, marker.Value, marker.Parent = "Tester", player, runner
			runner.Parent = storage
			local ok, result = pcall(require, runner)
			runner:Destroy()
			if ok then
				print("[P09-09 device] " .. http:JSONEncode(result))
			else
				local active = workspace:FindFirstChild("P0909WorkshopLoad")
				if active and active:GetAttribute("TesterUserId") == player.UserId then
					active:SetAttribute("Phase", "Abgebrochen")
				end
				warn("[P09-09 device] " .. tostring(result))
			end
		end
		while player.Parent == players do player.AncestryChanged:Wait() end
		local active = workspace:FindFirstChild("P0909WorkshopLoad")
		if active and active:GetAttribute("TesterUserId") == player.UserId then active:Destroy() end
		running = false
		local nextTester = players:GetPlayerByUserId(testerId)
		if nextTester then task.defer(launch, nextTester) end
	end)
end

players.PlayerAdded:Connect(launch)
for _, player in players:GetPlayers() do launch(player) end
