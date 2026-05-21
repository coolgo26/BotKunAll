--[[
  AUTO CLEAR ZENIT v4.0
  Pure findPath movement — game-physics walking.
  Tidak pakai movePoint (yang teleport).
]]

local BlackList = { 110 }

local CONFIG = {
    HIT_DELAY        = 800,
    JITTER_MAX_MS    = 200,
    PATH_TIMEOUT     = 20000,
    PATH_POLL        = 250,
    POST_PATH_DELAY  = 800,   -- Tunggu gravity settle setelah path selesai
    HIT_RANGE        = 3,
}

local client = getClient()

-- ============================================================
-- HELPERS
-- ============================================================

function inBl(id)
    if not id or id == 0 then return true end
    for _, blocked in pairs(BlackList) do
        if id == blocked then return false end
    end
    return true
end

local function isInWorld()
    local nav = client:navigation()
    return nav ~= nil and nav ~= "#menu" and nav ~= ""
end

local function dist(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

local function getTile(point)
    local w = client:world()
    if not w then return nil end
    local ok, tile = pcall(function() return w:tile(point) end)
    return ok and tile or nil
end

local function isSolid(point)
    local tile = getTile(point)
    if not tile then return false end
    return tile.foreground ~= 0 and inBl(tile.foreground)
end

local function isFoothold(point)
    local tile = getTile(point)
    if not tile then return false end
    if tile.foreground ~= 0 and inBl(tile.foreground) then return false end
    -- Tile bawah harus solid (pijakan)
    local below = Vector2i.new(point.x, point.y + 1)
    return isSolid(below)
end

local function shouldBreak(tile)
    if not tile then return false end
    return inBl(tile.foreground) and inBl(tile.background)
        and (tile.foreground ~= 0 or tile.background ~= 0)
end

-- ============================================================
-- MOVEMENT — Pure findPath (game physics)
-- ============================================================

-- Walk pakai pathfinding game (respect gravity & jump arc)
-- TIDAK pakai movePoint (itu teleport, bikin terbang)
local function walkTo(target)
    if not client:connected() then return false end

    local me = client:point()
    if not me then return false end
    if me:equals(target) then return true end

    -- Sudah dekat target? Tunggu sebentar lalu return
    if dist(me, target) <= CONFIG.HIT_RANGE then
        sleep(200)
        return true
    end

    -- Mulai pathfinding
    local started = client:findPath(target)
    if not started then return false end

    -- Tunggu pathfinding selesai TANPA interrupt
    -- (jangan clearPath di tengah jalan, bot akan freeze di udara)
    local elapsed = 0
    while client:pathfinding() and elapsed < CONFIG.PATH_TIMEOUT do
        sleep(CONFIG.PATH_POLL)
        elapsed = elapsed + CONFIG.PATH_POLL

        if not client:connected() then return false end
    end

    -- Hanya force-stop kalau timeout
    if client:pathfinding() then
        client:clearPath()
    end

    -- Tunggu gravity settle (bot turun ke pijakan)
    sleep(CONFIG.POST_PATH_DELAY)

    local final = client:point()
    return final ~= nil and dist(final, target) <= CONFIG.HIT_RANGE
end

-- ============================================================
-- BREAK LOGIC
-- ============================================================

local function tryBreakFrom(stand, target)
    if not walkTo(stand) then return false end

    local me = client:point()
    if not me then return false end
    if dist(me, target) > CONFIG.HIT_RANGE then return false end

    sleep(200 + math.random(0, CONFIG.JITTER_MAX_MS))
    client:hit(target)
    sleep(CONFIG.HIT_DELAY + math.random(0, CONFIG.JITTER_MAX_MS))
    return true
end

local function breakFromSide(target)
    -- Coba dari samping (kiri/kanan), prioritaskan yang ada pijakan
    local stands = {
        Vector2i.new(target.x - 1, target.y),
        Vector2i.new(target.x + 1, target.y),
    }

    -- Sort: stand yang ada pijakan dulu
    table.sort(stands, function(a, b)
        local af = isFoothold(a) and 0 or 1
        local bf = isFoothold(b) and 0 or 1
        return af < bf
    end)

    for _, stand in pairs(stands) do
        if tryBreakFrom(stand, target) then
            return true
        end
    end

    return false
end

-- ============================================================
-- COLLECT
-- ============================================================

local function collectDrops()
    local w = client:world()
    if not w then return end

    local ok, collectables = pcall(function() return w:collectables() end)
    if not ok or not collectables then return end

    for _, c in pairs(collectables) do
        if c then
            pcall(function() client:collect(c.id) end)
            sleep(150)
        end
    end
end

-- ============================================================
-- WORLD SCAN — Foothold map
-- ============================================================

local function scanWorld(width, height)
    local footholds = 0
    local breakable_count = 0
    local breakable_list = {}

    for y = 0, height - 2 do
        for x = 0, width - 1 do
            local pt = Vector2i.new(x, y)

            if isFoothold(pt) then
                footholds = footholds + 1
            end

            local tile = getTile(pt)
            if shouldBreak(tile) then
                breakable_count = breakable_count + 1
                breakable_list[#breakable_list+1] = pt
            end
        end
    end

    return footholds, breakable_count, breakable_list
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
    if not client:connected() then
        print("[clearworld] ❌ Not connected!")
        return
    end

    if not isInWorld() then
        print("[clearworld] ❌ Belum di world!")
        return
    end

    print("[clearworld] ✅ Di world: " .. client:navigation())

    local prefs = client:preferences()
    if prefs then
        prefs.collect = true
        prefs.reconnect = true
    end

    -- Get world size
    local w = client:world()
    local width, height = 100, 60
    if w then
        local ok, size = pcall(function() return w:size() end)
        if ok and size and size.x and size.y then
            width = size.x
            height = size.y
        end
    end

    print(string.format("[clearworld] World: %dx%d", width, height))

    -- Scan world layout
    print("[clearworld] 🔍 Scanning footholds & breakable...")
    local footholds, breakable, list = scanWorld(width, height)
    print(string.format("[clearworld] 🏗 Footholds: %d", footholds))
    print(string.format("[clearworld] 🧱 Breakable: %d", breakable))

    if breakable == 0 then
        print("[clearworld] ✅ World sudah bersih!")
        return
    end

    -- Sort breakable: dari bawah ke atas, dari posisi bot
    local me = client:point()
    if me then
        table.sort(list, function(a, b)
            -- Y besar dulu (paling bawah)
            if a.y ~= b.y then return a.y > b.y end
            -- Lalu yang paling dekat horizontal
            return math.abs(a.x - me.x) < math.abs(b.x - me.x)
        end)
    end

    print("[clearworld] 🚀 Starting clear...")

    local broken = 0
    local skipped = 0

    for i, target in ipairs(list) do
        if not client:connected() then
            print("[clearworld] ⚠️ DC, tunggu reconnect...")
            local waited = 0
            while not client:connected() and waited < 30000 do
                sleep(2000)
                waited = waited + 2000
            end
            if not client:connected() then
                print("[clearworld] ❌ Gagal reconnect")
                return
            end
        end

        -- Re-check tile (mungkin sudah hilang dari proses sebelumnya)
        local tile = getTile(target)
        if not shouldBreak(tile) then
            skipped = skipped + 1
        else
            local failCount = 0
            while shouldBreak(tile) do
                if not client:connected() then break end

                if breakFromSide(target) then
                    failCount = 0
                    broken = broken + 1
                else
                    failCount = failCount + 1
                    if failCount >= 3 then break end
                    sleep(300)
                end

                tile = getTile(target)
            end
        end

        -- Progress log
        if i % 10 == 0 then
            print(string.format("[clearworld] [%d/%d] broken: %d | skipped: %d",
                i, #list, broken, skipped))
            collectDrops()
        end
    end

    collectDrops()
    print(string.format("[clearworld] ✅ Done! broken: %d | skipped: %d", broken, skipped))
end

runThread(main)
print("[START] AUTO CLEAR ZENIT v4.0 thread spawned")
