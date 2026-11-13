-- P02-05 handover and turning-circle probe. Run in the Server datamodel during Play (one player present);
-- changes nothing in the saved place. Result: JSON in ServerStorage.P0205Handover (status "done").
-- Part 1: at each of the four places the rig is parked in its route stop pose (yard centre + 3.5 m to the
--   right of the arrival direction, facing out). The player avatar carries a carton-sized proxy
--   (0.46 x 0.51 x 0.46 m, underside 0.70 m above the feet, in front of the body) around the trailer:
--   left of slot A, left of slot B, behind the trailer, right of slot B, right of slot A and back.
--   At the four slot standpoints the avatar turns to face the trailer.
-- Part 2: full-lock circles at low speed, left and right, on the west workshop lot.
local S=25/7
local Http=game:GetService("HttpService")
local city=workspace.CityGreybox;local origin=city:GetAttribute("OriginStuds")
local root=workspace.P02Vehicle;local quad,trailer=root.Quad,root.Trailer
local ch,deck=quad.Chassis,trailer.Deck
local groundY=root:GetAttribute("GroundYStuds")
local player=game:GetService("Players"):GetPlayers()[1] or game:GetService("Players").PlayerAdded:Wait()
local char=player.Character or player.CharacterAdded:Wait()
local hum=char:WaitForChild("Humanoid");local hrp=char:WaitForChild("HumanoidRootPart")
local store=game:GetService("ServerStorage"):FindFirstChild("P0205Handover") or Instance.new("StringValue")
store.Name="P0205Handover";store.Value="{}";store.Parent=game:GetService("ServerStorage")
local V=Vector2.new
local function r2(x) return math.floor(x*100+0.5)/100 end
local function toLocal(v) return V((v.X-origin.X)/S,(v.Z-origin.Z)/S) end
for _,p in root:GetDescendants() do if p:IsA("BasePart") then pcall(function() p:SetNetworkOwner(nil) end) end end
local function placeRig(pos,heading)
	quad:SetAttribute("TestThrottle",0);quad:SetAttribute("TestSteer",0)
	local p=Vector3.new(origin.X+pos.X*S,groundY+0.50*S+0.03,origin.Z+pos.Y*S)
	local target=CFrame.lookAt(p,p+Vector3.new(heading.X,0,heading.Y))
	root:PivotTo(target*ch.CFrame:Inverse()*root:GetPivot())
	for _,part in root:GetDescendants() do if part:IsA("BasePart") then part.AssemblyLinearVelocity=Vector3.zero;part.AssemblyAngularVelocity=Vector3.zero end end
	task.wait(1.5)
end
-- arrival direction = from the single road neighbour of the yard node
local neighbour={}
local function key(p) return string.format("%.2f,%.2f",p.X,p.Y) end
for _,r in city.RoadSegments:GetChildren() do
	local a,b=r:GetAttribute("A"),r:GetAttribute("B");local pa,pb=V(a.X,a.Z),V(b.X,b.Z)
	neighbour[key(pa)]=pb;neighbour[key(pb)]=pa
