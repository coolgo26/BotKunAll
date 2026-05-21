--[[
  AUTO KUPU ZENIT v3.0
  Rewrite 100% berdasarkan Zenith v0.95 Lua API docs.
]]

-- ============================================================
-- CONFIG
-- ============================================================

local CONFIG = {
    BUTTERFLY_IDS = {
        1689,1690,1691,1692,1693,1694,1695,1696,1697,1698,
        1699,1700,1701,1702,1703,1704,1705,1706,1707,1708,
        1709,1710,1711,1712,1713,1714,1715,1716,1717,1718,
        1719,1720,1721,1722,1723,1724,1725,1726,1727,1728,
        1729,1730,1731,1732,1733,1734,1735,1736,1737,1738,
        1739,1740,1741,1742,1743,1744,1745,1746,1747,1748,
        1749,1750,1751,1752,
    },

    HIT_COUNT       = 5,
    HIT_DELAY       = 200,
    SCAN_INTERVAL   = 2000,
    MAX_WAIT_LOOPS  = 150,
    WARP_DELAY      = 3000,
    RECONNECT_DELAY = 5000,
    RECONNECT_MAX   = 5,

    INV_THRESHOLD   = 30,

    STORAGE_WORLD   = "STORAGE:ID",
    DROP_STEP       = 7,

    WEBHOOK_URL     = "",
    DEBUG           = true,
}

-- ============================================================
-- LOOKUPS
-- ============================================================

local BUTTER_LOOKUP = {}
for _, id in ipairs(CONFIG.BUTTERFLY_IDS) do BUTTER_LOOKUP[id] = true end

local NIGHT_SET = {
    [1729]=true,[1730]=true,[1731]=true,[1732]=true,[1733]=true,[1734]=true,
    [1735]=true,[1736]=true,[1737]=true,[1738]=true,[1739]=true,[1740]=true,
    [1741]=true,[1742]=true,[1743]=true,[1744]=true,[1745]=true,[1746]=true,
    [1747]=true,[1748]=true,[1749]=true,[1750]=true,[1751]=true,[1752]=true,
}

local NAMES = {
    [1689]="Zebra Longtail",[1690]="Tiger Longtail",[1691]="Empress",[1692]="Orange Tipper",
    [1693]="Pink Heart",[1694]="Black Lightning",[1695]="Monkey Bum",[1696]="Garden Maid",
    [1697]="Night Sky",[1698]="Blue Emperor",[1699]="Gray Glass Wing",[1700]="Red Orchae",
    [1701]="Rainbow Chitoria",[1702]="Pearl Heath",[1703]="Small Tortoiseshell",[1704]="Small Brimstone",
    [1705]="Blue-eyed Empress",[1706]="Admiral",[1707]="Birch Glider",[1708]="Blue Bottom",
    [1709]="Pink Cheeks",[1710]="Neon Striper",[1711]="Shadow Longtail",[1712]="Orange Tiger Tip",
    [1713]="Apollon",[1714]="Blue Ivory",[1715]="Pale Legate",[1716]="Lilium Haste",
    [1717]="Lava Aglais",[1718]="Purple Haze",[1719]="Crush Pearl",[1720]="Dirty Lemon",
    [1721]="Azure Flapper",[1722]="Violet Colossus",[1723]="Pink Delight",[1724]="Blue Knight",
    [1725]="Green Dwarf",[1726]="Yellow Dwarf",[1727]="Blue Dwarf",[1728]="Paper Kite",
    [1729]="Diaper Moth",[1730]="Rose Moth",[1731]="Poison Wing",[1732]="Green Nurse",
    [1733]="Salamander Moth",[1734]="Siren Hawk Moth",[1735]="Polilla Gigante",[1736]="Camouflage Moth",
    [1737]="White Nun",[1738]="Green Nun",[1739]="Bedstraw Hawk Moth",[1740]="Stud Moth",
    [1741]="Bittywee Hawk Moth",[1742]="Peacock Moth",[1743]="Blue Night",[1744]="Lemon Moth",
    [1745]="Skull Hawk Moth",[1746]="Willowherb Hawk Moth",[1747]="Peacock Behemoth",[1748]="Red Dot Moth",
    [1749]="Burp Moth",[1750]="Blood Moth",[1751]="Lava Moth",[1752]="Emerald Hawk Moth",
}

-- ============================================================
-- CLIENT (Zenith API: getClient())
-- ============================================================

local client = getClient()

-- ============================================================
-- STATE
-- ============================================================

