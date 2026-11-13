--!strict
-- P02-02: additive station layout and a native measuring Tool, not production logic.
-- Ownership: Workspace.P02Line, ServerStorage.P02CarryProbe, selected P02Greybox references/signs.
-- Before-state: .local/backups/2026-11-12-p02-02/before-p02-02.rbxm.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local starterPack = game:GetService("ServerStorage") -- isolated test fixture, not automatic starting inventory
assert(not workspace:FindFirstChild("P02Line") and not starterPack:FindFirstChild("P02CarryProbe"), "P02-02 already exists")
local greybox = workspace:FindFirstChild("P02Greybox")
local workshop = workspace:FindFirstChild("FableWorkshop")
assert(greybox and workshop and workshop:IsA("Model"), "P02-01 baseline missing")
local signs = greybox:FindFirstChild("Signs")
local references = greybox:FindFirstChild("References")
local template = signs and signs:FindFirstChild("FieldTitle")
assert(template and template:IsA("BasePart") and references, "Reference baseline missing")
local scale = 25 / 7
local importedScale = workshop:GetAttribute("MetersToStuds")
assert(typeof(importedScale) == "number" and math.abs(importedScale - scale) < 0.00001, "Unexpected workshop scale")
for _, name in {"Avatar_0_60x1_56x0_50m", "MeterCube_1m"} do
	local reference = references:FindFirstChild(name)
	assert(reference and reference:IsA("BasePart"), "Missing reference " .. name)
end
local avatarSignBefore = signs and signs:FindFirstChild("ReferenceAvatar")
assert(avatarSignBefore and avatarSignBefore:IsA("BasePart"), "Missing avatar sign")
local pivot = workshop:GetPivot()
local function position(x: number, y: number, height: number): Vector3
	return pivot:PointToWorldSpace(Vector3.new(-x, height, y) * scale)
end
local history = game:GetService("ChangeHistoryService")
local recording: string? = nil
if not history:IsRecordingInProgress() then recording = history:TryBeginRecording("P02StationLayout", "P02-02 stations and stores") end
assert(history:IsRecordingInProgress() or recording, "No undo recording")

local root = Instance.new("Model")
root.Name = "P02Line"
root:SetAttribute("TaskId", "P02-02")
root:SetAttribute("Revision", 1)
root:SetAttribute("MetersToStuds", scale)
root:SetAttribute("ProductionImplemented", false)
root:SetAttribute("BaselineSnapshot", ".local/backups/2026-11-12-p02-02/before-p02-02.rbxm")
root.Parent = workspace
local createdParts = 0
local function folder(parent: Instance, name: string): Folder
	local item = Instance.new("Folder")
	item.Name = name
	item.Parent = parent
	return item
end
local function part(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, solid: boolean, transparency: number): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size * scale
	item.CFrame = frame
	item.Anchored = true
	item.CanCollide = solid
	item.CanTouch = false
	item.CanQuery = solid
	item.CastShadow = solid
	item.Color = color
	item.Transparency = transparency
	item.Material = Enum.Material.SmoothPlastic
	item.Parent = parent
	createdParts += 1
	if createdParts % 20 == 0 then task.wait() end
	return item
end
local function caption(board: BasePart, text: string): ()
	for _, item in board:GetDescendants() do if item:IsA("TextLabel") then item.Text = text end end
end
local function sign(parent: Instance, name: string, text: string, frame: CFrame, width: number): BasePart
	local board = template:Clone()
	board.Name = name
	board.Size = Vector3.new(width, 0.35, 0.035) * scale
	board.CFrame = frame
	caption(board, text)
	board.Parent = parent
	createdParts += 1
	return board
end
local function transfer(item: BasePart, name: string, localPosition: Vector3): Attachment
	local point = Instance.new("Attachment")
	point.Name = name
	point.Position = localPosition
	point:SetAttribute("Actors", "Hand,Staff,Band")
	point.Parent = item
	return point
end
local function labelPad(pad: BasePart, text: string): ()
	local surface = Instance.new("SurfaceGui")
	surface.Name = "PadLabel"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 45
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(27, 43, 39)
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.Text = text
	label.Parent = surface
	surface.Parent = pad
end
local INPUT = Color3.fromRGB(104, 168, 216)
local PROCESS = Color3.fromRGB(221, 168, 80)
local OUTPUT = Color3.fromRGB(96, 179, 147)
local GREY = Color3.fromRGB(122, 131, 129)
local WOOD = Color3.fromRGB(197, 150, 100)
local floors = folder(root, "FloorExtension")
for _, spec in {
	{"West", -15.5, 2.5, 1, 7}, {"East", -8.5, 2.5, 1, 7},
	{"South", -12, -0.25, 6, 1.5}, {"North", -12, 5.25, 6, 1.5},
} do
	part(floors, spec[1] :: string, Vector3.new(spec[4] :: number, 0.14, spec[5] :: number), CFrame.new(position(spec[2] :: number, spec[3] :: number, -0.07)), GREY, true, 0)
