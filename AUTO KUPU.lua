-- ============================================================
-- AUTO KUPU — Simple butterfly catcher with webhook
-- ============================================================

local BUTTERFLY_IDS = {
    1686, 1691, 1692, 1693, 1694, 1695, 1696, 1697, 1698, 1699, 1700,
    1701, 1702, 1703, 1704, 1705, 1706, 1707, 1708, 1709, 1710,
    1711, 1712, 1713, 1714, 1715, 1716, 1717, 1718, 1719, 1720,
    1721, 1722, 1723, 1724, 1725, 1726, 1727, 1728, 1729, 1730,
    1731, 1732, 1733, 1734, 1735, 1736, 1737, 1738, 1739, 1740,
    1741, 1742, 1743, 1744, 1745, 1746, 1747, 1748, 1749, 1750,
    1751, 1752
}

-- ================== WEBHOOK CONFIG ==================
local WEBHOOK_URL = "https://discord.com/api/webhooks/1505218468600086723/u4mKyQvkvrM8-FRfc18Es-5-3U-JrPxSYIYxDNNP9BJUJiVuDGWZxH6tPufctHluNloC"  -- isi dengan Discord webhook URL
local WEBHOOK_COOLDOWN = 2000

-- Stats
local total_caught = 0
local last_webhook_ms = 0
local script_start = now_ms()

-- Night butterfly IDs
local NIGHT_SET = {
    [1729]=true,[1730]=true,[1731]=true,[1732]=true,[1733]=true,[1734]=true,
    [1735]=true,[1736]=true,[1737]=true,[1738]=true,[1739]=true,[1740]=true,
    [1741]=true,[1742]=true,[1743]=true,[1744]=true,[1745]=true,[1746]=true,
    [1747]=true,[1748]=true,[1749]=true,[1750]=true,[1751]=true,[1752]=true,
}

-- ================== HELPER ==================

local function getName(id)
    local info = getItemInfo(id)
    return (info and info.name) or ("Butterfly #" .. id)
end

local function getRarity(id)
    if id >= 1691 and id <= 1710 then return "Common", "⚪"
    elseif id >= 1711 and id <= 1730 then return "Uncommon", "🟢"
    elseif id >= 1731 and id <= 1740 then return "Rare", "🟡"
    elseif id >= 1741 and id <= 1748 then return "Epic", "🟣"
    elseif id >= 1749 and id <= 1752 then return "Legendary", "🔴"
    else return "Common", "⚪" end
end

local function fmtUptime()
    local e = math.floor((now_ms() - script_start) / 1000)
    return string.format("%dh %02dm %02ds", math.floor(e/3600), math.floor((e%3600)/60), e%60)
end

local function sendWebhook(msg)
    if WEBHOOK_URL == "" then return end
    -- Rate limit
    local now = now_ms()
    if now - last_webhook_ms < WEBHOOK_COOLDOWN then
        sleep_ms(WEBHOOK_COOLDOWN - (now - last_webhook_ms))
    end
    pcall(http.post, WEBHOOK_URL, { json = { content = msg } })
    last_webhook_ms = now_ms()
end

local function notifCatch(butterfly_id)
    local name = getName(butterfly_id)
    local rarity, emoji = getRarity(butterfly_id)
    local time_type = NIGHT_SET[butterfly_id] and "🌙 Night" or "☀️ Day"

    local msg = table.concat({
        "```",
        "🦋 BUTTERFLY CAUGHT",
        "───────────────────────",
        "🤖 Bot:       " .. bot:name(),
        "🦋 Butterfly: " .. name,
        "   Rarity:    " .. emoji .. " " .. rarity,
        "   Type:      " .. time_type,
        "🆔 Item ID:   " .. butterfly_id,
        "🌍 World:     " .. (bot:get_world_name() or "?"),
        "───────────────────────",
        "📊 Total: " .. total_caught,
        "⏱ Uptime: " .. fmtUptime(),
        "```",
    }, "\n")

    sendWebhook(msg)
end

-- ================== MAIN ==================

function findAndBreakButterflies()
    for _, id in ipairs(BUTTERFLY_IDS) do
        local tiles = bot:findTiles(id)
        for _, pos in ipairs(tiles) do
            bot:find_path(pos.x, pos.y)
            sleep(2000)
            for i = 1, 5 do
                bot:hit_block_at(pos.x, pos.y)
                sleep_ms(200)
            end
            bot:hit_block(0, 0)
            sleep_ms(200)

            -- Verify masuk inventory baru hitung
            local inv = bot:get_inventory()
            local got = false
            for _, item in ipairs(inv) do
                if item.id == id and item.amount > 0 then
                    got = true
                    break
                end
            end

            if got then
                total_caught = total_caught + 1
                log("✅ Caught: " .. getName(id) .. " (total: " .. total_caught .. ")")
                notifCatch(id)
            end
        end
    end
end

sendWebhook("🚀 **Auto Kupu Started** — " .. bot:name())

while true do
    findAndBreakButterflies()
    sleep(1000)
end