local total_caught = 0
local total_cycles = 0
local rarity_counts = { Common=0, Uncommon=0, Rare=0, Epic=0, Legendary=0 }
local day_night = { day=0, night=0 }

-- ============================================================
-- DEBUG / LOG (Zenith API: print / client:console())
-- ============================================================

local function dbg(msg)
    if CONFIG.DEBUG then print("[DBG] " .. tostring(msg)) end
end

local function info(msg) print("[INFO] " .. tostring(msg)) end
local function warn(msg) print("[WARN] " .. tostring(msg)) end

-- ============================================================
-- HELPERS
-- ============================================================

local function getRarity(id)
    if id >= 1691 and id <= 1710 then return "Common", "⚪"
    elseif id >= 1711 and id <= 1730 then return "Uncommon", "🟢"
    elseif id >= 1731 and id <= 1740 then return "Rare", "🟡"
    elseif id >= 1741 and id <= 1748 then return "Epic", "🟣"
    elseif id >= 1749 and id <= 1752 then return "Legendary", "🔴"
    else return "Common", "⚪" end
end

local function getDayNight(id)
    if NIGHT_SET[id] then return "night", "🌙" end
    return "day", "☀️"
end

local function getName(id)
    -- Zenith API: getInfo(blockType)
    local ok, info_data = pcall(getInfo, id)
    if ok and info_data and info_data.name then return info_data.name end
    return NAMES[id] or ("Butterfly #" .. id)
end

