--[[
	GameServer  (Script)
	À placer dans : ServerScriptService

	Ce script fait TOUT côté serveur :
	  - construit la carte (hub, tapis d'entraînement, forge, marchand, arènes)
	  - fait apparaître les monstres et les boss + leur IA
	  - gère les armes (Tool), les dégâts, le butin (+1 minerai par kill !)
	  - la forge, la vente, les améliorations, le rebirth, la téléportation
	  - la sauvegarde des joueurs (DataStore)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local rng = Random.new()

local function random01()
	return rng:NextNumber()
end

------------------------------------------------------------------------
-- 1. REMOTES (communication serveur <-> client)
------------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if remotes then
	remotes:Destroy()
end
remotes = Instance.new("Folder")
remotes.Name = "Remotes"

local function makeRemote(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local DataUpdate = makeRemote("DataUpdate") -- serveur -> client : données du joueur
local Notify = makeRemote("Notify")         -- serveur -> client : message à l'écran
local LootFx = makeRemote("LootFx")         -- serveur -> client : butin gagné
local HitFx = makeRemote("HitFx")           -- serveur -> client : chiffre de dégâts
local OpenPanel = makeRemote("OpenPanel")   -- serveur -> client : ouvrir un menu
local Action = makeRemote("Action")         -- client -> serveur : forger, vendre, etc.
remotes.Parent = ReplicatedStorage

local COLOR_WHITE = Color3.fromRGB(255, 255, 255)
local COLOR_GOOD = Color3.fromRGB(90, 230, 120)
local COLOR_BAD = Color3.fromRGB(255, 90, 90)
local COLOR_GOLD = Color3.fromRGB(255, 200, 60)

local function notify(player, text, color)
	Notify:FireClient(player, text, color or COLOR_WHITE)
end

------------------------------------------------------------------------
-- 2. CONSTRUCTION DE LA CARTE
------------------------------------------------------------------------
local BASE_Y = 50          -- tout est construit en hauteur (pas de conflit avec la Baseplate)
local HUB_SIZE = 180
local ARENA_SIZE = 110
local HUB_SPAWN = Vector3.new(0, BASE_Y + 1, 0)

local oldMap = workspace:FindFirstChild("LootForgeMap")
if oldMap then
	oldMap:Destroy()
end
local mapFolder = Instance.new("Folder")
mapFolder.Name = "LootForgeMap"
mapFolder.Parent = workspace

local enemiesFolder = Instance.new("Folder")
enemiesFolder.Name = "Enemies"
enemiesFolder.Parent = mapFolder

local function makePart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		if key ~= "Parent" then
			part[key] = value
		end
	end
	part.Parent = props.Parent or mapFolder
	return part
end

local function makeSign(adornee, text, color, width, height, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = adornee
	return gui, label
end

local function makePrompt(parent, actionText, objectText, panelName)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	if panelName then
		prompt.Triggered:Connect(function(player)
			OpenPanel:FireClient(player, panelName)
		end)
	end
	return prompt
end

-- Murs invisibles (un peu transparents) autour d'une zone carrée
local function makeWalls(center, size, color)
	local height = 10
	local thickness = 2
	local half = size / 2
	local walls = {
		{ Vector3.new(0, 0, half), Vector3.new(size, height, thickness) },
		{ Vector3.new(0, 0, -half), Vector3.new(size, height, thickness) },
		{ Vector3.new(half, 0, 0), Vector3.new(thickness, height, size) },
		{ Vector3.new(-half, 0, 0), Vector3.new(thickness, height, size) },
	}
	for _, wall in ipairs(walls) do
		makePart({
			Name = "Wall",
			Size = wall[2],
			Position = center + wall[1] + Vector3.new(0, height / 2, 0),
			Color = color,
			Material = Enum.Material.ForceField,
			Transparency = 0.4,
		})
	end
end

-- 2a. LE HUB ----------------------------------------------------------
makePart({
	Name = "HubFloor",
	Size = Vector3.new(HUB_SIZE, 4, HUB_SIZE),
	Position = Vector3.new(0, BASE_Y - 2, 0),
	Color = Color3.fromRGB(95, 140, 80),
	Material = Enum.Material.Grass,
})
makePart({
	Name = "HubPlaza",
	Size = Vector3.new(60, 0.2, 60),
	Position = Vector3.new(0, BASE_Y + 0.1, 0),
	Color = Color3.fromRGB(160, 160, 165),
	Material = Enum.Material.Cobblestone,
})
makeWalls(Vector3.new(0, BASE_Y, 0), HUB_SIZE, Color3.fromRGB(120, 200, 255))

local hubSpawn = Instance.new("SpawnLocation")
hubSpawn.Name = "HubSpawn"
hubSpawn.Anchored = true
hubSpawn.Size = Vector3.new(10, 1, 10)
hubSpawn.Position = Vector3.new(0, BASE_Y + 0.5, 0)
hubSpawn.Color = Color3.fromRGB(255, 200, 60)
hubSpawn.Material = Enum.Material.Neon
hubSpawn.Neutral = true
hubSpawn.Duration = 0
hubSpawn.TopSurface = Enum.SurfaceType.Smooth
hubSpawn.Parent = mapFolder

-- On désactive les autres points d'apparition (ex : celui du modèle "Baseplate")
for _, object in ipairs(workspace:GetDescendants()) do
	if object:IsA("SpawnLocation") and object ~= hubSpawn then
		object.Enabled = false
	end
end

-- Grand panneau titre
local titlePost = makePart({
	Name = "TitlePost",
	Size = Vector3.new(1, 1, 1),
	Position = Vector3.new(0, BASE_Y + 22, -60),
	Transparency = 1,
	CanCollide = false,
})
makeSign(titlePost, Config.GameTitle, COLOR_GOLD, 60, 12, 0)

-- 2b. TAPIS D'ENTRAÎNEMENT -------------------------------------------
local padParts = {}
for index, pad in ipairs(Config.TrainingPads) do
	local z = -60 + (index - 1) * 20
	local part = makePart({
		Name = "TrainingPad" .. index,
		Size = Vector3.new(14, 1, 14),
		Position = Vector3.new(-65, BASE_Y + 0.5, z),
		Color = pad.Color,
		Material = Enum.Material.Neon,
	})
	local requirement = "Requis : " .. Config.Format(pad.ReqPower) .. " puissance"
	if pad.ReqRebirths > 0 then
		requirement = requirement .. " + " .. pad.ReqRebirths .. " rebirth(s)"
	end
	makeSign(part, pad.Name .. "\n+" .. Config.Format(pad.Gain) .. " puissance/s\n" .. requirement, pad.Color, 14, 5, 5)
	padParts[index] = part
end

local function getPadAt(position)
	for index, part in ipairs(padParts) do
		local offset = position - part.Position
		if math.abs(offset.X) <= 7.5 and math.abs(offset.Z) <= 7.5 and offset.Y > -1 and offset.Y < 8 then
			return index
		end
	end
	return nil
end

-- 2c. LA FORGE (enclume + four) -------------------------------------
local anvilBase = makePart({
	Name = "AnvilBase",
	Size = Vector3.new(3, 3, 3),
	Position = Vector3.new(45, BASE_Y + 1.5, -45),
	Color = Color3.fromRGB(60, 60, 65),
	Material = Enum.Material.Metal,
})
local anvilTop = makePart({
	Name = "AnvilTop",
	Size = Vector3.new(7, 1.5, 3.5),
	Position = Vector3.new(45, BASE_Y + 3.75, -45),
	Color = Color3.fromRGB(45, 45, 50),
	Material = Enum.Material.Metal,
})
local furnace = makePart({
	Name = "Furnace",
	Size = Vector3.new(8, 8, 8),
	Position = Vector3.new(57, BASE_Y + 4, -45),
	Color = Color3.fromRGB(90, 60, 50),
	Material = Enum.Material.Brick,
})
local fire = Instance.new("Fire")
fire.Heat = 10
fire.Size = 8
fire.Parent = furnace
makeSign(anvilBase, "⚒ FORGE ⚒", Color3.fromRGB(255, 140, 50), 14, 3.5, 8)
makePrompt(anvilTop, "Forger", "Enclume", "Forge")

-- 2d. LE MARCHAND -----------------------------------------------------
local counter = makePart({
	Name = "MerchantCounter",
	Size = Vector3.new(12, 3.5, 4),
	Position = Vector3.new(45, BASE_Y + 1.75, 45),
	Color = Color3.fromRGB(140, 95, 55),
	Material = Enum.Material.WoodPlanks,
})
makePart({
	Name = "MerchantRoof",
	Size = Vector3.new(14, 1, 8),
	Position = Vector3.new(45, BASE_Y + 9, 47),
	Color = Color3.fromRGB(200, 60, 60),
	Material = Enum.Material.Fabric,
})
for _, x in ipairs({ 39, 51 }) do
	makePart({
		Name = "MerchantPole",
		Size = Vector3.new(0.8, 9, 0.8),
		Position = Vector3.new(x, BASE_Y + 4.5, 43.5),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	})
end
makeSign(counter, "💰 MARCHAND 💰", COLOR_GOLD, 14, 3.5, 9)
makePrompt(counter, "Vendre", "Marchand", "Ores")

-- 2e. L'ARMURERIE et L'AUTEL DE REBIRTH ------------------------------
local rack = makePart({
	Name = "WeaponRack",
	Size = Vector3.new(10, 5, 1),
	Position = Vector3.new(65, BASE_Y + 2.5, 0),
	Color = Color3.fromRGB(110, 75, 45),
	Material = Enum.Material.WoodPlanks,
})
makeSign(rack, "⚔ ARMURERIE ⚔", Color3.fromRGB(200, 220, 255), 14, 3.5, 6)
makePrompt(rack, "Mes armes", "Armurerie", "Weapons")

local altar = makePart({
	Name = "RebirthAltar",
	Size = Vector3.new(2, 8, 8), -- cylindre : X = hauteur, Y/Z = diamètre
	Position = Vector3.new(-30, BASE_Y + 1, 60),
	Color = Color3.fromRGB(180, 90, 255),
	Material = Enum.Material.Neon,
	Shape = Enum.PartType.Cylinder,
	Orientation = Vector3.new(0, 0, 90),
})
makeSign(altar, "♻ REBIRTH ♻", Color3.fromRGB(200, 140, 255), 14, 3.5, 6)
makePrompt(altar, "Rebirth", "Autel", "Rebirth")

local upgradeStand = makePart({
	Name = "UpgradeStand",
	Size = Vector3.new(6, 4, 6),
	Position = Vector3.new(30, BASE_Y + 2, 60),
	Color = Color3.fromRGB(70, 150, 255),
	Material = Enum.Material.Neon,
})
makeSign(upgradeStand, "⬆ AMÉLIORATIONS ⬆", Color3.fromRGB(140, 200, 255), 16, 3.5, 6)
makePrompt(upgradeStand, "Améliorer", "Améliorations", "Upgrades")

-- 2f. LE PORTAIL DU DONJON -------------------------------------------
for _, x in ipairs({ -8, 8 }) do
	makePart({
		Name = "PortalPillar",
		Size = Vector3.new(3, 16, 3),
		Position = Vector3.new(x, BASE_Y + 8, 80),
		Color = Color3.fromRGB(60, 50, 80),
		Material = Enum.Material.Slate,
	})
end
makePart({
	Name = "PortalTop",
	Size = Vector3.new(19, 3, 3),
	Position = Vector3.new(0, BASE_Y + 17.5, 80),
	Color = Color3.fromRGB(60, 50, 80),
	Material = Enum.Material.Slate,
})
local portal = makePart({
	Name = "Portal",
	Size = Vector3.new(13, 16, 0.5),
	Position = Vector3.new(0, BASE_Y + 8, 80),
	Color = Color3.fromRGB(150, 70, 255),
	Material = Enum.Material.Neon,
	Transparency = 0.3,
	CanCollide = false,
})
makeSign(portal, "🌀 DONJON 🌀", Color3.fromRGB(200, 150, 255), 16, 4, 12)
makePrompt(portal, "Entrer", "Donjon", "Teleport")

-- 2g. LES ARÈNES DU DONJON -------------------------------------------
local function arenaCenter(stage)
	return Vector3.new(0, BASE_Y, 400 + (stage - 1) * 260)
end

local function arenaArrival(stage)
	return arenaCenter(stage) + Vector3.new(0, 4, -ARENA_SIZE / 2 + 12)
end

local function getStageAt(position)
	for stage = 1, #Config.Stages do
		local center = arenaCenter(stage)
		if math.abs(position.X - center.X) <= ARENA_SIZE / 2
			and math.abs(position.Z - center.Z) <= ARENA_SIZE / 2
			and position.Y > center.Y - 20 and position.Y < center.Y + 60 then
			return stage
		end
	end
	return nil
end

local teleportToHub -- défini plus bas

for stage, info in ipairs(Config.Stages) do
	local center = arenaCenter(stage)
	makePart({
		Name = "Arena" .. stage,
		Size = Vector3.new(ARENA_SIZE, 4, ARENA_SIZE),
		Position = center - Vector3.new(0, 2, 0),
		Color = info.Floor,
		Material = Enum.Material[info.Material],
	})
	makeWalls(center, ARENA_SIZE, info.EnemyColor)

	-- Décor : quelques rochers / cristaux
	local decoRandom = Random.new(stage * 1000)
	for _ = 1, 8 do
		local size = decoRandom:NextNumber(3, 7)
		local side = decoRandom:NextInteger(0, 1) == 0 and -1 or 1
		makePart({
			Name = "Deco",
			Size = Vector3.new(size, size * 1.5, size),
			CFrame = CFrame.new(center + Vector3.new(side * decoRandom:NextNumber(40, 50), size * 0.6, decoRandom:NextNumber(-45, 45)))
				* CFrame.Angles(0, decoRandom:NextNumber(0, math.pi), decoRandom:NextNumber(-0.3, 0.3)),
			Color = info.EnemyColor:Lerp(info.Floor, 0.5),
			Material = Enum.Material.Rock,
		})
	end

	-- Panneau de l'étape
	local post = makePart({
		Name = "StageSign",
		Size = Vector3.new(1, 1, 1),
		Position = center + Vector3.new(0, 18, -ARENA_SIZE / 2 + 4),
		Transparency = 1,
		CanCollide = false,
	})
	makeSign(post, "Étape " .. stage .. " : " .. info.Name, info.EnemyColor, 40, 6, 0)

	-- Pad de retour au hub
	local returnPad = makePart({
		Name = "ReturnPad",
		Size = Vector3.new(6, 1, 6),
		Position = center + Vector3.new(-12, 0.5, -ARENA_SIZE / 2 + 8),
		Color = COLOR_GOLD,
		Material = Enum.Material.Neon,
	})
	makeSign(returnPad, "🏠 Hub", COLOR_GOLD, 6, 2, 3)
	local returnPrompt = makePrompt(returnPad, "Retour au hub", "Téléporteur", nil)
	returnPrompt.Triggered:Connect(function(player)
		teleportToHub(player)
	end)
end

------------------------------------------------------------------------
-- 3. DONNÉES DES JOUEURS + SAUVEGARDE
------------------------------------------------------------------------
local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.SaveKey)
	end)
	if ok then
		store = result
	else
		warn("[LootForge] DataStore indisponible : " .. tostring(result))
	end
end

local profiles = {} -- [player] = { Data = ..., CanSave = ..., ... }
local enemies = {}

local function defaultData()
	return {
		Coins = 0,
		Power = Config.StartPower,
		Rebirths = 0,
		MaxStage = 1,
		Ores = {},       -- { [idMinerai] = quantité }
		Weapons = {},    -- liste d'armes forgées
		Equipped = 0,    -- id de l'arme équipée (0 = épée en bois)
		Upgrades = { Capacity = 0, Luck = 0 },
		NextWeaponId = 1,
	}
end

local function reconcile(data)
	local default = defaultData()
	for key, value in pairs(default) do
		if data[key] == nil then
			data[key] = value
		end
	end
	for key, value in pairs(default.Upgrades) do
		if data.Upgrades[key] == nil then
			data.Upgrades[key] = value
		end
	end
	return data
end

local function loadData(player)
	if not store then
		return defaultData(), false
	end
	local key = "Player_" .. player.UserId
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			if type(result) == "table" then
				return reconcile(result), true
			end
			return defaultData(), true
		end
		warn("[LootForge] Chargement raté (essai " .. attempt .. ") : " .. tostring(result))
		if RunService:IsStudio() then
			break -- dans Studio, c'est presque toujours l'accès API qui est désactivé
		end
		task.wait(1)
	end
	return defaultData(), false
end

local function saveData(player)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return
	end
	local key = "Player_" .. player.UserId
	local ok, err = pcall(function()
		store:SetAsync(key, profile.Data)
	end)
	if not ok then
		warn("[LootForge] Sauvegarde ratée pour " .. player.Name .. " : " .. tostring(err))
	end
end

local function countOres(data)
	local total = 0
	for _, count in pairs(data.Ores) do
		total = total + count
	end
	return total
end

local function getEquippedWeapon(data)
	for _, weapon in ipairs(data.Weapons) do
		if weapon.Id == data.Equipped then
			return weapon
		end
	end
	return nil
end

local function getDamage(data)
	local weapon = getEquippedWeapon(data)
	local weaponMult = weapon and weapon.Mult or 1
	return Config.GetDamage(data.Power, weaponMult, data.Rebirths)
end

local function markDirty(player)
	local profile = profiles[player]
	if profile then
		profile.Dirty = true
	end
end

local function updateLeaderstats(player, data)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	leaderstats.Puissance.Value = Config.Format(data.Power)
	leaderstats["Étape"].Value = data.MaxStage
	leaderstats.Rebirths.Value = data.Rebirths
end

local function sendData(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.Data
	DataUpdate:FireClient(player, {
		Data = data,
		Damage = getDamage(data),
		Capacity = Config.GetCapacity(data.Upgrades.Capacity),
		OreTotal = countOres(data),
		Training = profile.Training,
		CanSave = profile.CanSave,
	})
	updateLeaderstats(player, data)
end

------------------------------------------------------------------------
-- 4. ARMES (Tool que le joueur tient en main)
------------------------------------------------------------------------
local onSwing -- défini plus bas

local function weldToHandle(handle, part, offset)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CFrame = handle.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = handle
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = handle.Parent
end

local function buildTool(weapon)
	local kindId = weapon and weapon.Kind or "Starter"
	local kind = Config.WeaponKinds[kindId] or Config.WeaponKinds.Starter
	local bladeColor = Color3.fromRGB(160, 115, 70)
	local bladeMaterial = Enum.Material.Wood
	local qualityName = nil
	if weapon then
		local ore = Config.OreById[weapon.MainOre]
		bladeColor = ore and ore.Color or COLOR_WHITE
		bladeMaterial = Enum.Material.Metal
		qualityName = weapon.Quality
		if ore and ore.Tier >= 11 then
			bladeMaterial = Enum.Material.Neon
		end
	end

	local tool = Instance.new("Tool")
	tool.Name = Config.GetWeaponName(weapon)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Dégâts ×" .. Config.Format(weapon and weapon.Mult or 1)
	tool:SetAttribute("LootForgeWeapon", true)
	tool:SetAttribute("Kind", kindId)
	-- Position de la main sur la poignée (comme l'épée classique de Roblox)
	tool.Grip = CFrame.new(0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0)

	-- La poignée (c'est le "Handle" que la main tient)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 0.35, 1.2)
	handle.Color = Color3.fromRGB(70, 45, 30)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	local slash = Instance.new("Sound")
	slash.Name = "SlashSound"
	slash.SoundId = "rbxasset://sounds/swordslash.wav"
	slash.Volume = 0.6
	slash.Parent = handle

	-- La garde
	local guard = Instance.new("Part")
	guard.Name = "Guard"
	guard.Size = Vector3.new(0.4, kind.Width * 2 + 0.6, 0.3)
	guard.Color = qualityName and (Config.Rarities[qualityName] or COLOR_GOLD) or Color3.fromRGB(90, 60, 40)
	guard.Material = Enum.Material.Metal
	weldToHandle(handle, guard, CFrame.new(0, 0, 0.75))

	-- La lame
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.2, kind.Width, kind.Length)
	blade.Color = bladeColor
	blade.Material = bladeMaterial
	blade.Reflectance = bladeMaterial == Enum.Material.Metal and 0.2 or 0
	weldToHandle(handle, blade, CFrame.new(0, 0, 0.9 + kind.Length / 2))

	-- Effets pour les belles qualités
	if qualityName == "Légendaire" or qualityName == "Mythique" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Config.Rarities[qualityName]
		sparkles.Parent = blade
	end
	if qualityName == "Épique" or qualityName == "Légendaire" or qualityName == "Mythique" then
		local light = Instance.new("PointLight")
		light.Color = Config.Rarities[qualityName]
		light.Brightness = 2
		light.Range = 8
		light.Parent = blade
	end

	return tool, kindId
end

local function removeWeaponTools(player)
	local function clear(container)
		if not container then
			return
		end
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Tool") and item:GetAttribute("LootForgeWeapon") then
				item:Destroy()
			end
		end
	end
	clear(player:FindFirstChildOfClass("Backpack"))
	clear(player.Character)
end

local function giveWeapon(player)
	local profile = profiles[player]
	local character = player.Character
	if not profile or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	removeWeaponTools(player)
	local tool, kindId = buildTool(getEquippedWeapon(profile.Data))
	tool.Activated:Connect(function()
		onSwing(player, tool, kindId)
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	tool.Parent = backpack or character
	humanoid:EquipTool(tool)
end

------------------------------------------------------------------------
-- 5. LES MONSTRES
------------------------------------------------------------------------
local function makeFace(body, angry)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(100, 100)
	surface.LightInfluence = 0
	surface.Parent = body
	local function frame(props)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		for key, value in pairs(props) do
			f[key] = value
		end
		f.Parent = surface
		return f
	end
	for _, x in ipairs({ 0.22, 0.58 }) do
		local eye = frame({ Size = UDim2.fromScale(0.2, 0.2), Position = UDim2.fromScale(x, 0.28), BackgroundColor3 = COLOR_WHITE })
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = eye
		local pupil = Instance.new("Frame")
		pupil.BorderSizePixel = 0
		pupil.Size = UDim2.fromScale(0.5, 0.5)
		pupil.Position = UDim2.fromScale(0.25, 0.35)
		pupil.BackgroundColor3 = angry and Color3.fromRGB(200, 0, 0) or Color3.fromRGB(0, 0, 0)
		pupil.Parent = eye
		local pupilCorner = Instance.new("UICorner")
		pupilCorner.CornerRadius = UDim.new(0.5, 0)
		pupilCorner.Parent = pupil
	end
	frame({ Size = UDim2.fromScale(0.5, 0.08), Position = UDim2.fromScale(0.25, 0.68), BackgroundColor3 = Color3.fromRGB(30, 10, 10) })
	return surface
end

local function updateEnemyBar(enemy)
	local ratio = math.max(0, math.min(1, enemy.HP / enemy.MaxHP))
	enemy.Fill.Size = UDim2.fromScale(ratio, 1)
	enemy.HPLabel.Text = Config.Format(math.ceil(math.max(enemy.HP, 0))) .. " / " .. Config.Format(enemy.MaxHP)
end

local function createEnemy(stage, isBoss, offsetX, offsetZ)
	local info = Config.Stages[stage]
	local size = isBoss and 11 or 5
	local center = arenaCenter(stage)
	local spawnPosition = center + Vector3.new(offsetX, size / 2, offsetZ)
	-- Le monstre regarde vers l'entrée de l'arène
	local spawnCFrame = CFrame.lookAt(spawnPosition, Vector3.new(center.X, spawnPosition.Y, center.Z - ARENA_SIZE))

	local body = Instance.new("Part")
	body.Name = isBoss and info.Boss or info.Enemy
	body.Anchored = true
	body.Size = Vector3.new(size, size, size)
	body.Color = isBoss and info.BossColor or info.EnemyColor
	body.Material = Enum.Material.SmoothPlastic
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = spawnCFrame
	makeFace(body, isBoss)

	-- Barre de vie au-dessus du monstre
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(isBoss and 12 or 6, 0, isBoss and 2.6 or 1.8, 0)
	gui.StudsOffset = Vector3.new(0, size / 2 + (isBoss and 3 or 1.6), 0)
	gui.MaxDistance = 150
	gui.LightInfluence = 0
	gui.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = (isBoss and "👑 " or "") .. body.Name
	nameLabel.TextColor3 = isBoss and COLOR_GOLD or COLOR_WHITE
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Parent = gui

	local barBack = Instance.new("Frame")
	barBack.Size = UDim2.fromScale(1, 0.45)
	barBack.Position = UDim2.fromScale(0, 0.55)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBack.BorderSizePixel = 0
	barBack.Parent = gui
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0.3, 0)
	backCorner.Parent = barBack

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = isBoss and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.3, 0)
	fillCorner.Parent = fill

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Size = UDim2.fromScale(1, 1)
	hpLabel.BackgroundTransparency = 1
	hpLabel.TextColor3 = COLOR_WHITE
	hpLabel.TextScaled = true
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.TextStrokeTransparency = 0.3
	hpLabel.ZIndex = 2
	hpLabel.Parent = barBack

	local enemy = {
		Body = body,
		Stage = stage,
		IsBoss = isBoss,
		Size = size,
		Center = center,
		SpawnCFrame = spawnCFrame,
		MaxHP = Config.GetEnemyHP(stage, isBoss),
		HP = 0,
		Alive = true,
		AtHome = true,
		LastAttack = 0,
		Contributors = {},
		Fill = fill,
		HPLabel = hpLabel,
	}
	enemy.HP = enemy.MaxHP
	updateEnemyBar(enemy)
	body.Parent = enemiesFolder
	table.insert(enemies, enemy)
	return enemy
end

local NORMAL_SPOTS = { { -25, -10 }, { 25, -10 }, { -25, 15 }, { 25, 15 } }
for stage = 1, #Config.Stages do
	for _, spot in ipairs(NORMAL_SPOTS) do
		createEnemy(stage, false, spot[1], spot[2])
	end
	createEnemy(stage, true, 0, 35)
end

local function respawnEnemy(enemy)
	enemy.HP = enemy.MaxHP
	enemy.Contributors = {}
	enemy.Body.CFrame = enemy.SpawnCFrame
	enemy.AtHome = true
	enemy.Alive = true
	updateEnemyBar(enemy)
	enemy.Body.Parent = enemiesFolder
end

local function rewardKill(player, enemy, position)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.Data
	local coins = Config.GetEnemyCoins(enemy.Stage, enemy.IsBoss)
	data.Coins = data.Coins + coins

	local capacity = Config.GetCapacity(data.Upgrades.Capacity)
	local drops = enemy.IsBoss and Config.BossOreDrops or 1
	local gained = {}
	local full = false
	for _ = 1, drops do
		if countOres(data) < capacity then
			local oreId = Config.RollOre(enemy.Stage, data.Upgrades.Luck, enemy.IsBoss and 1 or 0, random01())
			data.Ores[oreId] = (data.Ores[oreId] or 0) + 1
			table.insert(gained, oreId)
		else
			full = true
		end
	end
	LootFx:FireClient(player, { Ores = gained, Coins = coins, Position = position })

	if full and os.clock() - profile.FullWarn > 6 then
		profile.FullWarn = os.clock()
		notify(player, "🎒 Inventaire de minerais plein ! Forge, vends ou achète de la capacité.", COLOR_BAD)
	end

	if enemy.IsBoss and enemy.Stage >= data.MaxStage then
		if enemy.Stage < #Config.Stages then
			data.MaxStage = enemy.Stage + 1
			notify(player, "🔓 Étape " .. data.MaxStage .. " débloquée : " .. Config.Stages[data.MaxStage].Name .. " !", COLOR_GOLD)
		else
			notify(player, "🏆 Tu as battu le boss final ! Fais un Rebirth pour devenir encore plus fort.", COLOR_GOLD)
		end
	end
	markDirty(player)
end

local function killEnemy(enemy)
	enemy.Alive = false
	enemy.HP = 0
	local position = enemy.Body.Position
	enemy.Body.Parent = nil -- le monstre disparaît
	for contributor in pairs(enemy.Contributors) do
		if contributor.Parent == Players then
			rewardKill(contributor, enemy, position)
		end
	end
	enemy.Contributors = {}
	task.delay(enemy.IsBoss and Config.BossRespawn or Config.EnemyRespawn, function()
		respawnEnemy(enemy)
	end)
end

local function damageEnemy(enemy, player, amount)
	if not enemy.Alive then
		return
	end
	enemy.HP = enemy.HP - amount
	enemy.Contributors[player] = true
	local killed = enemy.HP <= 0
	HitFx:FireClient(player, enemy.Body.Position + Vector3.new(0, enemy.Size / 2, 0), amount, killed)
	if killed then
		killEnemy(enemy)
	else
		updateEnemyBar(enemy)
	end
end

-- Quand le joueur clique avec son arme
onSwing = function(player, tool, kindId)
	local profile = profiles[player]
	if not profile then
		return
	end
	local kind = Config.WeaponKinds[kindId] or Config.WeaponKinds.Starter
	local now = os.clock()
	if now - profile.LastSwing < kind.Cooldown then
		return
	end
	profile.LastSwing = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or tool.Parent ~= character then
		return
	end

	-- Animation d'attaque (gérée par le script "Animate" de Roblox)
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	local slash = tool:FindFirstChild("Handle") and tool.Handle:FindFirstChild("SlashSound")
	if slash then
		slash:Play()
	end

	local damage = getDamage(profile.Data)
	local closest, closestDistance = nil, math.huge
	for _, enemy in ipairs(enemies) do
		if enemy.Alive then
			local distance = (enemy.Body.Position - root.Position).Magnitude - enemy.Size / 2
			if distance <= kind.Range then
				if kind.AoE then
					damageEnemy(enemy, player, damage) -- Espadon : touche tout le monde autour
				elseif distance < closestDistance then
					closest, closestDistance = enemy, distance
				end
			end
		end
	end
	if closest then
		damageEnemy(closest, player, damage)
	end
end

-- IA des monstres : poursuivre le joueur le plus proche dans l'arène et attaquer
local function updateEnemy(enemy, targets, dt, now)
	local body = enemy.Body
	local position = body.Position
	local best, bestDistance = nil, Config.EnemyAggroRange
	if targets then
		for _, target in ipairs(targets) do
			local p = target.Root.Position
			local distance = (Vector3.new(p.X, position.Y, p.Z) - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = target, distance
			end
		end
	end

	local goal
	local attackRange = enemy.Size / 2 + 4
	if best then
		goal = best.Root.Position
		if bestDistance <= attackRange then
			if now - enemy.LastAttack >= Config.EnemyAttackCooldown then
				enemy.LastAttack = now
				best.Humanoid:TakeDamage(Config.GetEnemyDamage(enemy.Stage, enemy.IsBoss))
			end
			local flatGoal = Vector3.new(goal.X, position.Y, goal.Z)
			if (flatGoal - position).Magnitude > 0.5 then
				body.CFrame = CFrame.lookAt(position, flatGoal)
			end
			return
		end
	else
		goal = enemy.SpawnCFrame.Position
	end

	local flatGoal = Vector3.new(goal.X, position.Y, goal.Z)
	local direction = flatGoal - position
	local distance = direction.Magnitude
	if not best and distance < 0.5 then
		-- Revenu à sa place : il se soigne
		if not enemy.AtHome then
			enemy.AtHome = true
			body.CFrame = enemy.SpawnCFrame
			enemy.HP = enemy.MaxHP
			enemy.Contributors = {}
			updateEnemyBar(enemy)
		end
		return
	end
	enemy.AtHome = false
	local speed = enemy.IsBoss and Config.BossSpeed or Config.EnemySpeed
	local step = math.min(speed * dt, distance)
	local newPosition = position + direction.Unit * step
	local limit = ARENA_SIZE / 2 - enemy.Size / 2 - 2
	newPosition = Vector3.new(
		math.max(enemy.Center.X - limit, math.min(enemy.Center.X + limit, newPosition.X)),
		position.Y,
		math.max(enemy.Center.Z - limit, math.min(enemy.Center.Z + limit, newPosition.Z))
	)
	body.CFrame = CFrame.lookAt(newPosition, newPosition + direction.Unit)
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	-- Quels joueurs sont dans quelle arène ?
	local present = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local stage = getStageAt(root.Position)
			if stage then
				present[stage] = present[stage] or {}
				table.insert(present[stage], { Root = root, Humanoid = humanoid })
			end
		end
	end
	for _, enemy in ipairs(enemies) do
		if enemy.Alive then
			local targets = present[enemy.Stage]
			if targets or not enemy.AtHome then
				updateEnemy(enemy, targets, dt, now)
			end
		end
	end
end)

------------------------------------------------------------------------
-- 6. TÉLÉPORTATION
------------------------------------------------------------------------
teleportToHub = function(player)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(CFrame.new(HUB_SPAWN + Vector3.new(0, 3, 0)))
	end
end

local function teleportToStage(player, stage)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		local arrival = arenaArrival(stage)
		local center = arenaCenter(stage)
		character:PivotTo(CFrame.lookAt(arrival, Vector3.new(center.X, arrival.Y, center.Z)))
	end
end

------------------------------------------------------------------------
-- 7. ACTIONS DEMANDÉES PAR LE CLIENT (on vérifie TOUT côté serveur !)
------------------------------------------------------------------------
local actions = {}

actions.Forge = function(player, profile, selection)
	if type(selection) ~= "table" then
		return
	end
	local data = profile.Data
	if #data.Weapons >= Config.MaxWeapons then
		notify(player, "Tu as déjà " .. Config.MaxWeapons .. " armes. Vends-en une à l'armurerie !", COLOR_BAD)
		return
	end
	local clean = {}
	for oreId, count in pairs(selection) do
		if type(oreId) ~= "string" or type(count) ~= "number" or not Config.OreById[oreId] then
			return
		end
		count = math.floor(count)
		if count > 0 then
			if (data.Ores[oreId] or 0) < count then
				notify(player, "Tu n'as pas assez de minerais.", COLOR_BAD)
				return
			end
			clean[oreId] = count
		end
	end
	local preview = Config.PreviewForge(clean)
	if not preview.Ok then
		notify(player, preview.Error, COLOR_BAD)
		return
	end
	for oreId, count in pairs(clean) do
		data.Ores[oreId] = data.Ores[oreId] - count
		if data.Ores[oreId] <= 0 then
			data.Ores[oreId] = nil
		end
	end
	local quality = Config.RollQuality(random01())
	local weapon = {
		Id = data.NextWeaponId,
		Kind = preview.Kind,
		MainOre = preview.MainOre,
		Quality = quality.Name,
		Mult = preview.Mult * quality.Mult,
		OreCount = preview.Total,
	}
	data.NextWeaponId = data.NextWeaponId + 1
	table.insert(data.Weapons, weapon)
	notify(player, "⚒ Forgé : " .. Config.GetWeaponName(weapon) .. " [" .. quality.Name .. "]  Dégâts ×" .. Config.Format(weapon.Mult), Config.Rarities[quality.Name])

	-- On équipe automatiquement l'arme si elle est meilleure
	local current = getEquippedWeapon(data)
	if weapon.Mult > (current and current.Mult or 1) then
		data.Equipped = weapon.Id
		giveWeapon(player)
		notify(player, "Nouvelle arme équipée !", COLOR_GOOD)
	end
	markDirty(player)
end

actions.SellOre = function(player, profile, payload)
	if type(payload) ~= "table" or type(payload.Id) ~= "string" or type(payload.Amount) ~= "number" then
		return
	end
	local data = profile.Data
	local ore = Config.OreById[payload.Id]
	local owned = data.Ores[payload.Id] or 0
	local amount = math.min(owned, math.floor(payload.Amount))
	if not ore or amount <= 0 then
		return
	end
	data.Ores[payload.Id] = owned - amount
	if data.Ores[payload.Id] <= 0 then
		data.Ores[payload.Id] = nil
	end
	local earned = amount * ore.Sell
	data.Coins = data.Coins + earned
	notify(player, "💰 +" .. Config.Format(earned) .. " pièces (" .. amount .. " " .. ore.Name .. ")", COLOR_GOLD)
	markDirty(player)
end

actions.SellAllOres = function(player, profile)
	local data = profile.Data
	local earned, amount = 0, 0
	for oreId, count in pairs(data.Ores) do
		local ore = Config.OreById[oreId]
		if ore then
			earned = earned + count * ore.Sell
			amount = amount + count
		end
	end
	if amount == 0 then
		return
	end
	data.Ores = {}
	data.Coins = data.Coins + earned
	notify(player, "💰 +" .. Config.Format(earned) .. " pièces (" .. amount .. " minerais vendus)", COLOR_GOLD)
	markDirty(player)
end

actions.Equip = function(player, profile, weaponId)
	if type(weaponId) ~= "number" then
		return
	end
	local data = profile.Data
	if weaponId ~= 0 then
		local found = false
		for _, weapon in ipairs(data.Weapons) do
			if weapon.Id == weaponId then
				found = true
			end
		end
		if not found then
			return
		end
	end
	data.Equipped = weaponId
	giveWeapon(player)
	markDirty(player)
end

actions.SellWeapon = function(player, profile, weaponId)
	if type(weaponId) ~= "number" then
		return
	end
	local data = profile.Data
	for index, weapon in ipairs(data.Weapons) do
		if weapon.Id == weaponId then
			local price = Config.GetWeaponSellPrice(weapon)
			table.remove(data.Weapons, index)
			data.Coins = data.Coins + price
			notify(player, "💰 Arme vendue : +" .. Config.Format(price) .. " pièces", COLOR_GOLD)
			if data.Equipped == weaponId then
				data.Equipped = 0
				giveWeapon(player)
			end
			markDirty(player)
			return
		end
	end
end

actions.Upgrade = function(player, profile, upgradeId)
	local upgrade = type(upgradeId) == "string" and Config.Upgrades[upgradeId]
	if not upgrade then
		return
	end
	local data = profile.Data
	local level = data.Upgrades[upgradeId] or 0
	if level >= upgrade.Max then
		notify(player, "Niveau maximum atteint !", COLOR_BAD)
		return
	end
	local cost = Config.GetUpgradeCost(upgradeId, level)
	if data.Coins < cost then
		notify(player, "Il te manque " .. Config.Format(cost - data.Coins) .. " pièces.", COLOR_BAD)
		return
	end
	data.Coins = data.Coins - cost
	data.Upgrades[upgradeId] = level + 1
	notify(player, "⬆ " .. upgrade.Name .. " niveau " .. (level + 1) .. " !", COLOR_GOOD)
	markDirty(player)
end

actions.Rebirth = function(player, profile)
	local data = profile.Data
	local cost = Config.GetRebirthCost(data.Rebirths)
	if data.Power < cost then
		notify(player, "Il te faut " .. Config.Format(cost) .. " de puissance pour faire un Rebirth.", COLOR_BAD)
		return
	end
	data.Rebirths = data.Rebirths + 1
	data.Power = Config.StartPower
	data.MaxStage = 1
	notify(player, "♻ REBIRTH " .. data.Rebirths .. " ! Multiplicateur ×" .. Config.GetRebirthMult(data.Rebirths), Color3.fromRGB(200, 140, 255))
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = 100 + 25 * data.Rebirths
		humanoid.Health = humanoid.MaxHealth
	end
	teleportToHub(player)
	markDirty(player)
end

actions.Teleport = function(player, profile, stage)
	if type(stage) ~= "number" then
		return
	end
	stage = math.floor(stage)
	if stage == 0 then
		teleportToHub(player)
		return
	end
	if stage < 1 or stage > #Config.Stages then
		return
	end
	if stage > profile.Data.MaxStage then
		notify(player, "🔒 Étape verrouillée : bats le boss de l'étape " .. (stage - 1) .. " !", COLOR_BAD)
		return
	end
	teleportToStage(player, stage)
end

actions.RequestData = function(player, profile)
	profile.Dirty = true
end

Action.OnServerEvent:Connect(function(player, actionName, payload)
	local profile = profiles[player]
	if not profile or type(actionName) ~= "string" then
		return
	end
	local handler = actions[actionName]
	if handler then
		handler(player, profile, payload)
	end
end)

------------------------------------------------------------------------
-- 8. ARRIVÉE / DÉPART DES JOUEURS
------------------------------------------------------------------------
local function setupLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local power = Instance.new("StringValue")
	power.Name = "Puissance"
	power.Value = "0"
	power.Parent = leaderstats
	local stage = Instance.new("IntValue")
	stage.Name = "Étape"
	stage.Value = 1
	stage.Parent = leaderstats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats
	leaderstats.Parent = player
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local profile = profiles[player]
	if not humanoid or not profile then
		return
	end
	humanoid.MaxHealth = 100 + 25 * profile.Data.Rebirths
	humanoid.Health = humanoid.MaxHealth
	task.wait(0.3) -- on laisse le temps au sac à dos (Backpack) de se créer
	if player.Character == character then
		giveWeapon(player)
	end
end

local function onPlayerAdded(player)
	setupLeaderstats(player)
	local data, canSave = loadData(player)
	if player.Parent ~= Players then
		return -- le joueur est parti pendant le chargement
	end
	profiles[player] = {
		Data = data,
		CanSave = canSave,
		Dirty = true,
		LastSwing = 0,
		Training = 0,
		PadWarn = 0,
		FullWarn = 0,
	}
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	notify(player, "Bienvenue dans " .. Config.GameTitle .. " ! Bats des monstres, récupère des minerais et forge des armes !", COLOR_GOLD)
	if not canSave then
		notify(player, "⚠ Sauvegarde désactivée (dans Studio : Game Settings > Security > Enable Studio Access to API Services).", COLOR_BAD)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	profiles[player] = nil
	for _, enemy in ipairs(enemies) do
		enemy.Contributors[player] = nil
	end
end)

game:BindToClose(function()
	if not store then
		return
	end
	local remaining = 0
	for player in pairs(profiles) do
		remaining = remaining + 1
		task.spawn(function()
			saveData(player)
			remaining = remaining - 1
		end)
	end
	local started = os.clock()
	while remaining > 0 and os.clock() - started < 20 do
		task.wait(0.1)
	end
end)

------------------------------------------------------------------------
-- 9. BOUCLES : entraînement (chaque seconde), envoi des données, autosave
------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		for player, profile in pairs(profiles) do
			local gain = 0
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local padIndex = root and getPadAt(root.Position)
			if padIndex then
				local pad = Config.TrainingPads[padIndex]
				local data = profile.Data
				if data.Power >= pad.ReqPower and data.Rebirths >= pad.ReqRebirths then
					gain = pad.Gain * Config.GetRebirthMult(data.Rebirths)
					data.Power = data.Power + gain
				elseif os.clock() - profile.PadWarn > 4 then
					profile.PadWarn = os.clock()
					local text = "🔒 " .. pad.Name .. " : il faut " .. Config.Format(pad.ReqPower) .. " de puissance"
					if pad.ReqRebirths > 0 then
						text = text .. " et " .. pad.ReqRebirths .. " rebirth(s)"
					end
					notify(player, text, COLOR_BAD)
				end
			end
			if gain > 0 or gain ~= profile.Training then
				profile.Training = gain
				profile.Dirty = true
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		for player, profile in pairs(profiles) do
			if profile.Dirty then
				profile.Dirty = false
				sendData(player)
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(90)
		for player in pairs(profiles) do
			task.spawn(saveData, player)
		end
	end
end)

print("[LootForge] Serveur prêt !")
