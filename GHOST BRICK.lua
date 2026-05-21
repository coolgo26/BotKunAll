-- ============================================================
-- GHOST BRICK (Mirai) v2.1
-- Place + Break block batch packet untuk farm XP/drops.
--
-- Mekanisme: kirim SB (place) + HB (break) berulang via
-- send_packet dalam satu burst, lalu delay.
-- ============================================================

local CONFIG = {
    -- Block yang di-place & break
    BLOCK_ID = 2735,

    -- Jumlah place+break per batch
    STACK_COUNT = 30,

    -- Jumlah hit per block
    HITS_PER_BLOCK = 4,

    -- Delay antar batch (ms) — naikkan kalau kick
    BATCH_DELAY = 1000,

    -- Arah place: "left", "right", atau "auto"
    DIRECTION = "left",

    -- Total batch (0 = infinite)
    MAX_BATCHES = 0,

    -- Minimum block di inventory untuk lanjut
    MIN_BLOCKS = 50,

    -- Webhook (kosong = off)
    WEBHOOK_URL = "",

    -- Status report interval (ms)
    STATUS_INTERVAL = 60000,
}

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
    log("❌ Bot not found")
    return
end

-- ============================================================
-- STATS & HELPERS
-- ============================================================

local stats = {
    batches    = 0,
    placed     = 0,
    broken     = 0,
    start_time = now_ms(),
}

local function webhookSend(msg)
    if CONFIG.WEBHOOK_URL == "" then return end
    pcall(http.post, CONFIG.WEBHOOK_URL, { json = { content = msg } })
end

local function statusReport()
    local elapsed = math.floor((now_ms() - stats.start_time) / 1000)
    local uptime = string.format("%dh %02dm %02ds",
        math.floor(elapsed / 3600),
        math.floor((elapsed % 3600) / 60),
        elapsed % 60)
    local msg = string.format(
        "[GHOST BRICK] ⏱%s | 🧱%d placed | 💥%d broken | 📦%d batches",
        uptime, stats.placed, stats.broken, stats.batches)
    log(msg)
    webhookSend("```\n" .. msg .. "\n```")
end

local function getBlockCount()
    local inv = bot:get_inventory()
    if not inv then return 0 end
    for _, item in ipairs(inv) do
        if item.id == CONFIG.BLOCK_ID then
            return item.amount
        end
    end
    return 0
end

local function getTargetTile()
    local pos = bot:pos()
    if not pos then return nil, nil end

    local dir = CONFIG.DIRECTION
    if dir == "auto" then
        if bot:isWalkable(pos.tile_x - 1, pos.tile_y) then
            dir = "left"
        else
            dir = "right"
        end
    end

    if dir == "left" then
        return pos.tile_x - 1, pos.tile_y
    else
        return pos.tile_x + 1, pos.tile_y
    end
end

-- ============================================================
-- GHOST BRICK BATCH
-- Kirim SB + HB burst tanpa sleep di antara (satu "tick")
-- ============================================================

local function doBatch(tx, ty)
    for i = 1, CONFIG.STACK_COUNT do
        -- Place block (SB = Set Block)
        bot:send_packet({
            ID = "SB",
            x = tx,
            y = ty,
            BlockType = CONFIG.BLOCK_ID,
        })
        stats.placed = stats.placed + 1

        -- Hit/break block (HB = Hit Block)
        for j = 1, CONFIG.HITS_PER_BLOCK do
            bot:send_packet({
                ID = "HB",
                x = tx,
                y = ty,
            })
        end
        stats.broken = stats.broken + 1
    end

    stats.batches = stats.batches + 1
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
    log("👻 GHOST BRICK v2.1 — Bot: " .. bot:name())
    log(string.format("[ghost] Block: %d | Stack: %d | Hits: %d | Delay: %dms",
        CONFIG.BLOCK_ID, CONFIG.STACK_COUNT, CONFIG.HITS_PER_BLOCK, CONFIG.BATCH_DELAY))
    webhookSend("👻 **Ghost Brick Started** — " .. bot:name())

    -- Cek InWorld
    if bot:state() ~= "InWorld" then
        log("[ghost] ❌ Bot harus sudah InWorld!")
        return
    end

    -- Cek inventory
    local block_count = getBlockCount()
    log(string.format("[ghost] Inventory: %d blocks (ID %d)", block_count, CONFIG.BLOCK_ID))
    if block_count < CONFIG.MIN_BLOCKS then
        log(string.format("[ghost] ❌ Block kurang! Butuh min %d, punya %d",
            CONFIG.MIN_BLOCKS, block_count))
        return
    end

    -- Target tile
    local tx, ty = getTargetTile()
    if not tx then
        log("[ghost] ❌ Tidak bisa tentukan target tile")
        return
    end
    log(string.format("[ghost] Target: (%d,%d) [%s]", tx, ty, CONFIG.DIRECTION))

    local last_status = now_ms()
    local batch_count = 0

    while true do
        -- Status report
        if now_ms() - last_status > CONFIG.STATUS_INTERVAL then
            last_status = now_ms()
            statusReport()
        end

        -- Cek InWorld
        if bot:state() ~= "InWorld" then
            log("[ghost] ⚠ Tidak InWorld, stop")
            break
        end

        -- Max batches
        if CONFIG.MAX_BATCHES > 0 and batch_count >= CONFIG.MAX_BATCHES then
            log("[ghost] ✅ Max batches: " .. batch_count)
            break
        end

        -- Cek inventory setiap 10 batch
        if batch_count > 0 and batch_count % 10 == 0 then
            local remaining = getBlockCount()
            if remaining < CONFIG.MIN_BLOCKS then
                log(string.format("[ghost] ⚠ Block habis: %d left", remaining))
                break
            end
        end

        -- Kirim batch
        doBatch(tx, ty)

        -- Delay antar batch
        sleep(CONFIG.BATCH_DELAY)
        batch_count = batch_count + 1

        -- Progress log
        if batch_count % 50 == 0 then
            log(string.format("[ghost] %d batches | 🧱%d | 💥%d",
                batch_count, stats.placed, stats.broken))
        end
    end

    statusReport()
    log(string.format("👻 Done! 🧱%d placed | 💥%d broken | 📦%d batches",
        stats.placed, stats.broken, stats.batches))
    webhookSend(string.format("✅ **Ghost Brick Done** — 🧱%d | 💥%d | 📦%d",
        stats.placed, stats.broken, stats.batches))
end

runThread(main)
while true do sleep(1000) end
