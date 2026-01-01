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

    local left_top = area.left_top
    local right_bottom = area.right_bottom

    -- 计算chunk范围（每个chunk是32x32）
    local chunk_left = math.floor((left_top.x or left_top[1]) / 32)
    local chunk_top = math.floor((left_top.y or left_top[2]) / 32)
    local chunk_right = math.floor((right_bottom.x or right_bottom[1]) / 32)
    local chunk_bottom = math.floor((right_bottom.y or right_bottom[2]) / 32)

    -- 强制生成所有相关的chunk
    for chunk_x = chunk_left, chunk_right do
        for chunk_y = chunk_top, chunk_bottom do
            surface.request_to_generate_chunks({ chunk_x * 32, chunk_y * 32 }, 0)
            surface.force_generate_chunk_requests()
        end
    end

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

    for x = left_top.x or left_top[1], right_bottom.x or right_bottom[1] - 1 do
        for y = left_top.y or left_top[2], right_bottom.y or right_bottom[2] - 1 do
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
-- 导出函数供其他文件使用
return {
    clear_center_area = clear_center_area
}
