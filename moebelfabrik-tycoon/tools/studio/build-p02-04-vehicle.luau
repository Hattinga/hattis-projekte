-- P02-04: steerable quad + trailer proxy with DIMENSIONS.md hulls, two deck slots and fastened load.
-- Additive: only creates Workspace.P02Vehicle on the west workshop yard. Restore: remove that model.
-- All sizes/positions in metres; local -Z is the driving direction; Y is height above the yard surface.
assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
assert(not workspace:FindFirstChild("P02Vehicle"),"P02Vehicle already exists; inspect before changing it")
local city=workspace:FindFirstChild("CityGreybox")
assert(city and city:GetAttribute("TaskId")=="P02-03R","City baseline missing")
local yard=city.DeliveryYards:FindFirstChild("Tischlerei_West")
assert(yard and yard:IsA("BasePart"),"West yard missing")
local S=25/7
local origin=city:GetAttribute("OriginStuds")
local groundY=yard.Position.Y+yard.Size.Y/2
local yardCenter=Vector2.new(-72,-7)
local forward=(Vector2.new(-64,5)-yardCenter).Unit -- towards Zufahrt_West / Hauptstrasse
local GAP=0.15 -- coupling zone between the two hulls
local quadCenter=yardCenter+forward*(1+GAP/2)
local quadPos=Vector3.new(origin.X+quadCenter.X*S,groundY,origin.Z+quadCenter.Y*S)
local quadFrame=CFrame.lookAt(quadPos,quadPos+Vector3.new(forward.X,0,forward.Y))
local trailerFrame=quadFrame*CFrame.new(0,0,(2+GAP)*S)

local history=game:GetService("ChangeHistoryService")
local recording=nil
if not history:IsRecordingInProgress() then recording=history:TryBeginRecording("P02Vehicle","P02-04 quad and trailer proxy") end
assert(history:IsRecordingInProgress() or recording,"No undo recording")

local BODY=Color3.fromRGB(196,92,62)
local FRAME=Color3.fromRGB(70,76,80)
local TYRE=Color3.fromRGB(38,40,42)
local DECK=Color3.fromRGB(150,122,88)
local SLOT=Color3.fromRGB(229,184,99)
local WOOD=Color3.fromRGB(201,164,110)
local CARTON=Color3.fromRGB(176,138,96)
local STRAP=Color3.fromRGB(52,96,150)
local HULL=Color3.fromRGB(101,169,214)
local V3=Vector3.new

local root=Instance.new("Model");root.Name="P02Vehicle"
root:SetAttribute("TaskId","P02-04");root:SetAttribute("Revision",2);root:SetAttribute("MetersToStuds",S)
root:SetAttribute("GroundYStuds",groundY);root:SetAttribute("CouplingGapM",GAP)
root:SetAttribute("QuadHullM",V3(1.10,1.20,2.00));root:SetAttribute("DriverHullTopM",1.90)
root:SetAttribute("TrailerHullM",V3(1.20,1.15,2.00));root:SetAttribute("RigHullM",V3(1.20,1.90,4.15))
root:SetAttribute("DeckM",V3(0.70,0.55,1.20));root:SetAttribute("DeckCenterZM",0.25)
root:SetAttribute("SlotM",V3(0.65,0,0.55));root:SetAttribute("DriveTestPassed",false)
local function model(name,frame)
	local m=Instance.new("Model");m.Name=name;m:SetAttribute("FrameCFrame",frame);m.Parent=root;return m
end
local function folder(parent,name) local f=Instance.new("Folder");f.Name=name;f.Parent=parent;return f end
local function part(parent,frame,name,size,center,color,props)
	local p=Instance.new("Part");p.Name=name;p.Size=size*S;p.CFrame=frame*CFrame.new(center*S)
	p.Anchored=false;p.CanTouch=false;p.Color=color;p.Material=Enum.Material.SmoothPlastic
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
	if props then for k,value in props do (p::any)[k]=value end end
	p.Parent=parent;return p
