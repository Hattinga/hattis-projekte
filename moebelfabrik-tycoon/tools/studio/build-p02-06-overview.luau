-- P02-06: labelled overview of the driven road route on the city greybox.
-- Additive: only creates Workspace.P02Overview (non-colliding markers and billboards). Restore: remove that model.
-- Route legs match drive-p02-05-route.luau; each leg is drawn 1.0 m beside the next so overlapping legs stay visible.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
assert(not workspace:FindFirstChild("P02Overview"),"P02Overview already exists")
local city=workspace:FindFirstChild("CityGreybox");assert(city and city:GetAttribute("TaskId")=="P02-03R")
assert(workspace:FindFirstChild("P02Vehicle"),"Vehicle missing")
local S=25/7
local origin=city:GetAttribute("OriginStuds")
local V=Vector2.new
local history=game:GetService("ChangeHistoryService")
local recording=nil
if not history:IsRecordingInProgress() then recording=history:TryBeginRecording("P02Overview","P02-06 route overview") end
assert(history:IsRecordingInProgress() or recording,"No undo recording")
local nodes,adj={}, {}
local function key(p) return string.format("%.2f,%.2f",p.X,p.Y) end
for _,r in city.RoadSegments:GetChildren() do
	local a,b=r:GetAttribute("A"),r:GetAttribute("B")
	local pa,pb=V(a.X,a.Z),V(b.X,b.Z);local ka,kb=key(pa),key(pb)
	nodes[ka]=pa;nodes[kb]=pb;adj[ka]=adj[ka] or {};adj[kb]=adj[kb] or {}
	local d=(pa-pb).Magnitude;adj[ka][kb]=d;adj[kb][ka]=d
end
local function route(from,to)
	local dist,prev,done={[key(from)]=0},{},{}
	while true do
		local best,bd=nil,math.huge
		for k,d in dist do if not done[k] and d<bd then best,bd=k,d end end
		assert(best,"no route");if best==key(to) then break end
		done[best]=true
		for n,w in adj[best] do if not done[n] and bd+w<(dist[n] or math.huge) then dist[n]=bd+w;prev[n]=best end end
	end
	local pts={};local k=key(to)
	while k do table.insert(pts,1,nodes[k]);k=prev[k] end
	return pts,dist[key(to)]
end
local root=Instance.new("Model");root.Name="P02Overview"
root:SetAttribute("TaskId","P02-06");root:SetAttribute("Revision",1)
local function world(p,h) return Vector3.new(origin.X+p.X*S,h*S,origin.Z+p.Y*S) end
local count=0
local function strip(parent,a,b,width,height,color)
	local from,to=world(a,height),world(b,height)
	local p=Instance.new("Part");p.Name="Strip";p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
	p.Material=Enum.Material.Neon;p.Color=color;p.Size=Vector3.new(width*S,0.02*S,(to-from).Magnitude+0.05)
	p.CFrame=CFrame.lookAt((from+to)/2,to);p.Parent=parent;count+=1
end
-- Flat sign readable from above (north = -Z is up in a top-down view). Size in metres.
-- Text on a Top face runs along the part's Z axis, so the board is built depth x width and turned -90 degrees.
local SIGN_YAW=math.rad(-90)
local function signAt(parent,name,position,width,depth,text,color)
	local board=Instance.new("Part");board.Name=name;board.Anchored=true;board.CanCollide=false;board.CanQuery=false;board.CanTouch=false;board.CastShadow=false
	board.Material=Enum.Material.SmoothPlastic;board.Color=Color3.fromRGB(28,34,38);board.Size=Vector3.new(depth*S,0.05,width*S)
	board.CFrame=CFrame.new(position)*CFrame.Angles(0,SIGN_YAW,0);board.Parent=parent
	local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Top;gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=math.clamp(900/(width*S),4,40);gui.LightInfluence=0;gui.Parent=board
	local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1
	t.TextColor3=color;t.Font=Enum.Font.SourceSansBold;t.TextScaled=true;t.Text=text;t.Parent=gui
	return board
end
local function label(parent,name,p,height,text,color,width,depth)
	return signAt(parent,name,world(p,height),width or 36,depth or 9,text,color)
