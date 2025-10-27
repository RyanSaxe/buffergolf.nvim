-- Stats aggregation functions
local par = require("buffergolf.stats.par")
local metrics = require("buffergolf.stats.metrics")

local M = {}

function M.get_stats(session)
	return {
		correct_chars = metrics.count_correct_characters(session),
		wpm = metrics.calculate_wpm(session),
		keystrokes = metrics.get_keystroke_count(session),
		par = session.par or par.calculate_par(session),
	}
end

return M