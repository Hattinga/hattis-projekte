--!strict
-- P02-03 actual map greybox. The earlier workshop is only an AI comparison asset.
-- Owns MapGreybox, SpawnLocation.CFrame, the test Tool's parent, and editor camera.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
assert(not workspace:FindFirstChild("MapGreybox"), "MapGreybox already exists")
local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
assert(spawn, "Existing spawn missing")
local starterPack = game:GetService("StarterPack")
local serverStorage = game:GetService("ServerStorage")
local probe = starterPack:FindFirstChild("P02CarryProbe")
assert(not probe or not serverStorage:FindFirstChild("P02CarryProbe"), "Conflicting test tools")
local scale = 25 / 7
local origin = Vector3.new(360, 0, 360)
local history = game:GetService("ChangeHistoryService")
local recording: string? = nil
if not history:IsRecordingInProgress() then recording = history:TryBeginRecording("MapGreybox", "P02-03 map layout") end
assert(history:IsRecordingInProgress() or recording, "No undo recording")
local root = Instance.new("Model")
root.Name = "MapGreybox"
root:SetAttribute("TaskId", "P02-03")
root:SetAttribute("Revision", 1)
root:SetAttribute("MetersToStuds", scale)
root:SetAttribute("OriginStuds", origin)
root:SetAttribute("PreviousSpawnCFrame", spawn.CFrame)
root:SetAttribute("Snapshot", ".local/backups/2026-11-12-p02-03/before-map.rbxm")
root:SetAttribute("ComparisonWorkshopIsGameBuilding", false)
root.Parent = workspace
local count = 0
local function group(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = root
	return folder
end
local function point(x: number, z: number, height: number): Vector3
	return origin + Vector3.new(x, height, z) * scale
end
local function block(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, solid: boolean): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size * scale
	item.CFrame = frame
	item.Color = color
	item.Material = Enum.Material.SmoothPlastic
	item.Anchored = true
	item.CanCollide = solid
	item.CanTouch = false
	item.CanQuery = solid
	item.CastShadow = solid
	item.Parent = parent
	count += 1
	if count % 20 == 0 then task.wait() end
	return item
end
local signs = group("Signs")
local function sign(name: string, text: string, x: number, z: number, height: number, width: number): ()
	local board = block(signs, name, Vector3.new(width, 1.3, 0.08), CFrame.new(point(x, z, height)), Color3.fromRGB(42, 57, 50), false)
	for _, face in {Enum.NormalId.Front, Enum.NormalId.Back} do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 15
		local textLabel = Instance.new("TextLabel")
		textLabel.Size = UDim2.fromScale(1, 1)
		textLabel.BackgroundTransparency = 1
		textLabel.TextColor3 = Color3.fromRGB(245, 240, 223)
		textLabel.Font = Enum.Font.SourceSansBold
		textLabel.TextScaled = true
		textLabel.TextWrapped = true
		textLabel.Text = text
		textLabel.Parent = gui
		gui.Parent = board
	end
end
local grass = Color3.fromRGB(111, 137, 100)
local asphalt = Color3.fromRGB(67, 73, 75)
local concrete = Color3.fromRGB(169, 173, 165)
local timber = Color3.fromRGB(181, 134, 86)
local ground = group("Ground")
block(ground, "District", Vector3.new(224, 0.1, 180), CFrame.new(point(0, 0, -0.03)), grass, true)
local roads = group("Roads")
local function roadSegment(parent: Instance, name: string, a: Vector2, b: Vector2, width: number, lane: boolean): ()
	local from, to = point(a.X, a.Y, 0), point(b.X, b.Y, 0)
	local center = (from + to) / 2
	local frame = CFrame.lookAt(center, to)
	local length = (b - a).Magnitude
	local surface = block(parent, name, Vector3.new(width, 0.08, length + 0.15), frame, asphalt, true)
	surface.Material = Enum.Material.Asphalt
	if lane then
		block(parent, name .. "_Center", Vector3.new(0.12, 0.008, math.max(0.4, length * 0.58)), frame + Vector3.new(0, 0.052 * scale, 0), Color3.fromRGB(227, 217, 177), false)
	end
end
local ring: {Vector2} = {Vector2.new(-80, -36)}
local function arc(cx: number, cz: number, firstAngle: number): ()
	for index = 1, 8 do
		local angle = math.rad(firstAngle + index * 90 / 8)
		table.insert(ring, Vector2.new(cx + math.cos(angle) * 14, cz + math.sin(angle) * 14))
	end
end
arc(-66, -36, 180)
table.insert(ring, Vector2.new(66, -50))
arc(66, -36, 270)
table.insert(ring, Vector2.new(80, 36))
arc(66, 36, 0)
table.insert(ring, Vector2.new(-66, 50))
arc(-66, 36, 90)
table.insert(ring, ring[1])
for index = 1, #ring - 1 do roadSegment(roads, "Ring_" .. index, ring[index], ring[index + 1], 7, true) end
local spurs = group("Driveways")
roadSegment(spurs, "Factory", Vector2.new(-80, -10), Vector2.new(-32, -10), 6, false)
roadSegment(spurs, "Supplier", Vector2.new(-35, -50), Vector2.new(-35, -61), 6, false)
roadSegment(spurs, "Dealer", Vector2.new(80, -12), Vector2.new(93, -12), 6, false)
roadSegment(spurs, "Private", Vector2.new(35, 50), Vector2.new(35, 61), 6, false)

local plots = group("Plots")
for index, spec in {{-32, -22}, {32, -22}, {-32, 22}, {32, 22}} do
	block(plots, "Plot" .. index, Vector3.new(40, 0.035, 40), CFrame.new(point(spec[1], spec[2], 0.0125)), index == 1 and concrete or Color3.fromRGB(132, 148, 115), true)
	sign("Plot" .. index, index == 1 and "DEINE MOEBELFABRIK\nGrundstueck A | 40 x 40 m" or ("GRUNDSTUECK " .. index .. "\n40 x 40 m | Reserve"), spec[1], spec[2] - 17, 2.6, 10)
end
local factory = group("Factory")
block(factory, "HallFloor", Vector3.new(24, 0.2, 18), CFrame.new(point(-32, -29, 0.1)), Color3.fromRGB(192, 195, 185), true)
block(factory, "BackWall", Vector3.new(24, 6, 0.3), CFrame.new(point(-32, -38, 3.2)), Color3.fromRGB(211, 208, 192), true)
for _, x in {-44, -20} do block(factory, "SideWall", Vector3.new(0.3, 6, 18), CFrame.new(point(x, -29, 3.2)), Color3.fromRGB(211, 208, 192), true) end
for _, x in {-39, -25} do block(factory, "FrontPier", Vector3.new(10, 6, 0.3), CFrame.new(point(x, -20, 3.2)), Color3.fromRGB(211, 208, 192), true) end
block(factory, "DoorHeader", Vector3.new(4, 2, 0.3), CFrame.new(point(-32, -20, 5.2)), Color3.fromRGB(120, 139, 126), true)
sign("FactoryGate", "FABRIK A\nNeue Hallenprobe | Tor 4 x 4 m", -32, -20, 6.9, 12)

local pads = group("LoadingPads")
local destinations = group("Destinations")
for _, spec in {
	{"Factory", -32, -10, "FABRIK | Laden / Entladen"}, {"Supplier", -35, -61, "HOLZLIEFERANT | Abholung"},
	{"Dealer", 93, -12, "MOEBELHANDEL | Uebergabe"}, {"Private", 35, 61, "PRIVATKUNDEN | Uebergabe"},
} do
	local name, x, z = spec[1] :: string, spec[2] :: number, spec[3] :: number
	block(pads, name, Vector3.new(12, 0.08, 12), CFrame.new(point(x, z, 0.005)), Color3.fromRGB(181, 181, 162), true)
	local marker = block(destinations, name, Vector3.new(0.2, 0.008, 0.2), CFrame.new(point(x, z, 0.051)), Color3.fromRGB(237, 194, 101), false)
	marker:SetAttribute("Role", name)
	sign(name .. "Loading", spec[4] :: string, x, z - 5.5, 2.8, 10)
end
local buildings = group("Buildings")
block(buildings, "Supplier", Vector3.new(24, 6, 12), CFrame.new(point(-35, -74, 3.1)), timber, true)
block(buildings, "Dealer", Vector3.new(10, 7, 20), CFrame.new(point(106, -12, 3.6)), Color3.fromRGB(159, 175, 178), true)
for index, x in {20, 35, 50} do
	block(buildings, "House" .. index, Vector3.new(8, 4.5, 8), CFrame.new(point(x, 76, 2.35)), ({Color3.fromRGB(209, 185, 155),Color3.fromRGB(179, 190, 167),Color3.fromRGB(190, 178, 168)})[index], true)
	block(buildings, "HouseRoof" .. index, Vector3.new(8.8, 0.4, 8.8), CFrame.new(point(x, 76, 4.8)), Color3.fromRGB(83, 91, 89), true)
end
local landscape = group("Landscape")
for index = 1, 12 do
	local x = -101 + (index - 1) * 18
	for _, z in {-85, 85} do
		local trunk = block(landscape, "TreeTrunk", Vector3.new(0.6, 3.5, 0.6), CFrame.new(point(x, z, 1.8)), timber, false)
		local crown = block(landscape, "TreeCrown", Vector3.new(4, 5, 4), CFrame.new(point(x, z, 5)), Color3.fromRGB(69, 105, 73), false)
		crown.Shape = Enum.PartType.Ball
	end
end
sign("MapTitle", "MOEBELFABRIK TYCOON\nErste Spielkarten-Greybox | P02-03", 0, -4, 5, 20)
spawn.CFrame = CFrame.new(point(-16, -33, 0.03 + spawn.Size.Y / (2 * scale)))
root:SetAttribute("SpawnOnFactoryPlot", true)
if probe then probe.Parent = serverStorage end
root:SetAttribute("DebugToolRemovedFromStarterPack", probe ~= nil)
root:SetAttribute("PartCount", count)
workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(400, 820, 640), point(0, 0, 0))
workspace.CurrentCamera.Focus = CFrame.new(point(0, 0, 0))
if recording then history:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
return {task="P02-03",root=root:GetFullName(),parts=count,ringSegments=#ring-1,roadWidthMeters=7,cornerRadiusMeters=14,plots=4,activeFactoryPlots=1,destinations=4,comparisonAssetUsedAsBuilding=false}
