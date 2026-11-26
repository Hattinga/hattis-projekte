--!strict
-- P05-08: renders the confirmed inventory and station feedback. Reads state only; never changes stock.
local State = require(script.Parent.State)
local Labels = require(script.Parent.Labels)
local Line = require(script.Parent.Line)
local WareView = require(script.Parent.WareView)
local Equipment = require(script.Parent.Equipment)
local LineView = {}
local SCALE = 25 / 7
local COLORS = {
	RUNNING = Color3.fromRGB(150, 225, 140),
	READY = Color3.fromRGB(150, 225, 140),
	OUTPUT_FULL = Color3.fromRGB(255, 176, 80),
	OUTPUT_RESERVED = Color3.fromRGB(140, 190, 255),
	INPUT_MISSING = Color3.fromRGB(215, 215, 205),
	BACKLOG = Color3.fromRGB(255, 120, 90),
	STOPPED = Color3.fromRGB(215, 215, 205),
	IDLE = Color3.fromRGB(215, 215, 205),
}

export type Places = {
	points: {[string]: Attachment}, -- location id -> physical transfer point
	carriers: {[string]: BasePart}?, -- carrier location id -> body part that holds the ware
	mounts: {[string]: Attachment}?, -- moving location id (vehicle slot) -> attachment the ware is welded to
	stationPads: {[string]: BasePart}, -- station id -> pad above which the sign floats
	storeSlots: {string}?,
	storePad: BasePart?,
	beltStopped: boolean?, -- the first belt is switched off; a station that waits on it shows the cause
	selectedRecipeId: string?, -- the line's recipe choice (P10-02); the recipe sign and empty stations show it
}

local function folder(parent: Instance, name: string): Folder
	local found = parent:FindFirstChild(name)
	if found and found:IsA("Folder") then return found end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function holdOnCarrier(view: Model, carrier: BasePart)
	for _, part in view:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = carrier, part
			weld.Parent = part
		end
	end
end

