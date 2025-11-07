local M = {}

local has_snacks = pcall(require, "snacks.picker")
local has_telescope = pcall(require, "telescope")
local has_fzf_lua = pcall(require, "fzf-lua")

local adapter_stats = {
  snacks_calls = 0,
  telescope_calls = 0,
  fzf_calls = 0,
  fallback_calls = 0,
}

function M.has_snacks()
  return has_snacks
end

function M.has_telescope()
  return has_telescope
end

function M.has_fzf_lua()
  return has_fzf_lua
end

function M.get_available_pickers()
  local pickers = {}
  if has_snacks then
    table.insert(pickers, "snacks")
  end
  if has_telescope then
    table.insert(pickers, "telescope")
  end
  if has_fzf_lua then
    table.insert(pickers, "fzf-lua")
  end
  return pickers
end

function M.get_stats()
  return adapter_stats
end

function M.reset_stats()
  adapter_stats = {
    snacks_calls = 0,
    telescope_calls = 0,
    fzf_calls = 0,
    fallback_calls = 0,
  }
end

function M.run_picker(picker_type, custom_confirm, fallback)
  if has_snacks then
    adapter_stats.snacks_calls = adapter_stats.snacks_calls + 1
    local snacks = require("snacks.picker")
    snacks[picker_type]({ confirm = custom_confirm })
  else
    adapter_stats.fallback_calls = adapter_stats.fallback_calls + 1
    fallback()
  end
end

return M
