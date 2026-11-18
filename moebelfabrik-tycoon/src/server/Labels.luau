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
}) :: {Entry}

local byKey: {[string]: Entry} = {}
for _, entry in Labels.entries do
	assert(not byKey[entry.key], "Duplicate label key")
	byKey[entry.key] = entry
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
