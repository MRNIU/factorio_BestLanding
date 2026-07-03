# AGENTS.md

本文档为 Claude Code（claude.ai/code）在本仓库中工作时提供指引。

## 项目定位

Factorio 2.1 Mod（`BestLanding`），用 Lua 编写。仓库本身即是部署的 Mod——以 `%APPDATA%/Factorio/mods/BestLanding/` 的形式被游戏直接加载。没有构建步骤、没有包管理器、没有测试。改代码后重启 Factorio（或重载存档）即生效。

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
- **语法检查 / 预提交**：改完任何 `.lua` 后跑一次 `for f in *.lua; do luac5.4 -p "$f" || break; done`（全 Mod 扫一遍 < 100ms），能抓 `end` 缺失 / 括号不匹配 / 字符串没闭合等语法问题；**不查语义**（undefined global、类型错误等）。提交前养成这个习惯可以避免把纯语法错推到 Mod portal。
- **调试**：`.vscode/launch.json` 使用 Factorio Modding Tool Kit 2.1+ 的原生 `factorio` 调试适配器（Factorio 2.1 的 `--dap`），追控制流时优先用它。
- **打包发布**：打包为 `BestLanding_<version>.zip`，压缩包最外层是文件夹本身。版本号必须和 `info.json`、`changelog.txt` 顶条一致。
- **Changelog 格式**：Factorio 严格格式（99 个 `-`、`Version:`、`Date:`、缩进 `Changes:`），英文。

## 架构

纯运行时，一条 pipeline。`control.lua` 只做事件分发 + 顺序调用四个阶段模块；全部业务知识压在 `planets.lua` 这张配置表里。

### 文件职责

- **`control.lua`** — 事件注册 + `run_pipeline(surface)`。
  - `script.on_init(...)` 对 Nauvis 跑一次（`on_surface_created` 对新存档时已存在的 Nauvis 不触发）。
  - `script.on_event(on_surface_created, ...)` 对其他行星触发，用 `surface.planet ~= nil` 排除太空平台。
  - pipeline 顺序：`clean_area.run` → `place_resources.run` → `apply_blueprint.run`。
  - 资源生成模式由 runtime-global 设置 `BestLanding-resource-placement-mode` 控制：`auto` 会在起始蓝图含 mining drill / offshore pump / pumpjack 时跳过固定固体矿 / 普通 tile / fluid，改由蓝图驱动铺资源；`fixed` 强制只用 `origin + bands` 固定资源；`blueprint` 强制跳过固定资源并尝试按蓝图实体铺资源。起始蓝图关闭时固定资源仍作为 fallback 生成。

- **`constants.lua`** — 所有魔数的唯一出处：`CLEAR_RADIUS=224`、`RESOURCE_SLOT_SIZE=32`、`ORE_BAND_WIDTH=32`、`ORE_BAND_HEIGHT=32`、`TILE_RESOURCE_WIDTH=4`、`TILE_RESOURCE_HEIGHT=8`、`GLEBA_TILE_BAND_WIDTH=32`、`GLEBA_TILE_BAND_HEIGHT=64`、`ORE_PER_TILE=8192`、`FLUID_AMOUNT=0xFFFFFFFF`（uint32 上限，修掉旧代码 `8192*1024*512 = 2^32` 溢出）、`ENEMY_EXPAND`、`GLEBA_TREE_DENSITY`。

- **`planets.lua`** — 五颗行星的 single source of truth。每颗一个 `{ default_tile, enemy_cleanup, origin, bands, blueprint_mining?, blueprint_tile_resources?, blueprint_fluid_sources? }`。`bands` 是有序数组，每条 `{ kind = "ore"|"tile"|"fluid", name, plant? }`，主要作为蓝图关闭时或资源模式为 `fixed` 时的 fallback；固体矿默认占一个 32×32 资源槽；普通 tile / fluid 共用一个 32×32 资源槽里的 4×8 小格，并按固定锚点分散到槽内，避免油井和水/lava 等 tile 贴得太近；带 `plant` 的 Gleba tile 暂时保持 32×64 大条布局。`blueprint_mining.resources` / `blueprint_tile_resources.resources` / `blueprint_fluid_sources.resources` 分别定义蓝图里的矿机 / offshore pump / pumpjack 列从左到右对应的资源顺序，默认每 2 列实体一组。

- **`chunks.lua`** — `force_generate` / `force_generate_ring`。批量 `request_to_generate_chunks` + 单次 `force_generate_chunk_requests` 是官方推荐姿势。ring 变体用于 Vulcanus Demolisher 扫描扩围：清理区已经由 `force_generate` 生成过，只补外环 chunk 就够了。

