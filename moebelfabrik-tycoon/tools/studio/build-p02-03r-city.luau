--!strict
-- P02-03R: asymmetric town street fabric; native placeholder buildings, no game economy.
-- Owns CityGreybox, archives the former MapGreybox, and relocates the existing spawn/camera.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
assert(not workspace:FindFirstChild("CityGreybox"), "CityGreybox already exists")
local oldMap = workspace:FindFirstChild("MapGreybox")
local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
assert(oldMap and spawn, "Expected map baseline missing")
assert(oldMap:GetAttribute("TaskId")=="P02-03", "Unexpected previous map")
local existingArchive=game:GetService("ServerStorage"):FindFirstChild("MapPrototypes")
assert(not existingArchive or not existingArchive:FindFirstChild("MapGreybox"), "Archive already contains a map")
local scale = 25 / 7
local origin = Vector3.new(430, 0, 450)
type Street = {name: string, width: number, zone: string, points: {Vector2}}
type Road = {a: Vector2, b: Vector2, width: number, street: string}
local function v(x: number, z: number): Vector2 return Vector2.new(x, z) end
local streets: {Street} = {
	{name="Hauptstrasse",width=7.5,zone="mixed",points={v(-118,8),v(-91,14),v(-64,5),v(-49,-4),v(-18,-8),v(10,-2),v(34,-15),v(62,-24),v(94,-17),v(119,-9)}},
	{name="Nordstrasse",width=6.5,zone="home",points={v(-49,-4),v(-57,-38),v(-34,-63),v(6,-72),v(39,-60),v(62,-24)}},
	{name="Suedstrasse",width=6.5,zone="home",points={v(-18,-8),v(-26,24),v(1,49),v(20,55),v(42,61),v(80,50),v(84,30),v(94,-17)}},
	{name="Marktgasse",width=6,zone="mixed",points={v(-57,-38),v(-20,-35),v(11,-34),v(34,-15)}},
	{name="Kirchgasse",width=5.5,zone="home",points={v(-34,-63),v(-20,-35),v(-18,-8)}},
	{name="Muehlgasse",width=5.5,zone="home",points={v(10,-2),v(12,27),v(1,49)}},
	{name="Gartenweg",width=5.5,zone="home",points={v(12,27),v(47,26),v(80,50)}},
	{name="Bahnhofgasse",width=6,zone="mixed",points={v(62,-24),v(47,26)}},
	{name="Hintergasse",width=5.5,zone="service",points={v(6,-72),v(1,-95)}},
	{name="Holzweg",width=6,zone="service",points={v(-91,14),v(-87,48),v(-112,66)}},
	{name="Werkstattgasse",width=5.5,zone="home",points={v(-49,-4),v(-60,29),v(-50,57)}},
	{name="Buchenweg",width=5.5,zone="home",points={v(119,-9),v(115,30)}},
	{name="Lindenweg",width=5.5,zone="home",points={v(20,55),v(18,72),v(24,88)}},
	{name="Zufahrt_West",width=5.5,zone="drive",points={v(-64,5),v(-72,-7)}},
	{name="Zufahrt_Nord",width=5.5,zone="drive",points={v(1,-95),v(-11,-93)}},
	{name="Zufahrt_Sued",width=5.5,zone="drive",points={v(-50,57),v(-50,66)}},
	{name="Zufahrt_Ost",width=5.5,zone="drive",points={v(115,30),v(99,34)}},
	{name="Zufahrt_Handel",width=6,zone="drive",points={v(80,50),v(73,73)}},
	{name="Zufahrt_Privat",width=5.5,zone="drive",points={v(18,72),v(8,78)}},
}
local neighbors: {[string]: {[string]: boolean}} = {}
local function key(p: Vector2): string return string.format("%.3f,%.3f",p.X,p.Y) end
for _, street in streets do for index=1,#street.points-1 do
	local a,b=key(street.points[index]),key(street.points[index+1])
	neighbors[a]=neighbors[a] or {}; neighbors[b]=neighbors[b] or {}
	neighbors[a][b]=true; neighbors[b][a]=true
end end
local function degree(p: Vector2): number
	local count=0; for _ in neighbors[key(p)] or {} do count+=1 end; return count
