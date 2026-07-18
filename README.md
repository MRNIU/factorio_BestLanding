# Best Landing

A Factorio 2.1 mod that cleans up the landing area and seeds planet-appropriate resources whenever you arrive on a new planet surface.

## Features

- **Landing-area cleanup**: destroys trees, rocks, cliffs, enemies, and existing resources in a 448×448 square around (0,0), then lays a planet-appropriate buildable default tile.
- **Per-planet enemy purge** beyond the landing square:
  - Nauvis — 256-tile expand ring, removes biter / spitter spawners and worm turrets.
  - Vulcanus — 300-tile expand ring, removes `segmented-unit` Demolishers whose territories would otherwise still cover the landing zone.
  - Gleba — 256-tile expand ring, removes pentapod nests (`unit-spawner`).
  - Fulgora / Aquilo — no enemies, no expand.
- **Blueprint-driven resource seeding**: starter resources are inferred exclusively from mining drills, offshore pumps, and pumpjacks in the selected blueprint layers. Solid ores, source tiles, and fluid sources are assigned by column group; there is no fixed fallback layout. Fluid sources are seeded at `uint32` max so they effectively never run dry.
- **Three-level starter bases**: each planet independently supports a basic base, a powered base that adds a power-system blueprint, and a production base that additionally adds a production-facility blueprint. Higher levels cumulatively apply all lower-level layers.
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
- **Level 3 — Production base**: applies the basic, power-system, and production-facility blueprints in order.

Settings only affect planet surfaces processed after the change; existing bases are not rebuilt.

## License

MIT — see [LICENSE](LICENSE).

## Author

- **NZH** — zhihong@nzhnb.com
- Repository: <https://github.com/MRNIU/factorio_BestLanding>

## Changelog

See [changelog.txt](changelog.txt).
