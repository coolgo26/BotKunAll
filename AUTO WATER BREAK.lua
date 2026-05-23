math.randomseed(now_ms())

_G.script_start_ms = now_ms()



--------------------------------------------------
-- CONFIG
--------------------------------------------------

local CONFIG = {

    TARGET_ID = 18,

    --------------------------------------------------
    -- STORAGE
    --------------------------------------------------

    STORAGE_ITEMS     = { [18] = true, [19] = true },  -- 18 = Water Block (BlockWater/type=3), 19 = Water Seed (Seed/type=2)
    SEED_IDS          = { [19] = true },               -- IDs yang dianggap seed (inventory_type == 2)
    STORAGE_THRESHOLD = 25,

    PORTALS = {
        "RUPIAHXDOLLAR:MAHKOTASUMEDANG",
        "RUPIAHXDOLLAR:MAHKOTA2",
        "RUPIAHXDOLLAR:MAHKOTA3",
        "RUPIAHXDOLLAR:MAHKOTA4",
        "RUPIAHXDOLLAR:MAHKOTA5",
        "RUPIAHXDOLLAR:MAHKOTA6",
        "RUPIAHXDOLLAR:MAHKOTA7",
        "RUPIAHXDOLLAR:MAHKOTA8",
        "RUPIAHXDOLLAR:MAHKOTA9",
        "RUPIAHXDOLLAR:MAHKOTA10"
    },

    BASE_SHIFT      = 8,
    SHIFT_INTERVAL  = 30,
    MIN_SHIFT       = 1,

    STEP_DELAY      = 300,
    RELEASE_DELAY   = 400,

    --------------------------------------------------
    -- FARM
    --------------------------------------------------

    HIT_DELAY_MS       = 150,
    MOVE_COOLDOWN_MS   = 150,
    PATH_TIMEOUT_MS    = 6000,
    COLLECT_WAIT_MS    = 300,
    WORLD_LOOP_LIMIT   = 0,
    STATUS_LOG_MS      = 60000,
    RECONNECT_CD_MS    = 4000,
    MAX_PASSES         = 4,
    SYNC_WAIT_MS       = 500,
    DEBUG_LOGS         = false,
    LIMBO_TIMEOUT_MS   = 45000,
    CONNECT_TIMEOUT_MS = 15000,

    ENTER_TIMEOUT_MS   = 20000,

    HIT_JITTER_MIN  = 0,
    HIT_JITTER_MAX  = 40,
    HIT_RANGE       = 1,

    --------------------------------------------------
    -- WEBHOOK
    --------------------------------------------------

    WEBHOOK_URL       = "https://discord.com/api/webhooks/1501637373409230971/hqbjaPSLcmtBskG2gYEjy7lXc_sThqyU5KQEvBli_EClwzuDq2n55zb2krI0DbTu8nG0",
    WEBHOOK_COOLDOWN  = 5000,
    WEBHOOK_MAX_RETRY = 2,
}

--------------------------------------------------
-- GLOBALS
--------------------------------------------------

local bot_states  = {}
local bot_stats   = {}

local grand_found  = 0
local grand_broken = 0
local total_cycles = 0
local status_timer = 0

local CURRENT_PORTAL_INDEX = 1
local totalReleased        = 0

-- Per-portal stats: track seed dan block yang di-drop ke masing-masing portal
local portal_stats = {}  -- { ["World:ID"] = { blocks = 0, seeds = 0 } }

local pending_warns = {}
local last_webhook_ms = 0

--------------------------------------------------
-- SAFE CALL
--------------------------------------------------

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then return nil end
    return res
end

--------------------------------------------------
-- WEBHOOK (rate-limited, retry, single message)
--------------------------------------------------

local function webhookSend(msg)
    if not CONFIG.WEBHOOK_URL or CONFIG.WEBHOOK_URL == "" then return end

    local now = now_ms()
    if now - last_webhook_ms < CONFIG.WEBHOOK_COOLDOWN then
        sleep_ms(CONFIG.WEBHOOK_COOLDOWN - (now - last_webhook_ms))
    end

    for attempt = 1, CONFIG.WEBHOOK_MAX_RETRY do
        local ok, res = pcall(http.post, CONFIG.WEBHOOK_URL, {
            json = { content = msg }
        })
        if ok then
            last_webhook_ms = now_ms()
            return true
        end
        sleep_ms(2000 * attempt)
    end
    return false
end

--- Kirim Discord Embed (tampilan keren dengan warna, fields, footer)
local function webhookEmbed(embed_data)
    if not CONFIG.WEBHOOK_URL or CONFIG.WEBHOOK_URL == "" then return end

    local now = now_ms()
    if now - last_webhook_ms < CONFIG.WEBHOOK_COOLDOWN then
        sleep_ms(CONFIG.WEBHOOK_COOLDOWN - (now - last_webhook_ms))
    end

    local payload = {
        username   = "ðŸ’§ Water Farm Bot",
        avatar_url = "https://i.imgur.com/6YToyEF.png",
        embeds     = { embed_data }
    }

    for attempt = 1, CONFIG.WEBHOOK_MAX_RETRY do
        local ok, res = pcall(http.post, CONFIG.WEBHOOK_URL, {
            json = payload
        })
        if ok then
            last_webhook_ms = now_ms()
            return true
        end
        sleep_ms(2000 * attempt)
    end
    return false
end

--------------------------------------------------
-- LOG
--------------------------------------------------

local function info(id, msg)
    log("[" .. id .. "] " .. msg)
