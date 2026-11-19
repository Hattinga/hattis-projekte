--!strict
-- Studio-play demo: P05-09 with marked test stock, or P06-04/05 with purchases and the trailer.
-- Transient: in-memory persistence, no DataStore, everything disappears with Stop.
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
local Vehicles = require(factory.Vehicles)
local collection = game:GetService("CollectionService")
local http = game:GetService("HttpService")
local line = workspace.P02Line
local player = game:GetService("Players"):GetPlayers()[1]
assert(player and player.UserId > 0 and player.Character and player.Character:FindFirstChild("HumanoidRootPart"),
	"Wait for a signed-in Studio test player")
local playerGui = player:FindFirstChildOfClass("PlayerGui")
assert(playerGui and not workspace:FindFirstChild("P0509LineDemo"), "Demo already active or PlayerGui missing")
local character = player.Character
local body = character:FindFirstChild("HumanoidRootPart") :: BasePart
local hand = "Demo.Hand"
local TTL = 600
local logisticsEnabled = workspace:GetAttribute("P06LoadingDemo") == true

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
if logisticsEnabled then
	local vehicle = workspace.P02Vehicle
	local yards = workspace.CityGreybox.DeliveryYards
	local pickup = yards.Holzlieferant.P05Pickup
	local purchase = assert(Purchases.bind(pickup, line.Stores.Rohstofflager))
	local vehicleSlots = assert(Vehicles.bind(vehicle, vehicle:GetAttribute("VehicleId") :: string))
	local chassis = vehicle.Quad.Chassis :: BasePart
	loading = {vehicle = vehicle, slots = vehicleSlots, chassis = chassis, destinations = places.points, unloads = {},
		zones = {Supplier = yards.Holzlieferant.LoadZone.Volume, Workshop = yards.Tischlerei_West.LoadZone.Volume}}
	vehicle:SetAttribute("OwnerUserId", player.UserId)
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
	profile.money = 180 -- Only the in-memory test bankroll.
else
	for i = 1, 2 do
		local id = "Testholz-" .. i
		profile.batches[id] = State.newBatch(id, player.UserId, "Holzpaket", "RawStore.Slot" .. i)
	end
end
local stored: any = nil
local backend = {
	read = function(_: string): any return stored end,
	update = function(_: string, transform: (any) -> any): any
		local proposed = transform(stored)
		if proposed ~= nil then stored = proposed end
		return proposed
	end,
}
local controller = Persistence.new(player.UserId, backend)
assert(controller.load("demo/" .. http:GenerateGUID(false), TTL, function(): any
	return {profileVersion = 1, state = profile, progress = {version = 1, selectedRecipeId = "Hocker01", selectedRecipeVersion = 1}}
end).ok)
local function confirmed(): any return controller.snapshot().confirmed end

local demo = Instance.new("Folder")
demo.Name = "P0509LineDemo"
demo.Parent = workspace
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
local lastMessage = if loading then "Beim Holzlieferanten mit R kaufen und mit E verladen."
	else "Testholz am Rohstofflager mit E aufnehmen."
local function heldBatch(state: any): any
	for _, batch in state.batches do if batch.locationId == hand then return batch end end
	return nil
end
local function render()
	local state = confirmed().data.state
	LineView.syncWares(demo, state, places)
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
	local load = if loading then Vehicles.load(state, loading.slots.slotIds) else nil
	banner.Text = (if held then "In der Hand: " .. Recipe.stageNames[held.stage] .. " · Ziel: " .. (target or "Auflage")
		else "Hand frei · E an einer Auflage drücken") .. " · Fertiglager " .. store.used .. "/" .. store.capacity
		.. (if load then " · Anhänger " .. load.used .. "/" .. load.capacity .. " · Guthaben " .. state.money else "")
		.. "\n" .. lastMessage
	for _, prompt in prompts do prompt.ActionText = if held then "Ablegen" else "Aufnehmen" end
end

