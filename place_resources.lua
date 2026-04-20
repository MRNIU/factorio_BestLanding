-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 阶段 2：按星球配置在降落区北缘铺资源条。
-- 每条宽 BAND_WIDTH、高 BAND_HEIGHT；水平排列、零间距；起点 cfg.origin。

local C = require("constants")

local M = {}

--------------------------------------------------------------------------------
-- band area 计算（半开区间：right_bottom 不含边界）

local function band_area(origin, index)
    local x0 = origin.x + (index - 1) * C.BAND_WIDTH
    local y0 = origin.y
    return {
        left_top     = { x = x0,                   y = y0                    },
        right_bottom = { x = x0 + C.BAND_WIDTH,    y = y0 + C.BAND_HEIGHT    },
    }
end

--------------------------------------------------------------------------------
-- Gleba 果树

-- Gleba 果树的 prototype 命名：yumako 树是 "yumako-tree"，但 jellynut 的树叫
-- "jellystem"（"jellynut" 是果子 item，不是树 entity）。这是 Wube 故意的命名区分。
local function resolve_tree_name(plant)
    local name
    if plant == "yumako" then
        name = "yumako-tree"
    elseif plant == "jellynut" then
        name = "jellystem"
    else
        return nil
    end
    if prototypes.entity[name] then return name end
    return nil
end

-- 把 Gleba 果树拉到成熟阶段（能立刻结果子）。
-- Gleba 的 yumako-tree / jellystem 都是 PlantPrototype（继承 TreePrototype），
-- 成熟判定是 LuaEntity::tick_grown —— 这个 MapTick 到了就成熟。
-- tree_stage_index 只控制视觉 sprite 阶段，顺手拉到 max 让贴图也是成熟形态。
local function force_tree_mature(tree)
    if not (tree and tree.valid) then return end
    pcall(function() tree.tick_grown = game.tick end)
    pcall(function()
        local max_stage = tree.tree_stage_index_max
        if max_stage then tree.tree_stage_index = max_stage end
    end)
end

local function plant_trees(surface, area, plant)
    local name = resolve_tree_name(plant)
    if not name then
        log(("[BestLanding] plant_trees: prototype for %s not found, skipping"):format(tostring(plant)))
        return
    end

    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            if math.random() < C.GLEBA_TREE_DENSITY then
                local tree = surface.create_entity {
                    name        = name,
                    position    = { x + 0.5, y + 0.5 },
                    force       = "neutral",
                    raise_built = false,
                }
                force_tree_mature(tree)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- 三类 band 的落地实现

local function place_tile_band(surface, band, area)
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            tiles[#tiles + 1] = { name = band.name, position = { x, y } }
        end
    end
    surface.set_tiles(tiles)

    if band.plant then
        plant_trees(surface, area, band.plant)
    end
end

local function place_fluid_band(surface, band, area)
    -- 流体源就一个实体，放在 band 中心，amount 用 uint32 封顶值，永不枯
    local cx = math.floor((area.left_top.x + area.right_bottom.x) / 2)
    local cy = math.floor((area.left_top.y + area.right_bottom.y) / 2)
    surface.create_entity {
        name     = band.name,
        position = { cx, cy },
        amount   = C.FLUID_AMOUNT,
    }
end

local function place_ore_band(surface, band, area)
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            surface.create_entity {
                name     = band.name,
                position = { x, y },
                amount   = C.ORE_PER_TILE,
            }
        end
    end
end

local dispatch = {
    tile  = place_tile_band,
    fluid = place_fluid_band,
    ore   = place_ore_band,
}

--------------------------------------------------------------------------------
-- 阶段入口

function M.run(surface, cfg)
    if not (surface and surface.valid and cfg.bands) then return end

    for i, band in ipairs(cfg.bands) do
        local place = dispatch[band.kind]
        if place then
            place(surface, band, band_area(cfg.origin, i))
        else
            log(("[BestLanding] place_resources: unknown band kind %q on %s")
                :format(tostring(band.kind), surface.name))
        end
    end

    log(("[BestLanding] place_resources: %d bands on %s"):format(#cfg.bands, surface.name))
end

return M
