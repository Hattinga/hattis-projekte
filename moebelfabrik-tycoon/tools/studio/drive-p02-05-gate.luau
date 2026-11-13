-- P02-05 gate probe. Run in the Server datamodel during Play with the rig parked on the west yard
-- (about local -73.5/-8.8, facing away from the hall, as left by drive-p02-05-route.luau).
-- Drives into the starter hall through its 4 m gate (x -75..-71 at z -16), turns inside and leaves again.
-- Result: JSON in ServerStorage.P0205Result.
-- VARIANT "diagonal" (passes): 228 deg right turn on the yard, 48 deg diagonal entry, 3.0 m left turn inside,
--   straight exit along x -73.6.
-- VARIANT "straight" (hull overlaps FrontPier by 0.32 m on the way out): straight entry on x -72.5,
--   270 deg left turn R 3.3 around (-75.8;-21), then a 90 deg right turn R 2.5 through the gate.
local VARIANT="diagonal"
local S=25/7
local Http=game:GetService("HttpService")
local city=workspace.CityGreybox;local origin=city:GetAttribute("OriginStuds")
local root=workspace.P02Vehicle;local quad,trailer=root.Quad,root.Trailer
local ch,deck=quad.Chassis,trailer.Deck
local store=game:GetService("ServerStorage"):FindFirstChild("P0205Result") or Instance.new("StringValue")
store.Name="P0205Result";store.Value="{}";store.Parent=game:GetService("ServerStorage")
local hall=city.Buildings.Tischlerei_West
local V=Vector2.new
local function toLocal(v) return V((v.X-origin.X)/S,(v.Z-origin.Z)/S) end
local function resample(pts,step)
	local out={pts[1]}
	for i=2,#pts do local a,b=pts[i-1],pts[i];local n=math.max(1,math.ceil((b-a).Magnitude/step))
		for s=1,n do table.insert(out,a:Lerp(b,s/n)) end end
	return out
end
local function arc(pts,centre,radius,fromDeg,toDeg,steps)
	for i=0,steps do local phi=math.rad(fromDeg+(toDeg-fromDeg)*i/steps);table.insert(pts,centre+V(math.cos(phi),math.sin(phi))*radius) end
end
local pts={}
if VARIANT=="diagonal" then
	arc(pts,V(-75.8,-8.8),3.5,0,228,19)
	arc(pts,V(-70.6,-22),3.0,48,-180,19)
	table.insert(pts,V(-73.6,-9))
else
	local p0=toLocal(ch.Position);local c=V(-72,-7)
	local from=math.deg(math.atan2(p0.Y-c.Y,p0.X-c.X));local to=180;while to<from do to+=360 end
	arc(pts,c,3.5,from,to,16)
	table.insert(pts,V(-75.5,-9));table.insert(pts,V(-72.5,-13.5));table.insert(pts,V(-72.5,-21))
	arc(pts,V(-75.8,-21),3.3,0,-270,18)
	arc(pts,V(-75.8,-15.2),2.5,-90,0,8)
	table.insert(pts,V(-73.3,-8))
