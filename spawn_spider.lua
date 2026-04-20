-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 阶段 4：在降落区中心生成一台满配传奇蜘蛛机甲。

local C = require("constants")

local M = {}

--------------------------------------------------------------------------------
-- 机甲网格装备布局（15 宽 × 11 高，索引从 0 开始）

local equipment_layout = {
    -- 顶部：工具栏 3×1，5 件横铺一行
    { name = "toolbelt-equipment", positions = {
        { 0, 0 }, { 3, 0 }, { 6, 0 }, { 9, 0 }, { 12, 0 },
    } },

    -- 第二行：能量护盾 × 3 + 机器人港 × 2 + 激光防御 × 2（都占 2×2）
    { name = "energy-shield-mk2-equipment", positions = {
        { 0, 1 }, { 2, 1 }, { 4, 1 },
    } },
    { name = "personal-roboport-mk2-equipment", positions = {
        { 6, 1 }, { 8, 1 },
    } },
    { name = "personal-laser-defense-equipment", positions = {
        { 10, 1 }, { 12, 1 },
    } },

    -- 主体：聚变反应堆 × 4 (4×4) + 外骨骼 × 6 (2×4)
    { name = "fusion-reactor-equipment", positions = {
        { 0, 3 }, { 4, 3 }, { 0, 7 }, { 4, 7 },
    } },
    { name = "exoskeleton-equipment", positions = {
        { 8, 3 }, { 10, 3 }, { 12, 3 },
        { 8, 7 }, { 10, 7 }, { 12, 7 },
    } },

    -- 右侧：电池 × 5（1×2，堆满最后一列 y=1..10）
    { name = "battery-mk3-equipment", positions = {
        { 14, 1 }, { 14, 3 }, { 14, 5 }, { 14, 7 }, { 14, 9 },
    } },
}

--------------------------------------------------------------------------------
-- 蜘蛛背包预设物资

local preset_items = {
    { name = "construction-robot",     count = 1000, quality = "normal"    },
    { name = "logistic-robot",         count = 1000, quality = "normal"    },
    { name = "roboport",               count = 100,  quality = "normal"    },
    { name = "big-electric-pole",      count = 50,   quality = "normal"    },
    { name = "substation",             count = 200,  quality = "normal"    },
    { name = "solar-panel",            count = 1000, quality = "legendary" },
    { name = "accumulator",            count = 1000, quality = "legendary" },
    { name = "long-handed-inserter",   count = 50,   quality = "normal"    },
    { name = "fast-inserter",          count = 50,   quality = "normal"    },
    { name = "bulk-inserter",          count = 50,   quality = "normal"    },
    { name = "stack-inserter",         count = 50,   quality = "normal"    },
    { name = "steel-chest",            count = 50,   quality = "normal"    },
    { name = "active-provider-chest",  count = 50,   quality = "normal"    },
    { name = "passive-provider-chest", count = 50,   quality = "normal"    },
    { name = "storage-chest",          count = 50,   quality = "normal"    },
    { name = "buffer-chest",           count = 50,   quality = "normal"    },
    { name = "requester-chest",        count = 50,   quality = "normal"    },
    { name = "rocket",                 count = 400,  quality = "legendary" },
    { name = "explosive-rocket",       count = 400,  quality = "legendary" },
    { name = "atomic-bomb",            count = 10,   quality = "legendary" },
    { name = "laser-turret",           count = 100,  quality = "legendary" },
    { name = "repair-pack",            count = 200,  quality = "normal"    },
}

--------------------------------------------------------------------------------
-- 辅助：逐级放宽半径找落脚点

local function find_safe_position(surface, origin)
    for _, r in ipairs(C.SPIDER_SEARCH_RADII) do
        local p = surface.find_non_colliding_position(
            "spidertron", origin, r, C.SPIDER_SEARCH_PRECISION
        )
        if p then return p, r end
    end
    return nil, nil
end

local function fill_grid(spider)
    local grid = spider.grid
    if not grid then return end
    for _, eq in pairs(equipment_layout) do
        for _, pos in pairs(eq.positions) do
            grid.put { name = eq.name, position = pos, quality = "legendary" }
        end
    end
end

local function fill_trunk(spider)
    local inv = spider.get_inventory(defines.inventory.spider_trunk)
    if not inv then return end
    -- preset 里的 item 都来自 base / space-age / quality（硬依赖），保证存在。
    -- 不再做 prototypes.item 守卫——typo 应该直接报错而非静默吞掉
    for _, item in pairs(preset_items) do
        inv.insert(item)
    end
end

local function fill_ammo(spider)
    local inv = spider.get_inventory(defines.inventory.spider_ammo)
    if not inv then return end
    inv.insert { name = "rocket", count = 400, quality = "legendary" }
end

--------------------------------------------------------------------------------
-- 阶段入口

function M.run(surface)
    if not (surface and surface.valid) then return end

    local origin = { x = 0, y = 0 }
    local position, found_radius = find_safe_position(surface, origin)
    if not position then
        log(("[BestLanding] spawn_spider: no clear position within %d on %s, falling back to origin")
            :format(C.SPIDER_SEARCH_RADII[#C.SPIDER_SEARCH_RADII], surface.name))
        position = origin
    elseif found_radius > C.SPIDER_SEARCH_RADII[1] then
        log(("[BestLanding] spawn_spider: used fallback radius %d on %s")
            :format(found_radius, surface.name))
    end

    local spider = surface.create_entity {
        name     = "spidertron",
        position = position,
        force    = "player",
        quality  = "legendary",
    }
    if not (spider and spider.valid) then
        log(("[BestLanding] spawn_spider: create_entity failed on %s at (%s, %s)")
            :format(surface.name, position.x, position.y))
        return
    end

    fill_grid(spider)
    fill_trunk(spider)
    fill_ammo(spider)
end

return M
