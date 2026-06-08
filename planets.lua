-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 五颗行星的 single source of truth：默认地形、敌人清理策略、资源条序列、蓝图锚点。
-- 条的顺序和起点决定了蓝图的坐标契约，和 blueprint.lua 严格绑定——改这里前务必确认蓝图对得上。

local C = require("constants")

-- band kinds
-- "ore"   : 固体矿，区域内每 tile 都 create_entity
-- "tile"  : 地块资源（water / lava / overgrowth-*-soil 等），set_tiles
-- "fluid" : 流体源（crude-oil 等），只在条的中心点 create_entity 一个，amount=FLUID_AMOUNT
--
-- 固体矿默认 32×32；普通 tile / fluid 共用一个 32×32 资源槽里的 4×8 小格。
-- 带 plant 的 Gleba tile 暂时保持旧的大条布局，并在 soil 上顺手种果树。
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
        origin = { x = -96, y = -192 },
        bands = {
            { kind = "ore",   name = "iron-ore"    },
            { kind = "ore",   name = "copper-ore"  },
            { kind = "ore",   name = "stone"       },
            { kind = "ore",   name = "coal"        },
            { kind = "fluid", name = "crude-oil"   },
            { kind = "tile",  name = "water"       },
            { kind = "ore",   name = "uranium-ore" },
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
        origin = { x = -80, y = -224 },
        bands = {
            { kind = "ore",   name = "coal"                 },
            { kind = "ore",   name = "calcite"              },
            { kind = "fluid", name = "sulfuric-acid-geyser" },
            { kind = "ore",   name = "tungsten-ore"         },
            { kind = "tile",  name = "lava"                 },
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
        origin = { x = -208, y = -192 },
        bands = {
            { kind = "ore",  name = "stone"                                         },
            { kind = "tile", name = "overgrowth-jellynut-soil", plant = "jellynut" },
            { kind = "tile", name = "overgrowth-jellynut-soil", plant = "jellynut" },
            { kind = "tile", name = "overgrowth-jellynut-soil", plant = "jellynut" },
            { kind = "tile", name = "overgrowth-jellynut-soil", plant = "jellynut" },
            { kind = "tile", name = "overgrowth-jellynut-soil", plant = "jellynut" },
            { kind = "tile", name = "overgrowth-jellynut-soil", plant = "jellynut" },
            { kind = "tile", name = "overgrowth-yumako-soil",   plant = "yumako"   },
            { kind = "tile", name = "overgrowth-yumako-soil",   plant = "yumako"   },
            { kind = "tile", name = "overgrowth-yumako-soil",   plant = "yumako"   },
            { kind = "tile", name = "overgrowth-yumako-soil",   plant = "yumako"   },
            { kind = "tile", name = "overgrowth-yumako-soil",   plant = "yumako"   },
            { kind = "tile", name = "overgrowth-yumako-soil",   plant = "yumako"   },
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
        origin = { x = -80, y = -224 },
        bands = {
            { kind = "ore",  name = "scrap"             },
            { kind = "ore",  name = "scrap"             },
            { kind = "ore",  name = "scrap"             },
            { kind = "ore",  name = "scrap"             },
            { kind = "tile", name = "oil-ocean-shallow" },
        },
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
        origin = { x = -80, y = -224 },
        bands = {
            { kind = "fluid", name = "lithium-brine"    },
            { kind = "fluid", name = "fluorine-vent"    },
            { kind = "fluid", name = "crude-oil"        },
            { kind = "tile",  name = "ammoniacal-ocean" },
            { kind = "tile",  name = "ammoniacal-ocean" },
        },
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
