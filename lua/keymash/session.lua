local M = {}

-- Internal state per origin buffer
local sessions_by_origin = {}
local sessions_by_practice = {}

local function buf_valid(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function get_session_from_buf(bufnr)
  if sessions_by_origin[bufnr] then
    return sessions_by_origin[bufnr]
  end
  return sessions_by_practice[bufnr]
end

function M.is_active(bufnr)
  return get_session_from_buf(bufnr) ~= nil
end

local function clear_state(origin, practice)
  if origin then
    sessions_by_origin[origin] = nil
  end
  if practice then
    sessions_by_practice[practice] = nil
  end
end

local function render_dim_line(session, row0)
  local bufnr, ns_dim = session.practice_buf, session.ns_dim
  local cfg = session.config
  local line = vim.api.nvim_buf_get_lines(bufnr, row0, row0 + 1, true)[1] or ""
  local len = #line
  -- Clear dim highlights on this line
  vim.api.nvim_buf_clear_namespace(bufnr, ns_dim, row0, row0 + 1)
  if len == 0 then
    return
  end
  -- Build spans of columns that should remain dimmed (everything except typed-correct)
  local row_typed = (session.typed and session.typed[row0]) or {}
  local in_span = false
  local span_start = 0
  for col = 0, len - 1 do
    local entry = row_typed[col]
    local is_correct = entry and entry.status == 'correct'
    if not is_correct and not in_span then
      in_span = true
      span_start = col
    elseif is_correct and in_span then
      -- close span at col
      vim.api.nvim_buf_add_highlight(bufnr, ns_dim, cfg.dim_hl, row0, span_start, col)
      in_span = false
    end
  end
  if in_span then
    vim.api.nvim_buf_add_highlight(bufnr, ns_dim, cfg.dim_hl, row0, span_start, len)
  end
end

local function dim_buffer(session)
  local bufnr = session.practice_buf
  local lines = vim.api.nvim_buf_line_count(bufnr)
  -- Clear all then re-add per line based on current typed state
  vim.api.nvim_buf_clear_namespace(bufnr, session.ns_dim, 0, -1)
  for row0 = 0, lines - 1 do
    render_dim_line(session, row0)
  end
end

-- Typed state: map[row0][col0] = { id = extmark_id, status = 'correct'|'error' }
local function ensure_typed_row(session, row0)
  session.typed = session.typed or {}
  session.typed[row0] = session.typed[row0] or {}
  return session.typed[row0]
end

local function get_cursor(win)
  local r, c = unpack(vim.api.nvim_win_get_cursor(win))
  return r, c
end

local function set_cursor(win, row1, col0)
  vim.api.nvim_win_set_cursor(win, { row1, col0 })
end

local function line_len(lines, row1)
  local s = lines[row1] or ""
  return #s
end

local function expected_at(session, row1, col0)
  -- Returns expected char at given position, and a tag: 'char'|'nl'|'eof'
  local lines = session.expected_lines
  if row1 > #lines then
    return nil, 'eof'
  end
  local line = lines[row1]
  local len = #line
  if col0 < len then
    local ch = line:sub(col0 + 1, col0 + 1)
    return ch, 'char'
  elseif row1 < #lines then
    return "\n", 'nl'
  else
    return nil, 'eof'
  end
end

local function mark_char(session, row0, col0, status)
  -- Skip newline visualization
  local len = #session.expected_lines[row0 + 1]
  if col0 >= len then
    return
  end
  local row = ensure_typed_row(session, row0)
  if status == 'correct' then
    -- Don't overlay; just record and re-render dim to reveal syntax
    row[col0] = { id = nil, status = 'correct' }
    render_dim_line(session, row0)
    return
  end
  -- error overlay in red replaces dim
  local id = vim.api.nvim_buf_set_extmark(session.practice_buf, session.ns_marks, row0, col0, {
    end_row = row0,
    end_col = col0 + 1,
    hl_group = session.config.error_hl,
    hl_mode = 'replace',
    priority = session.prio_typed,
  })
  row[col0] = { id = id, status = 'error' }
end

local function clear_char(session, row0, col0)
  local row = ensure_typed_row(session, row0)
  local entry = row[col0]
  if entry and entry.id then
    pcall(vim.api.nvim_buf_del_extmark, session.practice_buf, session.ns_marks, entry.id)
  end
  row[col0] = nil
  -- Re-render dim for this line to cover this char again
  render_dim_line(session, row0)
end

local function advance_cursor(session, row1, col0)
  local lines = session.expected_lines
  local len = line_len(lines, row1)
  if col0 < len then
    return row1, col0 + 1
  elseif row1 < #lines then
    return row1 + 1, 0
  else
    return row1, col0 -- at EOF, stay
  end
end

local function retreat_cursor(session, row1, col0)
  if col0 > 0 then
    return row1, col0 - 1
  elseif row1 > 1 then
    local prev_len = line_len(session.expected_lines, row1 - 1)
    return row1 - 1, prev_len
  else
    return row1, col0
  end
end

local function setup_autocmds(session)
  local aug = vim.api.nvim_create_augroup("KeymashSession_" .. session.practice_buf, { clear = true })
  local buf = session.practice_buf

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = aug,
    buffer = buf,
    callback = function()
      if buf_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, session.ns_dim, 0, -1)
        vim.api.nvim_buf_clear_namespace(buf, session.ns_marks, 0, -1)
      end
      clear_state(session.origin_buf, session.practice_buf)
    end,
  })

  -- Intercept typed characters to write over existing text
  vim.api.nvim_create_autocmd({ "InsertCharPre" }, {
    group = aug,
    buffer = buf,
    callback = function()
      local win = session.practice_win
      local row1, col0 = get_cursor(win)
      local expected, tag = expected_at(session, row1, col0)
      local typed = vim.v.char
      if typed == "\r" then typed = "\n" end
      -- Cancel actual insertion; we manage cursor + highlights ourselves
      vim.v.char = ""

      if tag == 'eof' then
        return
      end

      if tag == 'nl' then
        if typed == "\n" then
          local nr, _ = advance_cursor(session, row1, col0)
          set_cursor(win, nr, 0)
        end
        return
      end

      local ok = (typed == expected)
      if not ok and expected == "\t" and session.config.auto_tab ~= false then
        if typed == "\t" or typed == " " then
          ok = true
        end
      end

      mark_char(session, row1 - 1, col0, ok and 'correct' or 'error')
      local nr, nc = advance_cursor(session, row1, col0)
      set_cursor(win, nr, nc)
    end,
  })

  -- Also map <CR> to prevent real newline insertion in edge cases
  local function handle_cr()
    local win = session.practice_win
    local row1, col0 = get_cursor(win)
    local _, tag = expected_at(session, row1, col0)
    if tag == 'nl' then
      local nr, _ = advance_cursor(session, row1, col0)
      set_cursor(win, nr, 0)
    end
  end
  vim.keymap.set('i', '<CR>', function()
    handle_cr()
    return ''
  end, { buffer = buf, nowait = true, silent = true, expr = true })

  -- Backspace: move left and clear mark at the previous position
  vim.keymap.set('i', '<BS>', function()
    local win = session.practice_win
    local row1, col0 = get_cursor(win)
    local pr, pc = retreat_cursor(session, row1, col0)
    clear_char(session, pr - 1, pc)
    set_cursor(win, pr, pc)
  end, { buffer = buf, nowait = true, silent = true })
