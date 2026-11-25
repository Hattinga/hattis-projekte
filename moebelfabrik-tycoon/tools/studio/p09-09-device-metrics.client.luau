--!strict
-- Install under StarterPlayerScripts in the device QA build. All metrics stay in this client.
if game.PlaceId ~= 79033653140107 or game.GameId ~= 10776116608 then return end
local players = game:GetService("Players")
local player = players.LocalPlayer
local test = workspace:WaitForChild("P0909WorkshopLoad", 180)
if not test or test:GetAttribute("TesterUserId") ~= player.UserId then return end
local runService = game:GetService("RunService")
local input = game:GetService("UserInputService")
local stats = game:GetService("Stats")
local settings = UserSettings():GetService("UserGameSettings")
local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "P0909DeviceMetrics"
gui.ResetOnSpawn = false
gui.DisplayOrder = -1 -- prompts and touch controls stay above the metrics panel on short screens
gui.Parent = playerGui
local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.fromScale(0.5, 0.03)
status.Size = UDim2.new(0.92, 0, 0, 124)
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(650, 124)
limit.Parent = status
status.BackgroundColor3 = Color3.fromRGB(32, 38, 32)
status.TextColor3 = Color3.fromRGB(255, 248, 222)
status.TextSize = 16
status.TextWrapped = true
status.Font = Enum.Font.GothamMedium
status.Parent = gui

local advice: {[string]: string} = {
	Aufbau = "Werkstätten werden aufgebaut.",
	Bereit = "Starte den Bandtest am Montageausgang.",
	["Band läuft"] = "Die beiden Werkstätten laufen.",
	["Rückstau"] = "Beobachte Band und Säge.",
	["Freiräumen"] = "Nimm den Rohhocker vom Montageausgang auf.",
	Wiederanlauf = "Geh zur anderen Gangseite und lege den Rohhocker am Finish-Eingang ab.",
	Fertig = "Beide Werkstätten haben geliefert.",
	Abgebrochen = "Gerätetest abgebrochen.",
}
local samples: {[string]: string} = {}
local phase = ""
local function render()
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.zero
	local quality = settings.SavedQualityLevel.Name:gsub("^QualityLevel", "")
	local lines = {
		string.format("%d × %d · %s · Grafik %s", size.X, size.Y, if input.TouchEnabled then "Touch" else "Desktop", quality),
		advice[phase] or phase,
	}
	for _, label in {"Rückstau", "Bandfahrt"} do
		if samples[label] then table.insert(lines, samples[label]) end
	end
	local notice = test:GetAttribute("Notice")
	if type(notice) == "string" then table.insert(lines, notice) end
	status.Text = table.concat(lines, "\n")
end

local function onPhase()
	phase = tostring(test:GetAttribute("Phase") or "Aufbau")
	render()
end

local function sample()
	local label = test:GetAttribute("SamplePhase")
	if label ~= "Rückstau" and label ~= "Bandfahrt" then return end
	task.spawn(function()
		local times: {number} = {}
		local elapsed = 0
		while test.Parent and test:GetAttribute("SamplePhase") == label do
			local delta = runService.PreRender:Wait()
			if test:GetAttribute("SamplePhase") ~= label then break end
			elapsed += delta
			table.insert(times, delta * 1000)
		end
		if #times == 0 or not test.Parent then return end
		table.sort(times)
		local tracked, memory = pcall(function() return stats:GetTotalMemoryUsageMb() end)
		local memoryText = if tracked and memory > 0 then string.format(" · %.0f MB", memory) else ""
		samples[label] = string.format("%s · %.1f s · %d Frames · p50 %.1f / p95 %.1f ms%s", label, elapsed, #times,
			times[math.ceil(#times * 0.5)], times[math.ceil(#times * 0.95)], memoryText)
		render()
	end)
end
test:GetAttributeChangedSignal("Phase"):Connect(onPhase)
test:GetAttributeChangedSignal("Notice"):Connect(render)
test:GetAttributeChangedSignal("SamplePhase"):Connect(sample)
local qualityChanged = settings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(render)
local camera = workspace.CurrentCamera
local viewportChanged = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(render) else nil
test.Destroying:Connect(function()
	qualityChanged:Disconnect()
	if viewportChanged then viewportChanged:Disconnect() end
	gui:Destroy()
end)
onPhase()
sample()
