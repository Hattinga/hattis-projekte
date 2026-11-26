--!strict
-- In-world greybox labels: English source text, German via LocalizationService.FactoryLabels (LOCALIZATION.md).
local Labels = {}

export type Entry = {read key: string, read en: string, read de: string}

Labels.TABLE_NAME = "FactoryLabels"
Labels.entries = table.freeze({
	table.freeze({key = "kit.name", en = "PARTS KIT · 9 PARTS", de = "BAUSATZ · 9 TEILE"}),
	table.freeze({key = "stool.raw.name", en = "RAW STOOL", de = "ROHHOCKER"}),
	table.freeze({key = "stool.finished.name", en = "FINISHED STOOL", de = "FERTIGER HOCKER"}),
	table.freeze({key = "carton.name", en = "STOOL CARTON", de = "HOCKERKARTON"}),
	table.freeze({key = "carton.count", en = "1 STOOL", de = "1 HOCKER"}),
	table.freeze({key = "carton.batch", en = "BATCH", de = "CHARGE"}),
	table.freeze({key = "package.name", en = "WOOD PACKAGE", de = "HOLZPAKET"}),
	-- P05-08 station signs (PRODUCTION "Sichtbare Rückmeldung").
	table.freeze({key = "process.Saege", en = "CUTTING", de = "ZUSCHNITT"}),
	table.freeze({key = "process.Montage", en = "ASSEMBLY", de = "MONTAGE"}),
	table.freeze({key = "process.Finish", en = "FINISHING", de = "FINISH"}),
	table.freeze({key = "process.Packen", en = "PACKING", de = "VERPACKEN"}),
	table.freeze({key = "status.starting", en = "STARTING", de = "STARTET"}),
	table.freeze({key = "status.outputFull", en = "OUTPUT FULL", de = "AUSGANG VOLL"}),
	table.freeze({key = "status.transport", en = "TRANSPORT RUNNING", de = "TRANSPORT LÄUFT"}),
	table.freeze({key = "status.reserved", en = "OUTPUT RESERVED", de = "AUSGANG RESERVIERT"}),
	table.freeze({key = "missing.Holzpaket", en = "WOOD PACKAGE MISSING", de = "HOLZPAKET FEHLT"}),
	table.freeze({key = "missing.Bausatz", en = "PARTS KIT MISSING", de = "BAUSATZ FEHLT"}),
	table.freeze({key = "missing.Rohhocker", en = "RAW STOOL MISSING", de = "ROHHOCKER FEHLT"}),
	table.freeze({key = "missing.Fertig", en = "FINISHED STOOL MISSING", de = "FERTIGER HOCKER FEHLT"}),
	table.freeze({key = "collect.Bausatz", en = "COLLECT PARTS KIT", de = "BAUSATZ ABHOLEN"}),
	table.freeze({key = "collect.Rohhocker", en = "COLLECT RAW STOOL", de = "ROHHOCKER ABHOLEN"}),
	table.freeze({key = "collect.Fertig", en = "COLLECT FINISHED STOOL", de = "FERTIGEN HOCKER ABHOLEN"}),
	table.freeze({key = "collect.Karton", en = "COLLECT STOOL CARTON", de = "HOCKERKARTON ABHOLEN"}),
	table.freeze({key = "store.name", en = "FINISHED STORE", de = "FERTIGLAGER"}),
	table.freeze({key = "store.full", en = "STORE FULL – FREE A SLOT", de = "FERTIGLAGER VOLL – PLATZ FREIMACHEN"}),
	-- P09-05 first belt and backlog back to the saw.
	table.freeze({key = "status.backlog", en = "BACKLOG", de = "RÜCKSTAU"}),
	table.freeze({key = "status.cause.assembly", en = "ASSEMBLY INPUT FULL", de = "MONTAGE-EINGANG VOLL"}),
	table.freeze({key = "status.cause.stopped", en = "BELT STOPPED", de = "BAND ANGEHALTEN"}),
	table.freeze({key = "belt.running", en = "BELT RUNNING", de = "BAND LÄUFT"}),
	table.freeze({key = "belt.idle", en = "BELT WAITING", de = "BAND WARTET"}),
	table.freeze({key = "belt.stopped", en = "BELT STOPPED", de = "BAND ANGEHALTEN"}),
	-- P06-01 buyer drop-off pads.
	table.freeze({key = "dropoff.dealer", en = "DEALER DROP-OFF", de = "HÄNDLERANNAHME"}),
	table.freeze({key = "dropoff.private", en = "PRIVATE DROP-OFF", de = "PRIVATANNAHME"}),
	-- P10-02 Beistelltisch01 (TABLE.md). Stages shared with the stool keep their keys; a key with the recipe id as
	-- suffix replaces the stool text for the table (see Labels.stageKey).
	table.freeze({key = "kit.table.name", en = "PARTS KIT · 10 PARTS", de = "BAUSATZ · 10 TEILE"}),
	table.freeze({key = "table.raw.name", en = "RAW TABLE", de = "ROHTISCH"}),
	table.freeze({key = "table.finished.name", en = "FINISHED TABLE", de = "FERTIGER TISCH"}),
	table.freeze({key = "carton.table.name", en = "TABLE CARTON", de = "TISCHKARTON"}),
	table.freeze({key = "carton.table.count", en = "1 TABLE", de = "1 TISCH"}),
	table.freeze({key = "package.table.name", en = "TABLE WOOD PACKAGE", de = "TISCHHOLZPAKET"}),
	table.freeze({key = "missing.Rohtisch", en = "RAW TABLE MISSING", de = "ROHTISCH FEHLT"}),
	table.freeze({key = "missing.Holzpaket.Beistelltisch01", en = "TABLE WOOD MISSING", de = "TISCHHOLZ FEHLT"}),
	table.freeze({key = "missing.Fertig.Beistelltisch01", en = "FINISHED TABLE MISSING", de = "FERTIGER TISCH FEHLT"}),
	table.freeze({key = "collect.Rohtisch", en = "COLLECT RAW TABLE", de = "ROHTISCH ABHOLEN"}),
	table.freeze({key = "collect.Fertig.Beistelltisch01", en = "COLLECT FINISHED TABLE", de = "FERTIGEN TISCH ABHOLEN"}),
	table.freeze({key = "collect.Karton.Beistelltisch01", en = "COLLECT TABLE CARTON", de = "TISCHKARTON ABHOLEN"}),
	-- P10-02 recipe choice: the sign above the saw.
	table.freeze({key = "recipe.name.Hocker01", en = "RECIPE: STOOL", de = "REZEPT: HOCKER"}),
	table.freeze({key = "recipe.name.Beistelltisch01", en = "RECIPE: SIDE TABLE", de = "REZEPT: BEISTELLTISCH"}),
	table.freeze({key = "recipe.next.Hocker01", en = "NEXT: STOOL WOOD PACKAGE", de = "NÄCHSTES: HOLZPAKET HOCKER"}),
	table.freeze({key = "recipe.next.Beistelltisch01", en = "NEXT: TABLE WOOD PACKAGE", de = "NÄCHSTES: TISCHHOLZPAKET"}),
}) :: {Entry}

