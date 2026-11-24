--!strict
-- Run directly in Studio or via the dedicated device QA bootstrap.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608)
local runService = game:GetService("RunService")
local players = game:GetService("Players")
local testerMarker = if script and script:IsA("ModuleScript") then script:FindFirstChild("Tester") else nil
local tester = if testerMarker and testerMarker:IsA("ObjectValue") then testerMarker.Value else nil
local deviceTester = if tester and tester:IsA("Player") and tester.Parent == players then tester else nil
assert(runService:IsServer() and runService:IsRunning() and (runService:IsStudio() or deviceTester))
assert(not workspace:FindFirstChild("P0909WorkshopLoad") and not workspace:FindFirstChild("P0509LineDemo"),
	"Start a fresh Play Server")
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local Recipe = require(factory.Recipe)
local Persistence = require(factory.Persistence)
local Transfers = require(factory.Transfers)
local HandMoves = require(factory.HandMoves)
local Workers = require(factory.Workers)
local WorkerRoute = require(factory.WorkerRoute)
local WorkerShift = require(factory.WorkerShift)
local Belts = require(factory.Belts)
local BeltRoute = require(factory.BeltRoute)
local BeltShift = require(factory.BeltShift)
local Line = require(factory.Line)
local LineView = require(factory.LineView)

local lease = if deviceTester then 600 else 120
local hallTemplate = workspace.CityGreybox.Buildings.Tischlerei_West :: Model
local lineTemplate = workspace.P02Line :: Model
local test = Instance.new("Folder")
test.Name = "P0909WorkshopLoad"
if deviceTester then
	test:SetAttribute("TesterUserId", deviceTester.UserId)
	test:SetAttribute("Phase", "Aufbau")
end
test.Parent = workspace
local hand = "Load.Hand"
local function stock(controller: Persistence.Controller): State.Profile
	return assert(controller.snapshot().confirmed).data.state
end

type Workshop = {
	root: Model, controller: Persistence.Controller, worker: WorkerShift.Shift, belt: BeltShift.Shift,
	places: LineView.Places, revision: number, owner: number,
}

local function workshop(name: string, owner: number, offset: Vector3, backlog: boolean): Workshop
	local root = Instance.new("Model")
	root.Name = name
	root.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local hall = hallTemplate:Clone()
	hall:PivotTo(hallTemplate:GetPivot() + offset)
	hall.Parent = root
	local line = lineTemplate:Clone()
	line:PivotTo(lineTemplate:GetPivot() + offset)
	line.Parent = root
	root.Parent = test
	local stations = assert(line:FindFirstChild("Stations"))
	local registry = assert(Recipe.bind(stations))
	local beltFixture = BeltRoute.spawn(BeltRoute.bind(stations), root)
	local route = WorkerRoute.bind(stations, "Finish")
	assert(WorkerRoute.clear(route.rest, route.source.stand.Position, {})
		and WorkerRoute.clear(route.source.stand.Position, route.target.stand.Position, {}), name .. " aisle blocked")
	local workerRig = WorkerRoute.spawn(route, root)
	local stationPads: {[string]: BasePart} = {}
	for _, rule in State.STATIONS do
		stationPads[rule.id] = stations[rule.id].Process
	end
	local places: LineView.Places = {points = registry.points, stationPads = stationPads,
		carriers = {[State.FIRST_WORKER.carrier] = workerRig.root}}
	places.points[State.FIRST_BELT.carrier] = beltFixture.buffer

	local saved: any = nil
	local controller = Persistence.new(owner, {
		read = function(): any return saved end,
		update = function(_, transform)
			local proposed = transform(saved)
			if proposed then saved = proposed end
			return saved
		end,
	})
	assert(controller.load("P0909/" .. name, lease, function()
		local state = State.newProfile(owner)
		state.money = 400
		state.locations = registry.locations
		state.locations[hand] = State.newLocation(hand, "Carrier", 1, {"Rohhocker"})
		state.batches.Kit = State.newBatch("Kit", owner, "Bausatz", "Saege.Output")
		state.batches.Wood = State.newBatch("Wood", owner, "Holzpaket", "Saege.Input")
		state.batches.Stool = State.newBatch("Stool", owner, "Fertig", "Finish.Output")
		if backlog then
			state.batches.BlockingKit = State.newBatch("BlockingKit", owner, "Bausatz", "Montage.Input")
			state.batches.BlockingOutput = State.newBatch("BlockingOutput", owner, "Rohhocker", "Montage.Output")
		end
		return {profileVersion = 1, state = state,
			progress = {version = 1, selectedRecipeId = Recipe.id, selectedRecipeVersion = Recipe.version}}
	end).ok)
	assert(Workers.hire(controller, owner, stock(controller).revision, lease).code == "HIRED")
	assert(Workers.assign(controller, owner, stock(controller).revision, lease).code == "ASSIGNED")
	assert(Belts.install(controller, owner, stock(controller).revision, lease).code == "BELT_INSTALLED")
	assert(Workers.reassign(controller, owner, stock(controller).revision, lease).code == "REASSIGNED")
	return {root = root, controller = controller, places = places, owner = owner,
		belt = BeltShift.new(beltFixture, root), worker = WorkerShift.new(route, workerRig, false), revision = -1}
