--!strict
-- P10-04: equipment a workshop buys with play money. An item shortens the run of one station for every recipe, from the
-- next run on. Ownership lives in the profile's progress (`progress.equipment[id] = {revision, price}`) and is bought
-- with one confirmed save together with the money, like the belt (P09-01).
local Recipes = require(script.Parent.Recipes)
local State = require(script.Parent.State)

-- The part of the persistence controller the purchase needs; Persistence itself would close a require cycle through Profiles.
export type Controller = {snapshot: () -> any, save: (any, number) -> any}
export type Item = {read id: string, read name: string, read stationId: string, read price: number,
	read seconds: {[string]: number}}
export type Owned = {revision: number, price: number}
export type Result = {ok: boolean, code: string, message: string, equipmentId: string?, unknown: boolean}
export type Offer = {id: string, name: string, price: number, canAfford: boolean, remaining: number,
	benefit: string, pace: string, aftermath: string?}

local Equipment = {}
local MAX_REVISION = 9007199254740991

-- Montagevorrichtung: the assembly bench gets a clamping jig. The seconds are the run times with the jig (whole seconds),
-- the price sits between the worker (120) and the belt (200). Balancing values like all prices and times.
local JIG_SECONDS: {[string]: number} = {Hocker01 = 6, Beistelltisch01 = 10}
table.freeze(JIG_SECONDS)
local ITEMS: {Item} = {
	table.freeze({id = "Montagevorrichtung", name = "Montagevorrichtung", stationId = "Montage", price = 150, seconds = JIG_SECONDS}),
}
Equipment.LIST = table.freeze(ITEMS)
local byId: {[string]: Item} = {}
for _, item in ITEMS do
	assert(byId[item.id] == nil and State.STATION_BY_ID[item.stationId], "Equipment needs a unique id and a known station")
	assert(item.price > 0 and item.price % 1 == 0, "Whole price")
	for _, recipe in Recipes.LIST do
		local faster = item.seconds[recipe.id]
		local timing = Recipes.timing(recipe.id, item.stationId)
		assert(faster and timing and faster > 0 and faster % 1 == 0 and faster < timing.durationSeconds,
			"Equipment must shorten the run of every recipe by whole seconds")
	end
	byId[item.id] = item
end
Equipment.BY_ID = table.freeze(byId)

local MESSAGES: {[string]: string} = {
	BOUGHT = "Ausrüstung gekauft. Ab dem nächsten Lauf arbeitet die Montage schneller.",
	OWNED = "Diese Ausrüstung besitzt du bereits.",
	NOT_CONFIRMED = "Der Spielstand wird gerade gespeichert. Bitte kurz warten.",
	NOT_AUTHORIZED = "Du darfst diese Werkstatt nicht verändern.",
	INVALID_REQUEST = "Diese Anfrage ist ungültig.",
	UNKNOWN_EQUIPMENT = "Diese Ausrüstung gibt es nicht.",
	STALE_REVISION = "Der Bestand hat sich geändert. Bitte erneut versuchen.",
	REVISION_OVERFLOW = "Der Bestand ist vorübergehend gesperrt.",
	NOT_ENOUGH_MONEY = "Dein Guthaben reicht für diese Ausrüstung nicht.",
	SAVE_FAILED = "Der Kauf konnte nicht gespeichert werden.",
}
Equipment.MESSAGES = table.freeze(MESSAGES)

function Equipment.get(id: any): Item?
	if type(id) ~= "string" then return nil end
	return byId[id]
end

-- `progress` may come from a saved or client-near record; only a table with a record under the id counts.
function Equipment.owned(progress: any, id: string): boolean
	local owned = if type(progress) == "table" then progress.equipment else nil
	return type(owned) == "table" and owned[id] ~= nil
end

local function effective(has: (string) -> boolean, stationId: string, recipeId: string, base: number): number
	local seconds = base
	for _, item in ITEMS do
		if item.stationId == stationId and has(item.id) then
			local faster = item.seconds[recipeId]
			if faster and faster < seconds then seconds = faster end
		end
	end
	return seconds
end

-- The run time of a station for a recipe, with every owned item applied. `base` is the recipe's own time.
function Equipment.seconds(progress: any, stationId: string, recipeId: string, base: number): number
	return effective(function(id: string): boolean return Equipment.owned(progress, id) end, stationId, recipeId, base)
end