end

local function warn(id, msg)
    log("[WARN][" .. id .. "] " .. msg)
    table.insert(pending_warns, "[" .. id .. "] " .. msg)
    if #pending_warns > 10 then
        table.remove(pending_warns, 1)
    end
end

local function debug(id, msg)
    if CONFIG.DEBUG_LOGS then
        log("[DEBUG][" .. id .. "] " .. msg)
    end
end

--------------------------------------------------
-- BOT STATS TRACKER
--------------------------------------------------

local function initBotStats(id)
    if not bot_stats[id] then
        bot_stats[id] = {
            broken_total   = 0,
            broken_minute  = 0,
            last_reset     = now_ms(),
            current_world  = "",
            phase          = "idle",
        }
    end
end

local function trackBreak(id)
    initBotStats(id)
    bot_stats[id].broken_total  = bot_stats[id].broken_total + 1
    bot_stats[id].broken_minute = bot_stats[id].broken_minute + 1
end

local function resetMinuteCounters()
    for id, stats in pairs(bot_stats) do
        stats.broken_minute = 0
        stats.last_reset    = now_ms()
    end
end

local function updateBotPhase(id, phase, world)
    initBotStats(id)
    bot_stats[id].phase = phase or "?"
    if world then
        bot_stats[id].current_world = world
    end
end

--------------------------------------------------
-- SEND REPORT (single webhook message, detailed)
--------------------------------------------------

