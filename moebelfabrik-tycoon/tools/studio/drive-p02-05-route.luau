-- P02-05 route probe. Run in the Server datamodel during Play; changes nothing in the saved place.
-- Drives Workspace.P02Vehicle with its TestThrottle/TestSteer attributes along the CityGreybox road graph:
-- Tischlerei_West -> Holzlieferant -> Tischlerei_West -> Moebelhandel -> Privatkunden -> Tischlerei_West,
-- with a 3.5 m right-hand turning semicircle on every delivery yard.
-- Result: JSON in ServerStorage.P0205Result (poll until status is "done" or "aborted").
local S=25/7
local Http=game:GetService("HttpService")
local city=workspace.CityGreybox;local origin=city:GetAttribute("OriginStuds")
local root=workspace.P02Vehicle;local quad,trailer=root.Quad,root.Trailer
local ch,deck=quad.Chassis,trailer.Deck
local store=game:GetService("ServerStorage"):FindFirstChild("P0205Result") or Instance.new("StringValue")
store.Name="P0205Result";store.Value="{}";store.Parent=game:GetService("ServerStorage")
local function toLocal(v) return Vector2.new((v.X-origin.X)/S,(v.Z-origin.Z)/S) end
local nodes,adj={}, {}
local function key(p) return string.format("%.2f,%.2f",p.X,p.Y) end
for _,r in city.RoadSegments:GetChildren() do
	local a,b=r:GetAttribute("A"),r:GetAttribute("B")
	local pa,pb=Vector2.new(a.X,a.Z),Vector2.new(b.X,b.Z);local ka,kb=key(pa),key(pb)
	nodes[ka]=pa;nodes[kb]=pb;adj[ka]=adj[ka] or {};adj[kb]=adj[kb] or {}
	local d=(pa-pb).Magnitude;adj[ka][kb]=d;adj[kb][ka]=d
end
local function route(from,to) -- shortest path over road segment endpoints
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
local function resample(pts,step)
	local out={pts[1]}
	for i=2,#pts do local a,b=pts[i-1],pts[i];local n=math.max(1,math.ceil((b-a).Magnitude/step))
		for s=1,n do table.insert(out,a:Lerp(b,s/n)) end end
	return out
