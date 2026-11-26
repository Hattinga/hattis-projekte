--!strict
-- P10-02: measured greybox of one assembled Beistelltisch01 (TABLE.md), pending the imported art.
-- Hull 0.42 x 0.48 x 0.42 m; pivot = centre of the ground plane between the four feet.
local Labels = require(script.Parent.Labels)
local TableView = {}
local SCALE = 25 / 7
-- Raw: light matte wood, joints visible. Finish: the same table in the warmer tone of the finished stool.
local LOOKS = {
	Rohtisch = {wood = Color3.fromRGB(226, 196, 156), label = "table.raw.name"},
	Fertig = {wood = Color3.fromRGB(168, 106, 62), label = "table.finished.name"},
}
local screw = Color3.fromRGB(70, 66, 60)

function TableView.create(parent: Instance, support: CFrame, batchId: string, stage: string): Model
	local look = LOOKS[stage]
	assert(look, "Unsupported table stage")
	local model = Instance.new("Model")
	model.Name = if stage == "Fertig" then "FertigTisch" else stage
	model:SetAttribute("BatchId", batchId)
	model:SetAttribute("Stage", stage)
	model:SetAttribute("RecipeId", "Beistelltisch01")
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
	local LEG, JOINT = 0.15, 0.014 -- leg centre offset; smallest exact Roblox part (0.05 studs)
	local top = part("Platte", Vector3.new(0.42, 0.025, 0.42), Vector3.new(0, 0.4675, 0), true)
	local index = 0
	for _, x in {-LEG, LEG} do
		for _, z in {-LEG, LEG} do
			index += 1
			part("Bein" .. index, Vector3.new(0.03, 0.455, 0.03), Vector3.new(x, 0.2275, z), true)
		end
	end
	-- Rails flush with the outer leg faces; their ends meet the inner leg faces 0.27 m apart.
	for i, side in {-1, 1} do
		part("Zarge" .. i, Vector3.new(0.27, 0.07, 0.02), Vector3.new(0, 0.42, 0.155 * side), true)
		part("Zarge" .. (i + 2), Vector3.new(0.02, 0.07, 0.27), Vector3.new(0.155 * side, 0.42, 0), true)
	end
	-- Lower shelf: a cross of two boards leaves the corner notches for the legs (0.33 m outer, 0.03 m notches).
	part("Ablageboden", Vector3.new(0.33, 0.02, 0.27), Vector3.new(0, 0.18, 0), true)
	part("Ablageboden", Vector3.new(0.27, 0.02, 0.33), Vector3.new(0, 0.18, 0), true)
	-- Raw joints stay visible: one head per rail end on the outer leg face, inside the 0.42 m plate envelope.
	local face = 0.165 + JOINT / 2
	for _, a in {-1, 1} do
		for _, b in {-1, 1} do
			part("Schraube", Vector3.new(JOINT, JOINT, JOINT), Vector3.new(face * a, 0.405, 0.155 * b), false)
			part("Schraube", Vector3.new(JOINT, JOINT, JOINT), Vector3.new(0.155 * b, 0.435, face * a), false)
		end
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "StufenLabel"
	sign.Adornee = top
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
	text.Text = Labels.text(look.label)
	text.Parent = sign
	model.Parent = parent
	return model
end

return table.freeze(TableView)
