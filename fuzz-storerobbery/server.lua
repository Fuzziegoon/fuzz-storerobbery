local QBCore = exports['qb-core']:GetCoreObject()
local hookid
local StringCharset = {}
local NumberCharset = {}

local webhook
for i = 48, 57 do NumberCharset[#NumberCharset + 1] = string.char(i) end
for i = 65, 90 do StringCharset[#StringCharset + 1] = string.char(i) end
for i = 97, 122 do StringCharset[#StringCharset + 1] = string.char(i) end

local function SetupStore()
    TriggerClientEvent("fuzz-storerobbery:client:setConfigs", -1, Config.Store)
end

local function SendLog(title, content, tageveryone)
    if not webhook then
        warn("No webhook link for " .. GetCurrentResourceName())
        return
    end
    local embedData = {
        username = "Store Robbery",
        embeds = {
            {
                title = title,
                color = 16711680,
                footer = {
                    text = os.date('%c')
                },
                description = content,
                author = {
                    name = "Store Robbery",
                    icon_url =
                    "https://media.discordapp.net/attachments/1139589833459761175/1144841078223159326/logo.png"
                }
            }
        }
    }
    if tageveryone then
        embedData.content = "@everyone"
    end
    PerformHttpRequest(webhook, function() end, 'POST', json.encode(embedData), { ['Content-Type'] = 'application/json' })
end

local function RandomStr(length)
    if length <= 0 then return '' end
    return RandomStr(length - 1) .. StringCharset[math.random(1, #StringCharset)]
end

local function RandomInt(length)
    if length <= 0 then return '' end
    return RandomInt(length - 1) .. NumberCharset[math.random(1, #NumberCharset)]
end

local function ResetStore(id)
    local cfg = Config.Store[id]
    if not cfg then return end
    if not cfg.cooldown then return end
    cfg.cooldown = false
    cfg.alerted = false
    cfg.combination = nil
    for _, v in pairs(cfg.registar) do
        v.robbed = false
        v.isusing = false
    end
    for _, v in pairs(cfg.search) do
        v.searched = false
        if v.iscomputer then
            v.founded = false
        end
    end
    if cfg.safe and cfg.safe.opened then
        cfg.safe.opened = false
        cfg.safe.id = nil
    end
end

local function Cooldown(storeid)
    local cfg = Config.Store[storeid]
    if not cfg then
        warn("No config found for " .. storeid)
        return
    end
    cfg.cooldown = true
    SetTimeout(1000 * 60 * 60, function()
        ResetStore(storeid)
    end)
    SendLog("Robbery end", ("Robbery with storeid: %s has ended"):format(storeid))
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, cfg)
end

local function GenerateSafeItems()
    local totalChance = 0
    for item, properties in pairs(Config.Prize.safe) do
        totalChance = totalChance + properties.chance
    end

    local randomNumber = math.random(1, totalChance)
    local currentChance = 0

    local selectedItems = {}

    for item, properties in pairs(Config.Prize.safe) do
        currentChance = currentChance + properties.chance
        if randomNumber <= currentChance then
            local itemCount = math.random(properties.min, properties.max)
            selectedItems[#selectedItems + 1] = {
                [1] = item,
                [2] = itemCount
            }
        end
    end
    return selectedItems
end

local function IncludeInventoryID(id)
    for _, v in ipairs(Config.Store) do
        if v.safe then
            if v.safe.id == id then
                return true
            end
        end
    end
    return false
end

local function GenerateCombination()
    return RandomInt(4)
end

RegisterNetEvent("fuzz-storerobbery:server:getConfig", function()
    local src = source
    TriggerClientEvent("fuzz-storerobbery:client:setConfigs", src, Config.Store)
end)

RegisterNetEvent("fuzz-storerobbery:server:setUse", function(storeid, regid, status)
    local storeConfig = Config.Store[storeid]
    if not storeConfig then return end
    local regConfig = storeConfig.registar[regid]
    if not regConfig then return end
    regConfig.isusing = status
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, storeConfig)
end)

RegisterNetEvent("fuzz-storerobbery:server:setHackUse", function(storeid, status)
    local cfg = Config.Store[storeid]
    if not cfg then return end
    cfg.hack.isusing = status
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, cfg)
end)

RegisterNetEvent("fuzz-storerobbery:server:registerAlert", function(storeid, status)
    local src = source
    local cfg = Config.Store[storeid]
    if not cfg then return end
    if cfg.alerted == status then return end
    cfg.alerted = status
    SetTimeout(1000 * 60 * 60, function()
        cfg = Config.Store[storeid]
        if not cfg then return end
        if not cfg.cooldown then
            ResetStore(storeid)
        end
    end)
    SendLog("Robbery Started", ("%s has started a robbery, storeid: %s"):format(GetPlayerName(src), storeid))
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, cfg)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= cache.resource then return end
    SetupStore()
    if Config.Inventory == "ox" then
        hookid = exports.ox_inventory:registerHook("swapItems", function(payload)
            if payload.fromType == "player" and IncludeInventoryID(payload.toInventory) then
                return false
            else
                return true
            end
        end, {
            inventoryFilter = {
                '^temp-[%w]+',
            }
        })
    end
end)

RegisterNetEvent("ran-houserobbery:server:setHackedState", function(storeid, status)
    local src = source
    local cfg = Config.Store[storeid]
    if not cfg then
        warn("No config found for " .. storeid)
        return
    end
    if cfg.hack.hacked == status then return end
    cfg.hack.hacked = status
    local delayCount = math.random(90, 120)
    cfg.hack.delayCount = delayCount
    TriggerClientEvent("QBCore:Notify", src, "The alarm will be delayed for " .. math.floor(delayCount) .. " seconds")
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, cfg)
end)

lib.callback.register("ran-houserobbery:server:getPrize", function(source, prize, storeid, regid)
    local config = Config.Store[storeid]
    if not config then return end
    local regConfig = config.registar[regid]
    if not regConfig then return end
    if regConfig.robbed then return end
    regConfig.robbed = true
    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then return end
    local itemExist
    if Config.Inventory == "qb" then
        itemExist = QBCore.Shared.Items[Config.Prize.item]
    elseif Config.Inventory == "ox" then
        itemExist = exports.ox_inventory:Items(Config.Prize.item)
    end
    if Config.Prize.item and itemExist then
        xPlayer.Functions.AddItem(Config.Prize.item, prize, nil, nil)
    else
        xPlayer.Functions.AddMoney('cash', prize, 'rob')
    end
    SendLog("Get Prize",
        ("%s are robbing a register and got %s %s"):format(GetPlayerName(source), prize,
            itemExist and itemExist.label or "cash"), prize >= Config.Prize.max)
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, config)
    return true
end)

lib.callback.register("fuzz-storerobbery:server:combination", function(source, storeid, sid, status)
    local cfg = Config.Store[storeid]
    if not cfg then return end
    local scfg = cfg.search[sid]
    if not scfg then return end
    if status then
        local combination = GenerateCombination()
        cfg.combination = tonumber(combination)
        if scfg.iscomputer then
            scfg.founded = true
        else
            local xPlayer = QBCore.Functions.GetPlayer(source)
            if not xPlayer then return end
            xPlayer.Functions.AddItem('stickynote', 1, nil, {
                combination = combination
            })
        end
    end
    scfg.searched = true
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, cfg)
    return true
end)


