-- ============================================================
-- AUTO MINE (Mirai) v1.1
-- Auto mining di MINEWORLD dengan pilihan level 1-5.
-- Jalankan di Global Executor atau Single-bot.
--
-- Cara kerja:
--   1. Bot kirim packet wlA (level selector) + TTjW (join special)
--   2. Masuk MINEWORLD instance sesuai level
--   3. Scan & mine semua gemstones/ores
--   4. Collect items, keluar, re-enter (loop)
--
-- Level 1-5 menentukan difficulty & reward di MINEWORLD.
-- ============================================================

local CONFIG = {
    -- Mine level (1-5)
    MINE_LEVEL = 1,

    -- Pickaxe item IDs (dari yang terbaik ke terburuk)
    -- Bot akan equip pickaxe terbaik yang ada di inventory
    PICKAXE_IDS = {
        4195,  -- WeaponPickaxeDark (terbaik)
        4093,  -- WeaponPickaxeEpic
        4092,  -- WeaponPickaxeMaster
        4091,  -- WeaponPickaxeHeavy
        4090,  -- WeaponPickaxeSturdy
        4089,  -- WeaponPickaxeBasic
        4088,  -- WeaponPickaxeFlimsy
        4087,  -- WeaponPickaxeCrappy
        53,    -- WeaponPickAxe (starter)
    },

    -- Timing
    HIT_DELAY       = 300,
    JITTER_MAX_MS   = 100,
    MOVE_DELAY      = 200,
    SCAN_DELAY      = 2000,
    WARP_DELAY      = 5000,
    COLLECT_DELAY   = 300,
    REENTER_DELAY   = 3000,

    -- Reconnect
    RECONNECT_DELAY = 5000,
    RECONNECT_MAX   = 10,

    -- Mining behavior
    HIT_COUNT       = 5,
    PRIORITIZE_GEMS = true,
    AUTO_REENTER    = true,
    MAX_LOOPS       = 0,  -- 0 = infinite
    MAX_PASSES      = 3,

    -- Logging
    STATUS_INTERVAL = 60000,
    WEBHOOK_URL     = "",
}

-- ============================================================
-- BLOCK IDS
-- ============================================================

-- Gemstones (high value, prioritas utama)
local GEMSTONE_IDS = {
    [3995] = true, [3996] = true, [3997] = true,
    [3998] = true, [3999] = true, [4000] = true,
    [4001] = true, [4002] = true, [4003] = true,
}

-- Crystals (medium value)
local CRYSTAL_IDS = {
    [3974] = true, [3975] = true, [3976] = true,
    [3977] = true, [3978] = true, [3979] = true,
}

-- Terrain/Soil/Rock (low value, fallback)
local TERRAIN_IDS = {
    [3980] = true, [3981] = true, [3982] = true,
    [3983] = true, [3984] = true, [3985] = true,
    [3986] = true, [3989] = true, [3991] = true,
    [3992] = true, [3994] = true,
}

-- Indestructible decorations — JANGAN di-hit
local DECORATION_IDS = {
    [4143] = true, [4144] = true, [4151] = true,
    [4152] = true, [4153] = true,
}

-- Exit portal
local EXIT_PORTAL_ID = 3966

-- ============================================================
-- RESOLVE BOT
-- ============================================================

local bot = nil
if EXECUTION_SCOPE == "global" then
    local ids = getBots()
    if #ids > 0 then bot = getBot(ids[1]) end
else
    local scope_id = EXECUTION_SCOPE:match("^single:(.+)$")
    if scope_id then
        bot = getBot(scope_id)
    else
        local ids = getBots()
        if #ids > 0 then bot = getBot(ids[1]) end
    end
end

if not bot then
    log("❌ Tidak ada bot aktif!")
    return
end

-- ============================================================
-- STATS & HELPERS
-- ============================================================

