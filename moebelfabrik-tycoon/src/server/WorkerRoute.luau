--!strict
-- P08-02: the first porter has one measured route between existing handover points.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

type Stop = {stand: BasePart, point: Attachment}
export type Binding = {source: Stop, target: Stop, rest: Vector3}
export type Rig = {model: Model, root: BasePart, humanoid: Humanoid}

local WorkerRoute = {}
WorkerRoute.SOURCE = "Saege.Output"
WorkerRoute.TARGET = "Montage.Input"
local FLAT = Vector3.new(1, 0, 1)
local WIDTH = 2.6
local HEIGHT = 5.8
-- Humanoid:MoveTo stops about one stud from the goal; both handover points remain in reach.
local ARRIVAL = 1.05

local function stop(station: Instance, name: string): Stop
	local stands = assert(station:FindFirstChild("Standpoints"))
	local stand = stands:FindFirstChild(name)
	local pad = station:FindFirstChild(name)
	local point = pad and pad:FindFirstChild("Transfer")
	assert(stand and stand:IsA("BasePart") and point and point:IsA("Attachment"))
	assert((stand.Position - point.WorldPosition).Magnitude < 6, "Worker stop too far from its transfer")
	return {stand = stand, point = point}
end

function WorkerRoute.bind(stations: Instance): Binding
	local source = stop(assert(stations:FindFirstChild("Saege")), "Output")
	local target = stop(assert(stations:FindFirstChild("Montage")), "Input")
	local along = target.stand.Position - source.stand.Position
	assert(math.abs(along.Y) < 0.05 and along.Magnitude > 2 and along.Magnitude < 6, "Worker stops do not share the aisle")
	return {source = source, target = target, rest = source.stand.Position - (along * FLAT).Unit * 8}
end

function WorkerRoute.clear(from: Vector3, to: Vector3, ignore: {Instance}): boolean
	local delta = (to - from) * FLAT
	if delta.Magnitude < 0.01 then return true end
	local center = (from + to) / 2 + Vector3.new(0, HEIGHT / 2 + 0.08, 0)
	local filter = OverlapParams.new()
	filter.FilterType = Enum.RaycastFilterType.Exclude
	filter.FilterDescendantsInstances = ignore
	filter.RespectCanCollide = true
	filter.MaxParts = 1
	local size = Vector3.new(WIDTH, HEIGHT, delta.Magnitude + WIDTH)
	return #workspace:GetPartBoundsInBox(CFrame.lookAt(center, center + delta), size, filter) == 0
end

function WorkerRoute.spawn(binding: Binding, parent: Instance): Rig
	local description = Instance.new("HumanoidDescription")
	description.TorsoColor = Color3.fromRGB(80, 109, 86)
	description.LeftLegColor, description.RightLegColor = Color3.fromRGB(59, 67, 69), Color3.fromRGB(59, 67, 69)
	local model = Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R6)
	description:Destroy()
	local humanoid = assert(model:FindFirstChildOfClass("Humanoid"))
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.Name = "Werkstattmitarbeiter"
	humanoid.DisplayName = "Mitarbeiter"
	humanoid.WalkSpeed = 4
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	local position = binding.rest + Vector3.new(0, 3, 0)
	model:PivotTo(CFrame.lookAt(position, position + (binding.source.stand.Position - binding.rest) * FLAT))
	model.Parent = parent
	root:SetNetworkOwner(nil)
	return {model = model, root = root, humanoid = humanoid}
end

function WorkerRoute.near(rig: Rig, stand: Vector3): boolean
	return rig.model.Parent ~= nil and rig.humanoid.Health > 0
		and ((rig.root.Position - stand) * FLAT).Magnitude <= ARRIVAL
		and math.abs(rig.root.Position.Y - stand.Y) < 5
end

function WorkerRoute.walk(rig: Rig, from: Vector3, to: Vector3): boolean
	if not WorkerRoute.clear(from, to, {rig.model}) then return false end
	if WorkerRoute.near(rig, to) then return true end
	rig.humanoid:MoveTo(to)
	local expires = os.clock() + 4
	while rig.model.Parent and rig.humanoid.Health > 0 and os.clock() < expires do
		RunService.Heartbeat:Wait()
		if WorkerRoute.near(rig, to) then
			rig.humanoid:Move(Vector3.zero)
			return true
		end
	end
	rig.humanoid:Move(Vector3.zero)
	return false
end

return table.freeze(WorkerRoute)
