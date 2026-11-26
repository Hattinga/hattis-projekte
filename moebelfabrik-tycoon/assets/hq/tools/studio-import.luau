--!strict
-- HQ-Serie 1: Reparatur der Importe im Studio-Edit-Datamodel (execute_luau, datamodel_type "Edit").
-- Vorher alle elf Assets aus import-log.json mit insert_asset in game.ServerStorage.HQ1Import einfügen (genau je einmal,
-- niemals erneut hochladen). Das Skript lief am 26.11.2026 in zwei Schritten (Schritt 1: Maßstab, Material, Verankerung;
-- Schritt 2: 180°-Drehung), Ergebnis: Hüllen auf 0,0002 Studs genau, Statuslampe exakt auf der Manifest-Marke.
-- Der Importer liefert GLB mit 1 m = 1 Stud, um 180° um die Hochachse gedreht, alle flachen Materialien grau, unverankert
-- und kollidierend. Texturen (SurfaceAppearance) kommen vollständig an. Der Pivot liegt danach im Ursprung der Blender-Datei
-- (Mitte der Grundfläche auf dem Boden). Regeln: assets/hq/README.md, Manifeste: manifest-goods.json / manifest-stations.json.
local MATERIALS: {[string]: any} = {
	Black = {Color = "#1C1E20", Material = "Rubber"},
	Cardboard = {Textured = true},
	SafetyOrange = {Color = "#D88B3D", Material = "SmoothPlastic"},
	SteelDark = {Color = "#34383C", Material = "SmoothPlastic"},
	WallWhite = {Color = "#E8E0D1", Material = "SmoothPlastic"},
	WoodFinish = {Textured = true},
	WoodRaw = {Textured = true},
	BareSteel = {Color = "#A3A8AD", Material = "Metal"},
	BeltRubber = {Textured = true},
	ClearGuard = {Color = "#D5E4EA", Material = "Glass", Transparency = 0.6},
	SignalRed = {Color = "#B8382E", Material = "SmoothPlastic"},
	SteelGreen = {Color = "#788678", Material = "SmoothPlastic"},
	WoodBench = {Textured = true},
}
-- Hüllen in Blender-Metern aus dem Manifest. Blender (x, y, z) wird zu Roblox (x, z, -y).
local BOUNDS: {[string]: {min: {number}, max: {number}}} = {
	Hocker01_Raw = {min = {-0.2, -0.2, 0}, max = {0.2, 0.2, 0.45}},
	Hocker01_Finish = {min = {-0.2, -0.2, 0}, max = {0.2, 0.2, 0.45}},
	Hocker01_Kit = {min = {-0.3, -0.25, 0}, max = {0.3, 0.25, 0.1788}},
	Holzpaket01 = {min = {-0.2932, -0.2198, 0}, max = {0.2901, 0.2198, 0.1448}},
	Hockerkarton01 = {min = {-0.2295, -0.2295, 0}, max = {0.2295, 0.2295, 0.5092}},
	Saege01 = {min = {-1.18, -0.4, 0}, max = {1.19, 0.4, 1.43}},
	Montagebank01 = {min = {-1.2, -0.4, 0}, max = {1.2, 0.4, 1.43}},
	Finishplatz01 = {min = {-1.18, -0.4, 0}, max = {1.19, 0.3815, 1.44}},
	Packtisch01 = {min = {-1.2, -0.4, 0}, max = {1.19, 0.4, 1.43}},
	Band01_1m = {min = {-0.5, -0.4, 0}, max = {0.5, 0.4, 0.916}},
	Band01_030 = {min = {-0.15, -0.4, 0}, max = {0.15, 0.4, 0.916}},
}
local LAMP = Vector3.new(4.1429, 4.8839, 1.3214) -- StatusLamp-Marker von Finishplatz01 in Studs
local S = 25 / 7
local folder = game:GetService("ServerStorage"):WaitForChild("HQ1Import")
local report: {string} = {}
local order: {string} = {}
for name in BOUNDS do table.insert(order, name) end
table.sort(order)
for _, name in order do
	local b = BOUNDS[name]
	local m = folder:FindFirstChild(name) :: Model
	assert(m and m:GetScale() == 1 and m:GetAttribute("YawFixed") == nil, name .. " fehlt oder wurde schon bearbeitet")
	m:PivotTo(CFrame.new(m:GetPivot().Position)) -- die zufällige Drehung des Imports aus dem Pivot nehmen
	m:ScaleTo(S) -- 25/7 Studs je Meter genau einmal
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false -- Sichtschicht
			if d:IsA("MeshPart") then
				local token = d.Name:match(".*__(.+)$")
				local spec = if token then MATERIALS[token] else nil
				assert(spec, d.Name .. ": unbekanntes Material")
				if spec.Textured then
					local sa = d:FindFirstChildWhichIsA("SurfaceAppearance")
					assert(sa and sa.ColorMap ~= "", d.Name .. " hat die Textur verloren")
				else
					d.Color = Color3.fromHex(spec.Color)
					d.Material = (Enum.Material :: any)[spec.Material]
					d.Transparency = spec.Transparency or 0
				end
			end
		end
	end
	m:PivotTo(CFrame.Angles(0, math.pi, 0)) -- GLB kommt um 180° gedreht an
	m.WorldPivot = CFrame.new(0, 0, 0)
	m:SetAttribute("YawFixed", true)
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local h = d.Size / 2
			for _, sx in {-1, 1} do for _, sy in {-1, 1} do for _, sz in {-1, 1} do
				local p = d.CFrame:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
				minV = Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
				maxV = Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
			end end end
		end
	end
	local a = (minV - Vector3.new(b.min[1], b.min[3], -b.max[2]) * S):Abs()
	local c = (maxV - Vector3.new(b.max[1], b.max[3], -b.min[2]) * S):Abs()
	local drift = math.max(a.X, a.Y, a.Z, c.X, c.Y, c.Z)
	table.insert(report, string.format("%s: Abweichung der Hülle %.4f Studs %s", name, drift, if drift <= 0.02 then "OK" else "ABWEICHUNG"))
end
local lamp: BasePart? = nil
for _, d in folder.Finishplatz01:GetDescendants() do if d.Name == "Finishplatz01__StatusLamp__WallWhite" then lamp = d :: BasePart end end
table.insert(report, string.format("Statuslampe: Abstand zur Marke %.3f Studs", (assert(lamp).Position - LAMP).Magnitude))
game:GetService("ChangeHistoryService"):SetWaypoint("HQ1 import repaired")
return table.concat(report, "\n")
