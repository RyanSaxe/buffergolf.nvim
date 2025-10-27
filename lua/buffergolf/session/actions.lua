-- Session actions
local storage = require("buffergolf.session.storage")
local timer = require("buffergolf.timer.control")

local M = {}

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