local function addTrailerStrap(view: Model, support: CFrame, stage: State.Stage, recipeId: string)
	if stage ~= "Holzpaket" and stage ~= "Karton" then return end
	local isTable = recipeId == "Beistelltisch01" -- table carton 0.48 x 0.54 m (TABLE.md), package width unchanged
	local halfWidth = if stage == "Holzpaket" then 0.30 elseif isTable then 0.24 else 0.23
	local top = if stage == "Holzpaket" then 0.15 elseif isTable then 0.526 else 0.496
	local thickness, width, offset = 0.014, 0.048, 0.085
	local function piece(name: string, size: Vector3, across: number, height: number, buckle: boolean?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size * SCALE
		part.CFrame = support * CFrame.new(Vector3.new(across, height, offset) * SCALE)
		part.Anchored = true
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Color = if buckle then Color3.fromRGB(143, 149, 154) else Color3.fromRGB(39, 61, 90)
		part.Material = if buckle then Enum.Material.Metal else Enum.Material.Fabric
		part.Parent = view
	end
	local edge = halfWidth + thickness / 2
	piece("LoadStrapTop", Vector3.new(2 * (halfWidth + thickness), thickness, width), 0, top + thickness / 2)
	piece("LoadStrapLeft", Vector3.new(thickness, top, width), -edge, top / 2)
	piece("LoadStrapRight", Vector3.new(thickness, top, width), edge, top / 2)
	piece("LoadStrapBuckle", Vector3.new(thickness, 0.055, 0.061), halfWidth + thickness, top / 2, true)
end

-- Keeps one ware view per batch at its confirmed location; rebuilds only when stage or place changed.
function LineView.syncWares(root: Instance, state: State.Profile, places: Places): {[string]: Model}
	local wares = folder(root, "Wares")
	local shown: {[string]: Model} = {}
	for _, batch in state.batches do
		local point = places.points[batch.locationId]
		local carrier = if places.carriers then places.carriers[batch.locationId] else nil
		local mount = if places.mounts then places.mounts[batch.locationId] else nil
		if not point and not carrier and not mount then continue end
		-- A batch keeps its recipe for good, so stage and place alone say when its view must be rebuilt.
		-- BeltShift finds the kit on the belt by this signature ("Bausatz@Band.First") for every recipe.
		local signature = batch.stage .. "@" .. batch.locationId
		local view = wares:FindFirstChild(batch.id)
		if view and view:GetAttribute("Signature") ~= signature then
			view:Destroy()
			view = nil
		end
		if not view or not view:IsA("Model") then
			local support = if point then point.WorldCFrame
				elseif mount then mount.WorldCFrame
				else (carrier :: BasePart).CFrame * CFrame.new(Vector3.new(0, -0.45, -0.55) * SCALE)
			local created = WareView.create(wares, support, batch.id, batch.stage, batch.recipeId)
			created.Name = batch.id
			created:SetAttribute("Signature", signature)
			created:SetAttribute("RecipeId", batch.recipeId)
			if not point and mount then
				addTrailerStrap(created, support, batch.stage, batch.recipeId)
				holdOnCarrier(created, mount.Parent :: BasePart)
			elseif not point and carrier then
				holdOnCarrier(created, carrier)
			end
			view = created
		end
		shown[batch.id] = view :: Model
	end
	for _, child in wares:GetChildren() do
		if not shown[child.Name] then child:Destroy() end
	end
	return shown
end

local function sign(parent: Instance, name: string, adornee: BasePart, height: number): (BillboardGui, TextLabel, TextLabel)
	local gui = parent:FindFirstChild(name)
	if gui and gui:IsA("BillboardGui") then
		return gui, gui:FindFirstChild("Head") :: TextLabel, gui:FindFirstChild("Detail") :: TextLabel
	end
	local board = Instance.new("BillboardGui")
	board.Name = name
	board.Adornee = adornee
	board.Size = UDim2.fromOffset(230, 64)
	board.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	board.MaxDistance = 40
	local function line(lineName: string, y: number, h: number): TextLabel
		local text = Instance.new("TextLabel")
		text.Name = lineName
		text.Position = UDim2.fromScale(0, y)
		text.Size = UDim2.fromScale(1, h)
		text.BackgroundTransparency = 0.25
		text.BackgroundColor3 = Color3.fromRGB(28, 32, 28)
		text.BorderSizePixel = 0
		text.TextScaled = true
		text.Font = Enum.Font.GothamBold
		text.TextColor3 = Color3.fromRGB(255, 249, 220)
		text.Parent = board
		return text
	end
	local head, detail = line("Head", 0, 0.55), line("Detail", 0.55, 0.45)
	board.Parent = parent
	return board, head, detail
end

local function setText(label: TextLabel, text: string, localize: boolean)
	label.AutoLocalize = localize
	label.Text = text
end

-- P09-05: the sign above the first belt. It names the state and, while the kit waits, the cause.
function LineView.syncBelt(root: Instance, state: State.Profile, now: number, adornee: BasePart, stopped: boolean): Line.BeltStatus
	local status = Line.beltStatus(state, now, stopped)
	local board, head, detail = sign(folder(root, "Signs"), "Status_Belt", adornee, 6.0)
	board:SetAttribute("StatusCode", status.code)
	head.TextColor3 = COLORS[status.code] or Color3.new(1, 1, 1)
	if status.code == "BACKLOG" then
		setText(head, Labels.text("status.backlog"), true)
		setText(detail, Labels.text("status.cause." .. (status.cause :: string)), true)
	else
		setText(head, Labels.text(if status.code == "STOPPED" then "belt.stopped" elseif status.code == "RUNNING" then "belt.running" else "belt.idle"), true)
		setText(detail, "", false)
	end
	return status
end

-- P10-04: the owned equipment stands in the workshop. The assembly jig is a greybox gantry behind the assembly
-- work place: two posts, a crossbar, an arm and a press plate above the work piece. Nothing collides, so the avatar
-- and the carried ware pass it. The model appears with the confirmed ownership and is removed without it.
local JIG_ID = "Montagevorrichtung"
function LineView.syncEquipment(root: Instance, progress: any, places: Places)
	local shelf = folder(root, "Equipment")
	local existing = shelf:FindFirstChild(JIG_ID)
	if not Equipment.owned(progress, JIG_ID) then
		if existing then existing:Destroy() end
		return
	end
	local pad = places.stationPads.Montage
	if existing or not pad then return end
	local model = Instance.new("Model")
	model.Name = JIG_ID
	model:SetAttribute("EquipmentId", JIG_ID)
	local steel, orange = Color3.fromRGB(84, 96, 110), Color3.fromRGB(230, 150, 40)
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3): BasePart
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size
		piece.CFrame = pad.CFrame * CFrame.new(offset)
		piece.Anchored = true
		piece.CanCollide, piece.CanTouch, piece.CanQuery = false, false, false
		piece.Color = color
		piece.Material = Enum.Material.Metal
		piece.Parent = model
		return piece
	end
	part("PostLeft", Vector3.new(0.22, 2.1, 0.22), Vector3.new(-1.45, 1.1, 1.0), steel)
	part("PostRight", Vector3.new(0.22, 2.1, 0.22), Vector3.new(1.45, 1.1, 1.0), steel)
	local bar = part("Crossbar", Vector3.new(3.12, 0.24, 0.24), Vector3.new(0, 2.25, 1.0), steel)
	part("Arm", Vector3.new(0.18, 0.18, 1.0), Vector3.new(0, 2.25, 0.5), steel)
	part("Rod", Vector3.new(0.14, 0.6, 0.14), Vector3.new(0, 1.95, 0), orange)
	part("Plate", Vector3.new(0.9, 0.1, 0.9), Vector3.new(0, 1.65, 0), orange)
	local board = Instance.new("BillboardGui")
	board.Name = "EquipmentLabel"
	board.Adornee = bar
	board.Size = UDim2.fromOffset(190, 30)
	board.StudsOffsetWorldSpace = Vector3.new(0, 1.0, 0)
	board.MaxDistance = 24
	board.Parent = model
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(255, 205, 120)
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Text = Labels.text("equipment." .. JIG_ID .. ".name")
	text.Parent = board
	model.Parent = shelf
