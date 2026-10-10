--[[
	GameClient  (LocalScript)
	À placer dans : StarterPlayer > StarterPlayerScripts

	Ce script crée toute l'interface (pas besoin de la dessiner à la main) :
	  - les stats (puissance, dégâts, pièces...) à gauche
	  - la barre de menus en bas : Forge, Minerais, Armes, Boutique, Donjon, Rebirth
	  - les notifications, le butin "+1 Rubis", les chiffres de dégâts
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataUpdate = remotes:WaitForChild("DataUpdate")
local Notify = remotes:WaitForChild("Notify")
local LootFx = remotes:WaitForChild("LootFx")
local HitFx = remotes:WaitForChild("HitFx")
local OpenPanel = remotes:WaitForChild("OpenPanel")
local Action = remotes:WaitForChild("Action")

local COLORS = {
	Panel = Color3.fromRGB(25, 27, 38),
	Row = Color3.fromRGB(40, 43, 58),
	Dark = Color3.fromRGB(18, 19, 28),
	Text = Color3.fromRGB(240, 240, 245),
	Sub = Color3.fromRGB(165, 170, 190),
	Gold = Color3.fromRGB(255, 200, 60),
	Good = Color3.fromRGB(70, 190, 100),
	Bad = Color3.fromRGB(225, 70, 70),
	Blue = Color3.fromRGB(65, 135, 255),
	Purple = Color3.fromRGB(165, 85, 255),
	Orange = Color3.fromRGB(255, 140, 50),
	Pink = Color3.fromRGB(220, 80, 160),
	Disabled = Color3.fromRGB(80, 82, 95),
}

local state = nil        -- dernières données reçues du serveur
local forgeSelection = {} -- { [idMinerai] = quantité choisie }

------------------------------------------------------------------------
-- PETITS OUTILS POUR CRÉER L'INTERFACE
------------------------------------------------------------------------
local function new(className, props)
	local instance = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function addCorner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
end

local function addStroke(parent, color, thickness)
	return new("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function addPadding(parent, pixels)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, pixels),
		PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, pixels),
		PaddingRight = UDim.new(0, pixels),
		Parent = parent,
	})
end

local function makeLabel(parent, props)
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	for key, value in pairs(props) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

local function makeButton(parent, text, color, props)
	local button = new("TextButton", {
		BackgroundColor3 = color,
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 18,
		AutoButtonColor = true,
	})
	addCorner(button, 8)
	for key, value in pairs(props or {}) do
		button[key] = value
	end
	button.Parent = parent
	return button
end

-- Bouton qui demande une confirmation ("Sûr ?") avant d'agir
local function confirmButton(button, normalText, onConfirm)
	local armed = false
	local token = 0
	button.Activated:Connect(function()
		if armed then
			armed = false
			button.Text = normalText
			onConfirm()
		else
			armed = true
			token = token + 1
			local myToken = token
			button.Text = "Sûr ?"
			task.delay(2.5, function()
				if armed and myToken == token and button.Parent then
					armed = false
					button.Text = normalText
				end
			end)
		end
	end)
end

-- Adapte la taille de l'interface à l'écran (PC, tablette, téléphone)
local scales = {}
local function addScale(frame)
	table.insert(scales, new("UIScale", { Parent = frame }))
end
local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.5, 1.25)
	for _, uiScale in ipairs(scales) do
		uiScale.Scale = scale
	end
end

local function getEquippedWeapon(data)
	for _, weapon in ipairs(data.Weapons) do
		if weapon.Id == data.Equipped then
			return weapon
		end
	end
	return nil
end

local function owned(oreId)
	if not state then
		return 0
	end
	return state.Data.Ores[oreId] or 0
end

local function colorTag(color, text)
	return '<font color="#' .. color:ToHex() .. '">' .. text .. "</font>"
end

------------------------------------------------------------------------
-- L'ÉCRAN PRINCIPAL
------------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "LootForgeUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Notifications (en haut au centre)
local notifFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(560, 10),
	BackgroundTransparency = 1,
	Parent = gui,
})
addScale(notifFrame)
new("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Parent = notifFrame,
})

