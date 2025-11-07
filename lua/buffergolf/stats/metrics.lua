local keystroke = require("buffergolf.session.keystroke")

local M = {}

local metrics_cache = {}

local function trim(str)
  return str:match("^%s*(.-)%s*$") or ""
end

local function cache_key(session, metric_type)
  if not session or not session.practice_buf then
    return nil
  end
  return string.format("%d_%s", session.practice_buf, metric_type)
end

local function get_cached_metric(session, metric_type)
  local key = cache_key(session, metric_type)
  if not key then
    return nil
  end
  local cached = metrics_cache[key]
  if cached and (os.time() - cached.timestamp) < 1 then
    return cached.value
  end
  return nil
end

local function set_cached_metric(session, metric_type, value)
  local key = cache_key(session, metric_type)
  if not key then
    return
  end
  metrics_cache[key] = {
    value = value,
    timestamp = os.time(),
  }
end

function M.clear_cache(session)
  if not session or not session.practice_buf then
    return
  end
  for key in pairs(metrics_cache) do
    if key:match("^" .. session.practice_buf .. "_") then
      metrics_cache[key] = nil
    end
  end
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
  if not session or not session.timer_state or not session.timer_state.start_time then
    return 0
  end

  local elapsed_seconds = (vim.uv.hrtime() - session.timer_state.start_time) / 1e9
  if elapsed_seconds < 0.1 then
    return 0
  end

  local correct_chars = M.count_correct_characters(session)
  return math.floor((correct_chars / 5) / (elapsed_seconds / 60) + 0.5)
end

function M.calculate_accuracy(session)
  if not session or not session.practice_buf or not session.reference_lines then
    return 0
  end

  local total_chars = 0
  for _, line in ipairs(session.reference_lines) do
    total_chars = total_chars + #trim(line)
  end

  if total_chars == 0 then
    return 100
  end

  local correct_chars = M.count_correct_characters(session)
  return math.floor((correct_chars / total_chars) * 100)
end

function M.get_session_duration(session)
  if not session or not session.timer_state then
    return 0
  end

  if session.timer_state.frozen_time then
    return session.timer_state.frozen_time
  end

  if not session.timer_state.start_time then
    return 0
  end

  return (vim.uv.hrtime() - session.timer_state.start_time) / 1e9
end

return M