local stats = {
    gems_mined   = 0,
    blocks_mined = 0,
    mines_done   = 0,
    start_time   = now_ms(),
}

local function isMineable(block_id)
    if not block_id or block_id == 0 then return false end
    if DECORATION_IDS[block_id] then return false end
    return GEMSTONE_IDS[block_id] or CRYSTAL_IDS[block_id] or TERRAIN_IDS[block_id]
end

local function isGem(block_id)
    return GEMSTONE_IDS[block_id] == true
end

local function webhookSend(msg)
    if CONFIG.WEBHOOK_URL == "" then return end
    pcall(http.post, CONFIG.WEBHOOK_URL, {
        json = { content = msg }
    })
end

local function statusReport()
    local elapsed = math.floor((now_ms() - stats.start_time) / 1000)
    local uptime = string.format("%dh %02dm %02ds",
        math.floor(elapsed / 3600),
        math.floor((elapsed % 3600) / 60),
        elapsed % 60)
    local msg = string.format(
        "[AUTO MINE] ⏱%s | Lv%d | 💎%d gems | 🪨%d blocks | ⛏%d mines",
        uptime, CONFIG.MINE_LEVEL, stats.gems_mined, stats.blocks_mined, stats.mines_done)
    log(msg)
    webhookSend("```\n" .. msg .. "\n```")
end

-- ============================================================
-- CONNECTION & MINE ENTRY
-- ============================================================

local function ensureConnected()
    if bot:connected() and bot:state() == "InWorld" then
        return true
    end

    log("[mine] Disconnected, reconnecting...")
    for attempt = 1, CONFIG.RECONNECT_MAX do
        log(string.format("[mine] Reconnect %d/%d", attempt, CONFIG.RECONNECT_MAX))
        sleep(CONFIG.RECONNECT_DELAY)

        if not bot:connected() then
            pcall(bot.connect, bot)
            sleep(CONFIG.RECONNECT_DELAY)
        end

        local waited = 0
        while not bot:connected() and waited < 20000 do
            sleep(1000)
            waited = waited + 1000
        end

        if bot:connected() then
            local state = bot:state()
            if state == "InWorld" then
                sleep(1000)
                return true
            elseif state == "MenuIdle" then
                return true  -- caller will handle joining
            end
        end
    end

    log("[mine] ❌ Reconnect gagal")
    return false
end

--- Cek apakah bot punya pickaxe di inventory.
--- Return pickaxe_id terbaik yang ditemukan, atau nil.
local function findPickaxeInInventory()
    local inv = bot:get_inventory()
    if not inv then return nil end

    for _, pickaxe_id in ipairs(CONFIG.PICKAXE_IDS) do
        for _, item in ipairs(inv) do
            if item.id == pickaxe_id then
                return pickaxe_id
            end
        end
    end
    return nil
end

