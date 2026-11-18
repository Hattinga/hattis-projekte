--!strict
-- Measured greybox of one assembled Hocker01 (DIMENSIONS H1-H4), pending the imported art.
local StoolView = {}
local SCALE = 25 / 7
local LOOKS = {
	Rohhocker = {wood = Color3.fromRGB(226, 196, 156), label = "Rohhocker"},
	Fertig = {wood = Color3.fromRGB(168, 106, 62), label = "Fertiger Hocker"},
}
local screw = Color3.fromRGB(70, 66, 60)

-- Pivot = centre of the ground plane between the four feet; the stool stands on its support.
function StoolView.create(parent: Instance, support: CFrame, batchId: string, stage: string): Model
	local look = LOOKS[stage]
	assert(look, "Unsupported stool stage")
	local model = Instance.new("Model")
	model.Name = stage
	model:SetAttribute("BatchId", batchId)
	model:SetAttribute("Stage", stage)
	local function part(name: string, size: Vector3, center: Vector3, isWood: boolean): BasePart
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size * SCALE
		piece.CFrame = support * CFrame.new(center * SCALE)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.Color = if isWood then look.wood else screw
		piece.Material = if isWood then Enum.Material.Wood else Enum.Material.Metal
		piece:SetAttribute("WoodPiece", isWood)
		piece.Parent = model
		return piece
	end
	local LEG, JOINT = 0.1625, 0.014 -- leg centre offset; smallest exact Roblox part (0.05 studs)
	local seat = part("Sitzplatte", Vector3.new(0.40, 0.025, 0.40), Vector3.new(0, 0.4375, 0), true)
	local index = 0
	for _, x in {-LEG, LEG} do
		for _, z in {-LEG, LEG} do
			index += 1
			part("Bein" .. index, Vector3.new(0.035, 0.425, 0.035), Vector3.new(x, 0.2125, z), true)
		end
	end
	for i, side in {-1, 1} do
		part("Zarge" .. i, Vector3.new(0.29, 0.06, 0.02), Vector3.new(0, 0.33, LEG * side), true)
		part("Zarge" .. (i + 2), Vector3.new(0.02, 0.06, 0.29), Vector3.new(LEG * side, 0.33, 0), true)
	end
	-- Raw joints stay visible: one head per rail end on the outer leg face (HJ2). The greybox head
	-- stands 3 mm proud to avoid coplanar flicker; it stays inside the 0.40 m seat envelope.
	local face = 0.183 - JOINT / 2
	for _, a in {-1, 1} do
		for _, b in {-1, 1} do
			part("Schraube", Vector3.new(JOINT, JOINT, JOINT), Vector3.new(face * a, 0.315, LEG * b), false)
			part("Schraube", Vector3.new(JOINT, JOINT, JOINT), Vector3.new(LEG * b, 0.345, face * a), false)
		end
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "StufenLabel"
	sign.Adornee = seat
	sign.Size = UDim2.fromOffset(160, 38)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 0.9, 0)
	sign.MaxDistance = 18
	sign.Parent = model
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(255, 249, 220)
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Text = look.label
	text.Parent = sign
	model.Parent = parent
	return model
end

return table.freeze(StoolView)
