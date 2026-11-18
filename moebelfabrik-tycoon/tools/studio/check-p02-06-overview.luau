--!strict
-- Read-only acceptance check in Edit or Server during Play; never exposes the overview to players.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local storage = game:GetService("ServerStorage")
local overview = storage:FindFirstChild("P02Overview")
assert(overview and overview:IsA("Model"), "Archived overview missing")
assert(not workspace:FindFirstChild("P02Overview"), "Overview must not appear during normal play")
assert(overview:GetAttribute("TaskId") == "P02-06" and overview:GetAttribute("Revision") == 2)

local parts, strips, labels = 0, 0, 0
for _, item in overview:GetDescendants() do
	assert(not item:IsA("LuaSourceContainer"), "Overview contains executable code")
	if item:IsA("BasePart") then
		parts += 1
		assert(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch,
			"Marker affects physics: " .. item:GetFullName())
		if item.Name == "Strip" then strips += 1 end
	elseif item:IsA("TextLabel") then
		labels += 1
		assert(#item.Text > 0, "Empty label")
	end
end
assert(parts == 171 and strips == 149 and labels == 22, "Overview contents changed")
local route = overview:FindFirstChild("Route")
local sequence = overview:FindFirstChild("StationSequence")
local yards = overview:FindFirstChild("YardTurns")
assert(route and #route:GetChildren() == 5, "Expected five route legs")
assert(sequence and #sequence:GetChildren() == 15, "Expected four stations, two stores, eight slot labels and band")
assert(yards)
for _, name in {"Tischlerei_West", "Holzlieferant", "Moebelhandel", "Privatkunden"} do
	assert(yards:FindFirstChild(name), "Missing destination: " .. name)
end

local line = workspace:FindFirstChild("P02Line")
assert(line)
local stores = line:FindFirstChild("Stores")
assert(stores)
local slots = 0
for _, name in {"Rohstofflager", "Fertiglager"} do
	local depot = stores:FindFirstChild(name)
	assert(depot and depot:GetAttribute("Capacity") == 4)
	for index = 1, 4 do
		local slot = depot:FindFirstChild("Slot" .. index)
		assert(slot and slot:IsA("BasePart") and slot:FindFirstChild("Transfer"), "Missing store slot")
		slots += 1
	end
end
local transfers = 0
for _, item in line:GetDescendants() do
	if item:IsA("Attachment") and item.Name == "Transfer" then transfers += 1 end
end
assert(transfers == 20, "Expected 20 shared transfer points")
return {task = "P02-06", status = "passed", parts = parts, strips = strips, labels = labels,
	storeSlots = slots, transferPoints = transfers, overviewPath = overview:GetFullName()}
