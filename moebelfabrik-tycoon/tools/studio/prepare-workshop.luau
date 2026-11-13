local model = workspace:FindFirstChild("FableWorkshop")
assert(model and model:IsA("Model"), "Imported workshop missing")
assert(not model:GetAttribute("ImportPrepared"), "Workshop is already prepared")
local materials = {["Plinth_Foundation"]={{0.603921573,0.588235292,0.552941176,1,0,"WS_concrete",0.949999988079071},{0.654901957,0.639215691,0.603921573,1,0,"WS_concrete_b",0.949999988079071}},
["Wall_Front"]={{0.909803912,0.878431359,0.819607827,1,0,"WS_wall_white",0.8999999761581421},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.878431359,0.823529417,0.721568618,1,0,"WS_lining_ply",0.8500000238418579}},
["Wall_Back"]={{0.909803912,0.878431359,0.819607827,1,0,"WS_wall_white",0.8999999761581421},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.878431359,0.823529417,0.721568618,1,0,"WS_lining_ply",0.8500000238418579}},
["Wall_Left"]={{0.909803912,0.878431359,0.819607827,1,0,"WS_wall_white",0.8999999761581421},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.878431359,0.823529417,0.721568618,1,0,"WS_lining_ply",0.8500000238418579}},
["Wall_Right"]={{0.909803912,0.878431359,0.819607827,1,0,"WS_wall_white",0.8999999761581421},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.878431359,0.823529417,0.721568618,1,0,"WS_lining_ply",0.8500000238418579}},
["WallPlate_Bearing_L"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579}},
["WallPlate_Bearing_R"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579}},
["Cladding_Battens"]={{0.864313724,0.834509795,0.778627453,1,0,"WS_wall_white_batten",0.8999999761581421}},
["Trim_BaseBoard"]={{0.399999997,0.44666667,0.399999997,1,0,"WS_green_dark",0.800000011920929}},
["Trim_CornerBoards"]={{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929}},
["Trim_GableFrieze"]={{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929}},
["Wall_LiningStrips"]={{0.808156856,0.757647045,0.663843142,1,0,"WS_lining_strip",0.8500000238418579}},
["Door_Frame_Threshold"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929}},
["Door_Casing_HingePlates"]={{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579}},
["Door_Leaf_L"]={{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929},{0.508235302,0.567529406,0.508235302,1,0,"WS_green_light",0.800000011920929},{0.399999997,0.44666667,0.399999997,1,0,"WS_green_dark",0.800000011920929},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579}},
["Door_Leaf_R"]={{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929},{0.508235302,0.567529406,0.508235302,1,0,"WS_green_light",0.800000011920929},{0.399999997,0.44666667,0.399999997,1,0,"WS_green_dark",0.800000011920929},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579}},
["Window_1"]={{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929},{0.399999997,0.44666667,0.399999997,1,0,"WS_green_dark",0.800000011920929},{0.70588236,0.776470592,0.760784317,0.3499999940395355,0,"WS_glass",0.11999999731779099},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579}},
["Window_2"]={{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929},{0.399999997,0.44666667,0.399999997,1,0,"WS_green_dark",0.800000011920929},{0.70588236,0.776470592,0.760784317,0.3499999940395355,0,"WS_glass",0.11999999731779099},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579}},
["Truss_TieBeams"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579}},
["Floor_EntryConcrete"]={{0.654901957,0.639215691,0.603921573,1,0,"WS_concrete_b",0.949999988079071},{0.603921573,0.588235292,0.552941176,1,0,"WS_concrete",0.949999988079071}},
["Floor_TransitionStrip"]={{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579}},
["Floor_Planks"]={{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929}},
["Floor_BenchMat"]={{0.172549018,0.184313727,0.192156866,1,0,"WS_rubber",0.8999999761581421}},
["Workbench"]={{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.164705884,0.141176469,0.125490196,1,0,"WS_dark_recess",0.949999988079071},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.525333339,0.399999997,0.266666667,1,0,"WS_wood_endgrain",0.8999999761581421}},
["Workbench_Vise"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.556862753,0.580392144,0.599999995,1,0.6000000238418579,"WS_tool_steel",0.44999998807907104},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929}},
["Workbench_Tools"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.556862753,0.580392144,0.599999995,1,0.6000000238418579,"WS_tool_steel",0.44999998807907104},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929}},
["ToolWall"]={{0.878431359,0.823529417,0.721568618,1,0,"WS_lining_ply",0.8500000238418579},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.556862753,0.580392144,0.599999995,1,0.6000000238418579,"WS_tool_steel",0.44999998807907104},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.525333339,0.399999997,0.266666667,1,0,"WS_wood_endgrain",0.8999999761581421},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579},{0.909803912,0.878431359,0.819607827,1,0,"WS_wall_white",0.8999999761581421}},
["Shelf_Open"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.525333339,0.399999997,0.266666667,1,0,"WS_wood_endgrain",0.8999999761581421},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579}},
["Shelf_Items"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.164705884,0.141176469,0.125490196,1,0,"WS_dark_recess",0.949999988079071},{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929},{0.399999997,0.44666667,0.399999997,1,0,"WS_green_dark",0.800000011920929},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.556862753,0.580392144,0.599999995,1,0.6000000238418579,"WS_tool_steel",0.44999998807907104},{0.909803912,0.878431359,0.819607827,1,0,"WS_wall_white",0.8999999761581421},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.70588236,0.776470592,0.760784317,0.3499999940395355,0,"WS_glass",0.11999999731779099},{0.508235302,0.567529406,0.508235302,1,0,"WS_green_light",0.800000011920929},{0.864313724,0.834509795,0.778627453,1,0,"WS_wall_white_batten",0.8999999761581421}},
["Lumber_Rack"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579}},
["Lumber_Stock"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.525333339,0.399999997,0.266666667,1,0,"WS_wood_endgrain",0.8999999761581421},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426}},
["Lumber_LeaningBoards"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579}},
["Sawhorses_Workpiece"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579},{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929}},
["Stool_Bucket"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.525333339,0.399999997,0.266666667,1,0,"WS_wood_endgrain",0.8999999761581421},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579},{0.556862753,0.580392144,0.599999995,1,0.6000000238418579,"WS_tool_steel",0.44999998807907104}},
["Lamp_Pendants"]={{0.172549018,0.184313727,0.192156866,1,0,"WS_rubber",0.8999999761581421},{0.399999997,0.44666667,0.399999997,1,0,"WS_green_dark",0.800000011920929},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.945098041,0.913725492,0.823529417,1,0,"WS_bulb",0.5}},
["Roof_Rafters"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426}},
["Roof_RidgeBeam"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579}},
["Roof_KingPosts_Struts"]={{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579}},
["Roof_EaveBlocking"]={{0.648941174,0.494117641,0.32941176,1,0,"WS_wood_dark",0.8500000238418579}},
["Roof_Sheathing"]={{0.849803923,0.647058828,0.431372552,1,0,"WS_wood_light",0.800000011920929},{0.718470592,0.547058828,0.364705881,1,0,"WS_wood_mid",0.8199999928474426},{0.772549008,0.588235292,0.392156864,1,0,"WS_wood",0.800000011920929}},
["Roof_MetalSkin"]={{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579},{0.232470586,0.250352938,0.268235296,1,0.3499999940395355,"WS_roof_steel_b",0.6000000238418579},{0.175372547,0.188862745,0.20235294,1,0.3499999940395355,"WS_roof_steel_seam",0.6000000238418579}},
["Roof_RidgeCap"]={{0.175372547,0.188862745,0.20235294,1,0.3499999940395355,"WS_roof_steel_seam",0.6000000238418579},{0.203921572,0.219607846,0.235294114,1,0.3499999940395355,"WS_roof_steel",0.6000000238418579}},
["Roof_VergeTrim"]={{0.175372547,0.188862745,0.20235294,1,0.3499999940395355,"WS_roof_steel_seam",0.6000000238418579}},
["Roof_EaveDripEdge"]={{0.175372547,0.188862745,0.20235294,1,0.3499999940395355,"WS_roof_steel_seam",0.6000000238418579}},
["Roof_BargeBoards"]={{0.470588241,0.525490191,0.470588241,1,0,"WS_green",0.800000011920929}}}
local matched = 0
local plan = {}
for _, node in model:GetChildren() do
    if node:IsA("Model") then
        local base = node.Name:gsub("_Node$", "")
        local slots = materials[base]
        assert(slots, "Unmatched source node: " .. node.Name)
        for _, part in node:GetChildren() do
            if part:IsA("MeshPart") then
                assert(part.Name:sub(1, #base) == base, "Unexpected mesh name")
                local suffix = part.Name:sub(#base + 1)
                local index = suffix == "" and 1 or tonumber(suffix)
                local source = index and slots[index]
                assert(source, "Unmatched material: " .. part.Name)
                table.insert(plan, {part=part, source=source})
                matched += 1
            end
        end
    end
end
assert(matched == 153, "Expected 153 material primitives")
local history = game:GetService("ChangeHistoryService")
local recording = history:TryBeginRecording("PrepareFableWorkshop", "Prepare Fable workshop")
for _, entry in plan do
    local p, source = entry.part, entry.source
    p.Anchored = true
    p.Color = Color3.new(source[1], source[2], source[3])
    p.Transparency = 1 - source[4]
    p.Material = source[6]:find("roof_steel", 1, true) and Enum.Material.Plastic
        or (source[5] > 0 and Enum.Material.Metal or Enum.Material.SmoothPlastic)
    p.Reflectance = 0
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p:SetAttribute("SourceMaterial", source[6])
    p:SetAttribute("SourceRoughness", source[7])
    p:SetAttribute("SourceMetallic", source[5])
end
-- The imported pivot axes are source (-X, Z, +Y), verified from the
-- window and entrance. Turning 180 degrees puts windows right and gate forward.
model:PivotTo(CFrame.Angles(0, math.pi, 0))
local function worldBounds()
    local lo = Vector3.new(math.huge,math.huge,math.huge)
    local hi = -lo
    for _, entry in plan do
        local p = entry.part
        for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
            local v=p.CFrame:PointToWorldSpace(p.Size * Vector3.new(x,y,z) / 2)
            lo=lo:Min(v); hi=hi:Max(v)
        end end end
    end
    return lo,hi
end
local lo,hi=worldBounds()
local factor=(4.895/.28)/(hi.Y-lo.Y)
model:ScaleTo(model:GetScale()*factor)
lo,hi=worldBounds()
local ray=RaycastParams.new()
ray.FilterType=Enum.RaycastFilterType.Exclude
ray.FilterDescendantsInstances={model}
local ground=workspace:Raycast(Vector3.new(0,100,-26),Vector3.new(0,-200,0),ray)
assert(ground, "Ground not found")
local center=(lo+hi)/2
local desired=Vector3.new(0,ground.Position.Y+(hi.Y-lo.Y)/2,-26)
model:PivotTo(model:GetPivot()+(desired-center))
-- Separate simple colliders keep disconnected decorative mesh islands from
-- creating solid convex hulls across the entrance or workshop interior.
local collisions=Instance.new("Model")
collisions.Name="Collision"
local pivot=model:GetPivot()
local function position(x,y,z)
    return pivot:PointToWorldSpace(Vector3.new(-x,z,y)*factor)
end
local function box(name,x0,x1,y0,y1,z0,z1,angle)
    local p=Instance.new("Part")
    p.Name=name
    p.Anchored=true; p.Transparency=1; p.CastShadow=false
    p.CanCollide=true; p.CanTouch=false; p.CanQuery=true
    p.Size=Vector3.new(x1-x0,z1-z0,y1-y0)*factor
    p.CFrame=CFrame.new(position((x0+x1)/2,(y0+y1)/2,(z0+z1)/2))*CFrame.Angles(0,angle or 0,0)
    p.Parent=collisions
end
box("Floor",-3.23,3.23,-.05,5.05,-.14,0)
box("FrontLeft",-3.2,-1.05,0,.20,0,2.92)
box("FrontRight",1.05,3.2,0,.20,0,2.92)
box("FrontHeader",-1.05,1.05,0,.20,2.35,3.20)
box("Back",-3.2,3.2,4.8,5,0,3.20)
box("Left",-3.2,-3,0,5,0,2.92)
box("RightBelowWindows",3,3.2,0,5,0,1.2)
box("RightAboveWindows",3,3.2,0,5,2.2,2.92)
box("RightPier1",3,3.2,0,.85,1.2,2.2)
box("RightPier2",3,3.2,1.95,3.1,1.2,2.2)
box("RightPier3",3,3.2,4.2,5,1.2,2.2)
box("WindowGlass1",3.105,3.11,.85,1.95,1.2,2.2)
box("WindowGlass2",3.105,3.11,3.1,4.2,1.2,2.2)
box("Workbench",-2.97,-2.27,1.45,3.75,0,.90)
box("Shelf",-2.906,-1.194,4.35,4.79,0,2.06)
box("LumberRack",-.9,2.85,4.18,4.8,0,2.4)
box("Sawhorses",.9,1.9,1.8,3.5,0,.82)
local function rotatedCollider(name, center, size, rotation)
    local p=Instance.new("Part")
    p.Name=name; p.Anchored=true; p.Transparency=1; p.CastShadow=false
    p.CanCollide=true; p.CanTouch=false; p.CanQuery=true
    p.Size=size*factor; p.CFrame=CFrame.new(center)*rotation; p.Parent=collisions
end
for _, side in {-1,1} do
    local x=side*1.78
    local z=4.65-(1.45/3.2)*1.78+.025
    rotatedCollider("Roof"..side,position(x,2.5,z),
        Vector3.new(math.sqrt(3.56^2+(3.56*1.45/3.2)^2),.08,5.6),
        CFrame.Angles(0,0,-side*math.atan(1.45/3.2)))
    local a=math.rad(side*100)
    local doorX=side*1.062+math.cos(a)*(-side*.529)-math.sin(a)*.0225
    local doorY=-.036+math.sin(a)*(-side*.529)+math.cos(a)*.0225
    rotatedCollider("Door"..side,position(doorX,doorY,1.1925),
        Vector3.new(1.058,2.329,.045),CFrame.Angles(0,a,0))
end
collisions.Parent=model
game:GetService("Lighting").EnvironmentSpecularScale=.15
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(32,22,11),Vector3.new(0,7,-26))
workspace.CurrentCamera.Focus=CFrame.new(0,7,-26)
model:SetAttribute("SourceAssetId","106051543998570")
model:SetAttribute("ImportPrepared",true)
model:SetAttribute("MetersToStuds",factor)
model:SetAttribute("SourceModel","Fable 5.2 round 2")
model:SetAttribute("ImportTask","COMP-R2-IMPORT")
lo,hi=worldBounds()
if recording then history:FinishRecording(recording,Enum.FinishRecordingOperation.Commit) end
history:SetWaypoint("Prepared Fable workshop")
return {materialsRestored=matched,anchored=matched,colliders=#collisions:GetChildren(),
    scale=factor,worldMin=tostring(lo),worldMax=tostring(hi),worldSize=tostring(hi-lo),
    sourceOrigin=tostring(model:GetPivot().Position),gateCenter=tostring(position(0,0,1.175)),
    rightWindow=tostring(position(3.2,1.4,1.7))}