local notifCount = 0
local function showNotification(text, color)
	notifCount = notifCount + 1
	local label = new("TextLabel", {
		LayoutOrder = notifCount,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.1,
		Text = text,
		TextColor3 = color or COLORS.Text,
		TextWrapped = true,
		Font = Enum.Font.FredokaOne,
		TextSize = 19,
		Parent = notifFrame,
	})
	addCorner(label, 10)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = label,
	})
	local stroke = addStroke(label, Color3.new(0, 0, 0), 2)

	-- Pas plus de 4 notifications à la fois
	local items = {}
	for _, child in ipairs(notifFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(items, child)
		end
	end
	if #items > 4 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #items - 4 do
			items[i]:Destroy()
		end
	end

	task.delay(4, function()
		if label.Parent then
			local info = TweenInfo.new(0.5)
			TweenService:Create(label, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
			task.delay(0.55, function()
				label:Destroy()
			end)
		end
	end)
end

-- Butin (à droite) : "+1 Rubis", "+12 💰"
local lootFeed = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(240, 260),
	BackgroundTransparency = 1,
	Parent = gui,
})
addScale(lootFeed)
new("UIListLayout", {
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Parent = lootFeed,
})

local lootCount = 0
local function showLoot(text, color)
	lootCount = lootCount + 1
	local label = new("TextLabel", {
		LayoutOrder = lootCount,
		Size = UDim2.fromOffset(240, 28),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color,
		Font = Enum.Font.FredokaOne,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0,
		Parent = lootFeed,
	})
	local items = {}
	for _, child in ipairs(lootFeed:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(items, child)
		end
	end
	if #items > 8 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #items - 8 do
			items[i]:Destroy()
		end
	end
	task.delay(2.2, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.45, function()
				label:Destroy()
			end)
		end
	end)
end

-- Stats (à gauche)
local statsFrame = new("Frame", {
	Name = "Stats",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, -10),
	Size = UDim2.fromOffset(270, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLORS.Panel,
	BackgroundTransparency = 0.15,
	Parent = gui,
})
addCorner(statsFrame, 12)
addStroke(statsFrame, Color3.new(0, 0, 0), 2)
addScale(statsFrame)
addPadding(statsFrame, 10)
new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = statsFrame })

local function statLine(order, color)
	return makeLabel(statsFrame, {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = color,
		TextSize = 18,
		Font = Enum.Font.FredokaOne,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Chargement...",
	})
end
local powerLabel = statLine(1, COLORS.Orange)
local damageLabel = statLine(2, Color3.fromRGB(255, 110, 110))
local coinsLabel = statLine(3, COLORS.Gold)
local oresLabel = statLine(4, Color3.fromRGB(110, 170, 255))
local rebirthLabel = statLine(5, Color3.fromRGB(200, 140, 255))
local weaponLabel = statLine(6, COLORS.Text)
local trainingLabel = statLine(7, Color3.fromRGB(110, 230, 140))
trainingLabel.Visible = false
local goalLabel = makeLabel(statsFrame, {
	LayoutOrder = 8,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	TextWrapped = true,
	TextSize = 14,
	Font = Enum.Font.GothamMedium,
	TextColor3 = COLORS.Sub,
})

-- Fenêtre des menus (au centre)
local window = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromOffset(620, 430),
	BackgroundColor3 = COLORS.Panel,
	Visible = false,
	Parent = gui,
})
addCorner(window, 14)
addStroke(window, Color3.new(0, 0, 0), 3)
addScale(window)
local titleLabel = makeLabel(window, {
	Position = UDim2.fromOffset(18, 8),
	Size = UDim2.new(1, -80, 0, 40),
	Font = Enum.Font.FredokaOne,
	TextSize = 28,
	TextColor3 = COLORS.Gold,
})
local closeButton = makeButton(window, "X", COLORS.Bad, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(38, 38),
	TextSize = 22,
})
local content = new("Frame", {
	Position = UDim2.fromOffset(14, 56),
	Size = UDim2.new(1, -28, 1, -70),
	BackgroundTransparency = 1,
	Parent = window,
})

local function makePanelFrame()
	return new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = content })
end

local function makeScroll(parent, props, useGrid)
	local scroll = new("ScrollingFrame", {
		BackgroundColor3 = COLORS.Dark,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	for key, value in pairs(props) do
		scroll[key] = value
	end
	scroll.Parent = parent
	addCorner(scroll, 10)
	if useGrid then
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(180, 66),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
	else
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	end
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 14),
		Parent = scroll,
	})
	return scroll
end

local function clearList(scroll)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function makeRow(parent, order, height)
	local row = new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height or 50),
		BackgroundColor3 = COLORS.Row,
		Parent = parent,
	})
	addCorner(row, 8)
	return row
end

local function makeSwatch(row, color)
	local swatch = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = color,
		Parent = row,
	})
	addCorner(swatch, 6)
	addStroke(swatch, Color3.new(0, 0, 0), 1.5)
	return swatch
end

local function emptyMessage(list, text)
	local row = makeRow(list, 0, 70)
	makeLabel(row, {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		TextWrapped = true,
		Text = text,
		TextColor3 = COLORS.Sub,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
	})
