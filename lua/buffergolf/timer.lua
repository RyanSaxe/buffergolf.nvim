local stats = require("buffergolf.stats")
local buffer = require("buffergolf.buffer")
local keystroke = require("buffergolf.keystroke")

local M = {}

local buf_valid = buffer.buf_valid
local win_valid = buffer.win_valid

local function format_time(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", minutes, secs)
end

local function get_elapsed_seconds(session)
	if not session.timer_state or not session.timer_state.start_time then
		return 0
	end

	local elapsed_ns = vim.loop.hrtime() - session.timer_state.start_time
	return math.floor(elapsed_ns / 1e9)
end

local function get_display_time(session)
	if not session.timer_state.start_time then
		return "--:--"
	end

	local elapsed = get_elapsed_seconds(session)

	if session.timer_state.countdown_mode then
		local remaining = math.max(0, session.timer_state.countdown_duration - elapsed)
		return format_time(remaining)
	else
		return format_time(elapsed)
	end
end

local function check_completion(session)
	if not buf_valid(session.practice_buf) or not session.reference_lines then
		return false
	end

	local ok, actual_lines = pcall(vim.api.nvim_buf_get_lines, session.practice_buf, 0, -1, true)
	if not ok or not actual_lines then
		return false
	end

	-- Normalize actual lines to match reference line normalization
	actual_lines = buffer.normalize_lines(actual_lines, session.practice_buf)

	-- Strip trailing empty lines from both actual and reference
	actual_lines = buffer.strip_trailing_empty_lines(actual_lines)
	local reference_lines = buffer.strip_trailing_empty_lines(session.reference_lines)

	-- Check if line counts match
	if #actual_lines ~= #reference_lines then
		return false
	end

	-- Check if all lines match exactly (after normalization)
	for i = 1, #actual_lines do
		if actual_lines[i] ~= reference_lines[i] then
			return false
		end
	end

	return true
end

local function freeze_stats(session)
	if session.timer_state.frozen_time then
		return -- Already frozen
	end

	session.timer_state.frozen_time = get_display_time(session)
	session.timer_state.frozen_wpm = stats.calculate_wpm(session)
	session.timer_state.frozen_keystrokes = stats.get_keystroke_count(session)
end

local function complete_session(session, reason)
	-- Unified completion logic for both text completion and countdown expiration
	if session.timer_state.completed then
		return -- Already completed
	end

	-- Freeze stats first
	freeze_stats(session)

	-- Mark as completed/locked and stop counting keys
	session.timer_state.completed = true
	session.timer_state.locked = true
	keystroke.set_tracking_enabled(session, false)

	-- Lock the buffer to prevent further edits
	if buf_valid(session.practice_buf) then
		pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = session.practice_buf })
		pcall(vim.api.nvim_set_option_value, "readonly", true, { buf = session.practice_buf })
	end

	-- Notify user based on completion reason
	if reason == "completed" then
		vim.notify("Buffergolf completed! 🎉", vim.log.levels.INFO, { title = "buffergolf" })
	elseif reason == "time_up" then
		vim.notify("Time's up!", vim.log.levels.WARN, { title = "buffergolf" })
	end
end

local function check_countdown_expired(session)
	if not session.timer_state.countdown_mode or session.timer_state.completed then
		return false
	end

	local elapsed = get_elapsed_seconds(session)
	if elapsed >= session.timer_state.countdown_duration then
		complete_session(session, "time_up")
		return true
	end

	return false
end

local function setup_highlights(config)
	-- Setup highlight groups for the stats window
	local bg_color = vim.api.nvim_get_hl(0, { name = "Normal" }).bg or "#1e1e1e"
	local border_color = vim.api.nvim_get_hl(0, { name = "FloatBorder" }).fg or "#4a4a4a"

	vim.api.nvim_set_hl(0, "BuffergolfStatsFloat", {
		bg = bg_color,
		fg = "#a8c7fa",
		blend = 0,
	})

	vim.api.nvim_set_hl(0, "BuffergolfStatsBorder", {
		fg = "#6d8aad",
		bg = bg_color,
	})

	-- Success/completion highlight (green)
	vim.api.nvim_set_hl(0, "BuffergolfStatsComplete", {
		bg = bg_color,
		fg = "#7fdc7f",
		bold = true,
		blend = 0,
	})

	vim.api.nvim_set_hl(0, "BuffergolfStatsBorderComplete", {
		fg = "#5eb65e",
		bg = bg_color,
	})