end
local function weld(base,item) local w=Instance.new("WeldConstraint");w.Part0=base;w.Part1=item;w.Parent=item end
local function attachment(p,name,worldFrame)
	local a=Instance.new("Attachment");a.Name=name;a.Parent=p;a.WorldCFrame=worldFrame;return a
end
local function joint(class,parent,name,p0,p1,worldFrame)
	local c=Instance.new(class);c.Name=name
	c.Attachment0=attachment(p0,name.."_A0",worldFrame);c.Attachment1=attachment(p1,name.."_A1",worldFrame)
	c.Parent=parent;return c
end
local function wheel(parent,frame,name,diameter,width,center,friction)
	return part(parent,frame,name,V3(width,diameter,diameter),center,TYRE,{Shape=Enum.PartType.Cylinder,CustomPhysicalProperties=PhysicalProperties.new(1,friction,0,100,1)})
end
local GHOST={Transparency=0.9,CanCollide=false,CanQuery=false,Massless=true,CastShadow=false}
local SOFT={CanCollide=false,Massless=true}

-- Quad: hull 1.10 x 1.20 x 2.00, seat top 0.76, hitch 0.40 above ground.
local quad=model("Quad",quadFrame)
local qJoints=folder(quad,"Constraints");local qHulls=folder(quad,"Envelopes")
local chassis=part(quad,quadFrame,"Chassis",V3(0.34,0.30,1.70),V3(0,0.50,0),FRAME,{CustomPhysicalProperties=PhysicalProperties.new(2.5,0.3,0,1,1)})
quad.PrimaryPart=chassis
for _,spec in {
	{"Body",V3(0.50,0.08,1.30),V3(0,0.64,0.05),BODY},
	{"FrontRack",V3(1.10,0.04,0.45),V3(0,0.62,-0.70),BODY},
	{"RearRack",V3(1.10,0.04,0.45),V3(0,0.62,0.72),BODY},
	{"Bumper",V3(0.90,0.10,0.05),V3(0,0.50,-0.975),FRAME},
	{"SteeringColumn",V3(0.06,0.47,0.06),V3(0,0.915,-0.40),FRAME},
	{"Handlebar",V3(0.70,0.05,0.05),V3(0,1.175,-0.40),FRAME},
	{"HitchBar",V3(0.06,0.06,0.15),V3(0,0.40,0.925),FRAME},
} do weld(chassis,part(quad,quadFrame,spec[1],spec[2],spec[3],spec[4],{Massless=true})) end
local ball=part(quad,quadFrame,"HitchBall",V3(0.06,0.06,GAP/2),V3(0,0.40,1+GAP/4),SLOT,SOFT)
ball:SetAttribute("Coupling",true);weld(chassis,ball)
local seat=Instance.new("VehicleSeat");seat.Name="Seat";seat.Size=V3(0.40,0.08,0.55)*S
seat.CFrame=quadFrame*CFrame.new(V3(0,0.72,0.25)*S) -- top 0.76: measured R15 driver incl. accessories stays below 1.90;seat.Anchored=false;seat.HeadsUpDisplay=false
seat.MaxSpeed=0;seat.Torque=0;seat.TurnSpeed=0;seat.Color=Color3.fromRGB(45,48,52);seat.Material=Enum.Material.SmoothPlastic
seat.TopSurface=Enum.SurfaceType.Smooth;seat.BottomSurface=Enum.SurfaceType.Smooth;seat.Parent=quad;weld(chassis,seat)
local prompt=Instance.new("ProximityPrompt");prompt.Name="DrivePrompt";prompt.ActionText="Fahren";prompt.ObjectText="Quad"
prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=false;prompt.Parent=seat
for _,side in {-1,1} do
	local tag=side==-1 and "L" or "R"
	local front=wheel(quad,quadFrame,"WheelF"..tag,0.56,0.22,V3(side*0.44,0.28,-0.62),1.4)
	local knuckle=part(quad,quadFrame,"KnuckleF"..tag,V3(0.10,0.10,0.10),V3(side*0.25,0.28,-0.62),FRAME,{CanCollide=false,CustomPhysicalProperties=PhysicalProperties.new(8,0.3,0,1,1)})
	local steer=joint("HingeConstraint",qJoints,"SteerF"..tag,chassis,knuckle,knuckle.CFrame*CFrame.Angles(0,0,math.pi/2))
	steer.ActuatorType=Enum.ActuatorType.Servo;steer.ServoMaxTorque=1e7;steer.AngularSpeed=5;steer.AngularResponsiveness=60
	steer.LimitsEnabled=true;steer.LowerAngle=-35;steer.UpperAngle=35;steer.TargetAngle=0
	joint("HingeConstraint",qJoints,"AxleF"..tag,knuckle,front,front.CFrame)
	local rear=wheel(quad,quadFrame,"WheelR"..tag,0.56,0.22,V3(side*0.44,0.28,0.62),1.4)
	local drive=joint("HingeConstraint",qJoints,"DriveR"..tag,chassis,rear,rear.CFrame)
	drive.ActuatorType=Enum.ActuatorType.Motor;drive.MotorMaxTorque=20000;drive.MotorMaxAcceleration=25;drive.AngularVelocity=0
