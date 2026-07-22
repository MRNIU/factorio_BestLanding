-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 最小化的无依赖 Lua 测试助手。

local M = { total = 0, failed = 0 }

function M.equal(actual, expected, message)
    M.total = M.total + 1
    if actual ~= expected then
        M.failed = M.failed + 1
        io.stderr:write((message or "values differ")
            .. (": expected %s, got %s\n"):format(tostring(expected), tostring(actual)))
    end
end

function M.truthy(actual, message)
    M.equal(not not actual, true, message)
end

function M.finish()
    if M.failed > 0 then
        io.stderr:write(("FAIL %d/%d assertions\n"):format(M.failed, M.total))
        os.exit(1)
    end
    print(("PASS %d assertions"):format(M.total))
end

return M
