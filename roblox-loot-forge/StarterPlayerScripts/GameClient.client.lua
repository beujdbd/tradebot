--[[
	GameClient  (LocalScript)
	À placer dans : StarterPlayer > StarterPlayerScripts

	Ce script crée toute l'interface (pas besoin de la dessiner à la main) :
	  - les stats (puissance, dégâts, pièces, minerais) en pastilles à gauche
	  - la barre de menus en bas : Forge, Minerais, Armes, Boutique, Donjon, Rebirth
	  - les notifications, le butin "+1 Rubis", les chiffres de dégâts
	Pour changer les couleurs ou les polices : regarde la partie STYLE plus bas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

if not RunService:IsClient() then
	warn("[LootForge] GameClient doit être un LocalScript (pas un Script), placé dans StarterPlayer > StarterPlayerScripts.")
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Message rouge en haut de l'écran quand l'installation a un problème
local function showFatal(text)
	warn("[LootForge] " .. text)
	if playerGui:FindFirstChild("LootForgeError") then
		return nil -- le serveur a déjà affiché l'explication
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "LootForgeClientError"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 100
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.Size = UDim2.new(0.85, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundColor3 = Color3.fromRGB(150, 25, 25)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextWrapped = true
	label.Text = "⚠ " .. text
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = screen
	screen.Parent = playerGui
	return screen
end

-- Attend un objet ; s'il tarde trop, explique le problème à l'écran mais continue
-- d'attendre (et enlève le message s'il finit par arriver)
local function waitFor(name, problem)
	local object = ReplicatedStorage:WaitForChild(name, 20)
	if object then
		return object
	end
	local banner = showFatal(problem)
	object = ReplicatedStorage:WaitForChild(name)
	if banner then
		banner:Destroy()
	end
	return object
end

local configModule = waitFor("GameConfig", "Je ne trouve pas le ModuleScript « GameConfig » dans ReplicatedStorage. Crée-le "
	.. "(ReplicatedStorage → + → ModuleScript), appelle-le exactement GameConfig et colle le script 1 dedans.")
local configLoaded, Config = pcall(require, configModule)
if not configLoaded or type(Config) ~= "table" or type(Config.Ores) ~= "table" then
	showFatal("GameConfig contient une erreur ou pas le bon code. Efface TOUT (Ctrl+A puis Suppr) et recolle le script 1 en entier.")
	-- Prévient le serveur que l'interface a bien démarré (pour qu'il n'affiche pas un 2e message trompeur)
	local earlyRemotes = ReplicatedStorage:FindFirstChild("Remotes")
	local earlyAction = earlyRemotes and earlyRemotes:FindFirstChild("Action")
	if earlyAction then
		earlyAction:FireServer("ClientConfigError")
	end
	return
end
local remotes = waitFor("Remotes", "Le script serveur ne s'est pas lancé. GameServer doit être un Script (pas un "
	.. "LocalScript) dans ServerScriptService, avec TOUT le script 2 collé dedans. Regarde la fenêtre Output (View → Output).")
local DataUpdate = remotes:WaitForChild("DataUpdate")
local Notify = remotes:WaitForChild("Notify")
local LootFx = remotes:WaitForChild("LootFx")
local HitFx = remotes:WaitForChild("HitFx")
local OpenPanel = remotes:WaitForChild("OpenPanel")
local Action = remotes:WaitForChild("Action")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

------------------------------------------------------------------------
-- STYLE : couleurs, polices (change-les ici pour personnaliser l'interface)
------------------------------------------------------------------------
local THEME = {
	Glass = Color3.fromRGB(16, 20, 34),   -- fond des panneaux
	Card = Color3.fromRGB(30, 36, 58),    -- lignes et cartes
	Inset = Color3.fromRGB(10, 13, 24),   -- fond des listes
	Text = Color3.fromRGB(246, 247, 255),
	Sub = Color3.fromRGB(152, 162, 194),
	Gold = Color3.fromRGB(255, 204, 64),
	Good = Color3.fromRGB(46, 204, 113),
	Bad = Color3.fromRGB(242, 72, 92),
	Blue = Color3.fromRGB(60, 150, 255),
	Muted = Color3.fromRGB(74, 81, 110),
}
local ACCENT = {
	Forge = Color3.fromRGB(255, 140, 40),
	Ores = Color3.fromRGB(52, 150, 255),
	Weapons = Color3.fromRGB(240, 70, 110),
	Upgrades = Color3.fromRGB(40, 200, 120),
	Teleport = Color3.fromRGB(140, 90, 255),
	Rebirth = Color3.fromRGB(230, 80, 200),
}
local FONT_TITLE = Enum.Font.FredokaOne
local FONT_BOLD = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.GothamMedium
local WHITE = Color3.new(1, 1, 1)

local state = nil        -- dernières données reçues du serveur
local forgeSelection = {} -- { [idMinerai] = quantité choisie }

------------------------------------------------------------------------
-- PETITS OUTILS POUR CRÉER L'INTERFACE
------------------------------------------------------------------------
local function new(className, props)
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
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

local function darken(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighten(color, amount)
	return color:Lerp(WHITE, amount)
end

-- Coins arrondis : un nombre = rayon en pixels, rien = complètement rond (pilule)
local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius and UDim.new(0, radius) or UDim.new(1, 0), Parent = parent })
end

local function outline(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Léger dégradé : le haut est plus clair que le bas (effet "bouton de jeu")
local function gloss(parent)
	return new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(196, 198, 214)),
		Parent = parent,
	})
end

local function padding(parent, top, right, bottom, left)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
		Parent = parent,
	})
end

local function listLayout(parent, gap, props)
	local layout = new("UIListLayout", { Padding = UDim.new(0, gap or 0), SortOrder = Enum.SortOrder.LayoutOrder })
	for key, value in pairs(props or {}) do
		layout[key] = value
	end
	layout.Parent = parent
	return layout
end

local function label(parent, props)
	local text = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		TextColor3 = THEME.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	for key, value in pairs(props) do
		text[key] = value
	end
	text.Parent = parent
	return text
end

