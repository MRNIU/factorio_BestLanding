-- Copyright The MRNIU/factorio_BestLanding Contributors
-- Chunk 生成 helper。
-- Factorio 的 find_entities_* / set_tiles 在未生成的 chunk 上会静默返回空 / 无效果，
-- 所以动这类区域前必须先把覆盖到的 chunk 都显式生成完。

local C = require("constants")

local M = {}

-- 把一个 {left_top, right_bottom} 区域折算成覆盖的 chunk 矩形边界
local function chunk_bounds(area)
    return {
        left   = math.floor(area.left_top.x     / C.CHUNK_SIZE),
        top    = math.floor(area.left_top.y     / C.CHUNK_SIZE),
        right  = math.floor(area.right_bottom.x / C.CHUNK_SIZE),
        bottom = math.floor(area.right_bottom.y / C.CHUNK_SIZE),
    }
end

-- 批量请求一片 chunk，然后一次性 force_generate_chunk_requests 阻塞等完。
-- 批量 + 单次 force 是 Factorio 官方推荐姿势，比每个 chunk 都 force 快得多。
function M.force_generate(surface, area)
    local b = chunk_bounds(area)
    for cx = b.left, b.right do
        for cy = b.top, b.bottom do
            surface.request_to_generate_chunks({ cx * C.CHUNK_SIZE, cy * C.CHUNK_SIZE }, 0)
        end
    end
    surface.force_generate_chunk_requests()
end

-- 只生成 outer 区域内、inner 区域外的那一圈 chunk（即"环形"）
-- 用于 Vulcanus Demolisher 扫描扩围：inner 已经生成过了，只需要补外环。
function M.force_generate_ring(surface, inner, outer)
    local ob = chunk_bounds(outer)
    local ib = chunk_bounds(inner)
    for cx = ob.left, ob.right do
        for cy = ob.top, ob.bottom do
            local inside_inner = cx >= ib.left and cx <= ib.right
                             and cy >= ib.top  and cy <= ib.bottom
            if not inside_inner then
                surface.request_to_generate_chunks({ cx * C.CHUNK_SIZE, cy * C.CHUNK_SIZE }, 0)
            end
        end
    end
    surface.force_generate_chunk_requests()
end

return M
