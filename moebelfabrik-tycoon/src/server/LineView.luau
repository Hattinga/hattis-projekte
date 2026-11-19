--!strict
-- P05-08: renders the confirmed inventory and station feedback. Reads state only; never changes stock.
local State = require(script.Parent.State)
local Labels = require(script.Parent.Labels)
local Line = require(script.Parent.Line)
local WareView = require(script.Parent.WareView)
local LineView = {}
local SCALE = 25 / 7
local COLORS = {
	RUNNING = Color3.fromRGB(150, 225, 140),
	READY = Color3.fromRGB(150, 225, 140),
	OUTPUT_FULL = Color3.fromRGB(255, 176, 80),
	OUTPUT_RESERVED = Color3.fromRGB(140, 190, 255),
	INPUT_MISSING = Color3.fromRGB(215, 215, 205),
}

export type Places = {
	points: {[string]: Attachment}, -- location id -> physical transfer point
	carriers: {[string]: BasePart}?, -- carrier location id -> body part that holds the ware
	mounts: {[string]: Attachment}?, -- moving location id (vehicle slot) -> attachment the ware is welded to
	stationPads: {[string]: BasePart}, -- station id -> pad above which the sign floats
	storeSlots: {string}?,
	storePad: BasePart?,
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

local function addTrailerStrap(view: Model, support: CFrame, stage: State.Stage)
	if stage ~= "Holzpaket" and stage ~= "Karton" then return end
	local halfWidth = if stage == "Holzpaket" then 0.30 else 0.23
	local top = if stage == "Holzpaket" then 0.15 else 0.496
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
			local created = WareView.create(wares, support, batch.id, batch.stage)
			created.Name = batch.id
			created:SetAttribute("Signature", signature)
			if not point and mount then
				addTrailerStrap(created, support, batch.stage)
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

-- Station and store signs following PRODUCTION feedback; returns the shown status per station.
function LineView.syncSigns(root: Instance, state: State.Profile, now: number, places: Places): {[string]: Line.Status}
	local signs = folder(root, "Signs")
	local statuses = Line.status(state, now)
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
			setText(detail, Labels.text("collect." .. status.outputStage), true)
		elseif status.code == "OUTPUT_RESERVED" then
			setText(head, Labels.text("status.transport"), true)
			setText(detail, Labels.text("status.reserved"), true)
		else
			setText(head, Labels.text("missing." .. status.inputStage), true)
			setText(detail, "", false)
		end
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
