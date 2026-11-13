--!strict
-- P02-01: additive metric greybox, executed once in the confirmed Edit place.
-- Ownership: Lead/Studio; only creates Workspace.P02Greybox.
-- Restore: undo the MCP edit recording or remove this task-owned model.
local TARGET_PLACE_ID = 79033653140107
local TARGET_UNIVERSE_ID = 10776116608
local SCALE = 25 / 7
assert(game.PlaceId == TARGET_PLACE_ID and game.GameId == TARGET_UNIVERSE_ID, "Wrong test place")
assert(not workspace:FindFirstChild("P02Greybox"), "P02Greybox already exists; inspect before changing it")

local workshop = workspace:FindFirstChild("FableWorkshop")
assert(workshop and workshop:IsA("Model") and workshop:GetAttribute("ImportPrepared"), "Prepared workshop missing")
local collision = workshop:FindFirstChild("Collision")
local floor = collision and collision:FindFirstChild("Floor")
assert(floor and floor:IsA("BasePart"), "Workshop floor missing")
local sourceScale = workshop:GetAttribute("MetersToStuds")
assert(typeof(sourceScale) == "number" and math.abs(sourceScale - SCALE) < 0.00001, "Scale differs from P01")
local sourcePivot = workshop:GetPivot()
local floorTop = floor.Position.Y + floor.Size.Y / 2

local history = game:GetService("ChangeHistoryService")
-- Studio MCP already records its command; do not start/finish a nested recording.
local outerRecording = history:IsRecordingInProgress()
local recording: string? = nil
if not outerRecording then
	recording = history:TryBeginRecording("P02MetricGreybox", "P02-01 metric greybox")
end
assert(outerRecording or recording, "Cannot record an undo step; no edits applied")

local root = Instance.new("Model")
root.Name = "P02Greybox"
root:SetAttribute("TaskId", "P02-01")
root:SetAttribute("Revision", 1)
root:SetAttribute("MetersToStuds", SCALE)
root:SetAttribute("SourceAssetId", "106051543998570")
root:SetAttribute("BaselineSnapshot", ".local/backups/2026-11-12-p02-01/before-p02-01.rbxm")
root:SetAttribute("FloorTopStuds", floorTop)
root:SetAttribute("DriveTestPassed", false)
root.Parent = workspace

local createdParts = 0
local GREY = Color3.fromRGB(123, 133, 132)
local GRID = Color3.fromRGB(237, 212, 148)
local WALK = Color3.fromRGB(83, 177, 155)
local ROAD = Color3.fromRGB(219, 160, 78)
local BLOCKED = Color3.fromRGB(202, 91, 81)
local REFERENCE = Color3.fromRGB(101, 169, 214)

