-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 阶段 2：按星球配置在降落区北缘铺资源条。
-- 以 32×32 资源槽为基本单位水平排列；不同资源类型在槽内使用不同尺寸。

local C = require("constants")

local M = {}

local PUMPJACK_NAME = "pumpjack"
local DEFAULT_COLUMNS_PER_RESOURCE = 2

--------------------------------------------------------------------------------
-- band area 计算（半开区间：right_bottom 不含边界）

local function slot_area(origin, slot_index, width, height)
    local x0 = origin.x + slot_index * C.RESOURCE_SLOT_SIZE
    return {
        left_top     = { x = x0,         y = origin.y          },
        right_bottom = { x = x0 + width, y = origin.y + height },
    }
end

local function small_cell_area(origin, slot_index, cell_index)
    local columns = math.floor(C.RESOURCE_SLOT_SIZE / C.TILE_RESOURCE_WIDTH)
    local col = cell_index % columns
    local row = math.floor(cell_index / columns)
    local x0 = origin.x + slot_index * C.RESOURCE_SLOT_SIZE + col * C.TILE_RESOURCE_WIDTH
    local y0 = origin.y + row * C.TILE_RESOURCE_HEIGHT
    return {
        left_top = { x = x0, y = y0 },
        right_bottom = {
            x = x0 + C.TILE_RESOURCE_WIDTH,
            y = y0 + C.TILE_RESOURCE_HEIGHT,
        },
    }
end

local function is_small_resource(band)
    -- Gleba 果树土条有独立的大片布局，暂时不塞进 4×8 小格。
    return (band.kind == "tile" or band.kind == "fluid") and not band.plant
end

local function band_area(origin, band, layout)
    if band.kind == "ore" then
        local area = slot_area(origin, layout.next_slot, C.ORE_BAND_WIDTH, C.ORE_BAND_HEIGHT)
        layout.next_slot = layout.next_slot + 1
        return area
    end

    if is_small_resource(band) then
        if not layout.small_slot then
            layout.small_slot = layout.next_slot
            layout.next_slot = layout.next_slot + 1
        end
        local area = small_cell_area(origin, layout.small_slot, layout.next_small_cell)
        layout.next_small_cell = layout.next_small_cell + 1
        return area
    end

    local area = slot_area(origin, layout.next_slot, C.GLEBA_TILE_BAND_WIDTH, C.GLEBA_TILE_BAND_HEIGHT)
    layout.next_slot = layout.next_slot + 1
    return area
end

--------------------------------------------------------------------------------
-- Gleba 果树

-- Gleba 果树的 prototype 命名：yumako 树是 "yumako-tree"，但 jellynut 的树叫
-- "jellystem"（"jellynut" 是果子 item，不是树 entity）。这是 Wube 故意的命名区分。
--
-- 缓存到 module 上：prototypes 表只在 control 阶段可读，所以 lazy 算一次就够。
-- 旧版每个 tile 调一次 prototypes.entity[...]，整片 Gleba ~12000 次 hash 查询
local TREE_NAMES
local function tree_names()
    if not TREE_NAMES then
        TREE_NAMES = {
            yumako   = prototypes.entity["yumako-tree"] and "yumako-tree" or nil,
            jellynut = prototypes.entity["jellystem"]   and "jellystem"   or nil,
        }
    end
    return TREE_NAMES
end

-- 把 Gleba 果树拉到成熟阶段（能立刻结果子）。
-- Gleba 的 yumako-tree / jellystem 都是 PlantPrototype（继承 TreePrototype），
-- 成熟判定是 LuaEntity::tick_grown —— 这个 MapTick 到了就成熟。
-- tree_stage_index 只控制视觉 sprite 阶段，顺手拉到 max 让贴图也是成熟形态。
local function force_tree_mature(tree)
    if not (tree and tree.valid) then return end
    tree.tick_grown = game.tick
    local max_stage = tree.tree_stage_index_max
    if max_stage then tree.tree_stage_index = max_stage end
end

