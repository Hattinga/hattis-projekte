--!strict
-- Manual Studio-play demo. Transient props, prompts and one artificial inventory.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsServer() and rs:IsRunning(), "Studio Server only")
local factory = game:GetService("ServerScriptService").Factory
local State = require(factory.State)
local Recipe = require(factory.Recipe)
local Transfers = require(factory.Transfers)
local HandMoves = require(factory.HandMoves)
local line = workspace.P02Line
local raw = line.Stores.Rohstofflager
local saw = line.Stations.Saege
local bench = line.Stations.Montage
local player = game:GetService("Players"):GetPlayers()[1]
assert(player and player.UserId > 0 and player.Character and player.Character:FindFirstChild("HumanoidRootPart"),
	"Wait for a signed-in Studio test player")
local playerGui = player:FindFirstChildOfClass("PlayerGui")
assert(playerGui and not workspace:FindFirstChild("P0503HandDemo"), "Demo already active or PlayerGui missing")
local character = player.Character
local hand = "Demo.Hand"
local endpoints: {[string]: HandMoves.Endpoint} = {
	["RawStore.Slot1"] = {point = raw.Slot1.Transfer, stand = raw.Standpoints.Slot1},
	["RawStore.Slot2"] = {point = raw.Slot2.Transfer, stand = raw.Standpoints.Slot2},
	["Saege.Input"] = {point = saw.Input.Transfer, stand = saw.Standpoints.Input},
	["Montage.Input"] = {point = bench.Input.Transfer, stand = bench.Standpoints.Input},
}
local stationBinding = assert(Recipe.bind(line.Stations))
local profile = State.newProfile(player.UserId)
profile.locations = stationBinding.locations
profile.locations[hand] = State.newLocation(hand, "Carrier", 1, {"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"})
for index = 1, 2 do
	local id = "RawStore.Slot" .. index
	profile.locations[id] = State.newLocation(id, "RawStore", 1, {"Holzpaket"})
	local batchId = "Holzpaket-" .. index
	profile.batches[batchId] = State.newBatch(batchId, player.UserId, "Holzpaket", id)
end
local store = Transfers.new(profile)
local demo = Instance.new("Folder")
demo.Name = "P0503HandDemo"
demo.Parent = workspace
local stock = Instance.new("Folder")
stock.Name = "StockViews"
stock.Parent = demo
local gui = Instance.new("ScreenGui")
gui.Name = "P0503HandDemo"
gui.ResetOnSpawn = false
gui.Parent = playerGui
local banner = Instance.new("TextLabel")
banner.Name = "Status"
banner.Position = UDim2.fromScale(0.5, 0.05)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Size = UDim2.new(0.9, 0, 0, 78)
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(650, 78)
limit.Parent = banner
banner.BackgroundColor3 = Color3.fromRGB(32, 38, 32)
banner.TextColor3 = Color3.fromRGB(255, 248, 222)
banner.TextWrapped = true
banner.TextSize = 17
banner.Font = Enum.Font.GothamMedium
banner.Parent = gui

local prompts: {[string]: ProximityPrompt} = {}
local function heldBatch(): State.Batch?
	for _, batch in store.profile.batches do if batch.locationId == hand then return batch end end
	return nil
end
local function update(message: string, redraw: boolean)
	local held = heldBatch()
	banner.Text = (if held then "In der Hand: " .. Recipe.stageNames[held.stage] .. " · Ziel: Säge (Eingang)\n"
		else "Hand frei · E an einer Auflage drücken\n") .. message
	for _, prompt in prompts do prompt.ActionText = if held then "Ablegen" else "Aufnehmen" end
	if not redraw then return end
	for _, view in stock:GetChildren() do view:Destroy() end
	local root = character:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"))
	local scale = 25 / 7
	for _, batch in store.profile.batches do
		local endpoint = endpoints[batch.locationId]
		if not endpoint and batch.locationId ~= hand then continue end
		local block = Instance.new("Part")
		block.Name = batch.id
		block.Size = Vector3.new(0.60, 0.15, 0.45) * scale
		block.Color = Color3.fromRGB(202, 148, 86)
		block.Material = Enum.Material.Wood
		block.Massless = true
		block.CanCollide = false
		block.CanTouch = false
		block.CanQuery = false
		block:SetAttribute("BatchId", batch.id)
		block:SetAttribute("SlotId", batch.locationId)
		if endpoint then
			block.Anchored = true
			block.CFrame = endpoint.point.WorldCFrame * CFrame.new(0, block.Size.Y / 2, 0)
		else
			block.CFrame = root.CFrame * CFrame.new(0, -0.38 * scale, -0.53 * scale)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = root, block
			weld.Parent = block
		end
		block.Parent = stock
	end
end

local function interact(user: Player, id: string, direction: "Take" | "Put"): HandMoves.Result
	local check = HandMoves.interact(store, user, true, hand, endpoints, id, direction,
		game:GetService("HttpService"):GenerateGUID(false), os.time())
	update(check.message, check.ok)
	return check
end
local last = -math.huge
local names = {["RawStore.Slot1"] = "Rohstofflager · Platz 1", ["RawStore.Slot2"] = "Rohstofflager · Platz 2",
	["Saege.Input"] = "Säge · Eingang für Holz", ["Montage.Input"] = "Montage · Eingang für Bausatz"}
for id, endpoint in endpoints do
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "P0503Hand"
	prompt.ObjectText = names[id]
	prompt.ActionText = "Aufnehmen"
	prompt.MaxActivationDistance = 6
	prompt.RequiresLineOfSight = true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = endpoint.point
	prompts[id] = prompt
	prompt.Triggered:Connect(function(user)
		if user ~= player or os.clock() - last < 0.4 then return end
		last = os.clock()
		interact(user, id, if heldBatch() then "Put" else "Take")
	end)
end
update("Holz am Rohstofflager aufnehmen. Teste zuerst die Montage, dann die Säge.", true)

-- Server-only hook for the automated proof. Players use the native prompts.
local hook = Instance.new("BindableFunction")
hook.Name = "P0503HandTest"
hook.OnInvoke = function(id: string, direction: "Take" | "Put"): any
	local response = interact(player, id, direction)
	return {result = response, revision = store.profile.revision, held = heldBatch(), batches = store.profile.batches,
		reservations = store.profile.reservations, banner = banner.Text}
end
hook.Parent = game:GetService("ServerStorage")
local entrance = line.Route:FindFirstChild("01_Eingang")
if entrance and entrance:IsA("BasePart") then
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = entrance.Position + Vector3.new(0, 3, 0)
		local focus = Vector3.new(raw.Slot1.Position.X, position.Y, raw.Slot1.Position.Z)
		character:PivotTo(CFrame.lookAt(position, focus))
	end
end
return {demo = "P0503HandDemo", playerReady = true, actions = 4, storage = false}