local byKey: {[string]: Entry} = {}
for _, entry in Labels.entries do
	assert(not byKey[entry.key], "Duplicate label key")
	byKey[entry.key] = entry
end

-- The key for a stage text: the recipe's own variant ("prefix.Stage.RecipeId") when one exists, else "prefix.Stage".
function Labels.stageKey(prefix: string, stage: string, recipeId: string?): string
	if recipeId ~= nil then
		local own = prefix .. "." .. stage .. "." .. recipeId
		if byKey[own] then return own end
	end
	return prefix .. "." .. stage
end

-- Source text for a TextLabel; AutoLocalize translates it for German clients.
function Labels.text(key: string): string
	local entry = byKey[key]
	assert(entry, "Unknown label key")
	return entry.en
end

-- Writes all entries into a LocalizationTable (en source, en-us/de/de-de values). Existing keys are replaced.
function Labels.fill(localizationTable: LocalizationTable)
	for _, entry in Labels.entries do
		localizationTable:SetEntryValue(entry.key, entry.en, "", "en-us", entry.en)
		localizationTable:SetEntryValue(entry.key, entry.en, "", "de", entry.de)
		localizationTable:SetEntryValue(entry.key, entry.en, "", "de-de", entry.de)
	end
end

return table.freeze(Labels)
