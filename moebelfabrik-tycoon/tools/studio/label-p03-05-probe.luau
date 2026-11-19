--!strict
-- Edit-time builder: native, per-player localizable labels, never baked word meshes.
-- Host passes assets/p03-models/p03-05-import/labels.json as decoded metadata.
local TRANSLATIONS: {[string]: {english: string, german: string}} = {
	["stool.raw"]={english="RAW",german="ROH"},
	["stool.finished"]={english="FINISHED",german="FERTIG"},
	["kit.parts"]={english="PARTS KIT",german="BAUSATZ"},
	["saw.name"]={english="SAW 01",german="SÄGE 01"},
	["saw.status"]={english="CLEAR",german="FREI"},
	["saw.input"]={english="IN",german="EIN"},
	["saw.process"]={english="PROCESS",german="PROZESS"},
	["saw.output"]={english="OUT",german="AUS"},
}
local SCALE=25/7
local function mapped(value: {number}): Vector3
	return Vector3.new(value[1],value[3],-value[2])
end
local function srgb(value: number): number
	return if value<=0.0031308 then value*12.92 else 1.055*value^(1/2.4)-0.055
end

return function(stage: Model, metadata: any): any
	assert(game.PlaceId==79033653140107 and game.GameId==10776116608,"Wrong test place")
	local run=game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(),"Edit only")
	assert(stage.Name=="P03ArtProbe" and metadata.word_geometry_in_fbx==false,"Wrong import metadata")
	local service=game:GetService("LocalizationService")
	local existing=service:FindFirstChild("FactoryLabels")
	assert(not existing or existing:IsA("LocalizationTable"), "FactoryLabels has an incompatible type")
	local localization=(existing or Instance.new("LocalizationTable")) :: LocalizationTable
	localization.Name="FactoryLabels"
	localization.SourceLocaleId="en-us"
	local entries=localization:GetEntries()
	local existingKeys={}
	for _,entry in entries do
		if entry.Key then existingKeys[entry.Key]=entry end
	end
	for key,words in TRANSLATIONS do
		local found=existingKeys[key]
		if found then
			assert(found.Source==words.english and found.Values["de-de"]==words.german, "Conflicting translation " .. key)
		else
			table.insert(entries,{Key=key,Source=words.english,Context="",Values={
				["en-us"]=words.english,["de-de"]=words.german,["de"]=words.german}})
		end
	end
	localization:SetEntries(entries)
	localization.Parent=service
	local count=0
	for assetName,labels in metadata.labels do
		local model=stage:FindFirstChild(assetName)
		assert(model and model:IsA("Model"),"Missing imported asset " .. assetName)
		assert(not model:FindFirstChild("NativeLabels"),"Labels already exist on " .. assetName)
		local root=model:GetPivot()
		local folder=Instance.new("Folder")
		folder.Name="NativeLabels"
		folder.Parent=model
		for _,label in labels do
			local words=TRANSLATIONS[label.key]
			assert(words,"Unknown label key " .. tostring(label.key))
			local normal=root:VectorToWorldSpace(mapped(label.normal_root_blender))
			local position=root:PointToWorldSpace(mapped(label.anchor_root_blender_m)*SCALE)
			local up=root:VectorToWorldSpace(mapped(label.up_root_blender))
			local anchor=Instance.new("Part")
			anchor.Name=label.key
			anchor:SetAttribute("LocalizationKey",label.key)
			anchor:SetAttribute("OwnerTask","P03-05")
			anchor.Anchored=true
			anchor.CanCollide=false
			anchor.CanTouch=false
			anchor.CanQuery=false
			anchor.Transparency=1
			anchor.Size=Vector3.new(label.surface_area_width_height_m[1]*SCALE,
				label.surface_area_width_height_m[2]*SCALE,0.0001*SCALE)
			local front=position+normal*0.012
			anchor.CFrame=CFrame.lookAt(front,front+normal,up)
			anchor.Parent=folder
			local gui=Instance.new("SurfaceGui")
			gui.Name="LocalizedLabel"
			gui.Adornee=anchor
			gui.Face=Enum.NormalId.Front
			gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize=Vector2.new(768,math.max(96,768*anchor.Size.Y/anchor.Size.X))
			gui.LightInfluence=0.4
			gui.AlwaysOnTop=false
			gui.AutoLocalize=true
			gui.RootLocalizationTable=localization
			gui.Parent=anchor
			local text=Instance.new("TextLabel")
			text.Name="Text"
			text.Size=UDim2.fromScale(1,1)
			text.BackgroundTransparency=1
			text.Text=words.english
			text.TextScaled=true
			text.TextWrapped=false
			text.Font=Enum.Font.SourceSansSemibold
			local color=label.foreground_base_color_linear
			text.TextColor3=Color3.new(srgb(color[1]),srgb(color[2]),srgb(color[3]))
			text.AutoLocalize=true
			text.RootLocalizationTable=localization
			text:SetAttribute("LocalizationKey",label.key)
			text.Parent=gui
			count+=1
		end
	end
	assert(count==8,"Expected eight translated labels")
	stage:SetAttribute("SupportedLocales","en-us,de-de")
	game:GetService("ChangeHistoryService"):SetWaypoint("P03-05 native EN-DE labels")
	return {labels=count,sourceLocale="en-us",translatedLocales={"de-de","de"}}
end
