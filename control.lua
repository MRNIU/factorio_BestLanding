-- Copyright The MRNIU/factorio_BestLanding Contributors

-- 引入区域清理器模块
local area_cleaner = require("area_cleaner")
local generate_resources = require("generate_resources")
local blueprints = require("blueprint")
local legendary_spider = require("legendary_spider")

--------------------------------------------------------------------------------------
-- Apply blueprint to the given surface
local function ApplyBlueprint(surface, blueprint_string, blueprint_pos, blueprint_direction)
    -- 仅在有玩家的势力执行，通常是 "player"
    local force = game.forces["player"]

    -- 如果提供了蓝图字符串，则应用蓝图
    if blueprint_string and blueprint_string ~= "" then
        -- 创建一个临时库存来处理蓝图
        local inventory = game.create_inventory(1)
        local stack = inventory[1]

        -- 导入蓝图字符串
        -- import_stack 返回 0 表示成功 (在某些版本中)，或者我们需要检查 stack 是否有效
        local import_result = stack.import_stack(blueprint_string)

        if stack.valid_for_read and stack.is_blueprint then
            -- 0. 预先生成区块，防止蓝图过大超出范围
            local blueprint_entities = stack.get_blueprint_entities()
            local blueprint_tiles = stack.get_blueprint_tiles()

            local min_x, min_y, max_x, max_y = 0, 0, 0, 0
            local initialized = false

            local function update_bounds(pos)
                if not initialized then
                    min_x, min_y = pos.x, pos.y
                    max_x, max_y = pos.x, pos.y
                    initialized = true
                else
                    if pos.x < min_x then min_x = pos.x end
                    if pos.x > max_x then max_x = pos.x end
                    if pos.y < min_y then min_y = pos.y end
                    if pos.y > max_y then max_y = pos.y end
                end
            end

            if blueprint_entities then
                for _, entity in pairs(blueprint_entities) do
                    update_bounds(entity.position)
                end
            end

            if blueprint_tiles then
                for _, tile in pairs(blueprint_tiles) do
                    update_bounds(tile.position)
                end
            end

            if initialized then
                local chunk_min_x = math.floor(min_x / 32)
                local chunk_max_x = math.floor(max_x / 32)
                local chunk_min_y = math.floor(min_y / 32)
                local chunk_max_y = math.floor(max_y / 32)

                for x = chunk_min_x, chunk_max_x do
                    for y = chunk_min_y, chunk_max_y do
                        surface.request_to_generate_chunks({ x * 32, y * 32 }, 0)
                    end
                end
                surface.force_generate_chunk_requests()
            end

            -- 1. 强制铺设地板
            if blueprint_tiles then
                local tiles_to_set = {}
                for _, t in pairs(blueprint_tiles) do
                    table.insert(tiles_to_set, { name = t.name, position = t.position })
                end
                surface.set_tiles(tiles_to_set)
            end

            -- 2. 在指定位置放置蓝图 (主要是实体)
            local ghosts = stack.build_blueprint {
                surface = surface,
                force = force,
                position = { blueprint_pos.x, blueprint_pos.y },
                direction = blueprint_direction,
                build_mode = defines.build_mode.forced,
                skip_fog_of_war = false
            }

            -- 3. 立即复活所有虚影为实体
            if ghosts then
                for _, ghost in pairs(ghosts) do
                    local revived, revived_entity, item_request_proxy = ghost.revive({ raise_revive = true })
                    if revived and revived_entity and item_request_proxy and item_request_proxy.valid then
                        -- 如果有物品请求代理（通常是插件），则插入物品并销毁代理
                        for _, item_req in pairs(item_request_proxy.item_requests) do
                            revived_entity.insert(item_req)
                        end
                        item_request_proxy.destroy()
                    end
                end
            end

            game.print("BestLanding: Blueprint applied!")
        else
            game.print("BestLanding: Invalid blueprint string or import failed. Result: " ..
                tostring(import_result))
        end

        inventory.destroy()
    else
        game.print("BestLanding: No blueprint provided.")
    end
end

local function ApplyBlueprints(surface)
    if not blueprints then return end

    for _, bp in pairs(blueprints) do
        if bp.data then
            ApplyBlueprint(surface, bp.data, bp.pos, bp.direction)
        end
    end
end

--------------------------------------------------------------------------------------
-- 在游戏初始化时清空中心区域
local function OnInit()
    area_cleaner.clear_center_area(game.surfaces.nauvis)
    generate_resources.generate_resource_planet(game.surfaces.nauvis)
    ApplyBlueprints(game.surfaces.nauvis)
    legendary_spider.spawn_legendary_spider(game.surfaces.nauvis, { x = 0, y = 0 })
end

--------------------------------------------------------------------------------------
-- 在新星球创建时清空中心区域
local function OnSurfaceCreated(event)
    local surface = game.surfaces[event.surface_index]

    if not surface.planet then
        return
    end

    area_cleaner.clear_center_area(surface)
    generate_resources.generate_resource_planet(surface)
    legendary_spider.spawn_legendary_spider(surface, { x = 0, y = 0 })
end

--------------------------------------------------------------------------------------
-- 事件注册
script.on_init(OnInit)
script.on_event(defines.events.on_surface_created, OnSurfaceCreated)
