--!strict
-- P05-01: Hocker01's station contract and read-only binding to a workshop model.
local State = require(script.Parent.State)

export type Station = {
	id: string,
	inputStage: State.Stage,
	outputStage: State.Stage,
	durationSeconds: number,
}
export type Binding = {
	locations: {[string]: State.Location},
	points: {[string]: Attachment},
}

local Recipe = {}
Recipe.id = "Hocker01"
Recipe.version = 1
Recipe.stageNames = table.freeze({
	Holzpaket = "Holzpaket",
	Bausatz = "Bausatz · 9 Teile",
	Rohhocker = "Rohhocker",
	Fertig = "Fertiger Hocker",
	Karton = "Hockerkarton",
})

local function station(id: string, inputStage: State.Stage, outputStage: State.Stage, duration: number): Station
	return table.freeze({id = id, inputStage = inputStage, outputStage = outputStage, durationSeconds = duration})
end

Recipe.stations = table.freeze({
	station(State.SAW.id, State.SAW.inputStage, State.SAW.outputStage, State.SAW.durationSeconds),
	station("Montage", "Bausatz", "Rohhocker", 8),
	station("Finish", "Rohhocker", "Fertig", 6),
	station("Packen", "Fertig", "Karton", 4),
})

local function uniqueChild(parent: Instance, name: string): Instance?
	local match: Instance? = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			if match then return nil end
			match = child
		end
	end
	return match
end

function Recipe.bind(stationRoot: Instance): (Binding?, string?)
	local binding: Binding = {locations = {}, points = {}}
	for sequence, rule in Recipe.stations do
		local model = uniqueChild(stationRoot, rule.id)
		if not model or not model:IsA("Model") or model:GetAttribute("Sequence") ~= sequence
			or model:GetAttribute("InputStage") ~= rule.inputStage or model:GetAttribute("OutputStage") ~= rule.outputStage then
			return nil, "INVALID_STATION:" .. rule.id
		end
		for _, role in {"Input", "Process", "Output"} do
			local id = rule.id .. "." .. role
			local pad = uniqueChild(model, role)
			local point = if pad then uniqueChild(pad, "Transfer") else nil
			if not pad or not pad:IsA("BasePart") or pad:GetAttribute("Capacity") ~= 1
				or not point or not point:IsA("Attachment") then
				return nil, "INVALID_POINT:" .. id
			end
			local stage = if role == "Output" then rule.outputStage else rule.inputStage
			binding.locations[id] = State.newLocation(id, "Station" .. role, 1, {stage})
			binding.points[id] = point
		end
	end
	return binding, nil
end

return table.freeze(Recipe)
