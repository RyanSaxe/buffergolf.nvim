local keystroke = require("buffergolf.keystroke")

local M = {}

local function trim_whitespace(str)
  return str:match("^%s*(.-)%s*$") or ""
end

-- Calculate character-level Levenshtein edit distance between two strings
local function calculate_string_distance(str1, str2)
  local m, n = #str1, #str2
  local dp = {}

  -- Initialize DP table
  for i = 0, m do
    dp[i] = {}
    dp[i][0] = i
  end
  for j = 0, n do
    dp[0][j] = j
  end

  -- Fill DP table
  for i = 1, m do
    for j = 1, n do
      local cost = (str1:sub(i, i) == str2:sub(j, j)) and 0 or 1
      dp[i][j] = math.min(
        dp[i-1][j] + 1,      -- deletion
        dp[i][j-1] + 1,      -- insertion
        dp[i-1][j-1] + cost  -- substitution
      )
    end
  end

  return dp[m][n]
end

-- Calculate Levenshtein edit distance between two sets of lines (LINE-LEVEL, legacy)
function M.calculate_edit_distance(lines1, lines2)
  -- Trim whitespace from each line for comparison
  local trimmed1 = {}
  for _, line in ipairs(lines1 or {}) do
    table.insert(trimmed1, trim_whitespace(line))
  end

  local trimmed2 = {}
  for _, line in ipairs(lines2 or {}) do
    table.insert(trimmed2, trim_whitespace(line))
  end

  -- Standard Levenshtein algorithm
  local m, n = #trimmed1, #trimmed2
  local dp = {}

  -- Initialize DP table
  for i = 0, m do
    dp[i] = {}
    dp[i][0] = i
  end
  for j = 0, n do
    dp[0][j] = j
  end

  -- Fill DP table
  for i = 1, m do
    for j = 1, n do
      local cost = (trimmed1[i] == trimmed2[j]) and 0 or 1
      dp[i][j] = math.min(
        dp[i-1][j] + 1,      -- deletion
        dp[i][j-1] + 1,      -- insertion
        dp[i-1][j-1] + cost  -- substitution
      )
    end
  end

  return dp[m][n]
end

-- Calculate par for typing mode (from empty buffer)
local function calculate_typing_mode_par(reference_lines)
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

