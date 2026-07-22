-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 校验绝对吸附蓝图的内容坐标和建造位置不会混用。

return function(T)
    package.loaded.apply_blueprint = nil

    local build_positions = {}
    local resource_position
    local blueprint_entities = {
        {entity_number = 1, name = "test-machine", position = {x = 0.5, y = 0.5}},
    }

    package.loaded.blueprints = {
        gleba = {
            {
                level = 1,
                data = "test-basic-blueprint",
                pos = {x = 0, y = 0},
                direction = 0,
            },
            {
                level = 3,
                data = "test-mining-blueprint",
                pos = {x = 0, y = 0},
                direction = 0,
            },
        },
    }
    package.loaded.clean_area = {
        clean_blueprint_area = function() end,
    }
    package.loaded.place_resources = {
        is_resource_zone_marker = function() return false end,
        place_blueprint_resources = function(_, entities, transform)
            resource_position = transform(entities[1]).position
        end,
    }

    _G.log = function() end
    _G.defines = {
        build_mode = {forced = 1},
        inventory = {
            roboport_robot = 1,
            roboport_material = 2,
        },
    }
    _G.prototypes = {
        entity = {
            ["test-machine"] = {
                collision_box = {
                    left_top = {x = -0.5, y = -0.5},
                    right_bottom = {x = 0.5, y = 0.5},
                },
            },
        },
    }

    local function new_ghost()
        local ghost = {
            valid = true,
            type = "entity-ghost",
            ghost_name = "test-machine",
            position = {x = -195.5, y = -186.5},
            bounding_box = {
                left_top = {x = -196, y = -187},
                right_bottom = {x = -195, y = -186},
            },
        }
        function ghost.destroy()
            ghost.valid = false
        end
        function ghost.revive()
            ghost.valid = false
            return nil, {valid = true, type = "assembling-machine"}, nil
        end
        return ghost
    end

    local stack = {
        valid_for_read = true,
        is_blueprint = true,
        blueprint_absolute_snapping = true,
        blueprint_snap_to_grid = {x = 392, y = 383},
        blueprint_position_relative_to_grid = {x = 196, y = 196},
    }
    function stack.import_stack()
        return 0
    end
    function stack.get_blueprint_entities()
        return blueprint_entities
    end
    function stack.get_blueprint_tiles()
        return nil
    end
    function stack.build_blueprint(params)
        build_positions[#build_positions + 1] = params.position
        return {new_ghost()}
    end

    local inventory = {[1] = stack}
    function inventory.destroy() end

    _G.game = {
        forces = {player = {index = 1}},
        create_inventory = function() return inventory end,
    }

    local surface = {valid = true, name = "gleba"}
    require("apply_blueprint").run(surface, {max_level = 3})

    T.equal(#build_positions, 2, "every blueprint layer builds exactly once")
    for index, position in ipairs(build_positions) do
        T.equal(position.x or position[1], 0,
            ("absolute blueprint build %d uses configured build x"):format(index))
        T.equal(position.y or position[2], 0,
            ("absolute blueprint build %d uses configured build y"):format(index))
    end
    T.equal(resource_position.x, -195.5,
        "resource transform uses the formula-derived content x")
    T.equal(resource_position.y, -186.5,
        "resource transform uses the formula-derived content y")
end