end
local dest={}
for _,m in city.Destinations:GetChildren() do local lp=m:GetAttribute("LocalPosition");dest[m.Name]=V(lp.X,lp.Z) end
local legs={
	{"Tischlerei_West","Holzlieferant",Color3.fromRGB(255,170,60)},
	{"Holzlieferant","Tischlerei_West",Color3.fromRGB(255,225,120)},
	{"Tischlerei_West","Moebelhandel",Color3.fromRGB(90,200,255)},
	{"Moebelhandel","Privatkunden",Color3.fromRGB(190,130,255)},
	{"Privatkunden","Tischlerei_West",Color3.fromRGB(120,235,150)},
}
local legend={}
local routeFolder=Instance.new("Folder");routeFolder.Name="Route";routeFolder.Parent=root
for index,leg in legs do
	local folder=Instance.new("Folder");folder.Name=string.format("Leg%d_%s_%s",index,leg[1],leg[2]);folder.Parent=routeFolder
	local pts,len=route(dest[leg[1]],dest[leg[2]])
	folder:SetAttribute("RoadM",len)
	local offset=(index-3)*1.0
	for i=2,#pts do
		local d=(pts[i]-pts[i-1]).Unit;local side=V(-d.Y,d.X)*offset
		strip(folder,pts[i-1]+side,pts[i]+side,0.9,0.16+index*0.004,leg[3])
	end
	table.insert(legend,string.format("%d  %s > %s  %d m",index,leg[1]:gsub("_"," "),leg[2]:gsub("_"," "),math.floor(len+0.5)))
	task.wait()
end
local yards=Instance.new("Folder");yards.Name="YardTurns";yards.Parent=root
local places={
	{"Tischlerei_West","1  START-TISCHLEREI WEST\nFabrik | Ladehof 12 x 12 m"},
	{"Holzlieferant","2  HOLZLIEFERANT\nHolzpaket laden"},
	{"Moebelhandel","3  MOEBELHANDEL\nKarton abliefern"},
	{"Privatkunden","4  PRIVATKUNDEN\nKarton abliefern"},
}
local labelSpot={Tischlerei_West=V(-73,-38),Holzlieferant=V(-104,98),Moebelhandel=V(98,98),Privatkunden=V(-12,100)}
for _,place in places do
	local c=dest[place[1]]
	for i=1,24 do
		local a,b=math.pi*2*(i-1)/24,math.pi*2*i/24
		strip(yards,c+V(math.cos(a),math.sin(a))*3.5,c+V(math.cos(b),math.sin(b))*3.5,0.3,0.15,Color3.fromRGB(240,240,240))
	end
	label(yards,place[1],labelSpot[place[1]],12,place[2],Color3.fromRGB(255,244,214))
end
local notes=Instance.new("Folder");notes.Name="Notes";notes.Parent=root
label(notes,"Legend",V(-92,-84),12,"FAHRROUTE P02-05\n"..table.concat(legend,"\n"),Color3.fromRGB(255,255,255),66,30)
label(notes,"Gate",V(-73,-29.5),7,"HALLENTOR 4,00 m | Kehre nur mit schraegem Anlauf",Color3.fromRGB(255,190,170),20,2.2)
label(notes,"Rig",V(-58,-9),0.3,"GESPANN 1,20 x 1,90 x 4,15 m | 2 Slots | Wendekreis 7,2 m",Color3.fromRGB(200,230,255),12,1.4)
-- Station sequence and store slots on the P02-02 test field: top-readable labels above the existing bodies.
local line=workspace:FindFirstChild("P02Line");assert(line and line:GetAttribute("TaskId")=="P02-02","Station field missing")
local stationNotes=Instance.new("Folder");stationNotes.Name="StationSequence";stationNotes.Parent=root
for _,station in line.Stations:GetChildren() do
	local p=station:GetBoundingBox().Position;local back=station:GetAttribute("Sequence")<=2
	signAt(stationNotes,station.Name,Vector3.new(p.X,8,p.Z+(back and -1.5 or 1.5)),2.45,0.45,
		string.format("%d %s: %s > %s",station:GetAttribute("Sequence"),station.Name:upper(),station:GetAttribute("InputStage"),station:GetAttribute("OutputStage")),Color3.fromRGB(255,244,214))
end
for _,store in line.Stores:GetChildren() do
	local p=store:GetBoundingBox().Position
	signAt(stationNotes,store.Name,Vector3.new(p.X,8,p.Z+2.0),2.45,0.45,
		string.format("%s: %d Plaetze %s",store.Name:upper(),store:GetAttribute("Capacity"),store:GetAttribute("AcceptedStage")),Color3.fromRGB(200,230,255))
end
local band=line.Connections.FirstBandPreview.Position
signAt(stationNotes,"Band",Vector3.new(band.X,8.4,band.Z-3.6),3.6,0.45,"BAND 1,00 m: Saege-Ausgang > Montage-Eingang",Color3.fromRGB(240,240,240))
root:SetAttribute("Strips",count)
root.Parent=workspace
if recording then history:FinishRecording(recording,Enum.FinishRecordingOperation.Commit) end
return {task="P02-06",strips=count,legend=legend}
