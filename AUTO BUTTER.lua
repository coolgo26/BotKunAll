-- =========================================
-- BUTTERFLY HUNT
-- =========================================

-- =========================================
-- TARGET BLOCK IDS
-- =========================================

local TARGET_BLOCK_IDS = {
    1685,
    1686,
    1687,
    1688
}

-- =========================================
-- SAVE ITEM IDS
-- =========================================

local SAVE_ITEM_IDS = {
    1689,1690,1691,1692,1693,1694,1695,1696,
    1697,1698,1699,1700,1701,1702,1703,1704,
    1705,1706,1707,1708,1709,1710,1711,1712,
    1713,1714,1715,1716,1717,1718,1719,1720,
    1721,1722,1723,1724,1725,1726,1727,1728,
    1729,1730,1731,1732,1733,1734,1735,1736,
    1737,1738,1739,1740,1741,1742,1743,1744,
    1745,1746,1747,1748,1749,1750,1751,1752
}

-- =========================================
-- STORAGE
-- =========================================

local STORAGE_WORLD = "RUPIAHXDOLLAR:MAHKOTA2"

local DROP_X = 25
local DROP_Y = 33

local DROP_TILE_LIMIT = 30

-- shared counter
local CURRENT_DROP_X = DROP_X
local CURRENT_DROP_Y = DROP_Y
local CURRENT_DROP_COUNT = 0

-- =========================================
-- DELAY
-- =========================================

local HIT_COUNT = 3
local HIT_DELAY = 180

local SCAN_DELAY = 3000
local WORLD_JOIN_DELAY = 5000

-- =========================================
-- WEBHOOK CONFIG (FONNTE WHATSAPP)
-- =========================================

local FONNTE_TOKEN     = "7YxS8vZqfy2TypBbEEWc"   -- Ganti dengan token dari dashboard Fonnte
local FONNTE_TARGET    = "6281224064255"        -- Ganti dengan nomor WA kamu (format: 628xxx)
local WEBHOOK_INTERVAL = 60000 -- 1 menit

-- =========================================
-- GLOBAL STATS
-- =========================================

local totalBlocksDestroyed = 0
local totalItemsSaved      = 0
local totalCycles          = 0
local activeWorkers        = 0

local itemStats = {}

math.randomseed(now_ms())

-- =========================================
-- RANDOM WORLD
-- =========================================

