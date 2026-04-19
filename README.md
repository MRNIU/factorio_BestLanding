# Best Landing

A Factorio 2.0 mod that cleans up the landing area and seeds planet-appropriate resources whenever you arrive on a new planet surface.

## Features

- **Landing-area cleanup**: destroys trees, rocks, cliffs, enemies, and existing resources in a 448×448 square around (0,0), then lays a planet-appropriate default tile.
- **Vulcanus Demolisher purge**: sweeps a 300-tile ring outside the cleared square to remove `segmented-unit` Demolishers whose territories would otherwise still cover the landing zone.
- **Planet-specific resource seeding**: places ores, fluid sources, and tile resources tuned for each Space Age planet (Nauvis, Vulcanus, Gleba, Fulgora, Aquilo).
- **Starter blueprints**: each supported planet comes with its own blueprint that is applied on arrival — modules, filters, and fuel embedded in the blueprints are delivered into the revived entities automatically.
- **Legendary spidertron**: spawns a fully-equipped legendary spidertron pre-loaded with robots, power, defense, ammo, and repair packs at the landing site.
- **Runs on every new planet**: both on the initial Nauvis spawn and every time `on_surface_created` fires for a new planet surface. Orbital space platforms are skipped.

## Disclaimer

Blueprints bundled with this mod come from the Factorio community. All credit belongs to the original blueprint authors.

## Compatibility

- Factorio 2.0.55 or newer.
- Requires `base`, `space-age`, `quality`.

## License

MIT — see [LICENSE](LICENSE).

## Author

- **NZH** — zhihong@nzhnb.com
- Repository: <https://github.com/MRNIU/factorio_BestLanding>

## Changelog

See [changelog.txt](changelog.txt).
