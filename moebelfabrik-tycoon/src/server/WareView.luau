--!strict
-- One greybox view per recipe stage; pivot = centre of the ware's underside on its support.
local Labels = require(script.Parent.Labels)
local KitView = require(script.Parent.KitView)
local StoolView = require(script.Parent.StoolView)
local TableView = require(script.Parent.TableView)
local CartonView = require(script.Parent.CartonView)
local WareView = {}
local SCALE = 25 / 7
local WOOD = Color3.fromRGB(196, 150, 96)
local BAND = Color3.fromRGB(60, 60, 64)

-- DIMENSIONS: wood package 0.60 x 0.15 x 0.45 m with two straps; strap segments stay inside the envelope.
-- TABLE.md: the table package is 0.60 x 0.15 x 0.50 m.
local function package(parent: Instance, support: CFrame, batchId: string, recipeId: string?): Model
	local isTable = recipeId == "Beistelltisch01"
	local depth = if isTable then 0.50 else 0.45
	local model = Instance.new("Model")
	model.Name = "Holzpaket"
	model:SetAttribute("BatchId", batchId)
	model:SetAttribute("Stage", "Holzpaket")
	model:SetAttribute("RecipeId", recipeId or "Hocker01")
	local first: BasePart? = nil
	for _, segment in {{-0.21, 0.18, false}, {-0.105, 0.03, true}, {0, 0.18, false}, {0.105, 0.03, true}, {0.21, 0.18, false}} do
		local centerX, width, strap = segment[1] :: number, segment[2] :: number, segment[3] :: boolean
		local piece = Instance.new("Part")
		piece.Name = if strap then "Band" else "Holz"
		piece.Size = Vector3.new(width, 0.15, depth) * SCALE
		piece.CFrame = support * CFrame.new(Vector3.new(centerX, 0.075, 0) * SCALE)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.Color = if strap then BAND else WOOD
		piece.Material = if strap then Enum.Material.Fabric else Enum.Material.Wood
		piece.Parent = model
		first = first or piece
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "StufenLabel"
	sign.Adornee = first
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
	text.Text = Labels.text(if isTable then "package.table.name" else "package.name")
	text.Parent = sign
	model.Parent = parent
	return model
end

-- `recipeId` names the product of the batch; without it the first recipe is shown.
function WareView.create(parent: Instance, support: CFrame, batchId: string, stage: string, recipeId: string?): Model
	local isTable = recipeId == "Beistelltisch01"
	if stage == "Holzpaket" then return package(parent, support, batchId, recipeId) end
	if stage == "Bausatz" then return KitView.create(parent, support, batchId, recipeId) end
	if stage == "Rohtisch" or (stage == "Fertig" and isTable) then return TableView.create(parent, support, batchId, stage) end
	if stage == "Rohhocker" or stage == "Fertig" then return StoolView.create(parent, support, batchId, stage) end
	if stage == "Karton" then return CartonView.create(parent, support, batchId, recipeId) end
	error("Unknown ware stage")
end

return table.freeze(WareView)
