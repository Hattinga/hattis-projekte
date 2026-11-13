-- Read-only P02-04 acceptance (Edit, vehicle at its built pose): hulls, deck, slots, load, coupling as one spatial unit.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608)
local root=workspace:FindFirstChild("P02Vehicle")
assert(root and root:GetAttribute("TaskId")=="P02-04")
local S=25/7
local EPS=0.002 -- metres
local quad,trailer=root.Quad,root.Trailer
local groundY=root:GetAttribute("GroundYStuds")
-- Model frames: ground-level centre of each hull, rebuilt from the primary part's known local centre.
local quadFrame=quad.Chassis.CFrame*CFrame.new(0,-0.50*S,0)
local trailerFrame=trailer.Deck.CFrame*CFrame.new(0,-0.52*S,-0.25*S)
local function box(frame,p)
	local rel=frame:ToObjectSpace(p.CFrame)
	local r,u,l=rel.RightVector,rel.UpVector,rel.LookVector
	local h=Vector3.new(
		math.abs(r.X)*p.Size.X+math.abs(u.X)*p.Size.Y+math.abs(l.X)*p.Size.Z,
		math.abs(r.Y)*p.Size.X+math.abs(u.Y)*p.Size.Y+math.abs(l.Y)*p.Size.Z,
		math.abs(r.Z)*p.Size.X+math.abs(u.Z)*p.Size.Y+math.abs(l.Z)*p.Size.Z)/2
	return (rel.Position-h)/S,(rel.Position+h)/S
end
local function bounds(frame,instances,filter)
	local lo,hi=Vector3.one*math.huge,-Vector3.one*math.huge
	for _,container in instances do for _,p in container:GetDescendants() do
		if p:IsA("BasePart") and filter(p) then local a,b=box(frame,p);lo=lo:Min(a);hi=hi:Max(b) end
	end end
	return lo,hi
end
local function solid(p) return not p:FindFirstAncestor("Envelopes") and not p:GetAttribute("Coupling") end
local function inside(lo,hi,minimum,maximum,label)
	assert(lo.X>=minimum.X-EPS and lo.Y>=minimum.Y-EPS and lo.Z>=minimum.Z-EPS and hi.X<=maximum.X+EPS and hi.Y<=maximum.Y+EPS and hi.Z<=maximum.Z+EPS,label.." leaves its hull: "..tostring(lo).." / "..tostring(hi))
end
local function fmt(v) return string.format("%.3f;%.3f;%.3f",v.X,v.Y,v.Z) end
local V3=Vector3.new
local qLo,qHi=bounds(quadFrame,{quad},solid)
inside(qLo,qHi,V3(-0.55,0,-1),V3(0.55,1.20,1),"Quad")
local tLo,tHi=bounds(trailerFrame,{trailer},solid)
inside(tLo,tHi,V3(-0.60,0,-1),V3(0.60,1.15,1),"Trailer")
assert(math.abs(qLo.Y)<EPS and math.abs(tLo.Y)<EPS,"Wheels do not rest on the ground plane")
assert(math.abs(quadFrame.Position.Y-groundY)<EPS*S and math.abs(trailerFrame.Position.Y-groundY)<EPS*S,"Frames off ground")
-- Deck and slots
local dLo,dHi=box(trailerFrame,trailer.Deck)
assert(math.abs(dHi.Y-0.55)<EPS and math.abs(dHi.X-dLo.X-0.70)<EPS and math.abs(dHi.Z-dLo.Z-1.20)<EPS and math.abs((dHi.Z+dLo.Z)/2-0.25)<EPS,"Deck differs from DIMENSIONS")
local loadReport={}
for _,slot in trailer.Slots:GetChildren() do
	local sLo,sHi=box(trailerFrame,slot)
	assert(sLo.X>=dLo.X-EPS and sHi.X<=dHi.X+EPS and sLo.Z>=dLo.Z-EPS and sHi.Z<=dHi.Z+EPS,slot.Name.." outside deck")
	assert(math.abs(sHi.X-sLo.X-0.65)<EPS and math.abs(sHi.Z-sLo.Z-0.55)<EPS,slot.Name.." footprint")
	local center=slot:GetAttribute("CenterM")
	assert(math.abs((sLo.Z+sHi.Z)/2-center.Z)<EPS and math.abs((sLo.X+sHi.X)/2)<EPS,slot.Name.." centre")
	local ware=nil
	for _,item in trailer.Load:GetChildren() do if item:GetAttribute("Slot")==slot.Name:sub(5) then ware=item end end
	assert(ware,"No load in "..slot.Name)
	local wLo,wHi=box(trailerFrame,ware)
	assert(wLo.X>=sLo.X-EPS and wHi.X<=sHi.X+EPS and wLo.Z>=sLo.Z-EPS and wHi.Z<=sHi.Z+EPS,ware.Name.." exceeds its slot")
	assert(math.abs(wLo.Y-0.55)<EPS and wHi.Y<=1.15+EPS,ware.Name.." not resting on deck / too high")
	assert((wHi-wLo-ware:GetAttribute("SizeM")).Magnitude<EPS,ware.Name.." size")
	local fastened=false
	for _,w in ware:GetChildren() do if w:IsA("WeldConstraint") and w.Part0==trailer.Deck and w.Enabled then fastened=true end end
	assert(fastened,ware.Name.." not fastened")
	table.insert(loadReport,{slot=slot.Name,ware=ware.Name,sizeM=fmt(wHi-wLo),topM=wHi.Y,sideAirM=math.min(wLo.X-sLo.X,sHi.X-wHi.X),endAirM=math.min(wLo.Z-sLo.Z,sHi.Z-wHi.Z)})
