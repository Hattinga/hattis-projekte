--!strict
-- P02-02: Server during Play, one R15 test avatar. Runtime-only measurement fixture.
-- Clones the actual 20-part tray; no stock, progression or persistent writes.
-- Poll ServerStorage.P0202CarryResult. Route uses physical Humanoid movement, one initial teleport.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local scale = 25 / 7
local storage = game:GetService("ServerStorage")
assert(not storage:FindFirstChild("P0202CarryResult"), "Probe already started in this Play session")
local player = game:GetService("Players"):GetPlayers()[1]
assert(player and player.Character, "Test player missing")
local character = player.Character :: Model
local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
local avatarRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart
assert(humanoid and avatarRoot)
local line = workspace.P02Line
local feet = humanoid.HipHeight + avatarRoot.Size.Y / 2
local floorTop = workspace.P02Greybox:GetAttribute("FloorTopStuds") :: number
local fixture = Instance.new("Model")
fixture.Name = "P0202VisibleTray"
local tray = storage.P02CarryProbe:Clone() :: Tool
tray.Parent = fixture -- Nested Tool preserves the source geometry without an automatic RightGrip.
fixture.Parent = character
local handle = tray.Handle :: BasePart
local hullSize = Vector3.new(0.6, 0.18, 0.5) * scale
local bodies: {Instance} = {}
for _, group in {line.Stations, line.Stores} do
	for _, station in group:GetChildren() do table.insert(bodies, station.Body) end
end
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = bodies
local ground = RaycastParams.new()
ground.FilterType = Enum.RaycastFilterType.Include
ground.FilterDescendantsInstances = {line.FloorExtension, workspace.P02Greybox.MeasureField}
local output = Instance.new("StringValue")
output.Name = "P0202CarryResult"
output.Parent = storage
local result: any = {task="P02-02",status="running",avatar={rig=humanoid.RigType.Name},
	carryPose={undersideM=0.70,forwardM=0.53},targets={},samples=0,overlapSamples=0,
	overlaps={},offFloorSamples=0,minWareBottomM=math.huge,maxWareBottomM=-math.huge,
	legacyStandpointOverlaps={},waypoints=0,waypointsReached=0,placed=0,hitEvents={}}
local phase, activeTarget = "setup", "start"
local function publish(): () output.Value = game:GetService("HttpService"):JSONEncode(result) end
local function hits(frame: CFrame): {BasePart}
	-- 1 mm inset ignores numerical contact while retaining penetrating corners.
	return workspace:GetPartBoundsInBox(frame, hullSize - Vector3.one * 0.002 * scale, overlap)
end
local function hullFrame(): CFrame return handle.CFrame * CFrame.new(0,0.085*scale,0) end
local function sample(): ()
	result.samples += 1
	local touched = hits(hullFrame())
	if #touched > 0 then
		result.overlapSamples += 1
		for _, part in touched do result.overlaps[part.Parent.Name] = true end
		if #result.hitEvents<40 then table.insert(result.hitEvents,{phase=phase,target=activeTarget,
			position=tostring(avatarRoot.Position),look=tostring(avatarRoot.CFrame.LookVector),
			body=touched[1].Parent.Name,hull=tostring(hullFrame())}) end
	end
	local ray = workspace:Raycast(avatarRoot.Position, Vector3.new(0,-feet-2,0), ground)
	if not ray then result.offFloorSamples += 1 end
	local bottom = (handle.Position.Y - 0.005*scale - floorTop)/scale
	result.minWareBottomM = math.min(result.minWareBottomM,bottom)
	result.maxWareBottomM = math.max(result.maxWareBottomM,bottom)
end
local carrier: WeldConstraint? = nil
local function carry(): ()
	handle.Anchored = false
	handle.CFrame = avatarRoot.CFrame * CFrame.new(0,0.705*scale-feet,-0.53*scale)
	carrier = Instance.new("WeldConstraint")
	carrier.Part0 = avatarRoot; carrier.Part1 = handle; carrier.Parent = fixture
	sample()
end
local function turn(direction: Vector3): ()
	phase="turn"
	humanoid.AutoRotate = false
	local start = avatarRoot.CFrame
	local finish = CFrame.lookAt(start.Position,start.Position+direction*Vector3.new(1,0,1))
	for step=1,12 do
		avatarRoot.CFrame = start:Lerp(finish,step/12)
		task.wait(0.05); sample()
	end
end
local function walk(point: Vector3): number
	result.waypoints += 1
	local delta=(point-avatarRoot.Position)*Vector3.new(1,0,1)
	if delta.Magnitude>0.01 then
		turn(delta.Unit)
		humanoid:MoveTo(point+delta.Unit*0.28*scale)
	end
	phase="walk"
	local deadline = os.clock()+8
	local distance = math.huge
	repeat
		task.wait(0.05);sample()
		distance = ((avatarRoot.Position-point)*Vector3.new(1,0,1)).Magnitude/scale
		humanoid.WalkSpeed=distance<0.4 and 3 or 9
	until distance < 0.10 or os.clock()>deadline
	humanoid:MoveTo(avatarRoot.Position)
	task.wait(0.1);sample()
	distance=((avatarRoot.Position-point)*Vector3.new(1,0,1)).Magnitude/scale
	if distance<0.10 then result.waypointsReached += 1 end
	assert(distance<0.10,"Unreachable waypoint "..result.waypoints)
	return distance
