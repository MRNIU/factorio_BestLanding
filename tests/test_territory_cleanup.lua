-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 校验撼地虫领地按固定基地 chunk 永久清理。

return function(T)
    local cleanup = require("territory_cleanup")
    local calls = 0
    local cleared_chunks
    local assigned_territory = "not-called"
    local destroy_calls = 0
    local territory = {
        valid = true,
        destroy = function()
            destroy_calls = destroy_calls + 1
        end,
    }
    local surface = {
        get_territory_for_chunk = function()
            return territory
        end,
        set_territory_for_chunks = function(chunks, territory)
            calls = calls + 1
            cleared_chunks = chunks
            assigned_territory = territory
        end,
    }

    local ok = pcall(cleanup.clear_area, surface, {
        left_top = {x = -224, y = -224},
        right_bottom = {x = 224, y = 224},
    })
    T.truthy(ok, "territory cleanup exposes permanent area clearing")
    if not ok then return end

    T.equal(calls, 1, "base chunks are cleared in one API call")
    T.equal(#cleared_chunks, 256,
        "territory cleanup adds one chunk around the 14x14 base")
    T.equal(assigned_territory, nil, "base chunks are assigned no territory")
    T.equal(destroy_calls, 1, "overlapping territory is destroyed exactly once")

    local seen = {}
    local min_x, max_x, min_y, max_y
    for _, chunk in ipairs(cleared_chunks) do
        local key = chunk.x .. "," .. chunk.y
        seen[key] = true
        min_x = not min_x and chunk.x or math.min(min_x, chunk.x)
        max_x = not max_x and chunk.x or math.max(max_x, chunk.x)
        min_y = not min_y and chunk.y or math.min(min_y, chunk.y)
        max_y = not max_y and chunk.y or math.max(max_y, chunk.y)
    end
    T.equal(min_x, -8, "territory cleanup starts one chunk left of the base")
    T.equal(max_x, 7, "territory cleanup ends one chunk right of the base")
    T.equal(min_y, -8, "territory cleanup starts one chunk above the base")
    T.equal(max_y, 7, "territory cleanup ends one chunk below the base")
    T.equal(seen["8,0"], nil, "second chunk beyond the right edge is retained")

    local pipeline_chunks
    local pipeline_surface = {
        valid = true,
        name = "vulcanus",
        request_to_generate_chunks = function() end,
        force_generate_chunk_requests = function() end,
        get_territory_for_chunk = function() return nil end,
        set_territory_for_chunks = function(chunks)
            pipeline_chunks = chunks
        end,
        find_entities = function() return {} end,
        set_tiles = function() end,
    }
    local previous_log = log
    log = function() end
    require("clean_area").run(pipeline_surface, {
        default_tile = "volcanic-soil-dark",
        territory_cleanup = true,
    })
    log = previous_log
    T.equal(#pipeline_chunks, 256,
        "clean_area pipeline clears the Level 1 chunks plus one outer ring")

    local planets = require("planets")
    T.equal(planets.vulcanus.territory_cleanup, true,
        "Vulcanus enables permanent territory cleanup")
    T.equal(planets.vulcanus.enemy_cleanup, nil,
        "Vulcanus does not scan Demolisher body entities")
end
