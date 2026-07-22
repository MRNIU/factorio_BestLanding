-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 根据沃土地格种植作物，并按物流请求给箱子补足种子。

local M = {}

-- 这里只定义沃土到种子的简单语义映射；实际作物始终从种子物品的
-- `plant_result` 读取，避免把作物实体名再写死一遍。
local SEED_BY_SOIL = {
    ["natural-yumako-soil"] = "yumako-seed",
    ["artificial-yumako-soil"] = "yumako-seed",
    ["overgrowth-yumako-soil"] = "yumako-seed",
    ["natural-jellynut-soil"] = "jellynut-seed",
    ["artificial-jellynut-soil"] = "jellynut-seed",
    ["overgrowth-jellynut-soil"] = "jellynut-seed",
}

local function prototype_name(prototype)
    return prototype and prototype.name or nil
end

function M.plan_for_tower(soil_name, device)
    local seed_name = SEED_BY_SOIL[soil_name]
    local seed = seed_name and prototypes.item[seed_name]
    local crop_name = seed and prototype_name(seed.plant_result)
    if not crop_name then return nil end

    return {
        crop = crop_name,
        seed = seed_name,
        position = device.position,
        radius = device.radius,
        growth_grid_size = device.growth_grid_size,
        device_key = device.device_key or device.key,
    }
end

local function record_failure(failures, crop, position)
    local failure = failures[crop]
    if not failure then
        failure = {count = 0, first_position = position}
        failures[crop] = failure
    end
    failure.count = failure.count + 1
end

local function log_plant_failures(surface, failures)
    local crops = {}
    for crop in pairs(failures) do crops[#crops + 1] = crop end
    table.sort(crops)
    for _, crop in ipairs(crops) do
        local failure = failures[crop]
        log(("[BestLanding] crop planting on %s: failed to create %s at %d positions; "
            .. "first failure at %.1f,%.1f"):format(
            surface.name,
            crop,
            failure.count,
            failure.first_position.x,
            failure.first_position.y
        ))
    end
end

function M.plant(surface, plans)
    if not (surface and surface.valid) then return end

    local failures = {}
    local attempted = 0
    local planted = 0
    for _, plan in ipairs(plans or {}) do
        local radius = math.floor(plan.radius or 0)
        local grid = plan.growth_grid_size or 3
        for grid_x = -radius, radius do
            for grid_y = -radius, radius do
                -- 中心生长格由农业塔本体占据，不属于可种植位置。
                if grid_x ~= 0 or grid_y ~= 0 then
                    local position = {
                        x = plan.position.x + grid_x * grid,
                        y = plan.position.y + grid_y * grid,
                    }
                    attempted = attempted + 1
                    local created = surface.create_entity {
                        name = plan.crop,
                        position = position,
                        force = game.forces.neutral,
                        register_plant = true,
                        raise_built = false,
                        create_build_effect_smoke = false,
                    }
                    if created then
                        planted = planted + 1
                    else
                        record_failure(failures, plan.crop, position)
                    end
                end
            end
        end
    end

    log_plant_failures(surface, failures)
    log(("[BestLanding] crop planting on %s: planted %d/%d crops from %d tower plans")
        :format(surface.name, planted, attempted, #(plans or {})))
end

local function quality_name(quality)
    if type(quality) == "string" then return quality end
    return prototype_name(quality) or "normal"
end

function M.fill_requested_seeds(entity)
    if not (entity and entity.valid and entity.type == "logistic-container") then return end

    local sections = entity.get_logistic_sections()
    if not (sections and sections.valid) then return end

    local inventory = entity.get_inventory(defines.inventory.chest)
    if not inventory then return end

    local requested = {}
    for _, section in pairs(sections.sections) do
        if section.valid and section.active then
            local multiplier = section.multiplier or 1
            for _, filter in pairs(section.filters) do
                local signal = filter.value
                local name = signal and signal.name
                local item = name and prototypes.item[name]
                local minimum = filter.min or 0
                if item and item.plant_result and minimum > 0 and multiplier > 0 then
                    local quality = quality_name(signal.quality)
                    local key = name .. "\0" .. quality
                    local entry = requested[key]
                    if not entry then
                        entry = {name = name, quality = quality, count = 0}
                        requested[key] = entry
                    end
                    entry.count = entry.count + math.ceil(minimum * multiplier)
                end
            end
        end
    end

    for _, request in pairs(requested) do
        local current = inventory.get_item_count {
            name = request.name,
            quality = request.quality,
        }
        local missing = math.max(0, request.count - current)
        if missing > 0 then
            local inserted = inventory.insert {
                name = request.name,
                quality = request.quality,
                count = missing,
            }
            if inserted < missing then
                log(("[BestLanding] seed supply: inserted %d/%d of %s (q=%s) into %s")
                    :format(inserted, missing, request.name, request.quality, entity.name))
            end
        end
    end
end

return M
