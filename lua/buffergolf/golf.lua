-- Golf module facade
local window = require("buffergolf.golf.window")
local navigation = require("buffergolf.golf.navigation")

local M = {}

-- Forward window functions
M.create_reference_window = window.create_reference_window
M.setup_mini_diff = window.setup_mini_diff

-- Forward navigation functions
M.goto_hunk_sync = navigation.goto_hunk_sync
M.setup_navigation = navigation.setup

return M