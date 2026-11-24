--!strict
-- P09-03/04: runs the first belt. The confirmed stock decides where the kit is; the visible motion is a local
-- phase on top of it. A motion starts only after its confirming save, waits at the exit until the delivery is
-- confirmed and falls back to the confirmed buffer whenever the transport is released or the belt stops.
local HttpService = game:GetService("HttpService")
local BeltRoute = require(script.Parent.BeltRoute)
local BeltTransport = require(script.Parent.BeltTransport)
local Persistence = require(script.Parent.Persistence)
local State = require(script.Parent.State)

local BeltShift = {}
local route = State.FIRST_BELT
local SIGNATURE = route.stage .. "@" .. route.carrier
BeltShift.LOAD_SECONDS = 0.7
BeltShift.EXIT_SECONDS = 1.25
local VIEW_WAIT = 1.25 -- LineView builds the confirmed view within one render pass.

-- `started` is set by the first frame that moves the confirmed view.
export type Motion = {batchId: string, claimId: string?, queued: number, started: number?}
export type Shift = {
	fixture: BeltRoute.Fixture, demo: Instance, status: string, powered: boolean, closing: boolean,
	state: State.Profile?, load: Motion?, exit: Motion?, view: Model?, offset: CFrame,
}

function BeltShift.new(fixture: BeltRoute.Fixture, demo: Instance): Shift
	return {fixture = fixture, demo = demo, status = "Material fehlt", powered = true, closing = false,
		offset = CFrame.identity}
end

local function beltClaim(state: State.Profile): State.Claim?
	for _, claim in state.claims do
		if claim.actorKind == "Band" and claim.actorId == route.carrier then return claim end
	end
	return nil
end

local function kitOnBelt(state: State.Profile): string?
	for id, batch in state.batches do
		if batch.locationId == route.carrier then return id end
	end
	return nil
end

-- A motion without a view keeps the same pacing, so the transport never depends on rendering.
local function finished(motion: Motion, seconds: number, clock: number): boolean
	if motion.started then return clock >= motion.started + seconds end
	return clock >= motion.queued + VIEW_WAIT + seconds
end

local function remember(shift: Shift, state: State.Profile)
	local known = shift.state
	if not known or state.revision >= known.revision then shift.state = state end
end

local function refresh(shift: Shift, controller: Persistence.Controller)
	local saved = controller.snapshot().confirmed
	if saved then remember(shift, saved.data.state) end
end

-- Poses the kit on Band.First from the last confirmed state: input → buffer while loading, buffer → exit while
-- this shift's own exit claim is confirmed, otherwise the confirmed buffer. Pass the confirmed state after each
-- view sync; per-frame calls may omit it.
function BeltShift.place(shift: Shift, clock: number, state: State.Profile?)
	if state then remember(shift, state) end
	local confirmed = shift.state
	local batchId = if confirmed then kitOnBelt(confirmed) else nil
	local wares = shift.demo:FindFirstChild("Wares")
	local view = if wares and batchId then wares:FindFirstChild(batchId) else nil
	if not confirmed or not batchId or not view or not view:IsA("Model")
		or view:GetAttribute("Signature") ~= SIGNATURE then
		shift.view = nil
		return
	end
	local buffer = shift.fixture.buffer.WorldCFrame
	if view ~= shift.view then
		-- LineView builds every Band.First view on the buffer support; keep that relation while moving it.
		shift.view, shift.offset = view, buffer:ToObjectSpace(view:GetPivot())
	end
	local from, to, alpha = buffer, buffer, 1
	local load, exit = shift.load, shift.exit
	if shift.powered and exit and exit.batchId == batchId and exit.claimId and confirmed.claims[exit.claimId] then
		local started = exit.started or clock
		exit.started = started
		from, to, alpha = buffer, shift.fixture.output.WorldCFrame, (clock - started) / BeltShift.EXIT_SECONDS
	elseif shift.powered and load and load.batchId == batchId then
		local started = load.started or clock
		load.started = started
		from, to, alpha = shift.fixture.input.WorldCFrame, buffer, (clock - started) / BeltShift.LOAD_SECONDS
	end
	local pose = from:Lerp(to, math.clamp(alpha, 0, 1)) * shift.offset
	if (view:GetPivot().Position - pose.Position).Magnitude > 1e-4 then view:PivotTo(pose) end
end

function BeltShift.tick(shift: Shift, controller: Persistence.Controller, lease: number)
	if shift.closing or not shift.fixture.model.Parent then return end
	local snap = controller.snapshot()
	if snap.status ~= "Confirmed" or snap.inFlight or not snap.confirmed then return end
	local data = snap.confirmed.data
	local belt = data.progress.firstBelt
	if not belt then return end
	local state = data.state
	remember(shift, state)
	shift.powered = not belt.stopped
	local clock, now = os.clock(), os.time()
	local active = beltClaim(state)
	local exit = shift.exit
	if exit and (not active or active.id ~= exit.claimId) then
		-- Delivered, cancelled or expired: the confirmed state alone shows where the kit is.
		shift.exit, exit = nil, nil
	end
	if not shift.powered then
		shift.status = "Pausiert"
		shift.load, shift.exit = nil, nil
		if active then
			BeltTransport.finish(controller, active.id, now, lease, false)
			refresh(shift, controller)
		end
		return
	end
	if active then
		if not exit then
			-- A claim this shift did not start, e.g. from the previous server: release it before anything moves.
			shift.status = "Bausatz im Puffer"
			BeltTransport.finish(controller, active.id, now, lease, false)
			refresh(shift, controller)
			return
		end
		shift.status = "Zur Montage"
		if not finished(exit, BeltShift.EXIT_SECONDS, clock) then return end
		-- At the exit: book the delivery. An unclear save keeps the kit at the exit until it is clarified;
		-- a known failure or an expired claim sends the view back to the confirmed buffer.
		local result = BeltTransport.finish(controller, active.id, now, lease, now < active.expiresAt)
		if not result.ok and not controller.snapshot().unknown then shift.exit = nil end
		refresh(shift, controller)
		return
	end
	local load = shift.load
	if load and not finished(load, BeltShift.LOAD_SECONDS, clock) then
		shift.status = "Zum Puffer"
		return
	end
	shift.load = nil
	local hold = state.reservations[route.source]
	local carrying = hold ~= nil and hold.kind == "Return" and hold.carrierId == route.carrier
	local result = BeltTransport.reserve(controller, if carrying then route.carrier else route.source,
		"belt/" .. HttpService:GenerateGUID(false), now, lease)
	if result.ok and result.batchId then
		local queued = os.clock()
		if carrying then
			shift.exit = {batchId = result.batchId, claimId = result.claimId, queued = queued}
			shift.status = "Zur Montage"
		else
			shift.load = {batchId = result.batchId, queued = queued}
			shift.status = "Zum Puffer"
		end
		refresh(shift, controller)
	elseif result.code == "TARGET_FULL" or result.code == "TARGET_RESERVED" then
		shift.status = "Montageeingang belegt"
	elseif result.code == "NO_MATERIAL" then
		shift.status = "Material fehlt"
	end
end

return table.freeze(BeltShift)
