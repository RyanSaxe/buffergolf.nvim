local timer = require("buffergolf.timer")

local M = {}

local sessions_by_origin = {}
local sessions_by_practice = {}

-- Debug logging
local debug_log_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h") .. "/debug.log"

local function debug_log(session, message)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local buf_id = session and session.practice_buf or "no-session"
  local log_line = string.format("[%s] [buf:%s] %s\n", timestamp, buf_id, message)

  local file = io.open(debug_log_path, "a")
  if file then
    file:write(log_line)
    file:close()
  end
end

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
    debug_log(session, "refresh_visuals: already refreshing, skipping")
    return
  end

  debug_log(session, "refresh_visuals: starting")
  session.refreshing = true

  local ok, err = pcall(function()
    repeat
      if not buf_valid(session.practice_buf) then
        break
      end

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
    debug_log(session, "refresh_visuals: ERROR - " .. tostring(err))
    vim.notify("Buffergolf refresh error: " .. tostring(err), vim.log.levels.ERROR)
  else
    debug_log(session, "refresh_visuals: completed successfully")
  end
end

local function attach_change_watcher(session)
  if session.change_attached then
    debug_log(session, "attach_change_watcher: already attached, skipping")
    return
  end
  if not buf_valid(session.practice_buf) then
    debug_log(session, "attach_change_watcher: buffer invalid, skipping")
    return
  end

  debug_log(session, "attach_change_watcher: attempting to attach")

  local ok, res = pcall(vim.api.nvim_buf_attach, session.practice_buf, false, {
    on_lines = function(_, buf, _, _, _, _)
      debug_log(session, string.format("on_lines fired: buf=%d, refreshing=%s", buf, tostring(session.refreshing)))

      if session.refreshing then
        debug_log(session, "on_lines: returning early (refreshing=true)")
        return
      end

      local buf_is_valid = buf_valid(buf)
      debug_log(session, string.format("on_lines: buf_valid(buf)=%s", tostring(buf_is_valid)))
      if not buf_is_valid then
        debug_log(session, "on_lines: DETACHING (buf_valid=false)")
        return true
      end

      local session_matches = sessions_by_practice[buf] == session
      debug_log(session, string.format("on_lines: session_matches=%s", tostring(session_matches)))
      if not session_matches then
        debug_log(session, "on_lines: DETACHING (session mismatch)")
        return true
      end

      debug_log(session, "on_lines: calling timer.on_first_edit and refresh_visuals")
      timer.on_first_edit(session)
      refresh_visuals(session)
    end,
    on_detach = function()
      debug_log(session, "on_detach fired: setting change_attached=nil")
      session.change_attached = nil
    end,
  })

  if ok and res then
    session.change_attached = true
    debug_log(session, "attach_change_watcher: successfully attached")
  else
    debug_log(session, string.format("attach_change_watcher: FAILED to attach (ok=%s, res=%s)", tostring(ok), tostring(res)))
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
  debug_log(session, "clear_state: called - clearing session state")

  -- Get stack trace to see what's calling this
  local trace = debug.traceback("", 2)
  debug_log(session, "clear_state: stack trace:\n" .. trace)

  timer.cleanup(session)
  sessions_by_origin[session.origin_buf] = nil
  sessions_by_practice[session.practice_buf] = nil
  debug_log(session, "clear_state: cleared sessions_by_practice and sessions_by_origin")

  if session.change_attached and buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_buf_detach, session.practice_buf)
    debug_log(session, "clear_state: detached buffer")
  end
  session.change_attached = nil
  session.refreshing = nil
  debug_log(session, "clear_state: set change_attached and refreshing to nil")

  if session.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
    debug_log(session, "clear_state: deleted autocommand group")
  end

  debug_log(session, "clear_state: completed")
end