end

local refreshPanel -- défini plus bas

------------------------------------------------------------------------
-- MENU : FORGE
------------------------------------------------------------------------
local forgePanel = makePanelFrame()
local forgeList = makeScroll(forgePanel, { Size = UDim2.new(0.6, -6, 1, 0) })
local forgeSide = new("Frame", {
	Position = UDim2.new(0.6, 6, 0, 0),
	Size = UDim2.new(0.4, -6, 1, 0),
	BackgroundColor3 = COLORS.Row,
	Parent = forgePanel,
})
addCorner(forgeSide, 10)
addPadding(forgeSide, 10)
local forgeInfo = makeLabel(forgeSide, {
	Size = UDim2.new(1, 0, 1, -100),
	TextWrapped = true,
	RichText = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Enum.Font.GothamMedium,
	TextSize = 15,
})
local forgeClear = makeButton(forgeSide, "Vider", COLORS.Disabled, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, -52),
	Size = UDim2.new(1, 0, 0, 38),
})
local forgeButton = makeButton(forgeSide, "⚒ FORGER", COLORS.Orange, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 46),
	TextSize = 24,
})

local function countSelectionTypes()
	local types = 0
	for _, count in pairs(forgeSelection) do
		if count > 0 then
			types = types + 1
		end
	end
	return types
end

local function setSelection(oreId, count)
	count = math.max(0, math.min(owned(oreId), count))
	local current = forgeSelection[oreId] or 0
	if current == 0 and count > 0 and countSelectionTypes() >= Config.MaxOreTypes then
		showNotification("Maximum " .. Config.MaxOreTypes .. " types de minerais par arme !", COLORS.Bad)
		return
	end
	if count == 0 then
		forgeSelection[oreId] = nil
	else
		forgeSelection[oreId] = count
	end
	refreshPanel(true)
end

