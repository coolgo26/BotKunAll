math.randomseed(now_ms())

_G.script_start_ms = now_ms()

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local CONFIG = {

    -- Block IDs yang HARUS dihancurkan (target)
    TARGET_IDS = {
        [1]    = true,
        [2]    = true,
        [4]    = true,
        [7]    = true,
        [8]    = true,
        [9]    = true,
        [18]   = true,
        [37]   = true,
        [1513] = true,
        [1514] = true,
        [1516] = true,
        [1518] = true,
        [1519] = true,
        [2735] = true,
    },

    --------------------------------------------------
    -- FARM TIMING
    --------------------------------------------------

    HIT_DELAY_MS       = 300,
    HIT_COUNT          = 5,
    MOVE_COOLDOWN_MS   = 200,
    PATH_TIMEOUT_MS    = 6000,
    COLLECT_WAIT_MS    = 200,
    STATUS_LOG_MS      = 60000,
    RECONNECT_CD_MS    = 4000,
    MAX_PASSES         = 4,
    SYNC_WAIT_MS       = 500,
    DEBUG_LOGS         = true,
    LIMBO_TIMEOUT_MS   = 45000,
    CONNECT_TIMEOUT_MS = 15000,
    ENTER_TIMEOUT_MS   = 20000,

    HIT_JITTER_MIN  = 30,
    HIT_JITTER_MAX  = 100,
    HIT_RANGE       = 1,

    WORLD_LOOP_LIMIT = 0,

    -- World target: kosongkan ("") untuk random
    TARGET_WORLD = "",

    --------------------------------------------------
    -- WEBHOOK
    --------------------------------------------------

    WEBHOOK_URL       = "",
    WEBHOOK_COOLDOWN  = 5000,
    WEBHOOK_MAX_RETRY = 2,
}

--------------------------------------------------
-- GLOBALS
--------------------------------------------------

local bot_states   = {}
local bot_stats    = {}

local grand_found  = 0
local grand_broken = 0
local total_cycles = 0
local status_timer = 0

local pending_warns   = {}
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
-- WEBHOOK
--------------------------------------------------

