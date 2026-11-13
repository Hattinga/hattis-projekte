--!strict
-- Read-only CityGreybox acceptance: graph, paved support, vehicle corridors, pedestrian clearance.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608)
local city=workspace:FindFirstChild("CityGreybox")
assert(city and city:GetAttribute("TaskId")=="P02-03R")
local scale=25/7
local origin=city:GetAttribute("OriginStuds")
assert(typeof(origin)=="Vector3")
local roads=city:FindFirstChild("RoadSegments")
local walks=city:FindFirstChild("Sidewalks")
local buildings=city:FindFirstChild("Buildings")
local destinations=city:FindFirstChild("Destinations")
assert(roads and walks and buildings and destinations)
local function key(p: Vector3): string return string.format("%.2f,%.2f",p.X,p.Z) end
local graph: {[string]: {[string]: boolean}}={}
local obstruction=RaycastParams.new();obstruction.FilterType=Enum.RaycastFilterType.Include;obstruction.FilterDescendantsInstances={buildings}
local floorFilter=RaycastParams.new();floorFilter.FilterType=Enum.RaycastFilterType.Include
floorFilter.FilterDescendantsInstances={roads,city:FindFirstChild("Junctions"),city:FindFirstChild("DeliveryYards")}
local segments,samples,corridors=0,0,0
for _,road in roads:GetChildren() do
	assert(road:IsA("BasePart"))
	local a,b=road:GetAttribute("A"),road:GetAttribute("B")
	assert(typeof(a)=="Vector3" and typeof(b)=="Vector3")
	local ka,kb=key(a),key(b);graph[ka]=graph[ka] or {};graph[kb]=graph[kb] or {};graph[ka][kb]=true;graph[kb][ka]=true
	local from,to=origin+a*scale,origin+b*scale
	local steps=math.max(1,math.ceil((b-a).Magnitude))
	for _,offset in {-1.2,0,1.2} do
		local side=road.CFrame.RightVector*offset*scale
		assert(not workspace:Raycast(from+side+Vector3.new(0,scale,0),to-from,obstruction),"Building blocks "..road.Name)
		corridors+=1
		for index=0,steps do
			assert(workspace:Raycast(from:Lerp(to,index/steps)+side+Vector3.new(0,scale,0),Vector3.new(0,-2*scale,0),floorFilter),"Missing pavement at "..road.Name)
			samples+=1
		end
	end
	segments+=1;if segments%10==0 then task.wait() end
end
local first=next(graph);assert(first)
local reached: {[string]: boolean}={[first]=true};local queue={first};local cursor=1
while cursor<=#queue do
	for neighbor in graph[queue[cursor]] do if not reached[neighbor] then reached[neighbor]=true;table.insert(queue,neighbor) end end
	cursor+=1;assert(cursor<1000,"Unexpected graph size")
end
local nodeCount,junctionCount,deadEnds=0,0,0
for node,neighbors in graph do
	assert(reached[node],"Disconnected road")
	local degree=0;for _ in neighbors do degree+=1 end
	if degree>=3 then junctionCount+=1 elseif degree==1 then deadEnds+=1 end
	nodeCount+=1
end
local destinationCount=0
for _,marker in destinations:GetChildren() do
	local p=marker:GetAttribute("LocalPosition");assert(typeof(p)=="Vector3" and reached[key(p)],"Disconnected destination")
	destinationCount+=1
end
local function footprintOverlap(a: BasePart,b: BasePart): boolean
	local delta=Vector3.new(a.Position.X-b.Position.X,0,a.Position.Z-b.Position.Z)
	for _,axis in {a.CFrame.RightVector,a.CFrame.LookVector,b.CFrame.RightVector,b.CFrame.LookVector} do
		local ra=math.abs(axis:Dot(a.CFrame.RightVector))*a.Size.X/2+math.abs(axis:Dot(a.CFrame.LookVector))*a.Size.Z/2
		local rb=math.abs(axis:Dot(b.CFrame.RightVector))*b.Size.X/2+math.abs(axis:Dot(b.CFrame.LookVector))*b.Size.Z/2
		if ra+rb-math.abs(delta:Dot(axis))<=0.01*scale then return false end
	end
	return true
end
local pedestrianChecks=0
for _,model in buildings:GetChildren() do
	local shape=model:FindFirstChild("Plinth") or model:FindFirstChild("Floor")
	assert(shape and shape:IsA("BasePart"))
	for _,walk in walks:GetChildren() do
		assert(walk:IsA("BasePart"));pedestrianChecks+=1
		assert(not footprintOverlap(shape,walk),model.Name.." obstructs "..walk.Name)
	end
end
assert(destinationCount==7 and junctionCount>=8 and deadEnds>=4)
assert(not workspace:FindFirstChild("MapGreybox"),"Old ring remains active")
local archive=game:GetService("ServerStorage"):FindFirstChild("MapPrototypes")
assert(archive and archive:FindFirstChild("MapGreybox"),"Old map archive missing")
assert(not game:GetService("StarterPack"):FindFirstChild("P02CarryProbe"))
assert(workspace:FindFirstChild("FableWorkshop") and workspace:FindFirstChild("P02Greybox") and workspace:FindFirstChild("P02Line"))
return {task="P02-03R",roadSegments=segments,connectedNodes=nodeCount,junctions=junctionCount,deadEnds=deadEnds,connectedDestinations=destinationCount,pavedSamples=samples,clearCorridors=corridors,pedestrianRectangleChecks=pedestrianChecks,pedestrianConflicts=0,oldRingArchived=true,workshops=4,buildings=#buildings:GetChildren(),vehicleTestPassed=false}
