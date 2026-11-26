--!strict
-- P10-03: the operating overview. Read-only: it derives raw stock, finished goods, vehicle load, free places and the
-- current bottlenecks from one confirmed profile and never changes stock, money or reservations.
-- Places are counted by location kind, so it works for any workshop that binds its stores, stations and vehicle slots.
local Equipment = require(script.Parent.Equipment)
local Line = require(script.Parent.Line)
local Recipes = require(script.Parent.Recipes)
local State = require(script.Parent.State)

export type Places = {used: number, capacity: number, free: number, full: boolean}
export type Where = {raw: number, supplier: number, vehicle: number, line: number, store: number, carried: number}
export type StockEntry = {recipeId: string, stage: string, name: string, count: number}
export type Bottleneck = {code: string, severity: string, message: string, stationId: string?}
export type Row = {label: string, value: string}
export type Overview = {
	money: number,
	advance: number?,
	recipe: {id: string, name: string, packageName: string, price: number, dealer: number, takt: string?},
	wood: {total: number, where: Where},
	cartons: {total: number, where: Where},
	inProgress: number,
	equipment: {string}, -- names of the owned equipment (P10-04)
	stock: {StockEntry},
	places: {raw: Places?, store: Places?, vehicle: Places?},
	saleOpen: boolean,
	bottlenecks: {Bottleneck},
}

local Overview = {}
-- stop: production stands still. action: the player owes a step. limit: output is reduced. hint: the next useful step.
local SEVERITY_ORDER: {[string]: number} = {stop = 1, action = 2, limit = 3, hint = 4, info = 5}
Overview.SEVERITY_ORDER = table.freeze(SEVERITY_ORDER)
local STATION_NAMES: {[string]: string} = {Saege = "Säge", Montage = "Montagebank", Finish = "Finishplatz", Packen = "Packtisch"}
Overview.STATION_NAMES = table.freeze(STATION_NAMES)
local BUCKET_OF_KIND: {[string]: string} = ({RawStore = "raw", Supplier = "supplier", VehicleSlot = "vehicle",
	FinishedStore = "store", StationInput = "line", StationProcess = "line", StationOutput = "line", Carrier = "carried",
	Band = "carried", Recovery = "carried"})
table.freeze(BUCKET_OF_KIND)
local BACKLOG_TEXT: {[string]: string} = ({
	assembly = "Band wartet: Der Montageeingang ist belegt.",
	stopped = "Förderband angehalten: Der Bausatz wartet am Sägeausgang.",
})
table.freeze(BACKLOG_TEXT)

local function emptyWhere(): Where
	return {raw = 0, supplier = 0, vehicle = 0, line = 0, store = 0, carried = 0}
end

-- Used places of one kind. A place counts as used while it holds a batch or is promised to one (Return reservation).
local function placesOf(state: State.Profile, kind: string): Places?
	local capacity, used = 0, 0
	for id, location in state.locations do
		if location.kind == kind then
			capacity += 1
			if State.countAt(state, id) > 0 or state.reservations[id] ~= nil then used += 1 end
		end
	end
	if capacity == 0 then return nil end
	return {used = used, capacity = capacity, free = capacity - used, full = used >= capacity}
end

local function plural(count: number, one: string, many: string): string
	return count .. " " .. (if count == 1 then one else many)
end

-- Where the stock lies, in the order a player thinks about it.
local WHERE_NAMES = {{"raw", "Rohstofflager"}, {"supplier", "Lieferant"}, {"vehicle", "Anhänger"}, {"line", "Linie"},
	{"store", "Fertiglager"}, {"carried", "unterwegs"}}
local function whereText(where: Where): string
	local parts: {string} = {}
	for _, entry in WHERE_NAMES do
		local count = (where :: any)[entry[1]]
		if count > 0 then table.insert(parts, entry[2] .. " " .. count) end
	end
	return table.concat(parts, ", ")
end

