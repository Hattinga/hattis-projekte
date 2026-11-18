--!strict
-- P05-09 manual Studio-play demo: complete hand line with marked test stock, real-time line ticks and views.
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
local Line = require(factory.Line)
local LineView = require(factory.LineView)
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

-- Registry from the physical fixtures: hand-reachable places, transfer points and signs.
local stations = assert(Recipe.bind(line.Stations))
local shelf = assert(Recipe.bindStore(line.Stores.Fertiglager, "FinishedStore", "Karton"))
local raw = assert(Recipe.bindStore(line.Stores.Rohstofflager, "RawStore", "Holzpaket"))
local endpoints: {[string]: HandMoves.Endpoint} = {}
local names: {[string]: string} = {}
local places = {points = {}, carriers = {[hand] = body}, stationPads = {}, storeSlots = {},
	storePad = line.Stores.Fertiglager.Slot2}
for _, binding in {stations, shelf, raw} do
	for id, point in binding.points do places.points[id] = point end
end
for i = 1, 4 do
	for _, spec in {{"RawStore", line.Stores.Rohstofflager, "Rohstofflager"}, {"FinishedStore", line.Stores.Fertiglager, "Fertiglager"}} do
		local id = spec[1] .. ".Slot" .. i
		endpoints[id] = {point = places.points[id], stand = (spec[2] :: any).Standpoints["Slot" .. i]}
		names[id] = spec[3] .. " · Platz " .. i
	end
	table.insert(places.storeSlots, "FinishedStore.Slot" .. i)
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

-- Marked test stock (QA-P05-02): two wood packages in the raw store; purchase and delivery are P05-02/P06.
local profile = State.newProfile(player.UserId)
for _, binding in {stations, shelf, raw} do
	for id, location in binding.locations do profile.locations[id] = location end
end
profile.locations[hand] = State.newLocation(hand, "Carrier", 1, {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"})
for i = 1, 2 do
	local id = "Testholz-" .. i
	profile.batches[id] = State.newBatch(id, player.UserId, "Holzpaket", "RawStore.Slot" .. i)
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
local lastMessage = "Testholz am Rohstofflager mit E aufnehmen."
local function heldBatch(state: any): any
	for _, batch in state.batches do if batch.locationId == hand then return batch end end
	return nil
end
local function render()
	local state = confirmed().data.state
	LineView.syncWares(demo, state, places)
	LineView.syncSigns(demo, state, os.time(), places)
	local held = heldBatch(state)
	local store = Line.storeStatus(state, places.storeSlots)
	banner.Text = (if held then "In der Hand: " .. Recipe.stageNames[held.stage] .. " · Ziel: " .. nextTarget[held.stage]
		else "Hand frei · E an einer Auflage drücken") .. " · Fertiglager " .. store.used .. "/" .. store.capacity
		.. "\n" .. lastMessage
	for _, prompt in prompts do prompt.ActionText = if held then "Ablegen" else "Aufnehmen" end
end

local busy = false
local function interact(user: Player, id: string, direction: "Take" | "Put"): HandMoves.Result
	assert(not busy, "Interaction already running")
	busy = true
	local ran, outcome = pcall(function(): HandMoves.Result
		local store = Transfers.new(confirmed().data.state)
		local check = HandMoves.interact(store, user, true, hand, endpoints, id, direction, http:GenerateGUID(false), os.time())
		if check.ok then
			local proposal = confirmed().data
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
	prompt.RequiresLineOfSight = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = endpoint.point
	prompts[id] = prompt
	prompt.Triggered:Connect(function(user)
		if user ~= player or busy or os.clock() - last < 0.4 then return end
		last = os.clock()
		interact(user, id, if heldBatch(confirmed().data.state) then "Put" else "Take")
	end)
end

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
	return {batches = state.batches, reservations = state.reservations, money = state.money, valid = State.validate(state),
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
	testStock = {"Testholz-1", "Testholz-2"}}
