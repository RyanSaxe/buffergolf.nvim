local disabled_plugins = require("buffergolf.disabled_plugins")

local M = {}

local buffer_stats = {}

function M.buf_valid(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

function M.win_valid(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

function M.record_buffer_creation(bufnr, buffer_type)
  buffer_stats[bufnr] = {
    type = buffer_type,
    created_at = os.time(),
  }
end

function M.get_buffer_stats(bufnr)
  return buffer_stats[bufnr]
end

function M.clear_buffer_stats(bufnr)
  buffer_stats[bufnr] = nil
end

function M.copy_indent_options(origin, target)
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

function M.generate_buffer_name(origin_bufnr, suffix)
  local origin_name = vim.api.nvim_buf_get_name(origin_bufnr)
  if origin_name == "" then
    local ft = vim.api.nvim_get_option_value("filetype", { buf = origin_bufnr })
    return "unnamed" .. suffix .. "." .. (ft ~= "" and ft or "txt")
  end

  local dir = vim.fn.fnamemodify(origin_name, ":h")
  local basename = vim.fn.fnamemodify(origin_name, ":t:r")
  local ext = vim.fn.fnamemodify(origin_name, ":e")
  local name = dir .. "/" .. basename .. suffix .. (ext ~= "" and "." .. ext or "")

  if vim.fn.filereadable(name) == 1 then
    vim.notify(
      "WARNING: Found existing file '"
        .. name
        .. "' on disk. "
        .. "BufferGolf practice/reference buffers should be temporary and never exist as real files. "
        .. "Please remove or rename this file.",
      vim.log.levels.ERROR,
      { title = "buffergolf" }
    )
  end
  return name
end

local function expand_tabs_to_spaces(line, tabstop)
  if not line:find("\t") then
    return line
  end
  local result, col = {}, 0
  for char in line:gmatch(".") do
    if char == "\t" then
      local spaces = tabstop - (col % tabstop)
      result[#result + 1] = string.rep(" ", spaces > 0 and spaces or tabstop)
      col = col + spaces
    else
      result[#result + 1] = char
      col = col + 1
    end
  end
  return table.concat(result)
end

function M.normalize_lines(lines, bufnr)
  local ok, expandtab = pcall(vim.api.nvim_get_option_value, "expandtab", { buf = bufnr })
  if not ok or not expandtab then
    return lines
  end

  local ok_ts, tabstop = pcall(vim.api.nvim_get_option_value, "tabstop", { buf = bufnr })
  tabstop = ok_ts and tabstop or 8

  local normalized = {}
  for _, line in ipairs(lines) do
    normalized[#normalized + 1] = expand_tabs_to_spaces(line, tabstop)
  end
  return normalized
end

function M.strip_trailing_empty_lines(lines)
  local last_non_empty = 0
  for i = #lines, 1, -1 do
    if lines[i] ~= "" then
      last_non_empty = i
      break
    end
  end
  if last_non_empty == 0 then
    return {}
  end
  local result = {}
  for i = 1, last_non_empty do
    result[#result + 1] = lines[i]
  end
  return result
end

function M.apply_defaults(session)
  local ctx = disabled_plugins.create_context({
    buf = session.practice_buf,
    win = session.practice_win,
    mode = session.mode,
    origin_buf = session.origin_buf,
  })

  -- Store original winhighlight if needed
  local dp = session.config.disabled_plugins
  local will_disable = dp == "auto"
    or (type(dp) == "table" and (dp._auto and dp.matchparen ~= false or dp.matchparen == true))
  if will_disable and not session.prev_winhighlight then
    local ok, prev = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = session.practice_win })
    session.prev_winhighlight = ok and prev or ""
  end

  disabled_plugins.apply(session.config, ctx)

  -- Apply to reference buffer too
  if session.reference_buf and M.buf_valid(session.reference_buf) and session.reference_win then
    disabled_plugins.apply(
      session.config,
      disabled_plugins.create_context({
        buf = session.reference_buf,
        win = session.reference_win,
        mode = session.mode,
        origin_buf = session.origin_buf,
      })
    )
  end
end

function M.dedent_lines(lines)
  if #lines == 0 then
    return lines
  end
  local min_indent = math.huge
  for _, line in ipairs(lines) do
    if line:match("%S") then
      min_indent = math.min(min_indent, line:match("^%s*"):len())
    end
  end
  if min_indent == 0 or min_indent == math.huge then
    return lines
  end

  local result = {}
  for _, line in ipairs(lines) do
    result[#result + 1] = line:match("%S") and line:sub(min_indent + 1) or line
  end
  return result
end

function M.prepare_lines(lines, _, config)
  return config.auto_dedent and M.dedent_lines(lines) or lines
end

function M.get_line_stats(lines)
  local stats = {
    total_lines = #lines,
    empty_lines = 0,
    total_chars = 0,
    max_line_length = 0,
    min_line_length = math.huge,
  }

  for _, line in ipairs(lines) do
    if line == "" then
      stats.empty_lines = stats.empty_lines + 1
    end
    stats.total_chars = stats.total_chars + #line
    stats.max_line_length = math.max(stats.max_line_length, #line)
    if #line > 0 then
      stats.min_line_length = math.min(stats.min_line_length, #line)
    end
  end

  if stats.min_line_length == math.huge then
    stats.min_line_length = 0
  end

  stats.avg_line_length = stats.total_lines > 0 and (stats.total_chars / stats.total_lines) or 0

  return stats
end

return M
