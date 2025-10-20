local M = {}

-- Disable built-ins / plugins that commonly conflict with overtype behavior

local function override_matchparen_highlight(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- Link MatchParen to NONE so builtin matchparen highlight is invisible in this window.
  local ok, current = pcall(vim.api.nvim_get_option_value, "winhighlight", { win = win })
  if not ok then
    return
  end

  local value = current or ""
  if value == "" then
    pcall(vim.api.nvim_set_option_value, "winhighlight", "MatchParen:NONE", { win = win })
    return
  end

  local parts = vim.split(value, ",", { trimempty = true })
  local replaced = false
  for idx, part in ipairs(parts) do
    local name = part:match("^%s*(.-)%s*:")
    if name == "MatchParen" then
      parts[idx] = "MatchParen:NONE"
      replaced = true
      break
    end
  end
  if not replaced then
    table.insert(parts, "MatchParen:NONE")
  end

  pcall(vim.api.nvim_set_option_value, "winhighlight", table.concat(parts, ","), { win = win })
end

local function disable_matchparen(buf, win)
  if win and vim.api.nvim_win_is_valid(win) then
    override_matchparen_highlight(win)
  else
    for _, w in ipairs(vim.fn.win_findbuf(buf)) do
      override_matchparen_highlight(w)
    end
  end
  -- If nvim-matchup is installed, it respects this buffer variable flag.
  pcall(vim.api.nvim_buf_set_var, buf, "matchup_matchparen_enabled", 0)
end

function M.apply(buf, maybe_win, compat)
  local win
  if type(maybe_win) == "number" then
    win, compat = maybe_win, compat
  else
    compat = maybe_win
  end

  compat = compat or {}
  local disable = compat.disable or {}

  -- mini.pairs: disable per-buffer
  if disable.mini_pairs ~= false then
    pcall(vim.api.nvim_buf_set_var, buf, "minipairs_disable", true)
  end

  -- mini.surround: disable per-buffer
  if disable.mini_surround ~= false then
    pcall(vim.api.nvim_buf_set_var, buf, "minisurround_disable", true)
  end

  -- matchparen / matchup
  if disable.matchparen ~= false then
    disable_matchparen(buf, win)
  end

  -- Optional user hook for custom per-buffer tweaks
  if type(compat.custom) == "function" then
    pcall(compat.custom, buf)
  end
end

return M