end
-- carried proxy
task.wait(1)
local feet=hum.HipHeight+hrp.Size.Y/2
local carton=Instance.new("Part");carton.Name="P0205CarryProxy";carton.Size=Vector3.new(0.46,0.51,0.46)*S
carton.Massless=true;carton.CanCollide=false;carton.CanTouch=false;carton.CanQuery=false;carton.Color=Color3.fromRGB(176,138,96)
carton.CFrame=hrp.CFrame*CFrame.new(0,(0.70+0.255)*S-feet,-0.53*S)
local weld=Instance.new("WeldConstraint");weld.Part0=hrp;weld.Part1=carton;weld.Parent=carton;carton.Parent=char
local wareHit=OverlapParams.new();wareHit.FilterType=Enum.RaycastFilterType.Include
wareHit.FilterDescendantsInstances={quad,trailer,city.Buildings,city.Signs,city.Greenery,city.TownSquare}
local fixed=OverlapParams.new();fixed.FilterType=Enum.RaycastFilterType.Include
fixed.FilterDescendantsInstances={city.Buildings,city.Signs,city.Greenery,city.TownSquare}
local paved=RaycastParams.new();paved.FilterType=Enum.RaycastFilterType.Include
paved.FilterDescendantsInstances={city.RoadSegments,city.Junctions,city.DeliveryYards,city.WorkshopLots}
local result={status="running",places={},avatar={rig=hum.RigType.Name,hipHeight=r2(hum.HipHeight/S)}}
local function handover(name)
	local centre do local lp=city.Destinations[name]:GetAttribute("LocalPosition");centre=V(lp.X,lp.Z) end
	local d=(centre-neighbour[key(centre)]).Unit;local right=V(-d.Y,d.X)
	placeRig(centre+right*3.5,-d)
	local frame=deck.CFrame*CFrame.new(0,-0.52*S,-0.25*S)
	local function at(x,z) return (frame*CFrame.new(x*S,0,z*S)).Position end
	local stand={LA=at(-1.3,-0.05),LB=at(-1.3,0.55),REAR=at(0,2.0),RB=at(1.3,0.55),RA=at(1.3,-0.05)}
	local slot={LA=at(0,-0.05),LB=at(0,0.55),RB=at(0,0.55),RA=at(0,-0.05)}
	local st={place=name,reached=0,targets=0,maxTargetErrorM=0,wareOverlapSamples=0,wareOverlaps={},offPavedSamples=0,samples=0,facingOverlap=0,standClear=0,standTotal=0}
	for _,p in stand do
		st.standTotal+=1
		if #workspace:GetPartBoundsInBox(CFrame.new(p+Vector3.new(0,0.85*S,0)),Vector3.new(1.2,1.5,1.2)*S,fixed)==0 then st.standClear+=1 end
	end
	local function sample()
		st.samples+=1
		local hits=workspace:GetPartsInPart(carton,wareHit)
		if #hits>0 then st.wareOverlapSamples+=1;for _,o in hits do st.wareOverlaps[o.Parent.Name.."."..o.Name]=true end end
		if not workspace:Raycast(hrp.Position,Vector3.new(0,-feet-2,0),paved) then st.offPavedSamples+=1 end
	end
	char:PivotTo(CFrame.new(at(-2.4,-0.05)+Vector3.new(0,feet+0.2,0)));task.wait(0.8)
	for _,id in {"LA","LB","REAR","RB","RA","RB","REAR","LB","LA"} do
		st.targets+=1;local goal=stand[id];local t=0;local err=math.huge
		hum:MoveTo(goal)
		while t<7 do
			t+=task.wait(0.05);sample()
			err=((hrp.Position-goal)*Vector3.new(1,0,1)).Magnitude/S
			if err<0.3 then break end
			if t>3.4 and t<3.5 then hum:MoveTo(goal) end
		end
		if err<0.3 then st.reached+=1 end
		st.maxTargetErrorM=math.max(st.maxTargetErrorM,err)
		if slot[id] then -- face the trailer with the ware in front
			hum.AutoRotate=false
			local here=hrp.Position;local look=Vector3.new(slot[id].X,here.Y,slot[id].Z)
			hrp.CFrame=CFrame.lookAt(here,look);task.wait(0.4);sample()
			if #workspace:GetPartsInPart(carton,wareHit)>0 then st.facingOverlap+=1 end
			hum.AutoRotate=true
		end
	end
	local names={};for k in st.wareOverlaps do table.insert(names,k) end;st.wareOverlaps=names
	st.maxTargetErrorM=r2(st.maxTargetErrorM);st.rigCentre=tostring(toLocal((ch.Position+deck.Position)/2))
	return st
end
local function circle(side) -- side +1 right lock, -1 left lock
	char:PivotTo(CFrame.new(origin.X-95*S,groundY+feet+0.5,origin.Z-4*S))
	placeRig(V(-80,side==1 and -9 or -4),V(1,0))
	quad:SetAttribute("TestSteer",side);quad:SetAttribute("TestThrottle",0.2);task.wait(4)
	local radii,centres,poses,art={}, {}, {},0
	local t=0
	while t<12 do
		t+=task.wait(0.05)
		local cf=ch.CFrame;local v=ch.AssemblyLinearVelocity*Vector3.new(1,0,1);local w=math.abs(ch.AssemblyAngularVelocity.Y)
		if w>0.05 then
			local radius=v.Magnitude/w
			table.insert(radii,radius);table.insert(centres,cf.Position+cf.RightVector*side*radius);table.insert(poses,{cf,deck.CFrame})
			local rel=cf:ToObjectSpace(deck.CFrame);art+=math.abs(math.deg(math.atan2(rel.LookVector.X,-rel.LookVector.Z)))
		end
	end
	quad:SetAttribute("TestSteer",0);quad:SetAttribute("TestThrottle",0);task.wait(1.2)
	local n=#radii;local sumR,sumC=0,Vector3.zero
	for i=1,n do sumR+=radii[i];sumC+=centres[i] end
	local c=sumC/n;local outer,inner=0,math.huge
	for _,pose in poses do
		for index,spec in {{pose[1],0.55,1.0,0},{pose[2],0.60,1.0,-0.25}} do
			for _,sx in {-1,1} do for _,sz in {-1,1} do
				local p=(spec[1]*CFrame.new(sx*spec[2]*S,0,(sz*spec[3]+spec[4])*S)).Position
				local dist=((p-c)*Vector3.new(1,0,1)).Magnitude/S
				outer=math.max(outer,dist);inner=math.min(inner,dist)
			end end
		end
	end
	return {side=side==1 and "right" or "left",samples=n,chassisRadiusM=r2(sumR/n/S),outerHullRadiusM=r2(outer),innerHullRadiusM=r2(inner),sweptWidthM=r2(outer-inner),wallToWallDiameterM=r2(outer*2),meanArticulationDeg=r2(art/n)}
end
task.spawn(function()
	local ok,err=pcall(function()
		for _,name in {"Tischlerei_West","Holzlieferant","Moebelhandel","Privatkunden"} do
			table.insert(result.places,handover(name));store.Value=Http:JSONEncode(result)
		end
		carton:Destroy()
		result.circles={circle(-1),circle(1)}
	end)
	result.status=ok and "done" or ("error: "..tostring(err));store.Value=Http:JSONEncode(result)
end)
return "started"