end
local stations = folder(root, "Stations")
local function station(name: string, number: number, x: number, y: number, yaw: number, input: string, output: string): ()
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("Sequence", number)
	model:SetAttribute("InputStage", input)
	model:SetAttribute("OutputStage", output)
	model.Parent = stations
	local frame = CFrame.new(position(x, y, 0)) * CFrame.Angles(0, yaw, 0)
	part(model, "Body", Vector3.new(2.4, 0.88, 0.8), frame * CFrame.new(0, 0.44 * scale, 0), GREY, true, 0)
	local standpoints = folder(model, "Standpoints")
	for index, nameOfPad in {"Input", "Process", "Output"} do
		local offset = (index - 2) * 0.8
		local pad = part(model, nameOfPad, Vector3.new(0.7, 0.02, 0.6), frame * CFrame.new(offset * scale, 0.89 * scale, 0), ({INPUT, PROCESS, OUTPUT})[index], false, 0)
		transfer(pad, "Transfer", Vector3.new(0, 0.01 * scale, 0))
		pad:SetAttribute("Capacity", 1)
		labelPad(pad, ({"IN", "ARBEIT", "OUT"})[index])
		local standWorld = frame:PointToWorldSpace(Vector3.new(offset * scale, 0.02 * scale, 0))
		standWorld = Vector3.new(standWorld.X, standWorld.Y, position(0, 3.3, 0).Z)
		part(standpoints, nameOfPad, Vector3.new(0.15, 0.008, 0.15), CFrame.new(standWorld), ({INPUT, PROCESS, OUTPUT})[index], false, 0.1)
	end
	sign(model, "Label", number .. "  " .. name .. "\n" .. input .. "  >  " .. output, frame * CFrame.new(0, 1.25 * scale, -0.36 * scale), 2.3)
end
station("Saege", 1, -13.3, 4.5, 0, "Holzpaket", "Bausatz")
station("Montage", 2, -10.7, 4.5, 0, "Bausatz", "Rohhocker")
station("Finish", 3, -10.7, 2.1, math.pi, "Rohhocker", "Fertig")
station("Packen", 4, -13.3, 2.1, math.pi, "Fertig", "Karton")

local stores = folder(root, "Stores")
local function store(name: string, slotXs: {number}, stage: string, color: Color3): ()
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("AcceptedStage", stage)
	model:SetAttribute("Capacity", 4)
	model.Parent = stores
	local centerX = (slotXs[1] + slotXs[4]) / 2
	part(model, "Body", Vector3.new(2.8, 0.88, 0.6), CFrame.new(position(centerX, 0.1, 0.44)), GREY, true, 0)
	local stands = folder(model, "Standpoints")
	for index, x in slotXs do
		local pad = part(model, "Slot" .. index, Vector3.new(0.7, 0.02, 0.6), CFrame.new(position(x, 0.1, 0.89)), color, false, 0)
		pad:SetAttribute("Capacity", 1)
		labelPad(pad, tostring(index))
		transfer(pad, "Transfer", Vector3.new(0, 0.01 * scale, 0))
		part(stands, "Slot" .. index, Vector3.new(0.15, 0.008, 0.15), CFrame.new(position(x, 1.1, 0.02)), color, false, 0.1)
	end
	sign(model, "Label", name .. " | 4 Plaetze\n" .. stage, CFrame.new(position(centerX, 0.1, 1.65)), 2.7)
end
store("Rohstofflager", {-15.6, -14.9, -14.2, -13.5}, "Holzpaket", INPUT)
store("Fertiglager", {-10.5, -9.8, -9.1, -8.4}, "Karton", OUTPUT)

local connections = folder(root, "Connections")
local band = part(connections, "FirstBandPreview", Vector3.new(1, 0.012, 0.7), CFrame.new(position(-12, 4.5, 0.905)), OUTPUT, false, 0.45)
band:SetAttribute("From", "Stations.Saege.Output.Transfer")
band:SetAttribute("To", "Stations.Montage.Input.Transfer")
band:SetAttribute("AutomationImplemented", false)
sign(connections, "BandLabel", "BANDANSCHLUSS 1,00 m\nGleiche Uebergabepunkte", CFrame.new(position(-12, 4.5, 1.72)), 1.9)

