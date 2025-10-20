local Session = require("keymash.session")

local M = {}

local default_config = {
  dim_hl = "KeymashDim",
  correct_hl = "KeymashCorrect",
  error_hl = "KeymashError",
  cursor_hl = "KeymashCursor",
  dim_blend = 70,
  auto_tab = true,
  auto_scroll = true,
  compat = {
    disable = {
      mini_pairs = true,
      mini_surround = true,
      matchparen = true, -- also disables nvim-matchup matchparen if present
    },
    -- custom = function(buf) end, -- user hook per practice buffer (optional)
  },
}

local configured = false

local function ensure_highlights(opts)
  local function hl_exists(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
    return ok and hl and (next(hl) ~= nil)
  end
  local function can_link(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
    return ok and hl ~= nil
  end

  -- Dim: prefer linking to Comment; fallback to gray cterm + gui
  if not hl_exists(opts.dim_hl) then
    if can_link('Comment') then
      vim.api.nvim_set_hl(0, opts.dim_hl, { link = 'Comment' })
    else
      vim.api.nvim_set_hl(0, opts.dim_hl, { fg = '#666666', ctermfg = 8 })
    end
  end

  -- Correct: prefer DiffAdd; fallback to green
  if not hl_exists(opts.correct_hl) then
    if can_link('DiffAdd') then
      vim.api.nvim_set_hl(0, opts.correct_hl, { link = 'DiffAdd' })
    else
      vim.api.nvim_set_hl(0, opts.correct_hl, { fg = '#98c379', ctermfg = 2 })
    end
  end

  -- Error: prefer DiagnosticError or DiffDelete; fallback to red
  if not hl_exists(opts.error_hl) then
    if can_link('DiagnosticError') then
      vim.api.nvim_set_hl(0, opts.error_hl, { link = 'DiagnosticError' })
    elseif can_link('DiffDelete') then
      vim.api.nvim_set_hl(0, opts.error_hl, { link = 'DiffDelete' })
    else
      vim.api.nvim_set_hl(0, opts.error_hl, { fg = '#e06c75', ctermfg = 1 })
    end
  end

  -- Cursor highlight (optional visual aid)
  if not hl_exists(opts.cursor_hl) then
    vim.api.nvim_set_hl(0, opts.cursor_hl, { bg = '#414868', ctermbg = 8 })
  end

  -- Backdrop for dimming editor behind the float
  if not hl_exists('KeymashBackdrop') then
    vim.api.nvim_set_hl(0, 'KeymashBackdrop', { bg = '#000000', ctermbg = 0 })
  end

end

function M.setup(opts)
  if configured then
    return
  end
  M.config = vim.tbl_deep_extend("force", {}, default_config, opts or {})
  ensure_highlights(M.config)

  -- Reapply highlights on colorscheme changes
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('KeymashHL', { clear = true }),
    callback = function()
      ensure_highlights(M.config)
    end,
  })

  vim.api.nvim_create_user_command("Keymash", function()
    M.toggle()
  end, { desc = "Toggle Keymash typing practice" })

  vim.api.nvim_create_user_command("KeymashStop", function()
    M.stop()
  end, { desc = "Stop Keymash session" })

  configured = true
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if Session.is_active(bufnr) then
    Session.stop(bufnr)
  else
    Session.start(bufnr, M.config)
  end
end

function M.start()
  Session.start(vim.api.nvim_get_current_buf(), M.config)
end

function M.stop()
  Session.stop(vim.api.nvim_get_current_buf())
end

return M
