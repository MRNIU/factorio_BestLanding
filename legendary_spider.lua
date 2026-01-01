-- Copyright The MRNIU/factorio_BestLanding Contributors

--------------------------------------------------------------------------------------
-- 配置传奇蜘蛛机甲
local function init_legendary_spider_armor(mech_armor)
    local grid = mech_armor.grid

    -- 手动指定装备位置配置 (机甲网格: 15宽 × 11高，索引从0开始)
    local equipment_positions = {
        -- toolbelt-equipment(3×1) - 放在顶部
        {
            name = "toolbelt-equipment",
            positions = {
                { 0, 0 }, { 3, 0 }, { 6, 0 }, { 9, 0 }, { 12, 0 } -- 5个工具栏装备
            }
        },

        -- energy-shield-mk2-equipment(2×2) - 能量护盾
        {
            name = "energy-shield-mk2-equipment",
            positions = {
                { 0, 1 },
                { 2, 1 },
                { 4, 1 }
            }
        },

        -- personal-roboport-mk2-equipment(2×2) - 个人机器人港
        {
            name = "personal-roboport-mk2-equipment",
            positions = {
                { 6, 1 },
                { 8, 1 },
            }
        },

        -- personal-laser-defense-equipment(2×2) - 个人激光防御
        {
            name = "personal-laser-defense-equipment",
            positions = {
                { 10, 1 },
                { 12, 1 },
            }
        },

        -- fusion-reactor-equipment(4×4) - 主要能源设备
        {
            name = "fusion-reactor-equipment",
            positions = {
                { 0, 3 },
                { 4, 3 },
                { 0, 7 },
                { 4, 7 },
            }
        },

        -- exoskeleton-equipment(2×4) - 外骨骼装备，放在底部
        {
            name = "exoskeleton-equipment",
            positions = {
                { 8,  3 },
                { 10, 3 },
                { 12, 3 },
                { 8,  7 },
                { 10, 7 },
                { 12, 7 },
            }
        },

        -- battery-mk3-equipment(1×2) - 电池，放在右侧
        {
            name = "battery-mk3-equipment",
            positions = {
                { 14, 1 },
                { 14, 3 },
                { 14, 5 },
                { 14, 7 },
                { 14, 9 },
            }
        },
    }

    -- 按指定位置添加装备
    for _, equipment_config in pairs(equipment_positions) do
        for i, position in ipairs(equipment_config.positions) do
            grid.put {
                name = equipment_config.name,
                position = position,
                quality = "legendary"
            }
        end
    end
end



--------------------------------------------------------------------------------------
-- 给指定库存添加物品
local function add_items_to_inventory(inventory, items)
    if not inventory then
        return
    end

    local added_items = {}

    for _, item_data in pairs(items) do
        local item_name = item_data.name or item_data[1]
        local item_count = item_data.count or item_data[2] or 1
        local item_quality = item_data.quality or "legendary"

        if prototypes.item[item_name] then
            local legendary_item = {
                name = item_name,
                count = item_count,
                quality = item_quality
            }

            local inserted = inventory.insert(legendary_item)
            if inserted > 0 then
                table.insert(added_items, item_count .. "x " .. item_quality .. " " .. item_name)
            end
        end
    end
end

--------------------------------------------------------------------------------------
-- 预设的传奇物品包
local preset_legendary_items = {
    -- 建造机器人和武器装备
    { name = "construction-robot", count = 1000, quality = "normal" }, -- 建造机器人
    { name = "logistic-robot", count = 1000, quality = "normal" },     -- 物流机器人
    { name = "roboport", count = 100, quality = "normal" },            -- 机器人港

    -- 电力设施
    { name = "big-electric-pole", count = 50, quality = "normal" }, -- 大电线杆
    { name = "substation", count = 200, quality = "normal" },       -- 变电站
    { name = "solar-panel", count = 1000 },                         -- 太阳能板
    { name = "accumulator", count = 1000 },                         -- 蓄电池

    -- 机械臂
    { name = "long-handed-inserter", count = 50, quality = "normal" }, -- 长臂机械臂
    { name = "fast-inserter", count = 50, quality = "normal" },        -- 快速机械臂
    { name = "bulk-inserter", count = 50, quality = "normal" },         -- 批量机械臂
    { name = "stack-inserter", count = 50, quality = "normal" },        -- 集装机械臂

    -- 物流系统
    { name = "steel-chest", count = 50, quality = "normal" },            -- 钢箱
    { name = "active-provider-chest", count = 50, quality = "normal" },  -- 紫箱
    { name = "passive-provider-chest", count = 50, quality = "normal" }, -- 红箱
    { name = "storage-chest", count = 50, quality = "normal" },          -- 黄箱
    { name = "buffer-chest", count = 50, quality = "normal" },           -- 绿箱
    { name = "requester-chest", count = 50, quality = "normal" },        -- 蓝箱

    -- 杂项
    { name = "rocket", count = 400 },                         -- 火箭
    { name = "explosive-rocket", count = 400 },               -- 爆炸火箭
    { name = "atomic-bomb", count = 10 },                     -- 原子弹
    { name = "laser-turret", count = 100 },                   -- 激光炮塔
    { name = "repair-pack", count = 200, quality = "normal" } -- 修理包
}

--------------------------------------------------------------------------------------
-- 在指定位置生成传奇蜘蛛机甲
local function spawn_legendary_spider(surface, position, force)
    if not surface or not position then return end

    -- 尝试找到一个不碰撞的位置
    local safe_position = surface.find_non_colliding_position("spidertron", position, 128, 1)
    if not safe_position then
        game.print("BestLanding: Warning - Could not find clear space for spider at " .. position.x .. "," .. position.y)
        safe_position = position
    end

    -- 创建传奇蜘蛛机甲
    local spider = surface.create_entity {
        name = "spidertron",
        position = safe_position,
        force = force or "player",
        quality = "legendary"
    }

    if spider then
        -- 初始化装备网格
        init_legendary_spider_armor(spider)

        -- 添加物品到背包
        local trunk = spider.get_inventory(defines.inventory.spider_trunk)
        add_items_to_inventory(trunk, preset_legendary_items)

        -- 添加弹药
        local ammo_inventory = spider.get_inventory(defines.inventory.spider_ammo)
        if ammo_inventory then
            ammo_inventory.insert({ name = "rocket", count = 400, quality = "legendary" })
        end
    else
        game.print("BestLanding: Failed to spawn legendary spider at " .. safe_position.x .. "," .. safe_position.y)
    end

    return spider
end

return {
    spawn_legendary_spider = spawn_legendary_spider
}
