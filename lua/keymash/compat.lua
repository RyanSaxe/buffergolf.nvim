local M = {}

-- Disable built-ins / plugins that commonly conflict with overtype behavior

local function disable_matchparen(buf)
  -- Built-in matchparen provides :NoMatchParen (buffer-local). Ignore errors if missing.
  vim.api.nvim_buf_call(buf, function()
    pcall(vim.cmd, 'silent! NoMatchParen')
  end)
  -- If nvim-matchup is installed, it respects this buffer variable flag.
  pcall(vim.api.nvim_buf_set_var, buf, 'matchup_matchparen_enabled', 0)
end

function M.apply(buf, compat)
  compat = compat or {}
  local disable = compat.disable or {}

  -- mini.pairs: disable per-buffer
  if disable.mini_pairs ~= false then
    pcall(vim.api.nvim_buf_set_var, buf, 'minipairs_disable', true)
  end

  -- mini.surround: disable per-buffer
  if disable.mini_surround ~= false then
    pcall(vim.api.nvim_buf_set_var, buf, 'minisurround_disable', true)
  end

  -- matchparen / matchup
  if disable.matchparen ~= false then
    disable_matchparen(buf)
  end

  -- Optional user hook for custom per-buffer tweaks
  if type(compat.custom) == 'function' then
    pcall(compat.custom, buf)
  end
end

return M

