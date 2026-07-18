-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 五颗行星的 single source of truth：默认地形、敌人清理策略和蓝图资源列映射。

local C = require("constants")

-- blueprint_mining 让固体矿跟随蓝图里的矿机列：从左到右每 2 列矿机一组。
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
        blueprint_mining = {
            columns_per_resource = 2,
            resources = {
                "iron-ore",
                "copper-ore",
                "stone",
                "coal",
                "uranium-ore",
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
        blueprint_mining = {
            columns_per_resource = 2,
            resources = {
                "coal",
                "calcite",
                "tungsten-ore",
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
        blueprint_mining = {
            columns_per_resource = 2,
            resources = {
                "stone",
            },
        },
    },

    fulgora = {
        default_tile = "fulgoran-dust",
        enemy_cleanup = nil, -- 无敌人
        blueprint_mining = {
            columns_per_resource = 2,
            resources = {
                "scrap",
                "scrap",
                "scrap",
                "scrap",
            },
        },
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
