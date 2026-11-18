--!strict
-- P06-01 builder (Edit): loading zones on the four test yards, dealer/private drop-off pads, supplier stand markers.
-- Aborts if already built. Yard geometry and roads stay unchanged.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and not rs:IsRunning(), "Edit only")
local S = 25 / 7
local city = workspace.CityGreybox
local yards = city.DeliveryYards
assert(not city:GetAttribute("P06Zones"), "P06-01 zones already built")
local origin = city:GetAttribute("OriginStuds") :: Vector3
local YELLOW = Color3.fromRGB(240, 200, 40)
local TEST = {
	{yard = "Tischlerei_West", role = "Workshop"},
	{yard = "Holzlieferant", role = "Supplier"},
	{yard = "Moebelhandel", role = "Dealer", dropoff = "dropoff.dealer", text = "DEALER DROP-OFF"},
	{yard = "Privatkunden", role = "Private", dropoff = "dropoff.private", text = "PRIVATE DROP-OFF"},
}

-- Road entry: the access segment of the road graph ends at the yard centre; its other end gives the drive-in side.
local function entryDirection(yard: BasePart): Vector3
	local centre = (yard.Position - origin) / S
	local flat = Vector3.new(centre.X, 0, centre.Z)
	local toward: Vector3? = nil
	for _, segment in city.RoadSegments:GetChildren() do
		local a, b = segment:GetAttribute("A") :: Vector3, segment:GetAttribute("B") :: Vector3
		if a and b then
			local fa, fb = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
			if (fa - flat).Magnitude < 1 then toward = fb - flat elseif (fb - flat).Magnitude < 1 then toward = fa - flat end
			if toward then break end
		end
	end
	assert(toward and toward.Magnitude > 1, "No access segment ends at yard " .. yard.Name)
	-- snap to the yard's dominant axis so pads sit on an edge
	local localDir = yard.CFrame:VectorToObjectSpace(toward)
	return if math.abs(localDir.X) > math.abs(localDir.Z) then Vector3.new(math.sign(localDir.X), 0, 0) else Vector3.new(0, 0, math.sign(localDir.Z))
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size * S
	item.CFrame = cframe
	item.Anchored = true
	item.CanCollide = false
	item.CanTouch = false
	item.CanQuery = false
	item.Color = color
	item.Material = Enum.Material.SmoothPlastic
	item.Transparency = transparency
	item.Parent = parent
	return item
end