-- Calculate par for golf mode using mini.diff hunks
local function calculate_golf_par_from_hunks(session)
  -- Use the original start and reference lines from session, not current buffer state
  local practice_lines = session.start_lines
  local reference_lines = session.reference_lines

  if not practice_lines or not reference_lines then
    return nil  -- Signal failure, caller should use fallback
  end

  -- Try to get hunks from mini.diff
  local ok, minidiff = pcall(require, 'mini.diff')
  if not ok then
    return nil  -- Signal failure, caller should use fallback
  end

  local buf_data = minidiff.get_buf_data(session.reference_buf)
  if not buf_data or not buf_data.hunks or #buf_data.hunks == 0 then
    -- No hunks means buffers are identical - already at goal
    return 0
  end

  -- Calculate hunk-based par
  local hunk_par = 0

  for _, hunk in ipairs(buf_data.hunks) do
    if hunk.type == "delete" then
      -- Lines exist in the starting text (reference) but not in the goal buffer.
      -- Each requires a `dd` (2 keys) from the practice buffer.
      hunk_par = hunk_par + ((hunk.ref_count or 0) * 2)

    elseif hunk.type == "add" then
      -- Lines exist in the goal buffer but not in the starting text.
      -- Each line needs an insertion: o/append (1 key) + content.
      for i = 1, (hunk.buf_count or 0) do
        local line_idx = (hunk.buf_start or 1) + i - 1
        local target_line = reference_lines[line_idx]
        if target_line then
          local trimmed = trim_whitespace(target_line)
          hunk_par = hunk_par + 1 + #trimmed
        else
          hunk_par = hunk_par + 1
        end
      end

    elseif hunk.type == "change" then
      -- For changed lines, calculate character-level distance
      -- But if too different, dd + rewrite might be cheaper
      local change_par = 0
      local max_count = math.max(hunk.buf_count or 0, hunk.ref_count or 0)

      for i = 1, max_count do
        local start_idx = (hunk.ref_start or 1) + i - 1
        local goal_idx = (hunk.buf_start or 1) + i - 1

        local start_line = practice_lines[start_idx]
        local goal_line = reference_lines[goal_idx]

        if start_line and goal_line then
          -- Both lines exist: calculate char-level edit distance
          local start_trimmed = trim_whitespace(start_line)
          local goal_trimmed = trim_whitespace(goal_line)
          local char_dist = calculate_string_distance(start_trimmed, goal_trimmed)

          -- Compare with dd + rewrite cost
          local rewrite_cost = 2 + #goal_trimmed
          change_par = change_par + math.min(char_dist, rewrite_cost)

        elseif goal_line then
          -- Need to add this line: o + content
          local goal_trimmed = trim_whitespace(goal_line)
          change_par = change_par + 1 + #goal_trimmed

        elseif start_line then
          -- Need to delete this line: dd
          change_par = change_par + 2
        end
      end

      hunk_par = hunk_par + change_par
    end
  end

  -- Calculate nuclear option: ggdG (4 keys) + rewrite from scratch
  local nuclear_par = 4  -- ggdG
  nuclear_par = nuclear_par + 1  -- Enter insert mode (i)

  for _, line in ipairs(reference_lines) do
    local trimmed = trim_whitespace(line)
    nuclear_par = nuclear_par + #trimmed
  end

  -- Add newlines between lines
  if #reference_lines > 1 then
    nuclear_par = nuclear_par + (#reference_lines - 1)
  end

  -- Return minimum of both strategies
  return math.min(hunk_par, nuclear_par)
end

function M.calculate_par(session_or_reference_lines, start_lines)
  -- Handle both old API (just reference_lines) and new API (session object)
  local reference_lines
  local mode = "typing"
  local session = nil

  -- Check if first arg is a session object
  if type(session_or_reference_lines) == "table" and session_or_reference_lines.reference_lines then
    session = session_or_reference_lines
    reference_lines = session.reference_lines
    start_lines = session.start_lines
    mode = session.mode or "typing"
  else
    -- Old API: just reference_lines passed
    reference_lines = session_or_reference_lines
  end

  -- For golf mode, use mini.diff hunks if available
  if mode == "golf" and session and session.practice_buf and session.reference_buf then
    local par = calculate_golf_par_from_hunks(session)

    -- If hunk-based calculation failed or returned nil, use line-level edit distance as fallback
    if par == nil and start_lines and reference_lines then
      par = M.calculate_edit_distance(start_lines, reference_lines)
    end

    -- If we still don't have a par, return 0
    if par == nil then
      par = 0
    end

    -- Apply difficulty multiplier if configured
    if session.config and session.config.difficulty then
      local multipliers = {
        easy = 1.0,
        medium = 0.67,
        hard = 0.5,
        expert = 0.33
      }
      local multiplier = multipliers[session.config.difficulty] or 0.67
      par = math.floor(par * multiplier + 0.5)  -- Round to nearest integer
    end
    return par
  end

  -- Otherwise, use typing mode par (character count from empty)
  return calculate_typing_mode_par(reference_lines)
end

function M.get_keystroke_count(session)
  if session and session.timer_state and session.timer_state.frozen_keystrokes ~= nil then
    return session.timer_state.frozen_keystrokes
  end
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
  local par = session.par or M.calculate_par(session)  -- Use cached par, fallback to calculate

  return {
    correct_chars = correct_chars,
    wpm = wpm,
    keystrokes = keystrokes,
    par = par,
  }
end

return M
