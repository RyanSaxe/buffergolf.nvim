local Session = require("keymash.session")

local M = {}

local default_config = {
  ghost_hl = "BuffergolfGhost",
  mismatch_hl = "BuffergolfMismatch",
  disable_diagnostics = true,
  disable_matchparen = true,
  ghost_guard = {
    allow = {},
  },
}

local configured = false

local function hl_exists(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
  return ok and hl and next(hl) ~= nil
end

local function can_link(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
  return ok and hl ~= nil
end

local function ensure_highlights(opts)
  if not hl_exists(opts.ghost_hl) then
    if can_link("Comment") then
      vim.api.nvim_set_hl(0, opts.ghost_hl, { link = "Comment" })
    else
      vim.api.nvim_set_hl(0, opts.ghost_hl, { fg = "#555555", ctermfg = 8 })
    end
  end

  if not hl_exists(opts.mismatch_hl) then
    vim.api.nvim_set_hl(0, opts.mismatch_hl, {
      fg = "#ff5f6d",
      ctermfg = 1,
      underline = true,
    })
  end
end

function M.setup(opts)
  if configured then
    return
  end

  M.config = vim.tbl_deep_extend("force", {}, default_config, opts or {})
  ensure_highlights(M.config)

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("BuffergolfHL", { clear = true }),
    callback = function()
      ensure_highlights(M.config)
    end,
  })

  vim.api.nvim_create_user_command("Keymash", function()
    M.toggle()
  end, { desc = "Toggle buffergolf practice buffer" })

  vim.api.nvim_create_user_command("KeymashStop", function()
    M.stop()
  end, { desc = "Stop buffergolf practice buffer" })

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
