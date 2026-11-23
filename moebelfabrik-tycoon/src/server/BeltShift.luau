--!strict
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local BeltRoute = require(script.Parent.BeltRoute)
local BeltTransport = require(script.Parent.BeltTransport)
local Persistence = require(script.Parent.Persistence)
local State = require(script.Parent.State)

local BeltShift = {}
local route = State.FIRST_BELT
export type Shift = {fixture: BeltRoute.Fixture, demo: Instance, status: string, powered: boolean, closing: boolean}

function BeltShift.new(fixture: BeltRoute.Fixture, demo: Instance): Shift
	return {fixture = fixture, demo = demo, status = "Material fehlt", powered = true, closing = false}
end

local function animate(shift: Shift, batchId: string, from: CFrame, to: CFrame, seconds: number): boolean
	local wares = shift.demo:FindFirstChild("Wares")
	local view = if wares then wares:FindFirstChild(batchId) else nil
	local signature = route.stage .. "@" .. route.carrier
	local deadline = os.clock() + 1.25
	while (not view or view:GetAttribute("Signature") ~= signature) and os.clock() < deadline and not shift.closing do
		RunService.Heartbeat:Wait()
		wares = shift.demo:FindFirstChild("Wares")
		view = if wares then wares:FindFirstChild(batchId) else nil
	end
	if not view or not view:IsA("Model") or view:GetAttribute("Signature") ~= signature then return false end
	local buffer = shift.fixture.buffer.WorldCFrame
	local offset = buffer:ToObjectSpace(view:GetPivot())
	local started = os.clock()
	while view.Parent and shift.powered and not shift.closing do
		local alpha = math.clamp((os.clock() - started) / seconds, 0, 1)
		view:PivotTo(from:Lerp(to, alpha) * offset)
		if alpha == 1 then return true end
		RunService.Heartbeat:Wait()
	end
	if view.Parent then view:PivotTo(buffer * offset) end
	return false
end

function BeltShift.tick(shift: Shift, controller: Persistence.Controller, lease: number)
	if shift.closing or not shift.fixture.model.Parent then return end
	local snap = controller.snapshot()
	if snap.status ~= "Confirmed" or snap.inFlight or not snap.confirmed then return end
	local data = snap.confirmed.data
	local belt = data.progress.firstBelt
	if not belt then return end
	shift.powered = not belt.stopped
	local active: State.Claim? = nil
	for _, claim in data.state.claims do
		if claim.actorKind == "Band" and claim.actorId == route.carrier then active = claim; break end
	end
	if not shift.powered then
		shift.status = "Pausiert"
		if active then BeltTransport.finish(controller, active.id, os.time(), lease, false) end
		return
	end
	if active then
		shift.status = "Zur Montage"
		local atExit = active.expiresAt > os.time() and animate(shift, active.batchId, shift.fixture.buffer.WorldCFrame,
			shift.fixture.output.WorldCFrame, 1.25)
		if shift.closing then return end
		local result = BeltTransport.finish(controller, active.id, os.time(), lease, atExit)
		if not result.ok then
			-- Rebuild from the confirmed buffer if the animation arrived but its Save is still unresolved.
			local wares = shift.demo:FindFirstChild("Wares")
			local lot = wares and wares:FindFirstChild(active.batchId)
			if lot and lot:GetAttribute("Signature") == route.stage .. "@" .. route.carrier then lot:Destroy() end
		end
		return
	end
	local hold = data.state.reservations[route.source]
	local carrying = hold and hold.kind == "Return" and hold.carrierId == route.carrier
	local result = BeltTransport.reserve(controller, if carrying then route.carrier else route.source,
		"belt/" .. HttpService:GenerateGUID(false), os.time(), lease)
	if result.ok and not carrying and result.batchId then
		shift.status = "Zum Puffer"
		animate(shift, result.batchId, shift.fixture.input.WorldCFrame, shift.fixture.buffer.WorldCFrame, 0.7)
	elseif result.code == "TARGET_FULL" or result.code == "TARGET_RESERVED" then
		shift.status = "Montageeingang belegt"
	elseif result.code == "NO_MATERIAL" then
		shift.status = "Material fehlt"
	end
end

return table.freeze(BeltShift)
