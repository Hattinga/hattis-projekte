--!strict
-- Measured greybox of one closed Hocker01 carton (DIMENSIONS: 0.46 x 0.51 x 0.46 m), pending the imported art.
local Labels = require(script.Parent.Labels)
local CartonView = {}
local SCALE = 25 / 7
local CARD = Color3.fromRGB(190, 150, 100)
local INK = Color3.fromRGB(45, 38, 30)

local function label(parent: Instance, text: string, position: UDim2, size: UDim2, localize: boolean): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = position
	item.Size = size
	item.TextColor3 = INK
	item.TextScaled = true
	item.Font = Enum.Font.GothamBold
	item.AutoLocalize = localize
	item.Text = text
	item.Parent = parent
	return item
end

local function bar(parent: Instance, position: UDim2, size: UDim2)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = INK
	frame.BorderSizePixel = 0
	frame.Position = position
	frame.Size = size
	frame.Parent = parent
end

-- Pivot = centre of the carton's underside; the carton rests on its support.
function CartonView.create(parent: Instance, support: CFrame, batchId: string): Model
	local model = Instance.new("Model")
	model.Name = "Karton"
	model:SetAttribute("BatchId", batchId)
	model:SetAttribute("Stage", "Karton")
	local function part(name: string, size: Vector3, center: Vector3, color: Color3): BasePart
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size * SCALE
		piece.CFrame = support * CFrame.new(center * SCALE)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.Color = color
		piece.Material = Enum.Material.Cardboard
		piece.Parent = model
		return piece
	end
	-- Tape (0.014 m, smallest exact part) sits inside the 0.51 m envelope on the closed lid.
	local body = part("Karton", Vector3.new(0.46, 0.496, 0.46), Vector3.new(0, 0.248, 0), CARD)
	part("Klebeband", Vector3.new(0.46, 0.014, 0.08), Vector3.new(0, 0.503, 0), CARD:Lerp(Color3.new(1, 1, 1), 0.35))
	for _, face in {Enum.NormalId.Front, Enum.NormalId.Back} do
		local sheet = Instance.new("SurfaceGui")
		sheet.Name = "Aufdruck" .. face.Name
		sheet.Face = face
		sheet.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sheet.PixelsPerStud = 120
		sheet.LightInfluence = 1
		sheet.Adornee = body
		sheet.Parent = body
		-- Language-neutral stool symbol: seat, two legs, one rail.
		bar(sheet, UDim2.fromScale(0.30, 0.12), UDim2.fromScale(0.40, 0.06))
		bar(sheet, UDim2.fromScale(0.34, 0.18), UDim2.fromScale(0.05, 0.30))
		bar(sheet, UDim2.fromScale(0.61, 0.18), UDim2.fromScale(0.05, 0.30))
		bar(sheet, UDim2.fromScale(0.34, 0.33), UDim2.fromScale(0.32, 0.04))
		label(sheet, Labels.text("carton.count"), UDim2.fromScale(0.08, 0.52), UDim2.fromScale(0.84, 0.16), true)
		label(sheet, Labels.text("carton.batch"), UDim2.fromScale(0.08, 0.72), UDim2.fromScale(0.84, 0.08), true)
		label(sheet, batchId, UDim2.fromScale(0.08, 0.81), UDim2.fromScale(0.84, 0.08), false)
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "StufenLabel"
	sign.Adornee = body
	sign.Size = UDim2.fromOffset(160, 38)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 1.3, 0)
	sign.MaxDistance = 18
	sign.Parent = model
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(255, 249, 220)
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Text = Labels.text("carton.name")
	text.Parent = sign
	model.Parent = parent
	return model
end

return table.freeze(CartonView)
