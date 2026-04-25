-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 事件入口 + 降落流水线编排。所有业务逻辑拆到各阶段模块，这里只做事件分发。

local planets         = require("planets")
local clean_area      = require("clean_area")
local place_resources = require("place_resources")
local apply_blueprint = require("apply_blueprint")
local spawn_spider    = require("spawn_spider")

-- 流水线顺序：清理 → 铺资源 → 铺蓝图 → 生成蜘蛛。
-- 注意：蜘蛛在蓝图之后生成，用 find_non_colliding_position + 多半径 fallback
-- 绕开蓝图实体。如果蓝图把中心整块占满就只能退到 (0,0)，容 log 显示。
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

local function run_pipeline(surface)
    if not (surface and surface.valid) then return end
    local cfg = planets[surface.name]
    if not cfg then return end

    run_stage("clean_area",      clean_area.run,      surface, cfg)
    run_stage("place_resources", place_resources.run, surface, cfg)
    if apply_blueprints_enabled() then
        run_stage("apply_blueprint", apply_blueprint.run, surface)
    else
        log(("[BestLanding] apply_blueprint skipped on %s (setting disabled)"):format(surface.name))
    end
    run_stage("spawn_spider",    spawn_spider.run,    surface)
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
