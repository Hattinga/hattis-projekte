--!strict
-- Read-only Edit acceptance for P02-02, excluding the separate carried walk test.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local scale = 25 / 7
local root = workspace:FindFirstChild("P02Line")
local old = workspace:FindFirstChild("P02Greybox")
local workshop = workspace:FindFirstChild("FableWorkshop")
assert(root and old and workshop and workshop:IsA("Model"), "Layout missing")
local tool = game:GetService("ServerStorage"):FindFirstChild("P02CarryProbe")
assert(tool and tool:IsA("Tool") and tool:GetAttribute("GreyboxOnly"), "Probe missing")
local function near(actual: number, expected: number, label: string): ()
	assert(math.abs(actual - expected) < 0.001, label .. " differs")
end
local function requirePart(parent: Instance, name: string): BasePart
	local item = parent:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), name .. " missing")
	return item
end
local function checkSize(item: BasePart, x: number, y: number, z: number): ()
	near(item.Size.X / scale, x, item.Name .. " X")
	near(item.Size.Y / scale, y, item.Name .. " Y")
	near(item.Size.Z / scale, z, item.Name .. " Z")
end
local stations = root:FindFirstChild("Stations")
local stores = root:FindFirstChild("Stores")
assert(stations and stores and #stations:GetChildren() == 4 and #stores:GetChildren() == 2)
local collision = workshop:FindFirstChild("Collision")
assert(collision)
local floor = requirePart(collision, "Floor")
local floorTop = floor.Position.Y + floor.Size.Y / 2
local padCount, solidCount, partCount = 0, 0, 0
local bodies: {BasePart} = {}
for _, model in stations:GetChildren() do
	checkSize(requirePart(model, "Body"), 2.4, 0.88, 0.8)
	table.insert(bodies, requirePart(model, "Body"))
	for _, name in {"Input", "Process", "Output"} do
		local pad = requirePart(model, name)
		checkSize(pad, 0.7, 0.02, 0.6)
		local point = pad:FindFirstChild("Transfer")
		assert(point and point:IsA("Attachment") and point:GetAttribute("Actors") == "Hand,Staff,Band")
		near((point.WorldPosition.Y - floorTop) / scale, 0.9, model.Name .. " transfer height")
		assert(pad:GetAttribute("Capacity") == 1)
		padCount += 1
	end
end
for _, model in stores:GetChildren() do
	assert(model:GetAttribute("Capacity") == 4)
	table.insert(bodies, requirePart(model, "Body"))
	for index = 1, 4 do
		local pad = requirePart(model, "Slot" .. index)
		checkSize(pad, 0.7, 0.02, 0.6)
		assert(pad:GetAttribute("Capacity") == 1)
		local point = pad:FindFirstChild("Transfer")
		assert(point and point:IsA("Attachment"))
		near((point.WorldPosition.Y - floorTop) / scale, 0.9, "Store transfer height")
		padCount += 1
	end
end
local saw = stations:FindFirstChild("Saege")
local assembly = stations:FindFirstChild("Montage")
local finish = stations:FindFirstChild("Finish")
local packing = stations:FindFirstChild("Packen")
assert(saw and assembly and finish and packing)
assert(requirePart(saw, "Input").Position.X < requirePart(saw, "Output").Position.X)
assert(requirePart(finish, "Input").Position.X > requirePart(finish, "Output").Position.X, "Front row not rotated")
near((requirePart(assembly, "Input").Position - requirePart(saw, "Output").Position).Magnitude / scale, 1, "First band length")
local sawBody = requirePart(saw, "Body")
local packBody = requirePart(packing, "Body")
near(((packBody.Position.Z - packBody.Size.Z / 2) - (sawBody.Position.Z + sawBody.Size.Z / 2)) / scale, 1.6, "Central aisle")
local rawStore = stores:FindFirstChild("Rohstofflager")
local finishedStore = stores:FindFirstChild("Fertiglager")
assert(rawStore and finishedStore)
local rawBody = requirePart(rawStore, "Body")
local finishedBody = requirePart(finishedStore, "Body")
near(((finishedBody.Position.X - finishedBody.Size.X / 2) - (rawBody.Position.X + rawBody.Size.X / 2)) / scale, 2.3, "Entry gap")
near(((rawBody.Position.Z - rawBody.Size.Z / 2) - (packBody.Position.Z + packBody.Size.Z / 2)) / scale, 1.3, "Front aisle")
for _, item in root:GetDescendants() do
	assert(not item:IsA("LuaSourceContainer"), "Unexpected runtime script")
	if item:IsA("BasePart") then
		partCount += 1
		assert(item.Anchored and not item.CanTouch)
		if item.CanCollide then solidCount += 1 else assert(not item.CanQuery) end
	end
end
assert(solidCount == 10, "Expected four floor strips and six solid fixtures")
assert(partCount == root:GetAttribute("CreatedParts"))
local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
local probeParts, components = 0, 0
for _, item in tool:GetDescendants() do
	assert(not item:IsA("LuaSourceContainer"), "Probe has runtime script")
	if item:IsA("BasePart") then
		probeParts += 1
		assert(not item.Anchored and item.Massless and not item.CanCollide and not item.CanTouch and not item.CanQuery)
		low = low:Min(item.Position - item.Size / 2)
		high = high:Max(item.Position + item.Size / 2)
		if item.Name == "Seat" or item.Name:match("^Leg%d$") or item.Name:match("^Rail%d$") then components += 1 end
	end
end
near((high.X - low.X) / scale, 0.6, "Probe width")
near((high.Y - low.Y) / scale, 0.18, "Probe height")
near((high.Z - low.Z) / scale, 0.5, "Probe depth")
assert(probeParts == 20 and components == 9 and not tool.CanBeDropped)
local parameters = RaycastParams.new()
parameters.FilterType = Enum.RaycastFilterType.Include
parameters.FilterDescendantsInstances = bodies
local function sourcePosition(x: number, y: number, height: number): Vector3
	return workshop:GetPivot():PointToWorldSpace(Vector3.new(-x, height, y) * scale)
end
for _, sourceY in {1.1, 3.3} do
	local start = sourcePosition(-15.5, sourceY, 0.7)
	assert(not workspace:Raycast(start, sourcePosition(-8.5, sourceY, 0.7) - start, parameters), "Horizontal aisle blocked")
end
for _, sourceX in {-15.25, -8.75} do
	local start = sourcePosition(sourceX, 0.5, 0.7)
	assert(not workspace:Raycast(start, sourcePosition(sourceX, 4.9, 0.7) - start, parameters), "Side aisle blocked")
end
local originalsUnchanged: boolean? = nil
if _G.P0202OriginalBase64 then
	local originals = {workshop, workspace:FindFirstChild("Baseplate"), workspace:FindFirstChildWhichIsA("SpawnLocation")}
	local bytes = game:GetService("SerializationService"):SerializeInstancesAsync(originals)
	originalsUnchanged = buffer.tostring(game:GetService("EncodingService"):Base64Encode(bytes)) == _G.P0202OriginalBase64
	assert(originalsUnchanged, "Fable workshop, baseplate or spawn changed")
end
return {task="P02-02",stations=4,storageSlots=8,transferPads=padCount,sceneParts=partCount,newSolidParts=solidCount,probeParts=probeParts,probeComponents=components,centralAisleMeters=1.6,entryGapMeters=2.3,frontAisleMeters=1.3,originalsUnchanged=originalsUnchanged,productionImplemented=false}
