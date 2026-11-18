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