end
part(qHulls,quadFrame,"QuadHull",V3(1.10,1.20,2.00),V3(0,0.60,0),HULL,GHOST)
part(qHulls,quadFrame,"DriverHull",V3(0.60,1.05,0.50),V3(0,1.375,0.25),HULL,GHOST)
for _,ghost in qHulls:GetChildren() do weld(chassis,ghost) end

-- Trailer: hull 1.20 x 1.15 x 2.00 incl. drawbar; deck 0.70 x 1.20 with top at 0.55, centred at Z +0.25.
local trailer=model("Trailer",trailerFrame)
local tJoints=folder(trailer,"Constraints");local tHulls=folder(trailer,"Envelopes")
local slots=folder(trailer,"Slots");local load=folder(trailer,"Load")
local deck=part(trailer,trailerFrame,"Deck",V3(0.70,0.06,1.20),V3(0,0.52,0.25),DECK,{CustomPhysicalProperties=PhysicalProperties.new(2,0.5,0,1,1)})
trailer.PrimaryPart=deck
for _,spec in {
	{"AxleBlock",V3(0.70,0.27,0.10),V3(0,0.355,0.40),FRAME},
	{"Drawbar",V3(0.06,0.06,0.65),V3(0,0.40,-0.675),FRAME},
	{"DrawbarPost",V3(0.06,0.06,0.06),V3(0,0.46,-0.32),FRAME},
	{"Headboard",V3(0.70,0.20,0.02),V3(0,0.65,-0.34),FRAME},
	{"RailL",V3(0.02,0.08,1.20),V3(-0.34,0.59,0.25),FRAME},
	{"RailR",V3(0.02,0.08,1.20),V3(0.34,0.59,0.25),FRAME},
	{"FenderL",V3(0.22,0.03,0.60),V3(-0.49,0.555,0.40),FRAME},
	{"FenderR",V3(0.22,0.03,0.60),V3(0.49,0.555,0.40),FRAME},
} do weld(deck,part(trailer,trailerFrame,spec[1],spec[2],spec[3],spec[4],{Massless=true,CanCollide=spec[1]~="Drawbar"})) end
local head=part(trailer,trailerFrame,"CouplingHead",V3(0.08,0.08,GAP/2),V3(0,0.40,-1-GAP/4),SLOT,SOFT)
head:SetAttribute("Coupling",true);weld(deck,head)
for _,side in {-1,1} do
	local tyre=wheel(trailer,trailerFrame,"Wheel"..(side==-1 and "L" or "R"),0.50,0.20,V3(side*0.50,0.25,0.40),1.0)
	joint("HingeConstraint",tJoints,"Axle"..(side==-1 and "L" or "R"),deck,tyre,tyre.CFrame)
