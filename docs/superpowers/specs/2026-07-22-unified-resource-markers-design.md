# Unified Resource Markers Design

Date: 2026-07-22
Target version: 2.0.0
Status: Approved design; implementation not started

## 1. Objective

BestLanding will use one blueprint contract for every starter resource. Solid resources, offshore-pump source tiles, underground fluid resources, and placeable agricultural or terrain tiles will all be declared by paired `BestLanding:resource-zone` constant combinators in the Mining blueprint layer.

The resource selected by the blueprint must not be replaced according to the current planet. In particular, a `water` signal must continue to mean water on Vulcanus, and a `crude-oil` signal must continue to mean crude oil.

The new implementation will remove all planet resource allowlists, denylists, and X-column mappings. It will support the latest blueprint contract only; compatibility with old blueprints, old column layouts, and already-processed surfaces is outside the scope of this change.

## 2. Scope and non-goals

Resource processing occurs only while applying a blueprint entry whose `level` is `3` (`Mining`).

- `basic` and `powered` do not generate resources.
- `mining` generates resources once from the Mining layer.
- `production` cumulatively applies the Mining layer, so Mining resources are still generated once; the Production layer itself is not scanned for resources.
- Resource drivers or resource-zone markers in non-Mining layers do not generate resources.
- Resource-zone marker ghosts remain design-only and are removed from every formally placed layer.

This design does not add `data.lua`, `data-final-fixes.lua`, persistent `storage`, configuration-change migrations, or automatic reruns on existing surfaces.

## 3. Marker contract

A marker is a blueprint entity satisfying all of the following:

- Its prototype type is `constant-combinator`.
- Its `player_description` is exactly `BestLanding:resource-zone`.
- It contains exactly one configured signal.
- The signal quality is `normal`.
- The signal count is a positive integer used as the zone ID; it is not a resource amount.

One resource zone consists of exactly two markers with the same signal type, signal name, signal quality, and zone ID. Their final transformed surface positions define an axis-aligned, inclusive device-selection rectangle. A device whose center lies on the rectangle boundary is selected.

The normalized zone record is conceptually:

```text
ResourceZone
  signal_type
  signal_name
  quality
  zone_id
  left
  right
  top
  bottom
```

Zones are ordered by signal type, signal name, quality, and zone ID so logs and normal execution are reproducible. This ordering is not a conflict-resolution policy; malformed or ambiguous blueprints have no guaranteed placement result.

## 4. Generic resource prototype resolution

At control stage, BestLanding lazily builds indexes from all loaded entity prototypes whose type is `resource`. The indexes associate every item or fluid mining product with the resource prototypes that can produce it. The indexes are module-local caches and are not persisted in `storage`.

For an item or fluid signal:

1. Find resource prototypes whose mining products contain the signal name and matching product type.
2. If a candidate resource prototype has the same name as the signal, prefer that candidate.
3. Otherwise, accept a unique candidate.
4. If no candidate exists, the signal does not describe an entity resource for that driver type.
5. If multiple candidates remain, log their names and treat the entity-resource target as unresolved.

This resolves vanilla Space Age examples without a resource whitelist:

- `iron-ore` item signal to `iron-ore` resource.
- `scrap` item signal to `scrap` resource.
- `crude-oil` fluid signal to `crude-oil` resource.
- `sulfuric-acid` fluid signal to `sulfuric-acid-geyser` resource.
- `fluorine` fluid signal to `fluorine-vent` resource.
- `lithium-brine` fluid signal to `lithium-brine` resource.

The same rule automatically supports compatible resource prototypes added by other mods.

## 5. Generic placeable-tile resolution

For an item signal, BestLanding reads the matching `LuaItemPrototype::place_as_tile_result`. If the property exists, its tile prototype is the tile target for agricultural towers.

There is no tile allowlist. Every loaded item with `place_as_tile_result` is supported, including the four Space Age agricultural soils:

- `artificial-yumako-soil`
- `overgrowth-yumako-soil`
- `artificial-jellynut-soil`
- `overgrowth-jellynut-soil`

