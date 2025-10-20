local M = {}

local sessions_by_origin = {}
local sessions_by_practice = {}

local function buf_valid(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function get_session(bufnr)
  return sessions_by_origin[bufnr] or sessions_by_practice[bufnr]
end

function M.is_active(bufnr)
  return get_session(bufnr) ~= nil
end

local function ensure_line_count(session)
  local bufnr = session.practice_buf
  if not buf_valid(bufnr) then
    return
  end

  local needed = math.max(#session.reference_lines, 1)
  local current = vim.api.nvim_buf_line_count(bufnr)
  if current >= needed then
    return
  end

  local extra = {}
  for _ = current + 1, needed do
    table.insert(extra, "")
  end
  vim.api.nvim_buf_set_lines(bufnr, current, current, true, extra)
end

local function clear_ghost_mark(session, row)
  local mark = session.ghost_marks[row]
  if mark then
    pcall(vim.api.nvim_buf_del_extmark, session.practice_buf, session.ns_ghost, mark)
    session.ghost_marks[row] = nil
  end
end

local function set_ghost_mark(session, row, col, text)
  clear_ghost_mark(session, row)

  if text == "" then
    return
  end

  local id = vim.api.nvim_buf_set_extmark(session.practice_buf, session.ns_ghost, row - 1, col, {
    virt_text = { { text, session.config.ghost_hl } },
    virt_text_pos = "inline",
    hl_mode = "combine",
    priority = session.prio_ghost,
  })
  session.ghost_marks[row] = id
end

local function refresh_visuals(session)
  if not buf_valid(session.practice_buf) then
    return
  end

  ensure_line_count(session)

  local bufnr = session.practice_buf
  local actual_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local total = math.max(#actual_lines, #session.reference_lines)

  for row = 1, total do
    local actual = actual_lines[row]
    if actual == nil then
      -- Extend buffer so the ghost text can attach to this row.
      vim.api.nvim_buf_set_lines(bufnr, row - 1, row - 1, true, { "" })
      actual = ""
      actual_lines[row] = actual
    end

    local reference = session.reference_lines[row] or ""
    local prefix = 0
    local matching = math.min(#actual, #reference)

    while prefix < matching do
      local from = prefix + 1
      if actual:sub(from, from) ~= reference:sub(from, from) then
        break
      end
      prefix = prefix + 1
    end

    local mismatch_start = prefix
    local mismatch_finish = #actual

    vim.api.nvim_buf_clear_namespace(bufnr, session.ns_mismatch, row - 1, row)
    clear_ghost_mark(session, row)

    if mismatch_finish > mismatch_start then
      vim.api.nvim_buf_add_highlight(
        bufnr,
        session.ns_mismatch,
        session.config.mismatch_hl,
        row - 1,
        mismatch_start,
        mismatch_finish
      )
    end

    local ghost = reference:sub(prefix + 1)
    set_ghost_mark(session, row, prefix, ghost)
  end

  -- Remove stale ghost marks if the buffer shrank.
  if #session.ghost_marks > total then
    for row = total + 1, #session.ghost_marks do
      clear_ghost_mark(session, row)
    end
  end
end

local function disable_diagnostics(bufnr)
  if type(vim.diagnostic) == "table" and vim.diagnostic.disable then
    pcall(vim.diagnostic.disable, bufnr)
  end
end

local function disable_external_ghost(bufnr)
  pcall(vim.api.nvim_buf_set_var, bufnr, "cmp_enabled", false)
  pcall(vim.api.nvim_buf_set_var, bufnr, "cmp_disable", true)
  pcall(vim.api.nvim_buf_set_var, bufnr, "copilot_enabled", false)
  pcall(vim.api.nvim_buf_set_var, bufnr, "avante_virtual_text_disabled", true)
end

local function clear_state(session)
  sessions_by_origin[session.origin_buf] = nil
  sessions_by_practice[session.practice_buf] = nil
  if session.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
  end
end

local function setup_autocmds(session)
  local aug = vim.api.nvim_create_augroup(("BuffergolfSession_%d"):format(session.practice_buf), { clear = true })
  session.augroup = aug

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      refresh_visuals(session)
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      vim.notify("Buffergolf buffers cannot be written.", vim.log.levels.WARN, { title = "buffergolf" })
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      clear_state(session)
    end,
  })
end

function M.start(origin_bufnr, config)
  if sessions_by_origin[origin_bufnr] then
    return
  end

  local reference = vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)
  if #reference == 0 then
    reference = { "" }
  end

  local practice_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = practice_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = practice_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("undofile", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = practice_buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = practice_buf })

  local origin_ft = vim.api.nvim_get_option_value("filetype", { buf = origin_bufnr })
  if origin_ft and origin_ft ~= "" then
    vim.api.nvim_set_option_value("filetype", origin_ft, { buf = practice_buf })
  end

  local empty_lines = {}
  for _ = 1, #reference do
    table.insert(empty_lines, "")
  end
  if #empty_lines == 0 then
    empty_lines = { "" }
  end
  vim.api.nvim_buf_set_lines(practice_buf, 0, -1, true, empty_lines)

  local current_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(current_win, practice_buf)

  local session = {
    origin_buf = origin_bufnr,
    origin_win = current_win,
    practice_buf = practice_buf,
    reference_lines = reference,
    config = config or {},
    ns_ghost = vim.api.nvim_create_namespace("BuffergolfGhostNS"),
    ns_mismatch = vim.api.nvim_create_namespace("BuffergolfMismatchNS"),
    prio_ghost = 200,
    ghost_marks = {},
  }

  sessions_by_origin[origin_bufnr] = session
  sessions_by_practice[practice_buf] = session

  if config.disable_diagnostics ~= false then
    disable_diagnostics(practice_buf)
  end

  if config.disable_external_ghost ~= false then
    disable_external_ghost(practice_buf)
  end

  setup_autocmds(session)
  refresh_visuals(session)
end

function M.stop(bufnr)
  local session = get_session(bufnr)
  if not session then
    return
  end

  local practice_buf = session.practice_buf
  local origin_buf = session.origin_buf

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

return M
