--!strict
-- Read-only P02-01 acceptance check in the confirmed Edit datamodel.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local scale = 25 / 7
local root = workspace:FindFirstChild("P02Greybox")
local workshop = workspace:FindFirstChild("FableWorkshop")
assert(root and root:IsA("Model") and root:GetAttribute("TaskId") == "P02-01", "Greybox missing")
assert(workshop and workshop:IsA("Model"), "Original workshop missing")

local function near(actual: number, expected: number, label: string): ()
	assert(math.abs(actual - expected) < 0.001, label .. " differs")
end
local function getPart(folder: string, name: string): BasePart
	local parent = root:FindFirstChild(folder)
	local item = parent and parent:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), folder .. "." .. name .. " missing")
	return item
end
local function sizeMeters(item: BasePart, expected: Vector3): ()
	near(item.Size.X / scale, expected.X, item.Name .. " width")
	near(item.Size.Y / scale, expected.Y, item.Name .. " height")
	near(item.Size.Z / scale, expected.Z, item.Name .. " depth")
end

local field = getPart("MeasureField", "Floor_6x4m")
sizeMeters(field, Vector3.new(6, 0.14, 4))
local originalCollision = workshop:FindFirstChild("Collision")
local originalFloor = originalCollision and originalCollision:FindFirstChild("Floor")
assert(originalFloor and originalFloor:IsA("BasePart"))
local floorTop = originalFloor.Position.Y + originalFloor.Size.Y / 2
near(field.Position.Y + field.Size.Y / 2, floorTop, "Field floor level")
near((getPart("MeasureField", "GridX_-14").Position - getPart("MeasureField", "GridX_-15").Position).Magnitude, scale, "Field grid 1m")
near((getPart("Interior", "GridX_1").Position - getPart("Interior", "GridX_0").Position).Magnitude, scale, "Interior grid 1m")
sizeMeters(getPart("References", "Avatar_0_60x1_56x0_50m"), Vector3.new(0.6, 1.56, 0.5))
sizeMeters(getPart("References", "MeterCube_1m"), Vector3.new(1, 1, 1))

local left = getPart("References", "GateLeft")
local right = getPart("References", "GateRight")
local header = getPart("References", "GateHeader")
local gateWidth = (right.Position.X - right.Size.X / 2) - (left.Position.X + left.Size.X / 2)
local gateHeight = header.Position.Y - header.Size.Y / 2 - floorTop
near(gateWidth / scale, 2.1, "Reference gate opening width")
near(gateHeight / scale, 2.35, "Reference gate opening height")
local lane = getPart("Approach", "Lane_3x5m")
sizeMeters(lane, Vector3.new(3, 0.008, 5))
sizeMeters(getPart("Interior", "Walkway_1_20m"), Vector3.new(1.2, 0.008, 3.6))

local partCount, solidCount, meshCount = 0, 0, 0
for _, item in root:GetDescendants() do
	assert(not item:IsA("LuaSourceContainer"), "Unexpected runtime script")
	if item:IsA("BasePart") then
		partCount += 1
		assert(item.Anchored and not item.CanTouch, "Unsafe greybox part")
		if item.CanCollide then
			solidCount += 1
			assert(item == field, "Unexpected new collider")
		else
			assert(not item.CanQuery, "Overlay affects raycasts")
		end
	end
end
for _, item in workshop:GetDescendants() do if item:IsA("MeshPart") then meshCount += 1 end end
assert(meshCount == 153 and originalCollision and #originalCollision:GetChildren() == 21, "Original composition changed")
assert(solidCount == 1 and partCount == root:GetAttribute("CreatedParts"))
local boundsCFrame, boundsSize = workshop:GetBoundingBox()
assert(field.Position.X + field.Size.X / 2 < boundsCFrame.Position.X - boundsSize.X / 2, "Measure field overlaps workshop")

local rayParameters = RaycastParams.new()
rayParameters.FilterType = Enum.RaycastFilterType.Include
rayParameters.FilterDescendantsInstances = {originalCollision}
local function sourcePosition(x: number, y: number, height: number): Vector3
	return workshop:GetPivot():PointToWorldSpace(Vector3.new(-x, height, y) * scale)
end
for _, x in {-0.3, 0, 0.3} do
	local start = sourcePosition(x, 0.2, 1.0)
	assert(not workspace:Raycast(start, sourcePosition(x, 3.8, 1.0) - start, rayParameters), "Central walk path blocked")
end
for _, x in {-0.7, 0, 0.7} do
	local start = sourcePosition(x, -0.3, 1.0)
	assert(not workspace:Raycast(start, sourcePosition(x, 0.4, 1.0) - start, rayParameters), "Original doorway blocked")
end

local snapshotMatches: boolean? = nil
if _G.P02BeforeBase64 then
	local roots = {workshop, workspace:FindFirstChild("Baseplate"), workspace:FindFirstChildWhichIsA("SpawnLocation")}
	local bytes = game:GetService("SerializationService"):SerializeInstancesAsync(roots)
	snapshotMatches = buffer.tostring(game:GetService("EncodingService"):Base64Encode(bytes)) == _G.P02BeforeBase64
	assert(snapshotMatches, "Original roots differ from the before snapshot")
end
return {task="P02-01", placeId=game.PlaceId, metersToStuds=scale, parts=partCount, newColliders=solidCount, workshopMeshes=meshCount, originalColliders=21, gateMeters={gateWidth/scale,gateHeight/scale}, clearRayChecks=6, originalSnapshotIdentical=snapshotMatches, knownDriveBlocker="Spawn intersects 5m approach; driving not accepted"}