end

local function create_stats_window(session)
	-- Setup highlights
	setup_highlights(session.config)

	-- Validate practice window exists
	if not win_valid(session.practice_win) then
		session.timer_state.stats_win = nil
		session.timer_state.stats_buf = nil
		return
	end

	-- Create buffer for stats display
	local stats_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = stats_buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = stats_buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = stats_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = stats_buf })
	vim.api.nvim_set_option_value("filetype", "BuffergolfStats", { buf = stats_buf })

	-- Set buffer name so statusline plugins ignore it
	pcall(vim.api.nvim_buf_set_name, stats_buf, "BuffergolfStats")

	-- Get position from config (default to top)
	local position = (session.config.stats_window and session.config.stats_window.position) or "top"

	-- Save current window
	local orig_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(session.practice_win)

	-- Create split above or below practice window
	if position == "bottom" then
		vim.cmd("rightbelow split")
	else
		vim.cmd("leftabove split")
	end

	local stats_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(stats_win, stats_buf)

	-- Set fixed height (4 lines to ensure underline shows)
	vim.api.nvim_win_set_height(stats_win, 4)

	-- Configure window options
	vim.api.nvim_set_option_value("number", false, { win = stats_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = stats_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = stats_win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = stats_win })
	vim.api.nvim_set_option_value("wrap", false, { win = stats_win })
	vim.api.nvim_set_option_value("cursorline", false, { win = stats_win })
	vim.api.nvim_set_option_value("winhl", "Normal:BuffergolfStatsFloat", { win = stats_win })

	-- Completely hide statusline and winbar
	vim.api.nvim_set_option_value("statusline", " ", { win = stats_win })
	vim.api.nvim_set_option_value("winbar", "", { win = stats_win })

	-- Return to original window
	vim.api.nvim_set_current_win(orig_win)

	session.timer_state.stats_win = stats_win
	session.timer_state.stats_buf = stats_buf
end

-- Helper to get mini.diff summary for golf mode
local function get_diff_summary(reference_buf)
	if not reference_buf or not buf_valid(reference_buf) then
		return nil
	end

	-- Get summary from mini.diff API
	local ok, minidiff = pcall(require, "mini.diff")
	if not ok or not minidiff.get_buf_data then
		return nil
	end

	local buf_data = minidiff.get_buf_data(reference_buf)
	if not buf_data or not buf_data.summary then
		return nil
	end

	return buf_data.summary
end

-- Helper to get diff icons (used by both formatting and highlighting)
local function get_diff_icons()
	local icons = (function()
		local ok, LV = pcall(require, "lazyvim.util")
		return ok and LV.config.icons or {
			git = { added = " ", modified = " ", removed = " " },
		}
	end)()

	return {
		add = icons.git.added or "+",
		delete = icons.git.removed or "-",
		change = icons.git.modified or "~",
	}
end

-- Format diff summary with icons
local function format_diff_summary(summary)
	if not summary then
		return ""
	end

	local diff_icons = get_diff_icons()

	local parts = {}
	if summary.add and summary.add > 0 then
		table.insert(parts, string.format("%s%d", diff_icons.add, summary.add))
	end
	if summary.delete and summary.delete > 0 then
		table.insert(parts, string.format("%s%d", diff_icons.delete, summary.delete))
	end
	if summary.change and summary.change > 0 then
		table.insert(parts, string.format("%s%d", diff_icons.change, summary.change))
	end

	return table.concat(parts, " ")
end