local function setup_autocmds(session)
  local aug = vim.api.nvim_create_augroup(("BuffergolfSession_%d"):format(session.practice_buf), { clear = true })
  session.augroup = aug
  debug_log(session, "setup_autocmds: created autocommand group")

  vim.api.nvim_create_autocmd("BufEnter", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      debug_log(session, "autocmd: BufEnter fired")
      apply_buffer_defaults(session)
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      debug_log(session, "autocmd: WinEnter fired - showing stats float")
      timer.show_stats_float(session)
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      debug_log(session, "autocmd: WinLeave fired - hiding stats float")
      timer.hide_stats_float(session)
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      debug_log(session, "autocmd: BufWriteCmd fired")
      vim.notify("Buffergolf buffers cannot be written.", vim.log.levels.WARN, { title = "buffergolf" })
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      debug_log(session, "autocmd: LspAttach fired")
      apply_buffer_defaults(session)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufHidden" }, {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      debug_log(session, "autocmd: BufLeave/BufHidden fired")
      if buf_valid(session.practice_buf) then
        pcall(vim.api.nvim_set_option_value, "modified", false, { buf = session.practice_buf })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = aug,
    buffer = session.practice_buf,
    callback = function()
      debug_log(session, "autocmd: BufWipeout/BufDelete fired")

      -- Only clear state if buffer is actually being destroyed
      -- This prevents spurious events (e.g., from blink.cmp) from breaking the session
      if not vim.api.nvim_buf_is_valid(session.practice_buf) then
        debug_log(session, "autocmd: buffer is invalid, calling clear_state")
        clear_state(session)
      else
        debug_log(session, "autocmd: buffer is still valid, ignoring spurious BufWipeout/BufDelete event")
      end
    end,
  })

  debug_log(session, "setup_autocmds: all autocmds created")
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

function M.start(origin_bufnr, config)
  if sessions_by_origin[origin_bufnr] then
    return
  end

  local reference = vim.api.nvim_buf_get_lines(origin_bufnr, 0, -1, true)
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
  }

  sessions_by_origin[origin_bufnr] = session
  sessions_by_practice[practice_buf] = session
  debug_log(session, string.format("M.start: registered session in sessions_by_origin[%d] and sessions_by_practice[%d]", origin_bufnr, practice_buf))

  apply_buffer_defaults(session)

  vim.api.nvim_win_set_buf(current_win, practice_buf)
  session.practice_win = vim.api.nvim_get_current_win()

  disable_matchparen(session)

  setup_autocmds(session)
  attach_change_watcher(session)
  timer.init(session)
  refresh_visuals(session)
end

function M.stop(bufnr)
  local session = get_session(bufnr)
  if not session then
    debug_log(nil, string.format("M.stop: no session found for buffer %d", bufnr))
    return
  end

  debug_log(session, string.format("M.stop: stopping session for buffer %d", bufnr))

  local practice_buf = session.practice_buf
  local origin_buf = session.origin_buf

  if win_valid(session.origin_win) and buf_valid(origin_buf) then
    vim.api.nvim_set_current_win(session.origin_win)
    vim.api.nvim_win_set_buf(session.origin_win, origin_buf)
    debug_log(session, "M.stop: restored origin window and buffer")
  elseif buf_valid(origin_buf) then
    vim.api.nvim_set_current_buf(origin_buf)
    debug_log(session, "M.stop: restored origin buffer")
  end

  if buf_valid(practice_buf) then
    debug_log(session, "M.stop: deleting practice buffer")
    vim.api.nvim_buf_delete(practice_buf, { force = true })
  end

  clear_state(session)
  debug_log(session, "M.stop: completed")
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

function M.get_debug_info(bufnr)
  local session = get_session(bufnr)
  if not session then
    return nil
  end

  return {
    practice_buf = session.practice_buf,
    origin_buf = session.origin_buf,
    change_attached = session.change_attached,
    refreshing = session.refreshing,
    buf_valid = buf_valid(session.practice_buf),
  }
end

return M