end
local hitch=joint("BallSocketConstraint",tJoints,"Hitch",ball,head,quadFrame*CFrame.new(V3(0,0.40,1+GAP/2)*S))
hitch.LimitsEnabled=true;hitch.UpperAngle=75;hitch.TwistLimitsEnabled=true;hitch.TwistLowerAngle=-20;hitch.TwistUpperAngle=20
local LIGHT={CustomPhysicalProperties=PhysicalProperties.new(0.25,0.6,0,1,1)}
for index,spec in {
	{name="A",z=-0.05,ware="Holzpaket",size=V3(0.60,0.15,0.45),color=WOOD},
	{name="B",z=0.55,ware="Hockerkarton",size=V3(0.46,0.51,0.46),color=CARTON},
} do
	local marker=part(slots,trailerFrame,"Slot"..spec.name,V3(0.65,0.004,0.55),V3(0,0.552,spec.z),SLOT,{CanCollide=false,CanQuery=false,Massless=true,CastShadow=false})
	marker:SetAttribute("CenterM",V3(0,0.55,spec.z));marker:SetAttribute("Ware",spec.ware);weld(deck,marker)
	local ware=part(load,trailerFrame,spec.ware,spec.size,V3(0,0.55+spec.size.Y/2,spec.z),spec.color,LIGHT)
	ware:SetAttribute("Slot",spec.name);ware:SetAttribute("SizeM",spec.size);weld(deck,ware)
	local strap=part(load,trailerFrame,"Strap"..spec.name,V3(spec.size.X+0.02,0.01,0.03),V3(0,0.55+spec.size.Y+0.005,spec.z),STRAP,{CanCollide=false,Massless=true})
	weld(deck,strap)
	for _,side in {-1,1} do
		weld(deck,part(load,trailerFrame,"Strap"..spec.name.."Side",V3(0.01,spec.size.Y,0.03),V3(side*(spec.size.X/2+0.005),0.55+spec.size.Y/2,spec.z),STRAP,{CanCollide=false,Massless=true}))
	end
end
part(tHulls,trailerFrame,"TrailerHull",V3(1.20,1.15,2.00),V3(0,0.575,0),HULL,GHOST)
for _,ghost in tHulls:GetChildren() do weld(deck,ghost) end

-- Server drive: seat input, or TestThrottle/TestSteer attributes while nobody is seated (automated probe).
local drive=Instance.new("Script");drive.Name="Drive"
drive.Source=[[
local quad=script.Parent
local seat=quad:WaitForChild("Seat")
local prompt=seat:WaitForChild("DrivePrompt")
local joints=quad:WaitForChild("Constraints")
local motors={joints:WaitForChild("DriveRL"),joints:WaitForChild("DriveRR")}
local servos={joints:WaitForChild("SteerFL"),joints:WaitForChild("SteerFR")}
local FORWARD,REVERSE,ANGLE=30,10,32 -- studs/s at 1 stud wheel radius, degrees
prompt.Triggered:Connect(function(player)
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health>0 and not seat.Occupant then seat:Sit(humanoid) end
end)
seat:GetPropertyChangedSignal("Occupant"):Connect(function() prompt.Enabled=seat.Occupant==nil end)
game:GetService("RunService").Heartbeat:Connect(function()
	local throttle,steer=seat.ThrottleFloat,seat.SteerFloat
	if not seat.Occupant then throttle=quad:GetAttribute("TestThrottle") or 0;steer=quad:GetAttribute("TestSteer") or 0 end
	local speed=seat.AssemblyLinearVelocity.Magnitude
	local spin=-(throttle>=0 and throttle*FORWARD or throttle*REVERSE)
	local angle=-steer*ANGLE*(1-0.45*math.clamp(speed/FORWARD,0,1))
	for _,motor in motors do motor.AngularVelocity=spin end
	for _,servo in servos do servo.TargetAngle=angle end
end)
]]
drive.Parent=quad
root.Parent=workspace
if recording then history:FinishRecording(recording,Enum.FinishRecordingOperation.Commit) end
return {task="P02-04",parts=#root:GetDescendants(),groundY=groundY,quadPosition=tostring(quadPos),heading=tostring(forward)}