local function refreshForge()
	-- La sélection ne peut pas dépasser ce qu'on possède
	for oreId, count in pairs(forgeSelection) do
		local have = owned(oreId)
		if have <= 0 then
			forgeSelection[oreId] = nil
		elseif count > have then
			forgeSelection[oreId] = have
		end
	end

	clearList(forgeList)
	local any = false
	for index = #Config.Ores, 1, -1 do -- les meilleurs minerais en haut
		local ore = Config.Ores[index]
		local have = owned(ore.Id)
		if have > 0 then
			any = true
			local selected = forgeSelection[ore.Id] or 0
			local row = makeRow(forgeList, #Config.Ores - index, 52)
			makeSwatch(row, ore.Color)
			makeLabel(row, {
				Position = UDim2.fromOffset(44, 5),
				Size = UDim2.new(1, -200, 0, 22),
				Text = ore.Name,
				TextColor3 = Config.Rarities[ore.Rarity],
				TextSize = 17,
				Font = Enum.Font.FredokaOne,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			makeLabel(row, {
				Position = UDim2.fromOffset(44, 27),
				Size = UDim2.new(1, -200, 0, 18),
				Text = "×" .. Config.Format(ore.Mult) .. "  •  tu as " .. have,
				TextColor3 = COLORS.Sub,
				TextSize = 13,
				Font = Enum.Font.GothamMedium,
			})
			local minus = makeButton(row, "-", COLORS.Bad, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -124, 0.5, 0),
				Size = UDim2.fromOffset(30, 30),
			})
			makeLabel(row, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -88, 0.5, 0),
				Size = UDim2.fromOffset(34, 30),
				Text = tostring(selected),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = selected > 0 and COLORS.Gold or COLORS.Sub,
				Font = Enum.Font.FredokaOne,
				TextSize = 20,
			})
			local plus = makeButton(row, "+", COLORS.Good, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -54, 0.5, 0),
				Size = UDim2.fromOffset(30, 30),
			})
			local maxButton = makeButton(row, "Max", COLORS.Blue, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.fromOffset(44, 30),
				TextSize = 15,
			})
			minus.Activated:Connect(function()
				setSelection(ore.Id, (forgeSelection[ore.Id] or 0) - 1)
			end)
			plus.Activated:Connect(function()
				setSelection(ore.Id, (forgeSelection[ore.Id] or 0) + 1)
			end)
			maxButton.Activated:Connect(function()
				setSelection(ore.Id, owned(ore.Id))
			end)
		end
	end
	if not any then
		emptyMessage(forgeList, "Tu n'as aucun minerai. Va dans le donjon (🌀) et bats des monstres : chaque kill = +1 minerai !")
	end

	local preview = Config.PreviewForge(forgeSelection)
	local lines = {
		"<b>Sélection :</b> " .. preview.Total .. " minerai(s)",
		"<b>Types :</b> " .. preview.Types .. " / " .. Config.MaxOreTypes,
		"",
	}
	if preview.Ok then
		local kind = Config.WeaponKinds[preview.Kind]
		table.insert(lines, "<b>Arme :</b> " .. colorTag(COLORS.Orange, kind.Name .. " " .. Config.OreById[preview.MainOre].Of))
		table.insert(lines, "<b>Dégâts :</b> " .. colorTag(COLORS.Gold, "×" .. Config.Format(preview.Mult)) .. " (+ qualité)")
		if kind.AoE then
			table.insert(lines, colorTag(COLORS.Sub, "Lent, mais frappe TOUS les monstres autour."))
		else
			table.insert(lines, colorTag(COLORS.Sub, "Rapide, frappe un monstre à la fois."))
		end
	else
		table.insert(lines, colorTag(Color3.fromRGB(255, 120, 120), preview.Error or ""))
	end
	table.insert(lines, "")
	table.insert(lines, colorTag(COLORS.Sub, Config.MinOres .. "-" .. (Config.GreatswordOres - 1) .. " minerais = Katana"))
	table.insert(lines, colorTag(COLORS.Sub, Config.GreatswordOres .. "+ minerais = Espadon"))
	table.insert(lines, colorTag(COLORS.Sub, "Qualité au hasard : jusqu'à ×" .. Config.Qualities[#Config.Qualities].Mult .. " !"))
	forgeInfo.Text = table.concat(lines, "\n")
	forgeButton.BackgroundColor3 = preview.Ok and COLORS.Orange or COLORS.Disabled
end

forgeButton.Activated:Connect(function()
	local preview = Config.PreviewForge(forgeSelection)
	if not preview.Ok then
		showNotification(preview.Error or "Sélection invalide", COLORS.Bad)
		return
	end
	local payload = {}
	for oreId, count in pairs(forgeSelection) do
		payload[oreId] = count
	end
	Action:FireServer("Forge", payload)
	forgeSelection = {}
	refreshPanel(true)
end)

forgeClear.Activated:Connect(function()
	forgeSelection = {}
	refreshPanel(true)
end)

local function oresSignature()
	local parts = {}
	for _, ore in ipairs(Config.Ores) do
		table.insert(parts, tostring(owned(ore.Id)))
	end
	return table.concat(parts, ",")
end

------------------------------------------------------------------------
-- MENU : MINERAIS (vendre)
------------------------------------------------------------------------
local oresPanel = makePanelFrame()
local oresHeader = makeLabel(oresPanel, {
	Size = UDim2.new(1, -180, 0, 34),
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
})
local sellAllButton = makeButton(oresPanel, "Tout vendre", COLORS.Bad, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.fromOffset(170, 34),
})
confirmButton(sellAllButton, "Tout vendre", function()
	Action:FireServer("SellAllOres")
end)
local oresList = makeScroll(oresPanel, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })

local function refreshOres()
	oresHeader.Text = "🎒 Minerais : " .. state.OreTotal .. " / " .. state.Capacity
	clearList(oresList)
	local any = false
	for index = #Config.Ores, 1, -1 do
		local ore = Config.Ores[index]
		local have = owned(ore.Id)
		if have > 0 then
			any = true
			local row = makeRow(oresList, #Config.Ores - index, 52)
			makeSwatch(row, ore.Color)
			makeLabel(row, {
				Position = UDim2.fromOffset(44, 5),
				Size = UDim2.new(1, -300, 0, 22),
				Text = ore.Name .. "  x" .. have,
				TextColor3 = Config.Rarities[ore.Rarity],
				TextSize = 18,
				Font = Enum.Font.FredokaOne,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			makeLabel(row, {
				Position = UDim2.fromOffset(44, 27),
				Size = UDim2.new(1, -300, 0, 18),
				Text = ore.Rarity .. "  •  ×" .. Config.Format(ore.Mult) .. "  •  " .. Config.Format(ore.Sell) .. " 💰/u",
				TextColor3 = COLORS.Sub,
				TextSize = 13,
				Font = Enum.Font.GothamMedium,
			})
			local sellOne = makeButton(row, "Vendre 1", COLORS.Blue, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -124, 0.5, 0),
				Size = UDim2.fromOffset(100, 34),
				TextSize = 16,
			})
			local sellAll = makeButton(row, "Vendre tout", COLORS.Bad, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(110, 34),
				TextSize = 16,
			})
			sellOne.Activated:Connect(function()
				Action:FireServer("SellOre", { Id = ore.Id, Amount = 1 })
			end)
			confirmButton(sellAll, "Vendre tout", function()
				Action:FireServer("SellOre", { Id = ore.Id, Amount = owned(ore.Id) })
			end)
		end
	end
	if not any then
		emptyMessage(oresList, "Aucun minerai pour l'instant. Bats des monstres dans le donjon !")
	end
end

------------------------------------------------------------------------
-- MENU : ARMES
------------------------------------------------------------------------
local weaponsPanel = makePanelFrame()
local weaponsHeader = makeLabel(weaponsPanel, {
	Size = UDim2.new(1, 0, 0, 34),
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
})
local weaponsList = makeScroll(weaponsPanel, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })

