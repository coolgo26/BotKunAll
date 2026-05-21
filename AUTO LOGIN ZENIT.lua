--[[
  AUTO LOGIN ZENIT v2.0
  
  Format akun: IGN:email:password (password boleh mengandung ":")
  
  Zenith API:
  - addClient({email, password}) → return client
  - client:connect()
  - client:connected() → boolean
  - client:state() → string
  - client:navigation() → string
  - client:warp("name")
  - client:set_auto_reconnect(bool)
]]

-- ================== CONFIG ==================
local accounts = [[
pw0f9f4ec3:pw0f9f4ec3@sweetescape.biz.id:DWO@fY5bN&6gKw
pwc3606664:pwc3606664@sweetescape.biz.id:2oq77dHETcV
pw85ea765c:pw85ea765c@sweetescape.biz.id:zdR5qxntb8%svL
pw456d57c7:pw456d57c7@sweetescape.biz.id:36FRLV@G7wMx
]]

local LOGIN_DELAY      = 1000   -- ms delay antar login
local CONNECT_TIMEOUT  = 20000  -- ms timeout tunggu connected
local POLL_INTERVAL    = 500    -- ms interval cek state
local AUTO_RECONNECT   = true
local WARP_AFTER_LOGIN = false
local VERBOSE          = true

-- ================== HELPER ==================
local function parseAccountLine(line)
    -- Format: IGN:email:password (password bisa mengandung ":")
    local ign, rest = line:match("^([^:]+):(.+)$")
    if not ign or not rest then
        return nil
    end

    local email, password = rest:match("^([^:]+):(.+)$")
    if not email or not password then
        return nil
    end

    ign = ign:match("^%s*(.-)%s*$")
    email = email:match("^%s*(.-)%s*$")
    password = password:match("^%s*(.-)%s*$")

    return { ign = ign, email = email, password = password }
end

-- ================== PARSE ACCOUNTS ==================
local account_list = {}
for line in accounts:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^%-%-") then
        local parsed = parseAccountLine(line)
        if parsed then
            table.insert(account_list, parsed)
        else
            print("⚠️ Format salah, skip: " .. line)
        end
    end
end

print("🔐 AUTO LOGIN ZENIT v2.0")
print("📥 Total akun: " .. #account_list)
print("========================================")

if #account_list == 0 then
    print("❌ Tidak ada akun valid. Cek format: IGN:email:password")
    return
end

-- ================== LOGIN LOOP ==================
local success_count = 0
local fail_count = 0
local bots = {}
local failed_list = {}

for i, acc in ipairs(account_list) do
    print(string.format("🔄 [%d/%d] Login: %s (%s)", i, #account_list, acc.ign, acc.email))

    -- Safe addClient
    local ok, client = pcall(addClient, acc.email, acc.password)
    if not ok or not client then
        local err_msg = tostring(client or "unknown error")
        print("  ❌ addClient gagal: " .. err_msg)
        fail_count = fail_count + 1
        table.insert(failed_list, { acc = acc, reason = "addClient: " .. err_msg })
    else
        -- Tunggu sampai connected
        sleep(2000)

        local connected = false
        local last_state = "Unknown"
        local waited = 0

        while waited < CONNECT_TIMEOUT do
            -- Cek connected()
            local c_ok, is_conn = pcall(function() return client:connected() end)
            if c_ok and is_conn then
                connected = true
                break
            end

            -- Cek navigation
            local nav_ok, nav = pcall(function() return client:navigation() end)
            if nav_ok and nav and nav ~= "" then
                connected = true
                break
            end

            -- Cek state
            local st_ok, st = pcall(function() return client:state() end)
            if st_ok and st then
                last_state = st
                if st == "MenuIdle" or st == "InWorld" then
                    connected = true
                    break
                elseif st == "Failed" or st == "Disconnected" then
                    break
                end
            end

            sleep(POLL_INTERVAL)
            waited = waited + POLL_INTERVAL
        end

        if connected then
            success_count = success_count + 1

            if AUTO_RECONNECT then
                pcall(function() client:set_auto_reconnect(true) end)
            end

            table.insert(bots, { client = client, acc = acc })
            print(string.format("  ✅ [%d] %s OK", success_count, acc.ign))

            -- Warp random (optional)
            if WARP_AFTER_LOGIN then
                sleep(1000)
                local wname = ""
                for _ = 1, math.random(4, 7) do
                    wname = wname .. string.char(math.random(65, 90))
                end
                pcall(function() client:warp(wname) end)
            end
        else
            fail_count = fail_count + 1
            local reason = "Timeout (" .. last_state .. ")"
            if last_state == "Failed" or last_state == "Disconnected" then
                reason = "Rejected/Banned"
            end
            print("  ❌ " .. acc.ign .. " → " .. reason)
            table.insert(failed_list, { acc = acc, reason = reason })
            pcall(function() removeClient(client:name()) end)
        end
    end

    -- Delay antar login
    if i < #account_list then
        sleep(LOGIN_DELAY)
    end
end

-- ================== HASIL ==================
print("")
print("========================================")
print("📊 LOGIN SELESAI!")
print("✅ Berhasil: " .. success_count)
print("❌ Gagal: " .. fail_count)
print("🤖 Bot aktif: " .. #bots)
print("========================================")

if #failed_list > 0 then
    print("")
    print("❌ GAGAL LOGIN:")
    for i, entry in ipairs(failed_list) do
        print(string.format("  %d. %s (%s) → %s", i, entry.acc.ign, entry.acc.email, entry.reason))
    end
end

if #bots > 0 then
    print("")
    print("✅ BOT AKTIF:")
    for i, entry in ipairs(bots) do
        print(string.format("  %d. %s (%s)", i, entry.acc.ign, entry.acc.email))
    end
end

print("========================================")

if #bots == 0 then
    print("💀 Tidak ada bot aktif. Script selesai.")
    return
end

-- ================== KEEP ALIVE ==================
print("🔋 Keep-Alive aktif...")

while true do
    local online = 0
    for _, entry in ipairs(bots) do
        local c_ok, is_conn = pcall(function() return entry.client:connected() end)
        if c_ok and is_conn then
            online = online + 1
        end
    end

    if online == 0 then
        print("⚠️ Semua bot DC. Script selesai.")
        break
    end

    sleep(10000)
end
