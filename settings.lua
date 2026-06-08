-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 设置阶段：声明 Mod settings。settings 阶段早于 data 阶段、远早于 control 阶段。
-- runtime-global = 运行时由管理员在 Mod settings → Map 里切换，对所有玩家生效。
-- 注意：pipeline 只在 on_init / on_surface_created 各跑一次，setting 改了不会回溯
-- 已落地的行星——只对之后新出现的行星 surface 起作用。

data:extend({
    {
        type          = "bool-setting",
        name          = "BestLanding-apply-blueprints",
        setting_type  = "runtime-global",
        default_value = true,
        order         = "a-blueprints",
    },
    {
        type           = "string-setting",
        name           = "BestLanding-resource-placement-mode",
        setting_type   = "runtime-global",
        default_value  = "auto",
        allowed_values = { "auto", "fixed", "blueprint" },
        order          = "b-resource-placement",
    },
})
