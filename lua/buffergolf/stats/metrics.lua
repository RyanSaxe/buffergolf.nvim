local keystroke = require("buffergolf.keystroke")

local M = {}

local function trim(str)
	return str:match("^%s*(.-)%s*$") or ""
end

function M.get_keystroke_count(session)
	if session and session.timer_state and session.timer_state.frozen_keystrokes ~= nil then
		return session.timer_state.frozen_keystrokes
	end
	return keystroke.get_count(session)
end

function M.count_correct_characters(session)
	if not session or not session.practice_buf or not session.reference_lines then return 0 end

	local ok, actual_lines = pcall(vim.api.nvim_buf_get_lines, session.practice_buf, 0, -1, true)
	if not ok or not actual_lines then return 0 end

	local correct_count = 0
	for row = 1, math.max(#actual_lines, #session.reference_lines) do
		local actual_trimmed = trim(actual_lines[row] or "")
		local reference_trimmed = trim(session.reference_lines[row] or "")

		for i = 1, math.min(#actual_trimmed, #reference_trimmed) do
			if actual_trimmed:sub(i, i) == reference_trimmed:sub(i, i) then
				correct_count = correct_count + 1
			else
				break
			end
		end
	end

	return correct_count
end

function M.calculate_wpm(session)
	if not session or not session.timer_state or not session.timer_state.start_time then return 0 end

	local elapsed_seconds = (vim.loop.hrtime() - session.timer_state.start_time) / 1e9
	if elapsed_seconds < 0.1 then return 0 end

	local correct_chars = M.count_correct_characters(session)
	return math.floor((correct_chars / 5) / (elapsed_seconds / 60) + 0.5)
end

return M