- **`clean_area.lua`** — `run(surface, cfg)` + `clean_blueprint_area(surface, area)`。
  - `run` 流程：`force_generate` 清理区 → `find_entities` 一次扫光非玩家实体（不再第二次 filter 资源 / 悬崖，`find_entities` 已经包含）→ `cleanup_enemies` 按 `cfg.enemy_cleanup.filters` 清扩围 → `set_tiles` 全刷 `cfg.default_tile`。
  - `clean_blueprint_area` 给 `apply_blueprint` 用，只清树 / 简单实体 / 悬崖，不动矿。

- **`place_resources.lua`** — `run(surface, cfg, opts)` 遍历 `cfg.bands`，按 kind 走三个分支；`opts.skip_blueprint_driven=true` 时跳过固定固体矿、普通 tile、fluid，只保留 Gleba 果树土条等非蓝图驱动资源。`place_blueprint_resources(surface, cfg, entities, transform)` 在蓝图 build 前扫描 mining drill / offshore pump / pumpjack，按 x 坐标归并成列，从左到右每 `columns_per_resource` 列对应配置里的一个资源，并分别在矿机采矿半径内 `create_entity` 固体矿、在 offshore pump 的 source tile 附近 `set_tiles`、在 pumpjack 中心 `create_entity` 流体源。普通 tile / fluid fallback 共享一个 32×32 资源槽并按 4×8 小格对齐；小格不再顺序紧贴排布，而是先落到槽内分散锚点，流体源在小格中心单次 `create_entity` amount=`FLUID_AMOUNT`。Gleba 的 `tile` 条如果带 `plant = "yumako"|"jellynut"`，暂时走 32×64 大条布局，`set_tiles` 完后按 `GLEBA_TREE_DENSITY` 概率 `create_entity` 果树。**果树名字注意**：yumako 树是 `"yumako-tree"`，但 jellynut 树叫 `"jellystem"`（"jellynut" 是果子 item，不是树 entity）。**成熟**靠设 `tree.tick_grown = game.tick`——Gleba 果树是 `PlantPrototype`，成熟判定看 `tick_grown` 这个 MapTick，不是 `tree_stage_index`（后者只影响贴图阶段）。

- **`apply_blueprint.lua`** — `run(surface, cfg)`。遍历 `blueprints` 表匹配 `surface.name`（小写比较）。单个蓝图流程：
  1. 临时 `game.create_inventory(1)` + `stack.import_stack(...)` + 校验 `valid_for_read and is_blueprint`。
  2. `compute_aabb` — **把蓝图本地坐标按 anchor + direction 变换到 surface 坐标**再算 AABB。这是修过的 bug：旧代码直接拿 blueprint-relative 坐标当 surface 坐标用，只因所有蓝图 `pos={0,0} direction=0` 巧合工作。
  3. `clean.clean_blueprint_area(surface, aabb)` 清树 / 简单实体 / 悬崖。
  4. `place_resources.place_blueprint_resources(...)` 根据蓝图里的矿机 / offshore pump / pumpjack 列，先铺对应固体矿、地块资源和流体源。
  5. `stack.build_blueprint{ build_mode = defines.build_mode.forced }`。forced 模式下 tile 直接落地，**不再手动 `set_tiles`**（旧代码那段是冗余且坐标没变换）。
  6. 对每个 ghost 调 `revive{ raise_revive = false, return_item_request_proxy = true }`，再走 `fulfill_item_requests`。
  7. 如果 revive 出来的实体是 `infinity-container` / `infinity-pipe` / `infinity-cargo-wagon`，立刻设 `minable_flag=false`、`destructible=false`、`operable=false`、`rotatable=false`。这类蓝图里的作弊供给实体只作为只读补给源存在：玩家不能打开设置界面、旋转、拆除或破坏它们，但 inserter / 管网仍然可以从里面取物品或抽流体。
  - `fulfill_item_requests` — **用 `proxy.insert_plan`，不是 `proxy.item_requests`**。LuaEntity 上这两个字段格式完全不同：
    - `LuaEntity::item_requests :: ItemWithQualityCounts`（只读）—— 扁平 `[{name, quality, count}, ...]`，没有 slot 信息
    - `LuaEntity::insert_plan :: array[BlueprintInsertPlan]`（读写）—— per-slot `[{id={name, quality}, items={in_inventory=[{inventory, stack, count}, ...], grid_count?}}, ...]`

    模块 / 过滤器 / 弹药要进对的 inventory，必须走 `insert_plan` 拿 `slot.inventory`（`defines.inventory.*` 编号）再 `entity.get_inventory(slot.inventory):insert{...}`。对回收机尤其关键：模块的 `slot.inventory` 是 `assembling_machine_modules`，按这个走进模块槽、**不会被当作回收原料**。
    
    注意 `slot.count` 可选，省略时默认 1——传 `nil` 给 `LuaInventory::insert` 会静默插 0 件。必须 `slot.count or 1`。
    
    参考实现：<https://github.com/refulgence/quantum-fabrication/blob/main/scripts/builder.lua>
  - 整段用 `pcall` 包起来，即便中途抛错也保证 `inventory.destroy()` 跑到。