--- Claim pickaxe gratis di world PIXELMINES (Mining Gear NPC).
--- Bot warp ke PIXELMINES, cari MiningCartClaim NPC (block ID 3967), dan interact.
local function claimPickaxeFromPixelMines()
    log("[mine] Belum punya pickaxe, claim di PIXELMINES...")

    -- Pastikan di MenuIdle
    if bot:state() == "InWorld" then
        pcall(bot.leave, bot)
        sleep(2000)
    end

    local waited = 0
    while bot:state() ~= "MenuIdle" and waited < 10000 do
        sleep(1000)
        waited = waited + 1000
    end

    if bot:state() ~= "MenuIdle" then
        log("[mine] ❌ Tidak bisa ke MenuIdle untuk claim pickaxe")
        return false
    end

    -- Warp ke PIXELMINES
    log("[mine] Warp ke PIXELMINES...")
    pcall(bot.warp, bot, "PIXELMINES")
    sleep(CONFIG.WARP_DELAY)

    waited = 0
    while bot:state() ~= "InWorld" and waited < 15000 do
        sleep(1000)
        waited = waited + 1000
    end

    if bot:state() ~= "InWorld" then
        log("[mine] ❌ Gagal masuk PIXELMINES")
        return false
    end

    sleep(2000)
    log("[mine] Masuk PIXELMINES, mencari Mining Gear NPC...")

    -- Cari block MiningCartClaim (ID 3967) — ini NPC mining gear
    local MINING_GEAR_NPC_ID = 3967
    local npc_tiles = bot:findTiles(MINING_GEAR_NPC_ID)

    if not npc_tiles or #npc_tiles == 0 then
        log("[mine] ❌ Mining Gear NPC tidak ditemukan di PIXELMINES")
        pcall(bot.leave, bot)
        sleep(2000)
        return false
    end

    log(string.format("[mine] Found %d Mining Gear NPC(s)", #npc_tiles))

    -- Coba interact dengan setiap NPC sampai dapat pickaxe
    for i, npc in ipairs(npc_tiles) do
        log(string.format("[mine] NPC #%d at (%d,%d)", i, npc.x, npc.y))

        -- Walk ke tile sebelah NPC (NPC biasanya solid jadi tidak bisa walkable)
        local adj_tiles = {
            { npc.x - 1, npc.y }, { npc.x + 1, npc.y },
            { npc.x, npc.y + 1 }, { npc.x, npc.y - 1 },
        }

        local moved = false
        for _, adj in ipairs(adj_tiles) do
            if bot:isWalkable(adj[1], adj[2]) then
                log(string.format("[mine] Walking to (%d,%d) next to NPC", adj[1], adj[2]))
                local ok = pcall(bot.find_path, bot, adj[1], adj[2])
                if ok then
                    sleep(1000)
                    moved = true
                    break
                end
            end
        end

        if not moved then
            log("[mine] ⚠ Tidak bisa walk ke NPC #" .. i)
        end

        -- Interact dengan NPC: pakai hit_block_at (HB packet)
        -- NPC click di Pixel Worlds biasanya pakai HB packet di tile NPC
        log(string.format("[mine] Interact (hit) NPC at (%d,%d)", npc.x, npc.y))
        for try = 1, 3 do
            pcall(bot.hit_block_at, bot, npc.x, npc.y)
            sleep(500)
        end

        -- Tunggu animation/dialog selesai
        sleep(2000)

        -- Cek apakah sudah dapat pickaxe
        local pickaxe = findPickaxeInInventory()
        if pickaxe then
            log("[mine] ✅ Pickaxe diterima dari NPC!")
            break
        end
    end

    -- Final collect untuk ambil item yang mungkin di-drop
    pcall(bot.collectAll, bot)
    sleep(1000)

    -- Leave PIXELMINES
    log("[mine] Leaving PIXELMINES...")
    pcall(bot.leave, bot)
    sleep(2000)

    waited = 0
    while bot:state() ~= "MenuIdle" and waited < 10000 do
        sleep(1000)
        waited = waited + 1000
    end

    -- Cek hasil akhir
    local pickaxe = findPickaxeInInventory()
    if pickaxe then
        log(string.format("[mine] ✅ Pickaxe claimed: ID %d", pickaxe))
        return true
    else
        log("[mine] ⚠ Claim mungkin gagal, tidak ada pickaxe di inventory")
        return false
    end
end

--- Equip pickaxe terbaik. Kalau belum punya, claim dulu di PIXELMINES.
--- Return true jika berhasil equip, false jika gagal total.
local function equipPickaxe()
    -- Cek inventory dulu
    local pickaxe_id = findPickaxeInInventory()

    -- Kalau belum punya, claim di PIXELMINES
    if not pickaxe_id then
        local claimed = claimPickaxeFromPixelMines()
        if claimed then
            pickaxe_id = findPickaxeInInventory()
        end
    end

    -- Equip pickaxe
    if pickaxe_id then
        local info = getItemInfo(pickaxe_id)
        log(string.format("[mine] Equip pickaxe: %s (ID %d)",
            info and info.name or "?", pickaxe_id))
        pcall(bot.equip, bot, pickaxe_id)
        sleep(500)
        return true
    end

    log("[mine] ❌ Tidak punya pickaxe dan gagal claim!")
    return false
end

--- Join MINEWORLD dengan level tertentu.
--- Kirim raw packet: wlA (level selector) + TTjW (join special).
--- Level di packet = CONFIG.MINE_LEVEL - 1 (0-indexed: 0=Lv1, 4=Lv5)
local function joinMineWorld()
    local state = bot:state()

    -- Kalau sudah di MINEWORLD, langsung return
    if state == "InWorld" then
        local wname = bot:get_world_name() or ""
        if wname:upper() == "MINEWORLD" then
            return true
        end
        -- Di world lain, leave dulu
        pcall(bot.leave, bot)
        sleep(2000)
    end

    -- Pastikan di MenuIdle
    if bot:state() ~= "MenuIdle" then
        if not bot:connected() then
            pcall(bot.connect, bot)
            sleep(CONFIG.RECONNECT_DELAY)
        end
        local waited = 0
        while bot:state() ~= "MenuIdle" and waited < 15000 do
            sleep(1000)
            waited = waited + 1000
        end
        if bot:state() ~= "MenuIdle" then
            log("[mine] ❌ Tidak bisa ke MenuIdle")
            return false
        end
    end

    -- Kirim packet untuk join MINEWORLD dengan level
    -- Packet 1: wlA dengan WCSD = [level_index]
    -- Packet 2: TTjW dengan Is=true, W=MINEWORLD
    local level_index = math.max(0, math.min(4, CONFIG.MINE_LEVEL - 1))

    -- WAJIB: Equip pickaxe sebelum masuk mine
    if not equipPickaxe() then
        log("[mine] ❌ Tidak bisa mine tanpa pickaxe!")
        return false
    end

    log(string.format("[mine] Joining MINEWORLD level %d (index %d)...",
        CONFIG.MINE_LEVEL, level_index))

    -- Kirim wlA (world load args / mine level selector)
    bot:send_packet({
        ID = "wlA",
        WCSD = { level_index },
    })
    sleep(100)

    -- Kirim TTjW (join world special)
    bot:send_packet({
        ID = "TTjW",
        Is = true,
        W = "MINEWORLD",
        WB = 0,
        Amt = 1,
    })

    -- Tunggu masuk world
    local waited = 0
    while bot:state() ~= "InWorld" and waited < 20000 do
        sleep(500)
        waited = waited + 500
    end

    if bot:state() ~= "InWorld" then
        log("[mine] ❌ Timeout masuk MINEWORLD")
        return false
    end

    -- Tunggu world data loaded
    sleep(CONFIG.SCAN_DELAY)
    return true
end

-- ============================================================
-- SCANNING
-- ============================================================

local function scanTargets()
    local w = bot:get_world()
    if not w or not w.width or w.width == 0 then return {}, nil end

    local pos = bot:pos()
    if not pos then return {}, nil end
    local px, py = pos.tile_x, pos.tile_y

    local gems = {}
    local crystals = {}
    local terrain = {}
    local exit_pos = nil

    for y = 0, w.height - 1 do
        for x = 0, w.width - 1 do
            local fg = w:fg_at(x, y)
            if fg and fg ~= 0 then
                if fg == EXIT_PORTAL_ID then
                    exit_pos = { x = x, y = y }
                elseif GEMSTONE_IDS[fg] then
                    local dist = math.abs(px - x) + math.abs(py - y)
                    gems[#gems + 1] = { x = x, y = y, dist = dist }
                elseif CRYSTAL_IDS[fg] then
                    local dist = math.abs(px - x) + math.abs(py - y)
                    crystals[#crystals + 1] = { x = x, y = y, dist = dist }
                elseif TERRAIN_IDS[fg] then
                    local dist = math.abs(px - x) + math.abs(py - y)
                    terrain[#terrain + 1] = { x = x, y = y, dist = dist }
                end
            end
        end
    end

    -- Sort by distance
    local function byDist(a, b) return a.dist < b.dist end
    table.sort(gems, byDist)
    table.sort(crystals, byDist)
    table.sort(terrain, byDist)

    -- Build priority list
    local targets = {}
    if CONFIG.PRIORITIZE_GEMS then
        for _, t in ipairs(gems) do targets[#targets + 1] = t end
        for _, t in ipairs(crystals) do targets[#targets + 1] = t end
        for _, t in ipairs(terrain) do targets[#targets + 1] = t end
    else
        local all = {}
        for _, t in ipairs(gems) do all[#all + 1] = t end
        for _, t in ipairs(crystals) do all[#all + 1] = t end
        for _, t in ipairs(terrain) do all[#all + 1] = t end
        table.sort(all, byDist)
        targets = all
    end

    return targets, exit_pos
end

-- ============================================================
-- MINING LOGIC
-- ============================================================

local function mineTarget(tx, ty)
    if not ensureConnected() then return false end

    -- Verify block still mineable
    local w = bot:get_world()
    if not w then return false end
    local fg = w:fg_at(tx, ty)
    if not isMineable(fg) then return false end

    local was_gem = isGem(fg)

    -- Navigate ke adjacent tile
    local pos = bot:pos()
    if not pos then return false end
    local dist = math.abs(pos.tile_x - tx) + math.abs(pos.tile_y - ty)

    if dist > 1 then
        -- Cari tile walkable di sebelah target
        local adj_tiles = {
            { tx - 1, ty }, { tx + 1, ty },
            { tx, ty - 1 }, { tx, ty + 1 },
        }

        local moved = false
        for _, adj in ipairs(adj_tiles) do
            if bot:isWalkable(adj[1], adj[2]) then
                local ok = pcall(bot.find_path, bot, adj[1], adj[2])
                if ok then
                    sleep(CONFIG.MOVE_DELAY)
                    moved = true
                    break
                end
            end
        end

        -- Fallback: coba langsung ke target tile
        if not moved then
            local ok = pcall(bot.find_path, bot, tx, ty)
            if not ok then return false end
            sleep(CONFIG.MOVE_DELAY)
        end
    end

    -- Hit block beberapa kali
    for i = 1, CONFIG.HIT_COUNT do
        if bot:state() ~= "InWorld" then return false end

        -- Cek block masih ada
        w = bot:get_world()
        if w then
            local current_fg = w:fg_at(tx, ty)
            if not current_fg or current_fg == 0 then
                break  -- Sudah pecah
            end
        end

        pcall(bot.hit_block_at, bot, tx, ty)
        sleep(CONFIG.HIT_DELAY + math.random(0, CONFIG.JITTER_MAX_MS))
    end

    -- Track stats
    stats.blocks_mined = stats.blocks_mined + 1
    if was_gem then stats.gems_mined = stats.gems_mined + 1 end

    return true
end

-- ============================================================
-- MAIN MINING LOOP (satu siklus mine)
-- ============================================================

local function mineLoop()
    -- Join MINEWORLD dengan level yang dipilih
    if not joinMineWorld() then
        log("[mine] ❌ Gagal masuk MINEWORLD")
        return false
    end

    local wname = bot:get_world_name() or "?"
    log("[mine] ✅ Masuk: " .. wname)

    -- Cek world data
    local w = bot:get_world()
    if not w or not w.width or w.width == 0 then
        log("[mine] ❌ World data tidak loaded")
        return false
    end
    log(string.format("[mine] World: %dx%d", w.width, w.height))

    -- Mining passes
    for pass = 1, CONFIG.MAX_PASSES do
        log(string.format("[mine] === Pass %d/%d ===", pass, CONFIG.MAX_PASSES))

        local targets, exit_pos = scanTargets()

        if #targets == 0 then
            log("[mine] ⛏ Mine cleared!")
            pcall(bot.collectAll, bot)
            sleep(CONFIG.COLLECT_DELAY)

            -- Jalan ke exit portal
            if exit_pos then
                log(string.format("[mine] Exit portal di (%d,%d)", exit_pos.x, exit_pos.y))
                pcall(bot.find_path, bot, exit_pos.x, exit_pos.y)
                sleep(1500)
            end
            break
        end

        log(string.format("[mine] %d targets (💎%d gems)",
            #targets,
            (function()
                local c = 0
                for _, t in ipairs(targets) do
                    local ww = bot:get_world()
                    if ww then
                        local fg = ww:fg_at(t.x, t.y)
                        if isGem(fg) then c = c + 1 end
                    end
                end
                return c
            end)()
        ))

        local mined_count = 0
        for i, t in ipairs(targets) do
            if bot:state() ~= "InWorld" then
                log("[mine] Lost connection")
                return false
            end

            local success = mineTarget(t.x, t.y)
            if success then mined_count = mined_count + 1 end

            -- Collect setiap 10 blocks
            if mined_count > 0 and mined_count % 10 == 0 then
                pcall(bot.collectAll, bot)
                sleep(CONFIG.COLLECT_DELAY)
            end

            -- Re-scan setiap 30 targets (posisi berubah)
            if i % 30 == 0 then break end
        end

        -- Final collect
        pcall(bot.collectAll, bot)
        sleep(CONFIG.COLLECT_DELAY)

        if mined_count == 0 then
            log("[mine] Tidak ada block di-mine pass ini, selesai")
            break
        end
    end

    stats.mines_done = stats.mines_done + 1
    return true
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
    log("⛏ AUTO MINE v1.1 — Bot: " .. bot:name() .. " | Level: " .. CONFIG.MINE_LEVEL)
    webhookSend("⛏ **Auto Mine Started** — " .. bot:name() .. " | Level " .. CONFIG.MINE_LEVEL)

    local last_status = now_ms()
    local loop_count = 0

    while true do
        -- Status report
        if now_ms() - last_status > CONFIG.STATUS_INTERVAL then
            last_status = now_ms()
            statusReport()
        end

        -- Check loop limit
        if CONFIG.MAX_LOOPS > 0 and loop_count >= CONFIG.MAX_LOOPS then
            log("[mine] Max loops reached: " .. loop_count)
            break
        end

        -- Pastikan connected
        if not ensureConnected() then
            log("[mine] ❌ Tidak bisa connect, retry 10s...")
            sleep(10000)
            goto next_loop
        end

        -- Run satu siklus mine
        local success = mineLoop()
        loop_count = loop_count + 1

        if not success then
            log("[mine] Loop gagal, retry 5s...")
            sleep(5000)
        end

        -- Re-enter atau stop
        if CONFIG.AUTO_REENTER then
            log(string.format("[mine] Re-enter in %dms... (loop %d)",
                CONFIG.REENTER_DELAY, loop_count))
            -- Leave world dulu
            if bot:state() == "InWorld" then
                pcall(bot.leave, bot)
                sleep(2000)
            end
            sleep(CONFIG.REENTER_DELAY)
        else
            break
        end

        ::next_loop::
    end

    statusReport()
    log(string.format("⛏ AUTO MINE selesai! 💎%d gems | 🪨%d blocks | ⛏%d mines",
        stats.gems_mined, stats.blocks_mined, stats.mines_done))
    webhookSend(string.format("✅ **Auto Mine Done** — 💎%d | 🪨%d | ⛏%d",
        stats.gems_mined, stats.blocks_mined, stats.mines_done))
end

runThread(main)

-- Keep script alive
while true do sleep(1000) end
