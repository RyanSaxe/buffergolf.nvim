local buffer = require("buffergolf.buffer")
local visual = require("buffergolf.visual")
local timer = require("buffergolf.timer")

local M = {}

function M.schedule_refresh(session)
	if session.refresh_scheduled then return end
	session.refresh_scheduled = true
	vim.schedule(function()
		session.refresh_scheduled = nil
		local storage = require("buffergolf.session.storage")
		if not session or not session.practice_buf or
		   storage.by_practice(session.practice_buf) ~= session or
		   not buffer.buf_valid(session.practice_buf) or
		   (session.timer_state and (session.timer_state.locked or session.timer_state.completed)) then
			return
		end
		visual.refresh(session)
	end)
end

function M.setup(session)
	local aug = vim.api.nvim_create_augroup(("BuffergolfSession_%d"):format(session.practice_buf), { clear = true })
	session.augroup = aug

	local cmds = {
		{ "BufEnter", function() buffer.apply_defaults(session) end },
		{ "BufWriteCmd", function()
			vim.notify("Buffergolf buffers cannot be written.", vim.log.levels.WARN, { title = "buffergolf" })
		end },
		{ "LspAttach", function() buffer.apply_defaults(session) end },
		{ { "BufLeave", "BufHidden" }, function()
			if buffer.buf_valid(session.practice_buf) then
				pcall(vim.api.nvim_set_option_value, "modified", false, { buf = session.practice_buf })
			end
		end },
		{ { "BufWipeout", "BufDelete" }, function()
			if not vim.api.nvim_buf_is_valid(session.practice_buf) then
				local lifecycle = require("buffergolf.session.lifecycle")
				lifecycle.clear_state(session)
			end
		end },
	}

	for _, cmd in ipairs(cmds) do
		vim.api.nvim_create_autocmd(cmd[1], {
			group = aug,
			buffer = session.practice_buf,
			callback = cmd[2]
		})
	end
end

function M.setup_change_watcher(session)
	visual.attach_change_watcher(session, {
		is_session_active = function(buf, target)
			local storage = require("buffergolf.session.storage")
			return storage.by_practice(buf) == target
		end,
		on_first_edit = timer.on_first_edit,
		schedule_refresh = M.schedule_refresh,
	})
end

return M