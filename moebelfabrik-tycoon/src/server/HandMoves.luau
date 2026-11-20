--!strict
-- P05-03: a physical workshop handoff, using the common server inventory.
local State = require(script.Parent.State)
local Transfers = require(script.Parent.Transfers)
local Loading = require(script.Parent.Loading)

export type Result = {ok: boolean, code: string, message: string, batch: State.Batch?}
export type Endpoint = {point: Attachment, stand: BasePart?}
local HandMoves = {}
local HANDOFF_REACH = 6 -- studs, measured from the authoritative avatar to the marked point
local MAX_INTEGER = 9007199254740991
local HAND_SLOTS: {[string]: boolean} = {RawStore = true, FinishedStore = true, StationInput = true,
	StationOutput = true, Supplier = true, VehicleSlot = true}
local LOADING_MESSAGES: {[string]: string} = {
	UNKNOWN_LOCATION = "Dieser Übergabeplatz ist nicht verfügbar.",
	NOT_VEHICLE_OWNER = "Dieses Fahrzeug gehört dir nicht.",
	VEHICLE_MOVING = "Halte vor dem Be- oder Entladen an.",
	WRONG_ZONE = "Parke beide Anhängerplätze in der passenden Ladezone.",
	WRONG_STAGE = "Diese Ware passt nicht auf den Anhänger.",
	WRONG_LOADING_ROUTE = "Bringe die Charge zur passenden Ablage oder zum reservierten Rückgabeplatz.",
	NO_FREE_TARGET = "Das Ziel hat keinen freien Ablageplatz. Die Ware bleibt auf dem Anhänger.",
	RECOVERY_REQUIRED = "Hole die Ware am Bergungsplatz ab und lade sie dort auf den Anhänger.",
}

local function rejected(code: string, message: string): Result
	return {ok = false, code = code, message = message}
end

function HandMoves.checkReach(player: Player, endpoint: Endpoint, vehicleSlot: boolean?, receiver: Model?): Result?
	local stand = endpoint.stand
	if not endpoint.point:IsDescendantOf(workspace)
		or (not vehicleSlot and (not stand or not stand:IsDescendantOf(workspace))) then
		return rejected("UNKNOWN_LOCATION", "Dieser Übergabeplatz ist nicht verfügbar.")
	end
	local point = endpoint.point
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local head = if character then character:FindFirstChild("Head") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not character:IsDescendantOf(workspace) or not root or not root:IsA("BasePart")
		or not head or not head:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return rejected("NO_AVATAR", "Warte auf deinen Charakter.")
	end
	local distance = point.WorldPosition - root.Position
	if distance.Magnitude > HANDOFF_REACH then
		return rejected("TOO_FAR", "Tritt näher an die markierte Auflage.")
	end
	if not vehicleSlot and stand then
		local horizontal = Vector3.new(1, 0, 1)
		local approach = (stand.Position - point.WorldPosition) * horizontal
		if approach.Magnitude == 0 or (-distance * horizontal):Dot(approach.Unit) <= 0 then
			return rejected("WRONG_SIDE", "Nutze die markierte Bedienseite der Auflage.")
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local hit = workspace:Raycast(head.Position, point.WorldPosition - head.Position, params)
	if hit and hit.Instance ~= point.Parent and not (receiver and hit.Instance:IsDescendantOf(receiver))
		and not (vehicleSlot and (hit.Position - point.WorldPosition).Magnitude <= 0.5) then
		return rejected("OBSTRUCTED", "Der Weg zur Auflage ist versperrt.")
	end
	return nil
end

function HandMoves.interact(
	store: Transfers.Store,
	player: Player,
	ready: boolean,
	carrierId: string,
	endpoints: {[string]: Endpoint},
	locationId: string,
	direction: "Take" | "Put",
	operationId: string,
	now: number,
	loading: Loading.Binding?
): Result
	if not ready then return rejected("NOT_READY", "Der Spielstand ist noch nicht freigegeben.") end
	local profile = store.profile
	if profile.ownerUserId ~= player.UserId then
		return rejected("NOT_AUTHORIZED", "Dieser Bestand gehört zu einer anderen Werkstatt.")
	end
	local location, carrier, endpoint = profile.locations[locationId], profile.locations[carrierId], endpoints[locationId]
	if not location or not HAND_SLOTS[location.kind] or not carrier or carrier.kind ~= "Carrier" or not endpoint then
		return rejected("UNKNOWN_LOCATION", "Dieser Übergabeplatz ist nicht verfügbar.")
	end
	local reachProblem = HandMoves.checkReach(player, endpoint, location.kind == "VehicleSlot" and endpoint.stand == nil)
	if reachProblem then return reachProblem end
	local held: State.Batch? = nil
	local stock: State.Batch? = nil
	for _, batch in profile.batches do
		if batch.locationId == carrierId then held = batch end
		if batch.locationId == locationId then stock = batch end
	end
	if direction == "Take" then
		if held then return rejected("HANDS_FULL", "Lege zuerst deine getragene Charge ab.") end
		if not stock then return rejected("EMPTY", "An dieser Auflage liegt keine Charge.") end
	elseif direction == "Put" then
		if not held then return rejected("NOT_CARRYING", "Du trägst keine Charge.") end
	else
		return rejected("INVALID_REQUEST", "Diese Übergabe ist ungültig.")
	end
	local batch = if direction == "Take" then stock else held
	assert(batch)
	local loadingProblem, unloadKind = Loading.check(loading, profile, location, endpoint.point, carrierId, batch, direction, now)
	if loadingProblem then return rejected(loadingProblem, LOADING_MESSAGES[loadingProblem]) end
	if profile.revision > MAX_INTEGER - 2 then
		return rejected("REVISION_OVERFLOW", "Der Bestand ist vorübergehend gesperrt.")
	end
	local actor = {ownerUserId = profile.ownerUserId, ready = true, kind = "Player",
		actorId = "Player/" .. string.format("%.0f", profile.ownerUserId), carrierLocationId = carrierId}
	local sourceId = batch.locationId
	local targetId = if direction == "Take" then carrierId else locationId
	local claim = Transfers.reserve(store, actor, {operationId = operationId .. "/reserve",
		expectedRevision = profile.revision, batchId = batch.id, sourceId = sourceId, targetId = targetId, quantity = 1}, now, 5)
	if not claim.ok then return rejected(claim.code, claim.message) end
	local commit = Transfers.commit(store, actor, {operationId = operationId .. "/commit",
		expectedRevision = store.profile.revision, claimId = claim.claimId}, now)
	if not commit.ok then return rejected(commit.code, commit.message) end
	if loading and unloadKind then
		loading.unloads[carrierId] = {batchId = batch.id, slotId = locationId, destinationKind = unloadKind}
	end
	return {ok = true, code = commit.code,
		message = if direction == "Take" then "Charge aufgenommen." else "Charge abgelegt.",
		batch = table.clone(store.profile.batches[batch.id])}
end

return table.freeze(HandMoves)