end

local function refresh(plot: Workshop, now: number, clock: number)
	local state = stock(plot.controller)
	if state.revision ~= plot.revision then
		LineView.syncWares(plot.root, state, plot.places)
		plot.worker.rig.root:SetNetworkOwner(nil)
		plot.revision = state.revision
	end
	LineView.syncSigns(plot.root, state, now, plot.places)
	LineView.syncBelt(plot.root, state, now, assert(plot.belt.fixture.model.PrimaryPart), false)
	BeltShift.place(plot.belt, clock, state)
end

local function waitFor(label: string, predicate: () -> boolean, seconds: number?)
	local deadline = os.clock() + (seconds or 22)
	repeat
		assert(not deviceTester or deviceTester.Parent == players, "Tester left")
		if predicate() then return end
		runService.Heartbeat:Wait()
	until os.clock() >= deadline
	error("Timed out: " .. label)
end

local function deliveries(profile: State.Profile, batchId: string, target: string): number
	local count = 0
	for _, receipt in profile.receipts do
		local result = receipt.result
		if receipt.action == "Commit" and result.batchId == batchId and result.targetId == target then count += 1 end
	end
	return count
end

-- Move B's blocking output through a test carrier using the same shared stock rules.
local function unblock(plot: Workshop)
	local current = assert(plot.controller.snapshot().confirmed).data
	local store = Transfers.new(current.state)
	local actor = {kind = "Player", ready = true, ownerUserId = plot.owner,
		actorId = "Player/" .. plot.owner, carrierLocationId = hand}
	local now = os.time()
	for _, move in {{"clear/take", "Montage.Output", hand}, {"clear/put", hand, "Finish.Input"}} do
		local id, source, target = move[1], move[2], move[3]
		local reserve = Transfers.reserve(store, actor, {operationId = id, expectedRevision = store.profile.revision,
			batchId = "BlockingOutput", sourceId = source, targetId = target, quantity = 1}, now, 5)
		assert(reserve.ok, reserve.code)
		local commit = Transfers.commit(store, actor, {operationId = id .. "/commit", claimId = id,
			expectedRevision = store.profile.revision}, now)
		assert(commit.ok, commit.code)
	end
	current.state = store.profile
	assert(plot.controller.save(current, lease).ok)
end