end
local path=resample(pts,0.4)
local paved=RaycastParams.new();paved.FilterType=Enum.RaycastFilterType.Include;paved.FilterDescendantsInstances={city.RoadSegments,city.Junctions,city.DeliveryYards,city.WorkshopLots,hall.Floor}
local solid=OverlapParams.new();solid.FilterType=Enum.RaycastFilterType.Include;solid.FilterDescendantsInstances={city.Buildings,city.Signs}
local wheels={}
for _,p in root:GetDescendants() do if p:IsA("BasePart") and p.Name:match("^Wheel") then table.insert(wheels,p) end end
local function r2(x) return math.floor(x*100+0.5)/100 end
local result={status="running",variant=VARIANT}
task.spawn(function()
	local cum={0};for i=2,#path do cum[i]=cum[i-1]+(path[i]-path[i-1]).Magnitude end
	local idx,t0,stuckT=1,os.clock(),0
	local st={maxDevM=0,maxArticulationDeg=0,minUpY=1,offPaved=0,obstacleSamples=0,samples=0,obstacles={},maxSpeedMs=0,minGateSideM=99,gateCrossings=0,minWallM=99}
	local lastZ=nil
	while true do
		local dt=task.wait(0.05)
		local cf=ch.CFrame
		local p=toLocal(cf.Position+cf.LookVector*0.62*S)
		local f=V(cf.LookVector.X,cf.LookVector.Z).Unit
		local speed=ch.AssemblyLinearVelocity.Magnitude/S
		local best,bd=idx,math.huge
		for i=idx,math.min(#path,idx+25) do local d=(path[i]-p).Magnitude;if d<bd then best,bd=i,d end end
		idx=best
		local remaining=cum[#path]-cum[idx]
		if remaining<1 then break end
		local L=1.8+0.3*speed
		local j=idx;while j<#path and cum[j]-cum[idx]<L do j+=1 end
		local to=path[j]-p;local right=V(-f.Y,f.X)
		local steer=math.clamp(math.deg(math.atan2(to:Dot(right),to:Dot(f)))/18,-1,1)
		local v=math.min(3.2-1.2*math.abs(steer),1.5+remaining*0.5)
		quad:SetAttribute("TestSteer",steer);quad:SetAttribute("TestThrottle",v/8.4)
		st.samples+=1;st.maxDevM=math.max(st.maxDevM,bd);st.maxSpeedMs=math.max(st.maxSpeedMs,speed)
		local rel=cf:ToObjectSpace(deck.CFrame)
		st.maxArticulationDeg=math.max(st.maxArticulationDeg,math.abs(math.deg(math.atan2(rel.LookVector.X,-rel.LookVector.Z))))
		st.minUpY=math.min(st.minUpY,cf.UpVector.Y,deck.CFrame.UpVector.Y)
		for _,w in wheels do if not workspace:Raycast(w.Position+Vector3.new(0,1,0),Vector3.new(0,-5,0),paved) then st.offPaved+=1 end end
		-- hull corner/mid-side points: side clearance in the gate plane band, wall clearance inside the hall
		for _,spec in {{cf,0.55,1.0},{deck.CFrame*CFrame.new(0,0,-0.25*S),0.60,1.0}} do
			for _,sx in {-1,1} do for _,sz in {-1,0,1} do
				local c=toLocal((spec[1]*CFrame.new(sx*spec[2]*S,0,sz*spec[3]*S)).Position)
				if c.Y>-16.4 and c.Y<-15.6 then st.minGateSideM=math.min(st.minGateSideM,c.X+75,-71-c.X) end
				if c.Y<-16.4 then st.minWallM=math.min(st.minWallM,c.Y+25.875,c.X+81.875,-64.125-c.X) end
			end end
		end
		local z=toLocal(cf.Position).Y
		if lastZ and (lastZ+16)*(z+16)<0 then st.gateCrossings+=1 end;lastZ=z
		local hit=false -- exact hull boxes against the building shell (the floor slab is expected below the hull)
		for _,spec in {{cf*CFrame.new(0,0.10*S,0),Vector3.new(1.1,1.2,2.0)},{deck.CFrame*CFrame.new(0,0.055*S,-0.25*S),Vector3.new(1.2,1.15,2.0)}} do
			for _,o in workspace:GetPartBoundsInBox(spec[1],spec[2]*S,solid) do if o.Name~="Floor" then hit=true;st.obstacles[o.Parent.Name.."."..o.Name]=true end end
		end
		if hit then st.obstacleSamples+=1 end
		if speed<0.2 then stuckT+=dt else stuckT=0 end
		if stuckT>4 then st.stuckAt=tostring(p);break end
		if os.clock()-t0>90 then st.timeout=true;break end
	end
	quad:SetAttribute("TestSteer",0);quad:SetAttribute("TestThrottle",0);task.wait(1.5)
	st.seconds=r2(os.clock()-t0-1.5);st.progress=r2(cum[idx]/cum[#path]);st.pathM=r2(cum[#path])
	for k,v in st do if type(v)=="number" then st[k]=r2(v) end end
	local names={};for k in st.obstacles do table.insert(names,k) end;st.obstacles=names
	st.endPos=tostring(toLocal(ch.Position))
	st.floorTopM=r2((hall.Floor.Position.Y+hall.Floor.Size.Y/2-root:GetAttribute("GroundYStuds"))/S)
	st.headerClearM=r2((hall.Header.Position.Y-hall.Header.Size.Y/2-hall.Floor.Position.Y-hall.Floor.Size.Y/2)/S)
	result.gate=st;result.status=(st.stuckAt or st.timeout) and "aborted" or "done";store.Value=Http:JSONEncode(result)
end)
return "started"