end
local function smooth(points: {Vector2}): {Vector2}
	local path={points[1]}
	for index=2,#points-1 do
		local before,corner,after=points[index-1],points[index],points[index+1]
		if degree(corner)==2 then
			local trim=math.min(7,(corner-before).Magnitude/3,(after-corner).Magnitude/3)
			local a=corner+(before-corner).Unit*trim
			local b=corner+(after-corner).Unit*trim
			table.insert(path,a)
			for step=1,6 do local t=step/6; table.insert(path,a*(1-t)^2+corner*2*(1-t)*t+b*t^2) end
		else table.insert(path,corner) end
	end
	table.insert(path,points[#points]); return path
end
local history=game:GetService("ChangeHistoryService")
local recording: string?=nil
if not history:IsRecordingInProgress() then recording=history:TryBeginRecording("CityGreybox","P02-03R organic town") end
assert(history:IsRecordingInProgress() or recording,"No undo recording")
local root=Instance.new("Model")
root.Name="CityGreybox"; root:SetAttribute("TaskId","P02-03R");root:SetAttribute("Revision",1)
root:SetAttribute("OriginStuds",origin);root:SetAttribute("MetersToStuds",scale)
root:SetAttribute("PreviousSpawnCFrame",spawn.CFrame)
root:SetAttribute("Snapshot",".local/backups/2026-11-12-p02-03r/before-city.rbxm")
root.Parent=workspace
local partCount=0
local function point(p: Vector2,height: number): Vector3 return origin+Vector3.new(p.X,height,p.Y)*scale end
local function group(name: string): Folder local f=Instance.new("Folder");f.Name=name;f.Parent=root;return f end
local function block(parent: Instance,name: string,size: Vector3,frame: CFrame,color: Color3,solid: boolean): Part
	local p=Instance.new("Part");p.Name=name;p.Size=size*scale;p.CFrame=frame;p.Anchored=true
	p.CanCollide=solid;p.CanQuery=solid;p.CanTouch=false;p.CastShadow=solid;p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.Parent=parent
	partCount+=1;if partCount%20==0 then task.wait() end;return p
end
local grass=Color3.fromRGB(111,135,101)
local asphalt=Color3.fromRGB(65,71,73)
local paving=Color3.fromRGB(181,179,162)
local roofColor=Color3.fromRGB(88,91,87)
local ground=group("Ground")
block(ground,"TownLand",Vector3.new(260,0.1,210),CFrame.new(point(v(0,0),-0.03)),grass,true)
local roadFolder=group("RoadSegments")
local sidewalks=group("Sidewalks")
local junctions=group("Junctions")
local roadData: {Road}={}
for _, street in streets do
	local path=smooth(street.points)
	for index=1,#path-1 do
		local a,b=path[index],path[index+1]
		local surfaceHeight=0.02+(#roadData+1)*0.0001 -- separate overlapping road surfaces to prevent depth flicker
		local from,to=point(a,surfaceHeight),point(b,surfaceHeight)
		local frame=CFrame.lookAt((from+to)/2,to)
		local length=(b-a).Magnitude
		local road=block(roadFolder,street.name.."_"..index,Vector3.new(street.width,0.08,length+0.20),frame,asphalt,true)
		road.Material=Enum.Material.Asphalt
		road.CastShadow=false
		road:SetAttribute("A",Vector3.new(a.X,0,a.Y));road:SetAttribute("B",Vector3.new(b.X,0,b.Y));road:SetAttribute("Street",street.name)
		table.insert(roadData,{a=a,b=b,width=street.width,street=street.name})
		if street.zone~="drive" and street.zone~="service" then
			local trimA=degree(a)>=3 and 5 or 0;local trimB=degree(b)>=3 and 5 or 0
			if length-trimA-trimB>0.5 then
				local start=a+(b-a).Unit*trimA;local finish=b-(b-a).Unit*trimB
				local mid=(point(start,0.06)+point(finish,0.06))/2
				local walkFrame=CFrame.lookAt(mid,point(finish,0.06))
				for _, side in {-1,1} do local walk=block(sidewalks,"Walk_"..street.name,Vector3.new(1.5,0.12,length-trimA-trimB+0.06),walkFrame*CFrame.new(side*(street.width/2+0.75)*scale,0,0),paving,true);walk.CastShadow=false end
			end
		end
	end
end
local capped: {[string]: boolean}={}
for _, street in streets do for _, node in street.points do
	if not capped[key(node)] and degree(node)~=2 then
		capped[key(node)]=true
		local diameter=street.width+(degree(node)>=3 and 1.2 or 0.3)
		local cap=block(junctions,"Junction",Vector3.new(0.08,diameter,diameter),CFrame.new(point(node,0.04))*CFrame.Angles(0,0,math.pi/2),asphalt,true)
		cap.Shape=Enum.PartType.Cylinder
		cap.Material=Enum.Material.Asphalt;cap.CastShadow=false
	end
end end
local signs=group("Signs")
local function sign(name: string,text: string,p: Vector2,height: number,width: number): ()
	local board=block(signs,name,Vector3.new(width,0.7,0.045),CFrame.new(point(p,height)),Color3.fromRGB(43,61,50),false)
	for _,face in {Enum.NormalId.Front,Enum.NormalId.Back} do
		local gui=Instance.new("SurfaceGui");gui.Face=face;gui.PixelsPerStud=25
		local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
		label.TextColor3=Color3.fromRGB(246,239,216);label.Font=Enum.Font.SourceSansBold;label.TextScaled=true;label.Text=text;label.Parent=gui;gui.Parent=board
	end
end
type Reserve={center: Vector2,width: number,depth: number}
local reserved: {Reserve}={
	{center=v(-73,-15),width=34,depth=32},{center=v(-12,-87),width=28,depth=28},
	{center=v(-51,76),width=32,depth=36},{center=v(100,25),width=20,depth=40},
	{center=v(-112,77),width=28,depth=36},{center=v(74,80),width=34,depth=36},
	{center=v(8,78),width=20,depth=18},{center=v(4,-45),width=26,depth=22},
}
local lots=group("WorkshopLots")
local yards=group("DeliveryYards")
local destinations=group("Destinations")
local buildingFolder=group("Buildings")
local occupied: {{position: Vector2,radius: number}}={}
local function frameAt(p: Vector2,front: Vector2): CFrame return CFrame.lookAt(point(p,0),point(p+front,0)) end
local function building(name: string,p: Vector2,width: number,depth: number,height: number,front: Vector2,color: Color3): Model
	local model=Instance.new("Model");model.Name=name;model.Parent=buildingFolder
	model:SetAttribute("FootprintCenter",Vector3.new(p.X,0,p.Y));model:SetAttribute("FootprintSize",Vector3.new(width,0,depth))
	local frame=frameAt(p,front)
	block(model,"Plinth",Vector3.new(width+0.2,0.10,depth+0.2),frame*CFrame.new(0,0.05*scale,0),paving,true)
	block(model,"Body",Vector3.new(width,height,depth),frame*CFrame.new(0,(height/2+0.10)*scale,0),color,true)
	local rise=depth*0.18;local slope=math.atan2(rise,depth/2);local roofLength=math.sqrt((depth/2)^2+rise^2)+0.45
	for _, side in {-1,1} do
		block(model,"Roof",Vector3.new(width+0.7,0.16,roofLength),frame*CFrame.new(0,(height+0.1+rise/2)*scale,side*depth/4*scale)*CFrame.Angles(side*slope,0,0),roofColor,true)
	end
	for _, side in {-1,1} do
		for _, half in {-1,1} do
			local gable=Instance.new("WedgePart");gable.Name="Gable";gable.Size=Vector3.new(0.12,rise,depth/2)*scale
			gable.CFrame=frame*CFrame.new(side*width/2*scale,(height+0.1+rise/2)*scale,half*depth/4*scale)*CFrame.Angles(0,half==1 and math.pi or 0,0)
			gable.Anchored=true;gable.CanCollide=true;gable.CanTouch=false;gable.Color=color;gable.Material=Enum.Material.SmoothPlastic;gable.Parent=model;partCount+=1
		end
	end
	for _, x in {-0.28,0.28} do
		block(model,"Window",Vector3.new(width*0.20,1.1,0.045),frame*CFrame.new(x*width*scale,2.3*scale,(-depth/2-0.025)*scale),Color3.fromRGB(113,151,161),false)
		if height>6 then block(model,"UpperWindow",Vector3.new(width*0.20,1.1,0.045),frame*CFrame.new(x*width*scale,5.1*scale,(-depth/2-0.025)*scale),Color3.fromRGB(113,151,161),false) end
	end
	block(model,"Door",Vector3.new(1.05,2.1,0.06),frame*CFrame.new(0,1.15*scale,(-depth/2-0.04)*scale),Color3.fromRGB(84,104,91),false)
	table.insert(occupied,{position=p,radius=math.sqrt(width^2+depth^2)/2+0.6});return model
end
local function yard(name: string,p: Vector2,role: string): ()
	local pad=block(yards,name,Vector3.new(12,0.10,12),CFrame.new(point(p,0.02)),paving,true)
	pad:SetAttribute("Role",role)
	local marker=block(destinations,name,Vector3.new(0.15,0.008,0.15),CFrame.new(point(p,0.076)),Color3.fromRGB(229,184,99),false)
	marker:SetAttribute("LocalPosition",Vector3.new(p.X,0,p.Y));marker:SetAttribute("Role",role)
end
local workshops={
	{name="Tischlerei_West",center=v(-73,-21),yard=v(-72,-7),width=18,depth=10},
	{name="Tischlerei_Nord",center=v(-12,-80.8),yard=v(-11,-93),width=18,depth=10},
	{name="Tischlerei_Sued",center=v(-51,81),yard=v(-50,66),width=20,depth=12},
	{name="Tischlerei_Ost",center=v(100.7,18),yard=v(99,34),width=16,depth=12},
}
for index,spec in workshops do
	local reserve=reserved[index]
	block(lots,spec.name.."_Yard",Vector3.new(reserve.width,0.025,reserve.depth),CFrame.new(point(reserve.center,0.045)),Color3.fromRGB(165,163,146),true)
	yard(spec.name,spec.yard,"Workshop")
	if index==1 then
		local model=Instance.new("Model");model.Name=spec.name;model.Parent=buildingFolder
		local frame=frameAt(spec.center,v(0,1))
		block(model,"Floor",Vector3.new(18,0.20,10),frame*CFrame.new(0,0.10*scale,0),paving,true)
		block(model,"Back",Vector3.new(18,5.5,0.25),frame*CFrame.new(0,2.95*scale,5*scale),Color3.fromRGB(210,204,179),true)
		for _,side in {-1,1} do
			block(model,"Side",Vector3.new(0.25,5.5,10),frame*CFrame.new(side*9*scale,2.95*scale,0),Color3.fromRGB(210,204,179),true)
			block(model,"FrontPier",Vector3.new(7,5.5,0.25),frame*CFrame.new(side*5.5*scale,2.95*scale,-5*scale),Color3.fromRGB(210,204,179),true)
		end
		block(model,"Header",Vector3.new(4,1.5,0.25),frame*CFrame.new(0,4.95*scale,-5*scale),Color3.fromRGB(111,133,115),true)
		model:SetAttribute("StarterWorkshop",true)
	else
		building(spec.name,spec.center,spec.width,spec.depth,5.4,(spec.yard-spec.center).Unit,Color3.fromRGB(191-index*8,177+index*4,145+index*6))
	end
	local facadeFront=(spec.yard-spec.center).Unit
	sign(spec.name,spec.name:gsub("_"," "),spec.center+facadeFront*(spec.depth/2+0.35),index==1 and 6.3 or 4.2,10)
end
yard("Holzlieferant",v(-112,66),"Supplier")
building("Holzhandel",v(-112,83),24,14,6.5,v(0,-1),Color3.fromRGB(172,133,91))
sign("Holzlieferant","HOLZLIEFERANT",v(-112,74),8,12)
yard("Moebelhandel",v(73,73),"Dealer")
building("Moebelhandel",v(75,89),24,12,7,v(0,-1),Color3.fromRGB(170,183,180))
sign("Moebelhandel","MOEBELHANDEL",v(75,81),8.5,12)
yard("Privatkunden",v(8,78),"Private")
sign("Privatkunden","WOHNVIERTEL | ANLIEFERUNG",v(8,71),2.3,8)
local square=group("TownSquare")
block(square,"MarketPaving",Vector3.new(22,0.10,16),CFrame.new(point(v(4,-45),0.04)),Color3.fromRGB(192,181,157),true)
for index,x in {-8,1,10,19} do
	building(({"Werkzeugladen","Baeckerei","Cafe","Ladenhaus"})[index],v(x,index==4 and -57 or -58),7.5,7.0,({7.2,5.3,7.8,6.0})[index],v(0,1),({Color3.fromRGB(202,182,156),Color3.fromRGB(205,195,169),Color3.fromRGB(182,194,174),Color3.fromRGB(193,176,163)})[index])
end
for _, x in {-2,11} do
	block(square,"BenchSeat",Vector3.new(2.2,0.1,0.6),CFrame.new(point(v(x,-45),0.5)),Color3.fromRGB(143,107,72),true)
	for _, side in {-1,1} do block(square,"BenchLeg",Vector3.new(0.12,0.36,0.50),CFrame.new(point(v(x+side*0.85,-45),0.27)),roofColor,true) end
	block(square,"BenchBack",Vector3.new(2.2,0.45,0.09),CFrame.new(point(v(x,-45.26),0.74)),Color3.fromRGB(143,107,72),true)
end
for index,p in {v(-4,92),v(12,95),v(35,89),v(43,80)} do building("Wohnhaus_Privat"..index,p,8,8,4.5,(v(20,78)-p).Unit,Color3.fromRGB(195-index*5,183+index*4,160+index*3)) end
local function distance(p: Vector2,a: Vector2,b: Vector2): number
	local delta=b-a;return (p-(a+delta*math.clamp((p-a):Dot(delta)/delta:Dot(delta),0,1))).Magnitude
end
local function clear(p: Vector2,radius: number): boolean
	if math.abs(p.X)+radius>127 or math.abs(p.Y)+radius>102 then return false end
	for _,reserve in reserved do
		local dx=math.max(math.abs(p.X-reserve.center.X)-reserve.width/2,0)
		local dz=math.max(math.abs(p.Y-reserve.center.Y)-reserve.depth/2,0)
		if math.sqrt(dx^2+dz^2)<radius+1 then return false end
	end
	for _,body in occupied do if (p-body.position).Magnitude<radius+body.radius+1 then return false end end
	for _,road in roadData do if distance(p,road.a,road.b)<road.width/2+radius+0.8 then return false end end
	return true
end
local random=Random.new(20303)
local houses=0
for _,street in streets do if street.zone=="home" or street.zone=="mixed" then
	for index=1,#street.points-1 do
		local a,b=street.points[index],street.points[index+1];local direction=(b-a).Unit;local normal=v(-direction.Y,direction.X)
		for step=12,(b-a).Magnitude-10,14 do for _,side in {-1,1} do
			if houses<46 then
				local width=random:NextNumber(7.0,10.5);local depth=random:NextNumber(6.5,9.0)
				local setback=random:NextNumber(2.0,4.5)
				local center=a+direction*step+normal*side*(street.width/2+1.5+depth/2+setback)
				local radius=math.sqrt(width^2+depth^2)/2
				if clear(center,radius) then
					houses+=1
					local tall=street.zone=="mixed" and houses%3~=0
					building("Strassenhaus_"..houses,center,width,depth,tall and random:NextNumber(6.8,8.5) or random:NextNumber(4.2,5.1),-normal*side,({Color3.fromRGB(205,194,172),Color3.fromRGB(181,194,178),Color3.fromRGB(197,182,168),Color3.fromRGB(191,194,185)})[houses%4+1])
				end
			end
		end end
	end
end end
local trees=group("Greenery")
local treeCount=0
for _,cluster in {v(-109,-63),v(89,-81),v(-95,88),v(116,72),v(-5,21)} do
	for index=1,12 do
		local angle=index*2.39996;local radius=math.sqrt(index)*4.6
		local p=cluster+v(math.cos(angle),math.sin(angle))*radius
		if clear(p,2.4) then
			treeCount+=1
			block(trees,"Trunk",Vector3.new(0.5,3.2,0.5),CFrame.new(point(p,1.62)),Color3.fromRGB(126,98,66),false)
			local crown=block(trees,"Crown",Vector3.new(4,5,4),CFrame.new(point(p,4.6)),Color3.fromRGB(71,108+index%3*6,76),false);crown.Shape=Enum.PartType.Ball
		end
	end
end
sign("Zentrum","ORTSKERN | MARKTGASSE",v(4,-40),2.4,9)
sign("Wohnviertel","LINDENVIERTEL",v(30,86),2.2,7)
sign("Gewerbe","HOLZWEG | GEWERBE",v(-99,47),2.5,8)
local archive=game:GetService("ServerStorage"):FindFirstChild("MapPrototypes")
if not archive then archive=Instance.new("Folder");archive.Name="MapPrototypes";archive.Parent=game:GetService("ServerStorage") end
oldMap.Parent=archive
root:SetAttribute("OldMapArchive",oldMap:GetFullName())
spawn.CFrame=CFrame.new(point(v(-85,-21),0.03+spawn.Size.Y/(2*scale)))
root:SetAttribute("RoadSegments",#roadData);root:SetAttribute("StreetNames",#streets)
root:SetAttribute("ProceduralHouses",houses);root:SetAttribute("WorkshopCount",4);root:SetAttribute("Trees",treeCount);root:SetAttribute("Parts",partCount)
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(420,960,900),point(v(0,0),0))
workspace.CurrentCamera.Focus=CFrame.new(point(v(0,0),0))
if recording then history:FinishRecording(recording,Enum.FinishRecordingOperation.Commit) end
return {task="P02-03R",parts=partCount,roadSegments=#roadData,streets=#streets,workshops=4,additionalStreetHouses=houses,landmarkBuildings=#buildingFolder:GetChildren(),trees=treeCount,oldRingArchived=true,mirrorLayout=false}
