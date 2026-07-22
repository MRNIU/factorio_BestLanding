-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 阶段 1：把降落区 (0,0) 周围 448×448 清空、刷默认地形；按星球配置清敌人或领地。

local C      = require("constants")
local chunks = require("chunks")
local territory_cleanup = require("territory_cleanup")

local M = {}

-- 以 (0,0) 为中心的清理区。
-- 区间惯例：left_top 闭、right_bottom 开（"半开"）—— 和 place_resources 的
-- band_area 保持一致，避免 off-by-one。所以覆盖 tiles 是 [-CLEAR_RADIUS, CLEAR_RADIUS)
-- 共 2*CLEAR_RADIUS 个 tile。对 LuaSurface::find_entities / set_tiles 的 area
-- 参数来说，闭/开差别只在边界一行，无功能影响
local function center_area()
    return {
        left_top     = { x = -C.CLEAR_RADIUS, y = -C.CLEAR_RADIUS },
        right_bottom = { x =  C.CLEAR_RADIUS, y =  C.CLEAR_RADIUS },
    }
end

-- 把 area 沿四边扩 n tile
local function expand_area(area, n)
    return {
        left_top     = { x = area.left_top.x     - n, y = area.left_top.y     - n },
        right_bottom = { x = area.right_bottom.x + n, y = area.right_bottom.y + n },
    }
end

-- 把 {left_top, right_bottom} 翻成 LuaSurface::find_entities(_filtered) 期望的嵌套数组格式
local function to_api_area(area)
    return {
        { area.left_top.x,     area.left_top.y     },
        { area.right_bottom.x, area.right_bottom.y },
    }
end

-- 清掉区域内所有非玩家实体。find_entities 已经覆盖 resource / cliff / tree / 敌人，
-- 不需要再用 filtered 各跑一遍（旧代码那两段 find_entities_filtered 是冗余）。
local function purge_entities(surface, area)
    for _, e in pairs(surface.find_entities(to_api_area(area))) do
        if e.valid and e.type ~= "character" then
            e.destroy()
        end
    end
end

-- 按 cleanup cfg 扫扩围清普通敌人
local function cleanup_enemies(surface, inner_area, cleanup)
    if not cleanup or not cleanup.expand or cleanup.expand <= 0 then return end

    local outer = expand_area(inner_area, cleanup.expand)
    -- inner 已经被 purge_entities 扫过，只需要把外环的 chunk 补上
    chunks.force_generate_ring(surface, inner_area, outer)

    local api_area = to_api_area(outer)
    for _, filter in ipairs(cleanup.filters or {}) do
        local query = { area = api_area }
        for k, v in pairs(filter) do query[k] = v end
        for _, e in pairs(surface.find_entities_filtered(query)) do
            if e.valid then e.destroy() end
        end
    end
end

-- 把整个清理区刷成默认 tile（保证原生的水 / 岩 / 坑全被覆盖，落地即可建）。
-- set_tiles 的位置参数（按顺序）：
--   tiles, correct_tiles=true, remove_colliding_entities=true,
--   remove_colliding_decoratives=true, raise_event=false
--
-- correct_tiles=false：跳过相邻边缘修正。整片填同一种 tile，内部 tile 之间
--   不需要任何过渡贴图；只有外边界一圈会和未清理区交界，那一圈不修正最多就是
--   贴图衔接糙一点，不影响功能。这个 flag 是这里最大的 hot-loop 收益
-- remove_colliding_entities=false：清理实体已经在 purge_entities 干完了，
--   set_tiles 再扫一次纯属重复
local function repaint(surface, area, tile_name)
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
        end
    end
    surface.set_tiles(tiles, false, false, false, false)
end

--------------------------------------------------------------------------------
-- 阶段入口：供 control.lua 在 pipeline 里调用
function M.run(surface, cfg)
    if not (surface and surface.valid) then return end

    local area = center_area()
    chunks.force_generate(surface, area)
    if cfg.territory_cleanup then
        territory_cleanup.clear_area(surface, area)
    end
    purge_entities(surface, area)
    cleanup_enemies(surface, area, cfg.enemy_cleanup)
    repaint(surface, area, cfg.default_tile)

    log(("[BestLanding] clean_area: done on %s"):format(surface.name))
end

-- 供 apply_blueprint 调用：清掉完整蓝图占地内的非玩家障碍，不碰资源、不换 tile。
-- 不能只枚举 tree / simple-entity / cliff；Space Age 和其他 Mod 可能使用别的
-- 中立实体类型表示岩石或遗迹。后续蓝图层已建好的玩家实体必须保留。
function M.clean_blueprint_area(surface, area)
    if not (surface and surface.valid and area) then return end

    local padded = expand_area(area, C.BLUEPRINT_CLEAR_MARGIN)
    chunks.force_generate(surface, padded)

    local player_force = game.forces.player
    local obstacles = surface.find_entities(to_api_area(padded))
    for _, e in pairs(obstacles) do
        local force = e.valid and e.force
        if e.valid
            and e.type ~= "character"
            and e.type ~= "resource"
            and (not force or force.index ~= player_force.index)
        then
            e.destroy()
        end
    end
end

return M
