-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 阶段 3：把 blueprints.lua 里匹配当前 surface 的蓝图应用到降落区。

local clean      = require("clean_area")
local blueprints = require("blueprints")
local resources  = require("place_resources")

local M = {}

local LOCKED_CHEAT_ENTITY_TYPES = {
    ["infinity-container"] = true,
    ["infinity-pipe"] = true,
    ["infinity-cargo-wagon"] = true,
}

local ROBOPORT_SUPPLIES = {
    robot = {
        "construction-robot",
        "logistic-robot",
    },
    material = {
        "repair-pack",
    },
}

--------------------------------------------------------------------------------
-- 蓝图本地坐标 → surface 坐标：先按 MapDirection 旋转，再平移 anchor

local function rotate_vector(vector, direction)
    local x, y = vector.x or vector[1], vector.y or vector[2]
    direction = (direction or 0) % 16

    -- 常用的四个正交方向保持精确值；其他方向主要用于斜向铁轨碰撞箱。
    if direction == 0 then
        return { x = x, y = y }
    elseif direction == 4 then
        return { x = -y, y = x }
    elseif direction == 8 then
        return { x = -x, y = -y }
    elseif direction == 12 then
        return { x = y, y = -x }
    end

    local angle = direction * math.pi / 8
    local cos_angle = math.cos(angle)
    local sin_angle = math.sin(angle)
    return {
        x = x * cos_angle - y * sin_angle,
        y = x * sin_angle + y * cos_angle,
    }
end

local function transform_pos(pos, anchor, direction)
    local rotated = rotate_vector(pos, direction)
    return { x = rotated.x + anchor.x, y = rotated.y + anchor.y }
end

-- 绝对吸附蓝图的实体坐标包含 position-relative-to-grid 偏移。这里只读取
-- 这个偏移并换算脚本放置所需的内容锚点，蓝图吸附设置本身保持原样。
-- build_blueprint 接收显式位置，不会执行玩家光标的网格吸附，所以清理、
-- 资源推断和实际建造都必须使用这个换算后的锚点。
local function resolve_blueprint_content_anchor(stack, anchor, direction)
    local resolved = { x = anchor.x, y = anchor.y }

    if stack.blueprint_absolute_snapping then
        local offset = stack.blueprint_position_relative_to_grid
        if offset then
            local rotated_offset = rotate_vector(offset, direction)
            resolved.x = resolved.x - rotated_offset.x
            resolved.y = resolved.y - rotated_offset.y
        end
    end

    return resolved
end

-- 从蓝图 entities + tiles 的完整占地，换算出 surface 上的 AABB。
-- 实体不能只看中心点，否则边缘大型建筑的碰撞箱会落到清理区之外。
local function compute_aabb(entities, tiles, anchor, direction)
    local min_x, min_y =  math.huge,  math.huge
    local max_x, max_y = -math.huge, -math.huge

    local function extend_surface_position(p)
        if p.x < min_x then min_x = p.x end
        if p.x > max_x then max_x = p.x end
        if p.y < min_y then min_y = p.y end
        if p.y > max_y then max_y = p.y end
    end

    local function extend_local_position(pos)
        extend_surface_position(transform_pos(pos, anchor, direction))
    end

    for _, entity in pairs(entities or {}) do
        local proto = prototypes.entity[entity.name]
        local box = proto and proto.collision_box
        local left_top = box and (box.left_top or box[1])
        local right_bottom = box and (box.right_bottom or box[2])

        if left_top and right_bottom then
            local left = left_top.x or left_top[1]
            local top = left_top.y or left_top[2]
            local right = right_bottom.x or right_bottom[1]
            local bottom = right_bottom.y or right_bottom[2]

            -- 对碰撞箱做中心对称扩展，可安全覆盖镜像实体和非对称原型。
            local half_width = math.max(math.abs(left), math.abs(right))
            local half_height = math.max(math.abs(top), math.abs(bottom))
            local entity_direction = ((entity.direction or 0) + (direction or 0)) % 16
            local center = transform_pos(entity.position, anchor, direction)

            for _, corner in ipairs {
                { x = -half_width, y = -half_height },
                { x =  half_width, y = -half_height },
                { x = -half_width, y =  half_height },
                { x =  half_width, y =  half_height },
            } do
                local rotated = rotate_vector(corner, entity_direction)
                extend_surface_position {
                    x = center.x + rotated.x,
                    y = center.y + rotated.y,
                }
            end
        else
            extend_local_position(entity.position)
        end
    end

    for _, tile in pairs(tiles or {}) do
        local x, y = tile.position.x, tile.position.y
        extend_local_position { x = x,     y = y }
        extend_local_position { x = x + 1, y = y }
        extend_local_position { x = x,     y = y + 1 }
        extend_local_position { x = x + 1, y = y + 1 }
    end

    if min_x == math.huge then return nil end
    return {
        left_top     = { x = min_x, y = min_y },
        right_bottom = { x = max_x, y = max_y },
    }
