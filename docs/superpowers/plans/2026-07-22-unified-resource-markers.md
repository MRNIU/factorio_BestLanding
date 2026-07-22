# Unified Resource Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace planet- and column-driven starter resources with one Mining-layer constant-combinator contract that drives solid resources, underground fluid resources, offshore fluid tiles, and every item-backed placeable tile.

**Architecture:** Add a pure `resource_zones.lua` module for marker grouping and prototype resolution, then make `place_resources.lua` the Factorio runtime adapter that selects devices, diagnoses ambiguous blueprints, and executes every parsed zone directly. `apply_blueprint.lua` invokes the pipeline only for level 3, while `planets.lua` loses all resource mappings.

**Tech Stack:** Factorio 2.1 runtime Lua, Lua 5.4 standalone tests with hand-written fakes, `luac5.4`, Python 3 only for blueprint and metadata audit commands, git.

## Global Constraints

- Work only in `/mnt/c/Users/nzh/AppData/Roaming/Factorio/mods/BestLanding`.
- Preserve the copyright header in every Lua file; write Lua comments in Chinese.
- Write `README.md`, `changelog.txt`, and `info.json` display text in English.
- Keep `factorio_version` at `2.1` and dependencies at `base >= 2.1.9`, `space-age`, and `quality`.
- Do not add `data.lua`, `data-final-fixes.lua`, persistent `storage`, migration logic, or compatibility fallbacks.
- Invoke resource placement only for blueprint `level == 3`; level 4 receives resources only because level 3 is applied cumulatively.
- Use `BestLanding:resource-zone`, one normal-quality signal, and a positive integer count as the paired zone ID.
- Do not select resources from planet names or X-column order.
- Support every item whose `LuaItemPrototype::place_as_tile_result` exists.
- Diagnose overlap and conflict without allowing diagnostics to filter, deduplicate, reorder, or otherwise change direct execution.
- Preserve the user's existing uncommitted `blueprints.lua`; never restore it and never stage it unless the user separately authorizes a blueprint-string correction.
- Codex cannot launch Factorio from WSL; runtime verification remains a Windows-side manual step.
- Read the approved design before implementation: `docs/superpowers/specs/2026-07-22-unified-resource-markers-design.md`.
- Before each behavior-changing task, invoke `superpowers:test-driven-development` and preserve the documented red-green evidence.

## File Structure

- Create `resource_zones.lua`: pure marker validation, zone grouping, resource-product indexing, item-to-tile resolution, and fluid-to-tile resolution. It performs no surface mutation and emits issue records instead of logging directly.
- Create `tests/testlib.lua`: minimal dependency-free Lua test helpers.
- Create `tests/run.lua`: deterministic standalone test entrypoint.
- Create `tests/test_resource_zones.lua`: unit tests for marker and prototype resolution.
- Create `tests/test_place_resources.lua`: fake-surface tests for device selection, footprints, diagnostics, and direct execution.
- Modify `place_resources.lua`: build placement operations from resolved zones, run non-authoritative diagnostics, then execute all operations without overlap suppression.
- Modify `apply_blueprint.lua`: remove its resource `cfg` parameter, pass the entry level into `apply`, and call resources only at level 3.
- Modify `control.lua`: stop passing the planet configuration to `apply_blueprint.run` while continuing to pass it to `clean_area.run`.
- Modify `planets.lua`: retain cleanup configuration and delete all resource configuration.
- Modify `AGENTS.md`, `README.md`, `changelog.txt`, and `info.json`: document the latest-only 2.0.0 contract.

---

### Task 1: Pure Marker and Prototype Resolver

**Files:**
- Create: `resource_zones.lua`
- Create: `tests/testlib.lua`
- Create: `tests/run.lua`
- Create: `tests/test_resource_zones.lua`

**Interfaces:**
- Produces: `resource_zones.is_marker(entity, entity_prototypes) -> boolean`
- Produces: `resource_zones.collect(entities, transform, entity_prototypes) -> zones, issues`
- Produces: `resource_zones.build_resource_index(entity_prototypes) -> {item=map, fluid=map}`
- Produces: `resource_zones.resolve(zone, indexes, item_prototypes, tile_prototypes) -> targets, issues`
- Produces: `resource_zones.position_in_zone(position, zone) -> boolean`
- `targets` has optional string fields `entity_resource`, `place_tile`, and `offshore_tile`.
- `issues` is an array of `{kind=string, message=string}` records; this module never calls global `log`.

- [ ] **Step 1: Create the standalone test harness**

Create `tests/testlib.lua` with a small assertion API and `tests/run.lua` with a fixed module list:

