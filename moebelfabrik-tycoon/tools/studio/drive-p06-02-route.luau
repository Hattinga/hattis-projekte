-- P06-02 route probe (Server, Play; changes nothing saved). Same driving model as drive-p02-05-route.luau:
-- Tischlerei_West -> Holzlieferant -> Tischlerei_West -> Moebelhandel -> Privatkunden -> Tischlerei_West,
-- 3.5 m right-hand turn on every yard. Additionally: hull contact with P06-01 pads/stands on every sample,
-- and after each leg whether trailer slots A/B and the whole rig stand inside the target LoadZone.
-- Result: JSON in ServerStorage.P0602Result (poll until status is "done" or "aborted").
local S=25/7
local Http=game:GetService("HttpService")
local serverStorage=game:GetService("ServerStorage")
local city=workspace.CityGreybox;local origin=city:GetAttribute("OriginStuds")
local root=workspace.P02Vehicle;local quad,trailer=root.Quad,root.Trailer
local ch,deck=quad.Chassis,trailer.Deck
local hulls={quad.Envelopes.QuadHull,quad.Envelopes.DriverHull,trailer.Envelopes.TrailerHull}
local store=game:GetService("ServerStorage"):FindFirstChild("P0602Result") or Instance.new("StringValue")
store.Name="P0602Result";store.Value="{}";store.Parent=game:GetService("ServerStorage")
local function toLocal(v) return Vector2.new((v.X-origin.X)/S,(v.Z-origin.Z)/S) end
-- P06-01 items: made queryable for this Play session only.
local items={}
for _,yard in city.DeliveryYards:GetChildren() do
	local recovery=yard:FindFirstChild("VehicleRecovery")
	if recovery then for _,point in recovery:GetDescendants() do if point:IsA("BasePart") then table.insert(items,point) end end end
	local acc=yard:FindFirstChild("Annahme")
	if acc then for _,p in acc:GetChildren() do if p:IsA("BasePart") then table.insert(items,p) end end end
	local pick=yard:FindFirstChild("P05Pickup")
	if pick then
		for _,p in pick:GetChildren() do if p:IsA("BasePart") then table.insert(items,p) end end
		if pick:FindFirstChild("Standpoints") then for _,p in pick.Standpoints:GetChildren() do table.insert(items,p) end end
	end
end
for _,p in items do p.CanQuery=true end
local zoneParams=OverlapParams.new();zoneParams.FilterType=Enum.RaycastFilterType.Include;zoneParams.FilterDescendantsInstances=items
local nodes,adj={}, {}
local function key(p) return string.format("%.2f,%.2f",p.X,p.Y) end
for _,r in city.RoadSegments:GetChildren() do
	local a,b=r:GetAttribute("A"),r:GetAttribute("B")
	local pa,pb=Vector2.new(a.X,a.Z),Vector2.new(b.X,b.Z);local ka,kb=key(pa),key(pb)
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
local function resample(pts,step)
	local out={pts[1]}
	for i=2,#pts do local a,b=pts[i-1],pts[i];local n=math.max(1,math.ceil((b-a).Magnitude/step))
		for s=1,n do table.insert(out,a:Lerp(b,s/n)) end end
	return out
