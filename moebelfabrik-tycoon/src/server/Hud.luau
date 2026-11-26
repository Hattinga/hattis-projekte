--!strict
-- P10-03: the operating HUD of one player. A collapsible overview panel (stock, vehicle load, free places and the
-- current bottleneck), a confirmation toast for purchase, recipe choice and sale, and a touch bar with a recipe button
-- that asks for confirmation before it switches. The server builds the gui, a small LocalScript handles taps and timing.
-- Layout target: 800 x 360 logical pixels (the weaker Android profile in landscape); every button is at least 44 px high.
local Equipment = require(script.Parent.Equipment)
local Overview = require(script.Parent.Overview)
local Recipes = require(script.Parent.Recipes)

export type Result = {ok: boolean, code: string, message: string}
-- What a tap may do. Every handler runs on the server and checks owner, reach and state itself.
-- selectRecipe answers with a result the HUD confirms; buy and settle confirm in the demo themselves.
export type Handlers = {selectRecipe: (Player, string) -> Result?, buy: (Player) -> (), settle: (Player) -> (),
	buyEquipment: (Player, string) -> Result?}
export type Hud = {
	gui: ScreenGui,
	player: Player,
	remote: RemoteEvent,
	followingId: string?,
	offerId: string?, -- the equipment the card currently offers (P10-04)
	toastId: number,
	lastAction: number,
	rows: {TextLabel},
	connection: RBXScriptConnection?,
}

local Hud = {}
local INK = Color3.fromRGB(255, 248, 222)
local PANEL = Color3.fromRGB(32, 38, 32)
local BUTTON = Color3.fromRGB(70, 96, 72)
local SEVERITY_COLOR: {[string]: string} = {stop = "#ff7a66", action = "#ffc15e", limit = "#ffc15e", hint = "#8ec9ff", info = "#b6bdb0"}
local RATE_SECONDS = 0.4

-- Taps and toast timing. Everything the player may press has a server-side check, the client only asks.
local CLIENT = [[
local gui = script.Parent
local remote = gui:WaitForChild("Action")
local panel = gui:WaitForChild("Panel")
local header = panel:WaitForChild("Header")
local body = panel:WaitForChild("Body")
local arrow = header:WaitForChild("Arrow")
local bar = gui:WaitForChild("Bar")
local recipeButton = bar:WaitForChild("Recipe")
local buyButton = bar:WaitForChild("Buy")
local sellButton = bar:WaitForChild("Sell")
local equipButton = panel:WaitForChild("Equip")
local equipCard = gui:WaitForChild("EquipCard")
local card = gui:WaitForChild("Card")
local toast = gui:WaitForChild("Toast")
local function sync() arrow.Text = if body.Visible then "–" else "+" end
header.Activated:Connect(function()
	body.Visible = not body.Visible
	sync()
end)
recipeButton.Activated:Connect(function()
	equipCard.Visible = false
	card.Visible = gui:GetAttribute("FollowingId") ~= nil and not card.Visible
end)
equipButton.Activated:Connect(function()
	card.Visible = false
	equipCard.Visible = gui:GetAttribute("OfferId") ~= nil and not equipCard.Visible
end)
equipCard:WaitForChild("Cancel").Activated:Connect(function() equipCard.Visible = false end)
equipCard:WaitForChild("Confirm").Activated:Connect(function()
	local id = gui:GetAttribute("OfferId")
	equipCard.Visible = false
	if id then remote:FireServer("Equip", id) end
end)
gui:GetAttributeChangedSignal("OfferId"):Connect(function() equipCard.Visible = false end)
buyButton.Activated:Connect(function() remote:FireServer("Buy") end)
sellButton.Activated:Connect(function() remote:FireServer("Settle") end)
card:WaitForChild("Cancel").Activated:Connect(function() card.Visible = false end)
card:WaitForChild("Confirm").Activated:Connect(function()
	local id = gui:GetAttribute("FollowingId")
	card.Visible = false
	if id then remote:FireServer("SelectRecipe", id) end
end)
gui:GetAttributeChangedSignal("FollowingId"):Connect(function() card.Visible = false end)
local shown = 0
local function showToast()
	local id = gui:GetAttribute("ToastId")
	if type(id) ~= "number" or id == shown then return end
	shown = id
	toast.Visible = true
	task.delay(6, function()
		if shown == id then toast.Visible = false end
	end)
end
gui:GetAttributeChangedSignal("ToastId"):Connect(showToast)
showToast()
sync()
]]