```lua
-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 最小化的无依赖 Lua 测试助手。

local M = { total = 0, failed = 0 }

function M.equal(actual, expected, message)
    M.total = M.total + 1
    if actual ~= expected then
        M.failed = M.failed + 1
        io.stderr:write((message or "values differ")
            .. (": expected %s, got %s\n"):format(tostring(expected), tostring(actual)))
    end
end

function M.truthy(actual, message)
    M.equal(not not actual, true, message)
end

function M.finish()
    if M.failed > 0 then
        io.stderr:write(("FAIL %d/%d assertions\n"):format(M.failed, M.total))
        os.exit(1)
    end
    print(("PASS %d assertions"):format(M.total))
end

return M
```

```lua
-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 顺序加载所有独立 Lua 测试。

package.path = "./?.lua;./tests/?.lua;" .. package.path

local T = require("testlib")
require("test_resource_zones")(T)
T.finish()
```

- [ ] **Step 2: Write resolver tests before the module exists**

Create `tests/test_resource_zones.lua`. Use an identity transform and fake prototypes shaped like Factorio runtime prototypes. Cover these exact assertions:

```lua
-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 校验资源区域标记和原型解析。

return function(T)
    local R = require("resource_zones")

    local entity_prototypes = {
        ["constant-combinator"] = { type = "constant-combinator" },
        ["iron-ore"] = {
            type = "resource",
            mineable_properties = { products = {{type = "item", name = "iron-ore"}} },
        },
        ["sulfuric-acid-geyser"] = {
            type = "resource",
            mineable_properties = { products = {{type = "fluid", name = "sulfuric-acid"}} },
        },
        ["fluorine-vent"] = {
            type = "resource",
            mineable_properties = { products = {{type = "fluid", name = "fluorine"}} },
        },
    }
    local item_prototypes = {
        ["iron-ore"] = { name = "iron-ore" },
        ["artificial-yumako-soil"] = {
            name = "artificial-yumako-soil",
            place_as_tile_result = { name = "artificial-yumako-soil" },
        },
    }
    local tile_prototypes = {
        water = { name = "water", fluid = { name = "water" } },
        deepwater = { name = "deepwater", fluid = { name = "water" } },
        ["oil-ocean-deep"] = { name = "oil-ocean-deep", fluid = { name = "heavy-oil" } },
        ["oil-ocean-shallow"] = { name = "oil-ocean-shallow", fluid = { name = "heavy-oil" } },
        ["ammoniacal-ocean"] = { name = "ammoniacal-ocean", fluid = { name = "ammoniacal-solution" } },
        ["ammoniacal-ocean-2"] = { name = "ammoniacal-ocean-2", fluid = { name = "ammoniacal-solution" } },
    }

    local function marker(number, x, y, signal_type, name, count)
        return {
            entity_number = number,
            name = "constant-combinator",
            position = {x = x, y = y},
            player_description = "BestLanding:resource-zone",
            control_behavior = { sections = { sections = {{ filters = {{
                type = signal_type, name = name, quality = "normal", count = count,
            }} }} } },
        }
    end
    local function identity(entity)
        return {position = entity.position, direction = entity.direction or 0}
    end

    local zones, issues = R.collect({
        marker(1, 0, 0, "item", "iron-ore", 1),
        marker(2, 10, 10, "item", "iron-ore", 1),
        marker(3, 20, 0, "fluid", "water", 2),
        marker(4, 30, 10, "fluid", "water", 2),
    }, identity, entity_prototypes)
    T.equal(#issues, 0, "paired markers are valid")
    T.equal(#zones, 2, "two zones collected")
    T.equal(zones[1].signal_type, "fluid", "zones sort by signal type")
    T.truthy(R.position_in_zone({x = 20, y = 0}, zones[1]), "boundary is inclusive")

    local index = R.build_resource_index(entity_prototypes)
    local iron = R.resolve({signal_type="item", signal_name="iron-ore"}, index,
        item_prototypes, tile_prototypes)
    T.equal(iron.entity_resource, "iron-ore", "item product resolves resource")

    local soil = R.resolve({signal_type="item", signal_name="artificial-yumako-soil"},
        index, item_prototypes, tile_prototypes)
    T.equal(soil.place_tile, "artificial-yumako-soil", "all place-as-tile items resolve")

    local acid = R.resolve({signal_type="fluid", signal_name="sulfuric-acid"},
        index, item_prototypes, tile_prototypes)
    T.equal(acid.entity_resource, "sulfuric-acid-geyser", "fluid product resolves geyser")

    local water = R.resolve({signal_type="fluid", signal_name="water"},
        index, item_prototypes, tile_prototypes)
    T.equal(water.offshore_tile, "water", "same-name fluid tile wins")

    local oil = R.resolve({signal_type="fluid", signal_name="heavy-oil"},
        index, item_prototypes, tile_prototypes)
    T.equal(oil.offshore_tile, "oil-ocean-shallow", "heavy-oil alias resolves")

    local ammonia = R.resolve({signal_type="fluid", signal_name="ammoniacal-solution"},
        index, item_prototypes, tile_prototypes)
    T.equal(ammonia.offshore_tile, "ammoniacal-ocean", "ammonia alias resolves")
end
```

