local timer = require("buffergolf.timer")
local keystroke = require("buffergolf.keystroke")
local buffer = require("buffergolf.buffer")
local visual = require("buffergolf.visual")
local golf = require("buffergolf.golf")

local M = {}

local buf_valid = buffer.buf_valid
local win_valid = buffer.win_valid

local sessions_by_origin = {}
local sessions_by_practice = {}

local function get_session(bufnr)
  return sessions_by_origin[bufnr] or sessions_by_practice[bufnr]
end

function M.is_active(bufnr)
  return get_session(bufnr) ~= nil
end

local function schedule_refresh(session)
  if session.refresh_scheduled then
    return
  end

  session.refresh_scheduled = true

  vim.schedule(function()
    session.refresh_scheduled = nil

    if not session or not session.practice_buf then
      return
    end

    -- Ensure session is still active for this practice buffer
    if sessions_by_practice[session.practice_buf] ~= session then
      return
    end

    if not buf_valid(session.practice_buf) then
      return
    end

    if session.timer_state and (session.timer_state.locked or session.timer_state.completed) then
      return
    end

    visual.refresh(session)
  end)
end

local function clear_state(session)
  timer.cleanup(session)
  keystroke.cleanup_session(session)
  sessions_by_origin[session.origin_buf] = nil
  sessions_by_practice[session.practice_buf] = nil
  if session.change_attached and buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_buf_detach, session.practice_buf)
  end
  session.change_attached = nil
  session.refreshing = nil
  session.refresh_scheduled = nil
  if session.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
  end
  -- Clean up mini.diff if it was enabled
  if session.mode == "golf" and session.minidiff_enabled then
    local ok, minidiff = pcall(require, 'mini.diff')
    if ok then
      if session.reference_buf and buf_valid(session.reference_buf) then
        pcall(minidiff.disable, session.reference_buf)
      end
      if session.practice_buf and buf_valid(session.practice_buf) then
        pcall(minidiff.disable, session.practice_buf)
      end
    end
  end
  if session.prev_winhighlight ~= nil then
    if win_valid(session.practice_win) then
      pcall(vim.api.nvim_set_option_value, "winhighlight", session.prev_winhighlight, { win = session.practice_win })
    end
    session.prev_winhighlight = nil
  end
  session.on_keystroke = nil
end

local function setup_autocmds(session)
  local aug = vim.api.nvim_create_augroup(("BuffergolfSession_%d"):format(session.practice_buf), { clear = true })
  session.augroup = aug

  vim.api.nvim_create_autocmd("BufEnter", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      buffer.apply_defaults(session)
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      vim.notify("Buffergolf buffers cannot be written.", vim.log.levels.WARN, { title = "buffergolf" })
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      buffer.apply_defaults(session)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufHidden" }, {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      if buf_valid(session.practice_buf) then
        pcall(vim.api.nvim_set_option_value, "modified", false, { buf = session.practice_buf })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      -- Only clear state if buffer is actually being destroyed
      -- This prevents spurious events (e.g., from blink.cmp) from breaking the session
      if not vim.api.nvim_buf_is_valid(session.practice_buf) then
        clear_state(session)
      end
    end,
  })
end

