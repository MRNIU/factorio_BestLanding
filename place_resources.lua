-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 根据起始蓝图里的矿机、抽取泵和抽油机自动铺设对应资源。

local C = require("constants")

local M = {}

local PUMPJACK_NAME = "pumpjack"
local RESOURCE_ZONE_DESCRIPTION = "BestLanding:resource-zone"
local DEFAULT_COLUMNS_PER_RESOURCE = 2

local function place_tile_area(surface, tile_name, area, placed)
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local key = x .. "," .. y
            if not placed[key] then
                tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
                placed[key] = true
            end
        end
    end
    if #tiles > 0 then
        surface.set_tiles(tiles)
    end
end

local function place_fluid_source(surface, resource_name, position, placed)
    if not prototypes.entity[resource_name] then
        log(("[BestLanding] place_fluid_source: resource prototype %s not found, skipping")
            :format(tostring(resource_name)))
        return
    end

    -- 蓝图里的泵类实体通常落在半格中心；资源 tile 要取实体所在 tile，
    -- 不能四舍五入到右下角，否则 pumpjack 会找不到流体源。
    local x = math.floor(position.x)
    local y = math.floor(position.y)
    local key = x .. "," .. y
    if placed[key] then return end

    surface.create_entity {
        name                      = resource_name,
        position                  = { x, y },
        amount                    = C.FLUID_AMOUNT,
        raise_built               = false,
        create_build_effect_smoke = false,
    }
    placed[key] = true
end

local function place_ore_tiles(surface, resource_name, area, placed)
    if not prototypes.entity[resource_name] then
        log(("[BestLanding] place_ore_tiles: resource prototype %s not found, skipping")
            :format(tostring(resource_name)))
        return
    end

    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local key = x .. "," .. y
            if not placed[key] then
                surface.create_entity {
                    name                      = resource_name,
                    position                  = { x, y },
                    amount                    = C.ORE_PER_TILE,
                    raise_built               = false,
                    create_build_effect_smoke = false,
                }
                placed[key] = true
            end
        end
    end
end

local function get_drill_radius(entity)
    local proto = prototypes.entity[entity.name]
    if not (proto and proto.type == "mining-drill" and entity.name ~= PUMPJACK_NAME) then
        return nil
    end
    if proto.get_mining_drill_radius then
        if entity.quality then
            return proto.get_mining_drill_radius(entity.quality)
        end
        return proto.get_mining_drill_radius()
    end
    return proto.mining_drill_radius
end

--------------------------------------------------------------------------------
-- 蓝图资源驱动实体的资源铺设

local function is_solid_resource_drill(entity)
    return get_drill_radius(entity) ~= nil
end

local function is_resource_zone_marker(entity)
    local proto = prototypes.entity[entity.name]
    return proto
        and proto.type == "constant-combinator"
        and entity.player_description == RESOURCE_ZONE_DESCRIPTION
end

local function resource_marker_signal(entity)
    local sections = entity.control_behavior
        and entity.control_behavior.sections
        and entity.control_behavior.sections.sections
    if not sections then
        return nil, nil, "missing constant-combinator sections"
    end

    local signal
    for _, section in pairs(sections) do
        for _, filter in pairs(section.filters or {}) do
            if filter.name then
                if signal then
                    return nil, nil, "more than one signal is configured"
                end
                signal = filter
            end
        end
    end

    if not signal then
        return nil, nil, "no signal is configured"
    end
    if signal.type and signal.type ~= "item" then
        return nil, nil, "the signal is not an item signal"
    end
    if signal.quality and signal.quality ~= "normal" then
        return nil, nil, "the signal quality is not normal"
    end

    local resource = prototypes.entity[signal.name]
    if not (resource and resource.type == "resource") then
        return nil, nil, ("%s is not a resource entity prototype"):format(signal.name)
    end

    local zone_id = signal.count or 1
    if type(zone_id) ~= "number" or zone_id < 1 or zone_id % 1 ~= 0 then
        return nil, nil, "the signal count is not a positive integer zone id"
    end

    return signal.name, zone_id
end

local function is_fluid_resource_drill(entity)
    return entity.name == PUMPJACK_NAME
end

local function is_offshore_pump(entity)
    local proto = prototypes.entity[entity.name]
    return proto and proto.type == "offshore-pump"
end

local function mining_area(position, radius)
    return {
        left_top = {
            x = math.floor(position.x - radius),
            y = math.floor(position.y - radius),
        },
        right_bottom = {
            x = math.ceil(position.x + radius),
            y = math.ceil(position.y + radius),
        },
    }
end

local function position_in_zone(position, zone)
    return position.x >= zone.left
        and position.x <= zone.right
        and position.y >= zone.top
        and position.y <= zone.bottom
