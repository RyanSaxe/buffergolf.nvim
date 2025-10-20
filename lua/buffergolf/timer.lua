local stats = require("buffergolf.stats")

local M = {}

local function win_valid(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function buf_valid(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
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

local function normalize_lines(lines, bufnr)
  -- Convert tabs to spaces if expandtab is on
  -- This ensures consistent comparison with reference lines
  local ok, expandtab = pcall(vim.api.nvim_get_option_value, "expandtab", { buf = bufnr })
  if not ok or not expandtab then
    return lines
  end

  local ok_ts, tabstop = pcall(vim.api.nvim_get_option_value, "tabstop", { buf = bufnr })
  if not ok_ts then
    tabstop = 8
  end

  local normalized = {}
  for _, line in ipairs(lines) do
    if line:find("\t") then
      local result = {}
      local col = 0
      for char in line:gmatch(".") do
        if char == "\t" then
          local spaces = tabstop - (col % tabstop)
          table.insert(result, string.rep(" ", spaces))
          col = col + spaces
        else
          table.insert(result, char)
          col = col + 1
        end
      end
      table.insert(normalized, table.concat(result))
    else
      table.insert(normalized, line)
    end
  end
  return normalized
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
  actual_lines = normalize_lines(actual_lines, session.practice_buf)

  -- Check if line counts match
  if #actual_lines ~= #session.reference_lines then
    return false
  end

  -- Check if all lines match exactly (after normalization)
  for i = 1, #actual_lines do
    if actual_lines[i] ~= session.reference_lines[i] then
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
end

local function check_countdown_expired(session)
  if not session.timer_state.countdown_mode or session.timer_state.locked then
    return false
  end

  local elapsed = get_elapsed_seconds(session)
  if elapsed >= session.timer_state.countdown_duration then
    session.timer_state.locked = true

    -- Freeze stats before locking
    freeze_stats(session)

    -- Lock the buffer
    if buf_valid(session.practice_buf) then
      pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = session.practice_buf })
    end

    return true
  end

  return false
end

local function setup_highlights()
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
end

local function create_stats_float(session)
  -- Setup highlights
  setup_highlights()

  -- Create buffer for stats display
  local stats_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = stats_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = stats_buf })

  -- Get practice window dimensions
  local win_width = vim.api.nvim_win_get_width(session.practice_win)
  local win_height = vim.api.nvim_win_get_height(session.practice_win)

  -- Calculate position for bottom-right (with padding for border)
  local float_width = 27 -- Width for stats with padding
  local float_height = 1

  -- Create floating window at bottom-right of practice window
  local stats_win = vim.api.nvim_open_win(stats_buf, false, {
    relative = "win",
    win = session.practice_win,
    width = float_width,
    height = float_height,
    row = win_height - float_height - 2,
    col = win_width - float_width - 2,
    anchor = "NW",
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 50,
  })

  -- Apply custom highlights
  vim.api.nvim_set_option_value("winhl", "Normal:BuffergolfStatsFloat,FloatBorder:BuffergolfStatsBorder", { win = stats_win })

  session.timer_state.stats_win = stats_win
  session.timer_state.stats_buf = stats_buf
end

function M.update_stats_float(session)
  if not session.timer_state.stats_buf or not buf_valid(session.timer_state.stats_buf) then
    return
  end

  -- Check for countdown expiration
  check_countdown_expired(session)

  -- Check for completion
  if not session.timer_state.completed and check_completion(session) then
    session.timer_state.completed = true
    freeze_stats(session)
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

  local stats_text
  if session.timer_state.countdown_mode then
    stats_text = string.format("⏱ %s ↓ | WPM: %d", time_str, wpm)
  else
    stats_text = string.format("⏱ %s | WPM: %d", time_str, wpm)
  end

  -- Update buffer text (doesn't cause flickering)
  pcall(vim.api.nvim_buf_set_lines, session.timer_state.stats_buf, 0, -1, false, { stats_text })
end

function M.show_stats_float(session)
  if not session.timer_state.stats_win or not win_valid(session.timer_state.stats_win) then
    return
  end
  pcall(vim.api.nvim_win_set_config, session.timer_state.stats_win, { hide = false })
end

function M.hide_stats_float(session)
  if not session.timer_state.stats_win or not win_valid(session.timer_state.stats_win) then
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
  session.timer_state.countdown_mode = true
  session.timer_state.countdown_duration = seconds
  session.timer_state.locked = false
  session.timer_state.completed = false
  session.timer_state.frozen_time = nil
  session.timer_state.frozen_wpm = nil

  -- Unlock buffer if it was previously locked
  if buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = session.practice_buf })
  end

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
