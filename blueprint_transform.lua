-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 蓝图局部坐标、绝对网格吸附和 surface 坐标的唯一换算入口。

local M = {}

local function components(vector)
    if not vector then return nil, nil end
    return vector.x or vector[1], vector.y or vector[2]
end

local function normalize_direction(direction)
    return (direction or 0) % 16
end

function M.rotate_vector(vector, direction)
    local x, y = components(vector)
    direction = normalize_direction(direction)

    if direction == 0 then
        return {x = x, y = y}
    elseif direction == 4 then
        return {x = -y, y = x}
    elseif direction == 8 then
        return {x = -x, y = -y}
    elseif direction == 12 then
        return {x = y, y = -x}
    end

    local angle = direction * math.pi / 8
    return {
        x = x * math.cos(angle) - y * math.sin(angle),
        y = x * math.sin(angle) + y * math.cos(angle),
    }
end

local function rotate_grid_size(grid, direction)
    local x, y = components(grid)
    direction = normalize_direction(direction)
    if direction == 4 or direction == 12 then
        return {x = y, y = x}
    elseif direction ~= 0 and direction ~= 8 then
        error(("absolute blueprint grid only supports cardinal directions, got %d")
            :format(direction))
    end
    return {x = x, y = y}
end

local function snap_axis(position, size, offset)
    return offset + math.floor((position - offset) / size) * size
end

function M.new(options)
    options = options or {}
    local build_x, build_y = components(options.build_position or {x = 0, y = 0})
    local direction = normalize_direction(options.direction)
    local anchor = {x = build_x, y = build_y}

    if options.absolute_snapping and options.snap_to_grid then
        local grid = rotate_grid_size(options.snap_to_grid, direction)
        local offset = M.rotate_vector(
            options.position_relative_to_grid or {x = 0, y = 0},
            direction
        )
        if not (grid.x and grid.y and grid.x > 0 and grid.y > 0) then
            error("absolute blueprint snapping requires a positive grid size")
        end
        anchor.x = snap_axis(build_x, grid.x, offset.x)
        anchor.y = snap_axis(build_y, grid.y, offset.y)
    end

    local transform = {
        anchor = anchor,
        build_position = {x = build_x, y = build_y},
        direction_value = direction,
    }

    function transform.position(local_position)
        local rotated = M.rotate_vector(local_position, direction)
        return {
            x = rotated.x + anchor.x,
            y = rotated.y + anchor.y,
        }
    end

    function transform.direction(local_direction)
        return (normalize_direction(local_direction) + direction) % 16
    end

    return transform
end

return M