This rule also permits other placeable terrain items such as landfill, ice platform, foundation, or tiles added by other mods. Blueprint authors are responsible for choosing an appropriate tile for the surface and agricultural layout.

## 6. Offshore fluid-to-tile resolution

For a fluid signal used with offshore pumps, BestLanding resolves a water or ocean tile as follows:

1. Prefer a tile whose name equals the fluid name and whose `fluid` property matches it. This handles `water` and `lava`.
2. Otherwise, collect all tiles whose `fluid` property equals the signal name.
3. Accept a unique candidate.
4. If several candidates remain, consult this small signal-to-tile disambiguation table:
   - `heavy-oil` to `oil-ocean-shallow`
   - `ammoniacal-solution` to `ammoniacal-ocean`
5. If the result is still unresolved, log the candidates and do not attempt offshore tile placement for that zone.

This is a signal interpretation rule, not a planet rule. The resolved tile may be placed on any supported planet surface.

## 7. Device dispatch and placement footprints

Signal meaning is determined jointly by signal type and selected device type.

### 7.1 Solid mining drills

- Driver: a `mining-drill` other than the vanilla `pumpjack`.
- Signal: item.
- Target: entity resource resolved from item mining products.
- Footprint: the drill's own quality-aware mining radius, using the existing mining-area calculation.
- Amount: `ORE_PER_TILE` per attempted resource tile.

### 7.2 Agricultural towers

- Driver: `agricultural-tower`.
- Signal: item.
- Target: the signal item's `place_as_tile_result`.
- Footprint: the tower's `agricultural_tower_radius` around its transformed center.
- Placement: `LuaSurface::set_tiles` over the tower work area.

### 7.3 Underground fluid drills

- Driver: the vanilla `pumpjack`.
- Signal: fluid.
- Target: entity resource resolved from fluid mining products.
- Footprint: one resource entity at `floor(position.x), floor(position.y)`.
- Amount: `FLUID_AMOUNT`.

### 7.4 Offshore pumps

- Driver: any entity whose prototype type is `offshore-pump`.
- Signal: fluid.
- Target: a fluid-bearing tile resolved by the offshore rule.
- Footprint: compute every selected pump's actual source tile from `fluid_source_offset` and its final direction, then fill the minimal axis-aligned rectangle containing those source tiles.
- Grouping: compute this rectangle independently for every marker zone. Different zone IDs never join distant pump groups into one ocean patch.

A signal that is not applicable to a selected device type is ignored for that device type. For example, an `iron-ore` item signal can drive mining drills but has no placeable tile for agricultural towers, while an agricultural-soil item signal can drive agricultural towers but has no entity-resource target for mining drills.

## 8. Diagnostics are separate from execution

Blueprint authors are responsible for providing valid, non-overlapping resource zones. BestLanding diagnoses ambiguous input but does not choose how to resolve it.

The diagnostic pass reports:

- Missing, empty, multiple, non-normal-quality, or otherwise invalid marker signals.
- Marker groups whose count is not exactly two.
- Signals with multiple candidate resource or tile prototypes.
- One device selected by multiple applicable zones with different resolved targets.
- Overlapping predicted footprints with different entity-resource targets.
- Overlapping predicted footprints with different tile targets.
- Runtime `create_entity` failures.

Diagnostics do not filter devices, reserve positions, choose a winner, merge targets, or alter execution order. Validly parsed zones are then executed directly and independently.

Consequences for an invalid or ambiguous blueprint are intentionally unspecified:

- The same device may be processed more than once.
- A resource entity created earlier may cause a later `create_entity` call to fail.
- A later `set_tiles` call may overwrite a tile placed earlier.

Only input that cannot be executed at all is skipped, such as an unpaired marker group, an unresolved target prototype, or a zone with no usable signal. Logs must explain the reason. Overlap and conflict logs should be aggregated with counts and a first example position instead of emitting one line per tile.

Diagnostic occupancy maps, if used, are temporary read-only analysis structures. They must not be reused by the execution pass to deduplicate or suppress placement.

## 9. Blueprint application flow

`apply_blueprint.lua` passes the entry level into the single-blueprint application function. The relevant flow is:

