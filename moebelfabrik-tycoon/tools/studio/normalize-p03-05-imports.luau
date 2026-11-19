--!strict
-- Studio Edit builder. Use the JSON printed by compact-p03-05-metadata.mjs.
-- Scale once, physically turn the imported meshes, then set a separate canonical pivot for labels.
local STUDS_PER_METER = 25 / 7
local CONTROL = "ControlCube_1m"
local NORMALIZED = "P0305Normalized"
local ASSET_NAMES = {CONTROL, "Hocker01_Raw", "Hocker01_Finish", "Hocker01_Kit", "Saege01"}
local CENTER_TOLERANCE = 0.10 -- Studs after calibration, including the thinnest annotations.
local BOUNDS_TOLERANCE = 0.125
local YAW_MARGIN = 0.035

type Bounds = {low: Vector3, high: Vector3}
type Mesh = {name: string, center: Vector3, color: Color3, textureFile: string}
type Match = {part: MeshPart, mesh: Mesh, texture: string}
type Fit = {rotation: CFrame, quarterTurns: number, offset: Vector3, rms: number, maxError: number}
type Plan = {model: Model, matches: {Match}, pivot: CFrame, factor: number, fit: Fit, bounds: Bounds}

local function sourceBounds(low: {number}, high: {number}): Bounds
	-- Blender (X,Y,Z) -> Roblox (X,Z,-Y). The inverted axis exchanges its min and max.
	return {
		low = Vector3.new(low[1], low[3], -high[2]) * STUDS_PER_METER,
		high = Vector3.new(high[1], high[3], -low[2]) * STUDS_PER_METER,
	}
end

local function srgb(value: number): number
	value = math.clamp(value, 0, 1)
	return if value <= 0.0031308 then value * 12.92 else 1.055 * value ^ (1 / 2.4) - 0.055
end

local function textureReference(part: MeshPart): string
	local surface = part:FindFirstChildOfClass("SurfaceAppearance")
	if surface and surface.ColorMap ~= "" then return surface.ColorMap end
	if part.TextureID ~= "" then return part.TextureID end
	local content = if surface then surface.ColorMapContent else part.TextureContent
	if content.Uri then return content.Uri end
	return if content.Object then tostring(content.Object) else ""
end

local function baseName(name: string): string
	return (string.gsub(name, "%.%d+$", ""))
end