local function weaponRow(order, weapon)
	local data = state.Data
	local isEquipped = (weapon and weapon.Id or 0) == data.Equipped
	local row = makeRow(weaponsList, order, 56)
	local ore = weapon and Config.OreById[weapon.MainOre]
	makeSwatch(row, ore and ore.Color or Color3.fromRGB(160, 115, 70))
	local qualityColor = weapon and Config.Rarities[weapon.Quality] or COLORS.Text
	makeLabel(row, {
		Position = UDim2.fromOffset(44, 6),
		Size = UDim2.new(1, -330, 0, 22),
		Text = Config.GetWeaponName(weapon),
		TextColor3 = qualityColor,
		TextSize = 18,
		Font = Enum.Font.FredokaOne,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local details = "Arme de départ"
	if weapon then
		details = "[" .. weapon.Quality .. "]  •  " .. weapon.OreCount .. " minerais"
	end
	makeLabel(row, {
		Position = UDim2.fromOffset(44, 30),
		Size = UDim2.new(1, -330, 0, 18),
		Text = details,
		TextColor3 = COLORS.Sub,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
	})
	makeLabel(row, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -226, 0.5, 0),
		Size = UDim2.fromOffset(80, 30),
		Text = "×" .. Config.Format(weapon and weapon.Mult or 1),
		TextColor3 = COLORS.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.FredokaOne,
		TextSize = 20,
	})
	local equipButton = makeButton(row, isEquipped and "Équipée" or "Équiper", isEquipped and COLORS.Disabled or COLORS.Good, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -124, 0.5, 0),
		Size = UDim2.fromOffset(96, 34),
		TextSize = 16,
	})
	if not isEquipped then
		equipButton.Activated:Connect(function()
			Action:FireServer("Equip", weapon and weapon.Id or 0)
		end)
	end
	if weapon then
		local priceText = "Vendre " .. Config.Format(Config.GetWeaponSellPrice(weapon))
		local sellButton = makeButton(row, priceText, COLORS.Bad, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(110, 34),
			TextSize = 15,
		})
		confirmButton(sellButton, priceText, function()
			Action:FireServer("SellWeapon", weapon.Id)
		end)
	end
end

local function refreshWeapons()
	local data = state.Data
	weaponsHeader.Text = "⚔ Armes : " .. #data.Weapons .. " / " .. Config.MaxWeapons
	clearList(weaponsList)
	local sorted = {}
	for _, weapon in ipairs(data.Weapons) do
		table.insert(sorted, weapon)
	end
	table.sort(sorted, function(a, b)
		return a.Mult > b.Mult
	end)
	for index, weapon in ipairs(sorted) do
		weaponRow(index, weapon)
	end
	weaponRow(#sorted + 1, nil) -- l'épée en bois, toujours disponible
end

local function weaponsSignature()
	local data = state.Data
	local parts = { tostring(data.Equipped) }
	for _, weapon in ipairs(data.Weapons) do
		table.insert(parts, weapon.Id .. ":" .. weapon.Mult)
	end
	return table.concat(parts, ",")
end

------------------------------------------------------------------------
-- MENU : BOUTIQUE (améliorations)
------------------------------------------------------------------------
local upgradesPanel = makePanelFrame()
local upgradesHeader = makeLabel(upgradesPanel, {
	Size = UDim2.new(1, 0, 0, 34),
	Font = Enum.Font.FredokaOne,
	TextSize = 20,
	TextColor3 = COLORS.Gold,
})
local upgradesList = makeScroll(upgradesPanel, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })

local function upgradeEffect(upgradeId, level)
	if upgradeId == "Capacity" then
		return Config.GetCapacity(level) .. " places"
	end
	return "+" .. (level * 15) .. "% de chance"
end

