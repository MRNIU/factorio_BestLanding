-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 五颗行星的默认地形和敌人清理策略。

local C = require("constants")

return {
    nauvis = {
        default_tile = "grass-1",
        enemy_cleanup = {
            expand  = C.ENEMY_EXPAND.nauvis,
            filters = {
                { type = { "unit-spawner", "turret" }, force = "enemy" },
            },
        },
    },

    vulcanus = {
        default_tile = "volcanic-soil-dark",
        territory_cleanup = true,
    },

    gleba = {
        default_tile = "pit-rock",
        enemy_cleanup = {
            expand  = C.ENEMY_EXPAND.gleba,
            filters = {
                { type = "unit-spawner", force = "enemy" },
            },
        },
    },

    fulgora = {
        default_tile = "fulgoran-dust",
        enemy_cleanup = nil, -- 无敌人
    },

    aquilo = {
        default_tile = "snow-crests",
        enemy_cleanup = nil, -- 无敌人
    },
}
