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

        local blueprint_entities = stack.get_blueprint_entities()
        local blueprint_tiles = stack.get_blueprint_tiles()

        -- 先算蓝图在 surface 上的 AABB，清掉范围内的树 / 简单实体 / 悬崖
        local aabb = compute_aabb(
            blueprint_entities,
            blueprint_tiles,
            anchor, direction
        )
        if aabb then
            clean.clean_blueprint_area(surface, aabb)
        end

        resources.place_blueprint_resources(
            surface,
            cfg,
            blueprint_entities,
            function(entity)
                local entity_direction = entity.direction or 0
                return {
                    position = transform_pos(entity.position, anchor, direction),
                    direction = (entity_direction + direction) % 16,
                }
            end
        )

        -- 直接 build_blueprint：forced 模式下 tile 直接铺（不走 tile ghost），
        -- 实体生成为 ghost 等我们手动 revive。不再手动 set_tiles——旧代码那段
        -- 既冗余又带着一个 blueprint-relative 坐标没变换的 bug。
        local ghosts = stack.build_blueprint {
            surface         = surface,
            force           = game.forces.player,
            position        = { anchor.x, anchor.y },
            direction       = direction,
            build_mode      = defines.build_mode.forced,
            skip_fog_of_war = false,
        } or {}

        -- revive 参数：
        --   raise_revive = false              省掉 script_raised_revive 事件广播
        --   return_item_request_proxy = true  确保第三个返回值给到 item_request_proxy
        --                                     （quantum-fabrication 等 2.0 working Mod 都这么传）
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
                end
            end
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
