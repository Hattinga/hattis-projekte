--!strict
-- Studio-play demo: P05-09 with marked test stock, or P06-04/05 with purchases and the trailer.
-- P07: in a buyer yard, E at the trailer opens a sale; the buyer pad confirms it (hold E).
-- P07SaleStock=true starts with one marked test carton on each trailer slot.
-- P07-07: F at the supplier claims a material advance (1 Holzpaket, no money) for a broke, empty workshop;
-- its sale repays it. P0707Broke=true starts the logistics demo with money 0 instead of 180.
-- In memory by default. P0607ResumeScope opts into an isolated save in the private test place.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local Recipe = require(factory.Recipe)
local Transfers = require(factory.Transfers)
local Persistence = require(factory.Persistence)
local HandMoves = require(factory.HandMoves)
local Loading = require(factory.Loading)
local Line = require(factory.Line)
local LineView = require(factory.LineView)
local Purchases = require(factory.Purchases)
local Trips = require(factory.Trips)
local VehicleRecovery = require(factory.VehicleRecovery)
local Vehicles = require(factory.Vehicles)
local Sales = require(factory.Sales)
local Workers = require(factory.Workers)
local WorkerRoute = require(factory.WorkerRoute)
local WorkerShift = require(factory.WorkerShift)
local WorkerTransport = require(factory.WorkerTransport)
local Belts = require(factory.Belts)
local BeltRoute = require(factory.BeltRoute)
local BeltShift = require(factory.BeltShift)
local players = game:GetService("Players")
local serverStorage = game:GetService("ServerStorage")
local collection = game:GetService("CollectionService")
local http = game:GetService("HttpService")
local line = workspace.P02Line
local player = players:GetPlayers()[1]
assert(player and player.UserId > 0 and player.Character and player.Character:FindFirstChild("HumanoidRootPart"),
	"Wait for a signed-in Studio test player")
local playerGui = player:FindFirstChildOfClass("PlayerGui")
assert(playerGui and not workspace:FindFirstChild("P0509LineDemo"), "Demo already active or PlayerGui missing")
local character = player.Character
local body = character:FindFirstChild("HumanoidRootPart") :: BasePart
local hand = "Demo.Hand"
local TTL = 600
local logisticsEnabled = workspace:GetAttribute("P06LoadingDemo") == true
local workerRoute = if logisticsEnabled then WorkerRoute.bind(line.Stations) else nil
local beltRoute = if logisticsEnabled then BeltRoute.bind(line.Stations) else nil
local resumeScope = workspace:GetAttribute("P0607ResumeScope")
if resumeScope ~= nil then
	assert(logisticsEnabled and type(resumeScope) == "string" and #resumeScope == 38
		and resumeScope:match("^P0607_%x+$"), "Expected an isolated P0607 test scope")
end

-- Registry from the physical fixtures: hand-reachable places, transfer points and signs.
local stations = assert(Recipe.bind(line.Stations))
local shelf = assert(Recipe.bindStore(line.Stores.Fertiglager, "FinishedStore", "Karton"))
local raw = assert(Recipe.bindStore(line.Stores.Rohstofflager, "RawStore", "Holzpaket"))
local endpoints: {[string]: HandMoves.Endpoint} = {}
local names: {[string]: string} = {}
local places: LineView.Places = {points = {}, carriers = {[hand] = body}, stationPads = {}, storeSlots = {},
	storePad = line.Stores.Fertiglager.Slot2}
local storeSlots = assert(places.storeSlots)
for _, binding in {stations, shelf, raw} do
	for id, point in binding.points do places.points[id] = point end
end
for i = 1, 4 do
	for _, spec in {{"RawStore", line.Stores.Rohstofflager, "Rohstofflager"}, {"FinishedStore", line.Stores.Fertiglager, "Fertiglager"}} do
		local id = spec[1] .. ".Slot" .. i
		endpoints[id] = {point = places.points[id], stand = (spec[2] :: any).Standpoints["Slot" .. i]}
		names[id] = spec[3] .. " · Platz " .. i
	end
	table.insert(storeSlots, "FinishedStore.Slot" .. i)
end
local stationNames = {Saege = "Säge", Montage = "Montagebank", Finish = "Finishplatz", Packen = "Packtisch"}
for _, rule in State.STATIONS do
	local model = line.Stations[rule.id]
	places.stationPads[rule.id] = model.Process
	for _, role in {"Input", "Output"} do
		local id = rule.id .. "." .. role
		endpoints[id] = {point = places.points[id], stand = model.Standpoints[role]}
		names[id] = stationNames[rule.id] .. (if role == "Input" then " · Eingang" else " · Ausgang")
	end
end

local profile = State.newProfile(player.UserId)
for _, binding in {stations, shelf, raw} do
	for id, location in binding.locations do profile.locations[id] = location end