end

-- build_blueprint 返回的幽灵位置是 Factorio 最终采用的真实位置。revive 前再按
-- 真实占地清一次障碍，避免任何实体占地差异留下树木或岩石。
local function compute_runtime_aabb(entities)
    local min_x, min_y =  math.huge,  math.huge
    local max_x, max_y = -math.huge, -math.huge

    for _, entity in pairs(entities or {}) do
        if entity.valid then
            local box = entity.bounding_box
            if box then
                local left_top = box.left_top or box[1]
                local right_bottom = box.right_bottom or box[2]
                local left = left_top.x or left_top[1]
                local top = left_top.y or left_top[2]
                local right = right_bottom.x or right_bottom[1]
                local bottom = right_bottom.y or right_bottom[2]

                if left < min_x then min_x = left end
                if top < min_y then min_y = top end
                if right > max_x then max_x = right end
                if bottom > max_y then max_y = bottom end
            end
        end
    end

    if min_x == math.huge then return nil end
    return {
        left_top = { x = min_x, y = min_y },
        right_bottom = { x = max_x, y = max_y },
    }
end

local function position_key(name, position)
    local x = math.floor(position.x * 256 + 0.5)
    local y = math.floor(position.y * 256 + 0.5)
    return name .. "@" .. x .. "," .. y
end

