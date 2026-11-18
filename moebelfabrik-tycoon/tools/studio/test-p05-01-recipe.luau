--!strict
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and (rs:IsServer() or not rs:IsRunning()), "Edit/Server only")
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local Recipe = require(factory.Recipe)
local root = workspace.P02Line.Stations
local binding, problem = Recipe.bind(root)
assert(binding, problem)
assert(Recipe.id == "Hocker01" and Recipe.version == 1 and #Recipe.stations == 4)
local stages = {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"}
local durations = {6, 8, 6, 4}
local stations = {"Saege", "Montage", "Finish", "Packen"}
local points: {[Instance]: boolean} = {}
local profile = State.newProfile(101)
profile.locations = binding.locations
local report: {any} = {}
for i, station in Recipe.stations do
	assert(station.id == stations[i] and station.durationSeconds == durations[i])
	assert(station.inputStage == stages[i] and station.outputStage == stages[i + 1])
	assert(Recipe.stageNames[stages[i]] and Recipe.stageNames[stages[i + 1]])
	local row: any = {station = station.id, seconds = station.durationSeconds, points = {}}
	for _, role in {"Input", "Process", "Output"} do
		local id = station.id .. "." .. role
		local location, point = binding.locations[id], binding.points[id]
		local expected = if role == "Output" then stages[i + 1] else stages[i]
		assert(location.kind == "Station" .. role and location.capacity == 1)
		assert(#location.acceptedStages == 1 and location.acceptedStages[1] == expected)
		assert(point:IsA("Attachment") and point == root[station.id][role].Transfer and not points[point])
		points[point] = true
		if role ~= "Process" then profile.batches[id] = State.newBatch(id, 101, expected, id) end
		row.points[role] = point:GetFullName()
	end
	table.insert(report, row)
end
assert(State.validate(profile))
profile.batches["Saege.Input"].stage = "Karton"
local valid, reason = State.validate(profile)
assert(not valid and reason == "WRONG_STAGE")
profile.batches["Saege.Input"].stage = "Holzpaket"
profile.batches.extra = State.newBatch("extra", 101, "Holzpaket", "Saege.Input")
valid, reason = State.validate(profile)
assert(not valid and reason == "CAPACITY_EXCEEDED")
local clone = root:Clone()
local ok, failure = pcall(function()
	clone.Saege.Input:SetAttribute("Capacity", 2)
	local bad, code = Recipe.bind(clone)
	assert(not bad and code == "INVALID_POINT:Saege.Input")
	clone.Saege.Input:SetAttribute("Capacity", 1)
	clone.Montage:SetAttribute("InputStage", "Holzpaket")
	bad, code = Recipe.bind(clone)
	assert(not bad and code == "INVALID_STATION:Montage")
	clone.Montage:SetAttribute("InputStage", "Bausatz")
	clone.Packen.Output.Transfer:Destroy()
	bad, code = Recipe.bind(clone)
	assert(not bad and code == "INVALID_POINT:Packen.Output")
end)
clone:Destroy()
assert(ok, tostring(failure))
return {task = "P05-01", status = "passed", testMode = if rs:IsRunning() then "Server" else "Edit",
	stations = report, locations = 12, checks = 9, totalDuration = 24, economicReady = false}