-- The slowest station of a recipe with the given ownership: its id and run time. The first of equal stations wins.
local function paceWith(has: (string) -> boolean, recipeId: string): (string, number)
	local slowest, slowestSeconds = "", 0
	for _, stationId in Recipes.STATION_IDS do
		local timing = Recipes.timing(recipeId, stationId)
		if timing then
			local seconds = effective(has, stationId, recipeId, timing.durationSeconds)
			if seconds > slowestSeconds then slowest, slowestSeconds = stationId, seconds end
		end
	end
	return slowest, slowestSeconds
end
function Equipment.pace(progress: any, recipeId: string): (string, number)
	return paceWith(function(id: string): boolean return Equipment.owned(progress, id) end, recipeId)
end

local STATION_NAMES: {[string]: string} = {Saege = "Säge", Montage = "Montagebank", Finish = "Finishplatz", Packen = "Packtisch"}

-- What to show before the purchase: the first item the workshop does not own yet, with price, benefit for every recipe,
-- the pace of the selected recipe before and after, and what the balance is afterwards. nil when everything is owned.
function Equipment.offer(progress: any, money: number, selectedRecipeId: string?, materialPrice: number?): Offer?
	local selected = Recipes.get(selectedRecipeId) or (Recipes.get(Recipes.DEFAULT_ID) :: Recipes.Recipe)
	for _, item in ITEMS do
		if Equipment.owned(progress, item.id) then continue end
		local parts: {string} = {}
		for _, recipe in Recipes.LIST do
			local timing = Recipes.timing(recipe.id, item.stationId)
			if timing then
				table.insert(parts, recipe.name .. " von " .. timing.durationSeconds .. " auf " .. (item.seconds[recipe.id] or timing.durationSeconds) .. " s")
			end
		end
		local benefit = STATION_NAMES[item.stationId] .. ": " .. table.concat(parts, ", ")
		local _, before = Equipment.pace(progress, selected.id)
		local afterStation, after = paceWith(function(id: string): boolean return id == item.id or Equipment.owned(progress, id) end, selected.id)
		local pace = "Takt " .. selected.name .. ": von " .. before .. " auf " .. after .. " s"
		if afterStation ~= "" and before == after then pace ..= " (" .. STATION_NAMES[afterStation] .. " begrenzt)" end
		local remaining = money - item.price
		local aftermath: string? = nil
		if remaining >= 0 and materialPrice and remaining < materialPrice then
			aftermath = "Danach reicht das Guthaben (" .. remaining .. ") nicht für Holz (" .. materialPrice .. "): Verkaufe zuerst Ware oder hole den Materialvorschuss."
		end
		return {id = item.id, name = item.name, price = item.price, canAfford = remaining >= 0, remaining = remaining,
			benefit = benefit, pace = pace, aftermath = aftermath}
	end
	return nil
end

local function result(code: string, equipmentId: string?, unknown: boolean?): Result
	return {ok = code == "BOUGHT" or code == "OWNED", code = code, message = MESSAGES[code], equipmentId = equipmentId,
		unknown = unknown == true}
end

-- `lease` is the save lease like in Belts. A repeated request for owned equipment answers OWNED and changes nothing.
function Equipment.buy(controller: Controller, ownerUserId: any, expectedRevision: any, equipmentId: any, lease: number): Result
	local snapshot = controller.snapshot()
	local saved = snapshot.confirmed
	if not saved or snapshot.inFlight or snapshot.status ~= "Confirmed" then return result("NOT_CONFIRMED", nil, snapshot.unknown) end
	local profile = saved.data
	local state = profile.state
	if state.ownerUserId ~= ownerUserId then return result("NOT_AUTHORIZED") end
	if type(expectedRevision) ~= "number" or expectedRevision % 1 ~= 0 or expectedRevision < 0 or expectedRevision > MAX_REVISION then
		return result("INVALID_REQUEST")
	end
	local item = Equipment.get(equipmentId)
	if not item then return result(if type(equipmentId) == "string" then "UNKNOWN_EQUIPMENT" else "INVALID_REQUEST") end
	if Equipment.owned(profile.progress, item.id) then return result("OWNED", item.id) end
	if state.revision ~= expectedRevision then return result("STALE_REVISION", item.id) end
	if state.revision == MAX_REVISION then return result("REVISION_OVERFLOW", item.id) end
	if state.money < item.price then return result("NOT_ENOUGH_MONEY", item.id) end
	state.money -= item.price
	state.revision += 1
	local owned = profile.progress.equipment or {}
	owned[item.id] = {revision = state.revision, price = item.price}
	profile.progress.equipment = owned
	local saved2 = controller.save(profile, lease)
	if not saved2.ok then return result("SAVE_FAILED", item.id, saved2.unknown == true) end
	return result("BOUGHT", item.id)
end

return table.freeze(Equipment)
