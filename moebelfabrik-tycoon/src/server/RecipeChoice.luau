--!strict
-- P10-02: the line's recipe choice. It lives in the profile's progress and changes with the State revision.
-- The choice decides what the supplier sells next. Every batch keeps the recipe it was bought with, and every station,
-- the saw included, works whatever recipe its batch carries (PRODUCTION, "Rezeptwechsel ohne Umdeuten alter Ware").
-- A switch is therefore never blocked by stock: wood bought before it stays usable.
local Persistence = require(script.Parent.Persistence)
local Recipes = require(script.Parent.Recipes)
local State = require(script.Parent.State)

export type Result = {ok: boolean, code: string, message: string, recipeId: string?, unknown: boolean}

local RecipeChoice = {}
local MAX_REVISION = 9007199254740991

local MESSAGES: {[string]: string} = {
	SELECTED = "Rezept gewechselt. Der nächste Einkauf folgt diesem Rezept, vorhandenes Holz bleibt nutzbar.",
	ALREADY_SELECTED = "Dieses Rezept ist bereits gewählt.",
	NOT_CONFIRMED = "Der Spielstand wird gerade gespeichert. Bitte kurz warten.",
	NOT_AUTHORIZED = "Du darfst diese Werkstatt nicht verändern.",
	INVALID_REQUEST = "Die Rezeptwahl enthält ungültige Angaben.",
	UNKNOWN_RECIPE = "Dieses Rezept gibt es nicht.",
	STALE_REVISION = "Der Bestand hat sich geändert. Bitte erneut versuchen.",
	REVISION_OVERFLOW = "Der Bestand ist vorübergehend gesperrt.",
	LAYOUT_UNSUPPORTED = "Diese Werkstatt kann das Rezept noch nicht verarbeiten.",
	SAVE_FAILED = "Die Rezeptwahl konnte nicht gespeichert werden.",
}

RecipeChoice.MESSAGES = table.freeze(MESSAGES)

local function result(code: string, recipeId: string?, unknown: boolean?): Result
	return {ok = code == "SELECTED" or code == "ALREADY_SELECTED", code = code, message = MESSAGES[code],
		recipeId = recipeId, unknown = unknown == true}
end

-- Every station place of the workshop must accept the stages this recipe passes through.
local function layoutRuns(state: State.Profile, recipeId: string): boolean
	for _, stationId in Recipes.STATION_IDS do
		local timing = Recipes.timing(recipeId, stationId)
		local rule = State.STATION_BY_ID[stationId]
		if not timing then return false end
		local input, process, output = state.locations[rule.input], state.locations[rule.process], state.locations[rule.output]
		if not input or not process or not output
			or not table.find(input.acceptedStages, timing.inputStage)
			or not table.find(process.acceptedStages, timing.inputStage)
			or not table.find(output.acceptedStages, timing.outputStage) then
			return false
		end
	end
	return true
end

-- `lease` is the save lease like in Workers.
function RecipeChoice.select(controller: Persistence.Controller, ownerUserId: any, expectedRevision: any, recipeId: any,
	lease: number): Result
	local snapshot = controller.snapshot()
	local profile = snapshot.confirmed
	if not profile or snapshot.inFlight or snapshot.status ~= "Confirmed" then
		return result("NOT_CONFIRMED", nil, snapshot.unknown)
	end
	local envelope = profile.data
	local state = envelope.state
	if state.ownerUserId ~= ownerUserId then return result("NOT_AUTHORIZED") end
	if type(expectedRevision) ~= "number" or expectedRevision % 1 ~= 0 or expectedRevision < 0
		or expectedRevision > MAX_REVISION then
		return result("INVALID_REQUEST")
	end
	local recipe = Recipes.get(recipeId)
	if not recipe then return result("UNKNOWN_RECIPE") end
	if envelope.progress.selectedRecipeId == recipe.id then return result("ALREADY_SELECTED", recipe.id) end
	if state.revision ~= expectedRevision then return result("STALE_REVISION") end
	if state.revision == MAX_REVISION then return result("REVISION_OVERFLOW") end
	if not layoutRuns(state, recipe.id) then return result("LAYOUT_UNSUPPORTED", recipe.id) end

	envelope.progress.selectedRecipeId, envelope.progress.selectedRecipeVersion = recipe.id, recipe.version
	state.revision += 1
	local saved = controller.save(envelope, lease)
	if not saved.ok then return result("SAVE_FAILED", recipe.id, saved.unknown) end
	return result("SELECTED", recipe.id)
end

return table.freeze(RecipeChoice)