local route = folder(root, "Route")
for index, node in {
	{"Eingang", -12, 1.1}, {"Rohstoff", -13.5, 1.1}, {"WestSued", -15.25, 1.1}, {"WestMitte", -15.25, 3.3},
	{"SaegeInput", -14.1, 3.3}, {"SaegeOutput", -12.5, 3.3}, {"MontageInput", -11.5, 3.3}, {"MontageOutput", -9.9, 3.3},
	{"FinishInput", -9.9, 3.3}, {"FinishOutput", -11.5, 3.3}, {"PackenInput", -12.5, 3.3}, {"PackenOutput", -14.1, 3.3},
	{"RueckwegMitte", -15.25, 3.3}, {"RueckwegSued", -15.25, 1.1}, {"Vordergang", -12, 1.1}, {"Fertigware", -10.5, 1.1},
} do
	local marker = part(route, string.format("%02d_%s", index, node[1] :: string), Vector3.new(0.09, 0.008, 0.09), CFrame.new(position(node[2] :: number, node[3] :: number, 0.028)), OUTPUT, false, 0.3)
	marker:SetAttribute("Order", index)
end

local function moveReference(name: string, x: number, y: number, height: number): ()
	local item = references:FindFirstChild(name)
	assert(item and item:IsA("BasePart"), "Missing reference " .. name)
	item.CFrame = CFrame.new(position(x, y, height))
end
moveReference("Avatar_0_60x1_56x0_50m", -14.8, 5.5, 0.78)
moveReference("MeterCube_1m", -9.0, 5.45, 0.5)
local avatarSign = signs and signs:FindFirstChild("ReferenceAvatar")
assert(avatarSign and avatarSign:IsA("BasePart"))
avatarSign.CFrame = CFrame.new(position(-14.8, 6.1, 1.90))
template.CFrame = CFrame.new(position(-12, 6.1, 2.3))
caption(template, "STATIONSPROBE 8 x 7 m | Kernraster 6 x 4 m\nP02-02 - Prueftraeger im Rucksack")
greybox:SetAttribute("ReferenceLayoutTask", "P02-02")

-- Static native Tool: a measuring fixture per tester, not player-owned stock.
local tool = Instance.new("Tool")
tool.Name = "P02CarryProbe"
tool.ToolTip = "Prueftraeger: 1 Sitz, 4 Beine, 4 Zargen. Keine Produktionsware."
tool.CanBeDropped = false
tool.RequiresHandle = true
tool.ManualActivationOnly = true
tool:SetAttribute("TaskId", "P02-02")
tool:SetAttribute("GreyboxOnly", true)
tool:SetAttribute("ComponentCount", 9)
local handle = part(tool, "Handle", Vector3.new(0.6, 0.01, 0.5), CFrame.new(0, 0.005 * scale, 0), INPUT, false, 0)
handle.Anchored = false
handle.Massless = true
local function probePiece(name: string, size: Vector3, center: Vector3, color: Color3): ()
	local item = part(tool, name, size, CFrame.new(center * scale), color, false, 0)
	item.Anchored = false
	item.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = item
	weld.Parent = item
end
for _, side in {-1, 1} do
	probePiece("Side" .. side, Vector3.new(0.01, 0.02, 0.5), Vector3.new(side * 0.295, 0.02, 0), INPUT)
	probePiece("End" .. side, Vector3.new(0.58, 0.02, 0.01), Vector3.new(0, 0.02, side * 0.245), INPUT)
	for _, z in {-0.08, 0.08} do probePiece("GripPost", Vector3.new(0.01, 0.15, 0.01), Vector3.new(side * 0.295, 0.105, z), INPUT) end
	probePiece("GripBar", Vector3.new(0.01, 0.01, 0.17), Vector3.new(side * 0.295, 0.175, 0), INPUT)
end
probePiece("Seat", Vector3.new(0.4, 0.025, 0.4), Vector3.new(-0.085, 0.0225, 0), WOOD)
for index = 0, 3 do
	probePiece("Leg" .. (index + 1), Vector3.new(0.035, 0.035, 0.425), Vector3.new(0.1475 + index * 0.04, 0.0275, 0), WOOD)
	probePiece("Rail" .. (index + 1), Vector3.new(0.29, 0.02, 0.06), Vector3.new(-0.08, 0.045, -0.105 + index * 0.07), WOOD)
end
tool.Parent = starterPack
root:SetAttribute("ExtendedFieldMeters", Vector3.new(8, 0.14, 7))
local sceneParts, probeParts = 0, 0
for _, item in root:GetDescendants() do if item:IsA("BasePart") then sceneParts += 1 end end
for _, item in tool:GetDescendants() do if item:IsA("BasePart") then probeParts += 1 end end
root:SetAttribute("CreatedParts", sceneParts)
if recording then history:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) end
return {task="P02-02", root=root:GetFullName(), stations=4, storageSlots=8, fieldMeters={8,7}, sceneParts=sceneParts, probeParts=probeParts, runtimeScripts=0, productionImplemented=false}