lib.callback.register("fuzz-storerobbery:server:setSafeState", function(_, storeid)
    local config = Config.Store[storeid]
    if not config then return end
    if config.safe.opened and config.safe.id then return end
    config.safe.isopened = true
    if Config.Inventory == "qb" then
        local stashid = RandomStr(2) .. RandomInt(2) .. RandomStr(2)
        local items = {}
        local itemList = GenerateSafeItems()
        for _, v in pairs(itemList) do
            ---@type string
            local itemname = v[1]
            ---@type number
            local itemCount = v[2]
            local itemInfo = QBCore.Shared.Items[itemname]
            if itemInfo then
                items[#items + 1] = {
                    name = itemInfo.name,
                    amount = tonumber(itemCount),
                    info = {},
                    label = itemInfo.label,
                    description = itemInfo.description ~= nil and itemInfo.description or "",
                    weight = itemInfo.weight,
                    type = itemInfo.type,
                    unique = itemInfo.unique,
                    useable = itemInfo.useable,
                    image = itemInfo.image,
                    slot = #items + 1
                }
            else
                warn("Can't find iteminfo for " .. itemname)
            end
        end
        MySQL.insert.await(
            "INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items", {
                ['stash'] = stashid,
                ['items'] = json.encode(items)
            })
        config.safe.id = stashid
    elseif Config.Inventory == "ox" then
        config.safe.id = exports.ox_inventory:CreateTemporaryStash({
            label = "Safe",
            slots = 10,
            maxWeight = 30000,
            items = GenerateSafeItems()
        })
    end
    TriggerClientEvent("fuzz-storerobbery:client:setStoreConfig", -1, storeid, config)
    return true
end)

lib.addCommand("reset-store", {
    help = "Reset Store (Store Robbery)"
}, function(source)
    if source == 0 or not source then return end
    local xPlayer = QBCore.Functions.GetPlayer(source)
    if not xPlayer then return end
    local job = xPlayer.PlayerData.job
    if not job then return end
    if job.name ~= "police" then return end
    local sc = lib.callback.await("fuzz-storerobbery:client:resetStore", source)
    if sc then
        Cooldown(sc)
    end
end)

lib.addCommand("get-store-config", {
    help = "Get Store Config (ADMIN ONLY)",
    restricted = 'group.admin'
}, function(source)
    ---@type number | false
    local cb = lib.callback.await("fuzz-storerobbery:client:openConfigContext", source)
    if cb then
        local cfg = Config.Store[cb]
        if not cfg then return end
        local ped = GetPlayerPed(source)
        if not ped then return end
        local coords = cfg.coords
        SetEntityCoords(ped, coords.x, coords.y, coords.z - 1.0, true, false, false, false)
    end
end)

QBCore.Functions.CreateUseableItem('stickynote', function(source, item)
    if item.info then
        TriggerClientEvent("QBCore:Notify", source, "Combination: " .. item.info.combination)
    elseif item.metadata then
        TriggerClientEvent("QBCore:Notify", source, "Combination: " .. item.metadata.combination)
    end
end)




AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if hookid then
            exports.ox_inventory:removeHooks(hookid)
        end
    end
end)
