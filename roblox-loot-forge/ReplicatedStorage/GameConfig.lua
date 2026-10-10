--[[
	GameConfig  (ModuleScript)
	À placer dans : ReplicatedStorage  (nom exact : GameConfig)

	Tous les réglages du jeu sont ici : minerais, étapes, armes, prix...
	Change les nombres pour équilibrer ton jeu comme tu veux !
]]

local Config = {}

Config.GameTitle = "Loot & Forge"   -- le nom affiché dans le hub
Config.StartPower = 5               -- puissance de départ (et après un rebirth)
Config.MaxWeapons = 15              -- nombre max d'armes dans l'inventaire
Config.SaveKey = "LootForge_Save_v1" -- nom de la sauvegarde (DataStore)

------------------------------------------------------------------------
-- RARETÉS (couleurs utilisées pour les minerais et la qualité des armes)
------------------------------------------------------------------------
Config.Rarities = {
	["Commun"] = Color3.fromRGB(200, 200, 200),
	["Peu commun"] = Color3.fromRGB(90, 220, 110),
	["Rare"] = Color3.fromRGB(70, 150, 255),
	["Épique"] = Color3.fromRGB(185, 95, 255),
	["Légendaire"] = Color3.fromRGB(255, 190, 40),
	["Mythique"] = Color3.fromRGB(255, 70, 90),
	["Secret"] = Color3.fromRGB(40, 255, 230),
}

------------------------------------------------------------------------
-- MINERAIS
-- Mult = multiplicateur de l'arme forgée avec ce minerai
-- Sell = prix de vente (pièces) d'un minerai
------------------------------------------------------------------------
Config.Ores = {
	{ Id = "stone",     Name = "Pierre",          Of = "de Pierre",          Rarity = "Commun",     Mult = 1,    Sell = 1,    Color = Color3.fromRGB(130, 130, 130) },
	{ Id = "copper",    Name = "Cuivre",          Of = "de Cuivre",          Rarity = "Commun",     Mult = 2,    Sell = 2,    Color = Color3.fromRGB(200, 110, 60) },
	{ Id = "iron",      Name = "Fer",             Of = "de Fer",             Rarity = "Peu commun", Mult = 4,    Sell = 5,    Color = Color3.fromRGB(190, 190, 200) },
	{ Id = "silver",    Name = "Argent",          Of = "d'Argent",           Rarity = "Peu commun", Mult = 7,    Sell = 10,   Color = Color3.fromRGB(225, 230, 240) },
	{ Id = "gold",      Name = "Or",              Of = "d'Or",               Rarity = "Rare",       Mult = 12,   Sell = 20,   Color = Color3.fromRGB(255, 200, 40) },
	{ Id = "ruby",      Name = "Rubis",           Of = "de Rubis",           Rarity = "Rare",       Mult = 20,   Sell = 40,   Color = Color3.fromRGB(230, 40, 60) },
	{ Id = "sapphire",  Name = "Saphir",          Of = "de Saphir",          Rarity = "Épique",     Mult = 35,   Sell = 80,   Color = Color3.fromRGB(40, 90, 230) },
	{ Id = "emerald",   Name = "Émeraude",        Of = "d'Émeraude",         Rarity = "Épique",     Mult = 60,   Sell = 150,  Color = Color3.fromRGB(30, 200, 100) },
	{ Id = "amethyst",  Name = "Améthyste",       Of = "d'Améthyste",        Rarity = "Légendaire", Mult = 100,  Sell = 300,  Color = Color3.fromRGB(160, 70, 230) },
	{ Id = "diamond",   Name = "Diamant",         Of = "de Diamant",         Rarity = "Légendaire", Mult = 170,  Sell = 600,  Color = Color3.fromRGB(120, 240, 255) },
	{ Id = "obsidian",  Name = "Obsidienne",      Of = "d'Obsidienne",       Rarity = "Mythique",   Mult = 300,  Sell = 1200, Color = Color3.fromRGB(70, 40, 95) },
	{ Id = "celestial", Name = "Cristal Céleste", Of = "de Cristal Céleste", Rarity = "Mythique",   Mult = 500,  Sell = 2500, Color = Color3.fromRGB(255, 170, 230) },
	{ Id = "apex",      Name = "Apex",            Of = "de l'Apex",          Rarity = "Secret",     Mult = 1000, Sell = 6000, Color = Color3.fromRGB(255, 255, 255) },
}

Config.OreById = {}
for index, ore in ipairs(Config.Ores) do
	ore.Tier = index
	Config.OreById[ore.Id] = ore
end