local function plant_trees(surface, area, plant)
    local name = tree_names()[plant]
    if not name then
        log(("[BestLanding] plant_trees: prototype for %s not found, skipping"):format(tostring(plant)))
        return
    end

    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            if math.random() < C.GLEBA_TREE_DENSITY then
                local tree = surface.create_entity {
                    name                      = name,
                    position                  = { x + 0.5, y + 0.5 },
                    force                     = "neutral",
                    raise_built               = false,
                    create_build_effect_smoke = false,
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

local function place_tile_area(surface, tile_name, area, placed)
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local key = x .. "," .. y
            if not placed[key] then
                tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
                placed[key] = true
            end
        end
    end
    if #tiles > 0 then
        surface.set_tiles(tiles)
    end
end

local function place_fluid_band(surface, band, area)
    -- 流体源就一个实体，放在 band 中心，amount 用 uint32 封顶值，永不枯
    local cx = math.floor((area.left_top.x + area.right_bottom.x) / 2)
    local cy = math.floor((area.left_top.y + area.right_bottom.y) / 2)
    surface.create_entity {
        name                      = band.name,
        position                  = { cx, cy },
        amount                    = C.FLUID_AMOUNT,
        raise_built               = false,
        create_build_effect_smoke = false,
    }
end

local function place_ore_band(surface, band, area)
    -- 矿条 32x32 = 1024 次 create_entity。
    -- raise_built / create_build_effect_smoke 关掉省视觉烟雾 + 事件广播
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            surface.create_entity {
                name                      = band.name,
                position                  = { x, y },
                amount                    = C.ORE_PER_TILE,
                raise_built               = false,
                create_build_effect_smoke = false,
            }
        end
    end
end

local function place_fluid_source(surface, resource_name, position, placed)
    if not prototypes.entity[resource_name] then
        log(("[BestLanding] place_fluid_source: resource prototype %s not found, skipping")
            :format(tostring(resource_name)))
        return
    end

    local x = math.floor(position.x + 0.5)
    local y = math.floor(position.y + 0.5)
    local key = x .. "," .. y
    if placed[key] then return end

    surface.create_entity {
        name                      = resource_name,
        position                  = { x, y },
        amount                    = C.FLUID_AMOUNT,
        raise_built               = false,
        create_build_effect_smoke = false,
    }
    placed[key] = true
end

local function place_ore_tiles(surface, resource_name, area, placed)
    if not prototypes.entity[resource_name] then
        log(("[BestLanding] place_ore_tiles: resource prototype %s not found, skipping")
            :format(tostring(resource_name)))
        return
    end

    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local key = x .. "," .. y
            if not placed[key] then
                surface.create_entity {
                    name                      = resource_name,
                    position                  = { x, y },
                    amount                    = C.ORE_PER_TILE,
                    raise_built               = false,
                    create_build_effect_smoke = false,
                }
                placed[key] = true
            end
        end
    end
end

local function get_drill_radius(entity)
    local proto = prototypes.entity[entity.name]
    if not (proto and proto.type == "mining-drill" and entity.name ~= PUMPJACK_NAME) then
        return nil
    end
    if proto.get_mining_drill_radius then
        if entity.quality then
            return proto.get_mining_drill_radius(entity.quality)
        end
        return proto.get_mining_drill_radius()
    end
    return proto.mining_drill_radius
end

local dispatch = {
    tile  = place_tile_band,
    fluid = place_fluid_band,
    ore   = place_ore_band,
}

--------------------------------------------------------------------------------
-- 阶段入口

function M.run(surface, cfg, opts)
    if not (surface and surface.valid and cfg.bands) then return end

    local skip_blueprint_driven = opts and opts.skip_blueprint_driven == true
    local layout = {
        next_slot = 0,
        next_small_cell = 0,
        small_slot = nil,
    }

    for _, band in ipairs(cfg.bands) do
        local place = dispatch[band.kind]
        if place then
            local area = band_area(cfg.origin, band, layout)
            local skipped = skip_blueprint_driven
                        and (band.kind == "ore" or is_small_resource(band))
            if not skipped then
                place(surface, band, area)
            end
        else
            log(("[BestLanding] place_resources: unknown band kind %q on %s")
                :format(tostring(band.kind), surface.name))
        end
    end

    log(("[BestLanding] place_resources: %d bands on %s"):format(#cfg.bands, surface.name))
end

--------------------------------------------------------------------------------
-- 蓝图矿机驱动的固体矿铺设

local function is_solid_resource_drill(entity)
    return get_drill_radius(entity) ~= nil
end

local function is_fluid_resource_drill(entity)
    return entity.name == PUMPJACK_NAME
end

local function is_offshore_pump(entity)
    local proto = prototypes.entity[entity.name]
    return proto and proto.type == "offshore-pump"
end

local function mining_area(position, radius)
    return {
        left_top = {
            x = math.floor(position.x - radius),
            y = math.floor(position.y - radius),
        },
        right_bottom = {
            x = math.ceil(position.x + radius),
            y = math.ceil(position.y + radius),
        },
    }
end

local function rotate_vector(vector, direction)
    local x, y = vector.x or vector[1], vector.y or vector[2]
    if direction == 2 then
        x, y = -y, x
    elseif direction == 4 then
        x, y = -x, -y
    elseif direction == 6 then
        x, y = y, -x
    end
    return { x = x, y = y }
end

local function offset_position(position, offset)
    return { x = position.x + offset.x, y = position.y + offset.y }
end

local function offshore_tile_area(entity)
    local proto = prototypes.entity[entity.name]
    local offset = proto and proto.fluid_source_offset
    if not offset then return nil end

    local source = offset_position(entity.position, rotate_vector(offset, entity.direction or 0))
    local direction = entity.direction or 0
    if direction == 2 then
        return {
            left_top = {
                x = math.floor(source.x),
                y = math.floor(source.y - C.TILE_RESOURCE_WIDTH / 2),
            },
            right_bottom = {
                x = math.floor(source.x) + C.TILE_RESOURCE_HEIGHT,
                y = math.floor(source.y - C.TILE_RESOURCE_WIDTH / 2) + C.TILE_RESOURCE_WIDTH,
            },
        }
    elseif direction == 6 then
        return {
            left_top = {
                x = math.floor(source.x) - C.TILE_RESOURCE_HEIGHT + 1,
                y = math.floor(source.y - C.TILE_RESOURCE_WIDTH / 2),
            },
            right_bottom = {
                x = math.floor(source.x) + 1,
                y = math.floor(source.y - C.TILE_RESOURCE_WIDTH / 2) + C.TILE_RESOURCE_WIDTH,
            },
        }
    elseif direction == 4 then
        return {
            left_top = {
                x = math.floor(source.x - C.TILE_RESOURCE_WIDTH / 2),
                y = math.floor(source.y),
            },
            right_bottom = {
                x = math.floor(source.x - C.TILE_RESOURCE_WIDTH / 2) + C.TILE_RESOURCE_WIDTH,
                y = math.floor(source.y) + C.TILE_RESOURCE_HEIGHT,
            },
        }
    end

    return {
        left_top = {
            x = math.floor(source.x - C.TILE_RESOURCE_WIDTH / 2),
            y = math.floor(source.y) - C.TILE_RESOURCE_HEIGHT + 1,
        },
        right_bottom = {
            x = math.floor(source.x - C.TILE_RESOURCE_WIDTH / 2) + C.TILE_RESOURCE_WIDTH,
            y = math.floor(source.y) + 1,
        },
    }
end

local function collect_columns(entities, transform, predicate, build)
    local columns = {}
    local by_key = {}

    for _, entity in pairs(entities or {}) do
        if predicate(entity) then
            local transformed = transform(entity)
            local position = transformed.position
            local key = math.floor(position.x + 0.5)
            local column = by_key[key]
            if not column then
                column = { key = key, drills = {} }
                by_key[key] = column
                columns[#columns + 1] = column
            end
            column.drills[#column.drills + 1] = build(entity, transformed)
        end
    end

    table.sort(columns, function(a, b) return a.key < b.key end)
    return columns
end

local function place_column_resources(surface, label, layout, columns, place)
    if not layout then return end

    local resources = layout.resources or {}
    local columns_per_resource = layout.columns_per_resource or DEFAULT_COLUMNS_PER_RESOURCE

    if #columns == 0 then
        log(("[BestLanding] %s: no matching blueprint entities found on %s")
            :format(label, surface.name))
        return
    end

    local placed = {}
    local assigned = 0
    for column_index, column in ipairs(columns) do
        local resource_index = math.floor((column_index - 1) / columns_per_resource) + 1
        local resource_name = resources[resource_index]
        if resource_name then
            for _, drill in ipairs(column.drills) do
                place(surface, resource_name, drill, placed)
                assigned = assigned + 1
            end
        else
            log(("[BestLanding] %s: no resource configured for column %d on %s")
                :format(label, column_index, surface.name))
        end
    end

    log(("[BestLanding] %s: seeded %d entities across %d columns on %s")
        :format(label, assigned, #columns, surface.name))
end

function M.place_blueprint_resources(surface, cfg, entities, transform)
    if not (surface and surface.valid and cfg) then return end

    place_column_resources(
        surface,
        "blueprint_mining",
        cfg.blueprint_mining,
        collect_columns(entities, transform, is_solid_resource_drill, function(entity, transformed)
            return {
                name = entity.name,
                position = transformed.position,
                radius = get_drill_radius(entity),
            }
        end),
        function(s, resource_name, drill, placed)
            place_ore_tiles(s, resource_name, mining_area(drill.position, drill.radius), placed)
        end
    )

    place_column_resources(
        surface,
        "blueprint_fluid_sources",
        cfg.blueprint_fluid_sources,
        collect_columns(entities, transform, is_fluid_resource_drill, function(entity, transformed)
            return {
                name = entity.name,
                position = transformed.position,
            }
        end),
        function(s, resource_name, drill, placed)
            place_fluid_source(s, resource_name, drill.position, placed)
        end
    )

    place_column_resources(
        surface,
        "blueprint_tile_resources",
        cfg.blueprint_tile_resources,
        collect_columns(entities, transform, is_offshore_pump, function(entity, transformed)
            return {
                name = entity.name,
                position = transformed.position,
                direction = transformed.direction,
            }
        end),
        function(s, tile_name, pump, placed)
            local area = offshore_tile_area(pump)
            if area then
                place_tile_area(s, tile_name, area, placed)
            end
        end
    )
end

return M