local function deviceControls(player: Player, plot: Workshop)
	local stations = plot.root.P02Line.Stations
	local output, input = "Montage.Output", "Finish.Input"
	local endpoints: {[string]: HandMoves.Endpoint} = {
		[output] = {point = plot.places.points[output], stand = stations.Montage.Standpoints.Output},
		[input] = {point = plot.places.points[input], stand = stations.Finish.Standpoints.Input},
	}
	local function position(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 15)
		local humanoid = character:WaitForChild("Humanoid", 15)
		if not root or not root:IsA("BasePart") or not humanoid or not humanoid:IsA("Humanoid")
			or player.Character ~= character then return end
		local stand = assert(endpoints[output].stand)
		local toward = endpoints[output].point.WorldPosition
		local edge = ((toward - stand.Position) * Vector3.new(1, 0, 1)).Unit * 2.25
		local at = stand.Position + edge + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
		character:PivotTo(CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z)))
		plot.places.carriers = {[State.FIRST_WORKER.carrier] = plot.worker.rig.root, [hand] = root}
		local wares = plot.root:FindFirstChild("Wares")
		if wares and stock(plot.controller).batches.BlockingOutput.locationId == hand then
			local oldView = wares:FindFirstChild("BlockingOutput")
			if oldView then oldView:Destroy() end
			plot.revision = -1
		end
	end
	local respawn = player.CharacterAdded:Connect(position)
	position(assert(player.Character))

	local function prompt(name: string, target: string, action: string, object: string): ProximityPrompt
		local result = Instance.new("ProximityPrompt")
		result.Name, result.ActionText, result.ObjectText = name, action, object
		result.MaxActivationDistance, result.ClickablePrompt = 6, true
		result.Enabled = false
		result.Parent = endpoints[target].point
		return result
	end
	local start = prompt("DeviceStart", output, "Test starten", "Förderband")
	local take = prompt("DeviceTake", output, "Aufnehmen", "Rohhocker am Montageausgang")
	local put = prompt("DevicePut", input, "Ablegen", "Finish-Eingang")
	local started, finished = false, false
	local function authorized(user: Player, enabled: boolean): boolean
		return enabled and user == player and user.UserId == plot.owner and user.Parent == players
	end
	local function move(location: string, direction: "Take" | "Put"): boolean
		local profile = assert(plot.controller.snapshot().confirmed).data
		local store = Transfers.new(profile.state)
		local outcome = HandMoves.interact(store, player, true, hand, endpoints, location, direction,
			"device/" .. direction, os.time(), nil)
		if not outcome.ok then
			test:SetAttribute("Notice", outcome.message)
			return false
		end
		profile.state = store.profile
		local saved = plot.controller.save(profile, lease)
		test:SetAttribute("Notice", if saved.ok then nil else saved.message)
		return saved.ok
	end
	start.Triggered:Connect(function(user)
		if not authorized(user, start.Enabled) then return end
		local problem = HandMoves.checkReach(user, endpoints[output])
		if problem then test:SetAttribute("Notice", problem.message) return end
		test:SetAttribute("Notice", nil)
		start.Enabled, started = false, true
	end)
	take.Triggered:Connect(function(user)
		if authorized(user, take.Enabled) and move(output, "Take") then
			take.Enabled, put.Enabled = false, true
			test:SetAttribute("Phase", "Wiederanlauf")
		end
	end)
	put.Triggered:Connect(function(user)
		if authorized(user, put.Enabled) and move(input, "Put") then
			put.Enabled, finished = false, true
		end
	end)
	local function cleanup()
		respawn:Disconnect()
		start:Destroy()
		take:Destroy()
		put:Destroy()
	end
	return {
		start = function()
			test:SetAttribute("Phase", "Bereit")
			start.Enabled = true
			waitFor("tester starts the load", function() return started end, 180)
			test:SetAttribute("Phase", "Band läuft")
		end,
		unblock = function()
			test:SetAttribute("Phase", "Freiräumen")
			take.Enabled = true
			waitFor("tester clears the assembly output", function() return finished end, 180)
		end,
		cleanup = cleanup,
	}
end

local first = workshop("A", 101, Vector3.new(0, 48, 0), false)
local second = workshop("B", if deviceTester then deviceTester.UserId else 102, Vector3.new(76, 48, 0), true)
local plots = {first, second}
local controls = if deviceTester then deviceControls(deviceTester, second) else nil
local active = false
local frames: RBXScriptConnection? = nil

