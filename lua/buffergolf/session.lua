-- Session module facade
local storage = require("buffergolf.session.storage")
local lifecycle = require("buffergolf.session.lifecycle")
local timer = require("buffergolf.timer")

local M = {}

-- Forward storage functions
M.is_active = storage.is_active
M.get = storage.get

-- Forward lifecycle functions
M.start = lifecycle.start
M.start_golf = lifecycle.start_golf
M.stop = lifecycle.stop
M.reset_to_start = lifecycle.reset_to_start

function M.start_countdown(bufnr, seconds)
	local session = storage.get(bufnr)
	if not session then
		vim.notify("No active buffergolf session", vim.log.levels.WARN, { title = "buffergolf" })
		return false
	end
	timer.start_countdown(session, seconds)
	return true
end

return M