local function label(parent: Instance, name: string, size: UDim2, textSize: number, bold: boolean?): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Size = size
	text.BackgroundTransparency = 1
	text.TextColor3 = INK
	text.TextSize = textSize
	text.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.RichText = true
	text.Parent = parent
	return text
end

local function button(parent: Instance, name: string, size: UDim2, text: string, textSize: number): TextButton
	assert(size.Y.Offset >= 44, "Touch targets need at least 44 px")
	local result = Instance.new("TextButton")
	result.Name = name
	result.Size = size
	result.BackgroundColor3 = BUTTON
	result.TextColor3 = INK
	result.TextSize = textSize
	result.Font = Enum.Font.GothamBold
	result.TextWrapped = true
	result.AutoButtonColor = true
	result.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = result
	result.Parent = parent
	return result
end

local function frame(parent: Instance, name: string, size: UDim2, color: Color3): Frame
	local result = Instance.new("Frame")
	result.Name = name
	result.Size = size
	result.BackgroundColor3 = color
	result.BackgroundTransparency = 0.12
	result.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = result
	result.Parent = parent
	return result
end

local function padded(parent: Instance, pixels: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, pixels), UDim.new(0, pixels)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, pixels), UDim.new(0, pixels)
	padding.Parent = parent
	return padding
end