end

local function collect_resource_zones(surface, entities, transform)
    local marker_groups = {}

    for _, entity in pairs(entities or {}) do
        if is_resource_zone_marker(entity) then
            local resource_name, zone_id, reason = resource_marker_signal(entity)
            if resource_name then
                local resource_groups = marker_groups[resource_name]
                if not resource_groups then
                    resource_groups = {}
                    marker_groups[resource_name] = resource_groups
                end

                local markers = resource_groups[zone_id]
                if not markers then
                    markers = {}
                    resource_groups[zone_id] = markers
                end
                markers[#markers + 1] = transform(entity).position
            else
                log(("[BestLanding] resource-zone marker %s on %s is invalid: %s; skipping")
                    :format(tostring(entity.entity_number), surface.name, reason))
            end
        end
    end

    local zones = {}
    for resource_name, resource_groups in pairs(marker_groups) do
        for zone_id, markers in pairs(resource_groups) do
            if #markers == 2 then
                zones[#zones + 1] = {
                    resource_name = resource_name,
                    zone_id = zone_id,
                    left = math.min(markers[1].x, markers[2].x),
                    right = math.max(markers[1].x, markers[2].x),
                    top = math.min(markers[1].y, markers[2].y),
                    bottom = math.max(markers[1].y, markers[2].y),
                }
            else
                log(("[BestLanding] resource-zone %s x %d on %s has %d markers instead of 2; skipping")
                    :format(resource_name, zone_id, surface.name, #markers))
            end
        end
    end

    table.sort(zones, function(a, b)
        if a.resource_name ~= b.resource_name then
            return a.resource_name < b.resource_name
        end
        return a.zone_id < b.zone_id
    end)
    return zones
end

local function collect_solid_drills(entities, transform)
    local drills = {}
    for _, entity in pairs(entities or {}) do
        if is_solid_resource_drill(entity) then
            local transformed = transform(entity)
            drills[#drills + 1] = {
                entity_number = entity.entity_number,
                name = entity.name,
                position = transformed.position,
                radius = get_drill_radius(entity),
            }
        end
    end

    table.sort(drills, function(a, b)
        if a.position.x ~= b.position.x then return a.position.x < b.position.x end
        if a.position.y ~= b.position.y then return a.position.y < b.position.y end
        return (a.entity_number or 0) < (b.entity_number or 0)
    end)
    return drills
end

local function place_marked_ore_resources(surface, entities, transform)
    local zones = collect_resource_zones(surface, entities, transform)
    if #zones == 0 then
        log(("[BestLanding] blueprint_mining: no valid resource zones found on %s")
            :format(surface.name))
        return
    end

    local placed = {}
    local assigned = 0
    for _, drill in ipairs(collect_solid_drills(entities, transform)) do
        local resource_name
        local conflicting_resource

        for _, zone in ipairs(zones) do
            if position_in_zone(drill.position, zone) then
                if resource_name and resource_name ~= zone.resource_name then
                    conflicting_resource = zone.resource_name
                    break
                end
                resource_name = zone.resource_name
            end
        end

        if conflicting_resource then
            log(("[BestLanding] blueprint mining drill %s on %s belongs to conflicting %s and %s zones; skipping")
                :format(
                    tostring(drill.entity_number),
                    surface.name,
                    resource_name,
                    conflicting_resource
                ))
        elseif resource_name then
            place_ore_tiles(
                surface,
                resource_name,
                mining_area(drill.position, drill.radius),
                placed
            )
            assigned = assigned + 1
        end
    end

    log(("[BestLanding] blueprint_mining: seeded %d drills from %d resource zones on %s")
        :format(assigned, #zones, surface.name))
end

local function cardinal_direction(direction)
    return (math.floor(((direction or 0) % 16 + 2) / 4) * 4) % 16
end

local function rotate_vector(vector, direction)
    local x, y = vector.x or vector[1], vector.y or vector[2]
    direction = cardinal_direction(direction)
    if direction == 4 then
        x, y = -y, x
    elseif direction == 8 then
        x, y = -x, -y
    elseif direction == 12 then
        x, y = y, -x
    end
    return { x = x, y = y }
end

local function offset_position(position, offset)
    return { x = position.x + offset.x, y = position.y + offset.y }
end

local function offshore_source_tile(entity)
    local proto = prototypes.entity[entity.name]
    local offset = proto and proto.fluid_source_offset
    if not offset then return nil end

    local source = offset_position(entity.position, rotate_vector(offset, entity.direction or 0))
    return { x = math.floor(source.x), y = math.floor(source.y) }
end

local function collect_columns(entities, transform, predicate, build)
    local columns = {}
    local by_key = {}

    for _, entity in pairs(entities or {}) do
        if predicate(entity) then
            local transformed = transform(entity)
            local position = transformed.position
            local key = math.floor(position.x + 0.5)
            local column = by_key[key]
            if not column then
                column = { key = key, drills = {} }
                by_key[key] = column
                columns[#columns + 1] = column
            end
            column.drills[#column.drills + 1] = build(entity, transformed)
        end
    end

    table.sort(columns, function(a, b) return a.key < b.key end)
    return columns
end

local function column_resource_name(resources, columns_per_resource, column_index, repeat_last_resource)
    local resource_index = math.floor((column_index - 1) / columns_per_resource) + 1
    if repeat_last_resource and #resources > 0 and resource_index > #resources then
        resource_index = #resources
    end
    return resources[resource_index]
end

local function place_column_resources(surface, label, layout, columns, place, opts)
    if not layout then return end

    local resources = layout.resources or {}
    local columns_per_resource = layout.columns_per_resource or DEFAULT_COLUMNS_PER_RESOURCE
    local repeat_last_resource = opts and opts.repeat_last_resource == true

    if #columns == 0 then
        log(("[BestLanding] %s: no matching blueprint entities found on %s")
            :format(label, surface.name))
        return
    end

    local placed = {}
    local assigned = 0
    for column_index, column in ipairs(columns) do
        local resource_name = column_resource_name(
            resources,
            columns_per_resource,
            column_index,
            repeat_last_resource
        )
        if resource_name then
            for _, drill in ipairs(column.drills) do
                place(surface, resource_name, drill, placed)
                assigned = assigned + 1
            end
        else
            log(("[BestLanding] %s: no resource configured for column %d on %s")
                :format(label, column_index, surface.name))
        end
    end

    log(("[BestLanding] %s: seeded %d entities across %d columns on %s")
        :format(label, assigned, #columns, surface.name))
end

local function extend_bounds(bounds, position)
    if not position then return end

    if not bounds.left_top then
        bounds.left_top = { x = position.x, y = position.y }
        bounds.right_bottom = { x = position.x + 1, y = position.y + 1 }
        return
    end

    if position.x < bounds.left_top.x then bounds.left_top.x = position.x end
    if position.y < bounds.left_top.y then bounds.left_top.y = position.y end
    if position.x + 1 > bounds.right_bottom.x then bounds.right_bottom.x = position.x + 1 end
    if position.y + 1 > bounds.right_bottom.y then bounds.right_bottom.y = position.y + 1 end
end

local function place_offshore_pump_resources(surface, cfg, entities, transform)
    local layout = cfg.blueprint_tile_resources
    if not layout then return end

    local columns = collect_columns(entities, transform, is_offshore_pump, function(entity, transformed)
        return {
            name = entity.name,
            position = transformed.position,
            direction = transformed.direction,
        }
    end)
    if #columns == 0 then
        log(("[BestLanding] blueprint_tile_resources: no matching blueprint entities found on %s")
            :format(surface.name))
        return
    end

    local resources = layout.resources or {}
    local columns_per_resource = layout.columns_per_resource or DEFAULT_COLUMNS_PER_RESOURCE
    local bounds_by_resource = {}
    local assigned = 0

    for column_index, column in ipairs(columns) do
        local tile_name = column_resource_name(resources, columns_per_resource, column_index, true)
        if tile_name then
            local bounds = bounds_by_resource[tile_name]
            if not bounds then
                bounds = {}
                bounds_by_resource[tile_name] = bounds
            end
            for _, pump in ipairs(column.drills) do
                extend_bounds(bounds, offshore_source_tile(pump))
                assigned = assigned + 1
            end
        else
            log(("[BestLanding] blueprint_tile_resources: no resource configured for column %d on %s")
                :format(column_index, surface.name))
        end
    end

    for tile_name, bounds in pairs(bounds_by_resource) do
        if bounds.left_top then
            place_tile_area(surface, tile_name, bounds, {})
        end
    end

    log(("[BestLanding] blueprint_tile_resources: seeded %d entities across %d columns on %s")
        :format(assigned, #columns, surface.name))
end

function M.place_blueprint_resources(surface, cfg, entities, transform)
    if not (surface and surface.valid and cfg) then return end

    place_marked_ore_resources(surface, entities, transform)

    place_column_resources(
        surface,
        "blueprint_fluid_sources",
        cfg.blueprint_fluid_sources,
        collect_columns(entities, transform, is_fluid_resource_drill, function(entity, transformed)
            return {
                name = entity.name,
                position = transformed.position,
            }
        end),
        function(s, resource_name, drill, placed)
            place_fluid_source(s, resource_name, drill.position, placed)
        end
    )

    place_offshore_pump_resources(surface, cfg, entities, transform)
end

return M