Add these explicit invalid-input cases before the test function returns:

```lua
    local _, unpaired_issues = R.collect({
        marker(10, 0, 0, "item", "iron-ore", 9),
    }, identity, entity_prototypes)
    T.truthy(#unpaired_issues > 0, "unpaired marker is reported")

    local multiple = marker(11, 0, 0, "item", "iron-ore", 10)
    multiple.control_behavior.sections.sections[1].filters[2] = {
        type="item", name="artificial-yumako-soil", quality="normal", count=10,
    }
    local _, multiple_issues = R.collect({multiple}, identity, entity_prototypes)
    T.truthy(#multiple_issues > 0, "multiple filters are reported")

    local legendary = marker(12, 0, 0, "item", "iron-ore", 11)
    legendary.control_behavior.sections.sections[1].filters[1].quality = "legendary"
    local _, quality_issues = R.collect({legendary}, identity, entity_prototypes)
    T.truthy(#quality_issues > 0, "non-normal quality is reported")

    local zero = marker(13, 0, 0, "item", "iron-ore", 0)
    local _, count_issues = R.collect({zero}, identity, entity_prototypes)
    T.truthy(#count_issues > 0, "non-positive zone id is reported")

    entity_prototypes["rare-spring-a"] = {
        type="resource",
        mineable_properties={products={{type="fluid", name="rare-slurry"}}},
    }
    entity_prototypes["rare-spring-b"] = {
        type="resource",
        mineable_properties={products={{type="fluid", name="rare-slurry"}}},
    }
    local ambiguous_index = R.build_resource_index(entity_prototypes)
    local ambiguous, ambiguous_issues = R.resolve(
        {signal_type="fluid", signal_name="rare-slurry"},
        ambiguous_index, item_prototypes, tile_prototypes
    )
    T.equal(ambiguous.entity_resource, nil, "ambiguous resource is unresolved")
    T.truthy(#ambiguous_issues > 0, "ambiguous resource candidates are reported")
```

- [ ] **Step 3: Run the tests and verify the expected failure**

Run:

```bash
lua5.4 tests/run.lua
```

Expected: FAIL while loading `resource_zones`, with `module 'resource_zones' not found`.

- [ ] **Step 4: Implement `resource_zones.lua` minimally**

Start with this exact module shape and keep Factorio mutation out of it:

```lua
-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 统一解析蓝图资源区域标记，并把信号映射到资源或地格原型。

local M = {}

local DESCRIPTION = "BestLanding:resource-zone"
local TILE_ALIASES = {
    ["heavy-oil"] = "oil-ocean-shallow",
    ["ammoniacal-solution"] = "ammoniacal-ocean",
}

local function issue(kind, message)
    return {kind = kind, message = message}
end

local function fluid_name(tile)
    local fluid = tile and tile.fluid
    return type(fluid) == "table" and fluid.name or fluid
end

function M.is_marker(entity, entity_prototypes)
    local proto = entity and entity_prototypes[entity.name]
    return proto and proto.type == "constant-combinator"
        and entity.player_description == DESCRIPTION
end

function M.position_in_zone(position, zone)
    return position.x >= zone.left and position.x <= zone.right
        and position.y >= zone.top and position.y <= zone.bottom
end
```

Complete the public interfaces with these exact algorithms:

- Treat missing `filter.type` as `item`.
- Group markers with a collision-safe composite key containing type, name, quality, and zone ID.
- Sort zones by type, name, quality, then numeric zone ID.
- Iterate every resource prototype's `mineable_properties.products or {}` and sort candidate name arrays.
- For exact-name preference, select it only from the already product-matched candidates.
- `place_as_tile_result` and `tile.fluid` can be prototype objects; read their `.name` fields.
- For offshore tiles, try same-name matching first, unique-fluid matching second, then the two approved aliases.
- Return issues for unresolved ambiguity; do not guess.

- [ ] **Step 5: Run the resolver tests**

Run:

```bash
lua5.4 tests/run.lua
luac5.4 -p resource_zones.lua tests/testlib.lua tests/run.lua tests/test_resource_zones.lua
```

Expected: the runner prints `PASS` with zero failed assertions; `luac5.4` exits 0 without output.

- [ ] **Step 6: Commit the pure resolver**

```bash
git add -- resource_zones.lua tests/testlib.lua tests/run.lua tests/test_resource_zones.lua
git commit -m "feat: resolve unified resource markers"
```

Do not stage `blueprints.lua`.

---

### Task 2: Unified Runtime Placement and Non-Authoritative Diagnostics