-- Petite animation : grossit au survol (souris), s'écrase quand on appuie (souris ou doigt)
local function pressEffect(button)
	local scale = new("UIScale", { Parent = button })
	local hovered = false
	local function scaleTo(value, duration)
		TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	button.InputBegan:Connect(function(input)
		if button:GetAttribute("Disabled") then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement then
			hovered = true
			scaleTo(1.05, 0.12)
		elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			scaleTo(0.93, 0.06)
			local connection
			connection = input.Changed:Connect(function()
				local inputState = input.UserInputState
				if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
					connection:Disconnect()
					if kind == Enum.UserInputType.Touch then
						hovered = false -- pas de "survol" sur un écran tactile
					end
					scaleTo(hovered and 1.05 or 1, 0.1)
				end
			end)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			hovered = false
			scaleTo(1, 0.12)
		end
	end)
end

-- Bouton arrondi (pilule) avec dégradé, contour et animation
local function makeButton(parent, text, color, props)
	local button = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Text = text,
		Font = FONT_TITLE,
		TextSize = 17,
		TextColor3 = WHITE,
		TextStrokeColor3 = darken(color, 0.6),
		TextStrokeTransparency = 0.65,
	})
	corner(button)
	gloss(button)
	outline(button, darken(color, 0.45), 2)
	for key, value in pairs(props or {}) do
		button[key] = value
	end
	-- Point d'ancrage au centre : l'animation grossit le bouton depuis son milieu
	if not parent:FindFirstChildWhichIsA("UIGridStyleLayout") then
		local anchor, size = button.AnchorPoint, button.Size
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = button.Position + UDim2.new(size.X.Scale * (0.5 - anchor.X), size.X.Offset * (0.5 - anchor.X),
			size.Y.Scale * (0.5 - anchor.Y), size.Y.Offset * (0.5 - anchor.Y))
	end
	button.Parent = parent
	pressEffect(button)
	return button
end

local function recolor(button, color)
	button.BackgroundColor3 = color
	button.TextStrokeColor3 = darken(color, 0.6)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = darken(color, 0.45)
	end
end

-- Bouton grisé et sans animation quand l'action n'est pas possible
local function setEnabled(button, enabled, color)
	recolor(button, enabled and color or THEME.Muted)
	button.BackgroundTransparency = enabled and 0 or 0.45
	button.TextTransparency = enabled and 0 or 0.4
	button:SetAttribute("Disabled", not enabled)
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

-- Panneau "verre" sombre aux coins arrondis
local function glassFrame(props, radius)
	local frame = new("Frame", { BackgroundColor3 = THEME.Glass, BackgroundTransparency = 0.06 })
	for key, value in pairs(props) do
		if key ~= "Parent" then
			frame[key] = value
		end
	end
	corner(frame, radius or 18)
	outline(frame, WHITE, 1.5, 0.86)
	frame.Parent = props.Parent
	return frame
end

-- Texte foncé sur les couleurs claires, blanc sur les couleurs foncées
local function textOn(color)
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	if luminance > 0.55 then
		return THEME.Glass
	end
	return WHITE
end

-- Petite pastille colorée (ex : qualité d'une arme)
local function chip(parent, text, color, props)
	local holder = new("Frame", {
		Size = UDim2.new(0, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
	})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	corner(holder)
	padding(holder, 0, 10, 0, 10)
	listLayout(holder, 0, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	label(holder, {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		Font = FONT_TITLE,
		TextSize = 13,
		TextColor3 = textOn(color),
	})
	holder.Parent = parent
	return holder
end

-- Barre de progression arrondie
local function progressBar(parent, color, props)
	local back = new("Frame", { BackgroundColor3 = THEME.Inset, BackgroundTransparency = 0.1 })
	for key, value in pairs(props) do
		back[key] = value
	end
	corner(back)
	outline(back, WHITE, 1, 0.88)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, Parent = back })
	fill:SetAttribute("MinPx", back.Size.Y.Offset)
	corner(fill)
	gloss(fill)
	local text = label(back, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = FONT_TITLE,
		TextSize = 15,
		TextStrokeTransparency = 0.5,
		ZIndex = 2,
	})
	back.Parent = parent
	return back, fill, text
end

local function setProgress(fill, ratio)
	ratio = math.clamp(ratio, 0, 1)
	fill.Visible = ratio > 0.001
	local minWidth = fill:GetAttribute("MinPx") or 0
	fill.Size = UDim2.new(ratio, math.floor(minWidth * (1 - ratio)), 1, 0) -- jamais plus étroit qu'un rond
end

-- Rond coloré (couleur d'un minerai)
local function swatch(parent, color, size, props)
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(size or 30, size or 30),
		BackgroundColor3 = color,
	})
	for key, value in pairs(props or {}) do
		dot[key] = value
	end
	corner(dot)
	gloss(dot)
	outline(dot, darken(color, 0.5), 2)
	dot.Parent = parent
	return dot
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
for _, oldName in ipairs({ "LootForgeUI", "LootForgeNotifs" }) do
	local oldGui = playerGui:FindFirstChild(oldName)
	if oldGui then
		oldGui:Destroy() -- le script a été relancé : on évite d'avoir l'interface en double
	end
