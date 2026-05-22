-- ================== KONFIGURASI ==================
local accounts = {
    -- Masukkan akun disini format: "email:password"
}

local LOGIN_DELAY_MIN    = 300
local LOGIN_DELAY_MAX    = 800
local CONNECT_TIMEOUT    = 15000
local POLL_INTERVAL      = 150
local KEEPALIVE_INTERVAL = 10000
local BATCH_SIZE         = 6
local BATCH_DELAY        = 500

-- Email Verification
local CHECK_VERIFICATION = true
local VERIFIED_FILE      = "verified_accounts.txt"
local UNVERIFIED_FILE    = "unverified_accounts.txt"

-- Tutorial
local CHECK_TUTORIAL     = true
local TUTORIAL_TIMEOUT   = 30000

-- File output
local SUCCESS_FILE       = "success_accounts.txt"
local FAILED_FILE        = "failed_accounts.txt"

-- ================== VALIDASI SCOPE ==================
if EXECUTION_SCOPE ~= "global" then
    log("❌ Script HANYA bisa dijalankan di Global Executor!")
    return
end

log("╔══════════════════════════════════════════════╗")
log("║  🔐 AUTO LOGIN + TUTORIAL v4.2 FAST          ║")
log("║  🤖 Multi-Account Manager by Mirai          ║")
log("╚══════════════════════════════════════════════╝")
log("")
log("📋 Total Akun    : " .. #accounts)
log("📧 Email Verify  : " .. (CHECK_VERIFICATION and "✅ ON" or "❌ OFF"))
log("🎓 Tutorial Check: " .. (CHECK_TUTORIAL and "✅ ON" or "❌ OFF"))
log("📦 Batch Size    : " .. BATCH_SIZE)
log("════════════════════════════════════════════════")

local success_count   = 0
local fail_count      = 0
local active_bots     = {}
local failed_accounts = {}
local verified_list   = {}
local unverified_list = {}
local success_list    = {}

-- ================== FUNGSI: CEK EMAIL VERIFICATION ==================
local function checkEmailVerification(bot, email)
    if not CHECK_VERIFICATION then return "unknown" end

    local status = "unknown"

    -- Cek get_account()
    local acc_ok, acc_data = pcall(function() return bot:get_account() end)
    if acc_ok and acc_data then
        local verified_field = nil
        if type(acc_data) == "table" then
            verified_field = acc_data.verified or acc_data.emailVerified
                or acc_data.email_verified or acc_data.isVerified
        else
            pcall(function() verified_field = acc_data.verified end)
            if verified_field == nil then
                pcall(function() verified_field = acc_data.emailVerified end)
            end
        end

        if verified_field ~= nil then
            if verified_field == true or verified_field == 1 then
                return "verified"
            else
                return "unverified"
            end
        end

        -- Cek level/gems
        local level, gems = nil, nil
        if type(acc_data) == "table" then
            level = acc_data.level or acc_data.Level
            gems = acc_data.gems or acc_data.Gems
        else
            pcall(function() level = acc_data.level end)
            pcall(function() gems = acc_data.gems end)
        end
        if level and level > 1 then status = "verified" end
        if gems and gems > 0 then status = "verified" end
    end

    -- Cek navigation
    local nav_ok, nav = pcall(function() return bot:navigation() end)
    if nav_ok and nav then
        local s = tostring(nav):lower()
        if s:find("verif") or s:find("email") then return "unverified" end
    end

    -- Cek dialog
    local d_ok, dialog = pcall(function() return bot:get_dialog() end)
    if d_ok and dialog then
        local s = tostring(dialog):lower()
        if s:find("verif") or s:find("email") then return "unverified" end
    end

    -- Coba warp ke world
    if status == "unknown" then
        local st = ""
        pcall(function() st = tostring(bot:state()) end)
        if st == "MenuIdle" then
            pcall(function() bot:warp("PIXELSTATION") end)
            sleep(2000)
            local ns = ""
            pcall(function() ns = tostring(bot:state()) end)
            if ns == "InWorld" then
                status = "verified"
                pcall(function() bot:warp("EXIT") end)
                sleep(1000)
            end
        elseif st == "InWorld" then
            status = "verified"
        end
    end

    return status
end

-- ================== FUNGSI: JALANKAN TUTORIAL ==================
local function runTutorial(bot, email)
    if not CHECK_TUTORIAL then return end

    -- Cek level
    local level = nil
    pcall(function()
        local acc = bot:get_account()
        if type(acc) == "table" then
            level = acc.level or acc.Level
        else
            level = acc.level
        end
    end)

    if level and level > 1 then
        log("  🎓 " .. email .. " → Lv." .. level .. " ✅ sudah tutorial")
        return
    end

    log("  🎓 " .. email .. " → Lv." .. tostring(level or "?") .. " 🔍 cek tutorial...")

    -- Pastikan MenuIdle
    local deadline = now_ms() + 8000
    while now_ms() < deadline do
        local st = ""
        pcall(function() st = tostring(bot:state()) end)
        if st == "MenuIdle" then break end
        sleep(300)
    end

    local st = ""
    pcall(function() st = tostring(bot:state()) end)
    if st ~= "MenuIdle" then
        log("  🎓 " .. email .. " → ⚠️ State=" .. st .. ", skip")
        return
    end

    sleep(800)

    -- Listener tutorial done
    local tutorialDone = false
    pcall(function()
        bot:once(events.PACKET_RECEIVED, function(pkt)
            if pkt and pkt.ids then
                for _, id in ipairs(pkt.ids) do
                    if id == "TC" then tutorialDone = true end
                end
            end
        end)
    end)

    -- Start tutorial via Mirai API
    local ok, err = pcall(function() bot:start_tutorial() end)
    if not ok then
        log("  🎓 " .. email .. " → ❌ GAGAL: " .. tostring(err))
        return
    end

    -- Tunggu 3s cek state
    sleep(3000)
    local state_after = ""
    pcall(function() state_after = tostring(bot:state()) end)

    -- MenuIdle/LoadingWorld = sudah tutorial sebelumnya
    if state_after == "MenuIdle" or state_after == "LoadingWorld" then
        log("  🎓 " .. email .. " → ✅ Sudah tutorial (state=" .. state_after .. ")")
        return
    end

    -- InWorld = belum tutorial, sedang proses
    if state_after == "InWorld" then
        log("  🎓 " .. email .. " → 📖 Tutorial running...")
        deadline = now_ms() + TUTORIAL_TIMEOUT
        while now_ms() < deadline and not tutorialDone do
            local cs = ""
            pcall(function() cs = tostring(bot:state()) end)
            if cs == "MenuIdle" then
                tutorialDone = true
                break
            end
            sleep(1000)
        end
        if tutorialDone then
            log("  🎓 " .. email .. " → 🎉 SELESAI!")
        else
            log("  🎓 " .. email .. " → ⏰ Timeout")
        end
    else
        log("  🎓 " .. email .. " → ⚠️ State=" .. state_after .. ", skip")
    end
end

-- ================== PROSES LOGIN ==================
local function loginSingle(i, acc)
    local email, pass = acc:match("^([^:]+):(.+)$")
    if not email or not pass then
        log("⚠️ [" .. i .. "] Format salah: " .. acc)
        fail_count = fail_count + 1
        table.insert(failed_accounts, {acc, "Format salah"})
        return
    end

    log("🔄 [" .. i .. "/" .. #accounts .. "] " .. email)

    local ok, result = pcall(addClient, email, pass)
    if not ok or not result then
        log("  ❌ addClient gagal")
        fail_count = fail_count + 1
        table.insert(failed_accounts, {email, "addClient gagal"})
        return
    end

    local bot = result

    local conn_ok, conn_err = pcall(function() bot:connect() end)
    if not conn_ok then
        log("  ❌ Connect error: " .. tostring(conn_err))
        fail_count = fail_count + 1
        table.insert(failed_accounts, {email, "connect error"})
        pcall(function() removeClient(bot:name()) end)
        return
    end

    -- Tunggu connected (dengan retry untuk jr=5 dan jr=11)
    local MAX_RETRIES = 3
    local connected = false
    local last_state = "Unknown"
    local reject_reason = ""

    for retry = 1, MAX_RETRIES do
        local start = now_ms()
        connected = false

        -- Listen untuk join reject
        local jr_code = nil
        local jr_listener = nil
        pcall(function()
            jr_listener = bot:on(events.PACKET_RECEIVED, function(pkt)
                if pkt and pkt.type == "JoinReject" then
                    jr_code = pkt.reason or pkt.code or pkt.jr
                end
            end)
        end)
        -- Fallback: cek via on_disconnect atau error message
        pcall(function()
            bot:on(events.DISCONNECTED, function(reason)
                if reason then
                    local r = tostring(reason)
                    if r:find("jr=5") or r:find("jr=11") or r:find("rate") or r:find("maintenance") then
                        jr_code = tonumber(r:match("jr=(%d+)")) or -1
                    end
                end
            end)
        end)

        while now_ms() - start < CONNECT_TIMEOUT do
            local s_ok, state = pcall(function() return bot:state() end)
            if not s_ok then
                sleep(POLL_INTERVAL)
            else
                last_state = tostring(state)
                if state == "MenuIdle" or state == "InWorld" then
                    connected = true
                    break
                elseif state == "Failed" or state == "Disconnected" then
                    break
                end
                sleep(POLL_INTERVAL)
            end
        end

        -- Remove listener
        if jr_listener then
            pcall(function() bot:remove_listener(jr_listener) end)
        end

        if connected then
            break -- Berhasil konek!
        end

        -- Cek apakah reject karena jr=5 atau jr=11
        local is_retryable = false
        if jr_code == 5 then
            reject_reason = "jr=5 (Rate Limited)"
            is_retryable = true
        elseif jr_code == 11 then
            reject_reason = "jr=11 (Server Full/Maintenance)"
            is_retryable = true
        else
            -- Cek dari state/error message
            local err_msg = ""
            pcall(function() err_msg = tostring(bot:get_error()) end)
            if err_msg:find("5") or err_msg:find("rate") then
                reject_reason = "jr=5 (Rate Limited)"
                is_retryable = true
            elseif err_msg:find("11") or err_msg:find("maintenance") or err_msg:find("full") then
                reject_reason = "jr=11 (Server Full/Maintenance)"
                is_retryable = true
            else
                reject_reason = last_state == "Failed" and "Rejected/Banned" or "Timeout"
                is_retryable = false
            end
        end

        if not is_retryable then
            break -- Tidak bisa di-retry (banned, dll)
        end

        -- Retry dengan delay
        if retry < MAX_RETRIES then
            local delay = 0
            if jr_code == 5 then
                delay = 3000 + (retry * 2000) -- jr=5: tunggu 3-7 detik
            elseif jr_code == 11 then
                delay = 5000 + (retry * 3000) -- jr=11: tunggu 5-11 detik
            else
                delay = 3000
            end
            log("  ⚠️ " .. reject_reason .. " → retry " .. retry .. "/" .. MAX_RETRIES .. " (wait " .. math.floor(delay/1000) .. "s)")
            
            -- Disconnect & reconnect
            pcall(function() bot:disconnect() end)
            sleep(delay)
            pcall(function() bot:connect() end)
        end
    end

    if not connected then
        log("  ❌ " .. reject_reason)
        fail_count = fail_count + 1
        table.insert(failed_accounts, {email, reject_reason})
        pcall(function() removeClient(bot:name()) end)
        return
    end

    -- Login berhasil
    bot:set_auto_reconnect(true)
    success_count = success_count + 1
    table.insert(active_bots, bot)
    table.insert(success_list, email .. ":" .. pass)
    log("  ✅ Connected!")

    -- CEK TUTORIAL
    sleep(200)
    runTutorial(bot, email)

    -- CEK EMAIL VERIFICATION
    sleep(200)
    local verify_status = checkEmailVerification(bot, email)
    if verify_status == "verified" then
        log("  📧 " .. email .. " → ✅ VERIFIED")
        table.insert(verified_list, email .. ":" .. pass)
    elseif verify_status == "unverified" then
        log("  📧 " .. email .. " → ❌ NOT VERIFIED")
        table.insert(unverified_list, email .. ":" .. pass)
    else
        log("  📧 " .. email .. " → ❓ Unknown")
        table.insert(verified_list, email .. ":" .. pass)
    end

    -- Warp ke world random
    sleep(300)
    for attempt = 1, 3 do
        local wname = ""
        for _ = 1, math.random(4, 7) do
            wname = wname .. string.char(math.random(65, 90))
        end
        pcall(function() bot:warp(wname) end)
        sleep(1500)
        local ws_ok, ws = pcall(function() return bot:state() end)
        if ws_ok and ws == "InWorld" then
            log("  🌍 Warp → " .. wname)
            break
        end
    end
    log("  ────────────────────────────────")
end

-- ================== LOGIN PER BATCH ==================
for batch_start = 1, #accounts, BATCH_SIZE do
    local batch_end = math.min(batch_start + BATCH_SIZE - 1, #accounts)
    local threads = {}

    log("")
    log("📦 Batch [" .. math.ceil(batch_start / BATCH_SIZE) .. "] → akun " .. batch_start .. "-" .. batch_end)
    log("────────────────────────────────────────")

    for i = batch_start, batch_end do
        local idx = i
        local acc = accounts[idx]
        threads[#threads + 1] = runThread(function()
            sleep(random.integer(0, LOGIN_DELAY_MAX))
            loginSingle(idx, acc)
        end)
        sleep(LOGIN_DELAY_MIN)
    end

    -- Tunggu semua thread selesai (dynamic, bukan fixed sleep)
    local batch_timeout = CONNECT_TIMEOUT + TUTORIAL_TIMEOUT + 5000
    local batch_start_time = now_ms()
    local all_done = false
    while now_ms() - batch_start_time < batch_timeout and not all_done do
        all_done = true
        for _, tid in ipairs(threads) do
            local t_ok, t_running = pcall(isThreadRunning, tid)
            if t_ok and t_running then
                all_done = false
                break
            end
        end
        if not all_done then sleep(500) end
    end

    for _, tid in ipairs(threads) do
        pcall(removeThread, tid)
    end

    if batch_end < #accounts then
        log("⏳ Next batch...")
        sleep(BATCH_DELAY)
    end
end

-- ================== SIMPAN HASIL KE FILE ==================
log("")
log("╔══════════════════════════════════════════════╗")
log("║  📊 HASIL LOGIN                             ║")
log("╚══════════════════════════════════════════════╝")
log("")
log("  ✅ Berhasil  : " .. success_count)
log("  ❌ Gagal     : " .. fail_count)
log("  🤖 Bot Aktif : " .. #active_bots)

-- Simpan akun berhasil
if #success_list > 0 then
    local f = io.open(SUCCESS_FILE, "a")
    if f then
        for _, acc in ipairs(success_list) do f:write(acc .. "\n") end
        f:close()
    end
    log("  💾 Berhasil saved → " .. SUCCESS_FILE)
end

-- Simpan akun gagal
if #failed_accounts > 0 then
    local f = io.open(FAILED_FILE, "a")
    if f then
        for _, entry in ipairs(failed_accounts) do
            f:write(entry[1] .. "|" .. entry[2] .. "\n")
        end
        f:close()
    end
    log("  💾 Gagal saved → " .. FAILED_FILE)
end

-- Simpan verified/unverified
if CHECK_VERIFICATION then
    if #verified_list > 0 then
        local f = io.open(VERIFIED_FILE, "a")
        if f then
            for _, acc in ipairs(verified_list) do f:write(acc .. "\n") end
            f:close()
        end
        log("  💾 Verified saved → " .. VERIFIED_FILE)
    end
    if #unverified_list > 0 then
        local f = io.open(UNVERIFIED_FILE, "a")
        if f then
            for _, acc in ipairs(unverified_list) do f:write(acc .. "\n") end
            f:close()
        end
        log("  💾 Unverified saved → " .. UNVERIFIED_FILE)
    end
end

log("")
if #failed_accounts > 0 then
    log("┌─── ❌ AKUN GAGAL ───────────────────────────┐")
    for i, entry in ipairs(failed_accounts) do
        log("│ " .. i .. ". " .. entry[1] .. " | " .. entry[2])
    end
    log("└──────────────────────────────────────────────┘")
end

log("════════════════════════════════════════════════")

if #active_bots == 0 then
    log("💀 Tidak ada bot aktif. Script berhenti.")
    return
end

-- ================== KEEP ALIVE + INFO DISPLAY ==================
log("🔋 Keep-Alive aktif | Tekan Stop untuk hentikan")
log("")

-- Display bot info setiap 30 detik
local INFO_INTERVAL = 30000
local last_info_time = 0

while true do
    local online = 0
    for _, b in ipairs(active_bots) do
        local c_ok, c = pcall(function() return b:connected() end)
        if c_ok and c then online = online + 1 end
    end
    if online == 0 then
        log("⚠️ Semua bot disconnect. Script berhenti.")
        break
    end

    -- Tampilkan info level & gems setiap INFO_INTERVAL
    if now_ms() - last_info_time >= INFO_INTERVAL then
        last_info_time = now_ms()
        log("")
        log("┌─── 📊 BOT STATUS ─────────────────────────┐")
        log("│ Online: " .. online .. "/" .. #active_bots .. " | " .. datetime.format("%H:%M:%S"))
        log("├────────────────────────────────────────────┤")
        for i, b in ipairs(active_bots) do
            local info_ok, info_str = pcall(function()
                local bname = b:name() or "?"
                local blevel = b.level or 0
                local bgems = b.gems or 0
                local bstatus = b.status or "?"
                local bworld = ""
                pcall(function() bworld = b:get_world_name() or "" end)
                local world_str = bworld ~= "" and (" | 🌍 " .. bworld) or ""
                return "│ " .. string.format("%-20s", bname) .. " Lv." .. blevel .. " | 💎" .. bgems .. " | " .. bstatus .. world_str
            end)
            if info_ok then
                log(info_str)
            else
                local bname = ""
                pcall(function() bname = b:name() or "?" end)
                log("│ " .. bname .. " — ❌ info unavailable")
            end
        end
        log("└────────────────────────────────────────────┘")
    end

    sleep(KEEPALIVE_INTERVAL)
end
