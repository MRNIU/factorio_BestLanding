-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 删除与基地及外围一圈 chunk 重合的完整领地，并把这些 chunk 永久设为无领地。

local C = require("constants")

local M = {}

function M.clear_area(surface, area)
    local margin = C.TERRITORY_CLEAR_MARGIN_CHUNKS
    local left   = math.floor(area.left_top.x / C.CHUNK_SIZE) - margin
    local top    = math.floor(area.left_top.y / C.CHUNK_SIZE) - margin
    local right  = math.ceil(area.right_bottom.x / C.CHUNK_SIZE) - 1 + margin
    local bottom = math.ceil(area.right_bottom.y / C.CHUNK_SIZE) - 1 + margin

    local chunk_positions = {}
    local territories = {}
    for x = left, right do
        for y = top, bottom do
            local chunk = {x = x, y = y}
            chunk_positions[#chunk_positions + 1] = chunk
            local territory = surface.get_territory_for_chunk(chunk)
            if territory and territory.valid then
                territories[territory] = true
            end
        end
    end

    for territory in pairs(territories) do
        if territory.valid then
            territory.destroy()
        end
    end

    -- territory=nil 会移除归属并阻止地图生成器以后在这些 chunk 自动重建领地。
    surface.set_territory_for_chunks(chunk_positions, nil)
end

return M
