local buffer = require("buffergolf.session.buffer")

local M = {}

local function ensure_line_count(session)
  local bufnr = session.practice_buf
  if not buffer.buf_valid(bufnr) then
    return
  end
  local needed, current = math.max(#session.reference_lines, 1), vim.api.nvim_buf_line_count(bufnr)
  if current < needed then
    local extra = {}
    for _ = current + 1, needed do
      table.insert(extra, "")
    end
    vim.api.nvim_buf_set_lines(bufnr, current, current, true, extra)
  end
end

function M.clear_ghost_mark(session, row)
  local mark = session.ghost_marks[row]
  if mark then
    pcall(vim.api.nvim_buf_del_extmark, session.practice_buf, session.ns_ghost, mark)
    session.ghost_marks[row] = nil
  end
end

local function expand_tabs(text, actual, bufnr)
  if not text:find("\t") then
    return text
  end
  local ok, tabstop = pcall(vim.api.nvim_get_option_value, "tabstop", { buf = bufnr })
  tabstop = ok and tabstop or 8
  local display_col = actual and vim.fn.strdisplaywidth(actual) or 0
  local pieces = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if ch == "\t" then
      local spaces = tabstop - (display_col % tabstop)
      pieces[#pieces + 1] = string.rep(" ", spaces > 0 and spaces or tabstop)
      display_col = display_col + spaces
    else
      pieces[#pieces + 1] = ch
      display_col = display_col + (vim.fn.strdisplaywidth(ch) or #ch)
    end
  end
  return table.concat(pieces)
end

function M.set_ghost_mark(session, row, col, text, actual)
  if text == "" then
    if session.ghost_marks[row] then
      M.clear_ghost_mark(session, row)
    end
    return
  end

  local virt_text = text:find("\t") and expand_tabs(text, actual or "", session.practice_buf) or text
  local opts = {
    virt_text = { { virt_text, "BuffergolfGhost" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
    priority = session.prio_ghost,
    id = session.ghost_marks[row],
  }
  session.ghost_marks[row] = vim.api.nvim_buf_set_extmark(session.practice_buf, session.ns_ghost, row - 1, col, opts)
end

function M.refresh(session)
  if session.refreshing then
    return
  end
  session.refreshing = true

  local ok = pcall(function()
    if not buffer.buf_valid(session.practice_buf) then
      return
    end

    if session.mode == "golf" then
      if session.update_mini_diff then
        session.update_mini_diff()
      end
      return
    end

    ensure_line_count(session)

    local bufnr = session.practice_buf
    local actual_line_count = vim.api.nvim_buf_line_count(bufnr)
    local total = math.max(actual_line_count, #session.reference_lines)
    session.mismatch_ranges = session.mismatch_ranges or {}

    for row = 1, total do
      local actual = (vim.api.nvim_buf_get_lines(bufnr, row - 1, row, true)[1] or "")
      local reference = session.reference_lines[row] or ""

      local prefix = 0
      for i = 1, math.min(#actual, #reference) do
        if actual:sub(i, i) ~= reference:sub(i, i) then
          break
        end
        prefix = i
      end

      local mismatch_start, mismatch_finish = prefix, #actual
      local prev_range = session.mismatch_ranges[row]
      if not prev_range or prev_range.start ~= mismatch_start or prev_range.finish ~= mismatch_finish then
        vim.api.nvim_buf_clear_namespace(bufnr, session.ns_mismatch, row - 1, row)
        if mismatch_finish > mismatch_start then
          vim.api.nvim_buf_set_extmark(bufnr, session.ns_mismatch, row - 1, mismatch_start, {
            end_col = mismatch_finish,
            hl_group = "BuffergolfMismatch",
          })
        end
        session.mismatch_ranges[row] = { start = mismatch_start, finish = mismatch_finish }
      end

      local ghost = prefix < #reference and reference:sub(prefix + 1) or ""
      M.set_ghost_mark(session, row, #actual, ghost, actual)
    end

    for row in pairs(session.ghost_marks) do
      if row > total then
        M.clear_ghost_mark(session, row)
      end
    end
    if session.mismatch_ranges then
      for row in pairs(session.mismatch_ranges) do
        if row > total then
          session.mismatch_ranges[row] = nil
        end
      end
    end

    pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
  end)

  session.refreshing = false
  if not ok then
    vim.notify("Buffergolf refresh error", vim.log.levels.ERROR)
  end
end

function M.attach_change_watcher(session, opts)
  if session.change_attached or not buffer.buf_valid(session.practice_buf) then
    return
  end
  opts = opts or {}

  local ok, res = pcall(vim.api.nvim_buf_attach, session.practice_buf, false, {
    on_lines = function(_, buf)
      if session.refreshing or not buffer.buf_valid(buf) then
        return
      end
      if opts.is_session_active and not opts.is_session_active(buf, session) then
        return true
      end
      if opts.on_first_edit then
        opts.on_first_edit(session)
      end
      if opts.schedule_refresh then
        opts.schedule_refresh(session)
      end
    end,
    on_detach = function()
      session.change_attached = nil
    end,
  })

  if ok and res then
    session.change_attached = true
  end
end

return M
