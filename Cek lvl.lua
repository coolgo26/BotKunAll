--[[
  CEK LEVEL & GEMS — Mirai Lua API
  Login akun → cek level & gems → disconnect.
  Jalankan di Global Executor.
]]

-- ================== KONFIGURASI ==================
local accounts = {
    "email:pass",
    "email:pass",
}

local CONNECT_TIMEOUT = 20000
local POLL_INTERVAL   = 300
local LOGIN_DELAY     = 1000

-- ================== VALIDASI ==================
if EXECUTION_SCOPE ~= "global" then
    log("❌ Script HANYA bisa dijalankan di Global Executor!")
    return
end

-- ================== MAIN ==================
log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
log("📊 CEK LEVEL & GEMS")
log("📥 Total akun: " .. #accounts)
log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

local results = {}
local total_gems = 0

for i, acc in ipairs(accounts) do
    local email, pass = acc:match("^([^:]+):(.+)$")
    if not email or not pass then
        log("⚠️ Format salah baris " .. i .. ": " .. acc)
    else
        log("🔄 [" .. i .. "/" .. #accounts .. "] Login: " .. email)

        local ok, result = pcall(addClient, email, pass)
        if not ok or not result then
            log("❌ Gagal login: " .. email)
            results[#results+1] = { no = i, email = email, name = "?", level = 0, gems = 0, error = true }
        else
            local bot = result

            -- Connect
            pcall(function() bot:connect() end)

            -- Tunggu connected
            local start = now_ms()
            local connected = false

            while now_ms() - start < CONNECT_TIMEOUT do
                local state = bot:state()
                if state == "MenuIdle" or state == "InWorld" then
                    connected = true
                    break
                elseif state == "Failed" then
                    break
                end
                sleep(POLL_INTERVAL)
            end

            if connected then
                local name = bot:name() or email

                -- Ambil level & gems via get_account()
                local lvl = 0
                local gems = 0
                local acc_ok, acc_data = pcall(bot.get_account, bot)
                if acc_ok and acc_data then
                    lvl = acc_data.level or acc_data.lvl or acc_data.player_level or 0
                    gems = acc_data.gems or 0
                end

                total_gems = total_gems + gems

                results[#results+1] = {
                    no    = i,
                    email = email,
                    name  = name,
                    level = lvl,
                    gems  = gems,
                }

                log(string.format("✅ #%d %s | Lv: %d | 💎 %d", i, name, lvl, gems))
            else
                log("❌ Timeout: " .. email)
                results[#results+1] = { no = i, email = email, name = "?", level = 0, gems = 0, error = true }
            end

            -- Disconnect & remove setelah cek
            pcall(function() bot:disconnect() end)
            sleep(500)
            pcall(function() removeClient(bot:name()) end)
        end
    end

    sleep(LOGIN_DELAY)
end

-- ================== HASIL ==================
log("")
log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
log("� HASIL CEK LEVEL & GEMS")
log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
log(string.format("%-4s %-20s %-6s %-10s", "#", "Name", "Level", "Gems"))
log("────────────────────────────────────────")

for _, r in ipairs(results) do
    if r.error then
        log(string.format("%-4d %-20s %-6s %-10s", r.no, r.email, "ERR", "ERR"))
    else
        log(string.format("%-4d %-20s %-6d 💎 %-10d", r.no, r.name, r.level, r.gems))
    end
end

log("────────────────────────────────────────")
log("📊 Total Akun: " .. #results)
log("💎 Total Gems: " .. total_gems)
log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
