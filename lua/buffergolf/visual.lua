local buffer = require("buffergolf.buffer")

local M = {}

local buf_valid = buffer.buf_valid

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

function M.clear_ghost_mark(session, row)
  local mark = session.ghost_marks[row]
  if mark then
    pcall(vim.api.nvim_buf_del_extmark, session.practice_buf, session.ns_ghost, mark)
    session.ghost_marks[row] = nil
  end
end

local function expand_ghost_text(session, actual_text, ghost_text)
  if ghost_text == "" or not ghost_text:find("\t") then
    return ghost_text
  end

  local tabstop = 8
  local ok_ts, ts = pcall(vim.api.nvim_get_option_value, "tabstop", { buf = session.practice_buf })
  if ok_ts and type(ts) == "number" and ts > 0 then
    tabstop = ts
  end

  local display_col = 0
  if actual_text and actual_text ~= "" then
    local ok_width, width = pcall(vim.fn.strdisplaywidth, actual_text)
    if ok_width and type(width) == "number" then
      display_col = width
    else
      display_col = #actual_text
    end
  end

  local pieces = {}
  local chars = {}
  for ch in ghost_text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if ch == "\t" then
      local spaces = tabstop - (display_col % tabstop)
      if spaces <= 0 then
        spaces = tabstop
      end
      table.insert(pieces, string.rep(" ", spaces))
      display_col = display_col + spaces
    else
      table.insert(pieces, ch)
      local ok_char_width, char_width = pcall(vim.fn.strdisplaywidth, ch)
      if ok_char_width and type(char_width) == "number" then
        display_col = display_col + char_width
      else
        display_col = display_col + #ch
      end
    end
  end

  return table.concat(pieces)
end

function M.set_ghost_mark(session, row, col, text, actual)
  local existing_id = session.ghost_marks[row]

  -- If text is empty, clear the mark if it exists
  if text == "" then
    if existing_id then
      M.clear_ghost_mark(session, row)
    end
    return
  end

  -- Prepare the virtual text
  local virt_text = text
  if virt_text:find("\t") then
    virt_text = expand_ghost_text(session, actual or "", virt_text)
  end

  -- Create or update the extmark
  local opts = {
    virt_text = { { virt_text, session.config.ghost_hl } },
    virt_text_pos = "inline",
    hl_mode = "combine",
    priority = session.prio_ghost,
  }

  -- If mark exists, update it in place (avoids flicker)
  if existing_id then
    opts.id = existing_id
  end

  local id = vim.api.nvim_buf_set_extmark(session.practice_buf, session.ns_ghost, row - 1, col, opts)
  session.ghost_marks[row] = id
end

function M.refresh(session)
  if session.refreshing then
    return
  end

  session.refreshing = true

  local ok, err = pcall(function()
    repeat
      if not buf_valid(session.practice_buf) then
        break
      end

      if session.mode == "golf" then
        if session.update_mini_diff then
          session.update_mini_diff()
        end
        break
      end

      ensure_line_count(session)

      local bufnr = session.practice_buf
      local actual_line_count = vim.api.nvim_buf_line_count(bufnr)
      local total = math.max(actual_line_count, #session.reference_lines)

      -- Initialize mismatch tracking if needed
      if not session.mismatch_ranges then
        session.mismatch_ranges = {}
      end

      for row = 1, total do
        local actual_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, true)
        local actual = actual_line[1] or ""

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

        -- Only update mismatch highlighting if it changed
        local prev_range = session.mismatch_ranges[row]
        local range_changed = not prev_range
          or prev_range.start ~= mismatch_start
          or prev_range.finish ~= mismatch_finish

        if range_changed then
          vim.api.nvim_buf_clear_namespace(bufnr, session.ns_mismatch, row - 1, row)

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

          session.mismatch_ranges[row] = { start = mismatch_start, finish = mismatch_finish }
        end

        local ghost_start_index = prefix + 1
        local ghost = ""
        if ghost_start_index <= #reference then
          ghost = reference:sub(ghost_start_index)
        end

        local ghost_col = #actual
        M.set_ghost_mark(session, row, ghost_col, ghost, actual)
      end

      -- Clean up ghost marks and mismatch ranges for rows beyond the current line count
      for row, _ in pairs(session.ghost_marks) do
        if row > total then
          M.clear_ghost_mark(session, row)
        end
      end

      if session.mismatch_ranges then
        for row, _ in pairs(session.mismatch_ranges) do
          if row > total then
            session.mismatch_ranges[row] = nil
          end
        end
      end
    until true

    if buf_valid(session.practice_buf) then
      pcall(vim.api.nvim_set_option_value, "modified", false, { buf = session.practice_buf })
    end
  end)

  session.refreshing = false

  if not ok then
    vim.notify("Buffergolf refresh error: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.attach_change_watcher(session, opts)
  if session.change_attached then
    return
  end
  if not buf_valid(session.practice_buf) then
    return
  end

  opts = opts or {}
  local is_session_active = opts.is_session_active
  local on_first_edit = opts.on_first_edit
  local schedule_refresh = opts.schedule_refresh

  local ok, res = pcall(vim.api.nvim_buf_attach, session.practice_buf, false, {
    on_lines = function(_, buf, _, _, _, _)
      if session.refreshing then
        return
      end
      if not buf_valid(buf) then
        return true
      end
      if is_session_active and not is_session_active(buf, session) then
        return true
      end
      if on_first_edit then
        on_first_edit(session)
      end
      if schedule_refresh then
        schedule_refresh(session)
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