function M.update_stats_float(session)
	if
		not session.timer_state.stats_buf
		or not buf_valid(session.timer_state.stats_buf)
		or not session.timer_state.stats_win
		or not win_valid(session.timer_state.stats_win)
	then
		create_stats_window(session)
	end

	if
		not session.timer_state.stats_buf
		or not buf_valid(session.timer_state.stats_buf)
		or not session.timer_state.stats_win
		or not win_valid(session.timer_state.stats_win)
	then
		return
	end

	-- Validate practice window
	if not win_valid(session.practice_win) then
		return
	end

	local stats_buf = session.timer_state.stats_buf
	if not buf_valid(stats_buf) then
		return
	end

	-- Get window width for content formatting
	local win_width = vim.api.nvim_win_get_width(session.timer_state.stats_win)

	-- Check for countdown expiration
	check_countdown_expired(session)

	-- Check for completion
	if not session.timer_state.completed and check_completion(session) then
		complete_session(session, "completed")
	end

	-- Use frozen values if locked or completed
	local time_str, wpm
	if session.timer_state.locked or session.timer_state.completed then
		time_str = session.timer_state.frozen_time or get_display_time(session)
		wpm = session.timer_state.frozen_wpm or stats.calculate_wpm(session)
	else
		time_str = get_display_time(session)
		wpm = stats.calculate_wpm(session)
	end

	-- Get keystroke and par info
	local keystrokes = stats.get_keystroke_count(session)
	local par = session.par or 0

	-- Build left-aligned stats: Time and Score/WPM only
	local left_parts = {}

	-- Time with label
	table.insert(left_parts, string.format("Time: %s", time_str))

	-- Score/WPM
	local score_display
	if session.mode == "golf" then
		-- Golf mode: Show score percentage
		if par > 0 then
			local score_pct = (1 - keystrokes / par) * 100

			if score_pct > 0 then
				score_display = string.format("Score: +%.1f%%", score_pct)
			elseif score_pct < 0 then
				score_display = string.format("Score: %.1f%%", score_pct)
			else
				score_display = "Score: 0.0%"
			end
		else
			score_display = "Score: N/A"
		end
	else
		-- Typing mode: Show WPM
		score_display = string.format("WPM: %d", wpm)
	end
	table.insert(left_parts, score_display)

	local left_str = table.concat(left_parts, " │ ")

	-- Build right-aligned stats: Keys, Par, and optionally Diff summary
	local right_parts = {}

	-- Keystrokes
	table.insert(right_parts, string.format("Keys: %d", keystrokes))

	-- Par
	table.insert(right_parts, string.format("Par: %d", par))

	-- Diff summary (golf mode only)
	if session.mode == "golf" and session.reference_buf then
		local summary = get_diff_summary(session.reference_buf)
		if summary then
			local diff_str = format_diff_summary(summary)
			if diff_str ~= "" then
				table.insert(right_parts, diff_str)
			end
		end
	end

	local right_str = table.concat(right_parts, " │ ")

	-- Calculate padding between left and right
	local left_width = vim.fn.strdisplaywidth(left_str)
	local right_width = vim.fn.strdisplaywidth(right_str)
	local padding_width = math.max(1, win_width - left_width - right_width)
	local padding = string.rep(" ", padding_width)

	-- Build the main line
	local main_line = left_str .. padding .. right_str

	-- Create multi-line content with visual separator
	local separator = string.rep("─", win_width)
	local content_lines = {
		"", -- Empty line for spacing
		" " .. main_line, -- Main content with left padding
		separator, -- Bottom border
	}

	-- Update window highlights based on completion state
	if session.timer_state.stats_win and win_valid(session.timer_state.stats_win) then
		local winhl = session.timer_state.completed
				and "Normal:BuffergolfStatsComplete,FloatBorder:BuffergolfStatsBorderComplete"
			or "Normal:BuffergolfStatsFloat,FloatBorder:BuffergolfStatsBorder"
		pcall(vim.api.nvim_set_option_value, "winhl", winhl, { win = session.timer_state.stats_win })
	end

	-- Update buffer text (make modifiable temporarily)
	pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = session.timer_state.stats_buf })
	pcall(vim.api.nvim_buf_set_lines, session.timer_state.stats_buf, 0, -1, false, content_lines)
	pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = session.timer_state.stats_buf })

	-- Apply highlighting for golf mode (diff summary only - no score coloring)
	local ns_id = vim.api.nvim_create_namespace("buffergolf_highlights")
	pcall(vim.api.nvim_buf_clear_namespace, session.timer_state.stats_buf, ns_id, 0, -1)

	-- Apply diff summary highlighting (golf mode only)
	if session.mode == "golf" and session.reference_buf and #right_parts > 2 then
		local summary = get_diff_summary(session.reference_buf)
		if summary then
			-- The line is: " " .. main_line where main_line = left_str .. padding .. right_str
			-- We need byte position, not display width
			-- Calculate the byte position where diff summary starts
			local prefix = " " .. left_str .. padding .. right_parts[1] .. " │ " .. right_parts[2] .. " │ "
			local diff_start_byte = #prefix -- Byte offset where diff summary begins

			-- Get the actual diff string components - must match format_diff_summary()
			local diff_icons = get_diff_icons()

			local current_byte = diff_start_byte

			-- Build and highlight each component
			local parts = {}

			-- Add
			if summary.add and summary.add > 0 then
				local add_str = string.format("%s%d", diff_icons.add, summary.add)
				table.insert(parts, {
					str = add_str,
					hl = "MiniDiffSignAdd",
				})
			end

			-- Delete
			if summary.delete and summary.delete > 0 then
				local delete_str = string.format("%s%d", diff_icons.delete, summary.delete)
				table.insert(parts, {
					str = delete_str,
					hl = "MiniDiffSignDelete",
				})
			end

			-- Change
			if summary.change and summary.change > 0 then
				local change_str = string.format("%s%d", diff_icons.change, summary.change)
				table.insert(parts, {
					str = change_str,
					hl = "MiniDiffSignChange",
				})
			end

			-- Apply highlights
			for i, part in ipairs(parts) do
				local byte_len = #part.str
				pcall(
					vim.api.nvim_buf_add_highlight,
					session.timer_state.stats_buf,
					ns_id,
					part.hl,
					1, -- Second line (0-indexed) - main content line
					current_byte,
					current_byte + byte_len
				)
				current_byte = current_byte + byte_len

				-- Add space separator byte if not the last part
				if i < #parts then
					current_byte = current_byte + 1 -- Space separator
				end
			end
		end
	end
