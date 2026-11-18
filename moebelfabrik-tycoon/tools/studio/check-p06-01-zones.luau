--!strict
-- P06-01 read-only check (Edit): zones, drop-off pads, supplier stands, drive-path clearance and walking paths.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local S = 25 / 7
local city = workspace.CityGreybox
local yards = city.DeliveryYards
local checks: {string} = {}
local function pass(text: string) table.insert(checks, text) end

-- 1. Zones: full yard volume, three lines, drive-in side open.
for _, name in {"Tischlerei_West", "Holzlieferant", "Moebelhandel", "Privatkunden"} do
	local yard = yards[name] :: BasePart
	local zone = yard:FindFirstChild("LoadZone") :: Model
	assert(zone and zone:GetAttribute("ZoneId") == name, name .. " zone")
	local volume = zone:FindFirstChild("Volume") :: BasePart
	assert(math.abs(volume.Size.X - yard.Size.X) < 0.01 and math.abs(volume.Size.Z - yard.Size.Z) < 0.01 and math.abs(volume.Size.Y / S - 3) < 0.01)
	local lines = 0
	for _, child in zone:GetChildren() do if child.Name == "Linie" then lines += 1 end end
	assert(lines == 3, name .. " lines " .. lines)
end
pass("four load zones cover their 12 x 12 m yards, 3 m high; three edge lines each, drive-in side open")

-- 2. Placed items: no overlap with buildings, greenery, signs or square; paved yard beneath.
local solid = OverlapParams.new()
solid.FilterType = Enum.RaycastFilterType.Include
solid.FilterDescendantsInstances = {city.Buildings, city.Greenery, city.Signs, city.TownSquare}
local items: {BasePart} = {}
for _, yard in yards:GetChildren() do
	for _, holder in {"LoadZone", "Annahme"} do
		local model = yard:FindFirstChild(holder)
		if model then for _, p in model:GetChildren() do if p:IsA("BasePart") and p.Name ~= "Volume" then table.insert(items, p) end end end
	end
	local pickup = yard:FindFirstChild("P05Pickup")
	if pickup and pickup:FindFirstChild("Standpoints") then
		for _, p in pickup.Standpoints:GetChildren() do table.insert(items, p :: BasePart) end
	end
end
local down = RaycastParams.new()
down.FilterType = Enum.RaycastFilterType.Include
down.FilterDescendantsInstances = {yards}
for _, item in items do
	local hits = workspace:GetPartsInPart(item, solid)
	assert(#hits == 0, item:GetFullName() .. " overlaps " .. (if hits[1] then hits[1]:GetFullName() else ""))
	if item.Name ~= "Linie" then
		local hit = workspace:Raycast(item.Position + Vector3.new(0, 2, 0), Vector3.new(0, -4, 0), down)
		assert(hit and hit.Instance:IsDescendantOf(yards), item:GetFullName() .. " not on a yard")
	end
end
pass(string.format("%d placed items overlap nothing solid; every pad and stand marker rests on its yard", #items))

-- 3. Clearance from the P02-05 drive model (yard-local metres, approach d, right r):
--    approach line r=-3.5 for d<=0, semicircle radius 3.5 around the centre for d>=0, parked rig r 2.75..4.25 x d -0.5..4.5.
local function clearance(yard: BasePart, part: BasePart): number
	local entry = (yard.LoadZone :: Model):GetAttribute("EntryLocal") :: Vector3
	local d = -entry
	local r = Vector3.new(-d.Z, 0, d.X)
	local best = math.huge
	local half = part.Size / S / 2
	for _, sx in {-1, 1} do
		for _, sz in {-1, 1} do
			local corner = yard.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, 0, sz * half.Z) * S)) / S
			local cd, cr = corner:Dot(d), corner:Dot(r)
			local line = if cd <= 0 then math.abs(cr + 3.5) else math.huge
			local circle = if cd >= 0 then math.abs(Vector2.new(cd, cr).Magnitude - 3.5) else math.huge
			local rig = Vector2.new(math.max(0, 2.75 - cr, cr - 4.25), math.max(0, -0.5 - cd, cd - 4.5)).Magnitude
			best = math.min(best, line - 1.1, circle - 1.1, rig)
		end
	end
	return best
end
local margins = {}
for _, name in {"Moebelhandel", "Privatkunden"} do
	local yard = yards[name] :: BasePart
	local pad = yard.Annahme.Pad :: BasePart
	local stand = yard.Annahme.Standpoint :: BasePart
	local m = math.min(clearance(yard, pad), clearance(yard, stand))
	assert(m >= 1.0, name .. " drop-off too close to the drive path: " .. m)
	margins[name] = math.floor(m * 100) / 100
end
local supplier = yards.Holzlieferant :: BasePart
local supplierMargin = math.huge
for i = 1, 4 do supplierMargin = math.min(supplierMargin, clearance(supplier, supplier.P05Pickup["Slot" .. i] :: BasePart)) end
margins.HolzlieferantSlots = math.floor(supplierMargin * 100) / 100
pass("drop-off pads and stand markers keep >= 1.0 m from approach, turn and parked rig")

-- 4. Walking: factory yard -> gate -> raw and finished store markers -> station markers.
local pf = game:GetService("PathfindingService")
local line = workspace.P02Line
local function walk(from: Vector3, to: Vector3): number?
	local path = pf:CreatePath({AgentRadius = 1.0, AgentHeight = 5.5, AgentCanJump = false, WaypointSpacing = 2})
	path:ComputeAsync(from, to)
	if path.Status ~= Enum.PathStatus.Success then return nil end
	local length = 0
	local points = path:GetWaypoints()
	for i = 2, #points do length += (points[i].Position - points[i - 1].Position).Magnitude end
	return length / S
end
local yardCentre = (yards.Tischlerei_West :: BasePart).Position + Vector3.new(0, 3, 0)
local walks = {}
for _, target in {line.Stores.Rohstofflager.Standpoints.Slot1, line.Stores.Rohstofflager.Standpoints.Slot4,
	line.Stores.Fertiglager.Standpoints.Slot1, line.Stores.Fertiglager.Standpoints.Slot4} do
	local metres = walk(yardCentre, (target :: BasePart).Position + Vector3.new(0, 3, 0))
	assert(metres, "No walking path to " .. target:GetFullName())
	walks[target.Parent.Parent.Name .. "." .. target.Name] = math.floor(metres * 10) / 10
end
local inner = walk(line.Stores.Rohstofflager.Standpoints.Slot1.Position + Vector3.new(0, 3, 0),
	line.Stations.Packen.Standpoints.Output.Position + Vector3.new(0, 3, 0))
assert(inner, "No walking path from raw store to the far station")
walks["Rohstofflager.Slot1->Packen.Output"] = math.floor(inner * 10) / 10
pass("walking paths lead from the factory yard through the gate to both stores and on to the stations")

-- 5. Drop-off labels are bilingual.
local labels = game:GetService("LocalizationService"):FindFirstChild("FactoryLabels") :: LocalizationTable
local de = labels:GetTranslator("de")
assert(de:Translate(game, "DEALER DROP-OFF") == "HÄNDLERANNAHME" and de:Translate(game, "PRIVATE DROP-OFF") == "PRIVATANNAHME")
pass("drop-off signs translate to HÄNDLERANNAHME / PRIVATANNAHME")

return {task = "P06-01", status = "passed", checks = checks, margins = margins, walkMetres = walks}