-- 用 Factorio 实际生成的 ghost 位置反推最终内容锚点。选择出现次数最少的
-- 实体类型产生候选平移，再用全部 ghost 打分，避免依赖 build_blueprint 返回顺序。
local function infer_runtime_anchor(blueprint_entities, ghosts, direction, fallback)
    local relative_by_name = {}
    for _, entity in pairs(blueprint_entities or {}) do
        local positions = relative_by_name[entity.name]
        if not positions then
            positions = {}
            relative_by_name[entity.name] = positions
        end
        positions[#positions + 1] = rotate_vector(entity.position, direction)
    end

    local actual_by_name = {}
    local actual_lookup = {}
    for _, ghost in pairs(ghosts or {}) do
        if ghost.valid and ghost.ghost_name and ghost.position then
            local positions = actual_by_name[ghost.ghost_name]
            if not positions then
                positions = {}
                actual_by_name[ghost.ghost_name] = positions
            end
            positions[#positions + 1] = ghost.position
            actual_lookup[position_key(ghost.ghost_name, ghost.position)] = true
        end
    end

    local candidate_name
    local candidate_cost = math.huge
    for name, relative_positions in pairs(relative_by_name) do
        local actual_positions = actual_by_name[name]
        if actual_positions then
            local cost = #relative_positions * #actual_positions
            if cost < candidate_cost then
                candidate_name = name
                candidate_cost = cost
            end
        end
    end
    if not candidate_name then return fallback end

    local best_anchor
    local best_score = -1
    local best_distance = math.huge
    for _, relative_position in ipairs(relative_by_name[candidate_name]) do
        for _, actual_position in ipairs(actual_by_name[candidate_name]) do
            local candidate = {
                x = actual_position.x - relative_position.x,
                y = actual_position.y - relative_position.y,
            }
            local score = 0
            for _, entity in pairs(blueprint_entities or {}) do
                local rotated = rotate_vector(entity.position, direction)
                local expected = {
                    x = rotated.x + candidate.x,
                    y = rotated.y + candidate.y,
                }
                if actual_lookup[position_key(entity.name, expected)] then
                    score = score + 1
                end
            end

            local dx = candidate.x - fallback.x
            local dy = candidate.y - fallback.y
            local distance = dx * dx + dy * dy
            if score > best_score or (score == best_score and distance < best_distance) then
                best_anchor = candidate
                best_score = score
                best_distance = distance
            end
        end
    end

    return best_anchor or fallback
end

local function build_blueprint_ghosts(stack, surface, anchor, direction)
    return stack.build_blueprint {
        surface         = surface,
        force           = game.forces.player,
        position        = { anchor.x, anchor.y },
        direction       = direction,
        build_mode      = defines.build_mode.forced,
        skip_fog_of_war = false,
    } or {}
end

-- 第一次 build 只用于读取 Factorio 最终采用的实体位置。资源必须在正式 ghost
-- 生成前铺好，否则在 ghost 占地内创建矿物可能让矿机 ghost 失效。
local function destroy_probe_ghosts(ghosts)
    local destroyed = 0
    for _, ghost in pairs(ghosts or {}) do
        if ghost.valid and ghost.type == "entity-ghost" then
            ghost.destroy()
            destroyed = destroyed + 1
        end
    end
    return destroyed
end

-- 资源区域常量运算器只用于声明矿机选择矩形，不属于最终基地。
-- 按最终内容锚点记录名称和位置，避免误删蓝图里的普通常量运算器。
local function collect_resource_marker_positions(blueprint_entities, anchor, direction)
    local positions = {}
    local count = 0
    for _, entity in pairs(blueprint_entities or {}) do
        if resources.is_resource_zone_marker(entity) then
            local position = transform_pos(entity.position, anchor, direction)
            local key = position_key(entity.name, position)
            positions[key] = (positions[key] or 0) + 1
            count = count + 1
        end
    end
    return positions, count
end

local function destroy_resource_marker_ghosts(ghosts, marker_positions)
    local destroyed = 0
    for index, ghost in pairs(ghosts or {}) do
        if ghost.valid and ghost.type == "entity-ghost" and ghost.ghost_name then
            local key = position_key(ghost.ghost_name, ghost.position)
            local remaining = marker_positions[key] or 0
            if remaining > 0 then
                ghost.destroy()
                ghosts[index] = nil
                marker_positions[key] = remaining - 1
                destroyed = destroyed + 1
            end
        end
    end
    return destroyed
end

--------------------------------------------------------------------------------
-- 锁定蓝图里的作弊实体：保留输出能力，但禁止玩家操作 / 拆除 / 破坏

local function safe_set_entity_flag(entity, field, value)
    local ok, err = pcall(function()
        entity[field] = value
    end)
    if not ok then
        log(("[BestLanding] lock_cheat_entity: failed to set %s on %s: %s")
            :format(field, entity.name, tostring(err)))
    end
end

local function lock_cheat_entity(entity)
    if not (entity and entity.valid and LOCKED_CHEAT_ENTITY_TYPES[entity.type]) then return end

    safe_set_entity_flag(entity, "minable_flag", false)
    safe_set_entity_flag(entity, "destructible", false)
    safe_set_entity_flag(entity, "operable", false)
    safe_set_entity_flag(entity, "rotatable", false)

    log(("[BestLanding] locked cheat entity %s at %.1f, %.1f")
        :format(entity.name, entity.position.x, entity.position.y))
end

--------------------------------------------------------------------------------
-- 初始化蓝图实体：充满电能缓冲，并为机器人指令平台补充一组常用品

local function insert_normal_stack(entity, inventory_id, item_name)
    local inventory = entity.get_inventory(inventory_id)
    local item = prototypes.item[item_name]
    if not (inventory and item) then
        log(("[BestLanding] initialize_blueprint_entity: missing inventory or item %s on %s")
            :format(item_name, entity.name))
        return
    end

    local want = item.stack_size
    local inserted = inventory.insert {
        name = item_name,
        count = want,
        quality = "normal",
    }
    if inserted < want then
        log(("[BestLanding] initialize_blueprint_entity: inserted %d/%d of %s (q=normal) into %s")
            :format(inserted, want, item_name, entity.name))
    end
end

local function initialize_blueprint_entity(entity)
    if not (entity and entity.valid) then return end

    local buffer_size = entity.electric_buffer_size
    if buffer_size and buffer_size > 0 then
        entity.energy = buffer_size
    end

    if entity.type ~= "roboport" then return end

    for _, item_name in ipairs(ROBOPORT_SUPPLIES.robot) do
        insert_normal_stack(entity, defines.inventory.roboport_robot, item_name)
    end
    for _, item_name in ipairs(ROBOPORT_SUPPLIES.material) do
        insert_normal_stack(entity, defines.inventory.roboport_material, item_name)
    end
end

--------------------------------------------------------------------------------
-- item_request_proxy 兑现：把模块 / 弹药 / 过滤器等插回复活实体

-- LuaEntity 上和蓝图物品请求相关的有两个**格式不同**的字段（Factorio 2.0）：
--
--   item_requests :: Read  ItemWithQualityCounts = array[ItemWithQualityCount]
--                    扁平格式 { name, quality, count }，没有 slot 信息
--   insert_plan   :: R/W   array[BlueprintInsertPlan]
--                    per-slot 格式 { id = {name, quality},
--                                     items = { in_inventory :: array[InventoryPosition],
--                                               grid_count   :: uint? } }
--                    其中 InventoryPosition = { inventory :: defines.inventory.*,
--                                                stack :: ItemStackIndex (0-based),
--                                                count :: uint? }  -- 省略默认 1
--
-- 我们要的是 insert_plan：它精确指定每件物品要进哪个 inventory 的哪个 slot。
-- 对回收机这种多 inventory 的实体，BlueprintInsertPlan 会把模块的 inventory 标成
-- assembling_machine_modules（模块槽）而不是 input 队列——所以模块进模块槽、不会
-- 被当作回收原料。
--
-- 旧代码读 `proxy.item_requests` 并当成 `BlueprintInsertPlan[]` 解析，`plan.id` 是
-- nil，守卫直接跳过——这就是"所有插件都没插进去"的原因。
local function fulfill_item_requests(entity, proxy)
    if not (proxy and proxy.valid) then return end

    for _, plan in pairs(proxy.insert_plan) do
        local name    = plan.id and plan.id.name
        local quality = (plan.id and plan.id.quality) or "normal"

        if name and plan.items and plan.items.in_inventory then
            for _, slot in pairs(plan.items.in_inventory) do
                local inv = entity.get_inventory(slot.inventory)
                if inv then
                    local want = slot.count or 1
                    local inserted = inv.insert { name = name, count = want, quality = quality }
                    if inserted < want then
                        log(("[BestLanding] fulfill_item_requests: inserted %d/%d of %s (q=%s) into %s inv=%s")
                            :format(inserted, want, name, quality, entity.name, tostring(slot.inventory)))
                    end
                end
            end
        end
        -- plan.items.grid_count（装甲网格里的装备请求）暂不处理：
        -- 本 Mod 的 5 个蓝图里没有带装备网格的实体。
    end

    proxy.destroy()
end

--------------------------------------------------------------------------------
-- 应用单个蓝图

local function apply(surface, cfg, blueprint_string, anchor, direction)
    if not blueprint_string or blueprint_string == "" then
        return false, "empty blueprint"
    end

    -- 临时库存承载 BlueprintItem；pcall 保证即便中途抛错也 destroy，不泄漏
    local inventory = game.create_inventory(1)
    local ok, err = pcall(function()
        local stack = inventory[1]

        local import_result = stack.import_stack(blueprint_string)
        if import_result ~= 0 then
            log(("[BestLanding] apply_blueprint: import_stack returned %d on %s")
                :format(import_result, surface.name))
        end
        if not (stack.valid_for_read and stack.is_blueprint) then
            error("stack is not a valid blueprint after import")
        end

        local content_anchor = resolve_blueprint_content_anchor(stack, anchor, direction)
        local blueprint_entities = stack.get_blueprint_entities()
        local blueprint_tiles = stack.get_blueprint_tiles()

        -- 先算蓝图在 surface 上的 AABB，清掉范围内的非玩家、非资源障碍
        local aabb = compute_aabb(
            blueprint_entities,
            blueprint_tiles,
            content_anchor, direction
        )
        if aabb then
            clean.clean_blueprint_area(surface, aabb)
        end

        -- 先试放一次取得 Factorio 实际采用的坐标。forced 模式会直接铺 tile，
        -- 但 tile 再铺一次是幂等的；实体 ghost 会在资源生成前删除并正式重建。
        local probe_ghosts = build_blueprint_ghosts(
            stack, surface, content_anchor, direction
        )

        local runtime_aabb = compute_runtime_aabb(probe_ghosts)
        if runtime_aabb then
            clean.clean_blueprint_area(surface, runtime_aabb)
        end

        local runtime_anchor = infer_runtime_anchor(
            blueprint_entities,
            probe_ghosts,
            direction,
            content_anchor
        )
        if runtime_anchor.x ~= content_anchor.x or runtime_anchor.y ~= content_anchor.y then
            log(("[BestLanding] apply_blueprint: adjusted resource anchor on %s from %.1f,%.1f to %.1f,%.1f")
                :format(
                    surface.name,
                    content_anchor.x,
                    content_anchor.y,
                    runtime_anchor.x,
                    runtime_anchor.y
                ))
        end

        destroy_probe_ghosts(probe_ghosts)

        resources.place_blueprint_resources(
            surface,
            cfg,
            blueprint_entities,
            function(entity)
                local entity_direction = entity.direction or 0
                return {
                    position = transform_pos(entity.position, runtime_anchor, direction),
                    direction = (entity_direction + direction) % 16,
                }
            end
        )

        -- 矿物已经存在后，再正式创建实体 ghost。这样矿机可以正常生成在矿物上，
        -- 同时保留蓝图中的配方、模块、过滤器、品质和连线等全部设置。
        local ghosts = build_blueprint_ghosts(
            stack, surface, content_anchor, direction
        )

        local marker_positions, expected_markers = collect_resource_marker_positions(
            blueprint_entities, runtime_anchor, direction
        )
        local destroyed_markers = destroy_resource_marker_ghosts(
            ghosts, marker_positions
        )
        if destroyed_markers ~= expected_markers then
            log(("[BestLanding] apply_blueprint: removed %d/%d resource-zone marker ghosts on %s")
                :format(destroyed_markers, expected_markers, surface.name))
        end

        local final_runtime_aabb = compute_runtime_aabb(ghosts)
        if final_runtime_aabb then
            clean.clean_blueprint_area(surface, final_runtime_aabb)
        end

        -- revive 参数：
        --   raise_revive = false              省掉 script_raised_revive 事件广播
        --   return_item_request_proxy = true  确保第三个返回值给到 item_request_proxy
        --                                     （quantum-fabrication 等 2.0 working Mod 都这么传）
        local invalid_ghosts = 0
        local failed_revives = 0
        for _, ghost in pairs(ghosts) do
            if ghost.valid then
                local _, revived_entity, proxy = ghost.revive {
                    raise_revive              = false,
                    return_item_request_proxy = true,
                }
                if revived_entity then
                    fulfill_item_requests(revived_entity, proxy)
                    initialize_blueprint_entity(revived_entity)
                    lock_cheat_entity(revived_entity)
                else
                    failed_revives = failed_revives + 1
                end
            else
                invalid_ghosts = invalid_ghosts + 1
            end
        end
        if invalid_ghosts > 0 or failed_revives > 0 then
            log(("[BestLanding] apply_blueprint: %d invalid ghosts and %d failed revives on %s")
                :format(invalid_ghosts, failed_revives, surface.name))
        end
    end)

    inventory.destroy()

    if not ok then
        log(("[BestLanding] apply_blueprint: error on %s: %s"):format(surface.name, tostring(err)))
        return false, err
    end
    return true
end

--------------------------------------------------------------------------------
-- 阶段入口

function M.run(surface, cfg, opts)
    if not (surface and surface.valid) then return end

    -- blueprints 是 { lowercase_surface_name = { entry, entry, ... } } 结构，
    -- 直接 O(1) 取这颗行星对应的 list
    local entries = blueprints[string.lower(surface.name)]
    if not entries then return end

    local max_level = (opts and opts.max_level) or 1
    for _, bp in ipairs(entries) do
        local level = bp.level or 1
        if level <= max_level and bp.data and bp.data ~= "" then
            apply(surface, cfg, bp.data, bp.pos or { x = 0, y = 0 }, bp.direction or 0)
        end
    end
end

return M
