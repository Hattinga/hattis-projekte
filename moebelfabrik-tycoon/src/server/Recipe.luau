--!strict
-- P05-01: Hocker01's station contract and read-only binding to a workshop model.
local State = require(script.Parent.State)
local Recipes = require(script.Parent.Recipes)

export type Station = {
	read id: string,
	read inputStage: State.Stage,
	read outputStage: State.Stage,
	read durationSeconds: number,
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
	Rohtisch = "Rohtisch", -- P10-02: the table's raw stage; its other stages use Recipe.stageNameFor
})
-- The player-facing name of a stage for the recipe of its batch (the names live in Recipes).
function Recipe.stageNameFor(stage: string, recipeId: string?): string
	return Recipes.stageName(stage, recipeId)
end

local stations: {Station} = {}
for _, rule in State.STATIONS do
	table.insert(stations, table.freeze({id = rule.id, inputStage = rule.inputStage,
		outputStage = rule.outputStage, durationSeconds = rule.durationSeconds}))
end
Recipe.stations = table.freeze(stations)

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
			-- P10-02: a station place accepts the stage of every registered recipe, not only the first recipe's.
			binding.locations[id] = State.newLocation(id, "Station" .. role, 1, Recipes.acceptedStages(rule.id, role))
			binding.points[id] = point
		end
	end
	return binding, nil
end

-- P05-07: binds a workshop store's marked slots (Slot1..Capacity, each Capacity 1) as one location kind.
function Recipe.bindStore(storeRoot: Instance, kind: string, stage: State.Stage): (Binding?, string?)
	local binding: Binding = {locations = {}, points = {}}
	local count = storeRoot:GetAttribute("Capacity")
	if storeRoot:GetAttribute("AcceptedStage") ~= stage or type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
		return nil, "INVALID_STORE"
	end
	for index = 1, count do
		local id = kind .. ".Slot" .. index
		local pad = uniqueChild(storeRoot, "Slot" .. index)
		local point = if pad then uniqueChild(pad, "Transfer") else nil
		if not pad or not pad:IsA("BasePart") or pad:GetAttribute("Capacity") ~= 1
			or not point or not point:IsA("Attachment") then
			return nil, "INVALID_POINT:" .. id
		end
		binding.locations[id] = State.newLocation(id, kind, 1, {stage})
		binding.points[id] = point
	end
	return binding, nil
end

return table.freeze(Recipe)