end

function M.on_first_edit(session)
	if not session.timer_state then
		return
	end

	if session.timer_state.start_time then
		return
	end

	session.timer_state.start_time = vim.loop.hrtime()
	M.update_stats_float(session)
end

function M.start_countdown(session, seconds)
	if not session or not session.timer_state then
		return
	end

	-- Reset timer state
	session.timer_state.start_time = nil
	session.timer_state.locked = false
	session.timer_state.completed = false
	session.timer_state.frozen_time = nil
	session.timer_state.frozen_wpm = nil
	session.timer_state.frozen_keystrokes = nil

	-- Handle nil or 0 as count-up mode
	if not seconds or seconds == 0 then
		-- Count-up mode (no countdown)
		session.timer_state.countdown_mode = false
		session.timer_state.countdown_duration = nil
	else
		-- Countdown mode
		session.timer_state.countdown_mode = true
		session.timer_state.countdown_duration = seconds
	end

	-- Unlock buffer if it was previously locked
	if buf_valid(session.practice_buf) then
		pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = session.practice_buf })
		pcall(vim.api.nvim_set_option_value, "readonly", false, { buf = session.practice_buf })
	end

	keystroke.set_tracking_enabled(session, true)

	-- Timer will start on first edit
	M.update_stats_float(session)
end

function M.init(session)
	session.timer_state = {
		start_time = nil,
		countdown_mode = false,
		countdown_duration = 0,
		locked = false,
		completed = false,
		frozen_time = nil,
		frozen_wpm = nil,
		frozen_keystrokes = nil,
		stats_win = nil,
		stats_buf = nil,
		update_timer = nil,
	}

	-- Create split window for stats
	create_stats_window(session)

	-- Create periodic update timer (250ms)
	local timer = vim.loop.new_timer()
	session.timer_state.update_timer = timer

	timer:start(
		250,
		250,
		vim.schedule_wrap(function()
			if not session.timer_state then
				timer:stop()
				timer:close()
				return
			end

			if not win_valid(session.practice_win) or not buf_valid(session.practice_buf) then
				timer:stop()
				timer:close()
				return
			end

			M.update_stats_float(session)
		end)
	)

	-- Initial stats display
	M.update_stats_float(session)
end

function M.cleanup(session)
	if not session.timer_state then
		return
	end

	-- Stop and close the update timer
	if session.timer_state.update_timer then
		local timer = session.timer_state.update_timer
		if not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end

	-- Close stats floating window
	if session.timer_state.stats_win and win_valid(session.timer_state.stats_win) then
		pcall(vim.api.nvim_win_close, session.timer_state.stats_win, true)
	end

	-- Delete stats buffer (will auto-wipe due to bufhidden=wipe)
	if session.timer_state.stats_buf and buf_valid(session.timer_state.stats_buf) then
		pcall(vim.api.nvim_buf_delete, session.timer_state.stats_buf, { force = true })
	end

	session.timer_state = nil
end

return M