end
local gui = new("ScreenGui", {
	Name = "LootForgeUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Taille de l'interface adaptée à l'écran (PC, tablette, téléphone)
local scales = {}
local function addScale(frame)
	table.insert(scales, new("UIScale", { Parent = frame }))
end

local window -- la fenêtre des menus (créée plus bas)
local smallScreen = false -- téléphone : mise en page compacte

------------------------------------------------------------------------
-- NOTIFICATIONS (en haut au centre)
------------------------------------------------------------------------
-- Les notifications ont leur propre écran, placé dans la barre du haut de Roblox,
-- pour ne jamais cacher le titre d'une fenêtre
local notifGui = new("ScreenGui", {
	Name = "LootForgeNotifs",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
	Parent = playerGui,
})
local notifFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(540, 10),
	BackgroundTransparency = 1,
	Parent = notifGui,
})
addScale(notifFrame)
listLayout(notifFrame, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

local notifCount = 0
local function showNotification(text, color)
	color = color or THEME.Text
	notifCount = notifCount + 1
	local toast = new("Frame", {
		LayoutOrder = notifCount,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Glass,
		BackgroundTransparency = 0.04,
		Parent = notifFrame,
	})
	corner(toast, 16)
	local stroke = outline(toast, color, 2, 0.35)
	padding(toast, 10, 16, 10, 16)
	listLayout(toast, 0)
	local text = label(toast, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextColor3 = color,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = FONT_TITLE,
		TextSize = 19,
	})
	-- Apparition en fondu
	toast.BackgroundTransparency = 1
	text.TextTransparency = 1
	stroke.Transparency = 1
	local fadeIn = TweenInfo.new(0.2)
	TweenService:Create(toast, fadeIn, { BackgroundTransparency = 0.04 }):Play()
	TweenService:Create(text, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, fadeIn, { Transparency = 0.35 }):Play()

	-- Pas plus de 4 notifications à la fois (1 seule quand une fenêtre est ouverte)
	local limit = (window and window.Visible) and 1 or 4
	local items = {}
	for _, child in ipairs(notifFrame:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	if #items > limit then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #items - limit do
			items[i]:Destroy()
		end
	end

	task.delay(4, function()
		if toast.Parent then
			local info = TweenInfo.new(0.4)
			TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(text, info, { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
			task.delay(0.45, function()
				toast:Destroy()
			end)
		end
	end)
end

------------------------------------------------------------------------
-- BUTIN (à droite) : bulles "+1 Rubis", "+12 💰"
------------------------------------------------------------------------
local lootFeed = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(240, 280),
	BackgroundTransparency = 1,
	Parent = gui,
})
addScale(lootFeed)
listLayout(lootFeed, 6, {
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
})

local lootCount = 0
local function showLoot(text, color, dotColor)
	lootCount = lootCount + 1
	local bubble = new("Frame", {
		LayoutOrder = lootCount,
		Size = UDim2.new(0, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = THEME.Glass,
		BackgroundTransparency = 0.2,
		Parent = lootFeed,
	})
	corner(bubble)
	padding(bubble, 0, 14, 0, 8)
	listLayout(bubble, 8, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	local dot = new("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(16, 16), BackgroundColor3 = dotColor or color, Parent = bubble })
	corner(dot)
	outline(dot, darken(dotColor or color, 0.5), 1.5)
	local text = label(bubble, {
		LayoutOrder = 2,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		TextColor3 = color,
		Font = FONT_TITLE,
		TextSize = 19,
	})
	local items = {}
	for _, child in ipairs(lootFeed:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	local maxBubbles = smallScreen and 4 or 7
	if #items > maxBubbles then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #items - maxBubbles do
			items[i]:Destroy()
		end
	end
	task.delay(2.4, function()
		if bubble.Parent then
			local info = TweenInfo.new(0.35)
			TweenService:Create(bubble, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(dot, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(text, info, { TextTransparency = 1 }):Play()
			task.delay(0.4, function()
				bubble:Destroy()
			end)
		end
	end)
end

------------------------------------------------------------------------
-- STATS (à gauche) : pastilles arrondies + carte d'infos
------------------------------------------------------------------------
local statsFrame = new("Frame", {
	Name = "Stats",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, -10),
	Size = UDim2.fromOffset(236, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
})
addScale(statsFrame)
local statsLayout = listLayout(statsFrame, 8)

local function statPill(order, icon, title, color)
	local pill = new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = THEME.Glass,
		BackgroundTransparency = 0.08,
		Parent = statsFrame,
	})
	corner(pill)
	outline(pill, color, 1.5, 0.5)
	local bubble = swatch(pill, color, 40, { Position = UDim2.new(0, 5, 0.5, 0) })
	label(bubble, {
		Size = UDim2.fromScale(1, 1),
		Text = icon,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	label(pill, {
		Position = UDim2.fromOffset(54, 7),
		Size = UDim2.new(1, -66, 0, 12),
		Text = title,
		TextSize = 12,
		TextColor3 = THEME.Sub,
	})
	return label(pill, {
		Position = UDim2.fromOffset(54, 20),
		Size = UDim2.new(1, -66, 0, 24),
		Text = "…",
		Font = FONT_TITLE,
		TextSize = 22,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

local powerLabel = statPill(1, "💪", "PUISSANCE", Color3.fromRGB(255, 140, 40))
local damageLabel = statPill(2, "⚔", "DÉGÂTS", Color3.fromRGB(242, 72, 92))
local coinsLabel = statPill(3, "💰", "PIÈCES", Color3.fromRGB(255, 196, 40))
local oresLabel = statPill(4, "🎒", "MINERAIS", Color3.fromRGB(52, 150, 255))

local weaponCard = glassFrame({
	LayoutOrder = 5,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = statsFrame,
}, 18)
padding(weaponCard, 12, 14, 12, 14)
listLayout(weaponCard, 6)
local weaponLabel = label(weaponCard, {
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 20),
	Font = FONT_TITLE,
	TextSize = 17,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local rebirthLabel = label(weaponCard, {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 16),
	TextSize = 13,
	TextColor3 = Color3.fromRGB(205, 160, 255),
})
local trainingChip = chip(weaponCard, "", THEME.Good, { LayoutOrder = 3, Visible = false, Size = UDim2.new(0, 0, 0, 24) })
local trainingLabel = trainingChip:FindFirstChildOfClass("TextLabel")
local goalLabel = label(weaponCard, {
	LayoutOrder = 4,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	TextWrapped = true,
	TextSize = 13,
	Font = FONT_BODY,
	TextColor3 = Color3.fromRGB(205, 212, 235),
})

------------------------------------------------------------------------
-- FENÊTRE DES MENUS (au centre)
------------------------------------------------------------------------
local WINDOW_SIZE = Vector2.new(660, 450)
local WINDOW_SIZE_PHONE = Vector2.new(720, 400) -- plus large et moins haute sur téléphone
window = glassFrame({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(WINDOW_SIZE.X, WINDOW_SIZE.Y),
	BackgroundTransparency = 0.03,
	Visible = false,
	Parent = gui,
}, 26)
local windowScale = new("UIScale", { Parent = window })
local header = new("Frame", {
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(1, -20, 0, 56),
	BackgroundColor3 = ACCENT.Forge,
	Parent = window,
})
corner(header, 18)
gloss(header)
local headerStroke = outline(header, darken(ACCENT.Forge, 0.45), 2)
local titleLabel = label(header, {
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.new(1, -80, 1, 0),
	Font = FONT_TITLE,
	TextSize = 27,
	TextStrokeTransparency = 0.55,
})
local closeButton = makeButton(header, "✕", THEME.Glass, {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(38, 38),
	TextSize = 20,
	BackgroundTransparency = 0.35,
})
local content = new("Frame", {
	Position = UDim2.fromOffset(16, 80),
	Size = UDim2.new(1, -32, 1, -96),
	BackgroundTransparency = 1,
	Parent = window,
})

local function makePanelFrame()
	return new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = content })
end

local function makeScroll(parent, props, useGrid)
	local scroll = new("ScrollingFrame", {
		BackgroundColor3 = THEME.Inset,
		BackgroundTransparency = 0.25,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = WHITE,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	for key, value in pairs(props) do
		scroll[key] = value
	end
	scroll.Parent = parent
	corner(scroll, 16)
	if useGrid then
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(196, 78),
			CellPadding = UDim2.fromOffset(8, 8),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
	else
		listLayout(scroll, 8)
	end
	padding(scroll, 8, 14, 8, 8)
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
		Size = UDim2.new(1, 0, 0, height or 56),
		BackgroundColor3 = THEME.Card,
		Parent = parent,
	})
	corner(row, 16)
	outline(row, WHITE, 1, 0.92)
	return row
end

local function emptyMessage(list, text)
	local row = makeRow(list, 0, 74)
	label(row, {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -32, 1, 0),
		TextWrapped = true,
		Text = text,
		TextColor3 = THEME.Sub,
		Font = FONT_BODY,
		TextSize = 15,
	})
end

-- En-tête de panneau : texte à gauche + éléments à droite
local function panelHeader(parent, height)
	local bar = new("Frame", { Size = UDim2.new(1, 0, 0, height or 36), BackgroundTransparency = 1, Parent = parent })
	local text = label(bar, {
		Size = UDim2.new(1, -200, 1, 0),
		Font = FONT_TITLE,
		TextSize = 20,
	})
	return bar, text
end

local refreshPanel -- défini plus bas
local closeWindow -- défini plus bas

------------------------------------------------------------------------
-- MENU : FORGE
------------------------------------------------------------------------
local forgePanel = makePanelFrame()
local forgeList = makeScroll(forgePanel, { Size = UDim2.new(0.6, -6, 1, 0) })
local forgeSide = new("Frame", {
	Position = UDim2.new(0.6, 6, 0, 0),
	Size = UDim2.new(0.4, -6, 1, 0),
	BackgroundColor3 = THEME.Card,
	Parent = forgePanel,
})
corner(forgeSide, 18)
outline(forgeSide, WHITE, 1, 0.9)
padding(forgeSide, 14)
local forgeInfo = label(forgeSide, {
	Size = UDim2.new(1, 0, 1, -112),
	TextWrapped = true,
	TextScaled = true,
	RichText = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = FONT_BODY,
	TextSize = 15,
})
new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 11, Parent = forgeInfo })
local forgeClear = makeButton(forgeSide, "Vider", THEME.Muted, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, -58),
	Size = UDim2.new(1, 0, 0, 40),
})
local forgeButton = makeButton(forgeSide, "⚒ FORGER", ACCENT.Forge, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 50),
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
		showNotification("Maximum " .. Config.MaxOreTypes .. " types de minerais par arme !", THEME.Bad)
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
			local row = makeRow(forgeList, #Config.Ores - index, 56)
			swatch(row, ore.Color)
			label(row, {
				Position = UDim2.fromOffset(50, 8),
				Size = UDim2.new(1, -224, 0, 22),
				Text = ore.Name,
				TextColor3 = Config.Rarities[ore.Rarity],
				TextSize = 17,
				Font = FONT_TITLE,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			label(row, {
				Position = UDim2.fromOffset(50, 30),
				Size = UDim2.new(1, -224, 0, 16),
				Text = "×" .. Config.Format(ore.Mult) .. "  •  tu as " .. have,
				TextColor3 = THEME.Sub,
				TextSize = 13,
				Font = FONT_BODY,
			})
			local minus = makeButton(row, "−", THEME.Bad, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -138, 0.5, 0),
				Size = UDim2.fromOffset(32, 32),
				TextSize = 20,
			})
			local countBox = new("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -98, 0.5, 0),
				Size = UDim2.fromOffset(36, 30),
				BackgroundColor3 = THEME.Inset,
				Parent = row,
			})
			corner(countBox, 10)
			label(countBox, {
				Size = UDim2.fromScale(1, 1),
				Text = tostring(selected),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = selected > 0 and THEME.Gold or THEME.Sub,
				Font = FONT_TITLE,
				TextSize = 18,
			})
			local plus = makeButton(row, "+", THEME.Good, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -58, 0.5, 0),
				Size = UDim2.fromOffset(32, 32),
				TextSize = 20,
			})
			local maxButton = makeButton(row, "Max", THEME.Blue, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(44, 32),
				TextSize = 14,
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
		table.insert(lines, "<b>Arme :</b> " .. colorTag(ACCENT.Forge, kind.Name .. " " .. Config.OreById[preview.MainOre].Of))
		table.insert(lines, "<b>Dégâts :</b> " .. colorTag(THEME.Gold, "×" .. Config.Format(preview.Mult)) .. " (+ qualité)")
		if kind.AoE then
			table.insert(lines, colorTag(THEME.Sub, "Lent, mais frappe TOUS les monstres autour."))
		else
			table.insert(lines, colorTag(THEME.Sub, "Rapide, frappe un monstre à la fois."))
		end
	else
		table.insert(lines, colorTag(Color3.fromRGB(255, 125, 135), preview.Error or ""))
	end
	table.insert(lines, "")
	table.insert(lines, colorTag(THEME.Sub, Config.MinOres .. "-" .. (Config.GreatswordOres - 1) .. " minerais = Katana"))
	table.insert(lines, colorTag(THEME.Sub, Config.GreatswordOres .. "+ minerais = Espadon"))
	table.insert(lines, colorTag(THEME.Sub, "Qualité au hasard : jusqu'à ×" .. Config.Qualities[#Config.Qualities].Mult .. " !"))
	forgeInfo.Text = table.concat(lines, "\n")
	setEnabled(forgeButton, preview.Ok, ACCENT.Forge)
end

forgeButton.Activated:Connect(function()
	local preview = Config.PreviewForge(forgeSelection)
	if not preview.Ok then
		showNotification(preview.Error or "Sélection invalide", THEME.Bad)
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
local oresBar, oresHeader = panelHeader(oresPanel, 40)
oresHeader.Size = UDim2.new(0, 120, 1, 0)
local _, capacityFill, capacityText = progressBar(oresBar, ACCENT.Ores, {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 128, 0.5, 0),
	Size = UDim2.new(1, -290, 0, 24),
})
local sellAllButton = makeButton(oresBar, "Tout vendre", THEME.Bad, {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -4, 0.5, 0),
	Size = UDim2.fromOffset(146, 38),
})
confirmButton(sellAllButton, "Tout vendre", function()
	Action:FireServer("SellAllOres")
end)
local oresList = makeScroll(oresPanel, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50) })

local function refreshOres()
	oresHeader.Text = "🎒 Ton sac"
	setProgress(capacityFill, state.OreTotal / math.max(1, state.Capacity))
	capacityText.Text = state.OreTotal .. " / " .. state.Capacity
	capacityFill.BackgroundColor3 = state.OreTotal >= state.Capacity and THEME.Bad or ACCENT.Ores
	clearList(oresList)
	local any = false
	for index = #Config.Ores, 1, -1 do
		local ore = Config.Ores[index]
		local have = owned(ore.Id)
		if have > 0 then
			any = true
			local row = makeRow(oresList, #Config.Ores - index, 58)
			swatch(row, ore.Color)
			label(row, {
				Position = UDim2.fromOffset(50, 8),
				Size = UDim2.new(1, -310, 0, 22),
				Text = ore.Name .. "  x" .. have,
				TextColor3 = Config.Rarities[ore.Rarity],
				TextSize = 18,
				Font = FONT_TITLE,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			label(row, {
				Position = UDim2.fromOffset(50, 31),
				Size = UDim2.new(1, -310, 0, 16),
				Text = ore.Rarity .. "  •  ×" .. Config.Format(ore.Mult) .. "  •  " .. Config.Format(ore.Sell) .. " 💰/u",
				TextColor3 = THEME.Sub,
				TextSize = 13,
				Font = FONT_BODY,
			})
			local sellOne = makeButton(row, "Vendre 1", THEME.Blue, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -132, 0.5, 0),
				Size = UDim2.fromOffset(104, 36),
				TextSize = 16,
			})
			local sellAll = makeButton(row, "Vendre tout", THEME.Bad, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(114, 36),
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
local _, weaponsHeader = panelHeader(weaponsPanel, 40)
local weaponsList = makeScroll(weaponsPanel, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50) })

local function weaponRow(order, weapon)
	local data = state.Data
	local isEquipped = (weapon and weapon.Id or 0) == data.Equipped
	local row = makeRow(weaponsList, order, 62)
	if isEquipped then
		local stroke = row:FindFirstChildOfClass("UIStroke")
		stroke.Color = THEME.Gold
		stroke.Transparency = 0.2
		stroke.Thickness = 2
	end
	local ore = weapon and Config.OreById[weapon.MainOre]
	swatch(row, ore and ore.Color or Color3.fromRGB(160, 115, 70), 34)
	local qualityColor = weapon and Config.Rarities[weapon.Quality] or THEME.Text
	label(row, {
		Position = UDim2.fromOffset(54, 8),
		Size = UDim2.new(1, -340, 0, 22),
		Text = Config.GetWeaponName(weapon),
		TextColor3 = qualityColor,
		TextSize = 18,
		Font = FONT_TITLE,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local details = new("Frame", {
		Position = UDim2.fromOffset(54, 33),
		Size = UDim2.new(1, -340, 0, 20),
		BackgroundTransparency = 1,
		Parent = row,
	})
	listLayout(details, 6, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	if weapon then
		chip(details, weapon.Quality, qualityColor, { LayoutOrder = 1, Size = UDim2.new(0, 0, 0, 20) })
		label(details, {
			LayoutOrder = 2,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = weapon.OreCount .. " minerais",
			TextColor3 = THEME.Sub,
			TextSize = 13,
			Font = FONT_BODY,
		})
	else
		label(details, {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "Arme de départ",
			TextColor3 = THEME.Sub,
			TextSize = 13,
			Font = FONT_BODY,
		})
	end
	label(row, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -240, 0.5, 0),
		Size = UDim2.fromOffset(84, 30),
		Text = "×" .. Config.Format(weapon and weapon.Mult or 1),
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = FONT_TITLE,
		TextSize = 21,
	})
	local equipButton = makeButton(row, isEquipped and "✔ Équipée" or "Équiper", THEME.Good, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -134, 0.5, 0),
		Size = UDim2.fromOffset(100, 36),
		TextSize = 15,
	})
	if isEquipped then
		setEnabled(equipButton, false, THEME.Good)
	else
		equipButton.Activated:Connect(function()
			Action:FireServer("Equip", weapon and weapon.Id or 0)
		end)
	end
	if weapon then
		local priceText = "Vendre " .. Config.Format(Config.GetWeaponSellPrice(weapon))
		local sellButton = makeButton(row, priceText, THEME.Bad, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(118, 36),
			TextSize = 15,
		})
		confirmButton(sellButton, priceText, function()
			Action:FireServer("SellWeapon", weapon.Id)
		end)
	end
