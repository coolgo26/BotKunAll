-- ============================================================
-- AUTO CLEAR WORLD (Mirai) v1.0
-- Convert dari Zenit ke Mirai Lua API.
-- Jalankan di Global Executor atau Single-bot.
-- ============================================================

local BlackList = { [110] = true }

local CONFIG = {
    HIT_DELAY       = 550,
    JITTER_MAX_MS   = 150,
    PATH_TIMEOUT    = 10000,
    PATH_STEP_DELAY = 550,
    RECONNECT_DELAY = 5000,
    RECONNECT_MAX   = 10,
    WARP_DELAY      = 4000,
}

-- Resolve bot handle
local bot = nil
if EXECUTION_SCOPE == "global" then
    local ids = getBots()
    if #ids > 0 then
        bot = getBot(ids[1])
    end
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

local current_world_name = ""

-- ================== HELPERS ==================

local function inBl(id)
    return BlackList[id] == true
end

local function shouldBreak(x, y)
    local w = bot:get_world()
    if not w or not w.width or w.width == 0 then return false end
    local fg = w:fg_at(x, y)
    local bg = w:bg_at(x, y)
    if not fg and not bg then return false end
    if inBl(fg) or inBl(bg) then return false end
    return (fg and fg ~= 0) or (bg and bg ~= 0)
end

local function ensureConnected()
    if bot:connected() and bot:state() == "InWorld" then
        return true
    end

    log("[reconnect] Disconnected, mencoba reconnect...")

    for attempt = 1, CONFIG.RECONNECT_MAX do
        log(string.format("[reconnect] Attempt %d/%d", attempt, CONFIG.RECONNECT_MAX))
        sleep(CONFIG.RECONNECT_DELAY)

        -- Coba connect
        if not bot:connected() then
            pcall(bot.connect, bot)
            sleep(CONFIG.RECONNECT_DELAY)
        end

        -- Tunggu connected
        local waited = 0
        while not bot:connected() and waited < 20000 do
            sleep(1000)
            waited = waited + 1000
        end

        if bot:connected() then
            local state = bot:state()
            log("[reconnect] Connected! State: " .. state)

            if state == "MenuIdle" then
                -- Warp kembali ke world
                if current_world_name ~= "" then
                    log("[reconnect] Warp kembali ke " .. current_world_name)
                    pcall(bot.warp, bot, current_world_name)
                    sleep(CONFIG.WARP_DELAY)

                    -- Tunggu InWorld
                    local w_waited = 0
                    while bot:state() ~= "InWorld" and w_waited < 15000 do
                        sleep(1000)
                        w_waited = w_waited + 1000
                    end

                    if bot:state() == "InWorld" then
                        log("[reconnect] Masuk world: " .. (bot:get_world_name() or "?"))
                    else
                        log("[reconnect] Gagal masuk world")
                        -- Coba lagi di next attempt
                    end
                end
            elseif state == "InWorld" then
                log("[reconnect] Sudah InWorld")
            end

            if bot:state() == "InWorld" then
                sleep(2000)
                return true
            end
        end
    end

    log("[reconnect] Gagal setelah " .. CONFIG.RECONNECT_MAX .. " percobaan")
    return false
end

local function pathTo(x, y)
    if not ensureConnected() then return false end

    local pos = bot:pos()
    if not pos then return false end
    if pos.tile_x == x and pos.tile_y == y then return true end

    -- Mirai find_path: blocking, max 15s timeout
    local ok = pcall(bot.find_path, bot, x, y)
    if ok then
        sleep(200)
    end
    return ok
end

local function tryBreakFrom(stand_x, stand_y, target_x, target_y)
    if pathTo(stand_x, stand_y) then
        pcall(bot.hit_block_at, bot, target_x, target_y)
        sleep(CONFIG.HIT_DELAY + math.random(0, CONFIG.JITTER_MAX_MS))
        return true
    end
    return false
end

local function breakFromSide(tx, ty)
    -- Coba kiri dan kanan
    local stands = {
        { tx - 1, ty },
        { tx + 1, ty },
    }

    for _, s in ipairs(stands) do
        if tryBreakFrom(s[1], s[2], tx, ty) then
            return true
        end
    end
    return false
end

local function breakBlockingSide(tx, ty)
    local blockers = {
        { tx - 1, ty },
        { tx + 1, ty },
    }

    for _, bl in ipairs(blockers) do
        local bx, by = bl[1], bl[2]

        -- Break blocker dari bawah target
        local failCount = 0
        while shouldBreak(bx, by) do
            if not tryBreakFrom(tx, ty + 1, bx, by) then
                failCount = failCount + 1
                if failCount >= 3 then break end
                sleep(300)
            else
                failCount = 0
            end
        end

        -- Setelah blocker clear, coba break target dari sisi ini
        if not shouldBreak(bx, by) then
            if tryBreakFrom(bx, by, tx, ty) then
                return true
            end
        end
    end
    return false
end

-- ================== MAIN ==================

local function main()
    if not ensureConnected() then
        log("[clearworld] Bot not connected, abort")
        return
    end

    -- Simpan world name
    current_world_name = bot:get_world_name() or ""
    if current_world_name ~= "" then
        log("[clearworld] World: " .. current_world_name)
    end

    -- Aktifkan auto collect
    pcall(bot.set_auto_collect, bot, true, 100)

    -- Dapatkan world size
    local w = bot:get_world()
    if not w or not w.width or w.width == 0 then
        log("[clearworld] World data not loaded")
        return
    end

    local width = w.width
    local height = w.height
    log(string.format("[clearworld] Size: %dx%d", width, height))
    log("[clearworld] Starting...")

    local total_broken = 0

    -- Zig-zag dari bawah ke atas
    for y = height - 2, 3, -1 do
        for x = 0, width - 1 do
            if not ensureConnected() then
                log("[clearworld] Lost connection, abort")
                return
            end

            local failCount = 0
            while shouldBreak(x, y) do
                if not ensureConnected() then
                    log("[clearworld] DC during break, abort")
                    return
                end

                local broke = breakFromSide(x, y)
                if not broke then
                    broke = breakBlockingSide(x, y)
                end

                if broke then
                    total_broken = total_broken + 1
                    failCount = 0
                    if total_broken % 50 == 0 then
                        log("[clearworld] Broken: " .. total_broken)
                        pcall(bot.collectAll, bot)
                    end
                else
                    failCount = failCount + 1
                    if failCount >= 3 then break end
                    sleep(300)
                end
            end
        end
    end

    pcall(bot.collectAll, bot)
    log(string.format("[clearworld] Done! Total broken: %d", total_broken))
end

runThread(main)

-- Keep script alive
while true do sleep(1000) end