local busy = false
local function interact(user: Player, id: string, direction: "Take" | "Put"): HandMoves.Result
	assert(not busy, "Interaction already running")
	busy = true
	local ran, outcome = pcall(function(): HandMoves.Result
		local snapshot = controller.snapshot()
		local current = snapshot.confirmed
		if not current or snapshot.status ~= "Confirmed" or snapshot.inFlight then
			return {ok = false, code = "NOT_READY", message = "Speichern unklar – bitte warten."}
		end
		local store = Transfers.new(current.data.state)
		local check = HandMoves.interact(store, user, true, hand, endpoints, id, direction, http:GenerateGUID(false), os.time(), loading)
		if check.ok then
			local proposal = current.data
			proposal.state = store.profile
			local saved = controller.save(proposal, TTL)
			if not saved.ok then
				check = {ok = false, code = saved.code, message = "Speichern unklar – bitte warten."}
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
for id, endpoint in endpoints do
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "P0509Line"
	prompt.ObjectText = names[id]
	prompt.ActionText = "Aufnehmen"
	prompt.MaxActivationDistance = 6
	local vehicleSlot = loading ~= nil and loading.slots.mounts[id] ~= nil
	prompt.RequiresLineOfSight = not vehicleSlot
	if vehicleSlot then prompt:SetAttribute("TrailerSlot", true) end
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = endpoint.point
	collection:AddTag(prompt, "P0509FacingPrompt")
	prompts[id] = prompt
	prompt.Triggered:Connect(function(user)
		if user ~= player or busy or os.clock() - last < 0.4 then return end
		last = os.clock()
		interact(user, id, if heldBatch(confirmed().data.state) then "Put" else "Take")
	end)
end

if purchaseSlots then
	local slots = purchaseSlots
	local endpoint = endpoints[slots.supplierIds[1]]
	local purchaseStatus = {NOT_ENOUGH_MONEY = "Dein Guthaben reicht für kein weiteres Holzpaket.",
		SUPPLIER_FULL = "Beim Lieferanten ist kein Abholplatz frei.",
		RAW_STORE_FULL = "Im Rohstofflager kann kein Platz für die Lieferung reserviert werden."}
	local function buy(user: Player): HandMoves.Result
		if user ~= player or busy then return {ok = false, code = "NOT_READY", message = "Kauf gerade nicht verfügbar."} end
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
			local result = Purchases.buy(controller, actor, {operationId = http:GenerateGUID(false),
				expectedRevision = confirmed().data.state.revision}, slots, TTL)
			return {ok = result.ok, code = result.code, message = if result.receipt then result.receipt.message
				else ((purchaseStatus :: {[string]: string})[result.code] or "Kauf gerade nicht verfügbar.")}
		end)
		busy = false
		local response = if ran then outcome else {ok = false, code = "ERROR", message = "Kauf gerade nicht verfügbar."}
		lastMessage = response.message
		render()
		return response
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
	if accumulated < 0.25 or busy or not demo.Parent then return end
	accumulated = 0
	busy = true
	local ran, problem = pcall(function()
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
render()

-- Server-only hook for the automated proof. Players use the native prompts.
local hook = Instance.new("BindableFunction")
hook.Name = "P0509LineTest"
hook.OnInvoke = function(id: string, direction: "Take" | "Put"): any
	while busy do task.wait() end
	local response = interact(player, id, direction)
	local state = confirmed().data.state
	return {result = response, revision = state.revision, held = heldBatch(state), batches = state.batches,
		reservations = state.reservations, banner = banner.Text, ticks = ticks}
end
hook.Parent = game:GetService("ServerStorage")
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
	return {batches = state.batches, reservations = state.reservations, money = state.money, revision = state.revision, valid = State.validate(state),
		banner = banner.Text, ticks = ticks, signs = signs, views = views}
end
reader.Parent = game:GetService("ServerStorage")
local entrance = line.Route:FindFirstChild("01_Eingang")
if entrance and entrance:IsA("BasePart") then
	local position = entrance.Position + Vector3.new(0, 3, 0)
	local focus = Vector3.new(line.Stores.Rohstofflager.Slot1.Position.X, position.Y, line.Stores.Rohstofflager.Slot1.Position.Z)
	character:PivotTo(CFrame.lookAt(position, focus))
end
local promptCount = 0
for _ in prompts do promptCount += 1 end
return {demo = "P0509LineDemo", playerReady = true, prompts = promptCount, storage = false,
	logistics = logisticsEnabled, testStock = if loading then {} else {"Testholz-1", "Testholz-2"}}
