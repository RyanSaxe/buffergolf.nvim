local timer = require("buffergolf.timer")
local keystroke = require("buffergolf.keystroke")
local diff = require("buffergolf.diff")

local M = {}

local sessions_by_origin = {}
local sessions_by_practice = {}

local function buf_valid(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function copy_indent_options(origin, target)
  -- Keep indentation behavior in the practice buffer aligned with the source buffer.
  local opts = {
    "expandtab",
    "tabstop",
    "softtabstop",
    "shiftwidth",
    "autoindent",
    "smartindent",
    "cindent",
    "indentexpr",
    "copyindent",
    "preserveindent",
  }

  for _, opt in ipairs(opts) do
    local ok, value = pcall(vim.api.nvim_get_option_value, opt, { buf = origin })
    if ok then
      pcall(vim.api.nvim_set_option_value, opt, value, { buf = target })
    end
  end
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
  local chars = vim.fn.split(ghost_text, "\\zs")
  for _, ch in ipairs(chars) do
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

local function set_ghost_mark(session, row, col, text, actual)
  clear_ghost_mark(session, row)

  if text == "" then
    return
  end

  local virt_text = text
  if virt_text:find("\t") then
    virt_text = expand_ghost_text(session, actual or "", virt_text)
  end

  local id = vim.api.nvim_buf_set_extmark(session.practice_buf, session.ns_ghost, row - 1, col, {
    virt_text = { { virt_text, session.config.ghost_hl } },
    virt_text_pos = "inline",
    hl_mode = "combine",
    priority = session.prio_ghost,
  })
  session.ghost_marks[row] = id
end

local function refresh_visuals(session)
  if session.refreshing then
    return
  end

  session.refreshing = true

  local ok, err = pcall(function()
    repeat
      if not buf_valid(session.practice_buf) then
        break
      end

      -- For golf mode, update diff highlights instead of ghost text
      if session.mode == "golf" then
        diff.apply_diff_highlights(session)
        break
      end

      -- Typing mode: show ghost text
      ensure_line_count(session)

      local bufnr = session.practice_buf
      local actual_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
      local total = math.max(#actual_lines, #session.reference_lines)

      for row = 1, total do
        local actual = actual_lines[row] or ""

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

        local ghost_start_index = prefix + 1
        local ghost = ""
        if ghost_start_index <= #reference then
          ghost = reference:sub(ghost_start_index)
        end

        local ghost_col = #actual
        set_ghost_mark(session, row, ghost_col, ghost, actual)
      end

      -- Remove stale ghost marks if the buffer shrank.
      if #session.ghost_marks > total then
        for row = total + 1, #session.ghost_marks do
          clear_ghost_mark(session, row)
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

local function attach_change_watcher(session)
  if session.change_attached then
    return
  end
  if not buf_valid(session.practice_buf) then
    return
  end

  local ok, res = pcall(vim.api.nvim_buf_attach, session.practice_buf, false, {
    on_lines = function(_, buf, _, _, _, _)
      if session.refreshing then
        return
      end
      if not buf_valid(buf) then
        return true
      end
      if sessions_by_practice[buf] ~= session then
        return true
      end
      timer.on_first_edit(session)
      refresh_visuals(session)
    end,
    on_detach = function()
      session.change_attached = nil
    end,
  })

  if ok and res then
    session.change_attached = true
  end
end

local function disable_diagnostics(bufnr)
  if type(vim.diagnostic) == "table" and vim.diagnostic.disable then
    pcall(vim.diagnostic.disable, bufnr)
  end
end

local function disable_inlay_hints(bufnr)
  local ih = vim.lsp and vim.lsp.inlay_hint
  if ih == nil then
    return
  end

  if type(ih) == "table" then
    if ih.enable then
      pcall(ih.enable, false, { bufnr = bufnr })
    elseif ih.disable then
      pcall(ih.disable, bufnr)
    end
  elseif type(ih) == "function" then
    pcall(ih, bufnr, false)
  end
end

local function disable_autopairs(bufnr)
  -- Disable nvim-autopairs
  pcall(vim.api.nvim_buf_set_var, bufnr, "autopairs_enabled", false)
  -- Disable mini.pairs
  pcall(vim.api.nvim_buf_set_var, bufnr, "minipairs_disable", true)
end

local function apply_buffer_defaults(session)
  local buf = session.practice_buf

  if session.config.disable_diagnostics ~= false then
    disable_diagnostics(buf)
  end
  if session.config.disable_inlay_hints ~= false then
    disable_inlay_hints(buf)
  end
  if session.config.disable_autopairs ~= false then
    disable_autopairs(buf)
  end
end

local function disable_matchparen(session)
  if session.config.disable_matchparen == false then
    return
  end

  local win = session.practice_win
  if not win_valid(win) then
    return
  end

  local ok, current = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
  local value = ok and current or ""
  if value ~= "" then
    if value:match("MatchParen:") then
      value = value:gsub("MatchParen:[^,%s]+", "MatchParen:None")
    else
      value = value .. ",MatchParen:None"
    end
  else
    value = "MatchParen:None"
  end
  vim.api.nvim_set_option_value("winhighlight", value, { win = win })

  pcall(vim.api.nvim_buf_set_var, session.practice_buf, "matchup_matchparen_enabled", 0)
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
  if session.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
  end
  -- Clear diff highlights if in golf mode
  if session.mode == "golf" then
    diff.clear_diff_highlights(session)
  end
end

local function setup_autocmds(session)
  local aug = vim.api.nvim_create_augroup(("BuffergolfSession_%d"):format(session.practice_buf), { clear = true })
  session.augroup = aug

  vim.api.nvim_create_autocmd("BufEnter", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      apply_buffer_defaults(session)
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      timer.show_stats_float(session)
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      timer.hide_stats_float(session)
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
      apply_buffer_defaults(session)
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

local function create_reference_window(session)
  -- Create readonly buffer with target text
  local ref_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(ref_buf, 0, -1, false, session.reference_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ref_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = ref_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = ref_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = ref_buf })

  -- Match filetype for syntax highlighting
  local ft = vim.api.nvim_get_option_value("filetype", { buf = session.practice_buf })
  if ft and ft ~= "" then
    vim.api.nvim_set_option_value("filetype", ft, { buf = ref_buf })
  end

  -- Get window configuration
  local ref_config = session.config.reference_window or {}
  local position = ref_config.position or "right"
  local size = ref_config.size or 50

  -- Create split based on configuration
  if position == "left" then
    vim.cmd("leftabove vsplit")
  elseif position == "top" then
    vim.cmd("leftabove split")
  elseif position == "bottom" then
    vim.cmd("rightbelow split")
  else  -- default to right
    vim.cmd("rightbelow vsplit")
  end

  local ref_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ref_win, ref_buf)

  -- Set window size based on configuration
  if position == "left" or position == "right" then
    -- For vertical splits, use percentage of screen width
    local screen_width = vim.api.nvim_get_option("columns")
    local win_width = math.floor(screen_width * size / 100)
    vim.api.nvim_win_set_width(ref_win, win_width)
  else
    -- For horizontal splits, use fixed line count or percentage of height
    if size <= 100 then
      -- Treat as percentage
      local screen_height = vim.api.nvim_get_option("lines")
      local win_height = math.floor(screen_height * size / 100)
      vim.api.nvim_win_set_height(ref_win, win_height)
    else
      -- Treat as absolute line count
      vim.api.nvim_win_set_height(ref_win, size)
    end
  end

  -- Set window options
  vim.api.nvim_set_option_value("number", true, { win = ref_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = ref_win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = ref_win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = ref_win })

  -- Add title to reference window
  vim.api.nvim_buf_set_var(ref_buf, "buffergolf_reference", true)

  -- Return to practice window
  vim.api.nvim_set_current_win(session.practice_win)

  -- Store reference window info in session
  session.reference_buf = ref_buf
  session.reference_win = ref_win

  return ref_buf, ref_win
end

local function normalize_reference_lines(lines, bufnr)
  -- If expandtab is on, convert tabs to spaces in reference lines
  -- This ensures byte-by-byte comparison works with autoindent
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

function M.start(origin_bufnr, config, target_lines)
  if sessions_by_origin[origin_bufnr] then
    return
  end

  local reference = target_lines or vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)
  if #reference == 0 then
    reference = { "" }
  end

  -- Normalize tabs to spaces if expandtab is on
  reference = normalize_reference_lines(reference, origin_bufnr)

  local practice_buf = vim.api.nvim_create_buf(false, false)
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

  copy_indent_options(origin_bufnr, practice_buf)

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
  }

  sessions_by_origin[origin_bufnr] = session
  sessions_by_practice[practice_buf] = session

  apply_buffer_defaults(session)

  vim.api.nvim_win_set_buf(current_win, practice_buf)
  session.practice_win = vim.api.nvim_get_current_win()

  disable_matchparen(session)

  setup_autocmds(session)
  attach_change_watcher(session)

  -- Set up keystroke tracking using the robust keystroke module
  keystroke.init_session(session)

  timer.init(session)
  refresh_visuals(session)
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
  reference = normalize_reference_lines(reference, origin_bufnr)
  start_lines = normalize_reference_lines(start_lines, origin_bufnr)

  local practice_buf = vim.api.nvim_create_buf(false, false)
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

  copy_indent_options(origin_bufnr, practice_buf)

  -- Set the starting lines (not empty for golf mode)
  vim.api.nvim_buf_set_lines(practice_buf, 0, -1, true, start_lines)

  local current_win = vim.api.nvim_get_current_win()
  pcall(vim.api.nvim_buf_set_var, practice_buf, "buffergolf_practice", true)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "copilot_enabled", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "copilot_suggestion_auto_trigger", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "autopairs_enabled", false)
  pcall(vim.api.nvim_buf_set_var, practice_buf, "minipairs_disable", true)

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
  }

  sessions_by_origin[origin_bufnr] = session
  sessions_by_practice[practice_buf] = session

  apply_buffer_defaults(session)

  vim.api.nvim_win_set_buf(current_win, practice_buf)
  session.practice_win = vim.api.nvim_get_current_win()

  disable_matchparen(session)

  setup_autocmds(session)
  attach_change_watcher(session)

  -- Set up keystroke tracking
  keystroke.init_session(session)

  -- Create reference window and initialize diff highlighting
  create_reference_window(session)
  diff.init(session)

  timer.init(session)
  refresh_visuals(session)
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

  -- Clear all ghost marks and mismatches
  if session.ghost_marks then
    for _, mark in pairs(session.ghost_marks) do
      pcall(vim.api.nvim_buf_del_extmark, session.practice_buf, session.ns_ghost, mark)
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
  end

  -- Refresh visuals to recreate ghost text and highlights
  refresh_visuals(session)

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

-- DEBUG: Expose function to print debug keys
function M.debug_keys(bufnr)
  local session = get_session(bufnr or vim.api.nvim_get_current_buf())
  if not session then
    print("No active buffergolf session")
    return
  end

  local debug_keys = keystroke.get_debug_keys(session)
  if not debug_keys or #debug_keys == 0 then
    print("No debug keys available")
    return
  end

  print("Recent keys captured:")
  for _, entry in ipairs(debug_keys) do
    print("  " .. entry)
  end
end

return M