end

function M.start(origin_bufnr, config)
  if sessions_by_origin[origin_bufnr] then
    return
  end

  -- Snapshot expected text from origin buffer
  local expected_lines = vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)

  -- Create practice buffer
  local practice_buf = vim.api.nvim_create_buf(false, true) -- unlisted scratch
  vim.api.nvim_buf_set_name(practice_buf, "keymash://practice")
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = practice_buf })
  -- Inherit original filetype to preserve syntax colors
  local origin_ft = vim.api.nvim_get_option_value("filetype", { buf = origin_bufnr })
  vim.api.nvim_set_option_value("filetype", origin_ft ~= '' and origin_ft or 'keymash', { buf = practice_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = practice_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = practice_buf })
  -- no special listed/modified handling for scratch; let defaults apply

  -- Put expected text into practice buffer
  vim.api.nvim_buf_set_lines(practice_buf, 0, -1, true, expected_lines)

  -- Open a dimmed backdrop and a centered floating window for practice
  local cols = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight

  -- Backdrop
  local back_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = back_buf })
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = back_buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = back_buf })
  local filler = {}
  for _ = 1, lines do table.insert(filler, '') end
  vim.api.nvim_buf_set_lines(back_buf, 0, -1, true, filler)
  local back_win = vim.api.nvim_open_win(back_buf, false, {
    relative = 'editor', width = cols, height = lines, row = 0, col = 0,
    style = 'minimal', zindex = 50, focusable = false,
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:KeymashBackdrop', { win = back_win })
  vim.api.nvim_set_option_value('winblend', 40, { win = back_win })

  -- Practice float
  local width = math.max(20, math.floor(cols * 0.85))
  local height = math.max(5, math.floor(lines * 0.85))
  local row = math.floor((lines - height) / 2)
  local col = math.floor((cols - width) / 2)
  local win = vim.api.nvim_open_win(practice_buf, true, {
    relative = 'editor', width = width, height = height, row = row, col = col,
    style = 'minimal', border = 'rounded', zindex = 60,
  })

  -- Set window-local options to reduce noise
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("list", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value('winblend', 0, { win = win })
  vim.api.nvim_set_option_value("buflisted", false, { buf = practice_buf })
  vim.api.nvim_set_option_value("modified", false, { buf = practice_buf })

  -- Namespaces
  local ns_dim = vim.api.nvim_create_namespace("KeymashDimNS")
  local ns_marks = vim.api.nvim_create_namespace("KeymashMarkNS")

  local session = {
    origin_buf = origin_bufnr,
    practice_buf = practice_buf,
    practice_win = win,
    backdrop_buf = back_buf,
    backdrop_win = back_win,
    expected_lines = expected_lines,
    ns_dim = ns_dim,
    ns_marks = ns_marks,
    prio_dim = 100,
    prio_typed = 200,
    config = config or {},
  }

  sessions_by_origin[origin_bufnr] = session
  sessions_by_practice[practice_buf] = session

  -- Initial visuals
  dim_buffer(session)

  setup_autocmds(session)
end

function M.stop(bufnr)
  local session = get_session_from_buf(bufnr)
  if not session then
    return
  end
  local pbuf = session.practice_buf
  if win_valid(session.backdrop_win) then
    pcall(vim.api.nvim_win_close, session.backdrop_win, true)
  end
  if buf_valid(session.backdrop_buf) then
    pcall(vim.api.nvim_buf_delete, session.backdrop_buf, { force = true })
  end
  if win_valid(session.practice_win) then
    pcall(vim.api.nvim_win_close, session.practice_win, true)
  end
  if buf_valid(pbuf) then
    -- Deleting the practice buffer will trigger autocmd cleanup
    pcall(vim.api.nvim_buf_delete, pbuf, { force = true })
  end
  clear_state(session.origin_buf, session.practice_buf)
end

return M