end
local R,TRIM=3.5,7 -- yard turning radius; road points this close to a yard centre are replaced by the turn
local function legPath(fromC,toC)
	local pts,len=route(fromC,toC)
	local d=(pts[#pts]-pts[#pts-1]).Unit;local right=Vector2.new(-d.Y,d.X)
	local out={}
	for _,p in resample(pts,0.5) do if (p-fromC).Magnitude>=TRIM and (p-toC).Magnitude>=TRIM then table.insert(out,p) end end
	for i=0,12 do local th=math.pi*i/12;table.insert(out,toC+(-right*math.cos(th)+d*math.sin(th))*R) end
	return resample(out,0.5),len
end
local paved=RaycastParams.new();paved.FilterType=Enum.RaycastFilterType.Include;paved.FilterDescendantsInstances={city.RoadSegments,city.Junctions,city.DeliveryYards,city.WorkshopLots}
local walk=RaycastParams.new();walk.FilterType=Enum.RaycastFilterType.Include;walk.FilterDescendantsInstances={city.Sidewalks}
local solid=OverlapParams.new();solid.FilterType=Enum.RaycastFilterType.Include;solid.FilterDescendantsInstances={city.Buildings,city.Greenery,city.TownSquare,city.Signs}
local wheels={}
for _,p in root:GetDescendants() do if p:IsA("BasePart") and p.Name:match("^Wheel") then table.insert(wheels,p) end end
local function r2(x) return math.floor(x*100+0.5)/100 end
local function follow(path,timeout) -- pure pursuit on the front axle; one sample every 0.05 s
	local cum={0};for i=2,#path do cum[i]=cum[i-1]+(path[i]-path[i-1]).Magnitude end
	local idx,t0,stuckT=1,os.clock(),0
	local st={maxDevM=0,maxArticulationDeg=0,minUpY=1,offPavedQuad=0,offPavedTrailer=0,onSidewalk=0,obstacleSamples=0,samples=0,obstacles={},maxSpeedMs=0}
	while true do
		local dt=task.wait(0.05)
		local cf=ch.CFrame
		local p=toLocal(cf.Position+cf.LookVector*0.62*S)
		local f=Vector2.new(cf.LookVector.X,cf.LookVector.Z).Unit
		local speed=ch.AssemblyLinearVelocity.Magnitude/S
		local best,bd=idx,math.huge
		for i=idx,math.min(#path,idx+40) do local d=(path[i]-p).Magnitude;if d<bd then best,bd=i,d end end
		idx=best
		local remaining=cum[#path]-cum[idx]
		if remaining<1 then break end
		local L=2.5+0.35*speed
		local j=idx;while j<#path and cum[j]-cum[idx]<L do j+=1 end
		local to=path[j]-p;local right=Vector2.new(-f.Y,f.X)
		local steer=math.clamp(math.deg(math.atan2(to:Dot(right),to:Dot(f)))/22,-1,1)
		local v=math.min(7-4.5*math.abs(steer),2+remaining*0.5) -- m/s
		quad:SetAttribute("TestSteer",steer);quad:SetAttribute("TestThrottle",v/8.4)
		st.samples+=1;st.maxDevM=math.max(st.maxDevM,bd);st.maxSpeedMs=math.max(st.maxSpeedMs,speed)
		local rel=cf:ToObjectSpace(deck.CFrame)
		st.maxArticulationDeg=math.max(st.maxArticulationDeg,math.abs(math.deg(math.atan2(rel.LookVector.X,-rel.LookVector.Z))))
		st.minUpY=math.min(st.minUpY,cf.UpVector.Y,deck.CFrame.UpVector.Y)
		for _,w in wheels do -- one count per wheel per sample
			local from=w.Position+Vector3.new(0,1,0)
			if not workspace:Raycast(from,Vector3.new(0,-4,0),paved) then if w:IsDescendantOf(quad) then st.offPavedQuad+=1 else st.offPavedTrailer+=1 end end
			if workspace:Raycast(from,Vector3.new(0,-4,0),walk) then st.onSidewalk+=1 end
		end
		local hit=false -- hull boxes with 0.2 m margin against buildings, trunks, benches and signs
		for _,spec in {{cf*CFrame.new(0,0.10*S,0),Vector3.new(1.3,1.2,2.2)},{deck.CFrame*CFrame.new(0,0.055*S,-0.25*S),Vector3.new(1.4,1.15,2.2)}} do
			for _,o in workspace:GetPartBoundsInBox(spec[1],spec[2]*S,solid) do hit=true;st.obstacles[o.Parent.Name.."."..o.Name]=true end
		end
		if hit then st.obstacleSamples+=1 end
		if speed<0.3 then stuckT+=dt else stuckT=0 end
		if stuckT>4 then st.stuckAt=tostring(p);break end
		if os.clock()-t0>timeout then st.timeout=true;break end
	end
	quad:SetAttribute("TestSteer",0);quad:SetAttribute("TestThrottle",0);task.wait(1.5)
	st.seconds=r2(os.clock()-t0-1.5);st.progress=r2(cum[idx]/cum[#path]);st.pathM=r2(cum[#path])
	for k,v in st do if type(v)=="number" then st[k]=r2(v) end end
	local names={};for k in st.obstacles do table.insert(names,k) end;st.obstacles=names
	return st
end
local dest={}
for _,m in city.Destinations:GetChildren() do local lp=m:GetAttribute("LocalPosition");dest[m.Name]=Vector2.new(lp.X,lp.Z) end
local order={"Tischlerei_West","Holzlieferant","Tischlerei_West","Moebelhandel","Privatkunden","Tischlerei_West"}
local carton0=deck.CFrame:ToObjectSpace(trailer.Load.Hockerkarton.CFrame).Position
local result={status="running",legs={}}
task.spawn(function()
	task.wait(2)
	for i=1,#order-1 do
		local path,len=legPath(dest[order[i]],dest[order[i+1]])
		local st=follow(path,150)
		st.from=order[i];st.to=order[i+1];st.roadM=r2(len)
		st.rigCentreToTargetM=r2((toLocal((ch.Position+deck.Position)/2)-dest[order[i+1]]).Magnitude)
		st.cartonDriftM=r2((deck.CFrame:ToObjectSpace(trailer.Load.Hockerkarton.CFrame).Position-carton0).Magnitude/S)
		st.hitchGapStuds=r2((trailer.Constraints.Hitch.Attachment0.WorldPosition-trailer.Constraints.Hitch.Attachment1.WorldPosition).Magnitude)
		table.insert(result.legs,st);store.Value=Http:JSONEncode(result)
		if st.stuckAt or st.timeout then result.status="aborted";store.Value=Http:JSONEncode(result);return end
	end
	result.status="done";store.Value=Http:JSONEncode(result)
end)
return "started"
