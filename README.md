# Best Landing

A Factorio 2.1 mod that cleans up the landing area and seeds planet-appropriate resources whenever you arrive on a new planet surface.

## Features

- **Landing-area cleanup**: destroys trees, rocks, cliffs, enemies, and existing resources in a 448×448 square around (0,0), then lays a planet-appropriate buildable default tile.
- **Per-planet enemy purge** beyond the landing square:
  - Nauvis — 256-tile expand ring, removes biter / spitter spawners and worm turrets.
  - Vulcanus — 300-tile expand ring, removes `segmented-unit` Demolishers whose territories would otherwise still cover the landing zone.
  - Gleba — 256-tile expand ring, removes pentapod nests (`unit-spawner`).
  - Fulgora / Aquilo — no enemies, no expand.
- **Planet-specific resource seeding**: Resources can use a fixed fallback row, follow starter-blueprint resource driver entities, or switch automatically. In auto mode, blueprints with mining drills, offshore pumps, or pumpjacks skip the fixed fallback and seed matching resources by column group. Fluid sources (crude oil, sulfuric acid geysers, lithium brine, fluorine vents) are seeded at `uint32` max so they effectively never run dry.
- **Gleba fruit trees**: overgrowth soil bands are pre-planted with mature, fruit-bearing yumako trees and jellystem trees (~50% density). You can harvest immediately — no waiting for growth.
- **Starter blueprints**: each supported planet has its own blueprint applied on arrival. Modules, filters, and ammo embedded in the blueprint are delivered into each revived entity via the Factorio 2.1 `insert_plan` API, so quality items land in the correct inventory slot (for example, productivity modules inside recyclers go to the module slot, not the recycling input queue).
- **Locked supply entities**: infinity containers, infinity pipes, and infinity cargo wagons embedded in starter blueprints are locked after placement so players cannot open, configure, rotate, mine, or destroy them. Inserters and fluid networks can still extract from them.
- **Runs on every new planet**: both on the initial Nauvis spawn (`on_init`) and every time `on_surface_created` fires for a new planet surface. Orbital space platforms are skipped via `surface.planet` filter.

## Disclaimer

Blueprints bundled with this mod come from the Factorio community. All credit belongs to the original blueprint authors.

## Compatibility

- Factorio 2.1.9 or newer.
- Requires `base`, `space-age`, `quality`.

## License

MIT — see [LICENSE](LICENSE).

## Author

- **NZH** — zhihong@nzhnb.com
- Repository: <https://github.com/MRNIU/factorio_BestLanding>

## Changelog

See [changelog.txt](changelog.txt).
