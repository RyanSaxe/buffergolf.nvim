local autocmds = require("buffergolf.session.autocmds")
local buffer = require("buffergolf.session.buffer")
local config = require("buffergolf.config")
local golf_nav = require("buffergolf.golf.navigation")
local golf_window = require("buffergolf.golf.window")
local keystroke = require("buffergolf.session.keystroke")
local storage = require("buffergolf.session.storage")
local timer = require("buffergolf.timer.control")
local visual = require("buffergolf.session.visual")

local M = {}

function M.clear_state(session)
  -- Ensure all cleanup steps run even if one fails
  pcall(timer.cleanup, session)
  pcall(keystroke.cleanup_session, session)
  storage.clear(session)
  if session.change_attached and buffer.buf_valid(session.practice_buf) then
    -- Extra safety: double-check buffer is still valid before detaching
    -- (it might have become invalid between the check and the detach call)
    local ok, is_valid = pcall(vim.api.nvim_buf_is_valid, session.practice_buf)
    if ok and is_valid then
      pcall(vim.api.nvim_buf_detach, session.practice_buf)
    end
  end
  session.change_attached, session.refreshing, session.refresh_scheduled = nil, nil, nil
  if session.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
  end
  if session.mode == "golf" and session.minidiff_enabled then
    local ok, minidiff = pcall(require, "mini.diff")
    if ok then
      for _, buf in ipairs({ session.reference_buf, session.practice_buf }) do
        if buffer.buf_valid(buf) then
          pcall(minidiff.disable, buf)
        end
      end
    end
  end
  if session.prev_winhighlight ~= nil and buffer.win_valid(session.practice_win) then
    pcall(vim.api.nvim_set_option_value, "winhighlight", session.prev_winhighlight, { win = session.practice_win })
    session.prev_winhighlight = nil
  end
  session.on_keystroke = nil
end

local function setup_practice_buffer(practice_buf, origin_buf, origin_ft)
  local opts = {
    bufhidden = "wipe",
    swapfile = false,
    undofile = false,
    modifiable = true,
    buflisted = false,
    buftype = "nofile",
  }
  for opt, val in pairs(opts) do
    vim.api.nvim_set_option_value(opt, val, { buf = practice_buf })
  end
  if origin_ft and origin_ft ~= "" then
    vim.api.nvim_set_option_value("filetype", origin_ft, { buf = practice_buf })
  end
  buffer.copy_indent_options(origin_buf, practice_buf)
  local vars = {
    buffergolf_practice = true,
    copilot_enabled = false,
    copilot_suggestion_auto_trigger = false,
    autopairs_enabled = false,
    minipairs_disable = true,
    buffergolf_active = true,
  }
  for var, val in pairs(vars) do
    pcall(vim.api.nvim_buf_set_var, practice_buf, var, val)
  end
end

local function create_session(origin_buf, practice_buf, reference, config, mode, start_lines)
  return {
    origin_buf = origin_buf,
    origin_win = vim.api.nvim_get_current_win(),
    practice_win = vim.api.nvim_get_current_win(),
    practice_buf = practice_buf,
    reference_lines = reference,
    start_lines = start_lines,
    config = config or {},
    ns_ghost = vim.api.nvim_create_namespace("BuffergolfGhostNS"),
    ns_mismatch = vim.api.nvim_create_namespace("BuffergolfMismatchNS"),
    prio_ghost = 200,
    ghost_marks = {},
    mode = mode,
    on_keystroke = nil,
  }
end

local function init_session_common(session)
  -- Apply mode-specific configuration overrides
  session.config = config.get_mode_config(session.mode, session.config)

  storage.store(session)
  buffer.apply_defaults(session)
  vim.api.nvim_win_set_buf(session.origin_win, session.practice_buf)
  session.practice_win = vim.api.nvim_get_current_win()
  autocmds.setup(session)
  autocmds.setup_change_watcher(session)
  keystroke.init_session(session)
end