end
local R,TRIM=3.5,7
local function legPath(fromC,toC)
	local pts,len=route(fromC,toC)
	local d=(pts[#pts]-pts[#pts-1]).Unit;local right=Vector2.new(-d.Y,d.X)
	local out={}
	for _,p in resample(pts,0.5) do if (p-fromC).Magnitude>=TRIM and (p-toC).Magnitude>=TRIM then table.insert(out,p) end end
	for i=0,12 do local th=math.pi*i/12;table.insert(out,toC+(-right*math.cos(th)+d*math.sin(th))*R) end
	return resample(out,0.5),len
end
local paved=RaycastParams.new();paved.FilterType=Enum.RaycastFilterType.Include;paved.FilterDescendantsInstances={city.RoadSegments,city.Junctions,city.DeliveryYards,city.WorkshopLots}
local solid=OverlapParams.new();solid.FilterType=Enum.RaycastFilterType.Include;solid.FilterDescendantsInstances={city.Buildings,city.Greenery,city.TownSquare,city.Signs}
local wheels={}
for _,p in root:GetDescendants() do if p:IsA("BasePart") and p.Name:match("^Wheel") then table.insert(wheels,p) end end
local function r2(x) return math.floor(x*100+0.5)/100 end
local function follow(path,timeout)
	local cum={0};for i=2,#path do cum[i]=cum[i-1]+(path[i]-path[i-1]).Magnitude end
	local idx,t0,stuckT=1,os.clock(),0
	local st={maxDevM=0,offPaved=0,obstacleSamples=0,zoneItemSamples=0,samples=0,zoneItems={}}
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
		local v=math.min(7-4.5*math.abs(steer),2+remaining*0.5)
		quad:SetAttribute("TestSteer",steer);quad:SetAttribute("TestThrottle",v/8.4)
		st.samples+=1;st.maxDevM=math.max(st.maxDevM,bd)
		for _,w in wheels do if not workspace:Raycast(w.Position+Vector3.new(0,1,0),Vector3.new(0,-4,0),paved) then st.offPaved+=1 end end
		local hit,zoneHit=false,false
		for _,h in hulls do
			if #workspace:GetPartsInPart(h,solid)>0 then hit=true end
			for _,o in workspace:GetPartsInPart(h,zoneParams) do zoneHit=true;st.zoneItems[o.Parent.Parent.Name.."."..o.Parent.Name.."."..o.Name]=true end
		end
		if hit then st.obstacleSamples+=1 end
		if zoneHit then st.zoneItemSamples+=1 end
		if speed<0.3 then stuckT+=dt else stuckT=0 end
		if stuckT>4 then st.stuckAt=tostring(p);break end
		if os.clock()-t0>timeout then st.timeout=true;break end
	end
	quad:SetAttribute("TestSteer",0);quad:SetAttribute("TestThrottle",0);task.wait(1.5)
	st.seconds=r2(os.clock()-t0-1.5);st.maxDevM=r2(st.maxDevM)
	local names={};for k in st.zoneItems do table.insert(names,k) end;st.zoneItems=names
	return st
end
local function inside(volume,point)
	local rel=volume.CFrame:PointToObjectSpace(point)
	return math.abs(rel.X)<=volume.Size.X/2 and math.abs(rel.Y)<=volume.Size.Y/2 and math.abs(rel.Z)<=volume.Size.Z/2
end
local function zoneCheck(target)
	local yard=city.DeliveryYards[target];local volume=yard.LoadZone.Volume
	local slots=inside(volume,trailer.Slots.SlotA.Position) and inside(volume,trailer.Slots.SlotB.Position)
	local corners,inCount=0,0
	for _,h in hulls do
		for _,sx in {-1,1} do for _,sz in {-1,1} do
			corners+=1;if inside(volume,h.CFrame:PointToWorldSpace(Vector3.new(sx*h.Size.X/2,0,sz*h.Size.Z/2))) then inCount+=1 end
		end end
	end
	local entry=yard.LoadZone:GetAttribute("EntryLocal");local d=-entry;local r=Vector3.new(-d.Z,0,d.X)
	local q=yard.CFrame:PointToObjectSpace(ch.Position)/S
	return {slotsInZone=slots,hullCornersInZone=inCount.."/"..corners,quadD=r2(q:Dot(d)),quadR=r2(q:Dot(r))}
end
local dest={}
for _,m in city.Destinations:GetChildren() do local lp=m:GetAttribute("LocalPosition");dest[m.Name]=Vector2.new(lp.X,lp.Z) end
local handoff=serverStorage:FindFirstChild("P0608Stop")
local order=if handoff then {"Tischlerei_West","Holzlieferant","Tischlerei_West","Moebelhandel"}
	elseif workspace:GetAttribute("P0606TripProbe") then {"Tischlerei_West","Moebelhandel","Privatkunden"}
	else {"Tischlerei_West","Holzlieferant","Tischlerei_West","Moebelhandel","Privatkunden","Tischlerei_West"}
local result={status="running",legs={}}
store.Value=Http:JSONEncode(result)
task.spawn(function()
	task.wait(2)
	for i=1,#order-1 do
		local path,len=legPath(dest[order[i]],dest[order[i+1]])
		local st=follow(path,150)
		st.from=order[i];st.to=order[i+1];st.roadM=r2(len)
		st.zone=zoneCheck(order[i+1])
		table.insert(result.legs,st);store.Value=Http:JSONEncode(result)
		if st.stuckAt or st.timeout then result.status="aborted";store.Value=Http:JSONEncode(result);return end
		if handoff and handoff:IsA("BindableFunction") then
			local ok,approved=pcall(handoff.Invoke,handoff,i,st)
			if not ok or approved~=true then
				result.status="aborted";st.handoffError=if ok then "Handoff refused" else tostring(approved)
				store.Value=Http:JSONEncode(result);return
			end
		end
	end
	result.status="done";store.Value=Http:JSONEncode(result)
end)
return "started"