------------------------------------------------------------------------
-- ÉTAPES DU DONJON (une arène par étape)
-- Pour débloquer l'étape suivante : battre le BOSS de l'étape.
------------------------------------------------------------------------
Config.Stages = {
	{ Name = "Grotte Moussue",     Material = "Grass",       Floor = Color3.fromRGB(70, 110, 60),   Enemy = "Slime",                  EnemyColor = Color3.fromRGB(90, 220, 90),   Boss = "Roi Slime",          BossColor = Color3.fromRGB(40, 170, 60) },
	{ Name = "Mine Abandonnée",    Material = "Slate",       Floor = Color3.fromRGB(110, 85, 60),   Enemy = "Gobelin Mineur",         EnemyColor = Color3.fromRGB(120, 160, 70),  Boss = "Chef Gobelin",       BossColor = Color3.fromRGB(90, 120, 40) },
	{ Name = "Cavernes de Cuivre", Material = "Rock",        Floor = Color3.fromRGB(150, 90, 50),   Enemy = "Golem de Cuivre",        EnemyColor = Color3.fromRGB(200, 120, 70),  Boss = "Golem Ancien",       BossColor = Color3.fromRGB(170, 90, 50) },
	{ Name = "Forêt Sombre",       Material = "Grass",       Floor = Color3.fromRGB(40, 70, 45),    Enemy = "Loup des Ombres",        EnemyColor = Color3.fromRGB(70, 70, 90),    Boss = "Alpha des Ombres",   BossColor = Color3.fromRGB(40, 40, 60) },
	{ Name = "Désert Brûlant",     Material = "Sand",        Floor = Color3.fromRGB(220, 190, 120), Enemy = "Scorpion",               EnemyColor = Color3.fromRGB(200, 140, 60),  Boss = "Faucheur du Désert", BossColor = Color3.fromRGB(150, 60, 40) },
	{ Name = "Marais Toxique",     Material = "Mud",         Floor = Color3.fromRGB(70, 90, 60),    Enemy = "Crapaud Toxique",        EnemyColor = Color3.fromRGB(140, 200, 60),  Boss = "Hydre du Marais",    BossColor = Color3.fromRGB(80, 140, 50) },
	{ Name = "Volcan",             Material = "Basalt",      Floor = Color3.fromRGB(60, 30, 30),    Enemy = "Diablotin de Lave",      EnemyColor = Color3.fromRGB(255, 100, 40),  Boss = "Seigneur de Magma",  BossColor = Color3.fromRGB(220, 60, 20) },
	{ Name = "Glacier Éternel",    Material = "Ice",         Floor = Color3.fromRGB(190, 220, 240), Enemy = "Yéti",                   EnemyColor = Color3.fromRGB(230, 240, 255), Boss = "Roi Yéti",           BossColor = Color3.fromRGB(160, 200, 255) },
	{ Name = "Ruines Antiques",    Material = "Cobblestone", Floor = Color3.fromRGB(150, 145, 130), Enemy = "Gardien de Pierre",      EnemyColor = Color3.fromRGB(170, 165, 150), Boss = "Colosse Antique",    BossColor = Color3.fromRGB(120, 115, 100) },
	{ Name = "Royaume de Cristal", Material = "Glass",       Floor = Color3.fromRGB(200, 150, 230), Enemy = "Élémentaire de Cristal", EnemyColor = Color3.fromRGB(230, 140, 255), Boss = "Reine de Cristal",   BossColor = Color3.fromRGB(190, 90, 255) },
	{ Name = "Abysses",            Material = "Slate",       Floor = Color3.fromRGB(25, 35, 70),    Enemy = "Rôdeur des Abysses",     EnemyColor = Color3.fromRGB(40, 80, 160),   Boss = "Kraken",             BossColor = Color3.fromRGB(20, 50, 130) },
	{ Name = "Néant",              Material = "Slate",       Floor = Color3.fromRGB(20, 15, 30),    Enemy = "Spectre du Néant",       EnemyColor = Color3.fromRGB(120, 60, 200),  Boss = "Dieu du Néant",      BossColor = Color3.fromRGB(60, 10, 90) },
}

Config.EnemyBaseHP = 40        -- PV d'un monstre de l'étape 1
Config.EnemyHPGrowth = 5       -- PV multipliés par 5 à chaque étape
Config.BossHPMult = 10         -- un boss a 10x plus de PV
Config.EnemyRespawn = 4        -- secondes avant qu'un monstre réapparaisse
Config.BossRespawn = 15        -- secondes avant que le boss réapparaisse
Config.EnemySpeed = 9          -- vitesse des monstres
Config.BossSpeed = 6
Config.EnemyAggroRange = 35    -- distance à laquelle un monstre te poursuit
Config.EnemyAttackCooldown = 2 -- secondes entre deux attaques d'un monstre
Config.BossOreDrops = 3        -- un boss donne 3 minerais

