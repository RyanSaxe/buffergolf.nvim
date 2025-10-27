local M = {}

local function trim(str)
  return str:match("^%s*(.-)%s*$") or ""
end

local function levenshtein(s1, s2, is_char)
  local m, n = is_char and #s1 or #s1, is_char and #s2 or #s2
  local dp = {}
  for i = 0, m do
    dp[i] = { [0] = i }
  end
  for j = 0, n do
    dp[0][j] = j
  end
  for i = 1, m do
    for j = 1, n do
      local v1 = is_char and s1:byte(i) or trim(s1[i])
      local v2 = is_char and s2:byte(j) or trim(s2[j])
      dp[i][j] = math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + (v1 == v2 and 0 or 1))
    end
  end
  return dp[m][n]
end

M.calculate_edit_distance = function(lines1, lines2)
  return levenshtein(lines1 or {}, lines2 or {}, false)
end

local function typing_mode_par(reference_lines)
  if not reference_lines or #reference_lines == 0 then
    return 0
  end
  local par = 1 -- Enter insert mode
  for _, line in ipairs(reference_lines) do
    par = par + #trim(line)
  end
  return par + math.max(0, #reference_lines - 1) -- Add newlines
end

local function golf_par_from_hunks(session)
  local practice_lines, reference_lines = session.start_lines, session.reference_lines
  if not practice_lines or not reference_lines then
    return nil
  end

  local ok, minidiff = pcall(require, "mini.diff")
  if not ok then
    return nil
  end

  local buf_data = minidiff.get_buf_data(session.reference_buf)
  if not buf_data or not buf_data.hunks or #buf_data.hunks == 0 then
    return 0
  end

  local hunk_par = 0
  for _, hunk in ipairs(buf_data.hunks) do
    if hunk.type == "delete" then
      hunk_par = hunk_par + ((hunk.ref_count or 0) * 2)
    elseif hunk.type == "add" then
      for i = 1, (hunk.buf_count or 0) do
        local line = reference_lines[(hunk.buf_start or 1) + i - 1]
        hunk_par = hunk_par + 1 + (line and #trim(line) or 0)
      end
    elseif hunk.type == "change" then
      local change_par = 0
      for i = 1, math.max(hunk.buf_count or 0, hunk.ref_count or 0) do
        local start_line = practice_lines[(hunk.ref_start or 1) + i - 1]
        local goal_line = reference_lines[(hunk.buf_start or 1) + i - 1]
        if start_line and goal_line then
          local s_trim, g_trim = trim(start_line), trim(goal_line)
          change_par = change_par + math.min(levenshtein(s_trim, g_trim, true), 2 + #g_trim)
        elseif goal_line then
          change_par = change_par + 1 + #trim(goal_line)
        elseif start_line then
          change_par = change_par + 2
        end
      end
      hunk_par = hunk_par + change_par
    end
  end

  -- Nuclear option: ggdG + rewrite
  local nuclear_par = 5 -- ggdG + i
  for _, line in ipairs(reference_lines) do
    nuclear_par = nuclear_par + #trim(line)
  end
  nuclear_par = nuclear_par + math.max(0, #reference_lines - 1)

  return math.min(hunk_par, nuclear_par)
end

function M.calculate_par(session_or_ref, start_lines)
  local session = type(session_or_ref) == "table" and session_or_ref.reference_lines and session_or_ref
  local reference_lines = session and session.reference_lines or session_or_ref
  local mode = session and session.mode or "typing"

  if mode == "golf" and session and session.practice_buf and session.reference_buf then
    local par = golf_par_from_hunks(session)
    if not par and start_lines and reference_lines then
      par = M.calculate_edit_distance(start_lines, reference_lines)
    end
    par = par or 0

    if session.config and session.config.difficulty then
      local mult = ({ easy = 1.0, medium = 0.67, hard = 0.5, expert = 0.33 })[session.config.difficulty] or 0.67
      par = math.floor(par * mult + 0.5)
    end
    return par
  end

  return typing_mode_par(reference_lines)
end

return M