end

local function refreshWeapons()
	local data = state.Data
	weaponsHeader.Text = "⚔ Tes armes : " .. #data.Weapons .. " / " .. Config.MaxWeapons
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
local _, upgradesHeader = panelHeader(upgradesPanel, 40)
upgradesHeader.TextColor3 = THEME.Gold
local upgradesList = makeScroll(upgradesPanel, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50) })

local UPGRADE_ICONS = { Capacity = "🎒", Luck = "🍀" }

local function upgradeEffect(upgradeId, level)
	if upgradeId == "Capacity" then
		return Config.GetCapacity(level) .. " places"
	end
	return "+" .. (level * 15) .. "% de chance"
end

local function refreshUpgrades()
	local data = state.Data
	upgradesHeader.Text = "💰 " .. Config.Format(data.Coins) .. " pièces"
	clearList(upgradesList)
	for order, upgradeId in ipairs(Config.UpgradeOrder) do
		local upgrade = Config.Upgrades[upgradeId]
		local level = data.Upgrades[upgradeId] or 0
		local isMax = level >= upgrade.Max
		local row = makeRow(upgradesList, order, 104)
		local icon = swatch(row, upgradeId == "Capacity" and ACCENT.Ores or ACCENT.Upgrades, 52, { Position = UDim2.new(0, 12, 0.5, 0) })
		label(icon, { Size = UDim2.fromScale(1, 1), Text = UPGRADE_ICONS[upgradeId] or "⬆", TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center })
		label(row, {
			Position = UDim2.fromOffset(78, 10),
			Size = UDim2.new(1, -260, 0, 24),
			Text = upgrade.Name,
			Font = FONT_TITLE,
			TextSize = 20,
		})
		label(row, {
			Position = UDim2.fromOffset(78, 35),
			Size = UDim2.new(1, -260, 0, 16),
			Text = upgrade.Description,
			TextColor3 = THEME.Sub,
			Font = FONT_BODY,
			TextSize = 13,
		})
		local _, levelFill, levelText = progressBar(row, ACCENT.Upgrades, {
			Position = UDim2.fromOffset(78, 58),
			Size = UDim2.new(1, -260, 0, 20),
		})
		setProgress(levelFill, level / upgrade.Max)
		levelText.TextSize = 12
		levelText.Text = "Niveau " .. level .. " / " .. upgrade.Max
		local effect = upgradeEffect(upgradeId, level)
		if not isMax then
			effect = effect .. "  →  " .. upgradeEffect(upgradeId, level + 1)
		end
		label(row, {
			Position = UDim2.fromOffset(78, 82),
			Size = UDim2.new(1, -260, 0, 16),
			Text = effect,
			TextColor3 = Color3.fromRGB(120, 230, 160),
			Font = FONT_BODY,
			TextSize = 13,
		})
		local cost = Config.GetUpgradeCost(upgradeId, level)
		local canBuy = not isMax and data.Coins >= cost
		local buyButton = makeButton(row, isMax and "MAX" or ("💰 " .. Config.Format(cost)), THEME.Good, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(150, 50),
			TextSize = 20,
		})
		setEnabled(buyButton, canBuy, THEME.Good)
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

