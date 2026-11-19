--!strict
-- Build the trusted replacement rig and two physical collection points in each upstream yard.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
assert(runService:IsStudio() and not runService:IsRunning(), "Studio Edit only")
local storage = game:GetService("ServerStorage")
local yards = workspace.CityGreybox.DeliveryYards
local sources = {yards.Tischlerei_West, yards.Holzlieferant}
assert(not storage:FindFirstChild("P0607VehicleTemplate"))
for _, yard in sources do assert(not yard:FindFirstChild("VehicleRecovery"), yard.Name) end

local vehicle = workspace.P02Vehicle
assert(vehicle:GetAttribute("VehicleId") == "Quad1")
local template = vehicle:Clone()
template.Name = "P0607VehicleTemplate"
template:SetAttribute("OwnerUserId", nil)
template.Parent = storage
local scale = 25 / 7

for _, yard in sources do
	local entry = yard.LoadZone:GetAttribute("EntryLocal") :: Vector3
	local along = -entry
	local edge = Vector3.new(-along.Z, 0, along.X)
	local root = Instance.new("Folder")
	root.Name = "VehicleRecovery"
	local stands = Instance.new("Folder")
	stands.Name = "Standpoints"
	stands.Parent = root
	local function part(parent: Instance, name: string, offset: Vector3, size: Vector3, color: Color3): Part
		local pad = Instance.new("Part")
		pad.Name = name
		pad.Anchored = true
		pad.CanCollide = false
		pad.CanTouch = false
		pad.CanQuery = false
		pad.Size = size * scale
		pad.CFrame = yard.CFrame * CFrame.new(offset * scale + Vector3.new(0, yard.Size.Y / 2, 0))
		pad.Color = color
		pad.Parent = parent
		return pad
	end
	for i, name in {"SlotA", "SlotB"} do
		local offset = along * (if i == 1 then -0.85 else 0.85)
		local pad = part(root, name, offset + edge * 5.35 + Vector3.new(0, 0.04, 0),
			Vector3.new(0.78, 0.08, 0.68), Color3.fromRGB(72, 119, 163))
		part(stands, name, offset + edge * 4.45 + Vector3.new(0, 0.01, 0),
			Vector3.new(0.28, 0.02, 0.28), Color3.fromRGB(240, 200, 40))
		local point = Instance.new("Attachment")
		point.Name = "Transfer"
		point.Position = Vector3.new(0, pad.Size.Y / 2, 0)
		point.Parent = pad
	end
	root.Parent = yard
end
return {replacement = template.Name, yards = #sources, points = #sources * 2}
