local buffer = require("buffergolf.session.buffer")

local M = {}

local function setup_highlights(config)
	local bg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg or "#1e1e1e"

	vim.api.nvim_set_hl(0, "BuffergolfStatsFloat", { bg = bg, fg = "#a8c7fa", blend = 0 })
	vim.api.nvim_set_hl(0, "BuffergolfStatsBorder", { bg = bg, fg = "#6d8aad" })
	vim.api.nvim_set_hl(0, "BuffergolfStatsComplete", { bg = bg, fg = "#7fdc7f", bold = true, blend = 0 })
	vim.api.nvim_set_hl(0, "BuffergolfStatsBorderComplete", { bg = bg, fg = "#5eb65e" })
end

function M.create_stats_window(session)
	setup_highlights(session.config)

	if not buffer.win_valid(session.practice_win) then
		session.timer_state.stats_win = nil
		session.timer_state.stats_buf = nil
		return
	end

	local stats_buf = vim.api.nvim_create_buf(false, true)
	local buf_opts = { bufhidden = "wipe", buftype = "nofile", modifiable = false, swapfile = false, filetype = "BuffergolfStats" }
	for opt, val in pairs(buf_opts) do
		vim.api.nvim_set_option_value(opt, val, { buf = stats_buf })
	end
	pcall(vim.api.nvim_buf_set_name, stats_buf, "BuffergolfStats")

	local position = (session.config.stats_window and session.config.stats_window.position) or "top"
	local orig_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(session.practice_win)
	vim.cmd(position == "bottom" and "rightbelow split" or "leftabove split")

	local stats_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(stats_win, stats_buf)
	vim.api.nvim_win_set_height(stats_win, 3)

	local win_opts = { number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
		wrap = false, cursorline = false, winhl = "Normal:BuffergolfStatsFloat", statusline = " ", winbar = "" }
	for opt, val in pairs(win_opts) do
		vim.api.nvim_set_option_value(opt, val, { win = stats_win })
	end

	vim.api.nvim_set_current_win(orig_win)

	session.timer_state.stats_win = stats_win
	session.timer_state.stats_buf = stats_buf
end

local function get_diff_summary(reference_buf)
	if not reference_buf or not buffer.buf_valid(reference_buf) then
		return nil
	end
	local ok, minidiff = pcall(require, "mini.diff")
	if not ok or not minidiff.get_buf_data then
		return nil
	end
	local buf_data = minidiff.get_buf_data(reference_buf)
	return buf_data and buf_data.summary
end

local function get_diff_icons()
	local ok, LV = pcall(require, "lazyvim.util")
	local icons = ok and LV.config.icons or { git = { added = " ", modified = " ", removed = " " } }
	return {
		add = icons.git.added or "+",
		delete = icons.git.removed or "-",
		change = icons.git.modified or "~",
	}
end

local function build_diff_segments(summary)
	if not summary then return {} end
	local diff_icons = get_diff_icons()
	local segments = {}
	local types = { { "add", "MiniDiffSignAdd" }, { "delete", "MiniDiffSignDelete" }, { "change", "MiniDiffSignChange" } }
	for _, t in ipairs(types) do
		local key, hl = t[1], t[2]
		if summary[key] and summary[key] > 0 then
			table.insert(segments, { text = string.format("%s%d", diff_icons[key], summary[key]), hl = hl })
		end
	end
	return segments
end

function M.render_stats(session, time_str, wpm, keystrokes, par)
	local stats_buf = session.timer_state.stats_buf
	local stats_win = session.timer_state.stats_win
	if not buffer.buf_valid(stats_buf) or not buffer.win_valid(stats_win) then return end

	local win_width = vim.api.nvim_win_get_width(stats_win)
	local sections = {}

	table.insert(sections, {{ text = string.format("Time: %s", time_str) }})

	local score_display
	if session.mode == "golf" then
		if par > 0 then
			local score_pct = (1 - keystrokes / par) * 100
			local sign = score_pct > 0 and "+" or ""
			score_display = string.format("Score: %s%.1f%%", sign, score_pct)
		else
			score_display = "Score: N/A"
		end
	else
		score_display = string.format("WPM: %d", wpm)
	end
	table.insert(sections, {{ text = score_display }})
	table.insert(sections, {{ text = string.format("Keys: %d", keystrokes) }})
	table.insert(sections, {{ text = string.format("Par: %d", par) }})

	if session.mode == "golf" and session.reference_buf then
		local diff_segments = build_diff_segments(get_diff_summary(session.reference_buf))
		if #diff_segments > 0 then
			local spaced = {}
			for i, seg in ipairs(diff_segments) do
				if i > 1 then table.insert(spaced, { text = " " }) end
				table.insert(spaced, seg)
			end
			table.insert(sections, spaced)
		end
	end

	local line_segments = {}
	for i, section in ipairs(sections) do
		if i > 1 then table.insert(line_segments, { text = " │ " }) end
		for _, segment in ipairs(section) do
			table.insert(line_segments, segment)
		end
	end

	local stats_line = ""
	local highlight_ranges = {}
	for _, seg in ipairs(line_segments) do
		local start = #stats_line
		stats_line = stats_line .. seg.text
		if seg.hl then
			table.insert(highlight_ranges, { hl = seg.hl, start_byte = start, end_byte = start + #seg.text })
		end
	end

	local left_padding = math.max(0, math.floor((win_width - vim.fn.strdisplaywidth(stats_line)) / 2))
	local content_lines = { "", string.rep(" ", left_padding) .. stats_line, string.rep("─", win_width) }

	local winhl = session.timer_state.completed
		and "Normal:BuffergolfStatsComplete,FloatBorder:BuffergolfStatsBorderComplete"
		or "Normal:BuffergolfStatsFloat,FloatBorder:BuffergolfStatsBorder"
	pcall(vim.api.nvim_set_option_value, "winhl", winhl, { win = stats_win })

	pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = stats_buf })
	pcall(vim.api.nvim_buf_set_lines, stats_buf, 0, -1, false, content_lines)
	pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = stats_buf })

	if #highlight_ranges > 0 then
		local ns_id = vim.api.nvim_create_namespace("buffergolf_highlights")
		pcall(vim.api.nvim_buf_clear_namespace, stats_buf, ns_id, 0, -1)
		for _, r in ipairs(highlight_ranges) do
			pcall(vim.api.nvim_buf_add_highlight, stats_buf, ns_id, r.hl, 1,
				left_padding + r.start_byte, left_padding + r.end_byte)
		end
	end
end

function M.close_stats_window(session)
	if not session.timer_state then return end
	if session.timer_state.stats_win and buffer.win_valid(session.timer_state.stats_win) then
		pcall(vim.api.nvim_win_close, session.timer_state.stats_win, true)
	end
	if session.timer_state.stats_buf and buffer.buf_valid(session.timer_state.stats_buf) then
		pcall(vim.api.nvim_buf_delete, session.timer_state.stats_buf, { force = true })
	end
	session.timer_state.stats_win = nil
	session.timer_state.stats_buf = nil
end

return M