function M.start(origin_bufnr, config, target_lines)
  if sessions_by_origin[origin_bufnr] then
    return
  end

  local reference = target_lines or vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)
  if #reference == 0 then
    reference = { "" }
  end

  -- Normalize tabs to spaces if expandtab is on
  reference = buffer.normalize_lines(reference, origin_bufnr)

  local practice_buf = vim.api.nvim_create_buf(false, false)

  -- Set buffer name for better UX in statuslines and buffer lists
  local practice_name = buffer.generate_buffer_name(origin_bufnr, ".golf")
  vim.api.nvim_buf_set_name(practice_buf, practice_name)

  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = practice_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("undofile", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = practice_buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("buftype", "", { buf = practice_buf })

  local origin_ft = vim.api.nvim_get_option_value("filetype", { buf = origin_bufnr })
  if origin_ft and origin_ft ~= "" then
    vim.api.nvim_set_option_value("filetype", origin_ft, { buf = practice_buf })
  end

  buffer.copy_indent_options(origin_bufnr, practice_buf)

  local empty_lines = {}
  for _ = 1, #reference do
    table.insert(empty_lines, "")
  end
  if #empty_lines == 0 then
    empty_lines = { "" }
  end
  vim.api.nvim_buf_set_lines(practice_buf, 0, -1, true, empty_lines)

  local current_win = vim.api.nvim_get_current_win()
  pcall(vim.api.nvim_buf_set_var, practice_buf, "buffergolf_practice", true)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "copilot_enabled", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "copilot_suggestion_auto_trigger", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "autopairs_enabled", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "minipairs_disable", true)

  -- Add buffer marker for user statusline customization
  pcall(vim.api.nvim_buf_set_var, practice_buf, "buffergolf_active", true)

  local session = {
    origin_buf = origin_bufnr,
    origin_win = current_win,
    practice_win = current_win,
    practice_buf = practice_buf,
    reference_lines = reference,
    config = config or {},
    ns_ghost = vim.api.nvim_create_namespace("BuffergolfGhostNS"),
    ns_mismatch = vim.api.nvim_create_namespace("BuffergolfMismatchNS"),
    prio_ghost = 200,
    ghost_marks = {},
    mode = "typing", -- Typing practice mode (empty start)
    on_keystroke = nil,
  }

  sessions_by_origin[origin_bufnr] = session
  sessions_by_practice[practice_buf] = session

  buffer.apply_defaults(session)

  vim.api.nvim_win_set_buf(current_win, practice_buf)
  session.practice_win = vim.api.nvim_get_current_win()

  buffer.disable_matchparen(session)

  setup_autocmds(session)
  visual.attach_change_watcher(session, {
    is_session_active = function(buf, target)
      return sessions_by_practice[buf] == target
    end,
    on_first_edit = timer.on_first_edit,
    schedule_refresh = schedule_refresh,
  })

  -- Set up keystroke tracking using the robust keystroke module
  keystroke.init_session(session)

  timer.init(session)

  -- Ensure cursor starts at the beginning of practice buffer
  if win_valid(session.practice_win) then
    vim.api.nvim_set_current_win(session.practice_win)
    vim.api.nvim_win_set_cursor(session.practice_win, {1, 0})
  end

  visual.refresh(session)

  -- Calculate par for typing mode
  vim.defer_fn(function()
    if not session or not buf_valid(session.practice_buf) then
      return
    end
    local stats = require("buffergolf.stats")
    session.par = stats.calculate_par(session)
    -- Trigger a visual refresh to update the display with the calculated par
    visual.refresh(session)
  end, 50)
end

function M.start_golf(origin_bufnr, start_lines, target_lines, config)
  if sessions_by_origin[origin_bufnr] then
    return
  end

  if not start_lines or #start_lines == 0 then
    start_lines = { "" }
  end

  local reference = target_lines or vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)
  if #reference == 0 then
    reference = { "" }
  end

  -- Normalize tabs to spaces if expandtab is on
  reference = buffer.normalize_lines(reference, origin_bufnr)
  start_lines = buffer.normalize_lines(start_lines, origin_bufnr)

  local practice_buf = vim.api.nvim_create_buf(false, false)

  -- Set buffer name for better UX in statuslines and buffer lists
  local practice_name = buffer.generate_buffer_name(origin_bufnr, ".golf")
  vim.api.nvim_buf_set_name(practice_buf, practice_name)

  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = practice_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("undofile", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = practice_buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("buftype", "", { buf = practice_buf })

  local origin_ft = vim.api.nvim_get_option_value("filetype", { buf = origin_bufnr })
  if origin_ft and origin_ft ~= "" then
    vim.api.nvim_set_option_value("filetype", origin_ft, { buf = practice_buf })
  end

  buffer.copy_indent_options(origin_bufnr, practice_buf)

  -- Set the starting lines (not empty for golf mode)
  vim.api.nvim_buf_set_lines(practice_buf, 0, -1, true, start_lines)

  local current_win = vim.api.nvim_get_current_win()
  pcall(vim.api.nvim_buf_set_var, practice_buf, "buffergolf_practice", true)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "copilot_enabled", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "copilot_suggestion_auto_trigger", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "autopairs_enabled", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "minipairs_disable", true)

  -- Add buffer marker for user statusline customization
  pcall(vim.api.nvim_buf_set_var, practice_buf, "buffergolf_active", true)

  local session = {
    origin_buf = origin_bufnr,
    origin_win = current_win,
    practice_win = current_win,
    practice_buf = practice_buf,
    reference_lines = reference,
    start_lines = start_lines, -- Store starting lines for par calculation
    config = config or {},
    ns_ghost = vim.api.nvim_create_namespace("BuffergolfGhostNS"),
    ns_mismatch = vim.api.nvim_create_namespace("BuffergolfMismatchNS"),
    prio_ghost = 200,
    ghost_marks = {},
    mode = "golf", -- Golf mode (non-empty start)
    on_keystroke = nil,
  }

  sessions_by_origin[origin_bufnr] = session
  sessions_by_practice[practice_buf] = session

  buffer.apply_defaults(session)

  vim.api.nvim_win_set_buf(current_win, practice_buf)
  session.practice_win = vim.api.nvim_get_current_win()

  buffer.disable_matchparen(session)

  setup_autocmds(session)
  visual.attach_change_watcher(session, {
    is_session_active = function(buf, target)
      return sessions_by_practice[buf] == target
    end,
    on_first_edit = timer.on_first_edit,
    schedule_refresh = schedule_refresh,
  })

  session.on_keystroke = function()
    if session.mode == "golf" and session.timer_state and not session.timer_state.start_time then
      timer.on_first_edit(session)
    end
  end

  -- Set up keystroke tracking
  keystroke.init_session(session)

  -- Create timer/stats window first (horizontal split spanning full width)
  timer.init(session)

  -- Then create reference window (vertical split in the bottom area)
  golf.create_reference_window(session)
  golf.setup_mini_diff(session)
  golf.setup_navigation(session)  -- Add navigation commands and keymaps

  visual.refresh(session)

  -- Calculate par once after mini.diff has had time to process hunks
  vim.defer_fn(function()
    if not session or not buf_valid(session.practice_buf) then
      return
    end
    local stats = require("buffergolf.stats")
    session.par = stats.calculate_par(session)
    -- Trigger a visual refresh to update the display with the calculated par
    visual.refresh(session)
  end, 150)  -- Slightly longer delay than overlay toggle to ensure hunks are ready
