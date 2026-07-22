-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 用伪造 surface 校验资源设备分派和直接执行。

return function(T)
    package.loaded.place_resources = nil
    package.loaded.resource_zones = nil

    -- 用非 table 对象模拟 Factorio LuaObject 的属性访问。
    local object_fields = setmetatable({}, {__mode = "k"})
    local object_metatable = {
        __index = function(object, key)
            return object_fields[object][key]
        end,
    }
    local function lua_object(fields)
        local object = coroutine.create(function() end)
        object_fields[object] = fields
        debug.setmetatable(object, object_metatable)
        return object
    end

    local logs = {}
    _G.log = function(message) logs[#logs + 1] = message end
    _G.prototypes = {
        entity = {
            ["constant-combinator"] = {type = "constant-combinator"},
            ["big-mining-drill"] = {
                type = "mining-drill",
                get_mining_drill_radius = function() return 1 end,
            },
            pumpjack = {type = "mining-drill"},
            ["agricultural-tower"] = {
                type = "agricultural-tower",
                agricultural_tower_radius = 3,
                growth_grid_tile_size = 3,
                collision_box = {
                    left_top = {x = -1.2, y = -1.2},
                    right_bottom = {x = 1.2, y = 1.2},
                },
            },
            ["offshore-pump"] = {type = "offshore-pump", fluid_source_offset = {x = 0, y = -1}},
            ["iron-ore"] = {
                type = "resource",
                mineable_properties = {products = {{type="item", name="iron-ore"}}},
            },
            ["copper-ore"] = {
                type = "resource",
                mineable_properties = {products = {{type="item", name="copper-ore"}}},
            },
            ["crude-oil"] = {
                type = "resource",
                mineable_properties = {products = {{type="fluid", name="crude-oil"}}},
            },
        },
        item = {
            ["iron-ore"] = {name="iron-ore"},
            ["copper-ore"] = {name="copper-ore"},
            ["artificial-yumako-soil"] = {
                name = "artificial-yumako-soil",
                place_as_tile_result = {
                    result = lua_object{name="artificial-yumako-soil"},
                },
            },
        },
        tile = {
            water = {name="water", fluid=lua_object{name="water"}},
        },
    }

    local surface = {valid=true, name="vulcanus", created={}, tile_batches={}}
    function surface.create_entity(params)
        surface.created[#surface.created + 1] = params
        return {valid=true}
    end
    function surface.set_tiles(tiles)
        surface.tile_batches[#surface.tile_batches + 1] = tiles
    end

    local function marker(number, x, y, signal_type, name, count)
        return {
            entity_number=number, name="constant-combinator", position={x=x, y=y},
            player_description="BestLanding:resource-zone",
            control_behavior={sections={sections={{filters={{
                type=signal_type, name=name, quality="normal", count=count,
            }}}}}},
        }
    end
    local function identity_transform(entity)
        return {position=entity.position, direction=entity.direction or 0}
    end
    local function count_created(created, name)
        local count = 0
        for _, params in ipairs(created) do
            if params.name == name then count = count + 1 end
        end
        return count
    end
    local function count_tiles(batches, name)
        local count = 0
        for _, batch in ipairs(batches) do
            for _, tile in ipairs(batch) do
                if tile.name == name then count = count + 1 end
            end
        end
        return count
    end
    local function tile_bounds(batches, name)
        local bounds = {}
        for _, batch in ipairs(batches) do
            for _, tile in ipairs(batch) do
                if tile.name == name then
                    local x, y = tile.position[1], tile.position[2]
                    bounds.left = bounds.left and math.min(bounds.left, x) or x
                    bounds.right = bounds.right and math.max(bounds.right, x) or x
                    bounds.top = bounds.top and math.min(bounds.top, y) or y
                    bounds.bottom = bounds.bottom and math.max(bounds.bottom, y) or y
                end
            end
        end
        return bounds
    end

    local entities = {
        marker(1, -2, -2, "item", "iron-ore", 1),
        marker(2, 2, 2, "item", "iron-ore", 1),
        {entity_number=3, name="big-mining-drill", position={x=0.5, y=0.5}},
        marker(4, 9, -2, "item", "artificial-yumako-soil", 2),
        marker(5, 13, 2, "item", "artificial-yumako-soil", 2),
        {entity_number=6, name="agricultural-tower", position={x=11.5, y=0.5}},
        marker(7, 19, -2, "fluid", "crude-oil", 3),
        marker(8, 23, 2, "fluid", "crude-oil", 3),
        {entity_number=9, name="pumpjack", position={x=21.5, y=0.5}},
        marker(10, 29, -2, "fluid", "water", 4),
        marker(11, 35, 2, "fluid", "water", 4),
        {entity_number=12, name="offshore-pump", position={x=31.5, y=0.5}, direction=0},
        {entity_number=13, name="offshore-pump", position={x=33.5, y=0.5}, direction=0},
    }
    local P = require("place_resources")
    P.place_blueprint_resources(surface, entities, identity_transform)

    T.equal(count_created(surface.created, "iron-ore"), 9,
        "radius-one drill attempts a 3x3 ore patch")
    T.equal(count_created(surface.created, "crude-oil"), 1,
        "pumpjack attempts one fluid resource")
    T.equal(count_tiles(surface.tile_batches, "artificial-yumako-soil"), 441,
        "agricultural tower covers its full 21x21 growth grid")
    local soil_bounds = tile_bounds(surface.tile_batches, "artificial-yumako-soil")
    T.equal(soil_bounds.left, 1, "agricultural soil starts at the left growth edge")
    T.equal(soil_bounds.right, 21, "agricultural soil ends at the right growth edge")
    T.equal(soil_bounds.top, -10, "agricultural soil starts at the top growth edge")
    T.equal(soil_bounds.bottom, 10, "agricultural soil ends at the bottom growth edge")
    T.equal(count_tiles(surface.tile_batches, "water"), 3,
        "two separated source tiles produce their minimal bounding row")

    local conflict_surface = {valid=true, name="nauvis", created={}, tile_batches={}}
    function conflict_surface.create_entity(params)
        conflict_surface.created[#conflict_surface.created + 1] = params
        return {valid=true}
    end
    function conflict_surface.set_tiles(tiles)
        conflict_surface.tile_batches[#conflict_surface.tile_batches + 1] = tiles
    end
    local conflicting = {
        marker(20, -2, -2, "item", "iron-ore", 1),
        marker(21, 2, 2, "item", "iron-ore", 1),
        marker(22, -2, -2, "item", "iron-ore", 2),
        marker(23, 2, 2, "item", "iron-ore", 2),
        marker(24, -2, -2, "item", "copper-ore", 3),
        marker(25, 2, 2, "item", "copper-ore", 3),
        {entity_number=26, name="big-mining-drill", position={x=0.5, y=0.5}},
    }
    P.place_blueprint_resources(conflict_surface, conflicting, identity_transform)
    T.equal(count_created(conflict_surface.created, "iron-ore"), 18,
        "repeated applicable zones are not deduplicated")
    T.equal(count_created(conflict_surface.created, "copper-ore"), 9,
        "conflicting target still executes")
    local conflict_logged = false
    for _, message in ipairs(logs) do
        if message:find("conflicting targets", 1, true) then conflict_logged = true end
    end
    T.truthy(conflict_logged, "conflicting targets are diagnosed")
end