local function refreshUpgrades()
	local data = state.Data
	upgradesHeader.Text = "💰 Pièces : " .. Config.Format(data.Coins)
	clearList(upgradesList)
	for order, upgradeId in ipairs(Config.UpgradeOrder) do
		local upgrade = Config.Upgrades[upgradeId]
		local level = data.Upgrades[upgradeId] or 0
		local isMax = level >= upgrade.Max
		local row = makeRow(upgradesList, order, 78)
		makeLabel(row, {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -180, 0, 24),
			Text = upgrade.Name .. "  (niv. " .. level .. "/" .. upgrade.Max .. ")",
			Font = Enum.Font.FredokaOne,
			TextSize = 19,
		})
		makeLabel(row, {
			Position = UDim2.fromOffset(12, 31),
			Size = UDim2.new(1, -180, 0, 18),
			Text = upgrade.Description,
			TextColor3 = COLORS.Sub,
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
		})
		local effect = "Actuel : " .. upgradeEffect(upgradeId, level)
		if not isMax then
			effect = effect .. "  →  " .. upgradeEffect(upgradeId, level + 1)
		end
		makeLabel(row, {
			Position = UDim2.fromOffset(12, 52),
			Size = UDim2.new(1, -180, 0, 18),
			Text = effect,
			TextColor3 = Color3.fromRGB(120, 220, 150),
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
		})
		local cost = Config.GetUpgradeCost(upgradeId, level)
		local canBuy = not isMax and data.Coins >= cost
		local buyButton = makeButton(row, isMax and "MAX" or ("💰 " .. Config.Format(cost)), canBuy and COLORS.Good or COLORS.Disabled, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(150, 46),
			TextSize = 20,
		})
		if not isMax then
			buyButton.Activated:Connect(function()
				Action:FireServer("Upgrade", upgradeId)
			end)
		end
	end
end

------------------------------------------------------------------------
-- MENU : DONJON (téléportation)
------------------------------------------------------------------------
local teleportPanel = makePanelFrame()
local teleportGrid = makeScroll(teleportPanel, { Size = UDim2.fromScale(1, 1) }, true)

local function refreshTeleport()
	local data = state.Data
	clearList(teleportGrid)
	local hubButton = makeButton(teleportGrid, "🏠 Hub\n(entraînement, forge)", COLORS.Gold, {
		LayoutOrder = 0,
		TextSize = 16,
		TextWrapped = true,
	})
	hubButton.Activated:Connect(function()
		Action:FireServer("Teleport", 0)
		window.Visible = false
	end)
	for stage, info in ipairs(Config.Stages) do
		local unlocked = stage <= data.MaxStage
		local text
		if unlocked then
			text = "Étape " .. stage .. " : " .. info.Name .. "\nPV : " .. Config.Format(Config.GetEnemyHP(stage, false))
				.. "  •  Boss : " .. Config.Format(Config.GetEnemyHP(stage, true))
		else
			text = "🔒 Étape " .. stage .. "\nBats le boss de l'étape " .. (stage - 1)
		end
		local button = makeButton(teleportGrid, text, unlocked and info.Floor:Lerp(COLORS.Purple, 0.45) or COLORS.Disabled, {
			LayoutOrder = stage,
			TextSize = 14,
			TextWrapped = true,
		})
		addStroke(button, Color3.new(0, 0, 0), 1.5)
		button.Activated:Connect(function()
			Action:FireServer("Teleport", stage)
			if unlocked then
				window.Visible = false
			end
		end)
	end
end

------------------------------------------------------------------------
-- MENU : REBIRTH
------------------------------------------------------------------------
local rebirthPanel = makePanelFrame()
local rebirthInfo = makeLabel(rebirthPanel, {
	Size = UDim2.new(1, 0, 0, 200),
	TextWrapped = true,
	RichText = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Enum.Font.GothamMedium,
	TextSize = 17,
})
local rebirthBarBack = new("Frame", {
	Position = UDim2.fromOffset(0, 212),
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = COLORS.Dark,
	Parent = rebirthPanel,
})
addCorner(rebirthBarBack, 8)
local rebirthBarFill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = COLORS.Purple,
	Parent = rebirthBarBack,
})
addCorner(rebirthBarFill, 8)
local rebirthBarText = makeLabel(rebirthBarBack, {
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.FredokaOne,
	TextSize = 18,
	ZIndex = 2,
})
local rebirthButton = makeButton(rebirthPanel, "♻ REBIRTH", COLORS.Purple, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -4),
	Size = UDim2.fromOffset(280, 56),
	TextSize = 28,
})
confirmButton(rebirthButton, "♻ REBIRTH", function()
	Action:FireServer("Rebirth")
end)