-- Couleur de tuile assez foncée pour que le texte blanc reste lisible
local function tileColor(color)
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	if luminance > 0.42 then
		return darken(color, math.clamp((luminance - 0.42) + 0.12, 0, 0.45))
	end
	return color
end

local function stageTile(order, color, topText, titleText, bottomText)
	-- La tuile est dans une "case" : l'animation la fait grossir depuis son centre
	local slot = new("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Parent = teleportGrid })
	local tile = makeButton(slot, "", color, { Size = UDim2.fromScale(1, 1) })
	tile:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 18)
	local textStyle = { TextColor3 = WHITE, TextStrokeColor3 = darken(color, 0.6), TextStrokeTransparency = 0.6 }
	local function styled(props)
		for key, value in pairs(textStyle) do
			props[key] = value
		end
		return label(tile, props)
	end
	styled({ Position = UDim2.fromOffset(14, 9), Size = UDim2.new(1, -28, 0, 14), Text = topText, TextSize = 12, TextTransparency = 0.15 })
	styled({
		Position = UDim2.fromOffset(14, 24),
		Size = UDim2.new(1, -28, 0, 24),
		Text = titleText,
		Font = FONT_TITLE,
		TextSize = 17,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	styled({ Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 16), Text = bottomText, TextSize = 13, Font = FONT_BODY, TextTransparency = 0.12 })
	return tile
end

local function refreshTeleport()
	local data = state.Data
	clearList(teleportGrid)
	local hubTile = stageTile(0, tileColor(Color3.fromRGB(240, 170, 40)), "RETOUR", "🏠 Hub", "Entraînement, forge…")
	hubTile.Activated:Connect(function()
		Action:FireServer("Teleport", 0)
		closeWindow()
	end)
	for stage, info in ipairs(Config.Stages) do
		local unlocked = stage <= data.MaxStage
		local tile
		if unlocked then
			tile = stageTile(stage, tileColor(info.Floor:Lerp(ACCENT.Teleport, 0.4)), "ÉTAPE " .. stage, info.Name,
				"PV " .. Config.Format(Config.GetEnemyHP(stage, false)) .. "  •  Boss " .. Config.Format(Config.GetEnemyHP(stage, true)))
			if stage == data.MaxStage then
				-- La dernière étape débloquée est entourée d'or
				local stroke = tile:FindFirstChildOfClass("UIStroke")
				stroke.Color = THEME.Gold
				stroke.Thickness = 3
			end
		else
			tile = stageTile(stage, THEME.Card, "ÉTAPE " .. stage, "🔒 Verrouillée", "Bats le boss de l'étape " .. (stage - 1))
			tile.BackgroundTransparency = 0.25
			tile:FindFirstChildOfClass("UIStroke").Color = THEME.Muted
			for _, child in ipairs(tile:GetChildren()) do
				if child:IsA("TextLabel") then
					child.TextTransparency = 0.4
				end
			end
		end
		tile.Activated:Connect(function()
			Action:FireServer("Teleport", stage)
			if unlocked then
				closeWindow()
			end
		end)
	end
end

------------------------------------------------------------------------
-- MENU : REBIRTH
------------------------------------------------------------------------
local rebirthPanel = makePanelFrame()
local multRow = new("Frame", { Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, Parent = rebirthPanel })
listLayout(multRow, 18, {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
})
local function multBubble(order, color, caption)
	local bubble = swatch(multRow, color, 84, { LayoutOrder = order })
	local value = label(bubble, {
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 12),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = FONT_TITLE,
		TextSize = 32,
		TextStrokeColor3 = darken(color, 0.6),
		TextStrokeTransparency = 0.4,
	})
	label(bubble, {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 54),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = caption,
		TextSize = 10,
		TextColor3 = lighten(color, 0.8),
	})
	return value
