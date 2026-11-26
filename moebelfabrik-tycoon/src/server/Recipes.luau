--!strict
-- P10-02: the recipe list. Stage names, station times, supplier price and buyer values of every recipe live here.
-- Pure data, no engine access. A stage is a processing level; `recipeId` on the batch names the product.
-- Hocker01 and Beistelltisch01 share the stages Holzpaket, Bausatz, Fertig and Karton, only the raw piece differs.
export type Stage = "Holzpaket" | "Bausatz" | "Rohhocker" | "Rohtisch" | "Fertig" | "Karton"
export type Timing = {read stationId: string, read inputStage: Stage, read outputStage: Stage, read durationSeconds: number}
export type Recipe = {
	read id: string,
	read version: number,
	read name: string, -- player-facing product name
	read packageName: string, -- the wood package the supplier sells for it
	read price: number, -- supplier price per package
	read dealer: number,
	read privateMin: number,
	read privateMax: number,
	read chain: {Stage}, -- input stage of the saw, then the output stage of each of the four stations
	read seconds: {number}, -- run time of each station
}

local Recipes = {}
Recipes.DEFAULT_ID = "Hocker01"
Recipes.STATION_IDS = table.freeze({"Saege", "Montage", "Finish", "Packen"})

local function recipe(id: string, name: string, packageName: string, price: number, dealer: number, privateMin: number,
	privateMax: number, chain: {Stage}, seconds: {number}): Recipe
	assert(#chain == #Recipes.STATION_IDS + 1 and #seconds == #Recipes.STATION_IDS, "Recipe chain needs five stages and four times")
	assert(price > 0 and privateMin <= dealer and dealer <= privateMax and privateMin > price,
		"Buyer values must cover the supplier price")
	for _, duration in seconds do assert(duration > 0 and duration % 1 == 0, "Whole station seconds only") end
	return table.freeze({id = id, version = 1, name = name, packageName = packageName, price = price, dealer = dealer,
		privateMin = privateMin, privateMax = privateMax, chain = table.freeze(chain), seconds = table.freeze(seconds)})
end

-- Hocker01 v1 (PRODUCTION): 6 + 8 + 6 + 4 s. Beistelltisch01 v1 (TABLE): 8 + 14 + 8 + 5 s.
Recipes.LIST = table.freeze({
	recipe("Hocker01", "Hocker", "Holzpaket", 60, 100, 80, 120,
		{"Holzpaket", "Bausatz", "Rohhocker", "Fertig", "Karton"}, {6, 8, 6, 4}),
	recipe("Beistelltisch01", "Beistelltisch", "Tischholzpaket", 80, 140, 112, 168,
		{"Holzpaket", "Bausatz", "Rohtisch", "Fertig", "Karton"}, {8, 14, 8, 5}),
})

local byId: {[string]: Recipe} = {}
local timings: {[string]: {[string]: Timing}} = {}
local stageSet: {[string]: boolean} = {}
for _, entry in Recipes.LIST do
	assert(byId[entry.id] == nil, "Duplicate recipe id")
	byId[entry.id] = entry
	local perStation: {[string]: Timing} = {}
	for index, stationId in Recipes.STATION_IDS do
		perStation[stationId] = table.freeze({stationId = stationId, inputStage = entry.chain[index],
			outputStage = entry.chain[index + 1], durationSeconds = entry.seconds[index]})
	end
	timings[entry.id] = table.freeze(perStation)
	for _, stage in entry.chain do stageSet[stage] = true end
end
Recipes.BY_ID = table.freeze(byId)
Recipes.STAGES = table.freeze(stageSet)

-- Any value may come from a saved or client-supplied record; only a known string id answers.
function Recipes.get(id: any): Recipe?
	if type(id) ~= "string" then return nil end
	return byId[id]
end

function Recipes.hasStage(id: string, stage: string): boolean
	local entry = byId[id]
	return entry ~= nil and table.find(entry.chain, stage :: Stage) ~= nil
end

-- Station times and stages of one recipe, nil for an unknown recipe or station.
function Recipes.timing(id: string, stationId: string): Timing?
	local perStation = timings[id]
	return if perStation then perStation[stationId] else nil
end

-- Stages a station location must accept so that every recipe can pass it.
-- Role "Input" and "Process" take the input stages, "Output" the output stages.
function Recipes.acceptedStages(stationId: string, role: string): {Stage}
	local stages: {Stage} = {}
	for _, entry in Recipes.LIST do
		local timing = timings[entry.id][stationId]
		assert(timing, "Unknown station")
		local stage = if role == "Output" then timing.outputStage else timing.inputStage
		if not table.find(stages, stage) then table.insert(stages, stage) end
	end
	return stages
end

-- Player-facing stage names of each recipe. A nil or unknown recipe answers with the first recipe's names, a stage the
-- recipe does not know with the stage id itself.
local STAGE_NAMES: {[string]: {[string]: string}} = {
	Hocker01 = {Holzpaket = "Holzpaket", Bausatz = "Bausatz · 9 Teile", Rohhocker = "Rohhocker", Fertig = "Fertiger Hocker",
		Karton = "Hockerkarton"},
	Beistelltisch01 = {Holzpaket = "Tischholzpaket", Bausatz = "Bausatz · 10 Teile", Rohtisch = "Rohtisch",
		Fertig = "Fertiger Tisch", Karton = "Tischkarton"},
}
for id, names in STAGE_NAMES do
	assert(byId[id], "Stage names for an unknown recipe")
	table.freeze(names)
end
table.freeze(STAGE_NAMES)
assert(STAGE_NAMES[Recipes.DEFAULT_ID], "The default recipe needs stage names")
function Recipes.stageName(stage: string, recipeId: string?): string
	local names = STAGE_NAMES[if recipeId ~= nil and STAGE_NAMES[recipeId] then recipeId else Recipes.DEFAULT_ID]
	return names[stage] or stage
end

return table.freeze(Recipes)
