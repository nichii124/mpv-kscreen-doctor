local luaunit = require('luaunit')

local function best_fit(target, options)
    local best = { distance = math.huge, id = nil }
    for mul = 1, 3 do
        for _, mode in pairs(options) do
            local offset = math.abs(target * mul - mode.rate)
            if offset < best.distance then
                best = {
                    distance = offset,
                    id = mode.id,
                }
            end
        end
    end
    return best.id
end

TestBestFit = {}

function TestBestFit:test_simple_case()
    local modes = {
        {id = 1, rate = 59.94},
        {id = 2, rate = 60.0},
        {id = 3, rate = 120.0},
    }
    luaunit.assertEquals(best_fit(24.0, modes), 1)
end

os.exit(luaunit.LuaUnit.run())

