# CLAUDE.md

本文档为 Claude Code（claude.ai/code）在本仓库中工作时提供指引。

## 项目定位

Factorio 2.0 Mod（`BestLanding`），用 Lua 编写。仓库本身即是部署的 Mod——以 `%APPDATA%/Factorio/mods/BestLanding/` 的形式被游戏直接加载。没有构建步骤、没有包管理器、没有测试。改代码后重启 Factorio（或重载存档）即生效。

`info.json` 声明的依赖：`base >= 2.0.76`、`space-age`、`quality`。本 Mod 仅运行时，覆盖 Space Age 所有五颗行星 surface（`nauvis`、`vulcanus`、`gleba`、`fulgora`、`aquilo`）。

## 常用命令

- **运行 / 迭代**：启动 Factorio，启用本 Mod，开新游戏（或者着陆到新行星触发第二次及以后的清理）。（注：Claude Code 跑在 WSL、Mod 文件通过 Windows 挂载访问，Claude 无法直接启动 Factorio 或 FactorioModDebug；运行验证需要你在 Windows 侧手工操作。）
- **语法检查**：`luac5.4 -p <file>.lua` 可以对 Lua 文件做 parse-only 校验，快速发现 `end` 缺失 / 括号不匹配等语法问题。不检查语义（undefined global、类型等）。
- **调试**：`.vscode/launch.json` 里配好了 [FactorioModDebug](https://marketplace.visualstudio.com/items?itemName=justarandomgeek.factoriomod-debug) 的启动项，追控制流时优先用它。
- **打包发布**：打包为 `BestLanding_<version>.zip`，压缩包最外层是文件夹本身。版本号必须和 `info.json`、`changelog.txt` 顶条一致。
- **Changelog 格式**：Factorio 严格格式（99 个 `-`、`Version:`、`Date:`、缩进 `Changes:`），英文。

## 架构

纯运行时。四个模块由 `control.lua` 串起来：

- **`control.lua`** — 两个事件处理器。每次着陆都跑同一个四步流水线：
  1. `area_cleaner.clear_center_area(surface)` — 清空 (0,0) 周边 448×448 的正方形，并铺上该星球对应的默认地表。
  2. `generate_resources.generate_resource_planet(surface)` — 根据星球铺矿 / 流体源 / 特殊 tile。
  3. `ApplyBlueprints(surface)` — 在 `blueprint.lua` 里找一个名字（不区分大小写）和当前 surface 匹配的蓝图并应用。
  4. `legendary_spider.spawn_legendary_spider(surface, {x=0, y=0})` — 生成一辆预配好装备和补给的传奇蜘蛛机甲。

  两个事件钩子：`script.on_init(OnInit)`（新游戏时 Nauvis 触发一次）和 `script.on_event(on_surface_created, OnSurfaceCreated)`（每当新行星 surface 生成时触发，用 `surface.planet ~= nil` 排除轨道平台）。

- **`area_cleaner.lua`** — `clear_center_area` / `clean_blueprint_area`。内部先走 `force_generate_chunks`（把区域向下取整到 32 tile 的 chunk 边界 → `request_to_generate_chunks` → `force_generate_chunk_requests`），否则 `find_entities_filtered` 在未生成的地形上会静默返回空。Vulcanus 多一趟：在扩大 300 tile 的外围里猎杀 `segmented-unit`（Demolisher），因为它们的领地能越过清理区的边界。

- **`generate_resources.lua`** — 把资源按放置方式分三类：
  - **Tile 资源**（`water`、`lava`、`oil-ocean-shallow`、`gleba-deep-lake`、`ammoniacal-ocean`、过增殖土）→ `surface.set_tiles`。
  - **流体资源**（`crude-oil`、`sulfuric-acid-geyser`、`lithium-brine`、`fluorine-vent`）→ 在区域中心单次 `create_entity`，`amount = amount`（传参前 `amount` 已经被乘过 `1024*512`——见 `generate_resource_nauvis`/`vulcanus`/`aquilo`）。
  - **矿石资源** → 区域内每个 tile 都 `create_entity` 一次。

  每颗行星的起点都是手选的（Nauvis 在 `{-112, -224}`，其余的 Vulcanus/Fulgora/Gleba/Aquilo 都是 `{-80, -224}`）。资源条宽 32、高 64、零间距。

- **`blueprint.lua`** — 五颗行星各一个蓝图字符串 + 一个 `{ name, data, pos, direction }` 列表。`control.lua` 里的匹配是 `string.lower(bp.name) == string.lower(surface.name)`，所以表里大小写怎么写都行。

- **`legendary_spider.lua`** — `spawn_legendary_spider(surface, position, force)` 先调 `find_non_colliding_position("spidertron", position, 128, 1)` 避开蓝图实体，再 `create_entity{ name = "spidertron", quality = "legendary" }`。蜘蛛自带 `.grid`（不像装甲那样要先拿 item stack），`init_legendary_spider_armor` 按手摆坐标填满一个 15×11 的装备网格。货仓用 `defines.inventory.spider_trunk`、弹药用 `defines.inventory.spider_ammo`。

### 蓝图应用流水线（`ApplyBlueprint`）

和 `LegendaryShipStart` 的那套形状一样，但目标是行星 surface 而不是太空平台：

1. `game.create_inventory(1)` → `stack.import_stack(blueprint_string)` → 用 `stack.valid_for_read and stack.is_blueprint` 校验。
2. 遍历 `get_blueprint_entities()` / `get_blueprint_tiles()` 算 AABB，然后 `area_cleaner.clean_blueprint_area`（只清树 / 岩石 / 悬崖，**不动矿**）。
3. `surface.set_tiles(...)` 铺蓝图 tile。
4. `stack.build_blueprint{ build_mode = defines.build_mode.forced, skip_fog_of_war = false }` → 对每个返回的 ghost 调 `revive({ raise_revive = true })`；如果顺带返回 `item_request_proxy` 就把 `item_requests` 灌进实体，这样蓝图里序列化的模块 / 过滤器 / 弹药才会真正进入实体。
5. 销毁临时库存。

### 状态模型（Factorio 2.0）

目前不维护任何持久状态，`storage` 是空的。如果以后需要，记得在 `on_init` 里初始化。

## 常见坑

- **`find_entities_*` / `set_tiles` 之前 chunk 必须先生成完。** `area_cleaner.lua` 里所有函数都先走 `force_generate_chunks` 就是这个原因。
- **Demolisher 的领地会越过本体位置。** `clear_area_to_land` 里 300 tile 的扩围不是随便设的，缩了会让领地重新覆盖着陆区。
- **`find_non_colliding_position` 可能返回 nil。** `spawn_legendary_spider` 拿不到安全位置时会退回原位置，后续 `create_entity` 就可能失败。如果以后调小搜索半径要注意。
- **蓝图条目虽然带 `pos` 和 `direction`**，但五个都是 `{x=0, y=0}` 和 `0`。以后如果蓝图要偏移原点，记得确认 `ApplyBlueprint` 里的 chunk 生成仍然覆盖了新的 AABB（它是按 entities/tiles 算的，理论上会自动跟上——但还是验一下）。

## 本地化

`locale/zh-CN/zh-CN.cfg` 里 `[mod-name]` / `[mod-description]` 用的 key 是 `factorio_BestLanding`，但 `info.json` 的 `name` 是 `BestLanding`。两边必须一致 Factorio 才会匹配——已知不一致，动本地化时顺手改掉。

## 语言约定

- Lua 代码注释、`CLAUDE.md`：**中文**。改到已有文件时，双语注释只保留中文那一半；新注释只写中文。
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
- `LuaEntity::revive{ raise_revive = true }` 以及 `item_request_proxy.item_requests`
- `defines.inventory.spider_trunk`、`defines.inventory.spider_ammo`
- `defines.build_mode.forced`
- `defines.events.on_init`、`on_surface_created`