end

-- Station and store signs following PRODUCTION feedback; returns the shown status per station.
function LineView.syncSigns(root: Instance, state: State.Profile, now: number, places: Places): {[string]: Line.Status}
	local signs = folder(root, "Signs")
	local statuses = Line.status(state, now, places.beltStopped, places.selectedRecipeId)
	for stationId, status in statuses do
		local pad = places.stationPads[stationId]
		if not pad then continue end
		local board, head, detail = sign(signs, "Status_" .. stationId, pad, 2.9)
		board:SetAttribute("StatusCode", status.code)
		head.TextColor3 = COLORS[status.code] or Color3.new(1, 1, 1)
		if status.code == "RUNNING" then
			setText(head, Labels.text("process." .. stationId), true)
			setText(detail, string.format("%d s", status.remaining or 0), false)
		elseif status.code == "READY" then
			setText(head, Labels.text("process." .. stationId), true)
			setText(detail, Labels.text("status.starting"), true)
		elseif status.code == "OUTPUT_FULL" then
			setText(head, Labels.text("status.outputFull"), true)
			setText(detail, Labels.text(Labels.stageKey("collect", status.outputStage, status.recipeId)), true)
		elseif status.code == "BACKLOG" then
			setText(head, Labels.text("status.backlog"), true)
			setText(detail, Labels.text("status.cause." .. (status.cause :: string)), true)
		elseif status.code == "OUTPUT_RESERVED" then
			setText(head, Labels.text("status.transport"), true)
			setText(detail, Labels.text("status.reserved"), true)
		else
			setText(head, Labels.text(Labels.stageKey("missing", status.inputStage, status.recipeId)), true)
			setText(detail, "", false)
		end
	end
	-- P10-02: the recipe sign stands above the saw sign and always names the choice and what the supplier sells next.
	local sawPad = places.stationPads.Saege
	if places.selectedRecipeId and sawPad then
		local board, head, detail = sign(signs, "Recipe", sawPad, 6.0)
		board:SetAttribute("RecipeId", places.selectedRecipeId)
		head.TextColor3 = Color3.fromRGB(255, 228, 150)
		setText(head, Labels.text("recipe.name." .. places.selectedRecipeId), true)
		setText(detail, Labels.text("recipe.next." .. places.selectedRecipeId), true)
	end
	if places.storeSlots and places.storePad then
		local store = Line.storeStatus(state, places.storeSlots)
		local board, head, detail = sign(signs, "Status_Store", places.storePad, 3.2)
		board:SetAttribute("StatusCode", if store.full then "STORE_FULL" else "STORE_OPEN")
		head.TextColor3 = if store.full then COLORS.OUTPUT_FULL else COLORS.INPUT_MISSING
		setText(head, Labels.text(if store.full then "store.full" else "store.name"), true)
		setText(detail, string.format("%d / %d", store.used, store.capacity), false)
	end
	return statuses
end

return table.freeze(LineView)
