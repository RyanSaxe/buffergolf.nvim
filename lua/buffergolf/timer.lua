-- Timer module facade - delegates to split modules
local timer_core = require("buffergolf.timer.timer")

local M = {}

-- Public API - forward all functions to the core module
M.init = timer_core.init
M.update_stats_float = timer_core.update_stats_float
M.on_first_edit = timer_core.on_first_edit
M.start_countdown = timer_core.start_countdown
M.cleanup = timer_core.cleanup

return M