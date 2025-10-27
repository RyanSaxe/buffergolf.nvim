local M = {}

function M.buf_valid(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

function M.win_valid(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
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
  local buf = session.practice_buf
  local config = session.config

  if config.disable_diagnostics ~= false then
    local diag = vim.diagnostic
    if diag and diag.enable then
      pcall(diag.enable, false, { bufnr = buf })
    elseif diag and diag.disable then
      pcall(diag.disable, buf)
    end
  end

  if config.disable_inlay_hints ~= false then
    local ih = vim.lsp and vim.lsp.inlay_hint
    if ih then
      if type(ih) == "table" and ih.enable then
        pcall(ih.enable, false, { bufnr = buf })
      elseif type(ih) == "table" and ih.disable then
        pcall(ih.disable, buf)
      elseif type(ih) == "function" then
        pcall(ih, buf, false)
      end
    end
  end

  if config.disable_autopairs ~= false then
    pcall(vim.api.nvim_buf_set_var, buf, "autopairs_enabled", false)
    pcall(vim.api.nvim_buf_set_var, buf, "minipairs_disable", true)
  end
end

function M.disable_matchparen(session)
  if session.config.disable_matchparen == false then
    return
  end

  local win = session.practice_win
  if not M.win_valid(win) then
    return
  end

  if session.prev_winhighlight == nil then
    local ok, prev = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
    session.prev_winhighlight = ok and prev or ""
  end

  local ok, current = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
  local value = ok and current or ""
  value = value:match("MatchParen:") and value:gsub("MatchParen:[^,%s]+", "MatchParen:None")
    or (value ~= "" and value .. ",MatchParen:None" or "MatchParen:None")
  vim.api.nvim_set_option_value("winhighlight", value, { win = win })

  if M.buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_buf_set_var, session.practice_buf, "matchup_matchparen_enabled", 0)
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

function M.prepare_lines(lines, bufnr, config)
  return config.auto_dedent and M.dedent_lines(lines) or lines
end

return M
