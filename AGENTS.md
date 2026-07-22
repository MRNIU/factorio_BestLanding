# AGENTS.md

本文档为 Claude Code（claude.ai/code）在本仓库中工作时提供指引。

## 项目定位

Factorio 2.1 Mod（`BestLanding`），用 Lua 编写。仓库本身即是部署的 Mod——以 `%APPDATA%/Factorio/mods/BestLanding/` 的形式被游戏直接加载。没有构建步骤和包管理器。`tests/` 提供不依赖 Factorio 的 Lua 单元测试；改代码后仍需重启 Factorio（或重载存档）验证运行时行为。

`info.json` 声明的依赖：`base >= 2.1.9`、`space-age`、`quality`。本 Mod 仅运行时，覆盖 Space Age 所有五颗行星 surface（`nauvis`、`vulcanus`、`gleba`、`fulgora`、`aquilo`）。

## 兄弟 Mod

本 Mod 是 NZH 维护的开局 Mod 家族的一员：

- [`LegendaryMechStart`](https://github.com/MRNIU/factorio_LegendaryMechStart) — 传奇机甲 + 装备网格 + 初始物品
- [`LegendaryShipStart`](https://github.com/MRNIU/factorio_LegendaryShipStart) — 预置传奇太空飞船
- **`BestLanding`（本仓库）** — 着陆区清理 + 行星资源 + 起始蓝图
- [`nzh_factorio_mod`](https://github.com/MRNIU/nzh_factorio_mod) — 整合包，一键启用上面三个

**如果发现本 Mod 要做的事和兄弟 Mod 重叠了**（比如"玩家背包发放物品" vs `LegendaryMechStart`、"太空平台蓝图" vs `LegendaryShipStart`），先停下问用户，不要在本仓库重复实现。`LegendaryShipStart` 有几乎同样的蓝图应用流水线，涉及蓝图处理时可以参考它——但别跨仓库 require。

## 常用命令

- **运行 / 迭代**：启动 Factorio，启用本 Mod，开新游戏（或者着陆到新行星触发第二次及以后的清理）。（注：Claude Code 跑在 WSL、Mod 文件通过 Windows 挂载访问，Claude 无法直接启动 Factorio 或 Factorio Modding Tool Kit；运行验证需要你在 Windows 侧手工操作。）
- **单元测试**：`lua5.4 tests/run.lua`。使用手写 prototype / surface 假对象，覆盖统一资源标记解析和资源操作生成；不能替代 Factorio 运行时验证。
- **语法检查 / 预提交**：改完任何 `.lua` 后跑一次 `for f in *.lua tests/*.lua; do luac5.4 -p "$f" || break; done`，能抓 `end` 缺失 / 括号不匹配 / 字符串没闭合等语法问题；**不查语义**（undefined global、类型错误等）。提交前养成这个习惯可以避免把纯语法错推到 Mod portal。
- **调试**：`.vscode/launch.json` 使用 Factorio Modding Tool Kit 2.1+ 的原生 `factorio` 调试适配器（Factorio 2.1 的 `--dap`），追控制流时优先用它。
- **打包发布**：打包为 `BestLanding_<version>.zip`，压缩包最外层是文件夹本身。版本号必须和 `info.json`、`changelog.txt` 顶条一致。
- **Changelog 格式**：Factorio 严格格式（99 个 `-`、`Version:`、`Date:`、缩进 `Changes:`），英文。

## 架构

纯运行时，一条 pipeline。`control.lua` 只做事件分发 + 顺序调用清理和蓝图两个阶段；`planets.lua` 只保留默认地形和敌人清理差异，资源类型完全来自 Mining 蓝图标记。

### 文件职责

- **`control.lua`** — 事件注册 + `run_pipeline(surface)`。
  - `script.on_init(...)` 对 Nauvis 跑一次（`on_surface_created` 对新存档时已存在的 Nauvis 不触发）。
  - `script.on_event(on_surface_created, ...)` 对其他行星触发，用 `surface.planet ~= nil` 排除太空平台。
  - pipeline 顺序：`clean_area.run` → `apply_blueprint.run`；只有 `level == 3` 的 Mining 蓝图在实体建造前调用 `place_resources.place_blueprint_resources`。
  - 没有资源生成模式设置和固定 fallback。矿物资源、地下流体源、海洋/水域地格和可放置地格都由 Mining 蓝图中的配对常量运算器标记决定；关闭起始蓝图时也不生成起始资源。
  - 五颗行星各有一个 `BestLanding-<planet>-base-level` runtime-global 设置：`basic=1`、`powered=2`、`mining=3`、`production=4`。选中等级会从一级开始累计应用所有不高于该等级的蓝图层。

- **`constants.lua`** — 所有魔数的唯一出处：`CLEAR_RADIUS=224`、`BLUEPRINT_CLEAR_MARGIN=16`、`ORE_PER_TILE=8192`、`FLUID_AMOUNT=0xFFFFFFFF`（uint32 上限，修掉旧代码 `8192*1024*512 = 2^32` 溢出）、`ENEMY_EXPAND`。

- **`planets.lua`** — 只定义五颗行星的 `{ default_tile, enemy_cleanup }`。这里不再包含任何资源白名单、黑名单、顺序或列映射。

- **`chunks.lua`** — `force_generate` / `force_generate_ring`。批量 `request_to_generate_chunks` + 单次 `force_generate_chunk_requests` 是官方推荐姿势。ring 变体用于 Vulcanus Demolisher 扫描扩围：清理区已经由 `force_generate` 生成过，只补外环 chunk 就够了。

- **`clean_area.lua`** — `run(surface, cfg)` + `clean_blueprint_area(surface, area)`。
  - `run` 流程：`force_generate` 清理区 → `find_entities` 一次扫光非玩家实体（不再第二次 filter 资源 / 悬崖，`find_entities` 已经包含）→ `cleanup_enemies` 按 `cfg.enemy_cleanup.filters` 清扩围 → `set_tiles` 全刷 `cfg.default_tile`。
  - `clean_blueprint_area` 给 `apply_blueprint` 用，清掉完整蓝图占地及外围 16 格视觉缓冲内所有非玩家、非资源实体，不动已有玩家建筑和矿物。

- **`resource_zones.lua`** — 纯解析器。校验和配对 `BestLanding:resource-zone` 标记，按资源原型的开采产物解析 item / fluid 信号，按 `place_as_tile_result` 解析可放置地格，并按 tile 的 `fluid` 属性和两个固定别名解析离岸泵地格。它不修改 surface，也不直接写日志。

- **`place_resources.lua`** — `place_blueprint_resources(surface, entities, transform)`。扫描固体矿机、原版 `pumpjack`、所有 `agricultural-tower` 和 `offshore-pump`，根据设备中心是否落在标记矩形中生成资源操作。先用临时映射汇总设备和预测占地冲突，再丢弃诊断映射并原样执行所有操作；诊断绝不去重、跳过或选择胜者。`is_resource_zone_marker` 复用 `resource_zones.is_marker`，保证放置和标记 ghost 删除使用同一识别规则。

- **`apply_blueprint.lua`** — `run(surface, opts)`。遍历 `blueprints` 表匹配 `surface.name`（小写比较）。单个蓝图流程：
  1. 临时 `game.create_inventory(1)` + `stack.import_stack(...)` + 校验 `valid_for_read and is_blueprint`。
  2. `resolve_blueprint_content_anchor` — 只读取绝对网格吸附蓝图的 `blueprint_position_relative_to_grid`，为清理、资源推断和实际建造换算统一的内容锚点，不修改任何蓝图吸附设置。脚本版 `build_blueprint` 使用显式位置，不会执行玩家光标的网格吸附。
  3. `compute_aabb` — **把蓝图实体的完整碰撞箱和 tile 占地按最终 anchor + direction 变换到 surface 坐标**再算 AABB。不能只取实体中心，否则边缘大型建筑仍可能被清理范围外的障碍挡住。
  4. `clean.clean_blueprint_area(surface, aabb)` 清掉范围内所有非玩家、非资源障碍实体。
  5. 第一次 `stack.build_blueprint{ build_mode = defines.build_mode.forced }` 只作为试放；根据 ghost 的真实 `bounding_box` 再清理一次实际建造范围，并用 `infer_runtime_anchor` 反推 Factorio 最终采用的内容锚点。
  6. 删除试放产生的实体 ghost；forced 模式已经直接落下的 tile 保留，因为第二次铺相同 tile 是幂等的。
  7. 仅当当前条目 `level == 3` 时，`place_resources.place_blueprint_resources(...)` 使用真实内容锚点，根据统一标记和设备类型铺资源实体或地格。
  8. 用完全相同的蓝图和放置参数第二次 `build_blueprint`，在资源已经存在的情况下正式生成实体 ghost，避免创建矿物导致矿机 ghost 失效。
  9. 按说明和最终实际坐标删除 `BestLanding:resource-zone` 常量运算器 ghost；它们只作为设计标记，不属于最终基地，普通常量运算器不受影响。
  10. 根据其余正式 ghost 的真实占地再清理一次障碍，然后逐个调用 `revive{ raise_revive = false, return_item_request_proxy = true }`，再走 `fulfill_item_requests`；无效 ghost 和复活失败会汇总写日志。
  11. 每个 revive 出来的实体都会把 `electric_buffer_size` 对应的电能缓冲充满；`roboport` 还会在机器人 / 材料库存中分别追加一组普通品质的建筑机器人、物流机器人和修理包。
  12. 如果 revive 出来的实体是 `infinity-container` / `infinity-pipe` / `infinity-cargo-wagon`，立刻设 `minable_flag=false`、`destructible=false`、`operable=false`、`rotatable=false`。这类蓝图里的作弊供给实体只作为只读补给源存在：玩家不能打开设置界面、旋转、拆除或破坏它们，但 inserter / 管网仍然可以从里面取物品或抽流体。
  - `fulfill_item_requests` — **用 `proxy.insert_plan`，不是 `proxy.item_requests`**。LuaEntity 上这两个字段格式完全不同：
    - `LuaEntity::item_requests :: ItemWithQualityCounts`（只读）—— 扁平 `[{name, quality, count}, ...]`，没有 slot 信息
    - `LuaEntity::insert_plan :: array[BlueprintInsertPlan]`（读写）—— per-slot `[{id={name, quality}, items={in_inventory=[{inventory, stack, count}, ...], grid_count?}}, ...]`

    模块 / 过滤器 / 弹药要进对的 inventory，必须走 `insert_plan` 拿 `slot.inventory`（`defines.inventory.*` 编号）再 `entity.get_inventory(slot.inventory):insert{...}`。对回收机尤其关键：模块的 `slot.inventory` 是 `assembling_machine_modules`，按这个走进模块槽、**不会被当作回收原料**。
    
    注意 `slot.count` 可选，省略时默认 1——传 `nil` 给 `LuaInventory::insert` 会静默插 0 件。必须 `slot.count or 1`。
    
    参考实现：<https://github.com/refulgence/quantum-fabrication/blob/main/scripts/builder.lua>
  - 整段用 `pcall` 包起来，即便中途抛错也保证 `inventory.destroy()` 跑到。

- **`blueprints.lua`** — 五颗行星各有四个蓝图层：原有的行星同名变量是基础基地，`*Power` 是二级追加的供电系统，`*Mining` 是三级追加的矿物设施，`*Production` 是四级追加的生产设施。表项格式为 `{ level, data, pos, direction }`。统一资源标记采用最新契约，只扫描 `*Mining`；其他层即使包含资源标记或驱动设备也会被忽略。

### Mining 蓝图标记 → 设备 → 资源 的契约

两个说明为 `BestLanding:resource-zone` 的常量运算器组成一个选择矩形。两者必须各有且只有一个相同的普通品质 item 或 fluid 信号，并使用相同的正整数数量作为区域编号。信号含义由被选中的设备类型共同决定：

- item + 固体 mining drill：按开采产物解析资源实体，铺满矿机自身采矿半径。
- fluid + `pumpjack`：按开采产物解析地下流体资源，在抽油机中心地格创建资源。
- item + `agricultural-tower`：读取物品的 `place_as_tile_result`，铺满农业塔工作范围。
- fluid + `offshore-pump`：按 tile 的 fluid 解析水域地格，每个区域独立包围所选泵的 source tile。
- `heavy-oil` 固定消歧为 `oil-ocean-shallow`，`ammoniacal-solution` 固定消歧为 `ammoniacal-ocean`；这只是信号映射，不是行星规则。
- 改 `ORE_PER_TILE` / `FLUID_AMOUNT` = 安全（只是数值，蓝图不依赖）。

蓝图作者必须保证标记没有歧义。重复区域、同一设备的不同目标、不同资源占地重叠都会记录日志，但程序不代替用户裁决，仍然直接执行每个可解析操作。

### 状态模型（Factorio 2.1）

目前不维护任何持久状态，`storage` 是空的。如果以后需要，记得在 `on_init` 里初始化。

## 常见坑

- **`find_entities_*` / `set_tiles` 之前 chunk 必须先生成完**：未生成的 chunk 上前者返回空、后者无效果。`clean_area.lua` 和 `apply_blueprint` 的 `clean_blueprint_area` 都先走 `chunks.force_generate`。
- **Demolisher 的领地会越过本体位置**：`ENEMY_EXPAND.vulcanus = 300` 不是拍脑袋，缩了会让领地重新覆盖着陆区。
- **资源条 amount 是 uint32**：`FLUID_AMOUNT` 必须 ≤ `0xFFFFFFFF`。旧代码 `8192*1024*512 = 2^32` 溢出。
- **资源冲突诊断不能参与执行**：`diagnose_operations` 的临时映射只用于日志，`execute_operations` 必须遍历原始操作数组；不要重新引入占位表、先到先得或冲突跳过逻辑。
- **`item_requests` 和 `insert_plan` 是两个不同字段**（Factorio 2.1 里仍然最容易踩的陷阱）：`item_requests` 是扁平 `{name, quality, count}` 的 ReadOnly 聚合视图；`insert_plan` 才是带 `{id, items.in_inventory[]}` 结构的 per-slot 列表。要把模块 / 弹药按蓝图指定的槽位插进实体，**必须**走 `insert_plan`。旧代码读 `item_requests` 按 `BlueprintInsertPlan` 解析会静默失败（每个元素的 `.id` 都是 nil）。
- **`ghost.revive{}` 要显式传 `return_item_request_proxy = true`**：这个参数在 API 页上没文档，但 2.x 时代的实测 Mod（quantum-fabrication 等）都这么传。不传可能拿不到 proxy。
- **蓝图里的永续管 / 永续箱要在 revive 后锁定**：蓝图字符串本身不改；`build_blueprint` 只给 ghost，必须等 `ghost.revive{...}` 返回真实 `LuaEntity` 后才能设置 `minable_flag` / `destructible` / `operable` / `rotatable`。`operable=false` 会禁止玩家打开作弊实体 GUI，但不应阻断 inserter 或管网抽取。

## 本地化

`locale/zh-CN/zh-CN.cfg` 的 `[mod-name]` / `[mod-description]` key 必须等于 `info.json` 的 `name = "BestLanding"`。曾经有过 `factorio_BestLanding` 的错位，1.2.0 已修。

## 语言约定

- Lua 代码注释、`AGENTS.md`：**中文**。改到已有文件时，双语注释只保留中文那一半；新注释只写中文。
- `README.md`、`changelog.txt`、`info.json` 的 `description` / `title`、Mod portal 上对外展示的内容：**英文**。已有双语条目下次改到时切换成纯英文。
- `locale/*.cfg` 按对应语言写。
- 版权头 `-- Copyright The MRNIU/factorio_BestLanding Contributors` 必须保留。
- 技术标识符不翻译，用反引号保留原样。

## Factorio API 参考

- Wiki：<https://wiki.factorio.com/>
- Mod 站：<https://mods.factorio.com/>
- Mod settings 教程：<https://wiki.factorio.com/Tutorial:Mod_settings>
- Prototype API（data 阶段）：<https://lua-api.factorio.com/latest/index-prototype.html>
- Runtime API（control 阶段）：<https://lua-api.factorio.com/latest/index-runtime.html>

本 Mod 常用的运行时 API：
- `LuaSurface::find_entities`、`find_entities_filtered`、`create_entity`、`set_tiles`、`request_to_generate_chunks`、`force_generate_chunk_requests`、`find_non_colliding_position`
- `LuaSurface::planet`（太空平台上为 nil，可以用来过滤）
- `LuaItemStack::import_stack`、`get_blueprint_entities`、`get_blueprint_tiles`、`build_blueprint`
- `LuaEntity::revive{ raise_revive, return_item_request_proxy }`
- `LuaEntity::insert_plan`（array[BlueprintInsertPlan]，per-slot 蓝图插入计划）vs `LuaEntity::item_requests`（扁平 ItemWithQualityCounts，只读聚合）
- `defines.build_mode.forced`
- `defines.events.on_init`、`on_surface_created`
