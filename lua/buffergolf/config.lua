local M = {}

local defaults = {
  disabled_plugins = "auto",
  typing_mode = {
    disabled_plugins = { _inherit = true, matchparen = true, treesitter_context = true },
  },
  golf_mode = {
    disabled_plugins = { _inherit = true, matchparen = false },
  },
  auto_dedent = true,
  keymaps = {
    toggle = "<leader>bg",
    countdown = "<leader>bG",
    golf = { next_hunk = "]h", prev_hunk = "[h", first_hunk = "[H", last_hunk = "]H" },
  },
  windows = {
    reference = { position = "right", size = 50 },
    stats = { position = "top", height = 3 },
  },
}

local config = {}

function M.get()
  return config
end

local function merge_disabled_plugins(base, override)
  if not override then
    return base
  end
  if type(override) == "string" then
    return override
  end
  if type(override) ~= "table" then
    return base
  end

  if not override._inherit or not base then
    return override
  end

  local result = type(base) == "string" and { _auto = true } or vim.deepcopy(base)
  for k, v in pairs(override) do
    if k ~= "_inherit" then
      result[k] = v
    end
  end
  return result
end

function M.get_mode_config(mode, base_config)
  -- Use provided base_config or fall back to module config
  local base = base_config or config
  local mode_config = base[mode .. "_mode"]
  if not mode_config then
    return vim.deepcopy(base)
  end

  local result = vim.deepcopy(base)
  if mode_config.disabled_plugins then
    result.disabled_plugins = merge_disabled_plugins(base.disabled_plugins, mode_config.disabled_plugins)
  end

  for k, v in pairs(mode_config) do
    if k ~= "disabled_plugins" then
      result[k] = type(v) == "table" and type(result[k]) == "table" and vim.tbl_deep_extend("force", result[k], v) or v
    end
  end
  return result
end

function M.setup(opts)
  opts = opts or {}

  -- Legacy compatibility
  local legacy =
    { disable_diagnostics = "diagnostics", disable_inlay_hints = "inlay_hints", disable_matchparen = "matchparen" }
  for old, new in pairs(legacy) do
    if opts[old] ~= nil then
      opts.disabled_plugins = type(opts.disabled_plugins) == "table" and opts.disabled_plugins or { _auto = true }
      opts.disabled_plugins[new] = opts[old]
      opts[old] = nil
    end
  end

  if opts.difficulty then
    vim.notify("BufferGolf: 'difficulty' option removed", vim.log.levels.WARN)
    opts.difficulty = nil
  end

  config = vim.tbl_deep_extend("force", defaults, opts)

  -- Validate
  local dp = config.disabled_plugins
  if dp and type(dp) ~= "string" and type(dp) ~= "table" then
    error("disabled_plugins must be 'auto' or a table")
  end
  if type(dp) == "string" and dp ~= "auto" then
    error("disabled_plugins must be 'auto'")
  end

  if config.windows then
    local ref_pos = config.windows.reference and config.windows.reference.position
    if ref_pos and not vim.tbl_contains({ "right", "left", "top", "bottom" }, ref_pos) then
      error("invalid reference window position")
    end
    local stats_pos = config.windows.stats and config.windows.stats.position
    if stats_pos and not vim.tbl_contains({ "top", "bottom" }, stats_pos) then
      error("invalid stats window position")
    end
  end

  return config
end

-- Make merge_disabled_plugins available for external use
M.merge_disabled_plugins = merge_disabled_plugins

return M