-- `handlers.selectRecipe` runs for a tap on the confirmation card and answers like the V prompt; `buy` and `settle` run
-- for the touch buttons and reach the same code as the world prompts.
function Hud.create(player: Player, playerGui: Instance, handlers: Handlers): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "BetriebHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1 -- the touch controls and prompts stay above the panel on short screens
	gui.Parent = playerGui
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Action"
	remote.Parent = gui

	-- Overview panel: a header that always shows the bottleneck, a body with the rows behind one tap.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Position = UDim2.new(0, 8, 0, 110)
	panel.Size = UDim2.new(0, 250, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.Parent = gui
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 2)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	local header = button(panel, "Header", UDim2.new(1, 0, 0, 56), "", 13)
	header.LayoutOrder = 1
	header.BackgroundColor3 = PANEL
	header.BackgroundTransparency = 0.12
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.RichText = true
	header.Font = Enum.Font.GothamMedium
	local headerPadding = padded(header, 6)
	headerPadding.PaddingRight = UDim.new(0, 24)
	-- The arrow belongs to the client: it flips the body, the server never sees that state.
	local arrow = label(header, "Arrow", UDim2.fromOffset(18, 18), 14, true)
	arrow.AnchorPoint = Vector2.new(1, 0)
	arrow.Position = UDim2.new(1, 18, 0, -2)
	arrow.TextXAlignment = Enum.TextXAlignment.Right
	arrow.Text = "+" -- the Gotham font has no triangles
	-- P10-04: the equipment button sits under the header while something is on offer; its card asks before the purchase.
	local equipButton = button(panel, "Equip", UDim2.new(1, 0, 0, 44), "Ausrüstung", 13)
	equipButton.LayoutOrder = 2
	equipButton.Visible = false
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.LayoutOrder = 3
	body.Size = UDim2.new(1, 0, 0, 96)
	body.BackgroundColor3 = PANEL
	body.BackgroundTransparency = 0.12
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.Visible = false
	body.Parent = panel
	local rowList = Instance.new("UIListLayout")
	rowList.Padding = UDim.new(0, 3)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = body
	padded(body, 6)

	-- Touch bar: the recipe button. The confirmation card names price, value and pace before anything changes.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, -8, 0, 104)
	bar.Size = UDim2.new(0, 170, 0, 0)
	bar.AutomaticSize = Enum.AutomaticSize.Y
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local barList = Instance.new("UIListLayout")
	barList.Padding = UDim.new(0, 4)
	barList.SortOrder = Enum.SortOrder.LayoutOrder
	barList.Parent = bar
	local recipeButton = button(bar, "Recipe", UDim2.new(1, 0, 0, 44), "Rezept", 14)
	recipeButton.LayoutOrder = 1
	local buyButton = button(bar, "Buy", UDim2.new(1, 0, 0, 44), "Kaufen", 14)
	buyButton.LayoutOrder = 2
	local sellButton = button(bar, "Sell", UDim2.new(1, 0, 0, 44), "Verkauf bestätigen", 14)
	sellButton.LayoutOrder = 3
	sellButton.Visible = false -- only while a sale is open

	local card = frame(gui, "Card", UDim2.new(0, 330, 0, 172), PANEL)
	-- Below the status banner (it ends at about y = 95 on a 360 px high screen), above the bottom touch controls.
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 100)
	card.Visible = false
	padded(card, 10)
	label(card, "Title", UDim2.new(1, 0, 0, 24), 18, true)
	local detail = label(card, "Detail", UDim2.new(1, 0, 0, 62), 14)
	detail.Position = UDim2.fromOffset(0, 28)
	local confirm = button(card, "Confirm", UDim2.new(0.5, -6, 0, 48), "Wechseln", 16)
	confirm.AnchorPoint = Vector2.new(0, 1)
	confirm.Position = UDim2.fromScale(0, 1)
	local cancel = button(card, "Cancel", UDim2.new(0.5, -6, 0, 48), "Abbrechen", 16)
	cancel.AnchorPoint = Vector2.new(1, 1)
	cancel.Position = UDim2.fromScale(1, 1)
	cancel.BackgroundColor3 = Color3.fromRGB(96, 78, 66)

	-- Right of the panel column (8..258 px) and left of the recipe button (starts at 527 px on 705 px width).
	-- Equipment card: price, benefit for every recipe, the pace before and after and what is left for wood.
	local equipCard = frame(gui, "EquipCard", UDim2.new(0, 330, 0, 206), PANEL)
	equipCard.AnchorPoint = Vector2.new(0.5, 0)
	equipCard.Position = UDim2.new(0.5, 0, 0, 100)
	equipCard.Visible = false
	padded(equipCard, 10)
	label(equipCard, "Title", UDim2.new(1, 0, 0, 24), 18, true)
	local equipDetail = label(equipCard, "Detail", UDim2.new(1, 0, 0, 100), 13)
	equipDetail.Position = UDim2.fromOffset(0, 28)
	local equipConfirm = button(equipCard, "Confirm", UDim2.new(0.5, -6, 0, 48), "Kaufen", 16)
	equipConfirm.AnchorPoint = Vector2.new(0, 1)
	equipConfirm.Position = UDim2.fromScale(0, 1)
	local equipCancel = button(equipCard, "Cancel", UDim2.new(0.5, -6, 0, 48), "Abbrechen", 16)
	equipCancel.AnchorPoint = Vector2.new(1, 1)
	equipCancel.Position = UDim2.fromScale(1, 1)
	equipCancel.BackgroundColor3 = Color3.fromRGB(96, 78, 66)

	local toast = frame(gui, "Toast", UDim2.new(0, 250, 0, 0), Color3.fromRGB(58, 110, 64))
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.Position = UDim2.new(0, 266, 0, 110)
	toast.Visible = false
	padded(toast, 8)
	local toastList = Instance.new("UIListLayout")
	toastList.SortOrder = Enum.SortOrder.LayoutOrder
	toastList.Parent = toast
	local toastTitle = label(toast, "Title", UDim2.new(1, 0, 0, 0), 15, true)
	toastTitle.AutomaticSize = Enum.AutomaticSize.Y
	toastTitle.LayoutOrder = 1
	local toastDetail = label(toast, "Detail", UDim2.new(1, 0, 0, 0), 13)
	toastDetail.AutomaticSize = Enum.AutomaticSize.Y
	toastDetail.LayoutOrder = 2

	local client = Instance.new("LocalScript")
	client.Name = "HudClient"
	client.Source = CLIENT
	client.Parent = gui

	local hud: Hud = {gui = gui, player = player, remote = remote, followingId = nil, offerId = nil, toastId = 0,
		lastAction = -math.huge, rows = {}, connection = nil}
	hud.connection = remote.OnServerEvent:Connect(function(user: Player, action: any, value: any)
		if user ~= player or (action ~= "SelectRecipe" and action ~= "Buy" and action ~= "Settle" and action ~= "Equip") then return end
		local now = os.clock()
		if now - hud.lastAction < RATE_SECONDS then return end
		hud.lastAction = now
		if action == "Buy" then
			local ran = pcall(handlers.buy, user)
			if not ran then Hud.toast(hud, "warn", "Kauf nicht möglich", "Das hat gerade nicht geklappt.") end
			return
		elseif action == "Settle" then
			local ran = pcall(handlers.settle, user)
			if not ran then Hud.toast(hud, "warn", "Verkauf nicht abgeschlossen", "Das hat gerade nicht geklappt.") end
			return
		end
		if type(value) ~= "string" then return end
		if action == "Equip" then
			-- Only the equipment the card offers right now can be bought by a tap.
			if value ~= hud.offerId then return end
			local ran, result = pcall(handlers.buyEquipment, user, value)
			if not ran then
				Hud.toast(hud, "warn", "Ausrüstung nicht gekauft", "Das hat gerade nicht geklappt.")
			elseif result then
				Hud.toast(hud, if result.ok then "ok" else "warn", if result.ok then "Ausrüstung gekauft" else "Ausrüstung nicht gekauft",
					result.message)
			end
			return
		end
		-- The server's current following recipe is the only one a tap may select, whatever the client sent.
		if value ~= hud.followingId then return end
		local ran, result = pcall(handlers.selectRecipe, user, value)
		if not ran then
			Hud.toast(hud, "warn", "Rezept nicht gewechselt", "Das hat gerade nicht geklappt.")
		elseif result then
			Hud.toast(hud, if result.ok then "ok" else "warn", if result.ok then "Rezept gewechselt" else "Rezept nicht gewechselt",
				result.message)
		end
	end)
	return hud
