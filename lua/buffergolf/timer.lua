local stats = require("buffergolf.stats")
local buffer = require("buffergolf.buffer")
local keystroke = require("buffergolf.keystroke")

local M = {}

local buf_valid = buffer.buf_valid
local win_valid = buffer.win_valid

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function compute_stats_geometry(session)
  if not win_valid(session.practice_win) then
    return nil
  end

  local win_width = vim.api.nvim_win_get_width(session.practice_win)
  local win_height = vim.api.nvim_win_get_height(session.practice_win)

  -- Require a minimally reasonable area for the float
  if win_width < 6 or win_height < 2 then
    return nil
  end

  local stats_config = session.config.stats_float or {}
  local offset_x = math.max(0, stats_config.offset_x or 2)
  local offset_y = math.max(0, stats_config.offset_y or 1)
  local position = stats_config.position or "bottom-right"

  local preferred_width = 23
  local preferred_height = 3
  local min_height = 2

  local width = math.max(6, math.min(preferred_width, win_width))
  local height = math.max(min_height, math.min(preferred_height, win_height))

  local max_col = math.max(0, win_width - width)
  local max_row = math.max(0, win_height - height)

  local row
  local col
  if position == "bottom-left" then
    row = clamp(max_row - offset_y, 0, max_row)
    col = clamp(offset_x, 0, max_col)
  elseif position == "top-right" then
    row = clamp(offset_y, 0, max_row)
    col = clamp(max_col - offset_x, 0, max_col)
  elseif position == "top-left" then
    row = clamp(offset_y, 0, max_row)
    col = clamp(offset_x, 0, max_col)
  else
    row = clamp(max_row - offset_y, 0, max_row)
    col = clamp(max_col - offset_x, 0, max_col)
  end

  local separator_width = 1
  if width < separator_width + 2 then
    separator_width = math.max(1, width - 2)
  end

  local available = width - separator_width
  if available < 2 then
    available = 2
  end

  local left_width = math.floor(available / 2)
  local right_width = available - left_width
  if left_width < 1 then
    left_width = 1
  end
  if right_width < 1 then
    right_width = 1
  end

  return {
    width = width,
    height = height,
    row = row,
    col = col,
    left_width = left_width,
    right_width = right_width,
    separator_width = separator_width,
    has_separator_row = height >= 3,
  }
end

local function truncate_to_width(str, width)
  if width <= 0 then
    return "", 0
  end

  local length = vim.fn.strchars(str)
  local parts = {}
  local consumed = 0
  local idx = 0

  while idx < length and consumed < width do
    local ch = vim.fn.strcharpart(str, idx, 1)
    if ch == "" then
      break
    end
    local ch_width = vim.fn.strdisplaywidth(ch)
    if consumed + ch_width > width then
      break
    end
    table.insert(parts, ch)
    consumed = consumed + ch_width
    idx = idx + 1
  end

  return table.concat(parts), consumed
end

local function pad_center(str, width)
  if width <= 0 then
    return ""
  end

  local fitted, display_width = truncate_to_width(str, width)
  local padding = width - display_width
  local left_pad = math.floor(padding / 2)
  local right_pad = padding - left_pad

  return string.rep(" ", left_pad) .. fitted .. string.rep(" ", right_pad)
end

local function pad_right(str, width)
  local display_width = vim.fn.strdisplaywidth(str)
  if display_width >= width then
    local fitted = truncate_to_width(str, width)
    return fitted
  end
  return str .. string.rep(" ", width - display_width)
end

local function content_column_range(text, offset)
  local length = vim.fn.strchars(text)
  local col = 0
  local start_col = nil
  local end_col = nil

  for i = 0, length - 1 do
    local ch = vim.fn.strcharpart(text, i, 1)
    if ch == "" then
      break
    end
    local width = vim.fn.strdisplaywidth(ch)
    if not start_col and ch:match("%S") then
      start_col = col
    end
    if ch:match("%S") then
      end_col = col + width
    end
    col = col + width
  end

  if not start_col or not end_col then
    return nil, nil
  end

  return offset + start_col, offset + end_col
