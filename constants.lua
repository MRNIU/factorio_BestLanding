-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 全局常量，只允许在这里改数值；各模块通过 require("constants") 读取。

return {
    -- Factorio 的 chunk 边长
    CHUNK_SIZE = 32,

    -- 清理区半边长（从 (0,0) 向四周延伸）：总 448×448，覆盖 14×14 chunk
    CLEAR_RADIUS = 224,

    -- 蓝图完整占地之外额外清理的视觉缓冲，避免外围树冠遮住边缘建筑
    BLUEPRINT_CLEAR_MARGIN = 16,

    -- 固体矿每 tile 的储量（uint32 范围内）
    ORE_PER_TILE = 8192,

    -- 流体源 (crude-oil / sulfuric-acid-geyser / lithium-brine / fluorine-vent)
    -- 的 amount 字段；Factorio 是 uint32，旧代码算出来的 8192*1024*512 = 2^32
    -- 正好越界，fix 为 uint32 最大值
    FLUID_AMOUNT = 0xFFFFFFFF,

    -- 清理区外额外扩围清敌人用，0 表示不扩
    ENEMY_EXPAND = {
        nauvis   = 256, -- Biter / Spitter 巢穴 + worms
        vulcanus = 300, -- Demolisher 领地大，需要多扩一点
        gleba    = 256, -- Pentapod nest
        fulgora  = 0,   -- 无敌人
        aquilo   = 0,   -- 无敌人
    },
}