local function randomWorld()

    local chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    local name = ""

    for i = 1, 8 do

        local rand =
            math.random(#chars)

        name =
            name ..
            chars:sub(rand, rand)

    end

    name =
        name ..
        tostring(math.random(0, 9))

    return name

end

-- =========================================
-- CHECK SAVE ITEM
-- =========================================

local function isSaveItem(id)

    for _, saveId in ipairs(SAVE_ITEM_IDS) do

        if id == saveId then
            return true
        end

    end

    return false

end

-- =========================================
-- WEBHOOK
-- =========================================

local function sendWebhook()

    if FONNTE_TOKEN == "TOKEN_FONNTE_KAMU" then
        return
    end

    local RARITY_LIST = {
        {
            label = "⚪ Common",
            names = {
                "ButterflyDayEmpress", "ButterflyDayGreenNurse", "ButterflyDayOrangeTipper", "ButterflyDayBlackLightning",
                "ButterflyDayDiaperMoth", "ButterflyDayGardenMaid", "ButterflyDayPearlHeath", "ButterflyDaySirenHawkMoth",
                "ButterflyDaySmallTortoiseshell", "ButterflyDaySmallBrimstone", "ButterflyDayWhiteNun", "ButterflyDayBirchGlider",
                "ButterflyDayPaleLegate", "ButterflyDayStudMoth", "ButterflyDayBittyweeHawkMoth", "ButterflyDayCrushPearl",
                "ButterflyDayDirtyLemon", "ButterflyDayLemonMoth", "ButterflyDayWillowHerbHawkMoth", "ButterflyDayGreenDwarf",
                "ButterflyDayRedDotMoth"
            }
        },
        {
            label = "🟢 Uncommon",
            names = {
                "ButterflyDayBlueDwarf", "ButterflyDayPaperKite", "ButterflyDayTigerLongtail", "ButterflyDayRoseMoth",
                "ButterflyDayBlueEmperor", "ButterflyDayBlueEyedEmpress", "ButterflyDayCamouflageMoth", "ButterflyDayAdmiral",
                "ButterflyDayBlueBottom", "ButterflyDayBedstraw", "ButterflyDayShadow", "ButterflyDayBurpMoth", "ButterflyDayPinkDelight"
            }
        },
        {
            label = "🔵 Rare",
            names = {
                "ButterflyDayZebra", "ButterflyDayGreenNun", "ButterflyDayMonkeyBum", "ButterflyDayRedOrchae",
                "ButterflyDayPeacockMoth", "ButterflyDayRainbowChitoria", "ButterflyDayNeonStriper", "ButterflyDayLiliumHaste",
                "ButterflyDayPeacockBehemoth", "ButterflyDayBlueKnight", "ButterflyDayBloodMoth", "ButterflyDayYellowDwarf"
            }
        },
        {
            label = "🟣 Ultra Rare",
            names = {
                "ButterflyDayGrayGlassWing", "ButterflyDayPoisonWing", "ButterflyDayPinkCheeks", "ButterflyDayBlueNight",
                "ButterflyDayApollon", "ButterflyDayLavaMoth", "ButterflyDayBlueIvory", "ButterflyDaySkullHawkMoth", "ButterflyDayPurpleHaze"
            }
        },
        {
            label = "🟡 Legendary",
            names = {
                "ButterflyDayPinkHeart", "ButterflyDaySalamanderMoth", "ButterflyDayNightSky", "ButterflyDayPolillaGigante",
                "ButterflyDayLavaAglais", "ButterflyDayOrangeTigerTip", "ButterflyDayAzureFlapper",
                "ButterflyDayVioletColossus", "ButterflyDayEmeraldHawkMoth"
            }
        },
    }

    local BUTTERFLY_DISPLAY = {
        ["ButterflyDayEmpress"] = "Empress",
        ["ButterflyDayGreenNurse"] = "Green Nurse",
        ["ButterflyDayOrangeTipper"] = "Orange Tipper",
        ["ButterflyDayBlackLightning"] = "Black Lightning",
        ["ButterflyDayDiaperMoth"] = "Diaper Moth",
        ["ButterflyDayGardenMaid"] = "Garden Maid",
        ["ButterflyDayPearlHeath"] = "Pearl Heath",
        ["ButterflyDaySirenHawkMoth"] = "Siren Hawk Moth",
        ["ButterflyDaySmallTortoiseshell"] = "Small Tortoiseshell",
        ["ButterflyDaySmallBrimstone"] = "Small Brimstone",
        ["ButterflyDayWhiteNun"] = "White Nun",
        ["ButterflyDayBirchGlider"] = "Birch Glider",
        ["ButterflyDayPaleLegate"] = "Pale Legate",
        ["ButterflyDayStudMoth"] = "Stud Moth",
        ["ButterflyDayBittyweeHawkMoth"] = "Bittywee Hawk Moth",
        ["ButterflyDayCrushPearl"] = "Crush Pearl",
        ["ButterflyDayDirtyLemon"] = "Dirty Lemon",
        ["ButterflyDayLemonMoth"] = "Lemon Moth",
        ["ButterflyDayWillowHerbHawkMoth"] = "Willowherb Hawk Moth",
        ["ButterflyDayGreenDwarf"] = "Green Dwarf",
        ["ButterflyDayRedDotMoth"] = "Red Dot Moth",
        ["ButterflyDayBlueDwarf"] = "Blue Dwarf",
        ["ButterflyDayPaperKite"] = "Paper Kite",
        ["ButterflyDayTigerLongtail"] = "Tiger Longtail",
        ["ButterflyDayRoseMoth"] = "Rose Moth",
        ["ButterflyDayBlueEmperor"] = "Blue Emperor",
        ["ButterflyDayBlueEyedEmpress"] = "Blue-eyed Empress",
        ["ButterflyDayCamouflageMoth"] = "Camouflage Moth",
        ["ButterflyDayAdmiral"] = "Admiral",
        ["ButterflyDayBlueBottom"] = "Blue Bottom",
        ["ButterflyDayBedstraw"] = "Bedstraw",
        ["ButterflyDayShadow"] = "Shadow",
        ["ButterflyDayBurpMoth"] = "Burp Moth",
        ["ButterflyDayPinkDelight"] = "Pink Delight",
        ["ButterflyDayZebra"] = "Zebra",
        ["ButterflyDayGreenNun"] = "Green Nun",
        ["ButterflyDayMonkeyBum"] = "Monkey Bum",
        ["ButterflyDayRedOrchae"] = "Red Orchae",
        ["ButterflyDayPeacockMoth"] = "Peacock Moth",
        ["ButterflyDayRainbowChitoria"] = "Rainbow Chitoria",
        ["ButterflyDayNeonStriper"] = "Neon Striper",
        ["ButterflyDayLiliumHaste"] = "Lilium Haste",
        ["ButterflyDayPeacockBehemoth"] = "Peacock Behemoth",
        ["ButterflyDayBlueKnight"] = "Blue Knight",
        ["ButterflyDayBloodMoth"] = "Blood Moth",
        ["ButterflyDayYellowDwarf"] = "Yellow Dwarf",
        ["ButterflyDayGrayGlassWing"] = "Gray Glass Wing",
        ["ButterflyDayPoisonWing"] = "Poison Wing",
        ["ButterflyDayPinkCheeks"] = "Pink Cheeks",
        ["ButterflyDayBlueNight"] = "Blue Night",
        ["ButterflyDayApollon"] = "Apollon",
        ["ButterflyDayLavaMoth"] = "Lava Moth",
        ["ButterflyDayBlueIvory"] = "Blue Ivory",
        ["ButterflyDaySkullHawkMoth"] = "Skull Hawk Moth",
        ["ButterflyDayPurpleHaze"] = "Purple Haze",
        ["ButterflyDayPinkHeart"] = "Pink Heart",
        ["ButterflyDaySalamanderMoth"] = "Salamander Moth",
        ["ButterflyDayNightSky"] = "Night Sky",
        ["ButterflyDayPolillaGigante"] = "Polilla Gigante",
        ["ButterflyDayLavaAglais"] = "Lava Aglais",
        ["ButterflyDayOrangeTigerTip"] = "Orange Tiger Tip",
        ["ButterflyDayAzureFlapper"] = "Azure Flapper",
        ["ButterflyDayVioletColossus"] = "Violet Colossus",
        ["ButterflyDayEmeraldHawkMoth"] = "Emerald Hawk Moth",
    }

    -- Build pesan WhatsApp
    local msg = {}
    msg[#msg+1] = "🦋 *BUTTERFLY HUNT*"
    msg[#msg+1] = "━━━━━━━━━━━━━━━━━━━━"
    msg[#msg+1] = "🦋 Total: " .. tostring(totalBlocksDestroyed)
    msg[#msg+1] = "📦 Saved: " .. tostring(totalItemsSaved)
    msg[#msg+1] = "🤖 Workers: " .. tostring(activeWorkers)
    msg[#msg+1] = "━━━━━━━━━━━━━━━━━━━━"

    local BUTTERFLY_EMOJI = {
        ["ButterflyDayEmpress"] = "👑",
        ["ButterflyDayGreenNurse"] = "🌿",
        ["ButterflyDayOrangeTipper"] = "🍊",
        ["ButterflyDayBlackLightning"] = "⚡",
        ["ButterflyDayDiaperMoth"] = "🤍",
        ["ButterflyDayGardenMaid"] = "🌸",
        ["ButterflyDayPearlHeath"] = "🪨",
        ["ButterflyDaySirenHawkMoth"] = "🌊",
        ["ButterflyDaySmallTortoiseshell"] = "🐢",
        ["ButterflyDaySmallBrimstone"] = "🌕",
        ["ButterflyDayWhiteNun"] = "🕊",
        ["ButterflyDayBirchGlider"] = "🍃",
        ["ButterflyDayPaleLegate"] = "🌙",
        ["ButterflyDayStudMoth"] = "💎",
        ["ButterflyDayBittyweeHawkMoth"] = "🌾",
        ["ButterflyDayCrushPearl"] = "🫧",
        ["ButterflyDayDirtyLemon"] = "🍋",
        ["ButterflyDayLemonMoth"] = "🟡",
        ["ButterflyDayWillowHerbHawkMoth"] = "🌱",
        ["ButterflyDayGreenDwarf"] = "🍀",
        ["ButterflyDayRedDotMoth"] = "🔴",
        ["ButterflyDayBlueDwarf"] = "🔵",
        ["ButterflyDayPaperKite"] = "🪁",
        ["ButterflyDayTigerLongtail"] = "🐯",
        ["ButterflyDayRoseMoth"] = "🌹",
        ["ButterflyDayBlueEmperor"] = "💙",
        ["ButterflyDayBlueEyedEmpress"] = "👁",
        ["ButterflyDayCamouflageMoth"] = "🫏",
        ["ButterflyDayAdmiral"] = "⚓",
        ["ButterflyDayBlueBottom"] = "🫐",
        ["ButterflyDayBedstraw"] = "🌼",
        ["ButterflyDayShadow"] = "🌑",
        ["ButterflyDayBurpMoth"] = "💨",
        ["ButterflyDayPinkDelight"] = "🩷",
        ["ButterflyDayZebra"] = "🦓",
        ["ButterflyDayGreenNun"] = "☘",
        ["ButterflyDayMonkeyBum"] = "🐒",
        ["ButterflyDayRedOrchae"] = "🌺",
        ["ButterflyDayPeacockMoth"] = "🦚",
        ["ButterflyDayRainbowChitoria"] = "🌈",
        ["ButterflyDayNeonStriper"] = "⚡",
        ["ButterflyDayLiliumHaste"] = "🌷",
        ["ButterflyDayPeacockBehemoth"] = "🦚",
        ["ButterflyDayBlueKnight"] = "🛡",
        ["ButterflyDayBloodMoth"] = "🩸",
        ["ButterflyDayYellowDwarf"] = "☀",
        ["ButterflyDayGrayGlassWing"] = "🪟",
        ["ButterflyDayPoisonWing"] = "☠",
        ["ButterflyDayPinkCheeks"] = "🌸",
        ["ButterflyDayBlueNight"] = "🌃",
        ["ButterflyDayApollon"] = "🌟",
        ["ButterflyDayLavaMoth"] = "🌋",
        ["ButterflyDayBlueIvory"] = "🔷",
        ["ButterflyDaySkullHawkMoth"] = "💀",
        ["ButterflyDayPurpleHaze"] = "🟣",
        ["ButterflyDayPinkHeart"] = "💗",
        ["ButterflyDaySalamanderMoth"] = "🦎",
        ["ButterflyDayNightSky"] = "🌌",
        ["ButterflyDayPolillaGigante"] = "🦋",
        ["ButterflyDayLavaAglais"] = "🔥",
        ["ButterflyDayOrangeTigerTip"] = "🐅",
        ["ButterflyDayAzureFlapper"] = "💠",
        ["ButterflyDayVioletColossus"] = "💜",
        ["ButterflyDayEmeraldHawkMoth"] = "💚",
    }

    for _, rarity in ipairs(RARITY_LIST) do
        local items = {}
        for _, name in ipairs(rarity.names) do
            local amount = itemStats[name]
            if amount and amount > 0 then
                local display = BUTTERFLY_DISPLAY[name] or name
                local emoji = BUTTERFLY_EMOJI[name] or "🦋"
                items[#items+1] = emoji .. " " .. display .. ": " .. tostring(amount)
            end
        end

        if #items > 0 then
            msg[#msg+1] = ""
            msg[#msg+1] = "*" .. rarity.label .. "*"
            for _, line in ipairs(items) do
                msg[#msg+1] = line
            end
        end
    end

    msg[#msg+1] = ""
    msg[#msg+1] = "━━━━━━━━━━━━━━━━━━━━"

    local message = table.concat(msg, "\n")

    -- Kirim via Fonnte API
    pcall(function()
        http.post("https://api.fonnte.com/send", {
            headers = {
                ["Authorization"] = FONNTE_TOKEN
            },
            json = {
                target  = FONNTE_TARGET,
                message = message
            },
            timeout = 10000
        })
    end)

end

-- =========================================
-- WEBHOOK LOOP
-- =========================================

local function webhookTimer()

    while true do

        sleep(WEBHOOK_INTERVAL)

        sendWebhook()

    end

end

-- =========================================
-- SAVE ITEMS
-- =========================================

local function saveItems(bot)

    local saveList = {}

    for _, inv in ipairs(bot:get_inventory()) do

        if isSaveItem(inv.id)
        and inv.amount > 0 then

            table.insert(saveList, {
                id     = inv.id,
                amount = inv.amount,
                name   = inv.name
            })

        end

    end

    if #saveList <= 0 then
        return false
    end

    log("Warping to storage...")

    bot:warp(STORAGE_WORLD)

    sleep_ms(WORLD_JOIN_DELAY)

    if bot:state() ~= "InWorld" then

        log("Failed enter storage")

        return false

    end

    -- =========================================
    -- CHANGE DROP TILE
    -- =========================================

    if CURRENT_DROP_COUNT >= DROP_TILE_LIMIT then

        CURRENT_DROP_COUNT = 0

        CURRENT_DROP_X =
            CURRENT_DROP_X - 1

        log(
            "Moving drop tile to:",
            CURRENT_DROP_X,
            CURRENT_DROP_Y
        )

    end

    pcall(function()

        bot:find_path(
            CURRENT_DROP_X,
            CURRENT_DROP_Y
        )

    end)

    sleep_ms(1000)

    -- =========================================
    -- DROP ITEMS
    -- =========================================

    for _, item in ipairs(saveList) do

        log(
            "Dropping",
            item.id,
            "x"..item.amount
        )

        local dropOk, dropErr =
            pcall(function()

                bot:drop(
                    item.id,
                    item.amount
                )

            end)

        if dropOk then

            -- update stats hanya kalau drop berhasil
            totalItemsSaved =
                totalItemsSaved + item.amount

            local itemKey =
                item.name or ("Item " .. item.id)

            if not itemStats[itemKey] then
                itemStats[itemKey] = 0
            end

            itemStats[itemKey] =
                itemStats[itemKey] + item.amount

        else

            log("Drop failed:", dropErr)

        end

        CURRENT_DROP_COUNT =
            CURRENT_DROP_COUNT + 1

        sleep_ms(300)

    end

    log(
        "Drop Count:",
        CURRENT_DROP_COUNT
    )

    log("Items saved")

    -- leave storage
    bot:warp("EXIT")

    sleep_ms(3000)

    return true

end

-- =========================================
-- BOT LOOP
-- =========================================

local function runBot(bot)

activeWorkers = activeWorkers + 1

while true do

    -- =========================================
    -- CHECK INVENTORY
    -- =========================================

    local hasSaveItem = false

    for _, inv in ipairs(bot:get_inventory()) do

        if isSaveItem(inv.id)
        and inv.amount > 0 then

            hasSaveItem = true
            break

        end

    end

    -- =========================================
    -- SAVE IF HAVE ITEM
    -- =========================================

    if hasSaveItem then

        saveItems(bot)

        sleep_ms(2000)

    end

    -- =========================================
    -- RANDOM WORLD
    -- =========================================

    local WORLD = randomWorld()

    log("Warping to:", WORLD)

    bot:warp(WORLD)

    sleep_ms(WORLD_JOIN_DELAY)

    while true do

        -- =========================================
        -- AUTO RECONNECT
        -- =========================================

        if bot:state() ~= "InWorld" then

            log("Reconnecting...")

            bot:connect()

            sleep_ms(5000)

            bot:warp(WORLD)

            sleep_ms(WORLD_JOIN_DELAY)

        end

        local targetPos = nil
        local targetId  = nil

        -- =========================================
        -- SCAN BLOCK
        -- =========================================

        for _, blockId in ipairs(TARGET_BLOCK_IDS) do

            local tiles =
                bot:findTiles(blockId)

            if #tiles > 0 then

                targetPos = tiles[1]
                targetId  = blockId

                break

            end

        end

        -- =========================================
        -- FOUND BLOCK
        -- =========================================

        if targetPos then

            local x = targetPos.x
            local y = targetPos.y

            log(
                "Found block",
                targetId,
                "at",
                x,
                y
            )

            local positions = {

                {x, y + 1},
                {x - 1, y},
                {x + 1, y},
                {x, y - 1}

            }

            local success = false

            for _, pos in ipairs(positions) do

                local px = pos[1]
                local py = pos[2]

                log(
                    "Trying:",
                    px,
                    py
                )

                pcall(function()

                    bot:find_path(px, py)

                end)

                sleep_ms(1000)

                -- =========================================
                -- BREAK
                -- =========================================

                for i = 1, HIT_COUNT do

                    bot:hit(x, y)

                    sleep_ms(HIT_DELAY)

                end

                sleep_ms(700)

                -- =========================================
                -- CHECK BLOCK
                -- =========================================

                local stillExists = false

                local tiles =
                    bot:findTiles(targetId)

                for _, t in ipairs(tiles) do

                    if t.x == x
                    and t.y == y then

                        stillExists = true
                        break

                    end

                end

                if not stillExists then

                    success = true

                    totalBlocksDestroyed =
                        totalBlocksDestroyed + 1

                    log("Block destroyed")

                    break

                end

            end

            -- =========================================
            -- FAILED
            -- =========================================

            if not success then

                log("Cannot reach block")

                break

            end

            -- =========================================
            -- LEAVE WORLD
            -- =========================================

            log("Leaving world...")

            bot:warp("EXIT")

            sleep_ms(3000)

            -- =========================================
            -- DISCONNECT
            -- =========================================

            log("Disconnecting...")

            bot:disconnect()

            sleep_ms(4000)

            -- =========================================
            -- RECONNECT
            -- =========================================

            log("Reconnecting...")

            bot:connect()

            sleep_ms(7000)

            totalCycles = totalCycles + 1

            -- lanjut random world baru
            break

        else

            log("Waiting block spawn...")

        end

        sleep_ms(SCAN_DELAY)

    end

end

end

-- =========================================
-- GLOBAL RUN
-- =========================================

-- jalanin webhook timer di thread sendiri
runThread(function()
    webhookTimer()
end)

for index, slot in ipairs(getBots()) do

    local bot = getBot(slot)

    if bot then

        runThread(function()

            -- delay 2 detik per bot
            sleep_ms((index - 1) * 2000)

            runBot(bot)

        end)

    end

end

while true do
    sleep_ms(60000)
end