local function startTicks()
	active = true
	for _, plot in plots do
		task.spawn(function()
			while active do
				WorkerShift.tick(plot.worker, plot.controller, lease)
				task.wait(0.25)
			end
		end)
	end
	local accumulated = 0.25
	frames = runService.Heartbeat:Connect(function(dt)
		accumulated += dt
		local now, clock = os.time(), os.clock()
		if accumulated >= 0.25 then
			accumulated = 0
			for _, plot in plots do
				Line.tick(plot.controller, now, lease)
				BeltShift.tick(plot.belt, plot.controller, lease)
				refresh(plot, now, clock)
			end
		else
			for _, plot in plots do BeltShift.place(plot.belt, clock) end
		end
		if controls then
			local exit = second.belt.exit
			local sample = test:GetAttribute("SamplePhase")
			local moving = exit and exit.batchId == "Kit" and exit.started and clock < exit.started + BeltShift.EXIT_SECONDS
			if moving then
				if sample ~= "Bandfahrt" then test:SetAttribute("SamplePhase", "Bandfahrt") end
			elseif sample == "Bandfahrt" then
				test:SetAttribute("SamplePhase", nil)
			end
		end
	end)
end

local ok, result = xpcall(function()
	if controls then controls.start() end
	startTicks()
	local movedBy = 0
	local horizontal = Vector3.new(1, 0, 1)
	waitFor("A moving while B waits at the buffer", function()
		local viewA, viewB = first.belt.view, second.belt.view
		if not viewA or not viewB or not first.belt.exit or second.belt.status ~= "Montageeingang belegt" then return false end
		movedBy = ((viewA:GetPivot().Position - first.belt.fixture.buffer.WorldPosition) * horizontal).Magnitude
		if movedBy < 0.25 then return false end
		assert(((viewB:GetPivot().Position - second.belt.fixture.buffer.WorldPosition) * horizontal).Magnitude < 0.01)
		return true
	end)
	local held = stock(second.controller)
	assert(held.batches.Kit.locationId == "Band.First" and held.batches.Wood.locationId == "Saege.Input")
	assert(second.root.Signs.Status_Belt:GetAttribute("StatusCode") == "BACKLOG"
		and second.root.Signs.Status_Saege:GetAttribute("StatusCode") == "BACKLOG")
	if controls then
		test:SetAttribute("Phase", "Rückstau")
		test:SetAttribute("SamplePhase", "Rückstau")
	end
	local holdingSince = os.clock()
	task.wait(3)
	if controls then test:SetAttribute("SamplePhase", nil) end
	local heldAgain = stock(second.controller)
	assert(heldAgain.batches.Kit.locationId == "Band.First" and heldAgain.batches.Wood.locationId == "Saege.Input"
		and heldAgain.reservations["Saege.Output"].batchId == "Kit" and deliveries(heldAgain, "Kit", "Montage.Input") == 0)
	assert(deliveries(stock(first.controller), "Kit", "Montage.Input") == 1)
	local holdSeconds = os.clock() - holdingSince
	if controls then
		controls.unblock()
	else
		local firstRevision = stock(first.controller).revision
		unblock(second)
		assert(stock(first.controller).revision == firstRevision, "Opening B affected A")
	end
	waitFor("both independent kit, stool and saw cycles", function()
		for _, plot in plots do
			local state = stock(plot.controller)
			if deliveries(state, "Kit", "Montage.Input") ~= 1 or deliveries(state, "Stool", "Packen.Input") ~= 1
				or state.batches.Wood.stage ~= "Bausatz" then return false end
		end
		return true
	end)
	local final = {}
	for _, plot in plots do
		local state = stock(plot.controller)
		assert(State.validate(state) and state.money == 80 and state.batches.Kit.ownerUserId == plot.owner)
		assert(deliveries(state, "Kit", "Band.First") == 1 and deliveries(state, "Stool", "Worker.First") == 1)
		assert((plot.root.Signs.Status_Belt :: BillboardGui).Adornee == plot.belt.fixture.model.PrimaryPart)
		table.insert(final, {plot = plot.root.Name, owner = plot.owner, revision = state.revision, money = state.money})
	end
	return {plots = final, workers = #plots, belts = #plots, startBatches = 8, separationStuds = 76,
		motionWhileBacklogStuds = movedBy, backlogSeconds = holdSeconds}
end, debug.traceback)
active = false
if frames then frames:Disconnect() end
for _, plot in plots do WorkerShift.stop(plot.worker) end
if controls then
	test:SetAttribute("SamplePhase", nil)
	controls.cleanup()
end
assert(ok, result)
if deviceTester then test:SetAttribute("Phase", "Fertig") end
return result