end

-- The next recipe in the list; a single-recipe workshop has none.
local function following(currentId: string): Recipes.Recipe?
	for index, recipe in Recipes.LIST do
		if recipe.id == currentId then return Recipes.LIST[index % #Recipes.LIST + 1] end
	end
	return Recipes.LIST[1]
end
Hud.following = following

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Redraws header, rows, recipe button and card from one overview. `overview` always comes from a confirmed profile.
-- `offer` is the equipment on offer (nil when everything is owned): the button and its card show it before the purchase.
function Hud.update(hud: Hud, overview: Overview.Overview, offer: Equipment.Offer?)
	local gui = hud.gui
	local equipButton = gui.Panel.Equip :: TextButton
	if offer then
		hud.offerId = offer.id
		gui:SetAttribute("OfferId", offer.id)
		equipButton.Visible = true
		equipButton.Text = offer.name .. " · " .. offer.price
		local equipCard = gui.EquipCard :: Frame
		local equipTitle, equipDetail = equipCard.Title :: TextLabel, equipCard.Detail :: TextLabel
		equipTitle.Text = offer.name .. " kaufen?"
		local lines = {offer.benefit, offer.pace, "Preis " .. offer.price .. " · " .. (if offer.canAfford
			then "danach bleiben " .. offer.remaining .. " Spielgeld." else "dir fehlen " .. -offer.remaining .. " Spielgeld.")}
		if offer.aftermath then table.insert(lines, offer.aftermath) end
		equipDetail.Text = table.concat(lines, "\n")
		local equipConfirm = equipCard.Confirm :: TextButton
		equipConfirm.BackgroundColor3 = if offer.canAfford then BUTTON else Color3.fromRGB(80, 80, 76)
	else
		hud.offerId = nil
		gui:SetAttribute("OfferId", nil)
		equipButton.Visible = false
	end
	local primary = Overview.primary(overview)
	local header = gui.Panel.Header :: TextButton
	local color = if primary then SEVERITY_COLOR[primary.severity] else "#8fd18a"
	header.Text = string.format('<font color="%s">●</font> <b>Engpass</b>  %s', color, escape(if primary then primary.message else "keiner"))
	local rows = Overview.rows(overview)
	local body = gui.Panel.Body :: ScrollingFrame
	local shown = 0
	for _, row in rows do
		if row.label == "Engpass" then continue end -- the header already shows it
		shown += 1
		local text = hud.rows[shown]
		if not text then
			text = label(body, "Row" .. shown, UDim2.new(1, -8, 0, 0), 13)
			text.AutomaticSize = Enum.AutomaticSize.Y
			text.LayoutOrder = shown
			hud.rows[shown] = text
		end
		text.Text = "<b>" .. escape(row.label) .. "</b>  " .. escape(row.value)
	end
	for index = shown + 1, #hud.rows do hud.rows[index].Text = "" end

	local nextRecipe = following(overview.recipe.id)
	local current = Recipes.get(overview.recipe.id)
	local recipeButton = gui.Bar.Recipe :: TextButton
	local card = gui.Card :: Frame
	local buyButton, sellButton = gui.Bar.Buy :: TextButton, gui.Bar.Sell :: TextButton
	buyButton.Text = "Kaufen\n" .. overview.recipe.packageName .. " · " .. overview.recipe.price
	sellButton.Visible = overview.saleOpen
	if nextRecipe and current and nextRecipe.id ~= current.id then
		hud.followingId = nextRecipe.id
		gui:SetAttribute("FollowingId", nextRecipe.id)
		recipeButton.Text = "Rezept: " .. current.name .. "  ⇄  " .. nextRecipe.name
		local timing = Recipes.timing(nextRecipe.id, "Montage")
		local title, detail = card.Title :: TextLabel, card.Detail :: TextLabel
		title.Text = "Zu " .. nextRecipe.name .. " wechseln?"
		detail.Text = string.format("Einkauf %d · Händler %d · Montage %s s.\nVorhandenes Holz und Ware behalten ihr Rezept.",
			nextRecipe.price, nextRecipe.dealer, if timing then tostring(timing.durationSeconds) else "?")
	else
		hud.followingId = nil
		gui:SetAttribute("FollowingId", nil)
		recipeButton.Text = "Rezept: " .. overview.recipe.name
	end
end

-- A confirmation: kind "ok" is green, "warn" amber. The client shows it for six seconds, the last one stays readable
-- in the gui's attributes for tests and support.
function Hud.toast(hud: Hud, kind: string, title: string, detail: string)
	local toast = hud.gui.Toast :: Frame
	toast.BackgroundColor3 = if kind == "ok" then Color3.fromRGB(58, 110, 64) else Color3.fromRGB(140, 98, 36)
	local titleLabel, detailLabel = toast.Title :: TextLabel, toast.Detail :: TextLabel
	titleLabel.Text = escape(title)
	detailLabel.Text = escape(detail)
	hud.toastId += 1
	hud.gui:SetAttribute("ToastKind", kind)
	hud.gui:SetAttribute("ToastTitle", title)
	hud.gui:SetAttribute("ToastDetail", detail)
	hud.gui:SetAttribute("ToastId", hud.toastId)
end

function Hud.destroy(hud: Hud)
	if hud.connection then hud.connection:Disconnect() end
	hud.gui:Destroy()
end

return table.freeze(Hud)
