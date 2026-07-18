# Best Landing

A Factorio 2.1 mod that cleans up the landing area and seeds planet-appropriate resources whenever you arrive on a new planet surface.

## Features

- **Landing-area cleanup**: destroys trees, rocks, cliffs, enemies, and existing resources in a 448×448 square around (0,0), then lays a planet-appropriate buildable default tile.
- **Per-planet enemy purge** beyond the landing square:
  - Nauvis — 256-tile expand ring, removes biter / spitter spawners and worm turrets.
  - Vulcanus — 300-tile expand ring, removes `segmented-unit` Demolishers whose territories would otherwise still cover the landing zone.
  - Gleba — 256-tile expand ring, removes pentapod nests (`unit-spawner`).
  - Fulgora / Aquilo — no enemies, no expand.
- **Blueprint-driven resource seeding**: solid ore types and drill-selection rectangles are declared by constant-combinator markers in each selected blueprint layer. Every selected mining drill receives that ore across its own mining radius. Offshore pumps and pumpjacks still drive source tiles and fluid sources from their configured column groups. There is no fixed fallback layout, and fluid sources are seeded at `uint32` max so they effectively never run dry.
- **Four-level starter bases**: each planet independently supports a basic base, a powered base that adds a power-system blueprint, a mining base that adds mining facilities, and a production base that finally adds production facilities. Higher levels cumulatively apply all lower-level layers.
- **Starter blueprint initialization**: modules, filters, and ammo embedded in a blueprint are delivered into each revived entity via the Factorio 2.1 `insert_plan` API, so quality items land in the correct inventory slot. Every revived entity starts with a full electric energy buffer, and each roboport receives one normal-quality stack each of construction robots, logistic robots, and repair packs.
- **Locked supply entities**: infinity containers, infinity pipes, and infinity cargo wagons embedded in starter blueprints are locked after placement so players cannot open, configure, rotate, mine, or destroy them. Inserters and fluid networks can still extract from them.
- **Runs on every new planet**: both on the initial Nauvis spawn (`on_init`) and every time `on_surface_created` fires for a new planet surface. Orbital space platforms are skipped via `surface.planet` filter.

## Disclaimer

Blueprints bundled with this mod come from the Factorio community. All credit belongs to the original blueprint authors.

## Compatibility

- Factorio 2.1.9 or newer.
- Requires `base`, `space-age`, `quality`.

## Settings

The global starter-blueprint toggle disables both blueprint placement and starter-resource generation. When enabled, each supported planet has its own base-level selector:

- **Level 1 — Basic base**: applies only the basic blueprint.
- **Level 2 — Powered base**: applies the basic blueprint, then the power-system blueprint.
- **Level 3 — Mining base**: applies the basic, power-system, and mining-facility blueprints in order.
- **Level 4 — Production base**: applies the basic, power-system, mining-facility, and production-facility blueprints in order.

Settings only affect planet surfaces processed after the change; existing bases are not rebuilt.

## Solid-resource zone markers

Two constant combinators define one drill-selection rectangle. Configure both combinators as follows:

- Set the description to exactly `BestLanding:resource-zone`.
- Configure exactly one normal-quality item signal whose name is also a solid resource entity, such as `iron-ore`.
- Use a positive integer signal count as the zone ID. Both markers must use the same resource and zone ID. Use another ID when the same resource needs another rectangle.

The two marker positions form an inclusive selection rectangle. The mod finds every solid mining drill whose center lies inside that rectangle, then fills the drill's own mining radius with the selected resource. The marker rectangle itself is not filled. Markers and drills must be in the same blueprint layer.

Resource-zone marker combinators are design-only metadata. They are removed from the placement result and are not built as part of the starter base. Ordinary constant combinators without the exact marker description are placed normally.

Malformed marker groups are logged and skipped. A drill selected by two different resource types is also logged and skipped. If different drills' mining areas overlap with different resources, the resource assigned first is preserved and the conflicting tile count is logged.

## License

MIT — see [LICENSE](LICENSE).

## Author

- **NZH** — zhihong@nzhnb.com
- Repository: <https://github.com/MRNIU/factorio_BestLanding>

## Changelog

See [changelog.txt](changelog.txt).
