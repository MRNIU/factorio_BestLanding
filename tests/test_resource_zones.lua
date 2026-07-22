-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 校验资源区域标记和原型解析。

return function(T)
    local R = require("resource_zones")

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

    local entity_prototypes = {
        ["constant-combinator"] = { type = "constant-combinator" },
        ["iron-ore"] = {
            type = "resource",
            mineable_properties = { products = {{type = "item", name = "iron-ore"}} },
        },
        ["sulfuric-acid-geyser"] = {
            type = "resource",
            mineable_properties = { products = {{type = "fluid", name = "sulfuric-acid"}} },
        },
    }
    local item_prototypes = {
        ["iron-ore"] = { name = "iron-ore" },
        ["artificial-yumako-soil"] = {
            name = "artificial-yumako-soil",
            place_as_tile_result = {
                result = lua_object{name = "artificial-yumako-soil"},
            },
        },
    }
    local tile_prototypes = {
        water = { name = "water", fluid = lua_object{name = "water"} },
        deepwater = { name = "deepwater", fluid = lua_object{name = "water"} },
        lava = { name = "lava", fluid = lua_object{name = "lava"} },
        ["oil-ocean-deep"] = { name = "oil-ocean-deep", fluid = lua_object{name = "heavy-oil"} },
        ["oil-ocean-shallow"] = { name = "oil-ocean-shallow", fluid = lua_object{name = "heavy-oil"} },
        ["ammoniacal-ocean"] = { name = "ammoniacal-ocean", fluid = lua_object{name = "ammoniacal-solution"} },
        ["ammoniacal-ocean-2"] = { name = "ammoniacal-ocean-2", fluid = lua_object{name = "ammoniacal-solution"} },
    }

    local function marker(number, x, y, signal_type, name, count)
        return {
            entity_number = number,
            name = "constant-combinator",
            position = {x = x, y = y},
            player_description = "BestLanding:resource-zone",
            control_behavior = { sections = { sections = {{ filters = {{
                type = signal_type, name = name, quality = "normal", count = count,
            }} }} } },
        }
    end
    local function identity(entity)
        return {position = entity.position, direction = entity.direction or 0}
    end

    local zones, issues = R.collect({
        marker(1, 0, 0, "item", "iron-ore", 1),
        marker(2, 10, 10, "item", "iron-ore", 1),
        marker(3, 20, 0, "fluid", "water", 2),
        marker(4, 30, 10, "fluid", "water", 2),
    }, identity, entity_prototypes)
    T.equal(#issues, 0, "paired markers are valid")
    T.equal(#zones, 2, "two zones collected")
    T.equal(zones[1].signal_type, "fluid", "zones sort by signal type")
    T.truthy(R.position_in_zone({x = 20, y = 0}, zones[1]), "boundary is inclusive")

    local index = R.build_resource_index(entity_prototypes)
    local iron = R.resolve({signal_type="item", signal_name="iron-ore"}, index,
        item_prototypes, tile_prototypes)
    T.equal(iron.entity_resource, "iron-ore", "item product resolves resource")

    local soil = R.resolve({signal_type="item", signal_name="artificial-yumako-soil"},
        index, item_prototypes, tile_prototypes)
    T.equal(soil.place_tile, "artificial-yumako-soil", "all place-as-tile items resolve")

    local acid = R.resolve({signal_type="fluid", signal_name="sulfuric-acid"},
        index, item_prototypes, tile_prototypes)
    T.equal(acid.entity_resource, "sulfuric-acid-geyser", "fluid product resolves geyser")

    local water = R.resolve({signal_type="fluid", signal_name="water"},
        index, item_prototypes, tile_prototypes)
    T.equal(water.offshore_tile, "water", "same-name fluid tile wins")

    local lava = R.resolve({signal_type="fluid", signal_name="lava"},
        index, item_prototypes, tile_prototypes)
    T.equal(lava.offshore_tile, "lava", "LuaObject fluid name resolves lava tile")

    local oil = R.resolve({signal_type="fluid", signal_name="heavy-oil"},
        index, item_prototypes, tile_prototypes)
    T.equal(oil.offshore_tile, "oil-ocean-shallow", "heavy-oil alias resolves")

    local ammonia = R.resolve({signal_type="fluid", signal_name="ammoniacal-solution"},
        index, item_prototypes, tile_prototypes)
    T.equal(ammonia.offshore_tile, "ammoniacal-ocean", "ammonia alias resolves")

    local _, unpaired_issues = R.collect({
        marker(10, 0, 0, "item", "iron-ore", 9),
    }, identity, entity_prototypes)
    T.equal(unpaired_issues[1] and unpaired_issues[1].kind,
        "invalid-marker-pair-count", "unpaired marker is reported")

    local multiple = marker(11, 0, 0, "item", "iron-ore", 10)
    multiple.control_behavior.sections.sections[1].filters[2] = {
        type="item", name="artificial-yumako-soil", quality="normal", count=10,
    }
    local _, multiple_issues = R.collect({multiple}, identity, entity_prototypes)
    T.equal(multiple_issues[1] and multiple_issues[1].kind,
        "invalid-marker-signal-count", "multiple filters are reported")

    local legendary = marker(12, 0, 0, "item", "iron-ore", 11)
    legendary.control_behavior.sections.sections[1].filters[1].quality = "legendary"
    local _, quality_issues = R.collect({legendary}, identity, entity_prototypes)
    T.equal(quality_issues[1] and quality_issues[1].kind,
        "invalid-marker-quality", "non-normal quality is reported")

    local zero = marker(13, 0, 0, "item", "iron-ore", 0)
    local _, count_issues = R.collect({zero}, identity, entity_prototypes)
    T.equal(count_issues[1] and count_issues[1].kind,
        "invalid-marker-zone-id", "non-positive zone id is reported")

    entity_prototypes["rare-spring-a"] = {
        type = "resource",
        mineable_properties={products={{type="fluid", name="rare-slurry"}}},
    }
    entity_prototypes["rare-spring-b"] = {
        type = "resource",
        mineable_properties={products={{type="fluid", name="rare-slurry"}}},
    }
    local ambiguous_index = R.build_resource_index(entity_prototypes)
    local ambiguous, ambiguous_issues = R.resolve(
        {signal_type="fluid", signal_name="rare-slurry"},
        ambiguous_index, item_prototypes, tile_prototypes
    )
    T.equal(ambiguous.entity_resource, nil, "ambiguous resource is unresolved")
    T.equal(ambiguous_issues[1] and ambiguous_issues[1].kind,
        "ambiguous-resource", "ambiguous resource candidates are reported")
end
