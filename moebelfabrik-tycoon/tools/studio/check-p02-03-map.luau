--!strict
-- Read-only map geometry/connection acceptance; does not claim a vehicle playtest.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local map = workspace:FindFirstChild("MapGreybox")
assert(map and map:GetAttribute("TaskId") == "P02-03")
local scale = 25 / 7
local roads = map:FindFirstChild("Roads")
local spurs = map:FindFirstChild("Driveways")
local pads = map:FindFirstChild("LoadingPads")
local plots = map:FindFirstChild("Plots")
local factory = map:FindFirstChild("Factory")
local buildings = map:FindFirstChild("Buildings")
assert(roads and spurs and pads and plots and factory and buildings)
local function near(a: number, b: number, label: string): ()
	assert(math.abs(a - b) < 0.003, label)
end
local function ends(part: BasePart): (Vector3, Vector3)
	local half = (part.Size.Z - 0.15 * scale) / 2
	return part.Position - part.CFrame.LookVector * half, part.Position + part.CFrame.LookVector * half
end
local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local direction = b - a
	local fraction = math.clamp((point - a):Dot(direction) / direction:Dot(direction), 0, 1)
	return (point - (a + direction * fraction)).Magnitude
end
local ring: {BasePart} = {}
for _, item in roads:GetChildren() do
	if item:IsA("BasePart") and item.Name:match("^Ring_%d+$") then table.insert(ring, item) end
end
table.sort(ring, function(a: BasePart, b: BasePart): boolean
	return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
end)
assert(#ring == 36 and #plots:GetChildren() == 4 and #pads:GetChildren() == 4)
for index, road in ring do
	near(road.Size.X / scale, 7, "Road width")
	local _, finish = ends(road)
	local nextStart = ends(ring[index % #ring + 1])
	near((finish - nextStart).Magnitude, 0, "Ring gap")
end
local floorFilter = RaycastParams.new()
floorFilter.FilterType = Enum.RaycastFilterType.Include
floorFilter.FilterDescendantsInstances = {map}
local obstacleFilter = RaycastParams.new()
obstacleFilter.FilterType = Enum.RaycastFilterType.Include
obstacleFilter.FilterDescendantsInstances = {factory, buildings}
local allRoads = table.clone(ring)
local destinations = 0
for _, driveway in spurs:GetChildren() do
	assert(driveway:IsA("BasePart"))
	near(driveway.Size.X / scale, 6, "Driveway width")
	local a, b = ends(driveway)
	local minimum = math.huge
	for _, road in ring do local ra, rb = ends(road); minimum = math.min(minimum, distanceToSegment(a, ra, rb)) end
	near(minimum, 0, "Driveway does not join ring")
	local pad = pads:FindFirstChild(driveway.Name)
	assert(pad and pad:IsA("BasePart"))
	near((Vector3.new(b.X, 0, b.Z) - Vector3.new(pad.Position.X, 0, pad.Position.Z)).Magnitude, 0, "Driveway misses loading pad")
	near(pad.Size.X / scale, 12, "Loading width")
	near(pad.Size.Z / scale, 12, "Loading depth")
	table.insert(allRoads, driveway)
	destinations += 1
end
local groundSamples = 0
for _, road in allRoads do
	local a, b = ends(road)
	local segments = math.ceil((b - a).Magnitude / scale)
	for _, lateral in {-1.2, 0, 1.2} do
		local offset = road.CFrame.RightVector * lateral * scale
		local start = a + offset + Vector3.new(0, 1.0 * scale, 0)
		assert(not workspace:Raycast(start, b - a, obstacleFilter), "Road corridor intersects a building")
		for index = 0, segments do
			local sample = a:Lerp(b, index / segments) + offset
			assert(workspace:Raycast(sample + Vector3.new(0, scale, 0), Vector3.new(0, -2 * scale, 0), floorFilter), "Missing road support")
			groundSamples += 1
		end
	end
	task.wait()
end
local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
local plotA = plots:FindFirstChild("Plot1")
assert(spawn and plotA and plotA:IsA("BasePart"))
assert(math.abs(spawn.Position.X - plotA.Position.X) + spawn.Size.X / 2 < plotA.Size.X / 2)
assert(math.abs(spawn.Position.Z - plotA.Position.Z) + spawn.Size.Z / 2 < plotA.Size.Z / 2)
for _, road in allRoads do
	local a, b = ends(road)
	local flatSpawn = Vector3.new(spawn.Position.X, a.Y, spawn.Position.Z)
	assert(distanceToSegment(flatSpawn, a, b) > road.Size.X / 2 + spawn.Size.Magnitude / 2, "Spawn blocks traffic")
end
assert(not game:GetService("StarterPack"):FindFirstChild("P02CarryProbe"), "Test tool still in game start")
assert(game:GetService("ServerStorage"):FindFirstChild("P02CarryProbe"), "Test fixture missing")
local originals = {workspace:FindFirstChild("FableWorkshop"), workspace:FindFirstChild("Baseplate"), workspace:FindFirstChild("P02Greybox"), workspace:FindFirstChild("P02Line")}
local bytes = game:GetService("SerializationService"):SerializeInstancesAsync(originals)
local identical = buffer.tostring(game:GetService("EncodingService"):Base64Encode(bytes)) == _G.MapOriginalBase64
assert(identical, "Old test area changed")
return {task="P02-03",ringSegments=36,connectedDestinations=destinations,groundSamples=groundSamples,clearCorridors=120,spawnOnFactoryPlot=true,spawnOutsideRoads=true,testToolInServerStorage=true,oldTestAreaByteIdentical=identical,vehicleTestPassed=false}
