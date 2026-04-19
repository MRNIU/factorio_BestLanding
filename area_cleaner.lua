-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 区域清理器 - 用于清空指定区域内的所有实体并替换地表

--------------------------------------------------------------------------------------
-- 强制生成指定区域的所有chunk
-- @param surface: 目标表面对象
-- @param area: 区域定义 {left_top = {x, y}, right_bottom = {x, y}}
-- @return boolean: 成功返回true，失败返回false
local function force_generate_chunks(surface, area)
    if not surface or not surface.valid then
        return false
    end

    if not area or not area.left_top or not area.right_bottom then
        return false
    end

    -- 计算chunk范围（每个chunk是32x32）
    local chunk_left = math.floor(area.left_top.x / 32)
    local chunk_top = math.floor(area.left_top.y / 32)
    local chunk_right = math.floor(area.right_bottom.x / 32)
    local chunk_bottom = math.floor(area.right_bottom.y / 32)

    -- 批量请求所有 chunk，再统一阻塞等待生成完成
    for chunk_x = chunk_left, chunk_right do
        for chunk_y = chunk_top, chunk_bottom do
            surface.request_to_generate_chunks({ chunk_x * 32, chunk_y * 32 }, 0)
        end
    end
    surface.force_generate_chunk_requests()

    return true
end

--------------------------------------------------------------------------------------
-- 清空指定区域内的所有实体，并根据星球类型替换地表
-- @param surface: 目标表面对象
-- @param area: 区域定义 {left_top = {x, y}, right_bottom = {x, y}}
-- @return boolean: 成功返回true，失败返回false
local function clear_area_to_land(surface, area)
    if not surface or not surface.valid then
        return false
    end

    -- 检查表面名称是否在允许的列表中
    local allowed_surfaces = { "nauvis", "vulcanus", "gleba", "fulgora", "aquilo" }
    local surface_allowed = false
    for _, allowed_name in pairs(allowed_surfaces) do
        if surface.name == allowed_name then
            surface_allowed = true
            break
        end
    end

    if not surface_allowed then
        return false
    end
    if not area or not area.left_top or not area.right_bottom then
        return false
    end

    -- 强制生成区域内的所有chunk
    force_generate_chunks(surface, area)

    -- 删除所有实体（包括敌人、建筑、树木、岩石等）
    local entities = surface.find_entities(area)
    for _, entity in pairs(entities) do
        if entity.valid then
            -- 不删除角色（玩家）
            if entity.type ~= "character" then
                entity.destroy()
            end
        end
    end

    -- 针对祝融星（Vulcanus）的特殊处理：清除附近的领地生物（Demolishers）
    -- 它们的领地范围很大，即使本体在区域外，领地也可能覆盖区域内
    if surface.name == "vulcanus" then
        local expand_dist = 300 -- 扩大搜索范围
        local left = area.left_top.x - expand_dist
        local top = area.left_top.y - expand_dist
        local right = area.right_bottom.x + expand_dist
        local bottom = area.right_bottom.y + expand_dist

        -- 必须先生成这些区域的区块，否则找不到实体
        local search_area_struct = {
            left_top = { x = left, y = top },
            right_bottom = { x = right, y = bottom }
        }
        force_generate_chunks(surface, search_area_struct)

        local search_area = { { left, top }, { right, bottom } }

        -- 查找并销毁 Demolishers (segmented-unit)
        local demolishers = surface.find_entities_filtered {
            area = search_area,
            type = "segmented-unit"
        }
        for _, demo in pairs(demolishers) do
            if demo.valid then
                demo.destroy()
            end
        end
    end

    -- 删除所有资源
    local resources = surface.find_entities_filtered {
        area = area,
        type = "resource"
    }
    for _, resource in pairs(resources) do
        if resource.valid then
            resource.destroy()
        end
    end

    -- 删除悬崖
    local cliffs = surface.find_entities_filtered {
        area = area,
        type = "cliff"
    }
    for _, cliff in pairs(cliffs) do
        if cliff.valid then
            cliff.destroy()
        end
    end

    -- 根据不同星球替换地形
    local tiles = {}
    local left_top = area.left_top
    local right_bottom = area.right_bottom

    -- 不同星球的默认地形配置
    local planet_terrain = {
        nauvis = "grass-1",
        vulcanus = "volcanic-soil-dark",
        gleba = "pit-rock",
        fulgora = "fulgoran-dust",
        aquilo = "snow-crests"
    }

    -- 根据星球名称选择合适的地形
    local tile_name = planet_terrain[surface.name] or "grass-1" -- 默认使用草地

    for x = left_top.x, right_bottom.x do
        for y = left_top.y, right_bottom.y do
            table.insert(tiles, { name = tile_name, position = { x, y } })
        end
    end

    -- 设置地形
    surface.set_tiles(tiles)

    return true
end

--------------------------------------------------------------------------------------
-- 清空指定坐标区域
-- @param surface: 目标表面
-- @param x1, y1: 左上角坐标
-- @param x2, y2: 右下角坐标
local function clear_area_by_coordinates(surface, x1, y1, x2, y2)
    local area = {
        left_top = { x = math.min(x1, x2), y = math.min(y1, y2) },
        right_bottom = { x = math.max(x1, x2), y = math.max(y1, y2) }
    }

    return clear_area_to_land(surface, area)
end

--------------------------------------------------------------------------------------
-- 清空以(0,0)为中心、半径 224 的正方形区域，这是游戏开始时默认生成的 chunk 大小
-- @param surface: 目标表面
local function clear_center_area(surface)
    if not surface or not surface.valid then
        game.print("clear_center_area: Invalid surface")
        return false
    end

    if not (surface.name == "nauvis" or surface.name == "vulcanus" or surface.name == "gleba" or surface.name == "fulgora" or surface.name == "aquilo") then
        game.print("clear_center_area: Unknown surface name " .. surface.name)
        return false
    end

    local radius = 224

    local area = {
        left_top = { x = -radius, y = -radius },
        right_bottom = { x = radius - 1, y = radius - 1 }
    }

    local success = clear_area_to_land(surface, area)
    if success then
        game.print("已清空以(0,0)为中心、半径 224 的正方形区域")
    else
        game.print("清空中心区域失败")
    end

    return success
end

--------------------------------------------------------------------------------------
-- 清理蓝图区域（仅移除树木、岩石、悬崖，不移除资源，不替换地表）
-- @param surface: 目标表面
-- @param area: 区域定义 {{x1, y1}, {x2, y2}}
local function clean_blueprint_area(surface, area)
    if not surface or not surface.valid or not area then return end

    local left_top = area[1]
    local right_bottom = area[2]

    if not left_top or not right_bottom then return end

    -- 扩大边界以确保覆盖实体的整个范围
    local min_x = left_top[1] - 5
    local min_y = left_top[2] - 5
    local max_x = right_bottom[1] + 5
    local max_y = right_bottom[2] + 5

    local expanded_area = {
        left_top = { x = min_x, y = min_y },
        right_bottom = { x = max_x, y = max_y }
    }

    -- 强制生成区块
    force_generate_chunks(surface, expanded_area)

    -- 清理区域内的树木、岩石和悬崖
    local obstacles = surface.find_entities_filtered {
        area = { { min_x, min_y }, { max_x, max_y } },
        type = { "tree", "simple-entity", "cliff" }
    }
    for _, entity in pairs(obstacles) do
        if entity.valid then
            entity.destroy()
        end
    end
end

--------------------------------------------------------------------------------------
-- 导出函数供其他文件使用
return {
    clear_center_area = clear_center_area,
    clean_blueprint_area = clean_blueprint_area
}
