--!strict
-- P09-02: a fixed belt bridge joins the existing saw and assembly transfer pads.
export type Binding = {
	source: Attachment, target: Attachment, bridge: CFrame, buffer: CFrame, length: number, depth: number,
}
export type Fixture = {model: Model, input: Attachment, output: Attachment, buffer: Attachment}

local BeltRoute = {}
local SCALE = 25 / 7
local KIT_LENGTH, KIT_DEPTH = 0.60 * SCALE, 0.50 * SCALE
local EPSILON = 0.003
local TREAD_HEIGHT, RAIL_WIDTH = 0.06, 0.12
local STEEL = Color3.fromRGB(88, 102, 109)
local HOUSING = Color3.fromRGB(51, 61, 65)
local TREADS = {Color3.fromRGB(31, 35, 36), Color3.fromRGB(43, 47, 48)}

local function transfer(stations: Instance, stationName: string, padName: string): (Attachment, BasePart)
	local station = assert(stations:FindFirstChild(stationName), "Missing belt station " .. stationName)
	local pad = station:FindFirstChild(padName)
	assert(pad and pad:IsA("BasePart"), "Missing belt pad " .. padName)
	local point = pad:FindFirstChild("Transfer")
	assert(point and point:IsA("Attachment"), "Missing belt Transfer " .. stationName)
	assert((pad.CFrame:PointToObjectSpace(point.WorldPosition) - Vector3.new(0, pad.Size.Y / 2, 0)).Magnitude < EPSILON,
		"Belt Transfer must sit at the pad surface center")
	assert(pad.Size.X >= KIT_LENGTH and pad.Size.Z >= KIT_DEPTH, "Belt pad does not support the full kit")
	return point, pad
end

function BeltRoute.bind(stations: Instance): Binding
	local source, sourcePad = transfer(stations, "Saege", "Output")
	local target, targetPad = transfer(stations, "Montage", "Input")
	local first, last = source.WorldCFrame, target.WorldCFrame
	local delta = last.Position - first.Position
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local distance = horizontal.Magnitude
	assert(distance > EPSILON and math.abs(delta.Y) < EPSILON, "Belt endpoints must be on the same level")
	local along = horizontal / distance
	assert(math.abs(along:Dot(sourcePad.CFrame.RightVector)) > 0.9999
		and math.abs(along:Dot(targetPad.CFrame.RightVector)) > 0.9999
		and sourcePad.CFrame.UpVector.Y > 0.9999 and targetPad.CFrame.UpVector.Y > 0.9999
		and first.RightVector:Dot(last.RightVector) > 0.9999
		and math.abs(along:Dot(first.RightVector)) > 0.9999
		and first.UpVector.Y > 0.9999 and last.UpVector.Y > 0.9999, "Belt pads and transfer frames must share a straight row")
	local edgeFrom = sourcePad.Size.X / 2
	local edgeTo = distance - targetPad.Size.X / 2
	local length = edgeTo - edgeFrom
	assert(length >= 0.25, "Insufficient gap between belt pads")

	-- The held kit rests partly on the reserved source pad and partly on the bridge.
	-- Keeping it clear of the target pad allows another kit to wait there.
	local bufferOffset = edgeFrom - 0.15
	local bufferEnd = bufferOffset + KIT_LENGTH / 2
	assert(bufferOffset > 0 and bufferEnd > edgeFrom and bufferEnd + EPSILON < edgeTo
		and distance - bufferOffset >= KIT_LENGTH + EPSILON, "No clear belt buffer position")
	local middle = first.Position + along * ((edgeFrom + edgeTo) / 2)
	return {
		source = source, target = target, bridge = CFrame.fromMatrix(middle, along, Vector3.yAxis),
		buffer = first + along * bufferOffset, length = length, depth = math.min(sourcePad.Size.Z, targetPad.Size.Z),
	}
end

function BeltRoute.spawn(binding: Binding, parent: Instance): Fixture
	local model = Instance.new("Model")
	model.Name = "Foerderband"
	local length, depth = binding.length, binding.depth
	local frame = binding.bridge
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Anchored = true
		item.CanCollide, item.CanTouch, item.CanQuery = false, false, false
		item.Size, item.CFrame = size, frame * CFrame.new(offset)
		item.Color, item.Material = color, material
		item.Parent = model
		return item
	end
	-- The station bodies project slightly beyond their pads, so recess the lower frame from both ends.
	local casing = part("Bandrahmen", Vector3.new(length * 0.60, 0.22, depth),
		Vector3.new(0, -(TREAD_HEIGHT + 0.11), 0), HOUSING, Enum.Material.Metal)
	model.PrimaryPart = casing
	for _, side in {-1, 1} do
		part("Seitenleiste", Vector3.new(length, TREAD_HEIGHT, RAIL_WIDTH),
			Vector3.new(0, -TREAD_HEIGHT / 2, side * (depth - RAIL_WIDTH) / 2), STEEL, Enum.Material.Metal)
		part("Puffermarke", Vector3.new(0.15, 0.05, RAIL_WIDTH),
			Vector3.new(-length / 2 + 0.075, 0.025, side * (depth - RAIL_WIDTH) / 2),
			Color3.fromRGB(224, 175, 74), Enum.Material.SmoothPlastic)
	end
	for i = 1, 4 do
		part("Bandglied" .. i, Vector3.new(length / 4, TREAD_HEIGHT, depth - 2 * RAIL_WIDTH),
			Vector3.new((i - 2.5) * length / 4, -TREAD_HEIGHT / 2, 0), TREADS[2 - i % 2], Enum.Material.SmoothPlastic)
	end
	local function attachment(name: string, worldFrame: CFrame): Attachment
		local point = Instance.new("Attachment")
		point.Name = name
		point.CFrame = casing.CFrame:ToObjectSpace(worldFrame)
		point.Parent = casing
		return point
	end
	local input = attachment("Input", binding.source.WorldCFrame)
	local output = attachment("Output", binding.target.WorldCFrame)
	local buffer = attachment("Buffer", binding.buffer)
	model.Parent = parent
	return {model = model, input = input, output = output, buffer = buffer}
end

return table.freeze(BeltRoute)