local report = {}
for _, spec in TEST do
	local yard = yards[spec.yard] :: BasePart
	local top = yard.Position.Y + yard.Size.Y / 2
	local base = CFrame.new(yard.Position.X, top, yard.Position.Z) * (yard.CFrame - yard.CFrame.Position)
	local entry = entryDirection(yard)
	local zone = Instance.new("Model")
	zone.Name = "LoadZone"
	zone:SetAttribute("Kind", "LoadZone")
	zone:SetAttribute("Role", spec.role)
	zone:SetAttribute("ZoneId", spec.yard)
	zone:SetAttribute("EntryLocal", entry)
	-- Volume used by later zone checks: the full yard footprint, 3 m high.
	local volume = part(zone, "Volume", Vector3.new(yard.Size.X / S, 3, yard.Size.Z / S), base * CFrame.new(0, 1.5 * S, 0), YELLOW, 1)
	volume:SetAttribute("Kind", "LoadZoneVolume")
	local half = Vector3.new(yard.Size.X / S / 2 - 0.30, 0, yard.Size.Z / S / 2 - 0.30)
	for _, edge in {{Vector3.new(half.X, 0, 0), Vector3.new(0.10, 0.014, half.Z * 2)}, {Vector3.new(-half.X, 0, 0), Vector3.new(0.10, 0.014, half.Z * 2)},
		{Vector3.new(0, 0, half.Z), Vector3.new(half.X * 2, 0.014, 0.10)}, {Vector3.new(0, 0, -half.Z), Vector3.new(half.X * 2, 0.014, 0.10)}} do
		local offset, size = edge[1] :: Vector3, edge[2] :: Vector3
		-- the entry edge stays open: no line across the drive-in side
		if offset.Magnitude > 0 and (offset.Unit - entry).Magnitude < 0.01 then continue end
		part(zone, "Linie", size, base * CFrame.new(offset * S + Vector3.new(0, 0.007 * S, 0)), YELLOW, 0)
	end
	zone.Parent = yard
	local row: any = {yard = spec.yard, entry = tostring(entry)}
	if spec.dropoff then
		-- P02-05 turn: approach along the left line, 3.5 m semicircle around the centre (+~1 m hull),
		-- parking 3.5 m right of the approach with the trailer trailing toward the far side.
		-- The far-left corner is >= 2.4 m from every drive path and parked rig (same side as the supplier pickup).
		local approach = -entry
		local right = Vector3.new(approach.Z, 0, -approach.X) * -1
		local corner = (approach - right) * 5.0
		local acceptance = Instance.new("Model")
		acceptance.Name = "Annahme"
		acceptance:SetAttribute("Role", spec.role)
		acceptance:SetAttribute("Capacity", 1)
		acceptance:SetAttribute("AcceptedStage", "Karton")
		local padCf = base * CFrame.new(corner * S + Vector3.new(0, 0.04 * S, 0))
		local pad = part(acceptance, "Pad", Vector3.new(0.80, 0.08, 0.65), padCf, Color3.fromRGB(70, 130, 180), 0)
		pad:SetAttribute("Capacity", 1)
		local transfer = Instance.new("Attachment")
		transfer.Name = "Transfer"
		transfer.Position = Vector3.new(0, pad.Size.Y / 2, 0)
		transfer.Parent = pad
		local standAt = corner - corner.Unit * 0.9
		local stand = part(acceptance, "Standpoint", Vector3.new(0.30, 0.014, 0.30), base * CFrame.new(standAt * S + Vector3.new(0, 0.007 * S, 0)), YELLOW, 0.3)
		stand.Name = "Standpoint"
		local sign = Instance.new("SurfaceGui")
		sign.Face = Enum.NormalId.Top
		sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sign.PixelsPerStud = 60
		sign.Parent = pad
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Text = spec.text :: string
		text.Parent = sign
		acceptance.Parent = yard
		row.dropoff = string.format("pad %.2f m from centre", (pad.Position - yard.Position).Magnitude / S)
	end
	if spec.role == "Supplier" then
		local pickup = yard:FindFirstChild("P05Pickup")
		assert(pickup and not pickup:FindFirstChild("Standpoints"), "Supplier pickup missing or already has stand markers")
		local stands = Instance.new("Folder")
		stands.Name = "Standpoints"
		local first = pickup.Slot1 :: BasePart
		local rel = yard.CFrame:VectorToObjectSpace(first.Position - yard.Position)
		local edge = if math.abs(rel.X) > math.abs(rel.Z) then Vector3.new(math.sign(rel.X), 0, 0) else Vector3.new(0, 0, math.sign(rel.Z))
		-- P05-02 pads sat at 4.90 m, 3 cm inside the conservative drive-in hull; move them 0.4 m outward.
		local shift = yard.CFrame:VectorToWorldSpace(edge * 0.4 * S)
		for i = 1, 4 do
			local slot = pickup["Slot" .. i] :: BasePart
			slot.CFrame += shift
			local p = yard.CFrame:PointToObjectSpace(slot.Position)
			local along = p - edge * edge:Dot(p)
			part(stands, "Slot" .. i, Vector3.new(0.30, 0.014, 0.30),
				base * CFrame.new(along + edge * 4.40 * S + Vector3.new(0, 0.007 * S, 0) - Vector3.new(0, along.Y, 0)), YELLOW, 0.3)
		end
		pickup:SetAttribute("P06Shift", "0.4 m outward for drive clearance")
		stands.Parent = pickup
		row.supplierEdge = tostring(edge)
		row.supplierNotOnEntry = (edge - entry).Magnitude > 0.01
	end
	table.insert(report, row)
end
city:SetAttribute("P06Zones", 1)
return report
