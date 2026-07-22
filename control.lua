-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 事件入口 + 降落流水线编排。所有业务逻辑拆到各阶段模块，这里只做事件分发。

local planets         = require("planets")
local clean_area      = require("clean_area")
local apply_blueprint = require("apply_blueprint")

-- 流水线顺序：清理 → 蓝图驱动资源 + 铺蓝图。
--
-- 每个 stage 单独 pcall：单个 stage 抛错只让该 stage 的产物缺失，
-- 不会让 on_init 整个炸掉（否则新存档会创建失败、用户连菜单都退不回去）
local function run_stage(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        log(("[BestLanding] stage %s failed: %s"):format(name, tostring(err)))
    end
end

-- runtime-global setting，缺失时（理论不会，settings.lua 已声明）兜底视为 true。
-- settings.global[name] 在 setting 未注册时返回 nil；用 .value 之前必须判空。
local function apply_blueprints_enabled()
    local s = settings.global["BestLanding-apply-blueprints"]
    return s == nil or s.value
end

local BASE_LEVELS = {
    basic = 1,
    powered = 2,
    mining = 3,
    production = 4,
}

local function selected_base_level(surface)
    local setting_name = "BestLanding-" .. surface.name .. "-base-level"
    local setting = settings.global[setting_name]
    return BASE_LEVELS[setting and setting.value] or BASE_LEVELS.basic
end

local function run_pipeline(surface)
    if not (surface and surface.valid) then return end
    local cfg = planets[surface.name]
    if not cfg then return end

    local blueprints_enabled = apply_blueprints_enabled()
    local base_level = selected_base_level(surface)

    run_stage("clean_area", clean_area.run, surface, cfg)
    if blueprints_enabled then
        run_stage("apply_blueprint", apply_blueprint.run, surface, {
            max_level = base_level,
        })
    else
        log(("[BestLanding] apply_blueprint skipped on %s (setting disabled)"):format(surface.name))
    end
end

--------------------------------------------------------------------------------
-- 事件注册

-- on_surface_created 对新存档时已经存在的 Nauvis 不会触发，必须在 on_init 单独跑一次
script.on_init(function()
    run_pipeline(game.surfaces.nauvis)
end)

-- 其它行星在玩家第一次落地时由 on_surface_created 触发。
-- surface.planet 为 nil 的是太空平台 / 手动 create_surface 的表面，跳过。
script.on_event(defines.events.on_surface_created, function(event)
    local surface = game.surfaces[event.surface_index]
    if surface and surface.planet then
        run_pipeline(surface)
    end
end)
