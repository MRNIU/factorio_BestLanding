-- Copyright The MRNIU/factorio_BestLanding Contributors
-- 顺序加载所有独立 Lua 测试。

package.path = "./?.lua;./tests/?.lua;" .. package.path

local T = require("testlib")
require("test_resource_zones")(T)
require("test_place_resources")(T)
require("test_territory_cleanup")(T)
T.finish()
