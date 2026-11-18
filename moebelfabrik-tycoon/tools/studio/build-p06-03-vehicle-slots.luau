--!strict
-- P06-03 builder (Edit): Transfer points on trailer slots A/B; the static P02-04 stand-in load is archived
-- because vehicle load now comes from the inventory. Aborts if already applied.
assert(game.PlaceId == 79033653140107 and game.GameId == 10776116608, "Wrong test place")
local rs = game:GetService("RunService")
assert(rs:IsStudio() and not rs:IsRunning(), "Edit only")
local vehicle = workspace.P02Vehicle
assert(not vehicle:GetAttribute("VehicleId"), "P06-03 already applied")
local trailer = vehicle.Trailer
for _, name in {"SlotA", "SlotB"} do
	local pad = trailer.Slots[name] :: BasePart
	assert(not pad:FindFirstChild("Transfer"))
	local mount = Instance.new("Attachment")
	mount.Name = "Transfer"
	mount.Position = Vector3.new(0, pad.Size.Y / 2, 0) -- ware underside rests on the slot surface
	mount.Parent = pad
end
local storage = game:GetService("ServerStorage")
local archive = storage:FindFirstChild("P02VehicleArchive") or Instance.new("Folder")
archive.Name = "P02VehicleArchive"
archive.Parent = storage
trailer.Load.Parent = archive
vehicle:SetAttribute("VehicleId", "Quad1")
vehicle:SetAttribute("Revision", 3)
return {mounts = 2, archivedLoad = archive:FindFirstChild("Load") ~= nil}