1. Import the blueprint into a temporary inventory.
2. Resolve the content anchor and transformed entity positions.
3. Clean the predicted blueprint area.
4. Probe-build ghosts and infer the actual runtime anchor.
5. Destroy probe ghosts.
6. If and only if the entry level is `3`, call the unified resource pipeline with the Mining blueprint entities and runtime transform.
7. Formally build the blueprint ghosts after resource placement.
8. Remove all design marker ghosts.
9. Revive and initialize the remaining entities.

The resource pipeline no longer receives a planet configuration record. Its public input is limited to the surface, blueprint entities, and coordinate transform.

## 10. File-level changes

### `apply_blueprint.lua`

- Pass the blueprint entry level into the single-blueprint application path.
- Call resource placement only for `level == 3`.
- Preserve the existing probe, anchor inference, marker removal, rebuild, and revive ordering.

### `place_resources.lua`

- Replace the current solid-only marker parser and column-based pump logic with the unified zone pipeline.
- Add lazy resource-product and fluid-tile resolution helpers.
- Add agricultural tower tile placement.
- Keep small, isolated functions for each device footprint and for diagnostics.
- Remove column grouping, `columns_per_resource`, repeated-last-resource behavior, and planet configuration dependencies.

### `planets.lua`

- Remove `blueprint_tile_resources` and `blueprint_fluid_sources` from every planet.
- Retain only default cleanup tile and enemy cleanup configuration.

### Documentation and metadata

- Update `AGENTS.md` in Chinese to describe the new architecture and blueprint contract.
- Update `README.md` in English.
- Add an English `2.0.0` changelog entry using Factorio's strict format.
- Set `info.json` version to `2.0.0`.

### Blueprint ownership

The existing uncommitted `blueprints.lua` belongs to the user and must not be reverted or overwritten. Its latest Mining blueprints are the source of truth. Blueprint strings are modified only when a required latest-contract correction is explicitly identified.

## 11. Verification

### Static verification available in WSL

- Run `luac5.4 -p` over every Lua file in the mod.
- Confirm removal of `blueprint_tile_resources`, `blueprint_fluid_sources`, `columns_per_resource`, `collect_columns`, and `column_resource_name`.
- Decode non-empty Mining blueprint strings and audit marker pairing, signal types, qualities, and zone IDs without printing the full strings.
- Confirm `info.json`, changelog top version, and documentation agree on `2.0.0`.
- Validate the changelog separator length and indentation.
- Inspect the final git diff while preserving unrelated user changes.

### Manual Factorio verification required on Windows

1. `basic` and `powered` produce no resources.
2. `mining` produces resources from its markers.
3. `production` applies Mining resources once and does not scan Production drivers.
4. Nauvis and Vulcanus both honor `water` as water and `crude-oil` as crude oil.
5. Vulcanus no longer substitutes lava or sulfuric acid geysers unless those resources are explicitly signaled.
6. All four Gleba agricultural-soil items fill selected agricultural-tower work areas.
7. `heavy-oil` and `ammoniacal-solution` resolve to the approved ocean tiles.
8. Sulfuric acid, fluorine, lithium brine, and crude oil signals resolve to their resource entities through mining products.
9. Deliberately overlapping zones produce diagnostic logs while the execution pass continues without conflict resolution.

Codex cannot claim game-runtime verification. The implementation handoff must explicitly identify the remaining Windows-side manual checks.

## 12. Acceptance criteria

- No resource type is selected from the current planet name.
- No resource type is selected from pump or drill X-column order.
- Only the Mining blueprint layer invokes resource placement.
- One paired constant-combinator contract drives all four resource categories.
- All items with `place_as_tile_result` are supported for agricultural towers.
- Resource entity signals are resolved from loaded mining products without a resource whitelist.
- Fluid-bearing tiles follow the approved generic resolver and two-entry disambiguation table.
- Diagnostics never change the direct placement strategy.
- The old resource configuration and column code are removed rather than retained as fallback behavior.
- Static checks pass, documentation is current, and required manual runtime checks are handed off clearly.