**Files:**
- Modify: `place_resources.lua:1-570`
- Create: `tests/test_place_resources.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes: `resource_zones.collect`, `build_resource_index`, `resolve`, and `position_in_zone` from Task 1.
- Preserves: `place_resources.is_resource_zone_marker(entity) -> boolean` for marker ghost deletion.
- Changes: `place_resources.place_blueprint_resources(surface, entities, transform)` no longer accepts `cfg`.
- Produces: direct placement attempts plus aggregate diagnostic and failure logs.

- [ ] **Step 1: Write fake-surface placement tests**

Create `tests/test_place_resources.lua` and add `require("test_place_resources")(T)` to `tests/run.lua` before `T.finish()`.

The test must define global `prototypes` and `log` before requiring `place_resources`. Use a fake surface that records every operation without rejecting overlaps:

```lua
-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 用伪造 surface 校验资源设备分派和直接执行。

return function(T)
    package.loaded.place_resources = nil
    package.loaded.resource_zones = nil

    local logs = {}
    _G.log = function(message) logs[#logs + 1] = message end
    _G.prototypes = {
        entity = {
            ["constant-combinator"] = {type = "constant-combinator"},
            ["big-mining-drill"] = {
                type = "mining-drill",
                get_mining_drill_radius = function() return 1 end,
            },
            pumpjack = {type = "mining-drill"},
            ["agricultural-tower"] = {type = "agricultural-tower", agricultural_tower_radius = 1},
            ["offshore-pump"] = {type = "offshore-pump", fluid_source_offset = {x = 0, y = -1}},
            ["iron-ore"] = {
                type = "resource",
                mineable_properties = {products = {{type="item", name="iron-ore"}}},
            },
            ["copper-ore"] = {
                type = "resource",
                mineable_properties = {products = {{type="item", name="copper-ore"}}},
            },
            ["crude-oil"] = {
                type = "resource",
                mineable_properties = {products = {{type="fluid", name="crude-oil"}}},
            },
        },
        item = {
            ["iron-ore"] = {name="iron-ore"},
            ["copper-ore"] = {name="copper-ore"},
            ["artificial-yumako-soil"] = {
                name = "artificial-yumako-soil",
                place_as_tile_result = {name="artificial-yumako-soil"},
            },
        },
        tile = {
            water = {name="water", fluid={name="water"}},
        },
    }

    local surface = {valid=true, name="vulcanus", created={}, tile_batches={}}
    function surface.create_entity(params)
        surface.created[#surface.created + 1] = params
        return {valid=true}
    end
    function surface.set_tiles(tiles)
        surface.tile_batches[#surface.tile_batches + 1] = tiles
    end

    local function marker(number, x, y, signal_type, name, count)
        return {
            entity_number=number, name="constant-combinator", position={x=x, y=y},
            player_description="BestLanding:resource-zone",
            control_behavior={sections={sections={{filters={{
                type=signal_type, name=name, quality="normal", count=count,
            }}}}}},
        }
    end
    local function identity_transform(entity)
        return {position=entity.position, direction=entity.direction or 0}
    end
    local function count_created(created, name)
        local count = 0
        for _, params in ipairs(created) do
            if params.name == name then count = count + 1 end
        end
        return count
    end
    local function count_tiles(batches, name)
        local count = 0
        for _, batch in ipairs(batches) do
            for _, tile in ipairs(batch) do
                if tile.name == name then count = count + 1 end
            end
        end
        return count
    end

    local entities = {
        marker(1, -2, -2, "item", "iron-ore", 1),
        marker(2, 2, 2, "item", "iron-ore", 1),
        {entity_number=3, name="big-mining-drill", position={x=0.5, y=0.5}},
        marker(4, 9, -2, "item", "artificial-yumako-soil", 2),
        marker(5, 13, 2, "item", "artificial-yumako-soil", 2),
        {entity_number=6, name="agricultural-tower", position={x=11.5, y=0.5}},
        marker(7, 19, -2, "fluid", "crude-oil", 3),
        marker(8, 23, 2, "fluid", "crude-oil", 3),
        {entity_number=9, name="pumpjack", position={x=21.5, y=0.5}},
        marker(10, 29, -2, "fluid", "water", 4),
        marker(11, 35, 2, "fluid", "water", 4),
        {entity_number=12, name="offshore-pump", position={x=31.5, y=0.5}, direction=0},
        {entity_number=13, name="offshore-pump", position={x=33.5, y=0.5}, direction=0},
    }
    local P = require("place_resources")
    P.place_blueprint_resources(surface, entities, identity_transform)

    T.equal(count_created(surface.created, "iron-ore"), 9,
        "radius-one drill attempts a 3x3 ore patch")
    T.equal(count_created(surface.created, "crude-oil"), 1,
        "pumpjack attempts one fluid resource")
    T.equal(count_tiles(surface.tile_batches, "artificial-yumako-soil"), 9,
        "radius-one agricultural tower sets a 3x3 tile patch")
    T.equal(count_tiles(surface.tile_batches, "water"), 3,
        "two separated source tiles produce their minimal bounding row")

    local conflict_surface = {valid=true, name="nauvis", created={}, tile_batches={}}
    conflict_surface.create_entity = surface.create_entity
    conflict_surface.set_tiles = surface.set_tiles
    function conflict_surface.create_entity(params)
        conflict_surface.created[#conflict_surface.created + 1] = params
        return {valid=true}
    end
    function conflict_surface.set_tiles(tiles)
        conflict_surface.tile_batches[#conflict_surface.tile_batches + 1] = tiles
    end
    local conflicting = {
        marker(20, -2, -2, "item", "iron-ore", 1),
        marker(21, 2, 2, "item", "iron-ore", 1),
        marker(22, -2, -2, "item", "iron-ore", 2),
        marker(23, 2, 2, "item", "iron-ore", 2),
        marker(24, -2, -2, "item", "copper-ore", 3),
        marker(25, 2, 2, "item", "copper-ore", 3),
        {entity_number=26, name="big-mining-drill", position={x=0.5, y=0.5}},
    }
    P.place_blueprint_resources(conflict_surface, conflicting, identity_transform)
    T.equal(count_created(conflict_surface.created, "iron-ore"), 18,
        "repeated applicable zones are not deduplicated")
    T.equal(count_created(conflict_surface.created, "copper-ore"), 9,
        "conflicting target still executes")
    local conflict_logged = false
    for _, message in ipairs(logs) do
        if message:find("conflicting targets", 1, true) then conflict_logged = true end
    end
    T.truthy(conflict_logged, "conflicting targets are diagnosed")
end
```

- [ ] **Step 2: Run tests to verify failure against the old pipeline**

Run:

```bash
lua5.4 tests/run.lua
```

Expected: FAIL because the old `place_blueprint_resources` requires planet `cfg`, rejects fluid markers, has no agricultural-tower handling, and suppresses overlaps.

- [ ] **Step 3: Replace the runtime pipeline**

Rewrite `place_resources.lua` around these internal phases:

```lua
local zones = require("resource_zones")
local C = require("constants")

local cached_resource_index
local function resource_index()
    if not cached_resource_index then
        cached_resource_index = zones.build_resource_index(prototypes.entity)
    end
    return cached_resource_index
end

function M.place_blueprint_resources(surface, entities, transform)
    if not (surface and surface.valid) then return end

    local parsed_zones, parse_issues = zones.collect(entities, transform, prototypes.entity)
    log_issues(surface, parse_issues)

    local index = resource_index()
    local devices = collect_devices(entities, transform)
    local operations = {}

    for _, zone in ipairs(parsed_zones) do
        local targets, resolve_issues = zones.resolve(
            zone, index, prototypes.item, prototypes.tile
        )
        log_issues(surface, resolve_issues)
        append_zone_operations(operations, zone, targets, devices)
    end

    diagnose_operations(surface, operations)
    execute_operations(surface, operations)
    log_operation_summary(surface, operations)
end
```

Use the following execution loop so diagnostics cannot suppress placement:

```lua
local function record_failure(failures, target, x, y)
    local failure = failures[target]
    if not failure then
        failure = {count=0, first_position={x=x, y=y}}
        failures[target] = failure
    end
    failure.count = failure.count + 1
end

local function log_failures(surface, failures)
    local targets = {}
    for target in pairs(failures) do targets[#targets + 1] = target end
    table.sort(targets)
    for _, target in ipairs(targets) do
        local failure = failures[target]
        log(("[BestLanding] resource placement on %s: failed to create %s "
            .. "at %d positions; first failure at %d,%d"):format(
            surface.name,
            target,
            failure.count,
            failure.first_position.x,
            failure.first_position.y
        ))
    end
end

local function execute_operations(surface, operations)
    local failures = {}
    for _, operation in ipairs(operations) do
        if operation.kind == "tile-area" then
            local tiles = {}
            for x = operation.area.left_top.x, operation.area.right_bottom.x - 1 do
                for y = operation.area.left_top.y, operation.area.right_bottom.y - 1 do
                    tiles[#tiles + 1] = {name=operation.target, position={x, y}}
                end
            end
            if #tiles > 0 then surface.set_tiles(tiles) end
        else
            local function attempt(x, y)
                local created = surface.create_entity{
                    name=operation.target,
                    position={x, y},
                    amount=operation.amount,
                    raise_built=false,
                    create_build_effect_smoke=false,
                }
                if not created then record_failure(failures, operation.target, x, y) end
            end
            if operation.kind == "resource-point" then
                attempt(operation.position.x, operation.position.y)
            else
                for x = operation.area.left_top.x, operation.area.right_bottom.x - 1 do
                    for y = operation.area.left_top.y, operation.area.right_bottom.y - 1 do
                        attempt(x, y)
                    end
                end
            end
        end
    end
    log_failures(surface, failures)
end
```

Use explicit operation records:

```lua
-- 实体资源矩形
{kind="resource-area", target=name, area=area, device_key=key, zone_key=key}
-- 地下流体点
{kind="resource-point", target=name, position=position, device_key=key, zone_key=key}
-- 农业塔或离岸泵地格矩形
{kind="tile-area", target=name, area=area, device_key=key, zone_key=key}
```

Required implementation details:

- Collect solid mining drills, vanilla pumpjacks, all `agricultural-tower` prototypes, and all `offshore-pump` prototypes once.
- Use transformed device centers for inclusive zone selection.
- Preserve quality-aware `get_mining_drill_radius` behavior for solid drills.
- Use `agricultural_tower_radius` for agricultural tile areas.
- Floor pumpjack positions before creating a resource.
- Rotate `fluid_source_offset` by final pump direction and compute one bounding rectangle per zone.
- Build diagnostic maps from operations, log different targets sharing a device or footprint, then discard those maps.
- Execute the original operations without an occupancy map and without consulting diagnostics.
- For every `resource-area` tile and every `resource-point`, call `surface.create_entity`; aggregate false/nil returns by target and first position.
- For every `tile-area`, build the full tile array and call `surface.set_tiles`; do not deduplicate against other operations.
- Keep logs aggregate and English, matching existing log style.
- Keep `M.is_resource_zone_marker` backed by `resource_zones.is_marker` so `apply_blueprint.lua` uses the same recognition rule.
- Remove `DEFAULT_COLUMNS_PER_RESOURCE`, `collect_columns`, `column_resource_name`, `place_column_resources`, and every `placed` table that changes execution.

- [ ] **Step 4: Run focused tests and syntax checks**

Run:

```bash
lua5.4 tests/run.lua
luac5.4 -p resource_zones.lua place_resources.lua tests/test_place_resources.lua tests/run.lua
```

Expected: all tests print `PASS`; syntax checks exit 0.

- [ ] **Step 5: Verify diagnostics do not govern execution**

Run:

```bash
rg -n "diagnose_operations|execute_operations|placed\[|conflicting.*skip|columns_per_resource|collect_columns" place_resources.lua
```

Expected:

- `diagnose_operations` and `execute_operations` both exist as separate calls.
- No `placed[...]` occupancy filter exists.
- No conflict branch skips an otherwise resolved operation.
- No column symbols remain.

- [ ] **Step 6: Commit the runtime pipeline**

```bash
git add -- place_resources.lua tests/run.lua tests/test_place_resources.lua
git commit -m "feat: place all resources from marker zones"
```

Do not stage `blueprints.lua`.

---

### Task 3: Mining-Layer Gate and Planet-Config Removal

**Files:**
- Modify: `control.lua:47-51`
- Modify: `apply_blueprint.lua:434-585`
- Modify: `planets.lua:1-95`

**Interfaces:**
- Consumes: `place_resources.place_blueprint_resources(surface, entities, transform)` from Task 2.
- Changes: `apply_blueprint.run(surface, opts)` no longer accepts `cfg`.
- Produces: resource placement only from entry `level == 3`.
- Removes: all `cfg` resource data; cleanup code continues consuming `default_tile` and `enemy_cleanup`.

- [ ] **Step 1: Run structural assertions before editing**

Run:

```bash
python3 - <<'PY'
import re
from pathlib import Path
apply = Path('apply_blueprint.lua').read_text()
control = Path('control.lua').read_text()
planets = Path('planets.lua').read_text()
assert 'if level == 3 then' in apply
assert 'blueprint_tile_resources' not in planets
assert 'blueprint_fluid_sources' not in planets
assert re.search(r'resources\.place_blueprint_resources\(\s*surface,\s*blueprint_entities,', apply)
assert re.search(r'function M\.run\(surface, opts\)', apply)
assert re.search(r'apply_blueprint\.run, surface, \{', control)
PY
```

Expected: FAIL on the first assertion because the current code places resources for every non-empty layer and still passes `cfg`.

- [ ] **Step 2: Add the level gate**

Change the local `apply` signature to remove `cfg` and accept `level`:

```lua
local function apply(surface, blueprint_string, anchor, direction, level)
```

Replace the unconditional call with:

```lua
if level == 3 then
    resources.place_blueprint_resources(
        surface,
        blueprint_entities,
        function(entity)
            local entity_direction = entity.direction or 0
            return {
                position = transform_pos(entity.position, runtime_anchor, direction),
                direction = (entity_direction + direction) % 16,
            }
        end
    )
end
```

Pass `level` from `M.run`:

```lua
apply(
    surface,
    bp.data,
    bp.pos or {x = 0, y = 0},
    bp.direction or 0,
    level
)
```

Change the public entry to `function M.run(surface, opts)`. In `control.lua`, keep `cfg` for `clean_area.run`, but call the blueprint stage as:

```lua
run_stage("apply_blueprint", apply_blueprint.run, surface, {
    max_level = base_level,
})
```

- [ ] **Step 3: Remove planet resource mappings**

Reduce `planets.lua` to `default_tile` and `enemy_cleanup` entries. Update its opening comment to Chinese text equivalent to “five planets' default terrain and enemy cleanup strategy.” Remove both old resource comments and every `blueprint_*` table.

- [ ] **Step 4: Rerun structural and syntax checks**

Run the Step 1 Python command again.

Expected: exit 0 with no output.

Then run:

```bash
for f in *.lua; do luac5.4 -p "$f" || exit 1; done
lua5.4 tests/run.lua
rg -n "blueprint_tile_resources|blueprint_fluid_sources|columns_per_resource|column_resource_name|collect_columns" --glob '*.lua' .
```

Expected: syntax and unit tests pass; `rg` returns no matches.

- [ ] **Step 5: Commit the integration**

```bash
git add -- control.lua apply_blueprint.lua planets.lua
git commit -m "refactor: seed resources only from mining blueprints"
```

Do not stage `blueprints.lua`.

---

### Task 4: Version 2.0.0 Documentation and Contract Update

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `changelog.txt`
- Modify: `info.json`

**Interfaces:**
- Documents the exact runtime contract implemented by Tasks 1-3.
- Produces release metadata version `2.0.0`.

- [ ] **Step 1: Run metadata assertions before editing**

Run:

```bash
python3 - <<'PY'
import json
from pathlib import Path
info = json.loads(Path('info.json').read_text())
changelog = Path('changelog.txt').read_text().splitlines()
readme = Path('README.md').read_text()
agents = Path('AGENTS.md').read_text()
assert info['version'] == '2.0.0'
assert changelog[1] == 'Version: 2.0.0'
assert 'Mining blueprint layer' in readme
assert 'place_as_tile_result' in readme
assert 'blueprint_tile_resources' not in agents
PY
```

Expected: FAIL because metadata and documentation still describe 1.9.0 and column mappings.

- [ ] **Step 2: Update `info.json` and `changelog.txt`**

Set `info.json` version to `2.0.0`. Prepend this exact changelog entry, using a 99-hyphen separator:

```text
---------------------------------------------------------------------------------------------------
Version: 2.0.0
Date: 2026-07-22
  Changes:
    - Unified solid resources, underground fluid sources, offshore fluid tiles, and placeable terrain tiles under paired Mining-blueprint resource-zone markers.
    - Removed planet-specific and column-based resource mappings so blueprint signals now determine resource types directly on every planet.
    - Added generic mining-product resolution, agricultural-tower tile placement, and signal-based offshore tile resolution.
    - Restricted starter-resource generation to the Mining blueprint layer and added diagnostics that report ambiguous blueprints without resolving their conflicts.
```

- [ ] **Step 3: Rewrite the README resource section in English**

Replace “Solid-resource zone markers” with “Mining-layer resource-zone markers.” Document:

- One normal-quality signal and positive integer zone ID on exactly two markers.
- Item + solid mining drill resolves entity resources by mining product.
- Fluid + pumpjack resolves underground resources by mining product.
- Item + agricultural tower resolves every `place_as_tile_result`.
- Fluid + offshore pump resolves same-name/unique tiles plus the two aliases.
- Only Mining layer is scanned.
- Diagnostics report overlap without changing direct execution.
- Vulcanus does not substitute water or crude oil.

Remove all statements that malformed conflicts are “skipped” or that first resources are deliberately preserved.

- [ ] **Step 4: Update `AGENTS.md` in Chinese**

Update file responsibilities, the pipeline steps, the planet-resource contract, common pitfalls, and the architecture summary. State explicitly:

- `planets.lua` no longer contains resources.
- `resource_zones.lua` is the pure resolver.
- `place_resources.lua` diagnoses then executes without conflict resolution.
- Only level 3 is scanned.
- `blueprints.lua` markers are latest-only and other layers' resource drivers are ignored.

- [ ] **Step 5: Verify metadata and changelog formatting**

Run the Step 1 Python command again; expected exit 0.

Run:

```bash
python3 - <<'PY'
from pathlib import Path
lines = Path('changelog.txt').read_text().splitlines()
assert lines[0] == '-' * 99
assert lines[1] == 'Version: 2.0.0'
assert lines[2] == 'Date: 2026-07-22'
assert lines[3] == '  Changes:'
entries = []
for line in lines[4:]:
    if line == '-' * 99:
        break
    entries.append(line)
assert entries and all(line.startswith('    - ') for line in entries)
PY
```

Expected: exit 0 with no output.

- [ ] **Step 6: Commit documentation and metadata**

```bash
git add -- AGENTS.md README.md changelog.txt info.json
git commit -m "docs: document unified resource marker contract"
```

Do not stage `blueprints.lua`.

---

### Task 5: Full Static Verification and Blueprint Audit

**Files:**
- Inspect: all modified files
- Inspect only: `blueprints.lua`
- Modify only if a preceding task introduced a defect; never normalize or replace blueprint strings during this task.

**Interfaces:**
- Consumes the complete implementation from Tasks 1-4.
- Produces verification evidence and a Windows runtime checklist; no new feature behavior.

- [ ] **Step 1: Run every Lua test and parse check**

```bash
lua5.4 tests/run.lua
for f in *.lua tests/*.lua; do luac5.4 -p "$f" || exit 1; done
```

Expected: test runner prints `PASS`; every parse check exits 0.

- [ ] **Step 2: Prove the old implementation is gone**

```bash
rg -n "blueprint_tile_resources|blueprint_fluid_sources|columns_per_resource|column_resource_name|collect_columns|repeat_last_resource" --glob '*.lua' --glob '*.md' --glob '!docs/superpowers/**' .
```

Expected: no matches in current source or current user documentation.

- [ ] **Step 3: Audit current Mining blueprint markers without printing strings**

Run:

```bash
python3 - <<'PY'
import base64, collections, json, re, zlib
from pathlib import Path

text = Path('blueprints.lua').read_text()
values = dict(re.findall(r'^local\s+(\w+)\s*=\s*"([^"]*)"', text, re.M))
for name in ('NauvisMining', 'VulcanusMining', 'FulgoraMining', 'GlebaMining', 'AquiloMining'):
    encoded = values.get(name, '')
    if not encoded:
        print(f'{name}: empty')
        continue
    blueprint = json.loads(zlib.decompress(base64.b64decode(encoded[1:])))['blueprint']
    groups = collections.Counter()
    for entity in blueprint.get('entities', []):
        if entity.get('player_description') != 'BestLanding:resource-zone':
            continue
        filters = []
        for section in (((entity.get('control_behavior') or {}).get('sections') or {}).get('sections') or []):
            filters.extend(f for f in section.get('filters', []) if f.get('name'))
        assert len(filters) == 1, (name, entity.get('entity_number'), len(filters))
        signal = filters[0]
        quality = signal.get('quality', 'normal')
        count = signal.get('count', 1)
        assert quality == 'normal', (name, entity.get('entity_number'), quality)
        assert isinstance(count, int) and count > 0, (name, entity.get('entity_number'), count)
        groups[(signal.get('type', 'item'), signal['name'], quality, count)] += 1
    bad = {key: count for key, count in groups.items() if count != 2}
    assert not bad, (name, bad)
    print(f'{name}: {len(groups)} valid marker pairs')
PY
```

Expected: every non-empty Mining blueprint reports only valid marker pairs. Empty Mining blueprints are allowed. Do not edit or stage `blueprints.lua` as part of this audit.

- [ ] **Step 4: Verify release metadata and staged scope**

```bash
python3 - <<'PY'
import json
from pathlib import Path
assert json.loads(Path('info.json').read_text())['version'] == '2.0.0'
assert Path('changelog.txt').read_text().splitlines()[1] == 'Version: 2.0.0'
PY
git diff --check -- . ':(exclude)blueprints.lua'
git status --short
```

Expected:

- Metadata assertions exit 0.
- `git diff --check` reports no implementation whitespace errors.
- `git status --short` may still show the user's pre-existing ` M blueprints.lua`; no implementation files should remain unintentionally unstaged after the task commits.

- [ ] **Step 5: Review the complete implementation diff**

```bash
git log --oneline --decorate -8
git diff 969af21..HEAD -- resource_zones.lua place_resources.lua apply_blueprint.lua planets.lua tests AGENTS.md README.md changelog.txt info.json
```

Check every acceptance criterion in the approved design against the diff. If a defect is found, fix only that defect, rerun Steps 1-4, and commit the fix with an exact path list.

- [ ] **Step 6: Prepare the manual Factorio handoff**

Report that WSL verification is complete only if all commands above exited 0. Hand off these Windows checks without claiming they passed:

- Basic/powered levels create no resources.
- Mining and cumulative production runs create Mining resources once.
- Nauvis and Vulcanus preserve explicit water and crude-oil signals.
- Gleba agricultural soils cover agricultural-tower work areas.
- Heavy oil and ammoniacal solution resolve to approved ocean tiles.
- Sulfuric acid, fluorine, lithium brine, and crude oil resolve through mining products.
- Deliberately conflicting zones log diagnostics while direct execution remains unsuppressed.

No final commit is needed if verification introduces no changes.
