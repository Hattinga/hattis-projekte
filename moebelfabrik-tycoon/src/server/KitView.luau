--!strict
-- Measured greybox representation of one Hocker01 kit, pending the imported art.
local KitView = {}
local SCALE = 25 / 7
local wood = Color3.fromRGB(205, 157, 106)
local tray = Color3.fromRGB(85, 111, 90)

function KitView.create(parent: Instance, support: CFrame, batchId: string): Model
	local model = Instance.new("Model")
	model.Name = "Bausatz"
	model:SetAttribute("BatchId", batchId)
	model:SetAttribute("Stage", "Bausatz")
	local function part(name: string, size: Vector3, center: Vector3, isWood: boolean): BasePart
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size * SCALE
		piece.CFrame = support * CFrame.new(center * SCALE)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.Color = if isWood then wood else tray
		piece.Material = if isWood then Enum.Material.Wood else Enum.Material.SmoothPlastic
		piece:SetAttribute("WoodPiece", isWood)
		piece.Parent = model
		return piece
	end
	-- Roblox clamps part sizes below 0.05 studs; THIN (0.014 m) is the smallest exact greybox wall.
	-- Thin walls sit inside the 0.60 x 0.18 x 0.50 m envelope; wood rests on the tray top at LIFT.
	local THIN, LIFT = 0.014, 0.004
	local edgeX, edgeZ = 0.30 - THIN / 2, 0.25 - THIN / 2
	local base = part("Traeger", Vector3.new(0.60, THIN, 0.50), Vector3.new(0, THIN / 2, 0), false)
	for _, side in {-1, 1} do
		part("Kantenleiste", Vector3.new(THIN, 0.02, 0.50), Vector3.new(edgeX * side, 0.02, 0), false)
		part("Kantenleiste", Vector3.new(0.58, 0.02, THIN), Vector3.new(0, 0.02, edgeZ * side), false)
		for _, z in {-0.19, 0.19} do
			part("Griffstütze", Vector3.new(THIN, 0.14, 0.025), Vector3.new(edgeX * side, 0.10, z), false)
		end
		part("Griff", Vector3.new(THIN, 0.02, 0.405), Vector3.new(edgeX * side, 0.17, 0), false)
	end
	part("Sitzplatte", Vector3.new(0.4, 0.025, 0.4), Vector3.new(-0.085, 0.0225 + LIFT, 0), true)
	for i = 1, 4 do
		part("Bein" .. i, Vector3.new(0.035, 0.035, 0.425), Vector3.new(0.1475 + (i - 1) * 0.04, 0.0275 + LIFT, 0), true)
		part("Zarge" .. i, Vector3.new(0.29, 0.02, 0.06), Vector3.new(-0.08, 0.045 + LIFT, (i - 2.5) * 0.07), true)
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "BausatzLabel"
	sign.Adornee = base
	sign.Size = UDim2.fromOffset(160, 38)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 0.65, 0)
	sign.MaxDistance = 18
	sign.Parent = model
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(255, 249, 220)
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Text = "Bausatz · 9 Teile"
	text.Parent = sign
	model.Parent = parent
	return model
end

return table.freeze(KitView)