-- `now` is the server time in seconds, `beltStopped` marks the first belt as switched off, `selectedRecipeId` is the
-- line's recipe choice, `progress` the profile's progress for owned equipment (nil counts as none). Every value comes from
-- the confirmed profile, so a rejected or unclear save changes nothing here.
function Overview.compute(state: State.Profile, selectedRecipeId: string?, now: number, beltStopped: boolean?, progress: any?): Overview
	local selected = Recipes.get(selectedRecipeId) or (Recipes.get(Recipes.DEFAULT_ID) :: Recipes.Recipe)
	local wood, cartons = emptyWhere(), emptyWhere()
	local inProgress = 0
	local counts: {[string]: number} = {}
	for _, batch in state.batches do
		local location = state.locations[batch.locationId]
		local bucket = if location then BUCKET_OF_KIND[location.kind] else nil
		if batch.stage == "Holzpaket" then
			if bucket then (wood :: any)[bucket] += 1 end
		elseif batch.stage == "Karton" then
			if bucket then (cartons :: any)[bucket] += 1 end
		else
			inProgress += 1
		end
		local key = batch.recipeId .. "|" .. batch.stage
		counts[key] = (counts[key] or 0) + 1
	end
	local woodTotal, cartonTotal = 0, 0
	for _, count in wood :: any do woodTotal += count end
	for _, count in cartons :: any do cartonTotal += count end

	-- Stock by recipe and stage, recipes in list order, stages in chain order.
	local stock: {StockEntry} = {}
	for _, recipe in Recipes.LIST do
		for _, stage in recipe.chain do
			local count = counts[recipe.id .. "|" .. stage]
			if count then
				table.insert(stock, {recipeId = recipe.id, stage = stage, name = Recipes.stageName(stage, recipe.id), count = count})
			end
		end
	end

	local places = {raw = placesOf(state, "RawStore"), store = placesOf(state, "FinishedStore"),
		vehicle = placesOf(state, "VehicleSlot")}
	local statuses = Line.status(state, now, beltStopped, selected.id)
	local list: {Bottleneck} = {}
	local function add(code: string, severity: string, message: string, stationId: string?)
		table.insert(list, {code = code, severity = severity, message = message, stationId = stationId})
	end

	-- Stations whose output waits for a pickup stand still until somebody moves the ware.
	for _, rule in State.STATIONS do
		local status = statuses[rule.id]
		if status and status.code == "OUTPUT_FULL" then
			add("OUTPUT_FULL", "stop", STATION_NAMES[rule.id] .. ": " .. Recipes.stageName(status.outputStage, status.recipeId)
				.. " am Ausgang abholen.", rule.id)
		end
	end
	local saw = statuses[State.SAW.id]
	if saw and saw.code == "BACKLOG" and saw.cause then
		add("BACKLOG", "limit", BACKLOG_TEXT[saw.cause] or BACKLOG_TEXT.assembly, State.SAW.id)
	end
	if state.pendingSale then
		add("SALE_OPEN", "action", "Verkauf offen: Bestätige den Karton am Käuferplatz oder lege ihn auf den Anhänger zurück.")
	end
	local store, vehicle = places.store, places.vehicle
	if store and store.full then
		add("STORE_FULL", "limit", "Fertiglager voll (" .. store.used .. "/" .. store.capacity .. "): Kartons verladen und verkaufen.")
	end
	if vehicle and vehicle.full then
		add("VEHICLE_FULL", "limit", "Anhänger voll (" .. vehicle.used .. "/" .. vehicle.capacity .. "): erst ausliefern oder entladen.")
	end

	-- Material: no wood anywhere. The workshop is idle when nothing is in progress either.
	if woodTotal == 0 then
		local idle = inProgress == 0 and cartonTotal == 0
		if state.money >= selected.price then
			add("NO_WOOD", if idle then "stop" else "hint", "Kein Holz: Kaufe beim Lieferanten ein " .. selected.packageName
				.. " für " .. selected.price .. ".")
		elseif state.advance == nil and next(state.batches) == nil then
			add("NO_MONEY", "stop", "Kein Geld für Holz (" .. selected.price .. "): Hole beim Lieferanten einen Materialvorschuss.")
		else
			add("NO_MONEY", if idle then "stop" else "hint", "Kein Geld für Holz (" .. selected.price
				.. "): Verkaufe zuerst fertige Ware.")
		end
	end
	if wood.supplier > 0 and vehicle then
		add("WOOD_AT_SUPPLIER", "hint", plural(wood.supplier, "Holzpaket liegt", "Holzpakete liegen")
			.. " beim Lieferanten: auf den Anhänger laden.")
	end
	if wood.vehicle > 0 then
		add("WOOD_ON_VEHICLE", "hint", plural(wood.vehicle, "Holzpaket", "Holzpakete")
			.. " auf dem Anhänger: im Rohstofflager entladen.")
	end
	if wood.raw > 0 and saw and saw.code == "INPUT_MISSING" then
		add("WOOD_IN_STORE", "hint", plural(wood.raw, "Holzpaket", "Holzpakete") .. " im Rohstofflager: zur Säge tragen.")
	end
	if cartons.store > 0 and not state.pendingSale then
		add("CARTONS_IN_STORE", "hint", plural(cartons.store, "Karton", "Kartons") .. " im Fertiglager: "
			.. (if vehicle then "auf den Anhänger laden und verkaufen." else "verkaufen."))
	end
	if cartons.vehicle > 0 and not state.pendingSale then
		add("CARTONS_ON_VEHICLE", "hint", plural(cartons.vehicle, "Karton", "Kartons")
			.. " auf dem Anhänger: zum Händler (" .. selected.dealer .. ") oder Privatkunden fahren.")
	end

	-- The slowest station of the selected recipe sets the pace of the line, with owned equipment applied (P10-04).
	local takt: string? = nil
	local slowest, slowestSeconds = Equipment.pace(progress, selected.id)
	local owned: {string} = {}
	for _, item in Equipment.LIST do
		if Equipment.owned(progress, item.id) then table.insert(owned, item.name) end
	end
	if slowest ~= "" then
		takt = STATION_NAMES[slowest] .. " bestimmt den Takt: " .. slowestSeconds .. " s je " .. selected.name .. "."
		add("TAKT", "info", takt :: string, slowest)
	end

	-- Stable order by severity, then by the order the rules found them.
	local ranked: {{index: number, item: Bottleneck}} = {}
	for index, item in list do table.insert(ranked, {index = index, item = item}) end
	table.sort(ranked, function(left: {index: number, item: Bottleneck}, right: {index: number, item: Bottleneck}): boolean
		local a, b = SEVERITY_ORDER[left.item.severity], SEVERITY_ORDER[right.item.severity]
		if a ~= b then return a < b end
		return left.index < right.index
	end)
	local bottlenecks: {Bottleneck} = {}
	for _, entry in ranked do table.insert(bottlenecks, entry.item) end

	return {
		money = state.money,
		advance = if state.advance then state.advance.amount else nil,
		recipe = {id = selected.id, name = selected.name, packageName = selected.packageName, price = selected.price,
			dealer = selected.dealer, takt = takt},
		wood = {total = woodTotal, where = wood},
		cartons = {total = cartonTotal, where = cartons},
		inProgress = inProgress,
		equipment = owned,
		stock = stock,
		places = places,
		saleOpen = state.pendingSale ~= nil,
		bottlenecks = bottlenecks,
	}