end
local currentMultLabel = multBubble(1, THEME.Muted, "ACTUEL")
label(multRow, {
	LayoutOrder = 2,
	Size = UDim2.fromOffset(40, 40),
	Text = "➜",
	TextSize = 34,
	Font = FONT_TITLE,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = ACCENT.Rebirth,
})
local nextMultLabel = multBubble(3, ACCENT.Rebirth, "APRÈS")
local _, rebirthFill, rebirthBarText = progressBar(rebirthPanel, ACCENT.Rebirth, {
	Position = UDim2.fromOffset(0, 108),
	Size = UDim2.new(1, 0, 0, 34),
})
rebirthBarText.TextSize = 17
local keepRow = new("Frame", {
	Position = UDim2.fromOffset(0, 154),
	Size = UDim2.new(1, 0, 0, 78),
	BackgroundTransparency = 1,
	Parent = rebirthPanel,
})
local function rebirthCard(xScale, xOffset, color, title, body)
	local card = new("Frame", {
		Position = UDim2.new(xScale, xOffset, 0, 0),
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundColor3 = color:Lerp(THEME.Card, 0.82),
		Parent = keepRow,
	})
	corner(card, 16)
	outline(card, color, 1.5, 0.55)
	padding(card, 10, 14, 10, 14)
	label(card, { Size = UDim2.new(1, 0, 0, 20), Text = title, Font = FONT_TITLE, TextSize = 17, TextColor3 = color })
	label(card, {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 1, -24),
		Text = body,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = FONT_BODY,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(215, 220, 240),
	})