end

function M.stop(bufnr)
  local session = get_session(bufnr)
  if not session then
    return
  end

  local practice_buf = session.practice_buf
  local origin_buf = session.origin_buf

  -- Close reference window if it exists (golf mode)
  if session.reference_win and win_valid(session.reference_win) then
    pcall(vim.api.nvim_win_close, session.reference_win, true)
  end

  -- Delete reference buffer if it exists
  if session.reference_buf and buf_valid(session.reference_buf) then
    pcall(vim.api.nvim_buf_delete, session.reference_buf, { force = true })
  end

  if win_valid(session.origin_win) and buf_valid(origin_buf) then
    vim.api.nvim_set_current_win(session.origin_win)
    vim.api.nvim_win_set_buf(session.origin_win, origin_buf)
  elseif buf_valid(origin_buf) then
    vim.api.nvim_set_current_buf(origin_buf)
  end

  if buf_valid(practice_buf) then
    vim.api.nvim_buf_delete(practice_buf, { force = true })
  end

  clear_state(session)
end

function M.reset_to_start(bufnr)
  local session = get_session(bufnr)
  if not session then
    vim.notify("No active buffergolf session", vim.log.levels.WARN, { title = "buffergolf" })
    return false
  end

  -- Ensure buffer is modifiable before resetting
  vim.api.nvim_set_option_value("modifiable", true, { buf = session.practice_buf })
  vim.api.nvim_set_option_value("readonly", false, { buf = session.practice_buf })

  -- Reset buffer content based on mode
  if session.mode == "typing" then
    -- Typing mode starts with empty lines
    local empty_lines = {}
    for _ = 1, #session.reference_lines do
      table.insert(empty_lines, "")
    end
    if #empty_lines == 0 then
      empty_lines = { "" }
    end
    vim.api.nvim_buf_set_lines(session.practice_buf, 0, -1, true, empty_lines)
  elseif session.mode == "golf" and session.start_lines then
    -- Golf mode starts with pre-filled lines
    vim.api.nvim_buf_set_lines(session.practice_buf, 0, -1, true, session.start_lines)
  end

  -- Reset cursor to start
  if win_valid(session.practice_win) then
    pcall(vim.api.nvim_win_set_cursor, session.practice_win, {1, 0})
  end

  -- Reset keystroke count
  keystroke.reset_count(session)
  keystroke.set_tracking_enabled(session, true)

  -- Clear all ghost marks and mismatches
  if session.ghost_marks then
    for row, _ in pairs(session.ghost_marks) do
      visual.clear_ghost_mark(session, row)
    end
    session.ghost_marks = {}
  end

  -- Clear mismatch highlights
  if session.ns_mismatch then
    pcall(vim.api.nvim_buf_clear_namespace, session.practice_buf, session.ns_mismatch, 0, -1)
  end

  -- Unlock buffer in case it was locked
  if buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = session.practice_buf })
    pcall(vim.api.nvim_set_option_value, "readonly", false, { buf = session.practice_buf })
  end

  if session.timer_state then
    session.timer_state.locked = false
    session.timer_state.completed = false
    session.timer_state.frozen_time = nil
    session.timer_state.frozen_wpm = nil
    session.timer_state.frozen_keystrokes = nil
  end

  -- Refresh visuals to recreate ghost text and highlights
  visual.refresh(session)

  return true
end

function M.start_countdown(bufnr, seconds)
  local session = get_session(bufnr)
  if not session then
    vim.notify("No active buffergolf session", vim.log.levels.WARN, { title = "buffergolf" })
    return false
  end

  timer.start_countdown(session, seconds)
  return true
end

-- Public API to get session for a buffer
function M.get(bufnr)
  return get_session(bufnr)
end

return M