local function sendReport()
    if not CONFIG.WEBHOOK_URL or CONFIG.WEBHOOK_URL == "" then return end

    local bot_ids = getBots()

    -- Uptime
    local uptime_str = "?"
    if _G.script_start_ms then
        local e = math.floor((now_ms() - _G.script_start_ms) / 1000)
        uptime_str = string.format("%dh %02dm %02ds",
            math.floor(e / 3600), math.floor((e % 3600) / 60), e % 60)
    end

    -- Phase summary
    local phase_count = {}
    local farming_count = 0
    for _, id in ipairs(bot_ids) do
        local st = bot_states[id]
        if st then
            local ph = st.phase or "?"
            phase_count[ph] = (phase_count[ph] or 0) + 1
            if ph == "farming" then farming_count = farming_count + 1 end
        end
    end

    local PHASE_EMOJI = {
        farming = "â›ï¸", entering = "ðŸšª", syncing = "ðŸ”„",
        scanning = "ðŸ”", storage_leave = "ðŸ“¤", storage_enter = "ðŸ“¥",
        storage_return = "â†©ï¸", leaving = "ðŸš¶", refresh = "â™»ï¸",
        idle = "ðŸ’¤", recover = "ðŸ”§",
    }

    local phase_lines = {}
    for ph, count in pairs(phase_count) do
        local emoji = PHASE_EMOJI[ph] or "â–ªï¸"
        table.insert(phase_lines, string.format("%s %s: **%d**", emoji, ph, count))
    end

    -- Per-bot detail
    local bot_details = {}
    for _, id in ipairs(bot_ids) do
        initBotStats(id)
        local s = bot_stats[id]
        local short_id = string.sub(id, 1, 10)

        local b = getBot(id)
        local lvl = 0
        local gems = 0
        if b and b:connected() and b:state() == "InWorld" then
            local acc = safeCall(b.get_account, b)
            if not acc then
                pcall(b.open_shop, b)
                sleep_ms(500)
                pcall(b.close_shop, b)
                sleep_ms(300)
                acc = safeCall(b.get_account, b)
            end
            if acc then
                gems = acc.gems or 0
                lvl = acc.level or 0
            end
        end

        table.insert(bot_details, {
            id = short_id, bpm = s.broken_minute, total = s.broken_total,
            phase = s.phase, world = s.current_world, level = lvl, gems = gems,
        })
    end
    table.sort(bot_details, function(a, b) return a.bpm > b.bpm end)

    -- Top bots string (world name di-blur)
    local top_lines = {}
    local show_count = math.min(#bot_details, 10)
    for i = 1, show_count do
        local d = bot_details[i]
        -- Blur world name: hanya tampilkan 3 huruf pertama + ***
        local world_blur = "---"
        if d.world and d.world ~= "" then
            world_blur = string.sub(d.world, 1, 3) .. "***"
        end
        table.insert(top_lines, string.format(
            "`%s` Lv%d | %dG | %d/m | %s | %s",
            d.id, d.level, d.gems, d.bpm, d.phase, world_blur
        ))
    end
    if #bot_details > 10 then
        table.insert(top_lines, string.format("*... +%d more*", #bot_details - 10))
    end

    -- Portal stats
    local portal_lines = {}
    for idx, p in ipairs(CONFIG.PORTALS) do
        local ps = portal_stats[p]
        if ps and (ps.blocks > 0 or ps.seeds > 0) then
            -- Blur nama portal: hanya tampilkan "Portal #1", "Portal #2", dst
            table.insert(portal_lines, string.format(
                "`Portal #%d` ðŸ§± %d | ðŸŒ± %d",
                idx, ps.blocks, ps.seeds
            ))
        end
    end

    -- Warnings
    local warn_text = ""
    if #pending_warns > 0 then
        local max_warns = math.min(#pending_warns, 5)
        local warn_lines = {}
        for i = 1, max_warns do
            table.insert(warn_lines, "â€¢ " .. pending_warns[i])
        end
        warn_text = table.concat(warn_lines, "\n")
        pending_warns = {}
    end

    -- Efficiency calc
    local bpm_total = 0
    for _, d in ipairs(bot_details) do
        bpm_total = bpm_total + d.bpm
    end

    -- Color based on status (green = good, yellow = some issues, red = bad)
    local embed_color = 3066993  -- green
    if farming_count < #bot_ids / 2 then
        embed_color = 15844367  -- yellow
    end
    if farming_count == 0 then
        embed_color = 15158332  -- red
    end

    -- Build embed
    local fields = {
        {
            name = "ðŸ“Š Statistics",
            value = table.concat({
                "ðŸŒŠ Found: **" .. grand_found .. "**",
                "ðŸ”¨ Broken: **" .. grand_broken .. "**",
                "ðŸ“¦ Dropped: **" .. totalReleased .. "**",
                "ðŸ”„ Cycles: **" .. total_cycles .. "**",
                "âš¡ Speed: **" .. bpm_total .. "**/min",
            }, "\n"),
            inline = true,
        },
        {
            name = "ðŸ¤– Bots (" .. #bot_ids .. ")",
            value = table.concat(phase_lines, "\n"),
            inline = true,
        },
    }

    -- Portal field (jika ada data)
    if #portal_lines > 0 then
        table.insert(fields, {
            name = "ðŸ“¦ Storage Portals",
            value = table.concat(portal_lines, "\n"),
            inline = false,
        })
    end

    -- Top bots field
    if #top_lines > 0 then
        table.insert(fields, {
            name = "ðŸ† Top Bots (per minute)",
            value = table.concat(top_lines, "\n"),
            inline = false,
        })
    end

    -- Warnings field
    if warn_text ~= "" then
        table.insert(fields, {
            name = "âš ï¸ Warnings",
            value = warn_text,
            inline = false,
        })
    end

    local embed = {
        title       = "ðŸ’§ Auto Water Farm",
        description = "â±ï¸ Uptime: **" .. uptime_str .. "** | ðŸ¤– **" .. #bot_ids .. "** bots active",
        color       = embed_color,
        fields      = fields,
        footer      = {
            text = "Water Farm v2.0 â€¢ " .. os.date("%Y-%m-%d %H:%M:%S"),
        },
        thumbnail   = {
            url = "https://i.imgur.com/6YToyEF.png",
        },
    }

    webhookEmbed(embed)

    -- Reset per-minute counters
    resetMinuteCounters()
end

--------------------------------------------------
-- HEARTBEAT
--------------------------------------------------

local function heartbeat(st)
    st.last_heartbeat = now_ms()
end

--------------------------------------------------
-- WORLD VALID
--------------------------------------------------

local function isValidWorld(w)
    -- Per docs: world table has w.fg, w.bg, w.water, w.wiring as separate arrays
    return w
        and type(w) == "table"
        and w.width
        and w.height
        and w.fg
        and #w.fg > 0
end

local function worldReady(actor)
    if actor:state() ~= "InWorld" then return false end
    local w = safeCall(actor.get_world, actor)
    return isValidWorld(w)
end

--------------------------------------------------
-- WAIT MENU IDLE
--------------------------------------------------

local function waitMenuIdle(actor, timeout)
    timeout = timeout or 15000
    local endTime = now_ms() + timeout
    while now_ms() < endTime do
        local s = safeCall(actor.state, actor)
        if s == "MenuIdle" then return true end
        if s == "Failed" or s == "Disconnected" then
            pcall(actor.connect, actor)
        end
        sleep_ms(250)
    end
    return false
end

--------------------------------------------------
-- CLEAN LEAVE
--------------------------------------------------

local function cleanLeave(b, st, id)
    local cur = safeCall(b.state, b) or ""
    if cur ~= "InWorld" then
        if cur == "MenuIdle" then return true end
        local ok = waitMenuIdle(b, 10000)
        if not ok then
            warn(id, "cleanLeave: state aneh (" .. cur .. "), reconnect")
            pcall(b.disconnect, b)
            sleep_ms(400)
            pcall(b.connect, b)
            st.phase       = "recover"
            st.next_action = now_ms() + 2500
            return false
        end
        return true
    end

    pcall(b.leave, b)
    sleep_ms(200)

    cur = safeCall(b.state, b) or ""
    if cur == "MenuIdle" then return true end

    local ok = waitMenuIdle(b, 15000)
    if not ok then
        warn(id, "cleanLeave timeout")
        pcall(b.disconnect, b)
        sleep_ms(400)
        pcall(b.connect, b)
        st.phase       = "recover"
        st.next_action = now_ms() + 2500
        return false
    end
    return true
end

--------------------------------------------------
-- SAFE WARP
--------------------------------------------------

local function safeWarp(b, st, id, destination)
    if not destination or destination == "" then
        warn(id, "safeWarp: destination kosong, kembali idle")
        st.phase         = "idle"
        st.current_world = ""
        st.next_action   = now_ms() + 300
        return false
    end

    local cur = safeCall(b.state, b) or ""

    if cur == "InWorld" then
        pcall(b.leave, b)
        sleep_ms(200)
        cur = safeCall(b.state, b) or ""
    end

    if cur == "MenuIdle" then
        pcall(b.warp, b, destination)
        return true
    end

    pcall(b.leave, b)
    local ok = waitMenuIdle(b, 12000)
    if not ok then
        warn(id, "safeWarp: gagal MenuIdle, reconnect")
        pcall(b.disconnect, b)
        sleep_ms(300)
        pcall(b.connect, b)
        st.phase         = "recover"
        st.next_action   = now_ms() + 2500
        st.path_active   = false
        return false
    end

    pcall(b.warp, b, destination)
    return true
end

--------------------------------------------------
-- FORCE RECONNECT
--------------------------------------------------

local function forceReconnect(b, st, id, reason)
    warn(id, "Reconnect: " .. reason)
    pcall(b.disconnect, b)
    sleep_ms(300)
    pcall(b.connect, b)
    st.phase         = "recover"
    st.next_action   = now_ms() + 2500
    st.path_active   = false
    st.connect_start = 0
    heartbeat(st)
end

--------------------------------------------------
-- PORTAL
--------------------------------------------------

local function getCurrentPortal()
    return CONFIG.PORTALS[CURRENT_PORTAL_INDEX]
end

local function nextPortal()
    CURRENT_PORTAL_INDEX = CURRENT_PORTAL_INDEX + 1
    if CURRENT_PORTAL_INDEX > #CONFIG.PORTALS then
        CURRENT_PORTAL_INDEX = 1
    end
end

--------------------------------------------------
-- ITEM COUNT
--------------------------------------------------

local function getItemCount(b, itemIds)
    local inv = safeCall(b.get_inventory, b) or {}
    local total = 0
    for _, item in ipairs(inv) do
        if itemIds[item.id] then
            total = total + (item.amount or 0)
        end
    end
    return total
end

--------------------------------------------------
-- RELOCATE
--------------------------------------------------

--- Gerak horizontal: dx positif = kanan, negatif = kiri
local function moveHorizontal(actor, steps)
    if not worldReady(actor) then return end
    local dir = steps > 0 and 1 or -1
    for _ = 1, math.abs(steps) do
        if not worldReady(actor) then break end
        pcall(actor.walk, actor, dir, 0)
        sleep_ms(CONFIG.STEP_DELAY)
    end
end

--- Cek apakah tile di depan bot ada collectable (penuh items)
local function isTileFull(actor)
    if not worldReady(actor) then return false end
    local collectables = safeCall(actor.get_collectables, actor) or {}
    local pos = safeCall(actor.pos, actor)
    if not pos then return false end

    -- Per docs: Collectable x/y are sub-pixel coordinates
    -- Use math.floor(c.x / 32) to convert to tile coords (as shown in docs example)
    local count = 0
    for _, c in ipairs(collectables) do
        local cx = math.floor(c.x / 32)
        local cy = math.floor(c.y / 32)
        if cx == pos.tile_x and cy == pos.tile_y then
            count = count + 1
        end
    end

    -- Tile penuh kalau >= 5 items (Pixel World limit)
    return count >= 5
end

--------------------------------------------------
-- DISTRIBUTE
--------------------------------------------------

local function distribute(actor, portal_name, bot_id)
    if not worldReady(actor) then return 0 end

    pcall(actor.set_auto_collect, actor, false)
    sleep_ms(200)

    local id = bot_id or "unknown"

    -- Init portal stats
    if portal_name and not portal_stats[portal_name] then
        portal_stats[portal_name] = { blocks = 0, seeds = 0 }
    end

    -- Step 1: Maju 7 block ke kanan setelah masuk portal
    moveHorizontal(actor, 7)
    sleep_ms(300)

    -- Step 2: Drop semua storage items
    local inventory = safeCall(actor.get_inventory, actor) or {}
    local released  = 0
    local dropCount = 0
    local blocks_dropped = 0
    local seeds_dropped  = 0

    for _, item in ipairs(inventory) do
        if not worldReady(actor) then break end

        -- Drop jika item ID ada di STORAGE_ITEMS
        local should_drop = CONFIG.STORAGE_ITEMS[item.id]

        if should_drop and item.amount > 0 then
            local remain = item.amount
            while remain > 0 do
                if not worldReady(actor) then break end

                -- Cek apakah tile saat ini penuh
                if isTileFull(actor) then
                    moveHorizontal(actor, -1)
                    sleep_ms(200)
                end

                local dropAmount = math.min(remain, 100)
                
                -- Get inventory SEBELUM drop
                local inv_before = safeCall(actor.get_inventory, actor) or {}
                local before_amount = 0
                for _, it in ipairs(inv_before) do
                    if it.id == item.id then before_amount = it.amount or 0 end
                end
                
                -- Attempt drop
                pcall(actor.drop, actor, item.id, dropAmount, item.inventory_type)
                sleep_ms(CONFIG.RELEASE_DELAY)

                -- Get inventory SETELAH drop
                local inv_after = safeCall(actor.get_inventory, actor) or {}
                local after_amount = 0
                for _, it in ipairs(inv_after) do
                    if it.id == item.id then after_amount = it.amount or 0 end
                end
                
                -- Check if drop actually succeeded
                local actual_dropped = before_amount - after_amount
                if actual_dropped <= 0 then
                    -- Drop gagal, mundur dan retry
                    moveHorizontal(actor, -1)
                    sleep_ms(200)
                    
                    -- Retry drop once
                    pcall(actor.drop, actor, item.id, dropAmount, item.inventory_type)
                    sleep_ms(CONFIG.RELEASE_DELAY)
                    
                    -- Check again after retry
                    inv_after = safeCall(actor.get_inventory, actor) or {}
                    after_amount = 0
                    for _, it in ipairs(inv_after) do
                        if it.id == item.id then after_amount = it.amount or 0 end
                    end
                    actual_dropped = before_amount - after_amount
                end

                -- Only count what actually dropped
                if actual_dropped > 0 then
                    released = released + actual_dropped
                    dropCount = dropCount + 1
                    remain = remain - actual_dropped
                    
                    -- Track block vs seed
                    local is_seed = false
                    if item.inventory_type == 2 then
                        is_seed = true
                    elseif CONFIG.SEED_IDS[item.id] then
                        is_seed = true
                    end

                    if is_seed then
                        seeds_dropped = seeds_dropped + actual_dropped
                    else
                        blocks_dropped = blocks_dropped + actual_dropped
                    end
                else
                    -- Drop failed repeatedly, skip remaining of this item
                    warn(id, "Drop failed for item " .. item.id .. ", skipping")
                    break
                end

                sleep_ms(CONFIG.RELEASE_DELAY)
            end
        end
    end

    -- Fallback: jika tidak ada storage items tapi inventory penuh, drop semua
    if released == 0 then
        inventory = safeCall(actor.get_inventory, actor) or {}
        for _, item in ipairs(inventory) do
            if not worldReady(actor) then break end
            if item.amount and item.amount > 0 then
                if isTileFull(actor) then
                    moveHorizontal(actor, -1)
                    sleep_ms(200)
                end
                pcall(actor.drop, actor, item.id, item.amount, item.inventory_type)
                released  = released + item.amount
                dropCount = dropCount + 1

                local is_seed = false
                if item.inventory_type == 2 then
                    is_seed = true
                elseif CONFIG.SEED_IDS[item.id] then
                    is_seed = true
                end

                if is_seed then
                    seeds_dropped = seeds_dropped + item.amount
                else
                    blocks_dropped = blocks_dropped + item.amount
                end

                sleep_ms(CONFIG.RELEASE_DELAY)
            end
        end
    end

    -- Update per-portal stats
    if portal_name and portal_stats[portal_name] then
        portal_stats[portal_name].blocks = portal_stats[portal_name].blocks + blocks_dropped
        portal_stats[portal_name].seeds  = portal_stats[portal_name].seeds + seeds_dropped
    end

    totalReleased = totalReleased + dropCount
    return released
end

--------------------------------------------------
-- AUTO EXPAND INVENTORY
--------------------------------------------------

local function tryExpandInventory(b, id)
    if not b then return end
    
    -- Completely safe approach - check everything
    local inv = nil
    local ok = pcall(function()
        inv = b:inventory()
    end)
    if not ok or not inv then return end
    
    -- Validate slots is a number
    if not inv.slots or type(inv.slots) ~= "number" then return end
    
    -- Count items safely
    local item_count = 0
    if inv.items and type(inv.items) == "table" then
        item_count = #inv.items
    end
    
    -- Calculate free slots
    local free_slots = inv.slots - item_count
    if free_slots > 2 then return end
    
    -- Get account safely
    local acc = nil
    ok = pcall(function()
        acc = b:get_account()
    end)
    if not ok or not acc then return end
    
    if not acc.gems or type(acc.gems) ~= "number" then return end
    if acc.gems < 50 then return end
    
    local gems_before = acc.gems
    local expanded = 0
    
    -- Try to expand inventory
    for _ = 1, 10 do
        local expand_ok = pcall(function()
            b:buy_inventory_slots()
        end)
        if not expand_ok then break end
        
        sleep_ms(500)
        
        -- Check gems again
        acc = nil
        ok = pcall(function()
            acc = b:get_account()
        end)
        if not ok or not acc or not acc.gems or type(acc.gems) ~= "number" then break end
        
        if acc.gems >= gems_before then break end
        
        expanded = expanded + 1
        gems_before = acc.gems
        
        if acc.gems < 50 then break end
    end
    
    if expanded > 0 and acc and acc.gems then
        info(id, "Expanded +" .. expanded .. " slots (gems: " .. acc.gems .. ")")
    end
end

--------------------------------------------------
-- STATUS (console)
--------------------------------------------------

local function logStatus()
    log("+--------------------------------+")
    log("Bots: "     .. #getBots())
    log("Found: "    .. grand_found)
    log("Broken: "   .. grand_broken)
    log("Released: " .. totalReleased)
    log("Cycles: "   .. total_cycles)
    log("+--------------------------------+")
end

--------------------------------------------------
-- INIT
--------------------------------------------------

local function init()
    for _, id in ipairs(getBots()) do
        local b      = getBot(id)
        local state  = b and safeCall(b.state, b) or "Unknown"
        local world  = b and safeCall(b.get_world_name, b) or ""
        local inWorld = (state == "InWorld")

        local startPhase
        if inWorld then
            startPhase = "syncing"
            info(id, "Resume in world: " .. world)
        elseif state == "MenuIdle" then
            startPhase = "idle"
        else
            startPhase = "recover"
        end

        bot_states[id] = {
            phase          = startPhase,
            worlds_done    = 0,
            current_world  = inWorld and world or "",
            targets        = {},
            target_idx     = 1,
            task           = "move",
            hits_count     = 0,
            next_action    = 0,
            path_active    = false,
            path_start     = 0,
            last_reconnect = 0,
            pass           = 0,
            enter_time     = 0,
            sync_retries   = 0,
            last_heartbeat = now_ms(),
            connect_start  = 0,
        }

        initBotStats(id)
        updateBotPhase(id, startPhase, world)

        if b then
            pcall(b.set_auto_reconnect, b, false)
            if inWorld then
                pcall(b.set_auto_collect, b, true, 100)
            end
        end
    end
end

init()

--------------------------------------------------
-- START
--------------------------------------------------

log("AUTO WATER FARM + STORAGE v2.0")
webhookEmbed({
    title       = "ðŸš€ Script Started",
    description = "Auto Water Farm aktif dengan **" .. #getBots() .. "** bot",
    color       = 3066993,
    fields      = {
        { name = "ðŸ¤– Bots", value = tostring(#getBots()), inline = true },
        { name = "ðŸ“¦ Portals", value = tostring(#CONFIG.PORTALS), inline = true },
        { name = "ðŸŽ¯ Target ID", value = tostring(CONFIG.TARGET_ID), inline = true },
    },
    footer      = { text = "Water Farm v2.0 â€¢ Started" },
    thumbnail   = { url = "https://i.imgur.com/6YToyEF.png" },
})

-- Debug: print account fields dari bot pertama
local debug_ids = getBots()
if #debug_ids > 0 then
    local db = getBot(debug_ids[1])
    if db and db:connected() then
        local acc = safeCall(db.get_account, db)
        if acc then
            log("[DEBUG] Account fields:")
            for k, v in pairs(acc) do
                log("  ", k, "=", tostring(v))
            end
        else
            log("[DEBUG] get_account() = nil")
        end
    end
end

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

while true do

    local now = now_ms()

    if now - status_timer > CONFIG.STATUS_LOG_MS then
        status_timer = now
        logStatus()
        sendReport()
    end

    for _, id in ipairs(getBots()) do

        local b  = getBot(id)
        local st = bot_states[id]

        if not b or not st or st.phase == "done" then
            goto continue_loop
        end

        if st.next_action > now then
            goto continue_loop
        end

        local state = safeCall(b.state, b) or "Unknown"

        -- Update stats tracker
        updateBotPhase(id, st.phase, st.current_world)

        ----------------------------------------------
        -- CONNECT TIMEOUT
        ----------------------------------------------

        if state == "Connecting" then
            if st.connect_start == 0 then
                st.connect_start = now
            elseif now - st.connect_start > CONFIG.CONNECT_TIMEOUT_MS then
                forceReconnect(b, st, id, "Connect timeout")
                goto continue_loop
            end
            st.next_action = now + 500
            goto continue_loop
        else
            st.connect_start = 0
        end

        ----------------------------------------------
        -- LIMBO
        ----------------------------------------------

        if state == "InWorld" then
            local w = safeCall(b.get_world, b)
            if not isValidWorld(w) then
                forceReconnect(b, st, id, "Limbo")
                goto continue_loop
            end
        end

        ----------------------------------------------
        -- HEARTBEAT TIMEOUT
        ----------------------------------------------

        if now - st.last_heartbeat > CONFIG.LIMBO_TIMEOUT_MS
        and st.phase ~= "idle"
        and st.phase ~= "recover"
        and st.phase ~= "storage_enter" then
            forceReconnect(b, st, id, "No heartbeat")
            goto continue_loop
        end

        ----------------------------------------------
        -- DISCONNECTED / FAILED
        ----------------------------------------------

        if not b:connected() or state == "Failed" then
            if now - (st.last_reconnect or 0) > CONFIG.RECONNECT_CD_MS then
                st.last_reconnect = now
                pcall(b.disconnect, b)
                sleep_ms(100)
                pcall(b.connect, b)
                st.phase       = "recover"
                st.next_action = now + 3000
            end
            goto continue_loop
        end

        ----------------------------------------------
        -- KICK DETECTION
        ----------------------------------------------

        if state ~= "InWorld"
        and state ~= "MenuIdle"
        and state ~= "Connecting"
        and (
            st.phase == "farming"
            or st.phase == "entering"
            or st.phase == "syncing"
            or st.phase == "scanning"
        ) then
            warn(id, "Kicked (" .. state .. ") phase=" .. st.phase)
            pcall(b.leave, b)
            st.phase       = "recover"
            st.next_action = now + 1500
            st.path_active = false
            heartbeat(st)
            goto continue_loop
        end

        ----------------------------------------------
        -- IDLE
        ----------------------------------------------

        if st.phase == "idle" then

            if state == "MenuIdle" then
                local can_loop =
                    CONFIG.WORLD_LOOP_LIMIT == 0
                    or st.worlds_done < CONFIG.WORLD_LOOP_LIMIT

                if can_loop then
                    local wname = string.char(math.random(65, 90))
                    for _ = 3, math.random(8, 15) do
                        wname = wname .. string.char(math.random(65, 90))
                    end
                    st.current_world = wname
                    info(id, "Warp " .. wname)
                    pcall(b.warp, b, wname)
                    st.phase       = "entering"
                    st.enter_time  = now
                    st.next_action = now + 2500
                    heartbeat(st)
                end
            end

        ----------------------------------------------
        -- ENTERING
        ----------------------------------------------

        elseif st.phase == "entering" then

            if state == "InWorld" then
                -- Update current_world dengan nama world yang sebenarnya
                local actual_world = safeCall(b.get_world_name, b) or st.current_world
                if actual_world and actual_world ~= "" then
                    st.current_world = actual_world
                end

                pcall(b.set_auto_collect, b, true, 100)
                st.sync_retries = 0
                st.phase        = "syncing"
                st.next_action  = now + CONFIG.SYNC_WAIT_MS
                heartbeat(st)
            elseif now - st.enter_time > CONFIG.ENTER_TIMEOUT_MS then
                warn(id, "Entering timeout, recover")
                st.phase       = "recover"
                st.next_action = now + 500
                st.path_active = false
            else
                st.next_action = now + 500
            end

        ----------------------------------------------
        -- SYNCING
        ----------------------------------------------

        elseif st.phase == "syncing" then

            local w = safeCall(b.get_world, b)
            if isValidWorld(w) then
                -- Auto expand inventory jika gems cukup (safe wrap)
                local expand_ok = pcall(function() tryExpandInventory(b, id) end)
                if not expand_ok then
                    warn(id, "Inventory expand error (skipped)")
                end

                st.phase       = "scanning"
                st.next_action = now
                heartbeat(st)
            else
                st.sync_retries = st.sync_retries + 1
                if st.sync_retries > 20 then
                    forceReconnect(b, st, id, "Sync timeout")
                else
                    st.next_action = now + 200
                end
            end

        ----------------------------------------------
        -- SCANNING
        ----------------------------------------------

        elseif st.phase == "scanning" then

            local w = safeCall(b.get_world, b)
            if isValidWorld(w) then
                st.targets = {}
                local count = 0
                -- Per docs: w.water is the flat array for water layer blocks
                -- Index formula: y * w.width + x + 1
                local water_data = w.water
                if water_data and #water_data > 0 then
                    for y = 0, w.height - 1 do
                        for x = 0, w.width - 1 do
                            if water_data[y * w.width + x + 1] == CONFIG.TARGET_ID then
                                table.insert(st.targets, { x = x, y = y })
                                count = count + 1
                            end
                        end
                    end
                end
                if st.pass == 0 then
                    grand_found = grand_found + count
                end
                if count == 0 then
                    st.phase       = "leaving"
                    st.next_action = now
                else
                    st.target_idx  = 1
                    st.task        = "move"
                    st.hits_count  = 0
                    st.phase       = "farming"
                    st.next_action = now
                end
            end

        ----------------------------------------------
        -- FARMING
        ----------------------------------------------

        elseif st.phase == "farming" then

            heartbeat(st)

            if state ~= "InWorld" then
                warn(id, "Not InWorld saat farming (" .. state .. ")")
                pcall(b.leave, b)
                st.phase       = "recover"
                st.next_action = now + 1500
                st.path_active = false
                goto continue_loop
            end

            local itemCount = getItemCount(b, CONFIG.STORAGE_ITEMS)
            if itemCount >= CONFIG.STORAGE_THRESHOLD then
                -- Cooldown: jangan trigger storage lagi kalau baru balik dari storage
                if st.last_storage_return and (now - st.last_storage_return) < 10000 then
                    -- Baru balik dari storage < 10 detik lalu, skip threshold check
                    -- Lanjut farming dulu
                else
                    pcall(b.set_auto_collect, b, false)
                    info(id, "Storage threshold (" .. itemCount .. ")")
                    st.phase       = "storage_leave"
                    st.next_action = now
                    goto continue_loop
                end
            end

            if st.target_idx > #st.targets then
                st.pass = st.pass + 1
                if st.pass < CONFIG.MAX_PASSES then
                    st.phase       = "refresh"
                    st.next_action = now
                else
                    st.phase       = "leaving"
                    st.next_action = now
                end
                goto continue_loop
            end

            local t   = st.targets[st.target_idx]
            local pos = safeCall(b.pos, b)
            local px  = pos and pos.tile_x or 0
            local py  = pos and pos.tile_y or 0
            local dist = pos
                and (math.abs(px - t.x) + math.abs(py - t.y))
                or 999

            if st.task == "move" then

                if dist <= CONFIG.HIT_RANGE then
                    st.task        = "hit"
                    st.hits_count  = 0
                    st.path_active = false
                    st.next_action = now + 80
                else
                    if not st.path_active then
                        if pcall(b.start_path, b, t.x, t.y) then
                            st.path_active = true
                            st.path_start  = now
                        else
                            st.target_idx = st.target_idx + 1
                        end
                    else
                        -- Cek apakah sudah sampai
                        local cur_pos = safeCall(b.pos, b)
                        local cur_dist = cur_pos
                            and (math.abs(cur_pos.tile_x - t.x) + math.abs(cur_pos.tile_y - t.y))
                            or 999

                        if cur_dist <= CONFIG.HIT_RANGE then
                            st.task        = "hit"
                            st.hits_count  = 0
                            st.path_active = false
                            st.next_action = now + 80
                        elseif now - st.path_start > CONFIG.PATH_TIMEOUT_MS then
                            st.path_active = false
                            st.target_idx  = st.target_idx + 1
                            debug(id, "Path timeout, skip")
                        else
                            st.next_action = now + CONFIG.MOVE_COOLDOWN_MS
                        end
                    end
                end

            elseif st.task == "hit" then

                if state ~= "InWorld" then
                    warn(id, "DC saat hit, recover")
                    st.task        = "move"
                    st.path_active = false
                    st.phase       = "recover"
                    st.next_action = now + 1000
                    goto continue_loop
                end

                if st.hits_count < 5 then
                    -- Validate position sebelum setiap hit
                    local pos = safeCall(b.pos, b)
                    if not pos then
                        -- Skip target jika pos invalid
                        debug(id, "Position invalid, skip")
                        st.target_idx = st.target_idx + 1
                        st.task = "move"
                        st.hits_count = 0
                        st.next_action = now
                    else
                        -- Check distance
                        local px = pos.tile_x or 0
                        local py = pos.tile_y or 0
                        local dist = math.abs(px - t.x) + math.abs(py - t.y)
                        
                        if dist > 1 then
                            -- Bot tidak adjacent, wait atau move kembali
                            if st.hits_count == 0 then
                                -- Retry move jika belum pernah hit
                                st.task = "move"
                                st.path_active = false
                                st.next_action = now + 200
                            else
                                -- Sudah hit sebelumnya, skip block
                                st.target_idx = st.target_idx + 1
                                st.task = "move"
                                st.hits_count = 0
                                st.next_action = now
                            end
                        else
                            -- Bot adjacent, use proper hit_water API
                            -- Per docs: hit_water(dx, dy) hits water block at offset from bot
                            local dx = t.x - px
                            local dy = t.y - py
                            pcall(b.hit_water, b, dx, dy)
                            
                            st.hits_count  = st.hits_count + 1
                            local jitter   = math.random(CONFIG.HIT_JITTER_MIN, CONFIG.HIT_JITTER_MAX)
                            st.next_action = now + CONFIG.HIT_DELAY_MS + jitter
                        end
                    end
                else
                    -- Done hitting, collect and move to next
                    pcall(b.collectAll, b)
                    grand_broken   = grand_broken + 1
                    trackBreak(id)
                    st.target_idx  = st.target_idx + 1
                    st.task        = "move"
                    st.hits_count  = 0
                    st.next_action = now + CONFIG.COLLECT_WAIT_MS
                end
            end

        ----------------------------------------------
        -- STORAGE LEAVE
        ----------------------------------------------

        elseif st.phase == "storage_leave" then

            -- Random portal dari list
            local portal = CONFIG.PORTALS[math.random(1, #CONFIG.PORTALS)]
            st.drop_portal = portal
            info(id, "Storage -> " .. portal)

            local ok = safeWarp(b, st, id, portal)
            if not ok then goto continue_loop end

            st.phase       = "storage_enter"
            st.enter_time  = now_ms()
            st.next_action = now_ms() + 3000

        ----------------------------------------------
        -- STORAGE ENTER
        ----------------------------------------------

        elseif st.phase == "storage_enter" then

            if state ~= "InWorld" then
                if st.enter_time > 0
                and now_ms() - st.enter_time > CONFIG.ENTER_TIMEOUT_MS then
                    warn(id, "Storage enter timeout, recover")
                    st.phase       = "recover"
                    st.next_action = now_ms() + 500
                else
                    st.next_action = now + 500
                end
                goto continue_loop
            end

            heartbeat(st)

            local released = distribute(b, st.drop_portal, id)
            if released > 0 then
                info(id, "Dropped " .. released)
            else
                warn(id, "Distribute gagal drop (0 items), skip storage")
            end

            -- Verifikasi inventory sudah turun
            local after_count = getItemCount(b, CONFIG.STORAGE_ITEMS)
            if after_count >= CONFIG.STORAGE_THRESHOLD then
                -- Masih penuh setelah drop â€” naikkan threshold sementara agar tidak loop
                warn(id, "Inventory masih penuh setelah drop (" .. after_count .. "), lanjut farming")
            end

            local ok = cleanLeave(b, st, id)
            if not ok then goto continue_loop end

            st.phase       = "storage_return"
            st.next_action = now_ms() + 300

        ----------------------------------------------
        -- STORAGE RETURN
        ----------------------------------------------

        elseif st.phase == "storage_return" then

            if st.current_world == "" then
                warn(id, "current_world kosong setelah storage, idle")
                st.phase       = "idle"
                st.next_action = now + 300
                goto continue_loop
            end

            info(id, "Return -> " .. st.current_world)

            local ok = safeWarp(b, st, id, st.current_world)
            if not ok then goto continue_loop end

            pcall(b.set_auto_collect, b, true, 100)
            st.last_storage_return = now_ms()
            st.phase       = "entering"
            st.enter_time  = now_ms()
            st.next_action = now_ms() + 2500

        ----------------------------------------------
        -- REFRESH
        ----------------------------------------------

        elseif st.phase == "refresh" then

            st.pass = 0

            if state ~= "InWorld" then
                st.phase       = "idle"
                st.next_action = now + 300
                goto continue_loop
            end

            local ok = cleanLeave(b, st, id)
            if not ok then goto continue_loop end

            st.phase       = "idle"
            st.next_action = now_ms() + 1000

        ----------------------------------------------
        -- LEAVING
        ----------------------------------------------

        elseif st.phase == "leaving" then

            if state == "InWorld" then
                local ok = cleanLeave(b, st, id)
                if not ok then goto continue_loop end
            end

            pcall(b.set_auto_collect, b, false)
            st.worlds_done = st.worlds_done + 1
            total_cycles   = total_cycles + 1
            st.phase       = "idle"
            st.pass        = 0
            st.path_active = false
            st.next_action = now_ms() + 300

        ----------------------------------------------
        -- RECOVER
        ----------------------------------------------

        elseif st.phase == "recover" then

            heartbeat(st)

            if not b:connected() then
                pcall(b.connect, b)
                st.next_action   = now + 1500
                st.connect_start = now

            elseif state == "MenuIdle" then
                if st.current_world ~= "" then
                    pcall(b.warp, b, st.current_world)
                    st.phase       = "entering"
                    st.enter_time  = now
                    st.next_action = now + 2500
                else
                    st.phase       = "idle"
                    st.next_action = now + 300
                end

            elseif state == "InWorld" then
                st.phase       = "syncing"
                st.next_action = now

            else
                pcall(b.leave, b)
                st.next_action = now + 800
            end
        end

        ::continue_loop::
    end

    sleep_ms(30)
end
