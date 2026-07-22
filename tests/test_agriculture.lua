-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 校验沃土作物种植和物流请求箱种子补充。

return function(T)
    package.loaded.agriculture = nil

    local logs = {}
    _G.log = function(message) logs[#logs + 1] = message end
    _G.defines = {inventory = {chest = 1}}
    _G.game = {forces = {neutral = {name = "neutral"}}}
    _G.prototypes = {
        item = {
            ["yumako-seed"] = {
                name = "yumako-seed",
                plant_result = {name = "yumako-tree"},
            },
            ["jellynut-seed"] = {
                name = "jellynut-seed",
                plant_result = {name = "jellystem"},
            },
            ["iron-plate"] = {name = "iron-plate"},
        },
    }

    local agriculture = require("agriculture")
    local plan = agriculture.plan_for_tower("artificial-yumako-soil", {
        position = {x = 11.5, y = 20.5},
        radius = 3,
        growth_grid_size = 3,
        device_key = "agricultural-tower#1",
    })
    T.truthy(plan, "yumako soil produces a crop planting plan")
    T.equal(plan.crop, "yumako-tree", "yumako soil resolves through its seed prototype")
    local jellynut_plan = agriculture.plan_for_tower("overgrowth-jellynut-soil", {
        position = {x = 0.5, y = 0.5},
        radius = 3,
        growth_grid_size = 3,
    })
    T.equal(jellynut_plan.crop, "jellystem",
        "jellynut soil resolves through the jellynut seed prototype")
    T.equal(agriculture.plan_for_tower("landfill", {}), nil,
        "unmapped terrain does not create a crop plan")

    local created = {}
    local surface = {valid = true, name = "gleba"}
    function surface.create_entity(params)
        created[#created + 1] = params
        return {valid = true}
    end
    agriculture.plant(surface, {plan})

    T.equal(#created, 48, "a radius-three tower plants every 3x3 growth cell except its center")
    local center_found = false
    for _, params in ipairs(created) do
        if params.position.x == 11.5 and params.position.y == 20.5 then
            center_found = true
        end
        T.equal(params.name, "yumako-tree", "the planned crop is created")
        T.equal(params.register_plant, true, "created crops register with agricultural towers")
        T.equal(params.tick_grown, nil, "created crops use their normal growth duration")
    end
    T.equal(center_found, false, "the agricultural tower center is not planted")

    local inserted_stacks = {}
    local counts = {["yumako-seed\0normal"] = 7}
    local inventory = {}
    function inventory.get_item_count(filter)
        return counts[filter.name .. "\0" .. (filter.quality or "normal")] or 0
    end
    function inventory.insert(stack)
        inserted_stacks[#inserted_stacks + 1] = stack
        local key = stack.name .. "\0" .. (stack.quality or "normal")
        counts[key] = (counts[key] or 0) + stack.count
        return stack.count
    end

    local non_logistic_ok = pcall(function()
        agriculture.fill_requested_seeds {
            valid = true,
            type = "assembling-machine",
            name = "assembling-machine-3",
        }
    end)
    T.equal(non_logistic_ok, true, "entities without logistic sections are skipped directly")

    local entity = {valid = true, type = "logistic-container", name = "requester-chest"}
    function entity.get_inventory(index)
        if index == defines.inventory.chest then return inventory end
    end
    function entity.get_logistic_sections()
        return {
            valid = true,
            sections = {
                {
                    valid = true,
                    active = true,
                    multiplier = 1,
                    filters = {
                        {value = {name = "yumako-seed", quality = "normal"}, min = 50},
                        {value = {name = "iron-plate", quality = "normal"}, min = 100},
                    },
                },
                {
                    valid = true,
                    active = false,
                    multiplier = 1,
                    filters = {
                        {value = {name = "jellynut-seed", quality = "normal"}, min = 50},
                    },
                },
            },
        }
    end

    agriculture.fill_requested_seeds(entity)
    T.equal(#inserted_stacks, 1, "only active seed requests are fulfilled")
    T.equal(inserted_stacks[1].name, "yumako-seed", "the requested seed is inserted")
    T.equal(inserted_stacks[1].count, 43, "only the amount missing from the requested total is inserted")
    T.equal(inserted_stacks[1].quality, "normal", "the requested seed quality is preserved")
end
