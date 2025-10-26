-- Buffer utilities shared across BufferGolf modules.
-- Provides helpers for checking buffer/window validity, aligning options,
-- normalising line content, and applying default session settings.

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
    local ext = ft ~= "" and ft or "txt"
    return "unnamed" .. suffix .. "." .. ext
  end

  local dir = vim.fn.fnamemodify(origin_name, ":h")
  local basename = vim.fn.fnamemodify(origin_name, ":t:r")
  local ext = vim.fn.fnamemodify(origin_name, ":e")

  local name
  if ext ~= "" then
    name = dir .. "/" .. basename .. suffix .. "." .. ext
  else
    name = dir .. "/" .. basename .. suffix
  end

  if vim.fn.filereadable(name) == 1 then
    vim.notify(
      "WARNING: Found existing file '" .. name .. "' on disk. " ..
      "BufferGolf practice/reference buffers should be temporary and never exist as real files. " ..
      "Please remove or rename this file.",
      vim.log.levels.ERROR,
      { title = "buffergolf" }
    )
  end

  return name
end

function M.normalize_lines(lines, bufnr)
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
          if spaces <= 0 then
            spaces = tabstop
          end
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
    table.insert(result, lines[i])
  end
  return result
end

local function disable_diagnostics(bufnr)
  if type(vim.diagnostic) == "table" and vim.diagnostic.enable then
    pcall(vim.diagnostic.enable, false, { bufnr = bufnr })
  elseif type(vim.diagnostic) == "table" and vim.diagnostic.disable then
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
  pcall(vim.api.nvim_buf_set_var, bufnr, "autopairs_enabled", false)
  pcall(vim.api.nvim_buf_set_var, bufnr, "minipairs_disable", true)
end

function M.apply_defaults(session)
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

function M.disable_matchparen(session)
  if session.config.disable_matchparen == false then
    return
  end

  local win = session.practice_win
  if not M.win_valid(win) then
    return
  end

  if session.prev_winhighlight == nil then
    local ok_prev, prev = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
    if ok_prev then
      session.prev_winhighlight = prev
    else
      session.prev_winhighlight = ""
    end
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

  if M.buf_valid(session.practice_buf) then
    pcall(vim.api.nvim_buf_set_var, session.practice_buf, "matchup_matchparen_enabled", 0)
  end
end

return M