local function genRandomWorld()
    -- Format: XXX_XXX (3 huruf + underscore + 3 huruf, total 7 char)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local a, b = "", ""
    for _ = 1, 3 do
        local idx = math.random(1, #chars)
        a = a .. chars:sub(idx, idx)
    end
    for _ = 1, 3 do
        local idx = math.random(1, #chars)
        b = b .. chars:sub(idx, idx)
    end
    return a .. "_" .. b
end

-- Zenith API: client:navigation() returns "#menu" if not in world
local function isInWorld()
    local nav = client:navigation()
    return nav ~= nil and nav ~= "#menu" and nav ~= ""
end

-- Zenith API: client:connected()
local function isConnected()
    return client:connected()
end

-- ============================================================
-- WEBHOOK
-- ============================================================

local function sendWebhook(msg)
    if CONFIG.WEBHOOK_URL == "" then return end
    pcall(function()
        if http and http.post then
            http.post(CONFIG.WEBHOOK_URL, { json = { content = msg } })
        end
    end)
end

local function notifCatch(butterfly_id, world_name)
    local name = getName(butterfly_id)
    local rar, rem = getRarity(butterfly_id)
    rarity_counts[rar] = (rarity_counts[rar] or 0) + 1
    local tt, tem = getDayNight(butterfly_id)
    day_night[tt] = (day_night[tt] or 0) + 1

    sendWebhook(table.concat({
        "```",
        "🦋 BUTTERFLY CAUGHT",
        "──────────────────────",
        "🤖 Bot:       " .. tostring(client.username or client.id or "?"),
        "🦋 Butterfly: " .. name,
        "   Rarity:    " .. rem .. " " .. rar,
        "   Type:      " .. tem .. " " .. tt,
        "🆔 Item ID:   " .. butterfly_id,
        "🌍 World:     " .. (world_name or "?"),
        "──────────────────────",
        "📊 Total: " .. total_caught,
        "☀️" .. day_night.day .. " 🌙" .. day_night.night ..
        " | ⚪" .. rarity_counts.Common .. " 🟢" .. rarity_counts.Uncommon ..
        " 🟡" .. rarity_counts.Rare .. " 🟣" .. rarity_counts.Epic ..
        " 🔴" .. rarity_counts.Legendary,
        "💎 Gems: " .. tostring(client.gems or 0) .. " | Lv: " .. tostring(client.level or 0),
        "```",
    }, "\n"))
end

local function notifStored(items)
    local lines = {}
    local total = 0
    for _, it in ipairs(items) do
        local _, em = getRarity(it.id)
        lines[#lines + 1] = string.format("  %s %s x%d", em, getName(it.id), it.amount)
        total = total + it.amount
    end

    sendWebhook(table.concat({
        "```",
        "📥 BUTTERFLY STORED",
        "──────────────────────",
        "🤖 " .. tostring(client.username or client.id or "?") .. " | 📦 " .. total .. " items",
        table.concat(lines, "\n"),
        "──────────────────────",
        "🦋 Total Catch: " .. total_caught,
        "💎 Gems: " .. tostring(client.gems or 0),
        "```",
    }, "\n"))
end

-- ============================================================
-- BOT FUNCTIONS (sesuai Zenith API docs)
-- ============================================================

local function ensureConnected()
    if isConnected() then return true end

    dbg("Disconnected, reconnecting...")
    for attempt = 1, CONFIG.RECONNECT_MAX do
        sleep(CONFIG.RECONNECT_DELAY)
        client:connect()
        sleep(CONFIG.RECONNECT_DELAY)

        local waited = 0
        while not client:connected() and waited < 20000 do
            sleep(1000)
            waited = waited + 1000
        end

        if client:connected() then
            dbg("Reconnected!")
            sleep(2000)
            return true
        end
    end
    return false
end

-- Zenith API: client:findPath(point), client:pathfinding(), client:clearPath()
local function pathTo(point)
    if not ensureConnected() then return false end

    local me = client:point()
    if not me then return false end

    if me:equals(point) then return true end

    local succeeded = client:findPath(point)
    if not succeeded then return false end

    -- Tunggu pathfinding selesai (max 10 detik)
    local waited = 0
    while client:pathfinding() and waited < 10000 do
        sleep(100)
        waited = waited + 100
    end

    -- Jika masih pathfinding setelah timeout, clear
    if client:pathfinding() then
        client:clearPath()
        return false
    end

    return true
end

-- ============================================================
-- SCAN BUTTERFLY
-- Zenith API: world:tiles() returns (tileIndex, tile) pairs
-- tile.foreground, tile.point
-- ============================================================

local function scanButterflies()
    local out = {}

    -- Zenith API: client:world()
    local world = client:world()
    if not world then
        dbg("scan: world() returned nil")
        return out
    end

    -- world.tiles adalah TABLE (bukan method) di Zenith v0.95
    local tiles = world.tiles
    if not tiles then
        dbg("scan: world.tiles is nil")
        return out
    end

    for tileIndex, tile in pairs(tiles) do
        if tile and tile.foreground and BUTTER_LOOKUP[tile.foreground] then
            if tile.point then
                out[#out + 1] = {
                    x = tile.point.x,
                    y = tile.point.y,
                    id = tile.foreground
                }
            end
        end
    end

    -- Sort nearest ke posisi bot
    if #out > 0 then
        local me = client:point()
        if me then
            table.sort(out, function(a, b)
                return (math.abs(a.x - me.x) + math.abs(a.y - me.y))
                     < (math.abs(b.x - me.x) + math.abs(b.y - me.y))
            end)
        end
    end

    return out
end

-- Cek apakah butterfly masih ada di tile
local function butterflyExists(x, y, id)
    local world = client:world()
    if not world then return false end

    local tile = world:tile(Vector2i.new(x, y))
    if not tile then return false end

    return tile.foreground == id
end

-- Hitung butterfly di inventory
-- Zenith API: client:inventory(), inventory.items, item.id, item.amount
local function getButterflyCount()
    local inventory = client:inventory()
    if not inventory or not inventory.items then return 0 end

    local count = 0
    for invKey, item in pairs(inventory.items) do
        if BUTTER_LOOKUP[item.id] then
            count = count + (item.amount or 0)
        end
    end
    return count
end

-- Hit butterfly
-- Zenith API: client:hit(Vector2i)
local function hitButterfly(x, y)
    local point = Vector2i.new(x, y)
    for _ = 1, CONFIG.HIT_COUNT do
        client:hit(point)
        sleep(CONFIG.HIT_DELAY)
    end
    sleep(500)
end

-- ============================================================
-- STORAGE
-- ============================================================

local function doStorage()
    info("Storage: warp ke " .. CONFIG.STORAGE_WORLD)

    if isInWorld() then
        client:leave()
        sleep(1500)
    end

    client:warp(CONFIG.STORAGE_WORLD)
    sleep(CONFIG.WARP_DELAY)

    if not isInWorld() then
        warn("Gagal masuk storage")
        return false
    end

    sleep(1000)

    -- Jalan beberapa step kanan
    for _ = 1, CONFIG.DROP_STEP do
        client:movePoint(Vector2i.new(1, 0))
        sleep(300)
    end
    sleep(500)

    -- Drop semua butterfly
    -- Zenith API: client:drop(blockType, inventoryType, amount)
    local inventory = client:inventory()
    if not inventory or not inventory.items then return false end

    local dropped = {}
    for invKey, item in pairs(inventory.items) do
        if BUTTER_LOOKUP[item.id] and item.amount > 0 then
            local before = item.amount
            client:drop(item.id, item.type, item.amount)
            sleep(400)
            dropped[#dropped + 1] = { id = item.id, amount = before }
        end
    end

    if #dropped > 0 then
        notifStored(dropped)
        info("Dropped " .. #dropped .. " types of butterfly")
    end

    client:leave()
    sleep(1500)
    return true
end

-- ============================================================
-- MAIN LOOP
-- ============================================================

local function mainLoop()
    info("AUTO KUPU ZENIT v3.0 started")
    info("Client: " .. tostring(client.username or client.id or "?"))

    -- Aktifkan preferences
    -- Zenith API: client:preferences()
    local prefs = client:preferences()
    if prefs then
        prefs.reconnect = true
        prefs.collect = true
    end

    if not ensureConnected() then
        warn("Tidak bisa connect, abort")
        return
    end

    sendWebhook("🚀 **Auto Kupu Started** — " .. tostring(client.username or client.id or "?"))

    while true do
        -- Cek inventory full → storage
        local count = getButterflyCount()
        dbg("Butterfly in inv: " .. count)
        if count >= CONFIG.INV_THRESHOLD then
            info("Inventory penuh (" .. count .. "), storage")
            doStorage()
            sleep(2000)
        end

        -- Warp ke world random (retry sampai berhasil masuk)
        local worldName = ""
        local warpSuccess = false
        local warpAttempts = 0
        local MAX_WARP_ATTEMPTS = 20

        while not warpSuccess and warpAttempts < MAX_WARP_ATTEMPTS do
            worldName = genRandomWorld()
            warpAttempts = warpAttempts + 1

            if isInWorld() then
                client:leave()
                sleep(1500)
            end

            dbg("Warp attempt #" .. warpAttempts .. " → " .. worldName)
            client:warp(worldName)
            sleep(CONFIG.WARP_DELAY)

            if isInWorld() then
                warpSuccess = true
                info("Masuk world: " .. worldName)
            else
                dbg("Gagal masuk " .. worldName .. " (full/reject), retry...")
                sleep(500)
            end
        end

        if not warpSuccess then
            warn("Gagal masuk world setelah " .. MAX_WARP_ATTEMPTS .. " attempts")
            sleep(3000)
        else
            -- Tunggu butterfly spawn (max ~5 menit)
            dbg("Scanning butterfly di " .. worldName)
            local found = {}
            local loops = 0

            while loops < CONFIG.MAX_WAIT_LOOPS do
                if not isInWorld() then break end

                found = scanButterflies()
                if #found > 0 then
                    info("🦋 " .. #found .. " butterfly found di " .. worldName)
                    break
                end

                if loops % 15 == 0 then
                    dbg("Wait #" .. loops .. ", no butterfly yet")
                end

                sleep(CONFIG.SCAN_INTERVAL)
                loops = loops + 1
            end

            -- Catch semua butterfly
            for _, t in ipairs(found) do
                if not isInWorld() then break end

                dbg("Pathfind ke " .. t.x .. "," .. t.y .. " (id " .. t.id .. ")")
                local target = Vector2i.new(t.x, t.y)

                if pathTo(target) then
                    sleep(300)

                    if butterflyExists(t.x, t.y, t.id) then
                        local before = getButterflyCount()
                        hitButterfly(t.x, t.y)
                        sleep(500)

                        if getButterflyCount() > before then
                            total_caught = total_caught + 1
                            info("✅ Caught " .. getName(t.id) .. " (total: " .. total_caught .. ")")
                            notifCatch(t.id, worldName)
                        else
                            dbg("Hit tapi tidak masuk inv")
                        end
                    else
                        dbg("Butterfly sudah hilang")
                    end
                else
                    dbg("Pathfind gagal ke " .. t.x .. "," .. t.y)
                end
            end

            -- Leave world
            if isInWorld() then
                client:leave()
                sleep(1500)
            end
        end

        total_cycles = total_cycles + 1
    end
end

-- ============================================================
-- START (Zenith API: runThread)
-- ============================================================

runThread(function()
    local ok, err = pcall(mainLoop)
    if not ok then
        warn("mainLoop crash: " .. tostring(err))
        sendWebhook("❌ **Script crashed**: " .. tostring(err))
    end
end)

print("[START] AUTO KUPU ZENIT v3.0 thread spawned")