end
rebirthCard(0, 0, THEME.Bad, "Tu perds", "Ta puissance et tes étapes débloquées.")
rebirthCard(0.5, 6, THEME.Good, "Tu gardes", "Armes, minerais, pièces et améliorations.")
local rebirthCost = label(rebirthPanel, {
	Position = UDim2.fromOffset(0, 240),
	Size = UDim2.new(1, 0, 0, 38),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = THEME.Sub,
	TextSize = 14,
	Font = FONT_BODY,
})
local rebirthButton = makeButton(rebirthPanel, "♻ REBIRTH", ACCENT.Rebirth, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -4),
	Size = UDim2.fromOffset(300, 58),
	TextSize = 28,
})
confirmButton(rebirthButton, "♻ REBIRTH", function()
	Action:FireServer("Rebirth")
end)

local function refreshRebirth()
	local data = state.Data
	local cost = Config.GetRebirthCost(data.Rebirths)
	currentMultLabel.Text = "×" .. Config.GetRebirthMult(data.Rebirths)
	nextMultLabel.Text = "×" .. Config.GetRebirthMult(data.Rebirths + 1)
	local ratio = math.clamp(data.Power / cost, 0, 1)
	setProgress(rebirthFill, ratio)
	rebirthBarText.Text = Config.Format(data.Power) .. " / " .. Config.Format(cost) .. "  (" .. math.floor(ratio * 100) .. "%)"
	rebirthCost.Text = "Rebirth n°" .. (data.Rebirths + 1) .. " : il faut " .. Config.Format(cost)
		.. " de puissance.\nLe multiplicateur booste l'entraînement ET les dégâts."
	setEnabled(rebirthButton, ratio >= 1, ACCENT.Rebirth)
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
		Title = "🛒 Boutique",
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
local baseScale = 1     -- taille de la fenêtre selon l'écran
local windowToken = 0   -- évite qu'une vieille animation de fermeture cache une fenêtre rouverte
local dock -- barre de menus (créée plus bas)

-- Sur téléphone, quand une fenêtre est ouverte, on cache ce qui est derrière
-- (stats, barre de menus, barre d'objets de Roblox) pour qu'elle prenne toute la place
local function setPhoneWindowMode(windowOpen)
	local hide = windowOpen and smallScreen
	dock.Visible = not hide
	statsFrame.Visible = not hide
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not hide)
	end)
end

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

closeWindow = function()
	if not window.Visible then
		return
	end
	windowToken = windowToken + 1
	local myToken = windowToken
	TweenService:Create(windowScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = baseScale * 0.9,
	}):Play()
	task.delay(0.1, function()
		if myToken == windowToken then
			window.Visible = false
			setPhoneWindowMode(false)
		end
	end)
end