local function webhookSend(msg)
    if not CONFIG.WEBHOOK_URL or CONFIG.WEBHOOK_URL == "" then return end
    local now = now_ms()
    if now - last_webhook_ms < CONFIG.WEBHOOK_COOLDOWN then
        sleep_ms(CONFIG.WEBHOOK_COOLDOWN - (now - last_webhook_ms))
    end
    for attempt = 1, CONFIG.WEBHOOK_MAX_RETRY do
        local ok = pcall(http.post, CONFIG.WEBHOOK_URL, {
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

--------------------------------------------------
-- LOG
--------------------------------------------------

local function info(id, msg)
    log("[" .. id .. "] " .. msg)
end

local function warn(id, msg)
    log("[WARN][" .. id .. "] " .. msg)
    table.insert(pending_warns, "[" .. id .. "] " .. msg)
    if #pending_warns > 10 then table.remove(pending_warns, 1) end
end

local function dbg(id, msg)
    if CONFIG.DEBUG_LOGS then log("[DBG][" .. id .. "] " .. msg) end
end

--------------------------------------------------
-- BOT STATS
--------------------------------------------------

local function initBotStats(id)
    if not bot_stats[id] then
        bot_stats[id] = { broken_total = 0, broken_minute = 0, current_world = "", phase = "idle" }
    end
end

local function trackBreak(id)
    initBotStats(id)
    bot_stats[id].broken_total  = bot_stats[id].broken_total + 1
    bot_stats[id].broken_minute = bot_stats[id].broken_minute + 1
end

local function resetMinuteCounters()
    for _, s in pairs(bot_stats) do s.broken_minute = 0 end
end

local function updateBotPhase(id, phase, world)
    initBotStats(id)
    bot_stats[id].phase = phase or "?"
    if world then bot_stats[id].current_world = world end
end

--------------------------------------------------
-- REPORT
--------------------------------------------------

local function sendReport()
    if not CONFIG.WEBHOOK_URL or CONFIG.WEBHOOK_URL == "" then return end
    local ids = getBots()
    local e = math.floor((now_ms() - (_G.script_start_ms or now_ms())) / 1000)
    local uptime = string.format("%dh %02dm %02ds", math.floor(e/3600), math.floor((e%3600)/60), e%60)

    local phase_count = {}
    for _, id in ipairs(ids) do
        local st = bot_states[id]
        if st then phase_count[st.phase] = (phase_count[st.phase] or 0) + 1 end
    end
    local pl = {}
    for ph, c in pairs(phase_count) do pl[#pl+1] = "  "..ph..": "..c end

    local dl = {}
    for _, id in ipairs(ids) do
        initBotStats(id)
        local s = bot_stats[id]
        local short_id = string.sub(id, 1, 12)
        local b = getBot(id)
        local lvl, gems = 0, 0
        if b then
            local ok1, acc = pcall(b.get_account, b)
            if ok1 and acc then lvl = acc.level or 0; gems = acc.gems or 0 end
        end
        dl[#dl+1] = string.format("  %s | Lv%d | %dG | %d/m | %d tot | %s",
            short_id, lvl, gems, s.broken_minute, s.broken_total, s.phase)
    end

    local w_str = ""
    if #pending_warns > 0 then
        w_str = "\n⚠️ " .. table.concat(pending_warns, " | ")
        pending_warns = {}
    end

    webhookSend(table.concat({
        "```",
        "═══ AUTO CLEAR WORLD ═══",
        "⏱ " .. uptime .. " | 🤖 " .. #ids .. " bots",
        "🔍 Found: " .. grand_found .. " | 🔨 Broken: " .. grand_broken .. " | 🔄 Cycles: " .. total_cycles,
        "───────────────────────",
        "PHASES:",
        table.concat(pl, "\n"),
        "───────────────────────",
        "BOT DETAIL:",
        table.concat(dl, "\n"),
        "```",
        w_str,
    }, "\n"))
    resetMinuteCounters()
end

--------------------------------------------------
-- SAVE WORLD NAME
--------------------------------------------------

local function saveWorldName(world_name)
    if not world_name or world_name == "" then return end
    pcall(function()
        local file = io.open("d:\\PROJEK BOT\\world name.txt", "a")
        if file then file:write(world_name .. "\n"); file:close() end
    end)
    log("[SAVE] " .. world_name)
end

--------------------------------------------------
-- HEARTBEAT / WORLD VALID
--------------------------------------------------

local function heartbeat(st) st.last_heartbeat = now_ms() end

local function isValidWorld(w)
    return w and type(w) == "table" and w.width and w.height
end

local function worldReady(actor)
    if actor:state() ~= "InWorld" then return false end
    return isValidWorld(safeCall(actor.get_world, actor))
end

--------------------------------------------------
-- WAIT MENU IDLE
--------------------------------------------------

local function waitMenuIdle(actor, timeout)
    local endT = now_ms() + (timeout or 15000)
    while now_ms() < endT do
        local s = safeCall(actor.state, actor)
        if s == "MenuIdle" then return true end
        if s == "Failed" then pcall(actor.connect, actor) end
        sleep_ms(250)
    end
    return false
end

--------------------------------------------------
-- CLEAN LEAVE / FORCE RECONNECT
--------------------------------------------------

local function cleanLeave(b, st, id)
    local cur = safeCall(b.state, b) or ""
    if cur ~= "InWorld" then
        if cur == "MenuIdle" then return true end
        if not waitMenuIdle(b, 10000) then
            pcall(b.disconnect, b); sleep_ms(400); pcall(b.connect, b)
            st.phase = "recover"; st.next_action = now_ms() + 2500
            return false
        end
        return true
    end
    pcall(b.leave, b); sleep_ms(200)
    if safeCall(b.state, b) == "MenuIdle" then return true end
    if not waitMenuIdle(b, 15000) then
        pcall(b.disconnect, b); sleep_ms(400); pcall(b.connect, b)
        st.phase = "recover"; st.next_action = now_ms() + 2500
        return false
    end
    return true
end

local function forceReconnect(b, st, id, reason)
    warn(id, "Reconnect: " .. reason)
    pcall(b.disconnect, b); sleep_ms(300); pcall(b.connect, b)
    st.phase = "recover"; st.next_action = now_ms() + 2500
    st.path_active = false; st.connect_start = 0
    heartbeat(st)
end

--------------------------------------------------
-- STATUS
--------------------------------------------------

local function logStatus()
    log("+--- CLEAR WORLD ---+")
    log("Bots: " .. #getBots() .. " | Found: " .. grand_found .. " | Broken: " .. grand_broken .. " | Cycles: " .. total_cycles)
    log("+-------------------+")
end

--------------------------------------------------
-- INIT
--------------------------------------------------

local function init()
    for _, id in ipairs(getBots()) do
        local b = getBot(id)
        local state = b and safeCall(b.state, b) or "Unknown"
        local world = b and safeCall(b.get_world_name, b) or ""
        local inWorld = (state == "InWorld")

        local startPhase
        if inWorld then startPhase = "syncing"
        elseif state == "MenuIdle" then startPhase = "idle"
        else startPhase = "recover" end

        if inWorld then info(id, "Resume: " .. world) end

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
            if inWorld then pcall(b.set_auto_collect, b, true, 100) end
        end
    end
end

init()

log("AUTO CLEAR WORLD v4.1")
webhookSend("🚀 **Clear World Started** — " .. #getBots() .. " bot")

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

        if not b or not st or st.phase == "done" then goto continue_loop end
        if st.next_action > now then goto continue_loop end

        local state = safeCall(b.state, b) or "Unknown"
        updateBotPhase(id, st.phase, st.current_world)

        -- CONNECT TIMEOUT
        if state == "Connecting" then
            if st.connect_start == 0 then st.connect_start = now
            elseif now - st.connect_start > CONFIG.CONNECT_TIMEOUT_MS then
                forceReconnect(b, st, id, "Connect timeout")
            end
            st.next_action = now + 500
            goto continue_loop
        else
            st.connect_start = 0
        end

        -- LIMBO
        if state == "InWorld" then
            if not isValidWorld(safeCall(b.get_world, b)) then
                forceReconnect(b, st, id, "Limbo")
                goto continue_loop
            end
        end

        -- HEARTBEAT TIMEOUT
        if now - st.last_heartbeat > CONFIG.LIMBO_TIMEOUT_MS
        and st.phase ~= "idle" and st.phase ~= "recover" then
            forceReconnect(b, st, id, "No heartbeat")
            goto continue_loop
        end

        -- DISCONNECTED
        if not b:connected() or state == "Failed" then
            if now - (st.last_reconnect or 0) > CONFIG.RECONNECT_CD_MS then
                st.last_reconnect = now
                pcall(b.disconnect, b); sleep_ms(100); pcall(b.connect, b)
                st.phase = "recover"; st.next_action = now + 3000
            end
            goto continue_loop
        end

        -- KICK
        if state ~= "InWorld" and state ~= "MenuIdle" and state ~= "Connecting"
        and (st.phase == "farming" or st.phase == "entering" or st.phase == "syncing" or st.phase == "scanning") then
            warn(id, "Kicked (" .. state .. ")")
            pcall(b.leave, b)
            st.phase = "recover"; st.next_action = now + 1500; st.path_active = false
            heartbeat(st)
            goto continue_loop
        end

        --============================================
        -- PHASE: IDLE
        --============================================
        if st.phase == "idle" then

            if state == "MenuIdle" then
                local can = CONFIG.WORLD_LOOP_LIMIT == 0 or st.worlds_done < CONFIG.WORLD_LOOP_LIMIT
                if can then
                    local wname
                    if CONFIG.TARGET_WORLD and CONFIG.TARGET_WORLD ~= "" then
                        wname = CONFIG.TARGET_WORLD
                    else
                        wname = string.char(math.random(65, 90))
                        for _ = 3, math.random(8, 15) do
                            wname = wname .. string.char(math.random(65, 90))
                        end
                    end
                    st.current_world = wname
                    info(id, "Warp " .. wname)
                    pcall(b.warp, b, wname)
                    st.phase = "entering"; st.enter_time = now; st.next_action = now + 2500
                    heartbeat(st)
                end
            end

        --============================================
        -- PHASE: ENTERING
        --============================================
        elseif st.phase == "entering" then

            if state == "InWorld" then
                pcall(b.set_auto_collect, b, true, 100)
                st.sync_retries = 0
                st.phase = "syncing"; st.next_action = now + CONFIG.SYNC_WAIT_MS
                heartbeat(st)
            elseif now - st.enter_time > CONFIG.ENTER_TIMEOUT_MS then
                warn(id, "Enter timeout")
                st.phase = "recover"; st.next_action = now + 500; st.path_active = false
            else
                st.next_action = now + 500
            end

        --============================================
        -- PHASE: SYNCING
        --============================================
        elseif st.phase == "syncing" then

            local w = safeCall(b.get_world, b)
            if isValidWorld(w) then
                st.phase = "scanning"; st.next_action = now
                heartbeat(st)
            else
                st.sync_retries = st.sync_retries + 1
                if st.sync_retries > 20 then
                    forceReconnect(b, st, id, "Sync timeout")
                else
                    st.next_action = now + 200
                end
            end

        --============================================
        -- PHASE: SCANNING
        --============================================
        elseif st.phase == "scanning" then

            local w = safeCall(b.get_world, b)
            if isValidWorld(w) then
                st.targets = {}
                local count = 0
                local fg_arr = w.fg or w.foreground
                if fg_arr then
                    for y = 0, w.height - 1 do
                        for x = 0, w.width - 1 do
                            local fg = fg_arr[y * w.width + x + 1]
                            if fg and CONFIG.TARGET_IDS[fg] then
                                st.targets[#st.targets + 1] = { x = x, y = y }
                                count = count + 1
                            end
                        end
                    end
                end

                if st.pass == 0 then grand_found = grand_found + count end

                if count == 0 then
                    info(id, "World clear!")
                    saveWorldName(st.current_world)
                    st.phase = "leaving"; st.next_action = now
                else
                    -- Zig-zag sort: atas ke bawah, spawn block terakhir
                    local spawn = w.start or safeCall(b.entrance, b)
                    local spawn_x = spawn and (spawn.x or spawn.tile_x) or nil
                    local spawn_y = spawn and (spawn.y or spawn.tile_y) or nil

                    table.sort(st.targets, function(a, bb)
                        local a_spawn = (spawn_x and spawn_y and a.x == spawn_x and a.y == spawn_y + 1)
                        local b_spawn = (spawn_x and spawn_y and bb.x == spawn_x and bb.y == spawn_y + 1)
                        if a_spawn and not b_spawn then return false end
                        if b_spawn and not a_spawn then return true end
                        if a.y ~= bb.y then return a.y < bb.y end
                        if a.y % 2 == 0 then return a.x < bb.x
                        else return a.x > bb.x end
                    end)

                    st.target_idx = 1; st.task = "move"; st.hits_count = 0
                    st.phase = "farming"; st.next_action = now
                    info(id, count .. " blocks found")
                end
            end

        --============================================
        -- PHASE: FARMING
        --============================================
        elseif st.phase == "farming" then

            heartbeat(st)

            if state ~= "InWorld" then
                warn(id, "Not InWorld (" .. state .. ")")
                pcall(b.leave, b)
                st.phase = "recover"; st.next_action = now + 1500; st.path_active = false
                goto continue_loop
            end

            if st.target_idx > #st.targets then
                st.pass = st.pass + 1
                if st.pass < CONFIG.MAX_PASSES then
                    info(id, "Pass " .. st.pass .. " done, re-scan")
                    st.phase = "scanning"; st.next_action = now + 500
                else
                    st.phase = "leaving"; st.next_action = now
                end
                goto continue_loop
            end

            local t   = st.targets[st.target_idx]
            local pos = safeCall(b.pos, b)
            local px  = pos and pos.tile_x or 0
            local py  = pos and pos.tile_y or 0
            local dist = math.abs(px - t.x) + math.abs(py - t.y)

            ---- TASK: MOVE ----
            if st.task == "move" then

                if dist <= CONFIG.HIT_RANGE then
                    st.task = "hit"; st.hits_count = 0; st.path_active = false
                    st.next_action = now + 150
                else
                    if not st.path_active then
                        local path_x, path_y = t.x, t.y
                        local walkable = safeCall(b.isWalkable, b, t.x, t.y)
                        if not walkable then
                            local adj = {{t.x-1,t.y},{t.x+1,t.y},{t.x,t.y-1},{t.x,t.y+1}}
                            local found = false
                            for _, a in ipairs(adj) do
                                if safeCall(b.isWalkable, b, a[1], a[2]) then
                                    path_x, path_y = a[1], a[2]
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                st.target_idx = st.target_idx + 1
                                goto continue_loop
                            end
                        end

                        if pcall(b.start_path, b, path_x, path_y) then
                            st.path_active = true
                            st.path_start  = now
                        else
                            st.target_idx = st.target_idx + 1
                        end
                    else
                        local cp = safeCall(b.pos, b)
                        local cd = cp and (math.abs(cp.tile_x - t.x) + math.abs(cp.tile_y - t.y)) or 999

                        if cd <= CONFIG.HIT_RANGE then
                            st.task = "hit"; st.hits_count = 0; st.path_active = false
                            st.next_action = now + 150
                        elseif now - st.path_start > CONFIG.PATH_TIMEOUT_MS then
                            st.path_active = false
                            st.target_idx  = st.target_idx + 1
                            dbg(id, "Path timeout")
                        else
                            st.next_action = now + CONFIG.MOVE_COOLDOWN_MS
                        end
                    end
                end

            ---- TASK: HIT ----
            elseif st.task == "hit" then

                if state ~= "InWorld" then
                    warn(id, "DC saat hit")
                    st.task = "move"; st.path_active = false
                    st.phase = "recover"; st.next_action = now + 1000
                    goto continue_loop
                end

                -- Cek block masih ada
                local w = safeCall(b.get_world, b)
                if w then
                    local fg_arr = w.fg or w.foreground
                    if fg_arr then
                        local fg = fg_arr[t.y * w.width + t.x + 1]
                        if not fg or not CONFIG.TARGET_IDS[fg] then
                            st.target_idx = st.target_idx + 1
                            st.task = "move"; st.hits_count = 0
                            st.next_action = now + 50
                            goto continue_loop
                        end
                    end
                end

                if st.hits_count < CONFIG.HIT_COUNT then
                    -- ID 18 = water pakai HW, sisanya hit_block_at
                    local w2 = safeCall(b.get_world, b)
                    local current_fg = nil
                    if w2 then
                        local fa = w2.fg or w2.foreground
                        if fa then current_fg = fa[t.y * w2.width + t.x + 1] end
                    end

                    if current_fg == 18 then
                        pcall(b.send, b, "HW", { x = t.x, y = t.y, NGVj = 0 })
                    else
                        pcall(b.hit_block_at, b, t.x, t.y)
                    end
                    st.hits_count  = st.hits_count + 1
                    st.next_action = now + CONFIG.HIT_DELAY_MS + math.random(CONFIG.HIT_JITTER_MIN, CONFIG.HIT_JITTER_MAX)
                else
                    pcall(b.collectAll, b)
                    grand_broken = grand_broken + 1
                    trackBreak(id)
                    st.target_idx  = st.target_idx + 1
                    st.task        = "move"
                    st.hits_count  = 0
                    st.next_action = now + CONFIG.COLLECT_WAIT_MS
                end
            end

        --============================================
        -- PHASE: LEAVING
        --============================================
        elseif st.phase == "leaving" then

            if state == "InWorld" then
                if not cleanLeave(b, st, id) then goto continue_loop end
            end
            pcall(b.set_auto_collect, b, false)
            st.worlds_done = st.worlds_done + 1
            total_cycles   = total_cycles + 1
            st.pass        = 0
            st.path_active = false
            st.phase       = "idle"
            st.next_action = now_ms() + 300

        --============================================
        -- PHASE: RECOVER
        --============================================
        elseif st.phase == "recover" then

            heartbeat(st)

            if not b:connected() then
                pcall(b.connect, b)
                st.next_action = now + 1500; st.connect_start = now
            elseif state == "MenuIdle" then
                if st.current_world ~= "" then
                    pcall(b.warp, b, st.current_world)
                    st.phase = "entering"; st.enter_time = now; st.next_action = now + 2500
                else
                    st.phase = "idle"; st.next_action = now + 300
                end
            elseif state == "InWorld" then
                st.phase = "syncing"; st.next_action = now
            else
                pcall(b.leave, b); st.next_action = now + 800
            end
        end

        ::continue_loop::
    end

    sleep_ms(30)
end