end
profile.locations[hand] = State.newLocation(hand, "Carrier", 1, {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"})
local loading: Loading.Binding? = nil
local purchaseSlots: Purchases.Slots? = nil
local trips: Trips.Tracker? = nil
local resumeRig: VehicleRecovery.Rig? = nil
local yards = workspace.CityGreybox.DeliveryYards
local recoveryPoints: {[string]: Attachment} = {}
local recoveryEndpoints: {[string]: HandMoves.Endpoint} = {}
local recoveryYard: string? = nil
local buyerZones: {[string]: BasePart} = {Dealer = yards.Moebelhandel.LoadZone.Volume,
	Private = yards.Privatkunden.LoadZone.Volume}
local buyerNames: {[string]: string} = {Dealer = "Möbelhandel", Private = "Privatkunde"}
local buyerPads: {[string]: HandMoves.Endpoint} = {}
for buyer, yardName in {Dealer = "Moebelhandel", Private = "Privatkunden"} do
	local annahme = yards[yardName].Annahme
	buyerPads[buyer] = {point = annahme.Pad.Transfer, stand = annahme.Standpoint}
end
local salePrompts: {[string]: ProximityPrompt} = {}
local openedHere: {[string]: boolean} = {} -- Sales whose carton left the trailer in this live session.
local unclearSale: string? = nil -- A settlement whose save outcome is still being clarified.
local lastReconcile = -math.huge
if logisticsEnabled then
	if resumeScope then
		resumeRig = VehicleRecovery.rig(workspace:FindFirstChild("P02Vehicle"), serverStorage.P0607VehicleTemplate)
	end
	local vehicle = if resumeRig then resumeRig.model else workspace.P02Vehicle
	local pickup = yards.Holzlieferant.P05Pickup
	local purchase = assert(Purchases.bind(pickup, line.Stores.Rohstofflager))
	local vehicleSlots = if resumeRig then resumeRig.slots else assert(Vehicles.bind(vehicle, vehicle:GetAttribute("VehicleId") :: string))
	local chassis = vehicle.Quad.Chassis :: BasePart
	loading = {vehicle = vehicle, slots = vehicleSlots, chassis = chassis, destinations = places.points, unloads = {},
		recoveryPoints = recoveryPoints,
		zones = {Supplier = yards.Holzlieferant.LoadZone.Volume, Workshop = yards.Tischlerei_West.LoadZone.Volume}}
	vehicle:SetAttribute("OwnerUserId", player.UserId)
	Vehicles.useServerPhysics(vehicle)
	trips = Trips.new({vehicle = vehicle, slots = vehicleSlots, chassis = chassis,
		recoveryPoints = recoveryPoints,
		zones = {Workshop = loading.zones.Workshop, Dealer = yards.Moebelhandel.LoadZone.Volume,
			Private = yards.Privatkunden.LoadZone.Volume}})
	purchaseSlots = purchase.slots
	places.mounts = vehicleSlots.mounts
	for _, id in purchase.slots.supplierIds do
		local point = purchase.points[id]
		places.points[id] = point
		endpoints[id] = {point = point, stand = pickup.Standpoints[(point.Parent :: BasePart).Name]}
		names[id] = "Lieferant · " .. (point.Parent :: BasePart).Name
		profile.locations[id] = purchase.locations[id]
	end
	for _, id in vehicleSlots.slotIds do
		local point = vehicleSlots.mounts[id]
		endpoints[id] = {point = point}
		names[id] = "Anhänger · Platz " .. id:sub(-1)
		profile.locations[id] = vehicleSlots.locations[id]
	end
	-- Only the in-memory test bankroll (with a resume scope only on the first start). P0707Broke tests the advance.
	profile.money = if workspace:GetAttribute("P0707Broke") == true then 0
		elseif workspace:GetAttribute("P0901Funds") == true then 260 else 180
	if workspace:GetAttribute("P07SaleStock") == true then -- With a resume scope only the first start seeds it.
		for index, id in vehicleSlots.slotIds do
			local stockId = "Testkarton-" .. index
			profile.batches[stockId] = State.newBatch(stockId, player.UserId, "Karton", id)
		end
	end
	if workspace:GetAttribute("P0803WorkerStock") == true then
		profile.batches.Testbausatz = State.newBatch("Testbausatz", player.UserId, "Bausatz", WorkerRoute.SOURCE)
		if workspace:GetAttribute("P0804WorkerTargetFull") == true then
			profile.batches.TestMontageInput = State.newBatch("TestMontageInput", player.UserId, "Bausatz", WorkerRoute.TARGET)
			profile.batches.TestMontageOutput = State.newBatch("TestMontageOutput", player.UserId, "Rohhocker", "Montage.Output")
		end
	end
else
	for i = 1, 2 do
		local id = "Testholz-" .. i
		profile.batches[id] = State.newBatch(id, player.UserId, "Holzpaket", "RawStore.Slot" .. i)
	end
end
local stored: any = nil
local backend: Persistence.Backend = {
	read = function(_: string): any return stored end,
	update = function(_: string, transform: (any) -> any): any
		local proposed = transform(stored)
		if proposed ~= nil then stored = proposed end
		return proposed
	end,
}
if resumeScope then
	local dataStore = game:GetService("DataStoreService"):GetDataStore("FactoryP0607_Test", resumeScope :: string)
	backend = Persistence.dataStore(dataStore)
end
local controller = Persistence.new(player.UserId, backend)
local loaded = controller.load("demo/" .. http:GenerateGUID(false), TTL, function(): any
	return {profileVersion = 1, state = profile, progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
end)
assert(loaded.ok, loaded.code)
local function confirmed(): any return controller.snapshot().confirmed end
local demo = Instance.new("Folder")
demo.Name = "P0509LineDemo"
demo.Parent = workspace
local restoredWorker: WorkerRoute.Rig? = nil
local beltFixture: BeltRoute.Fixture? = nil
if resumeRig then
	local progress = confirmed().data.progress
	if beltRoute and progress.firstBelt then
		beltFixture = BeltRoute.spawn(beltRoute, demo)
		places.points[State.FIRST_BELT.carrier] = beltFixture.buffer
	end
	local hire = progress.firstWorker
	if workerRoute and hire and hire.assigned then
		local ok, rig = pcall(WorkerRoute.spawn, workerRoute, demo)
		if not ok then
			demo:Destroy()
			controller.release()
			error("Worker restore failed: " .. tostring(rig))
		end
		restoredWorker = rig
	end
	local active, yardName = VehicleRecovery.restore(controller.snapshot(), player.UserId, os.time(), resumeRig,
		yards, places.points, body, hand, if restoredWorker then restoredWorker.root else nil)
	if not active then
		demo:Destroy()
		controller.release()
		error("Restore failed: " .. yardName)
	end
	recoveryYard = yardName
	for id, endpoint in active do
		recoveryEndpoints[id] = {point = endpoint.point, stand = endpoint.stand}
		recoveryPoints[id] = endpoint.point
		places.points[id] = endpoint.point
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "P0509LineDemo"
gui.ResetOnSpawn = false
gui.Parent = playerGui
local banner = Instance.new("TextLabel")
banner.Name = "Status"
banner.Position = UDim2.fromScale(0.5, 0.04)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Size = UDim2.new(0.9, 0, 0, 84)
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(680, 84)
limit.Parent = banner
banner.BackgroundColor3 = Color3.fromRGB(32, 38, 32)
banner.TextColor3 = Color3.fromRGB(255, 248, 222)
banner.TextWrapped = true
banner.TextSize = 17
banner.Font = Enum.Font.GothamMedium
banner.Parent = gui

local nextTarget = {Holzpaket = "Säge · Eingang", Bausatz = "Montagebank · Eingang", Rohhocker = "Finishplatz · Eingang",
	Fertig = "Packtisch · Eingang", Karton = "Fertiglager"}
local prompts: {[string]: ProximityPrompt} = {}
local hirePrompt: ProximityPrompt? = nil
local assignPrompt: ProximityPrompt? = nil
local beltPrompt: ProximityPrompt? = nil
local powerPrompt: ProximityPrompt? = nil
local beltShift: BeltShift.Shift? = nil
local workerStarted = false
local workerShift: WorkerShift.Shift? = nil
local workerCargo: string? = nil
local workerRecoveryPrompt: ProximityPrompt? = nil
local busy = false
local closing = false
local lastMessage = if loading then "Beim Holzlieferanten mit R kaufen und mit E verladen."
	else "Testholz am Rohstofflager mit E aufnehmen."
if loading and confirmed().data.state.money < Purchases.PRICE and next(confirmed().data.state.batches) == nil then
	lastMessage = "Kein Geld für Holz: Beim Holzlieferanten mit F einen Materialvorschuss holen."
end
if next(recoveryPoints) then lastMessage = "Fracht am Bergungsplatz abholen und auf den passenden Anhängerplatz laden." end
if confirmed().data.state.pendingSale then lastMessage = "Offener Verkauf: Lege den Karton zurück auf seinen Anhängerplatz." end
local function offerText(sale: any): string
	local name = buyerNames[sale.buyer]
	if sale.buyer == "Dealer" then return name .. ": 1 Hocker · Erlös " .. sale.dealerValue end
	return name .. ": 1 Hocker · " .. sale.quoteMin .. "–" .. sale.quoteMax .. " (Händler " .. sale.dealerValue .. ")"
end
-- A repaid material advance (P07-07) is part of the confirmed receipt: amount - repaid was credited.
local function repaidText(receipt: Sales.Receipt): string
	if receipt.balanceBefore == nil then return "" end
	local repaid = receipt.repaid or 0
	return " Vorschuss " .. repaid .. " verrechnet, " .. (receipt.amount - repaid) .. " gutgeschrieben."
end
local function heldBatch(state: any): any
	for _, batch in state.batches do if batch.locationId == hand then return batch end end
	return nil
end
local mountedCargo: {[string]: string} = {}
local function render()
	local snapshot = controller.snapshot()
	local saved = snapshot.confirmed
	if not saved then return end
	local state = saved.data.state
	local worker = saved.data.progress.firstWorker
	local permit = saved.data.progress.firstBelt
	local installedBelt = permit ~= nil
	if beltPrompt then beltPrompt.ActionText = if installedBelt then "Förderband ansehen" else "Installieren · " .. Belts.PRICE end
	if powerPrompt then
		powerPrompt.Enabled = installedBelt
		powerPrompt.ActionText = if permit and permit.stopped then "Starten" else "Anhalten"
	end
	if installedBelt and beltRoute and not beltFixture then
		beltFixture = BeltRoute.spawn(beltRoute, demo)
		places.points[State.FIRST_BELT.carrier] = beltFixture.buffer
	end
	local fixture = beltFixture
	if fixture and not beltShift then
		local shift = BeltShift.new(fixture, demo)
		beltShift = shift
		task.spawn(function()
			while not closing and demo.Parent and fixture.model.Parent do
				if not busy then BeltShift.tick(shift, controller, TTL) end
				task.wait(0.25)
			end
		end)
	end
	if beltShift then beltShift.powered = permit ~= nil and not permit.stopped end
	local hired = worker ~= nil
	local assigned = worker ~= nil and worker.assigned == true
	if hirePrompt then hirePrompt.ActionText = if hired then "Anstellung ansehen" else "Anstellen · " .. Workers.PRICE end
	if assignPrompt then
		assignPrompt.ActionText = if workerShift and workerShift.paused then "Weg erneut versuchen"
			elseif assigned then "Route ansehen" else "Route zuweisen"
	end
	local route = workerRoute
	if assigned and route and not workerStarted then
		workerStarted = true
		task.spawn(function()
			local workerRig = restoredWorker
			if not workerRig then
				local ok, rig = pcall(WorkerRoute.spawn, route, demo)
				if not ok then
					lastMessage = "Der Mitarbeiter konnte nicht erscheinen."
					warn(rig)
					return
				end
				workerRig = rig
			end
			if closing then return end
			local shift = WorkerShift.new(route, workerRig, restoredWorker ~= nil)
			workerShift = shift
			places.carriers[State.FIRST_WORKER.carrier] = workerRig.root
			local point = Instance.new("Attachment")
			point.Name = "WorkerRecoveryPoint"
			point.Position = Vector3.new(0, 0.25, -0.9)
			point.Parent = workerRig.root
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "P0805RecoverWorker"
			prompt.ObjectText = "Bausatz beim Mitarbeiter"
			prompt.ActionText = "Übernehmen"
			prompt.KeyboardKeyCode = Enum.KeyCode.G
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
			prompt.MaxActivationDistance = 6
			prompt.Enabled = false
			prompt.Parent = point
			workerRecoveryPrompt = prompt
			local function recover(user: Player): HandMoves.Result
				if user ~= player or busy or closing or not shift.paused or not workerCargo then
					return {ok = false, code = "NOT_READY", message = "Bergung derzeit nicht verfügbar."}
				end
				local reach = HandMoves.checkReach(user, {point = point}, true, workerRig.model)
				if reach then
					lastMessage = reach.message
					return reach
				end
				busy = true
				local ran, result = pcall(WorkerTransport.recover, controller, user.UserId, hand,
					"worker/recover/" .. http:GenerateGUID(false), os.time(), TTL)
				busy = false
				local recovered = ran and result.ok
				if recovered then shift.status = "Bausatz übernommen" end
				local code = if ran then result.code else "ERROR"
				lastMessage = if recovered then "Bausatz übernommen. Lege ihn an der Montage ab."
					elseif code == "TARGET_FULL" then "Lege zuerst die Ware in deiner Hand ab."
					else "Bausatz gerade nicht übernehmbar."
				return {ok = recovered, code = code, message = lastMessage}
			end
			prompt.Triggered:Connect(recover)
			local hook = Instance.new("BindableFunction")
			hook.Name = "P0805Recover"
			hook.OnInvoke = function(): HandMoves.Result
				while busy do task.wait() end
				return recover(player)
			end
			hook.Parent = serverStorage
			while not closing and demo.Parent and workerRig.model.Parent do
				if not busy then WorkerShift.tick(shift, controller, TTL) end
				task.wait(0.25)
			end
		end)
	end
	LineView.syncWares(demo, state, places)
	if workerShift then
		local hold = state.reservations[WorkerRoute.SOURCE]
		local cargo = if hold and hold.kind == "Return" and hold.carrierId == State.FIRST_WORKER.carrier then hold.batchId else nil
		if cargo ~= workerCargo then
			workerShift.rig.root:SetNetworkOwner(nil)
			workerCargo = cargo
		end
		if workerRecoveryPrompt then workerRecoveryPrompt.Enabled = workerShift.paused and cargo ~= nil end
	end
	local load = if loading then Vehicles.load(state, loading.slots.slotIds) else nil
	if load and loading then
		-- Adding or removing view welds can rebuild the assembly and restore automatic ownership.
		for _, slotId in loading.slots.slotIds do
			if mountedCargo[slotId] ~= load.batches[slotId] then
				Vehicles.useServerPhysics(loading.vehicle)
				break
			end
		end
		mountedCargo = load.batches
	end
	if trips then
		if snapshot.status == "Confirmed" and not snapshot.inFlight then
			Trips.sample(trips, state, os.clock())
		elseif snapshot.unknown then
			trips = Trips.new(trips.binding)
		end
	end
	LineView.syncSigns(demo, state, os.time(), places)
	local held = heldBatch(state)
	local store = Line.storeStatus(state, storeSlots)
	local target = if held then nextTarget[held.stage] else nil
	if loading and held then
		for id, reservation in state.reservations do
			if reservation.kind ~= "Return" or reservation.batchId ~= held.id then continue end
			local origin = state.locations[id].kind
			if origin == "Supplier" or origin == "FinishedStore" then target = "Anhänger" end
			if origin == "VehicleSlot" then target = if held.stage == "Karton" then "Fertiglager" else "Passende Holzablage" end
		end
	end
	local sale = state.pendingSale
	local selling = sale ~= nil and held ~= nil and held.id == sale.batchId
	if sale and selling then target = buyerNames[sale.buyer] .. " · Annahme" end
	banner.Text = (if held then "In der Hand: " .. Recipe.stageNames[held.stage] .. " · Ziel: " .. (target or "Auflage")
		else "Hand frei · E an einer Auflage drücken") .. " · Fertiglager " .. store.used .. "/" .. store.capacity
		.. (if load then " · Anhänger " .. load.used .. "/" .. load.capacity .. " · Guthaben " .. state.money else "")
		.. (if state.advance then " · Vorschuss offen: " .. state.advance.amount else "")
		.. (if beltShift then " · Band: " .. beltShift.status else "")
		.. (if assigned then " · Mitarbeiter: " .. (if workerShift then workerShift.status else "Startet")
			elseif hired then " · 1 Mitarbeiter" else "")
		.. "\n" .. (if sale then offerText(sale) .. "\n" else "") .. lastMessage
	for buyer, prompt in salePrompts do
		prompt.Enabled = selling and sale ~= nil and sale.buyer == buyer
		if sale and sale.buyer == buyer then prompt.ObjectText = offerText(sale) end
	end
	for _, prompt in prompts do prompt.ActionText = if held then "Ablegen" else "Aufnehmen" end
end

local saleActor = {ready = true, kind = "Player", ownerUserId = player.UserId,
	actorId = "Player/" .. string.format("%.0f", player.UserId), carrierLocationId = hand}
local function saleResponse(result: Sales.Result): HandMoves.Result
	return {ok = result.ok, code = result.code, message = result.message}
end
-- Trailer slots in a buyer yard and the sale carton's way back use the sales path instead of unloading.
-- seed and force come only from the server test hook.
local function saleMove(user: Player, state: any, id: string, direction: "Take" | "Put", fromRecovery: boolean?,
	seed: number?, force: boolean?): HandMoves.Result?
	if not loading or not trips then return nil end
	local sale = state.pendingSale
	local held = heldBatch(state)
	if direction == "Put" then
		if not sale or not held or held.id ~= sale.batchId then return nil end
		-- The sale carton leaves the hand only back onto its own slot (trailer mount or its recovery pad) or at the buyer.
		if id ~= sale.slotId then
			return {ok = false, code = "WRONG_LOADING_ROUTE",
				message = "Lege den Karton auf seinen Anhängerplatz zurück oder bestätige den Verkauf an der Annahme."}
		end
		local recovery = recoveryPoints[id]
		local endpoint: HandMoves.Endpoint? = if fromRecovery then recoveryEndpoints[id] else {point = loading.slots.mounts[id]}
		if not endpoint or not endpoint.point then
			return {ok = false, code = "UNKNOWN_LOCATION", message = "Dieser Übergabeplatz ist nicht verfügbar."}
		end
		if not fromRecovery then
			if loading.vehicle:GetAttribute("OwnerUserId") ~= user.UserId then
				return {ok = false, code = "NOT_VEHICLE_OWNER", message = "Dieses Fahrzeug gehört dir nicht."}
			end
			if not Vehicles.motion(loading.vehicle, loading.slots, loading.chassis) then
				return {ok = false, code = "VEHICLE_MOVING", message = "Halte vor dem Be- oder Entladen an."}
			end
		end
		local reach = HandMoves.checkReach(user, endpoint, not fromRecovery)
		if reach then return reach end
		local result = Sales.cancel(controller, saleActor, sale.id, os.time(), TTL)
		if result.ok then
			openedHere[sale.id] = nil
			if recovery and not fromRecovery then -- Back on the real trailer: the recovery pad has done its job.
				recoveryPoints[id] = nil
				recoveryEndpoints[id] = nil
				places.points[id] = nil
				local prompt = prompts["Recovery:" .. id]
				if prompt then prompt:Destroy(); prompts["Recovery:" .. id] = nil end
			end
		end
		return saleResponse(result)
	end
	if fromRecovery or recoveryPoints[id] or not loading.slots.mounts[id] then return nil end
	local mount = loading.slots.mounts[id]
	local zone = Vehicles.zone(loading.slots, buyerZones)
	if not zone then
		return if force then {ok = false, code = "NOT_AT_BUYER", message = "Parke beide Anhängerplätze im Hof des Käufers."}
			else nil
	end
	if held then return {ok = false, code = "HANDS_FULL", message = "Lege zuerst deine getragene Charge ab."} end
	local reach = HandMoves.checkReach(user, {point = mount}, true)
	if reach then return reach end
	local stock: any = nil
	for _, batch in state.batches do if batch.locationId == id then stock = batch end end
	if not stock then return {ok = false, code = "EMPTY", message = "An dieser Auflage liegt keine Charge."} end
	local arrival = if trips then Trips.arrival(trips, state, id, zone, os.clock()) else nil
	local result = Sales.open(controller, saleActor, {id = "sale/" .. http:GenerateGUID(false), buyer = zone :: any,
		vehicleId = loading.slots.vehicleId, slotId = id, batchId = stock.id}, arrival, os.time(), TTL, seed)
	if result.ok and result.offer then openedHere[result.offer.saleId] = true end
	return saleResponse(result)
end
local function interact(user: Player, id: string, direction: "Take" | "Put", fromRecovery: boolean?, seed: number?,
	force: boolean?): HandMoves.Result
	if closing then return {ok = false, code = "NOT_READY", message = "Spielstand wird geschlossen."} end
	assert(not busy, "Interaction already running")
	busy = true
	local ran, outcome = pcall(function(): HandMoves.Result
		local snapshot = controller.snapshot()
		local current = snapshot.confirmed
		if not current or snapshot.status ~= "Confirmed" or snapshot.inFlight then
			return {ok = false, code = "NOT_READY", message = "Speichern unklar – bitte warten."}
		end
		local selling = saleMove(user, current.data.state, id, direction, fromRecovery, seed, force)
		if selling then return selling end
		local store = Transfers.new(current.data.state)
		local registry = if fromRecovery then recoveryEndpoints else endpoints
		local check = HandMoves.interact(store, user, true, hand, registry, id, direction, http:GenerateGUID(false), os.time(), loading)
		if check.ok then
			local proposal = current.data
			proposal.state = store.profile
			local saved = controller.save(proposal, TTL)
			if not saved.ok then
				check = {ok = false, code = saved.code, message = "Speichern unklar – bitte warten."}
			elseif not fromRecovery and direction == "Put" and recoveryPoints[id] then
				recoveryPoints[id] = nil
				recoveryEndpoints[id] = nil
				places.points[id] = nil
				local prompt = prompts["Recovery:" .. id]
				if prompt then prompt:Destroy(); prompts["Recovery:" .. id] = nil end
			end
		end
		return check
	end)
	busy = false
	local check: HandMoves.Result = if ran then outcome
		else {ok = false, code = "ERROR", message = "Interner Fehler: " .. tostring(outcome)}
	lastMessage = check.message
	render()
	return check
end

local last = -math.huge
local function addPrompt(id: string, endpoint: HandMoves.Endpoint, fromRecovery: boolean)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "P0509Line"
	prompt.ObjectText = if fromRecovery then "Bergung · Platz " .. id:sub(-1) else names[id]
	prompt.ActionText = "Aufnehmen"
	prompt.MaxActivationDistance = 6
	local vehicleSlot = not fromRecovery and loading ~= nil and loading.slots.mounts[id] ~= nil
	prompt.RequiresLineOfSight = not vehicleSlot
	if vehicleSlot then prompt:SetAttribute("TrailerSlot", true) end
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = endpoint.point
	collection:AddTag(prompt, "P0509FacingPrompt")
	prompts[if fromRecovery then "Recovery:" .. id else id] = prompt
	prompt.Triggered:Connect(function(user)
		if user ~= player or busy or closing or os.clock() - last < 0.4 then return end
		last = os.clock()
		interact(user, id, if heldBatch(confirmed().data.state) then "Put" else "Take", fromRecovery)
	end)
end
for id, endpoint in endpoints do addPrompt(id, endpoint, false) end
for id, endpoint in recoveryEndpoints do addPrompt(id, endpoint, true) end

-- Binding handoff at the buyer pad. The price stays hidden until the settlement save is confirmed.
local function settleSale(user: Player, buyer: string): HandMoves.Result
	if user ~= player or busy or closing then return {ok = false, code = "NOT_READY", message = "Verkauf gerade nicht verfügbar."} end
	busy = true
	local ran, outcome = pcall(function(): HandMoves.Result
		local state = confirmed().data.state
		local sale = state.pendingSale
		local held = heldBatch(state)
		if not sale or not held or held.id ~= sale.batchId then
			return {ok = false, code = "SALE_NOT_FOUND", message = "Nimm zuerst im Käuferhof einen Karton vom Anhänger."}
		end
		if sale.buyer ~= buyer then
			return {ok = false, code = "WRONG_BUYER", message = "Dieser Karton ist für " .. buyerNames[sale.buyer] .. " bestimmt."}
		end
		if not openedHere[sale.id] then
			return {ok = false, code = "PICKUP_REQUIRED", message = "Lege den Karton zurück auf den Anhänger und liefere ihn erneut an."}
		end
		local reach = HandMoves.checkReach(user, buyerPads[buyer])
		if reach then return reach end
		local result = Sales.settle(controller, saleActor, sale.id, TTL)
		if result.unknown then unclearSale = sale.id end
		local receipt = result.receipt
		if result.ok and receipt then
			openedHere[sale.id] = nil
			return {ok = true, code = result.code,
				message = "Verkauft an " .. buyerNames[buyer] .. ": 1 Hocker für " .. receipt.amount .. "." .. repaidText(receipt)}
		end
		return saleResponse(result)
	end)
	busy = false
	local response: HandMoves.Result = if ran then outcome
		else {ok = false, code = "ERROR", message = "Interner Fehler: " .. tostring(outcome)}
	lastMessage = response.message
	render()
	return response
end
if loading then
	for buyer, endpoint in buyerPads do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "P07Sell"
		prompt.ObjectText = buyerNames[buyer] .. " · Annahme"
		prompt.ActionText = "Verkauf bestätigen"
		prompt.HoldDuration = 1
		prompt.MaxActivationDistance = 6
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Enabled = false
		prompt.Parent = endpoint.point
		salePrompts[buyer] = prompt
		prompt.Triggered:Connect(function(user)
			if user ~= player or busy or os.clock() - last < 0.4 then return end
			last = os.clock()
			settleSale(user, buyer)
		end)
	end
	render()
end

if purchaseSlots then
	local slots = purchaseSlots
	local endpoint = endpoints[slots.supplierIds[1]]
	local purchaseStatus = {NOT_ENOUGH_MONEY = "Dein Guthaben reicht für kein weiteres Holzpaket.",
		SUPPLIER_FULL = "Beim Lieferanten ist kein Abholplatz frei.",
		RAW_STORE_FULL = "Im Rohstofflager kann kein Platz für die Lieferung reserviert werden."}
	local advanceStatus = {MONEY_AVAILABLE = "Dein Guthaben reicht für einen regulären Einkauf (R).",
		STOCK_AVAILABLE = "Du hast noch Holz oder Ware. Der Vorschuss hilft nur einem leeren Betrieb.",
		ADVANCE_OPEN = "Dein Materialvorschuss ist noch offen. Der Verkauf dieser Charge verrechnet ihn.",
		SALE_OPEN = "Schließe zuerst den offenen Verkauf ab.",
		NOT_CONFIRMED = "Speichern unklar – bitte warten.", WRITE_UNKNOWN = "Speichern unklar – bitte warten.",
		SUPPLIER_FULL = purchaseStatus.SUPPLIER_FULL, RAW_STORE_FULL = purchaseStatus.RAW_STORE_FULL}
	-- Buying and the material advance share the reach check at the first pickup, the busy guard and the receipt text.
	local function supply(user: Player, claim: (Persistence.Controller, any, any, Purchases.Slots, number) -> any,
		statuses: {[string]: string}, fallback: string): HandMoves.Result
		if user ~= player or busy or closing then return {ok = false, code = "NOT_READY", message = fallback} end
		local reachProblem = HandMoves.checkReach(user, endpoint)
		if reachProblem then
			lastMessage = reachProblem.message
			render()
			return reachProblem
		end
		busy = true
		local ran, outcome = pcall(function(): HandMoves.Result
			local actor = {kind = "Player", actorId = "Player/" .. string.format("%.0f", user.UserId),
				ownerUserId = user.UserId, ready = true}
			local result = claim(controller, actor, {operationId = http:GenerateGUID(false),
				expectedRevision = confirmed().data.state.revision}, slots, TTL)
			return {ok = result.ok, code = result.code, message = if result.receipt then result.receipt.message
				else (statuses[result.code] or fallback)}
		end)
		busy = false
		local response = if ran then outcome else {ok = false, code = "ERROR", message = fallback}
		lastMessage = response.message
		render()
		return response
	end
	local function buy(user: Player): HandMoves.Result
		return supply(user, Purchases.buy, purchaseStatus, "Kauf gerade nicht verfügbar.")
	end
	local function advance(user: Player): HandMoves.Result
		return supply(user, Purchases.advance, advanceStatus, "Vorschuss gerade nicht verfügbar.")
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "P060405BuyWood"
	prompt.ObjectText = "1 Holzpaket"
	prompt.ActionText = "Kaufen · " .. Purchases.PRICE
	prompt.MaxActivationDistance = 6
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = endpoint.point
	collection:AddTag(prompt, "P0509FacingPrompt")
	prompt.Triggered:Connect(function(user)
		if user ~= player or busy or os.clock() - last < 0.4 then return end
		last = os.clock()
		buy(user)
	end)
	local test = Instance.new("BindableFunction")
	test.Name = "P060405Purchase"
	test.OnInvoke = function(): HandMoves.Result return buy(player) end
	test.Parent = game:GetService("ServerStorage")
	-- P07-07: a separate prompt beside the buy prompt; the server decides eligibility and explains refusals.
	local advancePrompt = Instance.new("ProximityPrompt")
	advancePrompt.Name = "P0707AdvanceWood"
	advancePrompt.ObjectText = "Materialvorschuss"
	advancePrompt.ActionText = "1 Holzpaket · ohne Geld"
	advancePrompt.MaxActivationDistance = 6
	advancePrompt.KeyboardKeyCode = Enum.KeyCode.F
	advancePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	advancePrompt.UIOffset = Vector2.new(0, 80) -- Shares the pickup point with the E and R prompts.
	advancePrompt.Parent = endpoint.point
	collection:AddTag(advancePrompt, "P0509FacingPrompt")
	advancePrompt.Triggered:Connect(function(user)
		if user ~= player or busy or os.clock() - last < 0.4 then return end
		last = os.clock()
		advance(user)
	end)
	local advanceTest = Instance.new("BindableFunction")
	advanceTest.Name = "P0707Advance"
	advanceTest.OnInvoke = function(): HandMoves.Result return advance(player) end
	advanceTest.Parent = game:GetService("ServerStorage")
end

if logisticsEnabled then
	local messages = {
		HIRED = "Mitarbeiter angestellt.",
		ALREADY_HIRED = "Dein Mitarbeiter ist bereits angestellt.",
		ASSIGNED = "Arbeitsweg zugewiesen: Sägeausgang → Montageeingang.",
		ALREADY_ASSIGNED = "Dein Mitarbeiter hat bereits den Weg von der Säge zur Montage.",
		NOT_HIRED = "Stelle zuerst am Fertiglager einen Mitarbeiter an.",
		BELT_INSTALLED = "Förderband zwischen Säge und Montage installiert.",
		BELT_OWNED = "Dieses Förderband ist bereits installiert.",
		NOT_ENOUGH_FOR_BELT = "Das Förderband kostet " .. Belts.PRICE .. " Spielgeld.",
		BELT_NOT_INSTALLED = "Installiere zuerst das Förderband.",
		BELT_STOPPED = "Förderband angehalten.",
		BELT_RUNNING = "Förderband gestartet.",
		NOT_ENOUGH_MONEY = "Die Anstellung kostet " .. Workers.PRICE .. " Spielgeld.",
		NOT_CONFIRMED = "Speichern unklar – bitte warten.",
		WRITE_UNKNOWN = "Speichern unklar – bitte warten.",
	} :: {[string]: string}
	local function workshopPrompt(name: string, label: string, key: Enum.KeyCode, gamepad: Enum.KeyCode,
		endpoint: HandMoves.Endpoint, action: (Persistence.Controller, number, number, number) -> {ok: boolean, code: string},
		promptName: string, facingOnly: boolean?): ProximityPrompt
		local fallback = "Diese Aktion ist gerade nicht verfügbar."
		local function interactWorkshop(user: Player): HandMoves.Result
			if user ~= player or busy or closing then
				return {ok = false, code = "NOT_READY", message = fallback}
			end
			local problem = HandMoves.checkReach(user, endpoint)
			if problem then
				lastMessage = problem.message
				render()
				return problem
			end
			busy = true
			local ran, result = pcall(action, controller, user.UserId, confirmed().data.state.revision, TTL)
			busy = false
			local code = if ran then result.code else "ERROR"
			lastMessage = messages[code] or fallback
			if code == "ALREADY_ASSIGNED" and workerShift and workerShift.paused then
				WorkerShift.retry(workerShift)
				lastMessage = "Der Mitarbeiter versucht es erneut."
			end
			render()
			return {ok = ran and result.ok, code = code, message = lastMessage}
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = promptName
		prompt.ObjectText = label
		prompt.KeyboardKeyCode, prompt.GamepadKeyCode = key, gamepad
		prompt.MaxActivationDistance = 6
		prompt.Parent = endpoint.point
		if facingOnly ~= false then collection:AddTag(prompt, "P0509FacingPrompt") end
		prompt.Triggered:Connect(interactWorkshop)
		local hook = Instance.new("BindableFunction")
		hook.Name = name
		hook.OnInvoke = function(): HandMoves.Result
			while busy do task.wait() end
			return interactWorkshop(player)
		end
		hook.Parent = serverStorage
		return prompt
	end
	hirePrompt = workshopPrompt("P0801Hire", "Erster Mitarbeiter", Enum.KeyCode.H, Enum.KeyCode.ButtonL1,
		endpoints["FinishedStore.Slot2"], Workers.hire, "P0801HireWorker")
	assignPrompt = workshopPrompt("P0802Assign", "Sägeausgang → Montageeingang", Enum.KeyCode.J, Enum.KeyCode.ButtonR1,
		endpoints[WorkerRoute.SOURCE], Workers.assign, "P0802AssignWorker")
	beltPrompt = workshopPrompt("P0901Belt", "Förderband · Säge → Montage", Enum.KeyCode.B, Enum.KeyCode.ButtonL2,
		endpoints[State.FIRST_BELT.source], Belts.install, "P0901InstallBelt")
	powerPrompt = workshopPrompt("P0905Power", "Förderband", Enum.KeyCode.T, Enum.KeyCode.ButtonR2,
		endpoints[State.FIRST_BELT.source], Belts.toggle, "P0905BeltPower", false)
end

-- Facing station rows share one aisle stand marker (e.g. Montage.Output / Finish.Input, both 4.3 studs away).
-- The client offers only prompts in front of the avatar, so E always means the station the player faces.
local facing = Instance.new("LocalScript")
facing.Name = "P0509Facing"
facing.Source = [[
local player = game:GetService("Players").LocalPlayer
local collection = game:GetService("CollectionService")
local prompts = {}
local refreshed = -math.huge
game:GetService("RunService").RenderStepped:Connect(function()
	if os.clock() - refreshed > 2 then
		refreshed = os.clock()
		prompts = collection:GetTagged("P0509FacingPrompt")
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local look = (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local trailerPrompt, trailerScore = nil, -math.huge
	for _, prompt in prompts do
		local point = prompt.Parent
		if point and point:IsA("Attachment") then
			local offset = point.WorldPosition - root.Position
			local toward = offset * Vector3.new(1, 0, 1)
			local score = if toward.Magnitude < 0.01 then 1 else look:Dot(toward.Unit)
			if prompt:GetAttribute("TrailerSlot") then
				if score > 0.35 and offset.Magnitude <= prompt.MaxActivationDistance and score > trailerScore then
					trailerPrompt, trailerScore = prompt, score
				end
			else
				prompt.Enabled = score > 0.35
			end
		end
	end
	for _, prompt in prompts do
		if prompt:GetAttribute("TrailerSlot") then prompt.Enabled = prompt == trailerPrompt end
	end
end)
]]
facing.Parent = playerGui

-- Real-time line: finish due runs, start ready stations, refresh signs; keep the session alive.
local accumulated = 0
local ticks = 0
rs.Heartbeat:Connect(function(dt: number)
	accumulated += dt
	if accumulated < 0.25 or busy or closing or not demo.Parent then return end
	accumulated = 0
	busy = true
	local ran, problem = pcall(function()
		local state = controller.snapshot()
		if state.unknown and not state.inFlight then
			-- Clarify an unclear write before any further action; a landed settlement shows its stored receipt.
			if os.clock() - lastReconcile < 2 then return end
			lastReconcile = os.clock()
			local resumed = Sales.resume(controller, saleActor, unclearSale)
			if resumed.ok then
				local receipt = resumed.receipt
				-- An unclear advance write is clarified here too; a landed advance then shows in the banner.
				lastMessage = if receipt then "Verkauf bestätigt: 1 Hocker für " .. receipt.amount .. "." .. repaidText(receipt)
					else "Spielstand geklärt."
				unclearSale = nil
			else
				lastMessage = "Speichern unklar – bitte warten."
			end
			return
		end
		local now = os.time()
		local saved = confirmed()
		if saved and saved.expiresAt - now < 120 then controller.save(saved.data, TTL) end
		for _, event in Line.tick(controller, now, TTL) do
			if not event.ok then lastMessage = "Linie angehalten: " .. event.code end
		end
	end)
	if not ran then lastMessage = "Linie angehalten: " .. tostring(problem) end
	ticks += 1
	busy = false
	render()
end)
-- Trip evidence keeps observing while a save is in flight: a slow DataStore write must not open a gap
-- that clears every slot's trip. Only an unclear save outcome resets the evidence.
local tripClock = 0
rs.Heartbeat:Connect(function(dt: number)
	tripClock += dt
	if tripClock < 0.25 or not trips or closing or not demo.Parent then return end
	tripClock = 0
	local snapshot = controller.snapshot()
	if snapshot.unknown then
		trips = Trips.new(trips.binding)
	elseif snapshot.status == "Confirmed" and snapshot.confirmed then
		Trips.sample(trips, snapshot.confirmed.data.state, os.clock())
	end
end)
render()

-- Server-only hook for the automated proof. Players use the native prompts.
local hook = Instance.new("BindableFunction")
hook.Name = "P0509LineTest"
hook.OnInvoke = function(id: string, direction: "Take" | "Put", fromRecovery: boolean?): any
	while busy do task.wait() end
	local response = interact(player, id, direction, fromRecovery)
	local state = confirmed().data.state
	return {result = response, revision = state.revision, held = heldBatch(state), batches = state.batches,
		reservations = state.reservations, banner = banner.Text, ticks = ticks}
end
hook.Parent = game:GetService("ServerStorage")
if loading then
	local saleHook = Instance.new("BindableFunction")
	saleHook.Name = "P07SaleTest"
	saleHook.OnInvoke = function(action: string, arg: any, seed: number?): any
		while busy do task.wait() end
		local response: any
		if action == "open" then
			response = interact(player, arg, "Take", false, seed, true)
		elseif action == "settle" then
			response = settleSale(player, arg)
		elseif action == "replay" then
			response = Sales.settle(controller, saleActor, arg, TTL)
		else
			error("Unknown sale test action " .. tostring(action))
		end
		return {result = response, banner = banner.Text}
	end
	saleHook.Parent = serverStorage
end
local reader = Instance.new("BindableFunction")
reader.Name = "P0509LineState"
reader.OnInvoke = function(): any
	local state = confirmed().data.state
	local signs = {}
	for _, board in demo.Signs:GetChildren() do
		local head = board:FindFirstChild("Head") :: TextLabel
		signs[board.Name] = {code = board:GetAttribute("StatusCode"), head = head.Text}
	end
	local views = {}
	for _, view in demo.Wares:GetChildren() do
		views[view.Name] = {signature = view:GetAttribute("Signature"), carried = view:FindFirstChildWhichIsA("WeldConstraint", true) ~= nil}
	end
	local arrivals: {[string]: Trips.Arrival} = {}
	if trips then
		local snapshot = controller.snapshot()
		if snapshot.status == "Confirmed" and not snapshot.inFlight then
			for _, id in trips.binding.slots.slotIds do
				arrivals[id] = Trips.arrival(trips, state, id, "Dealer", os.clock())
					or Trips.arrival(trips, state, id, "Private", os.clock())
			end
		end
	end
	local saleReceipts = {}
	local advanceReceipts = {}
	local workerReceipts = {}
	local beltReceipts = {}
	for id, receipt in state.receipts do
		if receipt.action == "Sale" then saleReceipts[id] = receipt.result end
		if receipt.action == "Advance" then advanceReceipts[id] = receipt.result end
		if receipt.action == "Commit" and receipt.actorId == State.FIRST_WORKER.carrier then
			workerReceipts[id] = receipt.result
		end
		if receipt.action == "Commit" and receipt.actorId == State.FIRST_BELT.carrier then beltReceipts[id] = receipt.result end
	end
	local sellPrompts = {}
	for buyer, prompt in salePrompts do sellPrompts[buyer] = {enabled = prompt.Enabled, text = prompt.ObjectText} end
	return {batches = state.batches, reservations = state.reservations, money = state.money, revision = state.revision, valid = State.validate(state),
		banner = banner.Text, ticks = ticks, signs = signs, views = views, recoverySlots = next(recoveryPoints) ~= nil, arrivals = arrivals,
		pendingSale = state.pendingSale, saleReceipts = saleReceipts, sellPrompts = sellPrompts,
		advance = state.advance, advanceReceipts = advanceReceipts, firstWorker = confirmed().data.progress.firstWorker,
		workerStatus = if workerShift then workerShift.status else nil,
		workerPaused = workerShift ~= nil and workerShift.paused, workerAttempts = if workerShift then workerShift.attempts else 0,
		workerReceipts = workerReceipts, claims = state.claims, firstBelt = confirmed().data.progress.firstBelt,
		beltLocation = state.locations[State.FIRST_BELT.carrier], beltReceipts = beltReceipts,
		beltStatus = if beltShift then beltShift.status else nil}
end
reader.Parent = game:GetService("ServerStorage")
if resumeRig then
	local function release(): Persistence.Result
		if closing then return controller.snapshot() end
		closing = true
		if workerShift then WorkerShift.stop(workerShift) end
		if beltShift then beltShift.closing = true end
		while busy or controller.snapshot().inFlight do task.wait() end
		return controller.release()
	end
	local releaseHook = Instance.new("BindableFunction")
	releaseHook.Name = "P0607Release"
	releaseHook.OnInvoke = release
	releaseHook.Parent = serverStorage
	players.PlayerRemoving:Connect(function(leaving)
		if leaving == player then release() end
	end)
	game:BindToClose(function() release() end)
end
local entrance = line.Route:FindFirstChild("01_Eingang")
if entrance and entrance:IsA("BasePart") then
	local position = entrance.Position + Vector3.new(0, 3, 0)
	local focus = Vector3.new(line.Stores.Rohstofflager.Slot1.Position.X, position.Y, line.Stores.Rohstofflager.Slot1.Position.Z)
	character:PivotTo(CFrame.lookAt(position, focus))
end
local promptCount = 0
for _ in prompts do promptCount += 1 end
return {demo = "P0509LineDemo", playerReady = true, prompts = promptCount, storage = resumeRig ~= nil,
	logistics = logisticsEnabled, recoveryYard = recoveryYard, testStock = if loading then {} else {"Testholz-1", "Testholz-2"}}