end
local function visit(model: Model, padName: string, biasM: number): ()
	activeTarget=model.Name.."."..padName
	local pad = model:FindFirstChild(padName) :: BasePart
	local transfer = pad:FindFirstChild("Transfer") :: Attachment
	local stand = model.Standpoints[padName] :: BasePart
	local direction = (transfer.WorldPosition-stand.Position)*Vector3.new(1,0,1)
	direction = direction.Unit
	local point = stand.Position-direction*biasM*scale
	local errorM = walk(point)
	local before = result.overlapSamples
	turn(direction)
	-- Compare the old marker's nominal carry pose without moving the avatar there.
	local legacy = CFrame.lookAt(Vector3.new(stand.Position.X,floorTop+feet,stand.Position.Z),
		Vector3.new(stand.Position.X,floorTop+feet,stand.Position.Z)+direction)
	local oldHits = hits(legacy*CFrame.new(0,0.79*scale-feet,-0.53*scale))
	if #oldHits>0 then table.insert(result.legacyStandpointOverlaps,model.Name.."."..padName) end
	assert(carrier);carrier:Destroy();carrier=nil
	handle.Anchored=true
	-- Model a lift to table height before reaching across the body, then the reverse pickup.
	local from = handle.CFrame
	local lifted = from+Vector3.new(0,0.20*scale,0)
	local placed = CFrame.new(transfer.WorldPosition+Vector3.new(0,0.005*scale,0))*from.Rotation
	phase="place"
	for _, endpoints in {{from,lifted},{lifted,placed}} do
		for step=1,8 do handle.CFrame=endpoints[1]:Lerp(endpoints[2],step/8);task.wait(0.025);sample() end
	end
	local placementHits = #hits(hullFrame())
	local bottomError = math.abs((handle.Position.Y-0.005*scale-transfer.WorldPosition.Y)/scale)
	if placementHits==0 and bottomError<0.002 then result.placed+=1 end
	phase="retrieve"
	for _, endpoints in {{placed,lifted},{lifted,from}} do
		for step=1,8 do handle.CFrame=endpoints[1]:Lerp(endpoints[2],step/8);task.wait(0.025);sample() end
	end
	carry()
	table.insert(result.targets,{id=model.Name.."."..padName,reachedErrorM=errorM,
		standOffsetM=biasM,placementHits=placementHits,bottomErrorM=bottomError,
		overlapsDuringHandling=result.overlapSamples-before})
	publish()
end
task.spawn(function()
	local ok,err=pcall(function()
		humanoid.WalkSpeed=9
		local raw=line.Stores.Rohstofflager
		local away=(raw.Standpoints.Slot1.Position-raw.Slot1.Position)*Vector3.new(1,0,1)
		local frontOffset=away.Unit*0.20*scale
		local entrance = line.Route["01_Eingang"].Position
		local start=Vector3.new(entrance.X,floorTop+feet+0.1,entrance.Z)+frontOffset
		character:PivotTo(CFrame.lookAt(start,start+Vector3.new(-1,0,0)))
		pcall(function() avatarRoot:SetNetworkOwner(nil) end)
		task.wait(0.8);carry()
		assert(#hits((bodies[1] :: BasePart).CFrame)>0,"Overlap detector failed positive control")
		for index=4,1,-1 do visit(line.Stores.Rohstofflager,"Slot"..index,0.20) end
		local westOffset=Vector3.new(-0.25*scale,0,0)
		walk(line.Route["03_WestSued"].Position+frontOffset+westOffset)
		walk(line.Route["04_WestMitte"].Position+westOffset)
		for _, name in {"Saege","Montage"} do
			for _, pad in {"Input","Process","Output"} do visit(line.Stations[name],pad,0.15) end
		end
		local rightX = line.Stores.Fertiglager.Slot4.Position.X-0.35*scale
		walk(Vector3.new(rightX,floorTop, line.Route["04_WestMitte"].Position.Z))
		turn(Vector3.new(-1,0,0))
		for _, name in {"Finish","Packen"} do
			for _, pad in {"Input","Process","Output"} do visit(line.Stations[name],pad,0.15) end
		end
		walk(line.Route["13_RueckwegMitte"].Position+westOffset)
		walk(line.Route["14_RueckwegSued"].Position+frontOffset+westOffset)
		for index=1,4 do visit(line.Stores.Fertiglager,"Slot"..index,0.20) end
		result.passed=#result.targets==20 and result.placed==20 and result.overlapSamples==0
			and result.offFloorSamples==0 and result.waypoints==result.waypointsReached
	end)
	result.status=ok and "done" or "error"
	result.error=not ok and tostring(err) or nil
	publish()
	-- Fixture remains visible for the final evidence capture; discarded by Stop.
end)
publish()
return "P02-02 carry probe started"
