local buffer = require("buffergolf.session.buffer")
local keystroke = require("buffergolf.session.keystroke")
local metrics = require("buffergolf.stats.metrics")
local stats_display = require("buffergolf.timer.stats_display")

local M = {}

local function format_time(seconds)
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function get_elapsed_seconds(session)
  if not session.timer_state or not session.timer_state.start_time then
    return 0
  end
  return math.floor((vim.uv.hrtime() - session.timer_state.start_time) / 1e9)
end

local function get_display_time(session)
  if not session.timer_state.start_time then
    return "--:--"
  end
  local elapsed = get_elapsed_seconds(session)
  if session.timer_state.countdown_mode then
    return format_time(math.max(0, session.timer_state.countdown_duration - elapsed))
  end
  return format_time(elapsed)
end

local function check_completion(session)
  if not buffer.buf_valid(session.practice_buf) or not session.reference_lines then
    return false
  end
  local ok, actual_lines = pcall(vim.api.nvim_buf_get_lines, session.practice_buf, 0, -1, true)
  if not ok or not actual_lines then
    return false
  end

  actual_lines = buffer.strip_trailing_empty_lines(buffer.normalize_lines(actual_lines, session.practice_buf))
  local reference_lines = buffer.strip_trailing_empty_lines(session.reference_lines)

  if #actual_lines ~= #reference_lines then
    return false
  end
  for i = 1, #actual_lines do
    if actual_lines[i] ~= reference_lines[i] then
      return false
    end
  end
  return true
end

local function freeze_stats(session)
  if session.timer_state.frozen_time then
    return
  end
  session.timer_state.frozen_time = get_display_time(session)
  session.timer_state.frozen_wpm = metrics.calculate_wpm(session)
  session.timer_state.frozen_keystrokes = metrics.get_keystroke_count(session)
end

local function complete_session(session, reason)
  if session.timer_state.completed then
    return
  end

  freeze_stats(session)
  session.timer_state.completed = true
  session.timer_state.locked = true
  keystroke.set_tracking_enabled(session, false)

  if buffer.buf_valid(session.practice_buf) then
    -- Exit insert mode if we're in the practice buffer
    if vim.api.nvim_get_current_buf() == session.practice_buf then
      local mode = vim.fn.mode()
      if mode == "i" or mode == "v" or mode == "V" or mode == "\22" then
        pcall(vim.cmd.stopinsert)
      end
    end

    pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = session.practice_buf })
    pcall(vim.api.nvim_set_option_value, "readonly", true, { buf = session.practice_buf })
    pcall(vim.api.nvim_set_option_value, "modified", false, { buf = session.practice_buf })
  end

  local messages = { completed = "Buffergolf completed! 🎉", time_up = "Time's up!" }
  local levels = { completed = vim.log.levels.INFO, time_up = vim.log.levels.WARN }
  if messages[reason] then
    vim.notify(messages[reason], levels[reason], { title = "buffergolf" })
  end
end

local function check_countdown_expired(session)
  if not session.timer_state.countdown_mode or session.timer_state.completed then
    return false
  end
  if get_elapsed_seconds(session) >= session.timer_state.countdown_duration then
    complete_session(session, "time_up")
    return true
  end
  return false
end

function M.update_stats_float(session)
  local ts = session.timer_state
  if
    not ts.stats_buf
    or not buffer.buf_valid(ts.stats_buf)
    or not ts.stats_win
    or not buffer.win_valid(ts.stats_win)
  then
    stats_display.create_stats_window(session)
    if
      not ts.stats_buf
      or not buffer.buf_valid(ts.stats_buf)
      or not ts.stats_win
      or not buffer.win_valid(ts.stats_win)
    then
      return
    end
  end

  if not buffer.win_valid(session.practice_win) then
    return
  end

  check_countdown_expired(session)
  if not ts.completed and check_completion(session) then
    complete_session(session, "completed")
  end

  local time_str = ts.frozen_time or get_display_time(session)
  local wpm = ts.frozen_wpm or metrics.calculate_wpm(session)
  local keystrokes = metrics.get_keystroke_count(session)
  local par = session.par or 0

  stats_display.render_stats(session, time_str, wpm, keystrokes, par)
end

function M.on_first_edit(session)
  if not session.timer_state or session.timer_state.start_time then
    return
  end
  session.timer_state.start_time = vim.uv.hrtime()
  M.update_stats_float(session)
end

function M.start_countdown(session, seconds)
  if not session or not session.timer_state then
    return
  end

  local ts = session.timer_state
  ts.start_time, ts.locked, ts.completed = nil, false, false
  ts.frozen_time, ts.frozen_wpm, ts.frozen_keystrokes = nil, nil, nil

  if seconds and seconds > 0 then
    ts.countdown_mode, ts.countdown_duration = true, seconds
  else
    ts.countdown_mode, ts.countdown_duration = false, nil
  end

  if buffer.buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = session.practice_buf })
    pcall(vim.api.nvim_set_option_value, "readonly", false, { buf = session.practice_buf })
  end

  keystroke.set_tracking_enabled(session, true)
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

  stats_display.create_stats_window(session)

  local timer = vim.uv.new_timer()
  if not timer then
    return
  end
  session.timer_state.update_timer = timer
  timer:start(
    250,
    250,
    vim.schedule_wrap(function()
      if
        not session.timer_state
        or not buffer.win_valid(session.practice_win)
        or not buffer.buf_valid(session.practice_buf)
      then
        if timer then
          timer:stop()
          timer:close()
        end
        return
      end
      M.update_stats_float(session)
    end)
  )

  M.update_stats_float(session)
end

function M.cleanup(session)
  if not session.timer_state then
    return
  end

  if session.timer_state.update_timer and not session.timer_state.update_timer:is_closing() then
    session.timer_state.update_timer:stop()
    session.timer_state.update_timer:close()
  end

  stats_display.close_stats_window(session)
  session.timer_state = nil
end

return M