local function openPanel(name, keepOpen)
	if currentPanel == name and window.Visible and not keepOpen then
		closeWindow()
		return
	end
	windowToken = windowToken + 1
	currentPanel = name
	for id, def in pairs(panelDefs) do
		def.Frame.Visible = (id == name)
	end
	local accent = ACCENT[name] or ACCENT.Forge
	header.BackgroundColor3 = accent
	headerStroke.Color = darken(accent, 0.45)
	titleLabel.Text = panelDefs[name].Title
	titleLabel.TextStrokeColor3 = darken(accent, 0.6)
	setPhoneWindowMode(true)
	if not window.Visible then
		windowScale.Scale = baseScale * 0.88
		window.Visible = true
	end
	-- Toujours revenir à la bonne taille (même si on rouvre pendant l'animation de fermeture)
	TweenService:Create(windowScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = baseScale,
	}):Play()
	-- Une seule notification visible quand une fenêtre est ouverte
	local toasts = {}
	for _, child in ipairs(notifFrame:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - 1 do
		toasts[i]:Destroy()
	end
	refreshPanel(true)
end

closeButton.Activated:Connect(closeWindow)

------------------------------------------------------------------------
-- BARRE DE MENUS (en bas) : grosses tuiles arrondies
------------------------------------------------------------------------
local MENU = {
	{ Id = "Forge", Icon = "⚒", Text = "Forge" },
	{ Id = "Ores", Icon = "🎒", Text = "Minerais" },
	{ Id = "Weapons", Icon = "⚔", Text = "Armes" },
	{ Id = "Upgrades", Icon = "🛒", Text = "Boutique" },
	{ Id = "Teleport", Icon = "🌀", Text = "Donjon" },
	{ Id = "Rebirth", Icon = "♻", Text = "Rebirth" },
}
local TILE = 82
local DOCK_HEIGHT = TILE + 20
local DOCK_BOTTOM = 80 -- laisse la place à la barre d'objets de Roblox
dock = glassFrame({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -DOCK_BOTTOM),
	Size = UDim2.fromOffset(#MENU * TILE + (#MENU - 1) * 10 + 20, DOCK_HEIGHT),
	BackgroundTransparency = 0.12,
	Parent = gui,
}, 28)
addScale(dock)
padding(dock, 10)
listLayout(dock, 10, {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
})
local badges = {}
for order, item in ipairs(MENU) do
	local color = ACCENT[item.Id]
	local slot = new("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(TILE, TILE), BackgroundTransparency = 1, Parent = dock })
	local tile = makeButton(slot, "", color, { Size = UDim2.fromScale(1, 1) })
	tile:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 22)
	label(tile, {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 38),
		Text = item.Icon,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	label(tile, {
		Position = UDim2.new(0, 0, 1, -30),
		Size = UDim2.new(1, 0, 0, 20),
		Text = item.Text,
		Font = FONT_TITLE,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = darken(color, 0.6),
		TextStrokeTransparency = 0.4,
	})
	-- Pastille rouge "!" quand une action t'attend dans ce menu
	local badge = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = THEME.Bad,
		Visible = false,
		ZIndex = 3,
		Parent = tile,
	})
	corner(badge)
	outline(badge, WHITE, 2)
	label(badge, { Size = UDim2.fromScale(1, 1), Text = "!", Font = FONT_TITLE, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	badges[item.Id] = badge
	tile.Activated:Connect(function()
		openPanel(item.Id)
	end)
end

-- Adapte tout à la taille de l'écran (PC, tablette, téléphone)
local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	smallScreen = viewport.Y < 500
	local scale
	if smallScreen then
		scale = math.clamp(viewport.Y / 520, 0.6, 1)
	else
		scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.25)
	end
	for _, uiScale in ipairs(scales) do
		uiScale.Scale = scale
	end
	local inset = 58
	local ok, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and topLeft then
		inset = topLeft.Y
	end
	local guiHeight = viewport.Y - inset

	-- Téléphone : infos plus compactes en haut à gauche (loin du joystick),
	-- butin au-dessus du bouton de saut
	goalLabel.Visible = not smallScreen
	rebirthLabel.Visible = not smallScreen
	statsLayout.Padding = UDim.new(0, smallScreen and 4 or 8)
	statsFrame.AnchorPoint = smallScreen and Vector2.new(0, 0) or Vector2.new(0, 0.5)
	statsFrame.Position = smallScreen and UDim2.new(0, 10, 0, 4) or UDim2.new(0, 14, 0.5, -10)
	lootFeed.Position = smallScreen and UDim2.new(1, -10, 0.3, 0) or UDim2.new(1, -14, 0.5, 0)
	local dockBottom = smallScreen and 70 or DOCK_BOTTOM
	dock.Position = UDim2.new(0.5, 0, 1, -dockBottom)

	local size
	if smallScreen then
		-- Fenêtre large et peu haute, qui prend presque tout l'écran
		size = WINDOW_SIZE_PHONE
		baseScale = math.min(1, (guiHeight - 10) / size.Y, (viewport.X - 220) / size.X)
		window.Position = UDim2.new(0.5, 0, 0, 4 + (guiHeight - 4) / 2)
	else
		-- La fenêtre se place dans l'espace libre au-dessus de la barre de menus
		size = WINDOW_SIZE
		local space = guiHeight - dockBottom - DOCK_HEIGHT * scale - 16
		baseScale = math.min(scale, (space - 8) / size.Y)
		window.Position = UDim2.new(0.5, 0, 0, 8 + space / 2)
	end
	window.Size = UDim2.fromOffset(size.X, size.Y)
	rebirthCost.Visible = not smallScreen
	teleportGrid:FindFirstChildOfClass("UIGridLayout").CellSize = UDim2.fromOffset(math.floor((size.X - 70) / 3), 78)
	if window.Visible then
		windowScale.Scale = baseScale
	end
	setPhoneWindowMode(window.Visible)
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
		return "Sac plein : forge, vends tes minerais ou achète de la capacité (🛒 Boutique)."
	end
	if data.MaxStage < #Config.Stages then
		return "Bats le boss 👑 de l'étape " .. data.MaxStage .. " pour débloquer la suivante. Trop dur ? Entraîne-toi sur les tapis du hub !"
	end
	return "Entraîne-toi et prépare ton prochain Rebirth !"
end

local function updateStats()
	local data = state.Data
	powerLabel.Text = Config.Format(data.Power)
	damageLabel.Text = Config.Format(state.Damage)
	coinsLabel.Text = Config.Format(data.Coins)
	oresLabel.Text = state.OreTotal .. " / " .. state.Capacity
	oresLabel.TextColor3 = state.OreTotal >= state.Capacity and Color3.fromRGB(255, 120, 130) or THEME.Text
	rebirthLabel.Text = "♻ Rebirth " .. data.Rebirths .. "  •  bonus ×" .. Config.GetRebirthMult(data.Rebirths)
	local weapon = getEquippedWeapon(data)
	weaponLabel.Text = "🗡 " .. Config.GetWeaponName(weapon)
	weaponLabel.TextColor3 = weapon and Config.Rarities[weapon.Quality] or THEME.Text
	trainingChip.Visible = state.Training > 0
	trainingLabel.Text = "🏋 Entraînement +" .. Config.Format(state.Training) .. "/s"
	goalLabel.Text = "🎯 " .. getGoal()
	badges.Rebirth.Visible = data.Power >= Config.GetRebirthCost(data.Rebirths)
	badges.Forge.Visible = #data.Weapons == 0 and state.OreTotal >= Config.MinOres
	badges.Ores.Visible = state.OreTotal >= state.Capacity
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
		TextColor3 = killed and THEME.Gold or WHITE,
		TextStrokeTransparency = 0,
		Font = FONT_TITLE,
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
			showLoot("+1 " .. ore.Name, Config.Rarities[ore.Rarity], ore.Color)
			flyLoot(info.Position, ore.Color)
		end
	end
	if info.Coins and info.Coins > 0 then
		showLoot("+" .. Config.Format(info.Coins) .. " 💰", THEME.Gold)
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

-- Si le serveur ne répond jamais, on le dit au lieu de rester sans données
task.delay(15, function()
	if state then
		return
	end
	local banner = showFatal("Le serveur ne répond pas. Ouvre la fenêtre Output (View → Output) : "
		.. "il y a sûrement une erreur rouge dans GameServer.")
	while not state do
		task.wait(1)
	end
	if banner then
		banner:Destroy()
	end
end)
