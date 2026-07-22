-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 按 Mining 蓝图里的统一资源区域标记铺设资源实体和地格。

local zones = require("resource_zones")
local C = require("constants")

local M = {}

local PUMPJACK_NAME = "pumpjack"
local cached_resource_index

local function resource_index()
    if not cached_resource_index then
        cached_resource_index = zones.build_resource_index(prototypes.entity)
    end
    return cached_resource_index
end

local function log_issues(surface, issues)
    for _, item in ipairs(issues) do
        log(("[BestLanding] resource placement on %s: %s")
            :format(surface.name, item.message))
    end
end

local function device_key(entity, transformed)
    if entity.entity_number then
        return ("%s#%s"):format(entity.name, tostring(entity.entity_number))
    end
    return ("%s@%.3f,%.3f"):format(
        entity.name, transformed.position.x, transformed.position.y
    )
end

local function zone_key(zone)
    return ("%s:%s:%s:%d"):format(
        zone.signal_type, zone.signal_name, zone.quality, zone.zone_id
    )
end

local function get_mining_drill_radius(entity, prototype)
    if prototype.get_mining_drill_radius then
        if entity.quality then
            return prototype.get_mining_drill_radius(entity.quality)
        end
        return prototype.get_mining_drill_radius()
    end
    return prototype.mining_drill_radius
end

local function area_around(position, radius)
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
    return {x = x, y = y}
end

local function agricultural_area(position, direction, prototype)
    local collision_box = prototype.collision_box
    local radius = prototype.agricultural_tower_radius
    if not (collision_box and radius) then return nil end

    local corners = {
        {x = collision_box.left_top.x, y = collision_box.left_top.y},
        {x = collision_box.right_bottom.x, y = collision_box.left_top.y},
        {x = collision_box.left_top.x, y = collision_box.right_bottom.y},
        {x = collision_box.right_bottom.x, y = collision_box.right_bottom.y},
    }
    local left, right, top, bottom
    for _, corner in ipairs(corners) do
        local rotated = rotate_vector(corner, direction)
        left = left and math.min(left, rotated.x) or rotated.x
        right = right and math.max(right, rotated.x) or rotated.x
        top = top and math.min(top, rotated.y) or rotated.y
        bottom = bottom and math.max(bottom, rotated.y) or rotated.y
    end

    local growth_grid_size = prototype.growth_grid_tile_size or 3
    local extension = radius * growth_grid_size
    return {
        left_top = {
            x = math.floor(position.x + left - extension),
            y = math.floor(position.y + top - extension),
        },
        right_bottom = {
            x = math.ceil(position.x + right + extension),
            y = math.ceil(position.y + bottom + extension),
        },
    }
end

local function offshore_source_tile(device)
    local prototype = prototypes.entity[device.name]
    local offset = prototype and prototype.fluid_source_offset
    if not offset then return nil end
    local rotated = rotate_vector(offset, device.direction)
    return {
        x = math.floor(device.position.x + rotated.x),
        y = math.floor(device.position.y + rotated.y),
    }
end

local function sort_devices(devices)
    table.sort(devices, function(a, b)
        if a.position.x ~= b.position.x then return a.position.x < b.position.x end
        if a.position.y ~= b.position.y then return a.position.y < b.position.y end
        return a.key < b.key
    end)
end

