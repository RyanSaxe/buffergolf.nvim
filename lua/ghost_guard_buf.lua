-- Block virtual "ghost text" in selected buffers, with per-buffer allowlists.
-- Guards at the API layer to avoid flicker: intercepts extmarks and decoration providers.

local M = {}

local protected = {}        -- [bufnr] = true
local allowmap = {}         -- [bufnr][nsid] = true
local allow_needles = {}    -- [bufnr] = { "cmp", ... }
local augroups = {}         -- [bufnr] = augroup id

local function resolve_allow_for(buf)
  local needles = allow_needles[buf]
  if not needles or #needles == 0 then
    return
  end

  allowmap[buf] = allowmap[buf] or {}
  local ok, nsmap = pcall(vim.api.nvim_get_namespaces)
  if not ok then
    return
  end

  for name, id in pairs(nsmap) do
    for _, needle in ipairs(needles) do
      if type(needle) == "string" and name:find(needle, 1, true) then
        allowmap[buf][id] = true
        break
      end
    end
  end
end

local function clear_state(buf)
  protected[buf] = nil
  allowmap[buf] = nil
  allow_needles[buf] = nil
  local aug = augroups[buf]
  if aug then
    pcall(vim.api.nvim_del_augroup_by_id, aug)
    augroups[buf] = nil
  end
end

function M.enable(buf, opts)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  opts = opts or {}
  local allow = {}
  if opts.allow then
    for _, needle in ipairs(opts.allow) do
      if needle ~= nil then
        table.insert(allow, needle)
      end
    end
  end

  allow_needles[buf] = allow
  protected[buf] = true
  resolve_allow_for(buf)

  local should_disable_diag = opts.disable_diagnostics ~= false
  if should_disable_diag then
    pcall(vim.diagnostic.disable, buf)
    if vim.lsp and vim.lsp.inlay_hint and vim.lsp.inlay_hint.enable then
      pcall(vim.lsp.inlay_hint.enable, false, { bufnr = buf })
    end
  end

  local group = vim.api.nvim_create_augroup("GhostGuardBuf" .. buf, { clear = true })
  augroups[buf] = group

  vim.api.nvim_create_autocmd({ "BufEnter", "LspAttach" }, {
    group = group,
    buffer = buf,
    callback = function()
      resolve_allow_for(buf)
    end,
    desc = "GhostGuard: refresh allowlist",
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = group,
    buffer = buf,
    callback = function()
      clear_state(buf)
    end,
    desc = "GhostGuard: cleanup state",
  })
end

function M.disable(buf)
  if not protected[buf] then
    return
  end
  clear_state(buf)
end

local function strip_virt(opts)
  if not opts then
    return opts
  end
  if opts.virt_text == nil and opts.virt_text_win_col == nil and opts.virt_text_pos == nil then
    return opts
  end
  local o = vim.deepcopy(opts)
  o.virt_text = nil
  o.virt_text_win_col = nil
  o.virt_text_pos = nil
  o.virt_text_hide = nil
  return o
end

if not vim.g.__ghost_guard_buf_patched then
  vim.g.__ghost_guard_buf_patched = true

  local old_extmark = vim.api.nvim_buf_set_extmark
  vim.api.nvim_buf_set_extmark = function(buf, ns, line, col, opts)
    if protected[buf] and opts and (opts.virt_text or opts.virt_text_win_col or opts.virt_text_pos) then
      local allow = allowmap[buf]
      if not (allow and allow[ns]) then
        opts = strip_virt(opts)
      end
    end
    return old_extmark(buf, ns, line, col, opts)
  end
end

return M