local function matchMeshes(model: Model, entries: any, materials: any): {Match}
	local meshes: {[string]: Mesh} = {}
	local matches: {Match} = {}
	for _, entry in entries do
		local name: string = entry[1]
		local bounds = sourceBounds(entry[2], entry[3])
		local material = assert(materials[entry[4]], "Missing source material for " .. name)
		assert(not meshes[name], "Duplicate manifest mesh " .. name)
		meshes[name] = {
			name = name,
			center = (bounds.low + bounds.high) / 2,
			color = Color3.new(srgb(material[1]), srgb(material[2]), srgb(material[3])),
			textureFile = material[4],
		}
	end

	local used: {[string]: boolean} = {}
	local unmapped: {MeshPart} = {}
	local function bind(part: MeshPart, mesh: Mesh)
		assert(not used[mesh.name], model.Name .. " duplicate live mesh " .. part.Name)
		local texture = textureReference(part)
		assert((mesh.textureFile ~= "") == (texture ~= ""), model.Name .. " unexpected texture on " .. part.Name)
		used[mesh.name] = true
		table.insert(matches, {part = part, mesh = mesh, texture = texture})
	end

	for _, node in model:GetDescendants() do
		if not node:IsA("BasePart") then continue end
		assert(node:IsA("MeshPart"), model.Name .. " unexpected physical part " .. node.Name)
		local exact = meshes[node.Name]
		if exact then bind(node, exact) else table.insert(unmapped, node) end
	end

	-- Blender uses .NNN numeric suffixes. Apply fallback only for a unique remaining match.
	for _, part in unmapped do
		local alias = baseName(part.Name)
		local candidate: Mesh? = nil
		for name, mesh in meshes do
			if not used[name] and baseName(name) == alias then
				assert(not candidate, model.Name .. " ambiguous mesh alias " .. part.Name)
				candidate = mesh
			end
		end
		bind(part, assert(candidate, model.Name .. " unknown mesh " .. part.Name))
	end
	assert(#matches == #entries, model.Name .. " imported mesh count differs from checks.json")
	return matches
end

local function fitYaw(assetName: string, matches: {Match}, pivot: CFrame, factor: number): Fit
	local expectedMean, importedMean = Vector3.zero, Vector3.zero
	for _, match in matches do
		expectedMean += match.mesh.center
		importedMean += pivot:PointToObjectSpace(match.part.Position) * factor
	end
	expectedMean /= #matches
	importedMean /= #matches

	local candidates: {Fit} = {}
	for quarterTurns = 0, (if assetName == CONTROL then 0 else 3) do
		local rotation = CFrame.Angles(0, quarterTurns * math.pi / 2, 0)
		local offset = rotation:VectorToWorldSpace(importedMean) - expectedMean
		local squaredError, maxError = 0, 0
		for _, match in matches do
			local imported = pivot:PointToObjectSpace(match.part.Position) * factor
			local error = (rotation:VectorToWorldSpace(imported) - offset - match.mesh.center).Magnitude
			squaredError += error * error
			maxError = math.max(maxError, error)
		end
		table.insert(candidates, {
			rotation = rotation, quarterTurns = quarterTurns, offset = offset,
			rms = math.sqrt(squaredError / #matches), maxError = maxError,
		})
	end
	table.sort(candidates, function(a, b) return a.rms < b.rms end)
	local fit = candidates[1]
	assert(fit.maxError <= CENTER_TOLERANCE, string.format("%s mesh centre residual %.4f studs", assetName, fit.maxError))
	assert(#candidates == 1 or candidates[2].rms - fit.rms > YAW_MARGIN, assetName .. " orientation fit is ambiguous")
	return fit
end

local function absVector(vector: Vector3): Vector3
	return Vector3.new(math.abs(vector.X), math.abs(vector.Y), math.abs(vector.Z))
end

local function inspectBounds(matches: {Match}, pose: (MeshPart) -> (CFrame, Vector3)): Bounds
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	for _, match in matches do
		local frame, size = pose(match.part)
		local radius = (absVector(frame.XVector) * size.X + absVector(frame.YVector) * size.Y
			+ absVector(frame.ZVector) * size.Z) * 0.5
		local first, last = frame.Position - radius, frame.Position + radius
		low = Vector3.new(math.min(first.X, low.X), math.min(first.Y, low.Y), math.min(first.Z, low.Z))
		high = Vector3.new(math.max(last.X, high.X), math.max(last.Y, high.Y), math.max(last.Z, high.Z))
	end
	return {low = low, high = high}
end

local function boundsError(actual: Bounds, expected: Bounds): number
	local low = absVector(actual.low - expected.low)
	local high = absVector(actual.high - expected.high)
	return math.max(low.X, low.Y, low.Z, high.X, high.Y, high.Z)
end

return function(stage: Model, metadata: any, calibrationFactor: number): any
	assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
	local run = game:GetService("RunService")
	assert(run:IsStudio() and not run:IsRunning(), "Edit only")
	assert(stage.Name == "P03ArtProbe" and stage:IsDescendantOf(workspace), "Wrong art probe")
	assert(metadata.task == "P03-05" and metadata.schema == "normalize-v1", "Wrong import metadata")
	assert(calibrationFactor > 0 and calibrationFactor < math.huge, "Invalid import scale")

	local stageRotation = stage:GetPivot().Rotation
	local plans: {Plan} = {}
	for _, name in ASSET_NAMES do
		local model = stage:FindFirstChild(name)
		assert(model and model:IsA("Model") and not model.PrimaryPart, "Missing or unexpected model root " .. name)
		assert(not model:GetAttribute(NORMALIZED) and not model:FindFirstChild("NativeLabels"), name .. " already prepared")
		local spec = assert(metadata.assets[name], "Missing metadata " .. name)
		local bounds = sourceBounds(spec.bounds[1], spec.bounds[2])
		local matches = matchMeshes(model, spec.meshes, metadata.materials)
		local pivot = model:GetPivot()
		-- The one metre block was calibrated before insertion of the other four assets.
		local factor = if name == CONTROL then 1 else calibrationFactor
		local fit = fitYaw(name, matches, pivot, factor)
		local predicted = inspectBounds(matches, function(part: MeshPart): (CFrame, Vector3)
			local localPose = pivot:ToObjectSpace(part.CFrame)
			local orientation = fit.rotation * localPose.Rotation
			local position = fit.rotation:VectorToWorldSpace(localPose.Position * factor) - fit.offset
			return CFrame.new(position) * orientation, part.Size * factor
		end)
		local error = boundsError(predicted, bounds)
		local tolerance = if name == CONTROL then 0.006 else BOUNDS_TOLERANCE
		assert(error <= tolerance, string.format("%s preflight bounds error %.4f studs", name, error))
		table.insert(plans, {model = model, matches = matches, pivot = pivot, factor = factor, fit = fit, bounds = bounds})
	end

	local report = {}
	for _, plan in plans do
		local model, pivot, fit = plan.model, plan.pivot, plan.fit
		for _, match in plan.matches do
			local part = match.part
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			if match.mesh.textureFile == "" then part.Color = match.mesh.color end
		end
		if plan.factor ~= 1 then model:ScaleTo(model:GetScale() * plan.factor) end
		local base = CFrame.new(pivot.Position) * stageRotation
		model:PivotTo(base * fit.rotation)
		-- Assigning WorldPivot moves the coordinate origin, leaving all geometry where PivotTo put it.
		local canonicalPivot = base * CFrame.new(fit.offset)
		model.WorldPivot = canonicalPivot
		local actual = model:GetPivot()
		assert((canonicalPivot.Position - actual.Position).Magnitude < 0.001
			and actual.XVector:Dot(base.XVector) > 0.99999 and actual.YVector:Dot(base.YVector) > 0.99999,
			model.Name .. " canonical root not applied")
		local liveBounds = inspectBounds(plan.matches, function(part: MeshPart): (CFrame, Vector3)
			return actual:ToObjectSpace(part.CFrame), part.Size
		end)
		local error = boundsError(liveBounds, plan.bounds)
		local tolerance = if model.Name == CONTROL then 0.006 else BOUNDS_TOLERANCE
		assert(error <= tolerance, string.format("%s live bounds error %.4f studs", model.Name, error))
		local colorCount, textureCount, liveCenterError = 0, 0, 0
		for _, match in plan.matches do
			local part, mesh = match.part, match.mesh
			local residual = (actual:PointToObjectSpace(part.Position) - mesh.center).Magnitude
			liveCenterError = math.max(residual, liveCenterError)
			assert(textureReference(part) == match.texture, "Texture changed on " .. part.Name)
			assert(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery,
				"Unsafe visual physics on " .. part.Name)
			if mesh.textureFile == "" then
				local actualColor, expectedColor = part.Color, mesh.color
				assert(math.max(math.abs(actualColor.R - expectedColor.R), math.abs(actualColor.G - expectedColor.G),
					math.abs(actualColor.B - expectedColor.B)) < 1 / 255, "Color did not apply on " .. part.Name)
				colorCount += 1
			else
				textureCount += 1
			end
		end
		assert(liveCenterError <= CENTER_TOLERANCE, model.Name .. " live centre residual differs from source")
		model:SetAttribute(NORMALIZED, true)
		local size = liveBounds.high - liveBounds.low
		report[model.Name] = {
			meshes = #plan.matches, plainColors = colorCount, textured = textureCount, scale = model:GetScale(),
			yawCorrectionDegrees = fit.quarterTurns * 90, fitRmsStuds = fit.rms,
			maxCenterErrorStuds = liveCenterError, maxBoundsErrorStuds = error,
			sizeStuds = {size.X, size.Y, size.Z}, bottomOffsetStuds = liveBounds.low.Y,
		}
	end
	return {status = "normalized", calibrationFactor = calibrationFactor, assets = report}
end