local function refreshRebirth()
	local data = state.Data
	local cost = Config.GetRebirthCost(data.Rebirths)
	local currentMult = Config.GetRebirthMult(data.Rebirths)
	local nextMult = Config.GetRebirthMult(data.Rebirths + 1)
	rebirthInfo.Text = table.concat({
		"<b>Rebirths :</b> " .. data.Rebirths,
		"<b>Multiplicateur :</b> ×" .. currentMult .. "  →  " .. colorTag(COLORS.Gold, "×" .. nextMult),
		"(il booste l'entraînement ET les dégâts)",
		"",
		"<b>Prix :</b> " .. Config.Format(cost) .. " de puissance",
		colorTag(Color3.fromRGB(255, 120, 120), "Tu perds : ta puissance et tes étapes débloquées."),
		colorTag(Color3.fromRGB(120, 220, 150), "Tu gardes : armes, minerais, pièces, améliorations."),
	}, "\n")
	local ratio = math.clamp(data.Power / cost, 0, 1)
	rebirthBarFill.Size = UDim2.fromScale(ratio, 1)
	rebirthBarText.Text = Config.Format(data.Power) .. " / " .. Config.Format(cost) .. "  (" .. math.floor(ratio * 100) .. "%)"
	rebirthButton.BackgroundColor3 = ratio >= 1 and COLORS.Purple or COLORS.Disabled
end

------------------------------------------------------------------------
-- GESTION DES MENUS
------------------------------------------------------------------------
local panelDefs = {
	Forge = { Title = "⚒ Forge", Frame = forgePanel, Refresh = refreshForge, Signature = oresSignature },
	Ores = {
		Title = "🎒 Minerais",
		Frame = oresPanel,
		Refresh = refreshOres,
		Signature = function()
			return oresSignature() .. "|" .. state.Capacity
		end,
	},
	Weapons = { Title = "⚔ Armes", Frame = weaponsPanel, Refresh = refreshWeapons, Signature = weaponsSignature },
	Upgrades = {
		Title = "⬆ Boutique",
		Frame = upgradesPanel,
		Refresh = refreshUpgrades,
		Signature = function()
			local data = state.Data
			return data.Coins .. "|" .. data.Upgrades.Capacity .. "|" .. data.Upgrades.Luck
		end,
	},
	Teleport = {
		Title = "🌀 Donjon",
		Frame = teleportPanel,
		Refresh = refreshTeleport,
		Signature = function()
			return tostring(state.Data.MaxStage)
		end,
	},
	Rebirth = {
		Title = "♻ Rebirth",
		Frame = rebirthPanel,
		Refresh = refreshRebirth,
		Signature = function()
			return state.Data.Power .. "|" .. state.Data.Rebirths
		end,
	},
}
local currentPanel = nil
local signatures = {}

refreshPanel = function(force)
	if not currentPanel or not state or not window.Visible then
		return
	end
	local def = panelDefs[currentPanel]
	local signature = def.Signature()
	if force or signature ~= signatures[currentPanel] then
		signatures[currentPanel] = signature
		def.Refresh()
	end
end

local function openPanel(name, keepOpen)
	if currentPanel == name and window.Visible and not keepOpen then
		window.Visible = false
		return
	end
	currentPanel = name
	for id, def in pairs(panelDefs) do
		def.Frame.Visible = (id == name)
	end
	titleLabel.Text = panelDefs[name].Title
	window.Visible = true
	refreshPanel(true)
end

closeButton.Activated:Connect(function()
	window.Visible = false
end)

-- Barre de menus (en bas)
local MENU = {
	{ Id = "Forge", Text = "⚒ Forge", Color = COLORS.Orange },
	{ Id = "Ores", Text = "🎒 Minerais", Color = COLORS.Blue },
	{ Id = "Weapons", Text = "⚔ Armes", Color = Color3.fromRGB(95, 105, 135) },
	{ Id = "Upgrades", Text = "⬆ Boutique", Color = COLORS.Good },
	{ Id = "Teleport", Text = "🌀 Donjon", Color = COLORS.Purple },
	{ Id = "Rebirth", Text = "♻ Rebirth", Color = COLORS.Pink },
}
local menuFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -78),
	Size = UDim2.fromOffset(#MENU * 112 + (#MENU - 1) * 8, 54),
	BackgroundTransparency = 1,
	Parent = gui,
})
addScale(menuFrame)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = menuFrame,
})
for order, item in ipairs(MENU) do
	local button = makeButton(menuFrame, item.Text, item.Color, {
		LayoutOrder = order,
		Size = UDim2.fromOffset(112, 54),
		TextSize = 19,
	})
	addStroke(button, Color3.new(0, 0, 0), 2)
	button.Activated:Connect(function()
		openPanel(item.Id)
	end)
end