end
assert(#loadReport==2,"Expected two slots")
local _,aHi=box(trailerFrame,trailer.Slots.SlotA);local bLo=box(trailerFrame,trailer.Slots.SlotB)
assert(bLo.Z-aHi.Z>=-EPS,"Slots overlap")
-- Coupling
local hitch=trailer.Constraints.Hitch
local a0,a1=hitch.Attachment0,hitch.Attachment1
assert(a0:IsDescendantOf(quad) and a1:IsDescendantOf(trailer),"Hitch does not join both vehicles")
assert((a0.WorldPosition-a1.WorldPosition).Magnitude<EPS*S,"Hitch attachments apart")
local hitchLocal=quadFrame:PointToObjectSpace(a0.WorldPosition)/S
local gap=(quadFrame:PointToObjectSpace(trailerFrame.Position)/S).Z-2
assert(math.abs(gap-0.15)<EPS and math.abs(hitchLocal.Z-1.075)<EPS and math.abs(hitchLocal.X)<EPS,"Coupling zone differs")
-- Whole rig incl. coupling parts and driver envelope
local rLo,rHi=bounds(quadFrame,{quad,trailer},function(p) return not p:FindFirstAncestor("Envelopes") or p.Name=="DriverHull" end)
inside(rLo,rHi,V3(-0.60,0,-1),V3(0.60,1.90,3.15),"Rig")
-- Running gear
local wheels,steered,driven=0,0,0
local floor=RaycastParams.new();floor.FilterType=Enum.RaycastFilterType.Include;floor.FilterDescendantsInstances={workspace.CityGreybox}
for _,p in root:GetDescendants() do
	if p:IsA("BasePart") and p.Name:match("^Wheel") then
		wheels+=1;assert(not p.Anchored and p.Shape==Enum.PartType.Cylinder)
		assert(workspace:Raycast(p.Position,Vector3.new(0,-p.Size.Y,0),floor),p.Name.." has no ground below")
	elseif p:IsA("HingeConstraint") then
		assert(p.Attachment0 and p.Attachment1 and (p.Attachment0.WorldPosition-p.Attachment1.WorldPosition).Magnitude<EPS*S,p.Name.." misaligned")
		if p.ActuatorType==Enum.ActuatorType.Servo then steered+=1 elseif p.ActuatorType==Enum.ActuatorType.Motor then driven+=1 end
	elseif p:IsA("BasePart") then assert(not p.Anchored,p.Name.." anchored") end
end
assert(wheels==6 and steered==2 and driven==2,"Running gear incomplete")
assert(quad.Seat:IsA("VehicleSeat") and quad:FindFirstChild("Drive") and quad.Drive:IsA("Script"))
local seatLo,seatHi=box(quadFrame,quad.Seat)
return {task="P02-04",quadM={min=fmt(qLo),max=fmt(qHi),size=fmt(qHi-qLo)},trailerM={min=fmt(tLo),max=fmt(tHi),size=fmt(tHi-tLo)},
	rigM={min=fmt(rLo),max=fmt(rHi),size=fmt(rHi-rLo)},deckM={size=fmt(dHi-dLo),topM=dHi.Y,centerZ=(dHi.Z+dLo.Z)/2},
	hitchM={heightM=hitchLocal.Y,behindQuadCentreM=hitchLocal.Z,gapM=gap},seatTopM=seatHi.Y,load=loadReport,
	wheels=wheels,steeredHinges=steered,drivenHinges=driven,driveTestPassed=root:GetAttribute("DriveTestPassed")}