local function collect_devices(entities, transform)
    local devices = {
        solid_drills = {},
        pumpjacks = {},
        agricultural_towers = {},
        offshore_pumps = {},
    }

    for _, entity in pairs(entities or {}) do
        local prototype = prototypes.entity[entity.name]
        if prototype then
            local category
            if entity.name == PUMPJACK_NAME then
                category = "pumpjacks"
            elseif prototype.type == "mining-drill" then
                category = "solid_drills"
            elseif prototype.type == "agricultural-tower" then
                category = "agricultural_towers"
            elseif prototype.type == "offshore-pump" then
                category = "offshore_pumps"
            end

            if category then
                local transformed = transform(entity)
                local device = {
                    key = device_key(entity, transformed),
                    name = entity.name,
                    position = transformed.position,
                    direction = transformed.direction or 0,
                }
                if category == "solid_drills" then
                    device.radius = get_mining_drill_radius(entity, prototype)
                    if device.radius then
                        devices[category][#devices[category] + 1] = device
                    end
                elseif category == "agricultural_towers" then
                    device.area = agricultural_area(
                        device.position, device.direction, prototype
                    )
                    if device.area then
                        devices[category][#devices[category] + 1] = device
                    end
                else
                    devices[category][#devices[category] + 1] = device
                end
            end
        end
    end

    for _, category in pairs(devices) do sort_devices(category) end
    return devices
end

local function append_resource_areas(operations, zone, target, devices)
    if not target then return end
    local key = zone_key(zone)
    for _, device in ipairs(devices) do
        if zones.position_in_zone(device.position, zone) then
            operations[#operations + 1] = {
                kind = "resource-area",
                target = target,
                amount = C.ORE_PER_TILE,
                area = area_around(device.position, device.radius),
                device_key = device.key,
                zone_key = key,
            }
        end
    end
end

local function append_resource_points(operations, zone, target, devices)
    if not target then return end
    local key = zone_key(zone)
    for _, device in ipairs(devices) do
        if zones.position_in_zone(device.position, zone) then
            operations[#operations + 1] = {
                kind = "resource-point",
                target = target,
                amount = C.FLUID_AMOUNT,
                position = {
                    x = math.floor(device.position.x),
                    y = math.floor(device.position.y),
                },
                device_key = device.key,
                zone_key = key,
            }
        end
    end
end

local function append_tower_tiles(operations, zone, target, devices)
    if not target then return end
    local key = zone_key(zone)
    for _, device in ipairs(devices) do
        if zones.position_in_zone(device.position, zone) then
            operations[#operations + 1] = {
                kind = "tile-area",
                target = target,
                area = device.area,
                device_key = device.key,
                zone_key = key,
            }
        end
    end
end

local function append_offshore_tiles(operations, zone, target, devices)
    if not target then return end
    local bounds
    local device_keys = {}
    for _, device in ipairs(devices) do
        if zones.position_in_zone(device.position, zone) then
            local source = offshore_source_tile(device)
            if source then
                device_keys[#device_keys + 1] = device.key
                if not bounds then
                    bounds = {
                        left_top = {x = source.x, y = source.y},
                        right_bottom = {x = source.x + 1, y = source.y + 1},
                    }
                else
                    bounds.left_top.x = math.min(bounds.left_top.x, source.x)
                    bounds.left_top.y = math.min(bounds.left_top.y, source.y)
                    bounds.right_bottom.x = math.max(bounds.right_bottom.x, source.x + 1)
                    bounds.right_bottom.y = math.max(bounds.right_bottom.y, source.y + 1)
                end
            end
        end
    end
    if bounds then
        operations[#operations + 1] = {
            kind = "tile-area",
            target = target,
            area = bounds,
            device_keys = device_keys,
            zone_key = zone_key(zone),
        }
    end
end

local function append_zone_operations(operations, zone, targets, devices)
    if zone.signal_type == "item" then
        append_resource_areas(
            operations, zone, targets.entity_resource, devices.solid_drills
        )
        append_tower_tiles(
            operations, zone, targets.place_tile, devices.agricultural_towers
        )
    elseif zone.signal_type == "fluid" then
        append_resource_points(
            operations, zone, targets.entity_resource, devices.pumpjacks
        )
        append_offshore_tiles(
            operations, zone, targets.offshore_tile, devices.offshore_pumps
        )
    end
end

local function ordered_pair(first, second)
    if first < second then return first, second end
    return second, first
end

local function record_conflict(conflicts, domain, first, second, example)
    first, second = ordered_pair(first, second)
    local key = domain .. "\0" .. first .. "\0" .. second
    local conflict = conflicts[key]
    if not conflict then
        conflict = {
            domain = domain,
            first = first,
            second = second,
            count = 0,
            example = example,
        }
        conflicts[key] = conflict
    end
    conflict.count = conflict.count + 1
end

local function operation_device_keys(operation)
    if operation.device_keys then return operation.device_keys end
    return {operation.device_key}
end

local function operation_domain(operation)
    if operation.kind == "tile-area" then return "tile" end
    return "resource"
end

local function each_operation_position(operation, callback)
    if operation.kind == "resource-point" then
        callback(operation.position.x, operation.position.y)
        return
    end
    for x = operation.area.left_top.x, operation.area.right_bottom.x - 1 do
        for y = operation.area.left_top.y, operation.area.right_bottom.y - 1 do
            callback(x, y)
        end
    end
end

local function diagnose_operations(surface, operations)
    local conflicts = {}
    local device_targets = {}
    local footprint_targets = {resource = {}, tile = {}}

    for _, operation in ipairs(operations) do
        local domain = operation_domain(operation)
        for _, key in ipairs(operation_device_keys(operation)) do
            local map_key = domain .. "\0" .. key
            local targets = device_targets[map_key]
            if not targets then
                targets = {}
                device_targets[map_key] = targets
            end
            for existing in pairs(targets) do
                if existing ~= operation.target then
                    record_conflict(
                        conflicts, domain .. " device", existing, operation.target, key
                    )
                end
            end
            targets[operation.target] = true
        end

        each_operation_position(operation, function(x, y)
            local position_key = x .. "," .. y
            local targets = footprint_targets[domain][position_key]
            if not targets then
                targets = {}
                footprint_targets[domain][position_key] = targets
            end
            for existing in pairs(targets) do
                if existing ~= operation.target then
                    record_conflict(
                        conflicts,
                        domain .. " footprint",
                        existing,
                        operation.target,
                        position_key
                    )
                end
            end
            targets[operation.target] = true
        end)
    end

    local keys = {}
    for key in pairs(conflicts) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local conflict = conflicts[key]
        log(("[BestLanding] resource placement on %s: conflicting targets %s and %s "
            .. "share %d %s assignments; first example %s"):format(
            surface.name,
            conflict.first,
            conflict.second,
            conflict.count,
            conflict.domain,
            conflict.example
        ))
    end
end

local function record_failure(failures, target, x, y)
    local failure = failures[target]
    if not failure then
        failure = {count=0, first_position={x=x, y=y}}
        failures[target] = failure
    end
    failure.count = failure.count + 1
end

local function log_failures(surface, failures)
    local targets = {}
    for target in pairs(failures) do targets[#targets + 1] = target end
    table.sort(targets)
    for _, target in ipairs(targets) do
        local failure = failures[target]
        log(("[BestLanding] resource placement on %s: failed to create %s "
            .. "at %d positions; first failure at %d,%d"):format(
            surface.name,
            target,
            failure.count,
            failure.first_position.x,
            failure.first_position.y
        ))
    end
end

local function execute_operations(surface, operations)
    local failures = {}
    for _, operation in ipairs(operations) do
        if operation.kind == "tile-area" then
            local tiles = {}
            for x = operation.area.left_top.x, operation.area.right_bottom.x - 1 do
                for y = operation.area.left_top.y, operation.area.right_bottom.y - 1 do
                    tiles[#tiles + 1] = {name=operation.target, position={x, y}}
                end
            end
            if #tiles > 0 then surface.set_tiles(tiles) end
        else
            local function attempt(x, y)
                local created = surface.create_entity{
                    name=operation.target,
                    position={x, y},
                    amount=operation.amount,
                    raise_built=false,
                    create_build_effect_smoke=false,
                }
                if not created then record_failure(failures, operation.target, x, y) end
            end
            if operation.kind == "resource-point" then
                attempt(operation.position.x, operation.position.y)
            else
                for x = operation.area.left_top.x, operation.area.right_bottom.x - 1 do
                    for y = operation.area.left_top.y, operation.area.right_bottom.y - 1 do
                        attempt(x, y)
                    end
                end
            end
        end
    end
    log_failures(surface, failures)
end

local function log_operation_summary(surface, operations)
    local resources = 0
    local tiles = 0
    for _, operation in ipairs(operations) do
        if operation.kind == "tile-area" then
            tiles = tiles + 1
        else
            resources = resources + 1
        end
    end
    log(("[BestLanding] resource placement on %s: executed %d resource operations "
        .. "and %d tile operations"):format(surface.name, resources, tiles))
end

-- apply_blueprint 复用同一条判定规则删除只用于设计的标记。
function M.is_resource_zone_marker(entity)
    return zones.is_marker(entity, prototypes.entity)
end

function M.place_blueprint_resources(surface, entities, transform)
    if not (surface and surface.valid) then return end

    local parsed_zones, parse_issues = zones.collect(
        entities, transform, prototypes.entity
    )
    log_issues(surface, parse_issues)

    local index = resource_index()
    local devices = collect_devices(entities, transform)
    local operations = {}

    for _, zone in ipairs(parsed_zones) do
        local targets, resolve_issues = zones.resolve(
            zone, index, prototypes.item, prototypes.tile
        )
        log_issues(surface, resolve_issues)
        append_zone_operations(operations, zone, targets, devices)
    end

    diagnose_operations(surface, operations)
    execute_operations(surface, operations)
    log_operation_summary(surface, operations)
end

return M
