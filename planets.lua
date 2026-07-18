-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 五颗行星的 single source of truth：默认地形、敌人清理策略和泵类蓝图资源列映射。

local C = require("constants")

-- 固体矿由蓝图中的常量运算器资源区域标记决定。
-- blueprint_tile_resources / blueprint_fluid_sources 分别跟随 offshore pump / pumpjack。

return {
    nauvis = {
        default_tile = "grass-1",
        enemy_cleanup = {
            expand  = C.ENEMY_EXPAND.nauvis,
            filters = {
                { type = { "unit-spawner", "turret" }, force = "enemy" },
            },
        },
        blueprint_tile_resources = {
            columns_per_resource = 2,
            resources = {
                "water",
            },
        },
        blueprint_fluid_sources = {
            columns_per_resource = 2,
            resources = {
                "crude-oil",
            },
        },
    },

    vulcanus = {
        default_tile = "volcanic-soil-dark",
        enemy_cleanup = {
            expand  = C.ENEMY_EXPAND.vulcanus,
            filters = {
                -- Demolisher（segmented-unit）不属于 enemy force，所以不加 force 过滤
                { type = "segmented-unit" },
            },
        },
        blueprint_tile_resources = {
            columns_per_resource = 2,
            resources = {
                "lava",
            },
        },
        blueprint_fluid_sources = {
            columns_per_resource = 2,
            resources = {
                "sulfuric-acid-geyser",
            },
        },
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
        blueprint_tile_resources = {
            columns_per_resource = 2,
            resources = {
                "oil-ocean-shallow",
            },
        },
    },

    aquilo = {
        default_tile = "snow-crests",
        enemy_cleanup = nil, -- 无敌人
        blueprint_tile_resources = {
            columns_per_resource = 2,
            resources = {
                "ammoniacal-ocean",
                "ammoniacal-ocean",
            },
        },
        blueprint_fluid_sources = {
            columns_per_resource = 2,
            resources = {
                "lithium-brine",
                "fluorine-vent",
                "crude-oil",
            },
        },
    },
}