------------------------------------------------------------------------
-- STATS + OBJECTIF
------------------------------------------------------------------------
local function getGoal()
	local data = state.Data
	if data.Power >= Config.GetRebirthCost(data.Rebirths) then
		return "Tu peux faire un Rebirth ! (bouton ♻ ou autel violet)"
	end
	if #data.Weapons == 0 then
		if state.OreTotal < Config.MinOres then
			return "Passe le portail violet (🌀 Donjon) et bats " .. (Config.MinOres - state.OreTotal) .. " monstre(s) pour gagner des minerais."
		end
		return "Forge ta première arme à l'enclume (bouton ⚒ Forge) !"
	end
	if state.OreTotal >= state.Capacity then
		return "Sac plein : forge, vends tes minerais ou achète de la capacité (⬆ Boutique)."
	end
	if data.MaxStage < #Config.Stages then
		return "Bats le boss 👑 de l'étape " .. data.MaxStage .. " pour débloquer la suivante. Trop dur ? Entraîne-toi sur les tapis du hub !"
	end
	return "Entraîne-toi et prépare ton prochain Rebirth !"
end

local function updateStats()
	local data = state.Data
	powerLabel.Text = "💪 Puissance : " .. Config.Format(data.Power)
	damageLabel.Text = "⚔ Dégâts : " .. Config.Format(state.Damage)
	coinsLabel.Text = "💰 Pièces : " .. Config.Format(data.Coins)
	oresLabel.Text = "🎒 Minerais : " .. state.OreTotal .. " / " .. state.Capacity
	oresLabel.TextColor3 = state.OreTotal >= state.Capacity and Color3.fromRGB(255, 110, 110) or Color3.fromRGB(110, 170, 255)
	rebirthLabel.Text = "♻ Rebirths : " .. data.Rebirths .. "  (×" .. Config.GetRebirthMult(data.Rebirths) .. ")"
	local weapon = getEquippedWeapon(data)
	weaponLabel.Text = "🗡 " .. Config.GetWeaponName(weapon)
	weaponLabel.TextColor3 = weapon and Config.Rarities[weapon.Quality] or COLORS.Text
	trainingLabel.Visible = state.Training > 0
	trainingLabel.Text = "🏋 Entraînement : +" .. Config.Format(state.Training) .. "/s"
	goalLabel.Text = "🎯 " .. getGoal()
end

------------------------------------------------------------------------
-- EFFETS : butin qui vole vers le joueur, chiffres de dégâts
------------------------------------------------------------------------
local function flyLoot(position, color)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local cube = new("Part", {
		Size = Vector3.new(0.9, 0.9, 0.9),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.Neon,
		Color = color,
		CFrame = CFrame.new(position + Vector3.new(0, 1, 0)),
		Parent = workspace,
	})
	local tween = TweenService:Create(cube, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = root.CFrame,
		Size = Vector3.new(0.2, 0.2, 0.2),
	})
	tween:Play()
	Debris:AddItem(cube, 0.7)
end

HitFx.OnClientEvent:Connect(function(position, amount, killed)
	local anchor = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position + Vector3.new(math.random(-15, 15) / 10, 0.5, math.random(-15, 15) / 10),
		Parent = workspace,
	})
	local billboard = new("BillboardGui", {
		Size = UDim2.fromOffset(150, 46),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = anchor,
	})
	local text = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = (killed and "💥 " or "") .. Config.Format(amount),
		TextColor3 = killed and COLORS.Gold or Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		Parent = billboard,
	})
	TweenService:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, 4, 0),
	}):Play()
	TweenService:Create(text, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(anchor, 0.85)
end)

LootFx.OnClientEvent:Connect(function(info)
	for _, oreId in ipairs(info.Ores or {}) do
		local ore = Config.OreById[oreId]
		if ore then
			showLoot("+1 " .. ore.Name, Config.Rarities[ore.Rarity])
			flyLoot(info.Position, ore.Color)
		end
	end
	if info.Coins and info.Coins > 0 then
		showLoot("+" .. Config.Format(info.Coins) .. " 💰", COLORS.Gold)
	end
end)

Notify.OnClientEvent:Connect(function(text, color)
	showNotification(text, color)
end)

OpenPanel.OnClientEvent:Connect(function(name)
	if panelDefs[name] then
		openPanel(name, true)
	end
end)

DataUpdate.OnClientEvent:Connect(function(newState)
	state = newState
	updateStats()
	refreshPanel(false)
end)

------------------------------------------------------------------------
-- DÉMARRAGE
------------------------------------------------------------------------
updateScale()
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

Action:FireServer("RequestData") -- demande nos données au serveur