end

-- The most urgent bottleneck that is not the plain pace note, or nil when nothing blocks the line.
function Overview.primary(overview: Overview): Bottleneck?
	local first = overview.bottlenecks[1]
	if first and first.severity ~= "info" then return first end
	return nil
end

-- Label and value pairs for a compact HUD panel; short enough for a 250 px wide column.
function Overview.rows(overview: Overview): {Row}
	local rows: {Row} = {}
	local money = tostring(overview.money)
	if overview.advance then money ..= " · Vorschuss " .. overview.advance .. " offen" end
	table.insert(rows, {label = "Guthaben", value = money})
	table.insert(rows, {label = "Rezept", value = overview.recipe.name .. " · Einkauf " .. overview.recipe.price
		.. " · Händler " .. overview.recipe.dealer})
	table.insert(rows, {label = "Ausrüstung", value = if #overview.equipment > 0 then table.concat(overview.equipment, ", ") else "keine"})
	local wood = tostring(overview.wood.total)
	if overview.wood.total > 0 then wood ..= " (" .. whereText(overview.wood.where) .. ")" end
	table.insert(rows, {label = "Holz", value = wood})
	table.insert(rows, {label = "In Arbeit", value = tostring(overview.inProgress)})
	local cartons = tostring(overview.cartons.total)
	if overview.cartons.total > 0 then cartons ..= " (" .. whereText(overview.cartons.where) .. ")" end
	table.insert(rows, {label = "Kartons", value = cartons})
	local store, vehicle = overview.places.store, overview.places.vehicle
	if store then table.insert(rows, {label = "Fertiglager", value = store.used .. "/" .. store.capacity .. " belegt"}) end
	if vehicle then
		table.insert(rows, {label = "Anhänger", value = vehicle.used .. "/" .. vehicle.capacity .. " belegt · " .. vehicle.free .. " frei"})
	end
	local primary = Overview.primary(overview)
	table.insert(rows, {label = "Engpass", value = if primary then primary.message else "keiner"})
	return rows
end

return table.freeze(Overview)