- **`blueprints.lua`** — 五颗行星各一个蓝图字符串 + 一个 `{ name, data, pos, direction }` 列表。`apply_blueprint` 的匹配是 `string.lower(bp.name) == string.lower(surface.name)`，所以表里大小写怎么写都行。

### 星球配置 → 资源 → 蓝图 的契约

`planets.lua` 里每颗星球的 `origin + bands` 决定蓝图关闭时或资源模式为 `fixed` 时 fallback 资源在 surface 上的落点；资源模式为 `blueprint`，或资源模式为 `auto` 且起始蓝图包含 mining drill / offshore pump / pumpjack 时，固体矿 / 地块资源 / 流体源位置分别由蓝图里的 mining drill / offshore pump / pumpjack 列决定，资源类型由 `blueprint_mining.resources` / `blueprint_tile_resources.resources` / `blueprint_fluid_sources.resources` 决定。所以：

- 改 `origin` / `bands` 顺序 / band 宽高 = 蓝图关闭时 fallback 资源落点会变。
- 改 `blueprint_*_resources.resources` 顺序 = 从左到右的实体列组对应资源会变。
- 改 band 的 `name`（资源类型） = fallback 资源类型会变。
- 改 `ORE_PER_TILE` / `FLUID_AMOUNT` = 安全（只是数值，蓝图不依赖）。

### 状态模型（Factorio 2.1）

目前不维护任何持久状态，`storage` 是空的。如果以后需要，记得在 `on_init` 里初始化。

## 常见坑

- **`find_entities_*` / `set_tiles` 之前 chunk 必须先生成完**：未生成的 chunk 上前者返回空、后者无效果。`clean_area.lua` 和 `apply_blueprint` 的 `clean_blueprint_area` 都先走 `chunks.force_generate`。
- **Demolisher 的领地会越过本体位置**：`ENEMY_EXPAND.vulcanus = 300` 不是拍脑袋，缩了会让领地重新覆盖着陆区。
- **资源条 amount 是 uint32**：`FLUID_AMOUNT` 必须 ≤ `0xFFFFFFFF`。旧代码 `8192*1024*512 = 2^32` 溢出。
- **`item_requests` 和 `insert_plan` 是两个不同字段**（Factorio 2.1 里仍然最容易踩的陷阱）：`item_requests` 是扁平 `{name, quality, count}` 的 ReadOnly 聚合视图；`insert_plan` 才是带 `{id, items.in_inventory[]}` 结构的 per-slot 列表。要把模块 / 弹药按蓝图指定的槽位插进实体，**必须**走 `insert_plan`。旧代码读 `item_requests` 按 `BlueprintInsertPlan` 解析会静默失败（每个元素的 `.id` 都是 nil）。
- **`ghost.revive{}` 要显式传 `return_item_request_proxy = true`**：这个参数在 API 页上没文档，但 2.x 时代的实测 Mod（quantum-fabrication 等）都这么传。不传可能拿不到 proxy。
- **Gleba 果树命名坑**：yumako 的树是 `"yumako-tree"`，jellynut 的树叫 `"jellystem"`——"jellynut" 只是果子 item 的名字。猜错名字会导致半个星球的 soil 上没树。
- **Gleba 果树成熟靠 `tick_grown`，不是 `tree_stage_index`**：`PlantPrototype` 的成熟判定看 `LuaEntity::tick_grown` 这个 MapTick，`tree_stage_index` 只影响贴图阶段。要让树一落地就能采，设 `tree.tick_grown = game.tick`。
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
- `LuaEntity::tick_grown`、`tree_stage_index`、`tree_stage_index_max`（Gleba PlantPrototype 成熟判定）
- `defines.build_mode.forced`
- `defines.events.on_init`、`on_surface_created`
