-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 统一解析蓝图资源区域标记，并把信号映射到资源或地格原型。

local M = {}

local DESCRIPTION = "BestLanding:resource-zone"
local TILE_ALIASES = {
    ["heavy-oil"] = "oil-ocean-shallow",
    ["ammoniacal-solution"] = "ammoniacal-ocean",
}

local function issue(kind, message)
    return {kind = kind, message = message}
end

local function fluid_name(tile)
    local fluid = tile and tile.fluid
    return type(fluid) == "table" and fluid.name or fluid
end

local function prototype_name(prototype)
    if type(prototype) == "table" then return prototype.name end
    return prototype
end

local function marker_number(entity)
    return entity.entity_number or "?"
end

local function configured_filters(entity)
    local result = {}
    local control = entity.control_behavior or {}
    local sections = (control.sections or {}).sections or {}
    for _, section in pairs(sections) do
        for _, filter in pairs(section.filters or {}) do
            if filter.name then result[#result + 1] = filter end
        end
    end
    return result
end

local function append_candidate(index, product_type, product_name, resource_name)
    if (product_type ~= "item" and product_type ~= "fluid") or not product_name then
        return
    end
    local candidates = index[product_type][product_name]
    if not candidates then
        candidates = {}
        index[product_type][product_name] = candidates
    end
    if not candidates[resource_name] then
        candidates[resource_name] = true
    end
end

local function sorted_names(set)
    local result = {}
    for name in pairs(set or {}) do result[#result + 1] = name end
    table.sort(result)
    return result
end

local function resolve_resource(signal_type, signal_name, indexes, issues)
    local candidates = ((indexes or {})[signal_type] or {})[signal_name] or {}
    if #candidates == 0 then return nil end
    for _, candidate in ipairs(candidates) do
        if candidate == signal_name then return candidate end
    end
    if #candidates == 1 then return candidates[1] end
    issues[#issues + 1] = issue(
        "ambiguous-resource",
        ("signal %s:%s matches multiple resource prototypes: %s"):format(
            signal_type, signal_name, table.concat(candidates, ", ")
        )
    )
    return nil
end

local function resolve_offshore_tile(signal_name, tile_prototypes, issues)
    local same_name = tile_prototypes[signal_name]
    if same_name and fluid_name(same_name) == signal_name then
        return signal_name
    end

    local candidates = {}
    for name, tile in pairs(tile_prototypes) do
        if fluid_name(tile) == signal_name then candidates[#candidates + 1] = name end
    end
    table.sort(candidates)
    if #candidates == 1 then return candidates[1] end
    if #candidates == 0 then return nil end

    local alias = TILE_ALIASES[signal_name]
    if alias then
        for _, candidate in ipairs(candidates) do
            if candidate == alias then return alias end
        end
    end

    issues[#issues + 1] = issue(
        "ambiguous-offshore-tile",
        ("fluid signal %s matches multiple tile prototypes: %s"):format(
            signal_name, table.concat(candidates, ", ")
        )
    )
    return nil
end

function M.is_marker(entity, entity_prototypes)
    local proto = entity and entity_prototypes[entity.name]
    return proto and proto.type == "constant-combinator"
        and entity.player_description == DESCRIPTION
end

function M.position_in_zone(position, zone)
    return position.x >= zone.left and position.x <= zone.right
        and position.y >= zone.top and position.y <= zone.bottom
end

function M.collect(entities, transform, entity_prototypes)
    local groups = {}
    local issues = {}

    for _, entity in pairs(entities or {}) do
        if M.is_marker(entity, entity_prototypes) then
            local filters = configured_filters(entity)
            if #filters ~= 1 then
                issues[#issues + 1] = issue(
                    "invalid-marker-signal-count",
                    ("resource-zone marker %s must contain exactly one signal; found %d")
                        :format(marker_number(entity), #filters)
                )
            else
                local filter = filters[1]
                local signal_type = filter.type or "item"
                local quality = filter.quality or "normal"
                local zone_id = filter.count
                local valid = true
                if signal_type ~= "item" and signal_type ~= "fluid" then
                    valid = false
                    issues[#issues + 1] = issue(
                        "invalid-marker-signal-type",
                        ("resource-zone marker %s uses unsupported signal type %s")
                            :format(marker_number(entity), tostring(signal_type))
                    )
                end
                if quality ~= "normal" then
                    valid = false
                    issues[#issues + 1] = issue(
                        "invalid-marker-quality",
                        ("resource-zone marker %s must use normal quality; found %s")
                            :format(marker_number(entity), tostring(quality))
                    )
                end
                if type(zone_id) ~= "number" or zone_id <= 0 or zone_id % 1 ~= 0 then
                    valid = false
                    issues[#issues + 1] = issue(
                        "invalid-marker-zone-id",
                        ("resource-zone marker %s must use a positive integer count as zone id")
                            :format(marker_number(entity))
                    )
                end

                if valid then
                    groups[signal_type] = groups[signal_type] or {}
                    groups[signal_type][filter.name] = groups[signal_type][filter.name] or {}
                    groups[signal_type][filter.name][quality] =
                        groups[signal_type][filter.name][quality] or {}
                    local quality_groups = groups[signal_type][filter.name][quality]
                    quality_groups[zone_id] = quality_groups[zone_id] or {}
                    quality_groups[zone_id][#quality_groups[zone_id] + 1] = {
                        entity = entity,
                        transformed = transform(entity),
                    }
                end
            end
        end
    end

    local zones = {}
    for signal_type, names in pairs(groups) do
        for signal_name, qualities in pairs(names) do
            for quality, ids in pairs(qualities) do
                for zone_id, markers in pairs(ids) do
                    if #markers ~= 2 then
                        issues[#issues + 1] = issue(
                            "invalid-marker-pair-count",
                            ("resource zone %s:%s quality %s id %d must have exactly two markers; found %d")
                                :format(signal_type, signal_name, quality, zone_id, #markers)
                        )
                    else
                        local first = markers[1].transformed.position
                        local second = markers[2].transformed.position
                        zones[#zones + 1] = {
                            signal_type = signal_type,
                            signal_name = signal_name,
                            quality = quality,
                            zone_id = zone_id,
                            left = math.min(first.x, second.x),
                            right = math.max(first.x, second.x),
                            top = math.min(first.y, second.y),
                            bottom = math.max(first.y, second.y),
                        }
                    end
                end
            end
        end
    end

    table.sort(zones, function(a, b)
        if a.signal_type ~= b.signal_type then return a.signal_type < b.signal_type end
        if a.signal_name ~= b.signal_name then return a.signal_name < b.signal_name end
        if a.quality ~= b.quality then return a.quality < b.quality end
        return a.zone_id < b.zone_id
    end)
    return zones, issues
end

function M.build_resource_index(entity_prototypes)
    local sets = {item = {}, fluid = {}}
    for resource_name, prototype in pairs(entity_prototypes or {}) do
        if prototype.type == "resource" then
            local mineable = prototype.mineable_properties or {}
            for _, product in pairs(mineable.products or {}) do
                append_candidate(
                    sets,
                    product.type or "item",
                    product.name,
                    resource_name
                )
            end
        end
    end

    local index = {item = {}, fluid = {}}
    for _, product_type in ipairs({"item", "fluid"}) do
        for product_name, candidates in pairs(sets[product_type]) do
            index[product_type][product_name] = sorted_names(candidates)
        end
    end
    return index
end

function M.resolve(zone, indexes, item_prototypes, tile_prototypes)
    local targets = {}
    local issues = {}
    targets.entity_resource = resolve_resource(
        zone.signal_type, zone.signal_name, indexes, issues
    )

    if zone.signal_type == "item" then
        local item = item_prototypes[zone.signal_name]
        targets.place_tile = prototype_name(item and item.place_as_tile_result)
    elseif zone.signal_type == "fluid" then
        targets.offshore_tile = resolve_offshore_tile(
            zone.signal_name, tile_prototypes, issues
        )
    end

    return targets, issues
end

return M
