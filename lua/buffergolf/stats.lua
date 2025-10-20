local keystroke = require("buffergolf.keystroke")

local M = {}

local function trim_whitespace(str)
  return str:match("^%s*(.-)%s*$") or ""
end

function M.calculate_par(reference_lines)
  -- Calculate par as the number of keystrokes needed to type the reference text
  -- from an empty buffer, excluding leading/trailing whitespace per line
  -- (since autoindent should handle those for free)
  if not reference_lines or #reference_lines == 0 then
    return 0
  end

  local par = 0

  for _, line in ipairs(reference_lines) do
    local trimmed = trim_whitespace(line)
    par = par + #trimmed
  end

  -- Add newlines between lines (not after the last line)
  if #reference_lines > 1 then
    par = par + (#reference_lines - 1)
  end

  -- Add one keystroke to enter insert mode
  par = par + 1

  return par
end

function M.get_keystroke_count(session)
  return keystroke.get_count(session)
end

function M.count_correct_characters(session)
  if not session or not session.practice_buf or not session.reference_lines then
    return 0
  end

  local ok, actual_lines = pcall(vim.api.nvim_buf_get_lines, session.practice_buf, 0, -1, true)
  if not ok or not actual_lines then
    return 0
  end

  local correct_count = 0

  for row = 1, math.max(#actual_lines, #session.reference_lines) do
    local actual = actual_lines[row] or ""
    local reference = session.reference_lines[row] or ""

    -- Trim leading and trailing whitespace for both
    local actual_trimmed = trim_whitespace(actual)
    local reference_trimmed = trim_whitespace(reference)

    -- Find the offsets where the trimmed content starts and ends in the original strings
    local actual_start = actual:find("%S") or (#actual + 1)
    local reference_start = reference:find("%S") or (#reference + 1)

    -- Count matching characters position by position (only in non-trimmed portion)
    local min_len = math.min(#actual_trimmed, #reference_trimmed)

    for i = 1, min_len do
      if actual_trimmed:sub(i, i) == reference_trimmed:sub(i, i) then
        correct_count = correct_count + 1
      else
        -- Stop counting on this line once we hit a mismatch
        break
      end
    end
  end

  return correct_count
end

function M.calculate_wpm(session)
  if not session or not session.timer_state or not session.timer_state.start_time then
    return 0
  end

  local elapsed_ns = vim.loop.hrtime() - session.timer_state.start_time
  local elapsed_seconds = elapsed_ns / 1e9

  -- Avoid division by zero for very short times
  if elapsed_seconds < 0.1 then
    return 0
  end

  local correct_chars = M.count_correct_characters(session)
  local elapsed_minutes = elapsed_seconds / 60

  -- WPM = (correct characters / 5) / minutes
  local wpm = (correct_chars / 5) / elapsed_minutes

  return math.floor(wpm + 0.5)
end

function M.get_stats(session)
  local correct_chars = M.count_correct_characters(session)
  local wpm = M.calculate_wpm(session)
  local keystrokes = M.get_keystroke_count(session)
  local par = M.calculate_par(session.reference_lines)

  return {
    correct_chars = correct_chars,
    wpm = wpm,
    keystrokes = keystrokes,
    par = par,
  }
end

return M