local function group(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = root
	return folder
end

-- Existing workshop source convention, not the new-asset export convention.
local function position(sourceX: number, sourceY: number, height: number): Vector3
	return sourcePivot:PointToWorldSpace(Vector3.new(-sourceX, height, sourceY) * SCALE)
end

local function part(parent: Instance, name: string, sizeMeters: Vector3, worldPosition: Vector3, color: Color3, collides: boolean, transparency: number): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = sizeMeters * SCALE
	item.CFrame = CFrame.new(worldPosition)
	item.Anchored = true
	item.CanCollide = collides
	item.CanTouch = false
	item.CanQuery = collides
	item.CastShadow = collides
	item.Material = Enum.Material.SmoothPlastic
	item.Color = color
	item.Transparency = transparency
	item.Parent = parent
	createdParts += 1
	if createdParts % 20 == 0 then task.wait() end
	return item
end

local function mark(parent: Instance, name: string, sourceX: number, sourceY: number, width: number, depth: number, height: number, color: Color3, transparency: number): Part
	return part(parent, name, Vector3.new(width, 0.008, depth), position(sourceX, sourceY, height), color, false, transparency)
end

local signs = group("Signs")
local function sign(name: string, text: string, sourceX: number, sourceY: number, height: number, width: number): ()
	local board = part(signs, name, Vector3.new(width, 0.55, 0.035), position(sourceX, sourceY, height), Color3.fromRGB(38, 51, 48), false, 0)
	for _, face in {Enum.NormalId.Front, Enum.NormalId.Back} do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 45
		gui.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(245, 242, 229)
		label.Font = Enum.Font.SourceSansBold
		label.TextScaled = true
		label.TextWrapped = true
		label.Text = text
		label.Parent = gui
		gui.Parent = board
	end
end

local interior = group("Interior")
for x = -3, 3 do mark(interior, "GridX_" .. x, x, 2.5, 0.015, 4.6, 0.018, GRID, 0.20) end
for y = 1, 4 do mark(interior, "GridY_" .. y, 0, y, 6, 0.015, 0.020, GRID, 0.20) end
mark(interior, "Walkway_1_20m", 0, 2.0, 1.2, 3.6, 0.012, WALK, 0.78)
mark(interior, "GateClearWidth_2_10m", 0, 0.12, 2.1, 0.07, 0.024, REFERENCE, 0)
mark(interior, "StopBeforeRack", 0, 3.8, 1.2, 0.07, 0.024, BLOCKED, 0)

local obstructions = group("ExistingFootprints")
for _, name in {"Workbench", "Shelf", "LumberRack", "Sawhorses"} do
	local existing = collision and collision:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		local footprint = part(obstructions, name, Vector3.new(existing.Size.X / SCALE, 0.008, existing.Size.Z / SCALE), Vector3.new(existing.Position.X, floorTop + 0.025 * SCALE, existing.Position.Z), BLOCKED, false, 0.72)
		footprint:SetAttribute("ExistingCollider", existing:GetFullName())
	end
end

local measureField = group("MeasureField")
part(measureField, "Floor_6x4m", Vector3.new(6, 0.14, 4), position(-12, 2.5, -0.07), GREY, true, 0)
for x = -15, -9 do mark(measureField, "GridX_" .. x, x, 2.5, 0.015, 4, 0.018, GRID, 0) end
for index = 0, 4 do mark(measureField, "GridY_" .. index, -12, 0.5 + index, 6, 0.015, 0.020, GRID, 0) end
measureField:SetAttribute("Purpose", "Metric test field; no production stations yet")

local references = group("References")
part(references, "Avatar_0_60x1_56x0_50m", Vector3.new(0.6, 1.56, 0.5), position(-14.2, 3.8, 0.78), REFERENCE, false, 0.40)
part(references, "MeterCube_1m", Vector3.new(1, 1, 1), position(-9.75, 3.75, 0.5), REFERENCE, false, 0.55)
part(references, "GateLeft", Vector3.new(0.08, 2.35, 0.08), position(-13.09, 0.5, 1.175), REFERENCE, false, 0.15)
part(references, "GateRight", Vector3.new(0.08, 2.35, 0.08), position(-10.91, 0.5, 1.175), REFERENCE, false, 0.15)
part(references, "GateHeader", Vector3.new(2.26, 0.08, 0.08), position(-12, 0.5, 2.39), REFERENCE, false, 0.15)

local paths = group("Paths")
local fieldFront = position(-12, 0.5, 0)
local fieldCenter = position(-12, 2.5, 0)
part(paths, "SpawnToWest", Vector3.new((math.abs(fieldCenter.X) - 6) / SCALE, 0.008, 1.2), Vector3.new((fieldCenter.X - 6) / 2, 0.06, 0), WALK, false, 0.35)
part(paths, "WestToField", Vector3.new(1.2, 0.008, math.abs(fieldFront.Z) / SCALE), Vector3.new(fieldCenter.X, 0.06, fieldFront.Z / 2), WALK, false, 0.35)

local approach = group("Approach")
-- Paint only: the current spawn still intersects the outer end of this 5 m lane.
local gatePosition = position(0, 0, 0)
part(approach, "Lane_3x5m", Vector3.new(3, 0.008, 5), Vector3.new(gatePosition.X, 0.04, gatePosition.Z + 2.5 * SCALE), ROAD, false, 0.68)
for _, side in {-1, 1} do
	part(approach, "Edge_" .. side, Vector3.new(0.025, 0.008, 5), Vector3.new(gatePosition.X + side * 1.5 * SCALE, 0.07, gatePosition.Z + 2.5 * SCALE), ROAD, false, 0)
end
approach:SetAttribute("SpawnOverlapUnresolved", true)

sign("FieldTitle", "MASSFELD 6 x 4 m | Raster 1 m\nP02-01 - Stationsprobe folgt", -12, 4.6, 2.2, 4.6)
sign("ReferenceGate", "TOR: lichte Probe 2,10 x 2,35 m", -12, 0.5, 2.80, 3.0)
sign("ReferenceAvatar", "Avatarhuelle 0,60 x 1,56 x 0,50 m", -14.2, 4.4, 1.90, 2.3)
sign("WorkshopGrid", "WERKSTATT | Raster 1 m\nGruen: Fussweg 1,20 m - Rot: Bestand", 0, 3.9, 2.1, 2.5)
sign("DriveBlocker", "SOLL-ANFAHRT 3 x 5 m\nSpawn schneidet Spur - Fahrtest offen", 3.1, -2.5, 1.8, 3.0)

root:SetAttribute("CreatedParts", createdParts)
if recording then history:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
return {task="P02-01", root=root:GetFullName(), parts=createdParts, metersToStuds=SCALE, fieldCenter=tostring(fieldCenter), floorTop=floorTop, existingWorkshopUntouched=true, driveTestPassed=false}
