# Blueprint Coordinate Transform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace blueprint-anchor patches with one tested transform matching Factorio absolute-grid placement.

**Architecture:** Add a pure `blueprint_transform.lua` module that computes the snapped surface anchor and transforms local positions. Make `apply_blueprint.lua` consume that transform everywhere and remove probe-based inference.

**Tech Stack:** Factorio 2.1 runtime Lua, Lua 5.4 unit tests, `luac5.4` syntax verification.

## Global Constraints

- Preserve the copyright header in every Lua file.
- Lua comments are Chinese; changelog and public metadata are English.
- Do not stage or modify the user's existing `blueprints.lua` change.
- Behavior changes require `info.json` and `changelog.txt` version `2.0.6`.

---

### Task 1: Pure coordinate transform

**Files:**
- Create: `blueprint_transform.lua`
- Create: `tests/test_blueprint_transform.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `Transform.new(options) -> transform`
- Produces: `transform.position(local_position) -> {x, y}`
- Produces: `transform.direction(local_direction) -> MapDirection`
- Produces: `transform.anchor -> {x, y}`

- [ ] Write tests for unsnapped and relative blueprints using `anchor = build_position`.
- [ ] Write tests proving `390×98 / 195,1` resolves to `(-195,-97)` at `(0,0)`.
- [ ] Write tests proving `392×383 / 196,196` resolves to `(-196,-187)` at `(0,0)`.
- [ ] Write tests for negative local coordinates and north/east/south/west rotation.
- [ ] Run `lua5.4 tests/run.lua`; expect failure because `blueprint_transform` does not exist.
- [ ] Implement the minimal pure module with floor-grid snapping and exact orthogonal rotation.
- [ ] Run `lua5.4 tests/run.lua`; expect all assertions to pass.

### Task 2: Apply pipeline integration

**Files:**
- Modify: `apply_blueprint.lua`
- Modify: `tests/test_apply_blueprint.lua`

**Interfaces:**
- Consumes: `Transform.new`, `transform.position`, `transform.direction`.
- Removes: `resolve_blueprint_content_anchor`, `infer_runtime_anchor`, `destroy_probe_ghosts`.

- [ ] Change the integration test to expect exactly one `build_blueprint` call per layer and formula-derived resource coordinates.
- [ ] Run `lua5.4 tests/run.lua`; expect the call-count assertion to fail against the probe implementation.
- [ ] Create one transform after importing each blueprint and pass it to AABB, resources, and marker collection.
- [ ] Remove probe construction and runtime-anchor inference while retaining the final runtime AABB cleanup.
- [ ] Run `lua5.4 tests/run.lua`; expect all assertions to pass.

### Task 3: Documentation and release

**Files:**
- Modify: `AGENTS.md`
- Modify: `info.json`
- Modify: `changelog.txt`

- [ ] Document the single transform and one-build pipeline in `AGENTS.md`.
- [ ] Set `info.json` version to `2.0.6`.
- [ ] Add a correctly formatted English `2.0.6` changelog entry dated `2026-07-23`.
- [ ] Run `lua5.4 tests/run.lua` and parse every Lua file with `luac5.4 -p`.
- [ ] Run JSON, changelog separator, and `git diff --check` validation.
- [ ] Stage only the files listed in this plan, commit, and confirm `blueprints.lua` remains unstaged.