function M.start(origin_bufnr, config, target_lines)
  if storage.is_active(origin_bufnr) then
    return
  end

  local reference = target_lines or vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)
  if #reference == 0 then
    reference = { "" }
  end
  reference = buffer.normalize_lines(reference, origin_bufnr)

  local practice_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(practice_buf, buffer.generate_buffer_name(origin_bufnr, ".golf"))
  setup_practice_buffer(practice_buf, origin_bufnr, vim.api.nvim_get_option_value("filetype", { buf = origin_bufnr }))

  local empty_lines = {}
  for _ = 1, math.max(1, #reference) do
    table.insert(empty_lines, "")
  end
  vim.api.nvim_buf_set_lines(practice_buf, 0, -1, true, empty_lines)

  local session = create_session(origin_bufnr, practice_buf, reference, config, "typing", nil)
  init_session_common(session)
  timer.init(session)

  if buffer.win_valid(session.practice_win) then
    vim.api.nvim_set_current_win(session.practice_win)
    vim.api.nvim_win_set_cursor(session.practice_win, { 1, 0 })
  end

  visual.refresh(session)
  vim.defer_fn(function()
    if session and buffer.buf_valid(session.practice_buf) then
      local par = require("buffergolf.stats.par")
      session.par = par.calculate_par(session)
      visual.refresh(session)
    end
  end, 50)
end

function M.start_golf(origin_bufnr, start_lines, target_lines, config)
  if storage.is_active(origin_bufnr) then
    return
  end

  start_lines = start_lines and #start_lines > 0 and start_lines or { "" }
  local reference = target_lines or vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)
  if #reference == 0 then
    reference = { "" }
  end
  reference = buffer.normalize_lines(reference, origin_bufnr)
  start_lines = buffer.normalize_lines(start_lines, origin_bufnr)

  local practice_buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(practice_buf, buffer.generate_buffer_name(origin_bufnr, ".golf"))
  setup_practice_buffer(practice_buf, origin_bufnr, vim.api.nvim_get_option_value("filetype", { buf = origin_bufnr }))
  vim.api.nvim_buf_set_lines(practice_buf, 0, -1, true, start_lines)

  local session = create_session(origin_bufnr, practice_buf, reference, config, "golf", start_lines)
  session.on_keystroke = function()
    if session.mode == "golf" and session.timer_state and not session.timer_state.start_time then
      timer.on_first_edit(session)
    end
  end

  init_session_common(session)
  timer.init(session)
  golf_window.create_reference_window(session)
  golf_window.setup_mini_diff(session)
  golf_nav.setup(session)

  visual.refresh(session)
  vim.defer_fn(function()
    if session and buffer.buf_valid(session.practice_buf) then
      local par = require("buffergolf.stats.par")
      session.par = par.calculate_par(session)
      visual.refresh(session)
    end
  end, 150)
end

function M.stop(bufnr)
  local session = storage.get(bufnr)
  if not session then
    return
  end

  if session.reference_win and buffer.win_valid(session.reference_win) then
    pcall(vim.api.nvim_win_close, session.reference_win, true)
  end
  if session.reference_buf and buffer.buf_valid(session.reference_buf) then
    pcall(vim.api.nvim_buf_delete, session.reference_buf, { force = true })
  end

  if buffer.win_valid(session.origin_win) and buffer.buf_valid(session.origin_buf) then
    pcall(vim.api.nvim_set_current_win, session.origin_win)
    pcall(vim.api.nvim_win_set_buf, session.origin_win, session.origin_buf)
  elseif buffer.buf_valid(session.origin_buf) then
    pcall(vim.api.nvim_set_current_buf, session.origin_buf)
  end

  if buffer.buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_buf_delete, session.practice_buf, { force = true })
  end

  M.clear_state(session)
end

function M.reset_to_start(bufnr)
  local session = storage.get(bufnr)
  if not session then
    vim.notify("No active buffergolf session", vim.log.levels.WARN, { title = "buffergolf" })
    return false
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = session.practice_buf })
  vim.api.nvim_set_option_value("readonly", false, { buf = session.practice_buf })

  if session.mode == "typing" then
    local empty_lines = {}
    for _ = 1, math.max(1, #session.reference_lines) do
      table.insert(empty_lines, "")
    end
    vim.api.nvim_buf_set_lines(session.practice_buf, 0, -1, true, empty_lines)
  elseif session.mode == "golf" and session.start_lines then
    vim.api.nvim_buf_set_lines(session.practice_buf, 0, -1, true, session.start_lines)
  end

  if buffer.win_valid(session.practice_win) then
    pcall(vim.api.nvim_win_set_cursor, session.practice_win, { 1, 0 })
  end

  keystroke.reset_count(session)
  keystroke.set_tracking_enabled(session, true)

  if session.ghost_marks then
    for row, _ in pairs(session.ghost_marks) do
      visual.clear_ghost_mark(session, row)
    end
    session.ghost_marks = {}
  end

  if session.ns_mismatch then
    pcall(vim.api.nvim_buf_clear_namespace, session.practice_buf, session.ns_mismatch, 0, -1)
  end

  if buffer.buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = session.practice_buf })
    pcall(vim.api.nvim_set_option_value, "readonly", false, { buf = session.practice_buf })
  end

  if session.timer_state then
    local ts = session.timer_state
    ts.locked, ts.completed = false, false
    ts.frozen_time, ts.frozen_wpm, ts.frozen_keystrokes = nil, nil, nil
  end

  visual.refresh(session)
  return true
end

return M
