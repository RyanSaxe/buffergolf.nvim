-- Stats module facade
local par = require("buffergolf.stats.par")
local metrics = require("buffergolf.stats.metrics")

local M = {}

-- Forward par functions
M.calculate_edit_distance = par.calculate_edit_distance
M.calculate_par = par.calculate_par

-- Forward metrics functions
M.get_keystroke_count = metrics.get_keystroke_count
M.count_correct_characters = metrics.count_correct_characters
M.calculate_wpm = metrics.calculate_wpm

function M.get_stats(session)
	return {
		correct_chars = M.count_correct_characters(session),
		wpm = M.calculate_wpm(session),
		keystrokes = M.get_keystroke_count(session),
		par = session.par or M.calculate_par(session),
	}
end

return M