function Config.GetEnemyHP(stage, isBoss)
	local hp = Config.EnemyBaseHP * Config.EnemyHPGrowth ^ (stage - 1)
	if isBoss then
		hp = hp * Config.BossHPMult
	end
	return hp
end

function Config.GetEnemyCoins(stage, isBoss)
	local coins = math.floor(2 * 2.2 ^ (stage - 1))
	if isBoss then
		coins = coins * 8
	end
	return coins
end

-- Dégâts d'un coup de monstre (le joueur a 100 PV, +25 par rebirth)
function Config.GetEnemyDamage(stage, isBoss)
	if isBoss then
		return 4 + 2 * stage
	end
	return 1 + math.floor(stage / 2)
end

-- Tire au hasard le minerai lâché par un monstre de l'étape "stage".
-- luckLevel = niveau de l'amélioration Chance ; bonusTier = +1 pour les boss
function Config.RollOre(stage, luckLevel, bonusTier, randomNumber)
	local base = math.max(1, math.min(#Config.Ores, stage + (bonusTier or 0)))
	local luck = 1 + 0.15 * (luckLevel or 0)
	local options = {
		{ Tier = base - 1, Weight = 30 },
		{ Tier = base, Weight = 55 },
		{ Tier = base + 1, Weight = 14 * luck },
		{ Tier = base + 2, Weight = 1 * luck },
	}
	local valid = {}
	local total = 0
	for _, option in ipairs(options) do
		if option.Tier >= 1 and option.Tier <= #Config.Ores then
			table.insert(valid, option)
			total = total + option.Weight
		end
	end
	local roll = (randomNumber or math.random()) * total
	for _, option in ipairs(valid) do
		roll = roll - option.Weight
		if roll <= 0 then
			return Config.Ores[option.Tier].Id
		end
	end
	return Config.Ores[valid[#valid].Tier].Id
end

------------------------------------------------------------------------
-- ARMES
-- 4 à 12 minerais  -> Katana  (rapide, un seul ennemi)
-- 13 minerais ou + -> Espadon (lent, frappe tous les ennemis autour)
------------------------------------------------------------------------
Config.MinOres = 4
Config.GreatswordOres = 13
Config.MaxOreTypes = 4

Config.WeaponKinds = {
	Starter = { Name = "Épée en bois", Cooldown = 0.45, Range = 7,  AoE = false, Length = 2.6, Width = 0.45, Bonus = 1 },
	Katana  = { Name = "Katana",       Cooldown = 0.35, Range = 9,  AoE = false, Length = 3.6, Width = 0.4,  Bonus = 1 },
	Espadon = { Name = "Espadon",      Cooldown = 0.8,  Range = 13, AoE = true,  Length = 5,   Width = 1.1,  Bonus = 1.6 },
}

-- Qualité tirée au hasard à chaque forge (Chance = pourcentage)
Config.Qualities = {
	{ Name = "Commun",     Chance = 50, Mult = 1 },
	{ Name = "Rare",       Chance = 30, Mult = 1.25 },
	{ Name = "Épique",     Chance = 14, Mult = 1.6 },
	{ Name = "Légendaire", Chance = 5,  Mult = 2.2 },
	{ Name = "Mythique",   Chance = 1,  Mult = 3.5 },
}

function Config.RollQuality(randomNumber)
	local total = 0
	for _, quality in ipairs(Config.Qualities) do
		total = total + quality.Chance
	end
	local roll = (randomNumber or math.random()) * total
	for _, quality in ipairs(Config.Qualities) do
		roll = roll - quality.Chance
		if roll <= 0 then
			return quality
		end
	end
	return Config.Qualities[1]
end

-- Calcule l'arme obtenue avec une sélection { [idMinerai] = quantité }
-- Renvoie un tableau : { Ok, Error, Kind, Mult, MainOre, Total, Types }
function Config.PreviewForge(selection)
	local total, types, weighted = 0, 0, 0
	local mainOre = nil
	for oreId, count in pairs(selection) do
		local ore = Config.OreById[oreId]
		if ore and count > 0 then
			total = total + count
			types = types + 1
			weighted = weighted + ore.Mult * count
			if mainOre == nil or ore.Tier > Config.OreById[mainOre].Tier then
				mainOre = oreId
			end
		end
	end
	local result = { Ok = false, Total = total, Types = types }
	if total < Config.MinOres then
		result.Error = "Il faut au moins " .. Config.MinOres .. " minerais pour forger"
		return result
	end
	if types > Config.MaxOreTypes then
		result.Error = "Maximum " .. Config.MaxOreTypes .. " types de minerais différents"
		return result
	end
	local kind = "Katana"
	if total >= Config.GreatswordOres then
		kind = "Espadon"
	end
	local average = weighted / total
	result.Ok = true
	result.Kind = kind
	result.MainOre = mainOre
	result.Mult = average * (1 + 0.15 * total) * Config.WeaponKinds[kind].Bonus
	return result
end

function Config.GetWeaponName(weapon)
	if not weapon then
		return Config.WeaponKinds.Starter.Name
	end
	local ore = Config.OreById[weapon.MainOre]
	local kindName = Config.WeaponKinds[weapon.Kind] and Config.WeaponKinds[weapon.Kind].Name or weapon.Kind
	if ore then
		return kindName .. " " .. ore.Of
	end
	return kindName
end

function Config.GetWeaponSellPrice(weapon)
	return math.max(1, math.floor(weapon.Mult * 5))
end

------------------------------------------------------------------------
-- ENTRAÎNEMENT (tapis dans le hub : reste dessus pour gagner de la puissance)
------------------------------------------------------------------------
Config.TrainingPads = {
	{ Name = "Tapis I",   Gain = 1,     ReqPower = 0,         ReqRebirths = 0, Color = Color3.fromRGB(200, 200, 200) },
	{ Name = "Tapis II",  Gain = 5,     ReqPower = 100,       ReqRebirths = 0, Color = Color3.fromRGB(90, 220, 110) },
	{ Name = "Tapis III", Gain = 25,    ReqPower = 1500,      ReqRebirths = 0, Color = Color3.fromRGB(70, 150, 255) },
	{ Name = "Tapis IV",  Gain = 120,   ReqPower = 20000,     ReqRebirths = 0, Color = Color3.fromRGB(185, 95, 255) },
	{ Name = "Tapis V",   Gain = 700,   ReqPower = 300000,    ReqRebirths = 1, Color = Color3.fromRGB(255, 190, 40) },
	{ Name = "Tapis VI",  Gain = 4000,  ReqPower = 5000000,   ReqRebirths = 3, Color = Color3.fromRGB(255, 70, 90) },
	{ Name = "Tapis VII", Gain = 25000, ReqPower = 100000000, ReqRebirths = 6, Color = Color3.fromRGB(40, 255, 230) },
}

------------------------------------------------------------------------
-- AMÉLIORATIONS (achetées avec les pièces)
------------------------------------------------------------------------
Config.BaseCapacity = 10
Config.Upgrades = {
	Capacity = { Name = "Capacité de minerais", Description = "+5 places de minerais", Max = 14, BaseCost = 100, Growth = 3 },
	Luck = { Name = "Chance", Description = "+15% de chances d'avoir des minerais rares", Max = 10, BaseCost = 300, Growth = 4 },
}
Config.UpgradeOrder = { "Capacity", "Luck" }

function Config.GetUpgradeCost(upgradeId, level)
	local upgrade = Config.Upgrades[upgradeId]
	return math.floor(upgrade.BaseCost * upgrade.Growth ^ level)
end

function Config.GetCapacity(level)
	return Config.BaseCapacity + 5 * level
end

------------------------------------------------------------------------
-- REBIRTH
-- Remet ta puissance et tes étapes à zéro, mais te donne un multiplicateur
-- permanent (entraînement ET dégâts). Tu gardes armes, minerais et pièces.
------------------------------------------------------------------------
Config.RebirthBaseCost = 10000
Config.RebirthCostGrowth = 6

function Config.GetRebirthCost(rebirths)
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths
end

function Config.GetRebirthMult(rebirths)
	return 1 + rebirths
end

function Config.GetDamage(power, weaponMult, rebirths)
	return power * weaponMult * Config.GetRebirthMult(rebirths)
end

------------------------------------------------------------------------
-- AFFICHAGE DES GRANDS NOMBRES (1500 -> 1.5K, 2000000 -> 2M ...)
------------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(text)
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

function Config.Format(number)
	number = tonumber(number) or 0
	if number ~= number then
		return "0"
	end
	local sign = ""
	if number < 0 then
		sign = "-"
		number = -number
	end
	if number == math.huge then
		return sign .. "∞"
	end
	local index = 1
	while number >= 999.5 and index < #SUFFIXES do
		number = number / 1000
		index = index + 1
	end
	if number >= 999.5 then
		return sign .. string.format("%.2e", number * 1000 ^ (index - 1))
	end
	local text
	if number >= 100 then
		text = string.format("%.0f", number)
	elseif number >= 10 then
		text = trimZeros(string.format("%.1f", number))
	else
		text = trimZeros(string.format("%.2f", number))
	end
	return sign .. text .. SUFFIXES[index]
end

return Config
