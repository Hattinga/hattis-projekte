--!strict
-- P08-03/04: step the scheduled job. Movement runs outside the profile's write path.
local HttpService = game:GetService("HttpService")
local WorkerTransport = require(script.Parent.WorkerTransport)
local WorkerRoute = require(script.Parent.WorkerRoute)
local Persistence = require(script.Parent.Persistence)
local State = require(script.Parent.State)

local WorkerShift = {}
local route = State.FIRST_WORKER

export type Shift = {
	binding: WorkerRoute.Binding, rig: WorkerRoute.Rig,
	status: string, paused: boolean, attempts: number, retryAt: number,
}

function WorkerShift.new(binding: WorkerRoute.Binding, rig: WorkerRoute.Rig): Shift
	return {binding = binding, rig = rig, status = "Material fehlt", paused = false, attempts = 0, retryAt = 0}
end

local function operation(): string
	return "worker/" .. HttpService:GenerateGUID(false)
end

local function walk(shift: Shift, to: Vector3): boolean
	local p = shift.rig.root.Position
	return WorkerRoute.walk(shift.rig, Vector3.new(p.X, to.Y, p.Z), to)
end

function WorkerShift.retry(shift: Shift)
	if shift.paused then
		shift.paused = false
		shift.attempts = 0
		shift.retryAt = 0
	end
end

function WorkerShift.tick(shift: Shift, controller: Persistence.Controller, lease: number)
	if shift.paused or os.clock() < shift.retryAt then return end
	local snapshot = controller.snapshot()
	if snapshot.status ~= "Confirmed" or snapshot.inFlight or not snapshot.confirmed then return end
	local state = snapshot.confirmed.data.state
	local active: State.Claim? = nil
	for _, claim in state.claims do
		if claim.carrierId == route.carrier and claim.actorKind == "Worker" and claim.actorId == route.carrier then
			active = claim
			break
		end
	end
	local source = shift.binding.source.stand.Position
	local target = shift.binding.target.stand.Position
	local held = state.reservations[route.source]
	local carrying = held and held.kind == "Return" and held.carrierId == route.carrier
	local now = os.time()
	if active then
		local picking = active.nextTargetId == route.target
		if now >= active.expiresAt then
			WorkerTransport.cancel(controller, active.id, now, lease)
			return
		end
		shift.status = if picking then "Zur Säge unterwegs" else "Zur Montage unterwegs"
		local reached = walk(shift, if picking then source else target)
		if not reached then
			shift.status = "Weg blockiert"
			shift.attempts += 1
			shift.retryAt = os.clock() + 0.8
			if shift.attempts >= 2 then
				local cancelled = WorkerTransport.cancel(controller, active.id, os.time(), lease)
				shift.paused = cancelled.ok and not carrying
			end
			return
		end
		shift.attempts = 0
		local result = if picking then WorkerTransport.take(controller, active.id, os.time(), lease)
			else WorkerTransport.put(controller, active.id, os.time(), lease)
		if result.ok then
			shift.status = if picking then "Zur Montage unterwegs" else "Abgeliefert"
			if not picking then walk(shift, shift.binding.rest) end
		end
		return
	end
	if carrying then
		shift.status = "Bringt Ware zurück"
		if walk(shift, source) then
			local restored = WorkerTransport.restore(controller, operation(), os.time(), lease)
			if not restored.ok then return end
			shift.status = "Ware am Sägeausgang"
			walk(shift, shift.binding.rest)
		else
			shift.status = "Weg blockiert · trägt Ware"
		end
		shift.paused = true
		return
	end
	local reserved = WorkerTransport.reserve(controller, operation(), now, lease)
	if reserved.ok then
		shift.status = "Zur Säge unterwegs"
	elseif reserved.code == "NO_MATERIAL" then
		shift.status = "Material fehlt"
	elseif reserved.code == "TARGET_FULL" or reserved.code == "TARGET_RESERVED" then
		shift.status = "Montageeingang belegt"
	end
end

return table.freeze(WorkerShift)
