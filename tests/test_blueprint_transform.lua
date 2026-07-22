-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 校验蓝图网格吸附、局部坐标和旋转共享同一套 surface 换算。

return function(T)
    local Transform = require("blueprint_transform")

    local diagonal = Transform.rotate_vector({x = 1, y = 0}, 2)
    T.truthy(math.abs(diagonal.x - math.sqrt(0.5)) < 1e-12,
        "diagonal entity collision vector rotates x")
    T.truthy(math.abs(diagonal.y - math.sqrt(0.5)) < 1e-12,
        "diagonal entity collision vector rotates y")

    local unsnapped = Transform.new {
        build_position = {x = 10, y = -20},
        direction = 0,
    }
    local unsnapped_position = unsnapped.position {x = 2, y = 3}
    T.equal(unsnapped.anchor.x, 10, "unsnapped x anchor uses build position")
    T.equal(unsnapped.anchor.y, -20, "unsnapped y anchor uses build position")
    T.equal(unsnapped_position.x, 12, "unsnapped local x is translated")
    T.equal(unsnapped_position.y, -17, "unsnapped local y is translated")

    local relative = Transform.new {
        build_position = {x = 10, y = -20},
        direction = 0,
        snap_to_grid = {x = 390, y = 98},
        absolute_snapping = false,
        position_relative_to_grid = {x = 195, y = 1},
    }
    T.equal(relative.anchor.x, 10, "relative snapping keeps build x")
    T.equal(relative.anchor.y, -20, "relative snapping keeps build y")

    local strip = Transform.new {
        build_position = {x = 0, y = 0},
        direction = 0,
        snap_to_grid = {x = 390, y = 98},
        absolute_snapping = true,
        position_relative_to_grid = {x = 195, y = 1},
    }
    T.equal(strip.anchor.x, -195, "390-wide absolute grid snaps x to -195")
    T.equal(strip.anchor.y, -97, "98-high absolute grid snaps y to -97")
    local shifted_local = strip.position {x = 1, y = -97}
    T.equal(shifted_local.x, -194, "implicit grid-position x remains in local coordinate")
    T.equal(shifted_local.y, -194, "implicit grid-position y remains in local coordinate")

    local gleba = Transform.new {
        build_position = {x = 0, y = 0},
        direction = 0,
        snap_to_grid = {x = 392, y = 383},
        absolute_snapping = true,
        position_relative_to_grid = {x = 196, y = 196},
    }
    T.equal(gleba.anchor.x, -196, "even absolute grid snaps x by its half offset")
    T.equal(gleba.anchor.y, -187, "odd absolute grid uses the preceding lattice point")
    local gleba_marker = gleba.position {x = 0.5, y = 382.5}
    T.equal(gleba_marker.x, -195.5, "Gleba marker x uses the common transform")
    T.equal(gleba_marker.y, 195.5, "Gleba marker y uses the common transform")

    local moved = Transform.new {
        build_position = {x = 400, y = 100},
        direction = 0,
        snap_to_grid = {x = 390, y = 98},
        absolute_snapping = true,
        position_relative_to_grid = {x = 195, y = 1},
    }
    T.equal(moved.anchor.x, 195, "absolute x selects the lattice cell containing build x")
    T.equal(moved.anchor.y, 99, "absolute y selects the lattice cell containing build y")

    local expected_anchors = {
        [0] = {x = -195, y = -97},
        [4] = {x = -1, y = -195},
        [8] = {x = -195, y = -1},
        [12] = {x = -97, y = -195},
    }
    for direction, expected in pairs(expected_anchors) do
        local rotated = Transform.new {
            build_position = {x = 0, y = 0},
            direction = direction,
            snap_to_grid = {x = 390, y = 98},
            absolute_snapping = true,
            position_relative_to_grid = {x = 195, y = 1},
        }
        T.equal(rotated.anchor.x, expected.x,
            ("direction %d rotates and snaps grid x"):format(direction))
        T.equal(rotated.anchor.y, expected.y,
            ("direction %d rotates and snaps grid y"):format(direction))
        T.equal(rotated.direction(0), direction,
            ("direction %d composes entity direction"):format(direction))
    end
end