end

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

  -- Score-based highlights for golf mode
  local score_colors = (config and config.score_colors) or {}

  vim.api.nvim_set_hl(0, "BuffergolfScoreVeryBad", {
    fg = score_colors.very_bad or "#ff0000",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "BuffergolfScoreBad", {
    fg = score_colors.bad or "#ff5555",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "BuffergolfScorePoor", {
    fg = score_colors.poor or "#ffaa00",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "BuffergolfScoreOkay", {
    fg = score_colors.okay or "#88ccff",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "BuffergolfScoreGood", {
    fg = score_colors.good or "#5555ff",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "BuffergolfScoreGreat", {
    fg = score_colors.great or "#00ff00",
    bold = true,
  })
end

local function create_stats_float(session)
  -- Setup highlights
  setup_highlights(session.config)

  local geometry = compute_stats_geometry(session)
  if not geometry then
    session.timer_state.stats_win = nil
    session.timer_state.stats_buf = nil
    session.timer_state.geometry = nil
    return
  end

  -- Create buffer for stats display
  local stats_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = stats_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = stats_buf })

  local stats_win = vim.api.nvim_open_win(stats_buf, false, {
    relative = "win",
    win = session.practice_win,
    width = geometry.width,
    height = geometry.height,
    row = geometry.row,
    col = geometry.col,
    anchor = "NW",
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  })

  if stats_win then
    vim.api.nvim_set_option_value("winhl", "Normal:BuffergolfStatsFloat,FloatBorder:BuffergolfStatsBorder", { win = stats_win })
  end

  session.timer_state.stats_win = stats_win
  session.timer_state.stats_buf = stats_buf
  session.timer_state.geometry = geometry
end

function M.update_stats_float(session)
  if not session.timer_state.stats_buf or not buf_valid(session.timer_state.stats_buf) or
     not session.timer_state.stats_win or not win_valid(session.timer_state.stats_win) then
    create_stats_float(session)
  end

  if not session.timer_state.stats_buf or not buf_valid(session.timer_state.stats_buf) or
     not session.timer_state.stats_win or not win_valid(session.timer_state.stats_win) then
    return
  end

  local geometry = compute_stats_geometry(session)
  if not geometry then
    -- Hide the float if the practice window is too small
    pcall(vim.api.nvim_win_set_config, session.timer_state.stats_win, { hide = true })
    return
  end

  session.timer_state.geometry = geometry

  pcall(vim.api.nvim_win_set_config, session.timer_state.stats_win, {
    relative = "win",
    win = session.practice_win,
    width = geometry.width,
    height = geometry.height,
    row = geometry.row,
    col = geometry.col,
    hide = false,
  })

  local left_width = geometry.left_width
  local right_width = geometry.right_width
  local separator_width = geometry.separator_width
  local separator_left_pad = math.max(0, math.floor((separator_width - 1) / 2))
  local separator_right_pad = math.max(0, separator_width - 1 - separator_left_pad)
  local vertical_separator = string.rep(" ", separator_left_pad) .. "|" .. string.rep(" ", separator_right_pad)

  local stats_buf = session.timer_state.stats_buf
  if not buf_valid(stats_buf) then
    return
  end

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
  local par = session.par or 0  -- Use cached par from session initialization

  -- Format time with icon and countdown indicator
  local time_display
  if session.timer_state.completed then
    time_display = string.format("✓ %s%s", time_str, session.timer_state.countdown_mode and " ↓" or "")
  else
    time_display = string.format("⏱ %s%s", time_str, session.timer_state.countdown_mode and " ↓" or "")
  end

  -- Calculate the bottom-right metric based on mode
  local bottom_right
  local score_hl_group = nil
  if session.mode == "golf" then
    -- Golf mode: Show score percentage
    if par > 0 then
      local score_pct = (1 - keystrokes / par) * 100

      -- Determine highlight group based on score
      if score_pct < -50 then
        score_hl_group = "BuffergolfScoreVeryBad"
      elseif score_pct < -25 then
        score_hl_group = "BuffergolfScoreBad"
      elseif score_pct < 0 then
        score_hl_group = "BuffergolfScorePoor"
      elseif score_pct < 25 then
        score_hl_group = "BuffergolfScoreOkay"
      elseif score_pct < 50 then
        score_hl_group = "BuffergolfScoreGood"
      else
        score_hl_group = "BuffergolfScoreGreat"
      end

      if score_pct > 0 then
        bottom_right = string.format("+%.1f%%", score_pct)
      elseif score_pct < 0 then
        bottom_right = string.format("%.1f%%", score_pct)
      else
        bottom_right = "0.0%"
      end
    else
      bottom_right = "N/A"
    end
  else
    -- Typing mode: Show WPM
    bottom_right = string.format("WPM: %d", wpm)
  end

  -- Format the values for display
  local par_display = string.format("Par: %d", par)
  local keys_display = string.format("Keys: %d", keystrokes)

  -- Pad strings to ensure consistent grid alignment
  time_display = pad_center(time_display, left_width)
  par_display = pad_center(par_display, right_width)
  keys_display = pad_center(keys_display, left_width)
  bottom_right = pad_center(bottom_right, right_width)

  local line_top = pad_right(time_display .. vertical_separator .. par_display, geometry.width)
  local content_lines = { line_top }

  if geometry.has_separator_row then
    local horizontal_left = string.rep("-", left_width + separator_left_pad)
    local horizontal_right = string.rep("-", right_width + separator_right_pad)
    local horizontal_line = pad_right(horizontal_left .. "+" .. horizontal_right, geometry.width)
    table.insert(content_lines, horizontal_line)
  end

  local line_bottom = pad_right(keys_display .. vertical_separator .. bottom_right, geometry.width)
  table.insert(content_lines, line_bottom)

  while #content_lines < geometry.height do
    table.insert(content_lines, string.rep(" ", geometry.width))
  end

  -- Update window highlights based on completion state
  if session.timer_state.stats_win and win_valid(session.timer_state.stats_win) then
    local winhl = session.timer_state.completed
      and "Normal:BuffergolfStatsComplete,FloatBorder:BuffergolfStatsBorderComplete"
      or "Normal:BuffergolfStatsFloat,FloatBorder:BuffergolfStatsBorder"
    pcall(vim.api.nvim_set_option_value, "winhl", winhl, { win = session.timer_state.stats_win })
  end

  -- Update buffer text (doesn't cause flickering)
  pcall(vim.api.nvim_buf_set_lines, session.timer_state.stats_buf, 0, -1, false, content_lines)

  -- Apply score color highlighting for golf mode
  local ns_id = vim.api.nvim_create_namespace("buffergolf_score_color")
  pcall(vim.api.nvim_buf_clear_namespace, session.timer_state.stats_buf, ns_id, 0, -1)

  if session.mode == "golf" and score_hl_group then
    local offset = left_width + separator_width
    local start_col, end_col = content_column_range(bottom_right, offset)
    if start_col and end_col and end_col > start_col then
      local highlight_row = geometry.has_separator_row and 2 or 1
      pcall(vim.api.nvim_buf_add_highlight,
        session.timer_state.stats_buf,
        ns_id,
        score_hl_group,
        highlight_row,
        start_col,
        end_col
      )
    end
  end
end

function M.show_stats_float(session)
  if not session.timer_state or not session.timer_state.stats_win or not win_valid(session.timer_state.stats_win) then
    return
  end

  -- Only show if the current buffer is the practice buffer
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= session.practice_buf then
    return
  end

  pcall(vim.api.nvim_win_set_config, session.timer_state.stats_win, { hide = false })
end

function M.hide_stats_float(session)
  if not session.timer_state or not session.timer_state.stats_win or not win_valid(session.timer_state.stats_win) then
    return
  end
  pcall(vim.api.nvim_win_set_config, session.timer_state.stats_win, { hide = true })
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

  -- Create floating window for stats
  create_stats_float(session)

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
