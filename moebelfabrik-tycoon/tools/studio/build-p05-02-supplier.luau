--!strict
-- Four marked prototype pickup pads on the existing supplier yard. Edit mode only.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local runService = game:GetService("RunService")
assert(runService:IsStudio() and not runService:IsRunning(), "Edit only")
local yard = workspace.CityGreybox.DeliveryYards.Holzlieferant
assert(yard:IsA("BasePart") and yard:GetAttribute("Role") == "Supplier" and not yard:FindFirstChild("P05Pickup"))
local scale = 25 / 7
local fixture = Instance.new("Model")
fixture.Name = "P05Pickup"
for index = 1, 4 do
	local pad = Instance.new("Part")
	pad.Name = "Slot" .. index
	pad.Anchored = true
	pad.CanCollide = false
	pad.Color = Color3.fromRGB(174, 129, 85)
	pad.Size = Vector3.new(0.80, 0.08, 0.65) * scale
	pad.CFrame = yard.CFrame * CFrame.new((index - 2.5) * 1.15 * scale, yard.Size.Y / 2 + 0.04 * scale, 4.9 * scale)
	pad:SetAttribute("Capacity", 1)
	pad.Parent = fixture
	local point = Instance.new("Attachment")
	point.Name = "Transfer"
	point.Position = Vector3.new(0, pad.Size.Y / 2, 0)
	point.Parent = pad
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.CanvasSize = Vector2.new(300, 200)
	surface.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "HOLZ " .. index
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 247, 216)
	label.Parent = surface
end
fixture.Parent = yard
return {path = fixture:GetFullName(), pads = 4}
