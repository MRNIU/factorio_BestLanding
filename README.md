# Best Landing

A Factorio 2.1 mod that cleans up the landing area and seeds blueprint-defined resources whenever you arrive on a new planet surface.

## Features

- **Landing-area cleanup**: destroys trees, rocks, cliffs, enemies, and existing resources in a 448×448 square around (0,0), then lays a planet-appropriate buildable default tile.
- **Per-planet enemy purge** beyond the landing square:
  - Nauvis — 256-tile expand ring, removes biter / spitter spawners and worm turrets.
  - Vulcanus — 300-tile expand ring, removes `segmented-unit` Demolishers whose territories would otherwise still cover the landing zone.
  - Gleba — 256-tile expand ring, removes pentapod nests (`unit-spawner`).
  - Fulgora / Aquilo — no enemies, no expand.
- **Blueprint-driven resource seeding**: paired constant-combinator markers in the Mining blueprint layer declare solid resources, underground fluid sources, offshore fluid tiles, and placeable terrain tiles. Resource prototypes are resolved from mining products or tile metadata rather than planet-specific mappings. Fluid sources are seeded at `uint32` max so they effectively never run dry.
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

## Mining-layer resource-zone markers

Exactly two constant combinators define one inclusive device-selection rectangle. Configure both markers as follows:

- Set the description to exactly `BestLanding:resource-zone`.
- Configure exactly one normal-quality item or fluid signal.
- Use a positive integer signal count as the zone ID. Both markers must use the same signal type, signal name, quality, and zone ID. Use another ID for another rectangle.

Signal meaning depends on the selected device type:

- An item signal with a solid mining drill resolves a resource entity through that resource's mining products, then fills the drill's own mining radius.
- A fluid signal with a `pumpjack` resolves an underground resource entity through its mining products, then places one source under the pumpjack.
- An item signal with an agricultural tower resolves every item that exposes `place_as_tile_result`, then fills the tower's work area with that tile.
- A fluid signal with an offshore pump resolves a same-name or unique fluid-bearing tile. `heavy-oil` maps to `oil-ocean-shallow`, and `ammoniacal-solution` maps to `ammoniacal-ocean`. The selected pumps' source tiles define one minimal rectangle per marker zone.

Only the Mining blueprint layer is scanned for resource drivers. Basic, powered, and production layers never drive resource placement; the production setting still receives Mining resources because blueprint levels are applied cumulatively.

Signals are interpreted identically on every planet. In particular, Vulcanus does not replace explicitly signaled `water` or `crude-oil` with lava or sulfuric acid. There are no planet resource allowlists, denylists, column mappings, or fallback layouts.

Resource-zone marker combinators are design-only metadata. They are removed from the placement result and are not built as part of the starter base. Ordinary constant combinators without the exact marker description are placed normally.

Malformed or unresolved marker groups are logged because they cannot be executed. Overlapping valid zones and conflicting targets are also logged, but diagnostics never select a winner, deduplicate placement, or suppress an otherwise valid operation. Blueprint authors are responsible for providing unambiguous layouts.

## License

MIT — see [LICENSE](LICENSE).

## Author

- **NZH** — zhihong@nzhnb.com
- Repository: <https://github.com/MRNIU/factorio_BestLanding>

## Changelog

See [changelog.txt](changelog.txt).
