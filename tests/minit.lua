#!/usr/bin/env -S nvim -l

-- Setup package paths for luacov (when running with nvim -l, the environment needs help)
-- This ensures luacov can be found even when running as a script
local function setup_luacov_paths()
  -- Get luarocks paths if not already set
  if not vim.env.LUA_PATH or vim.env.LUA_PATH == "" then
    local handle = io.popen("luarocks path --lr-path 2>/dev/null")
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and result ~= "" then
        -- Remove trailing newline and append default paths
        result = result:gsub("[\n\r]", "") .. ";;"
        package.path = result .. package.path
      end
    end
  end

  if not vim.env.LUA_CPATH or vim.env.LUA_CPATH == "" then
    local handle = io.popen("luarocks path --lr-cpath 2>/dev/null")
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and result ~= "" then
        -- Remove trailing newline and append default paths
        result = result:gsub("[\n\r]", "") .. ";;"
        package.cpath = result .. package.cpath
      end
    end
  end
end

-- Setup paths and load luacov for coverage tracking
setup_luacov_paths()

-- Load luacov before any other code
local has_luacov, luacov = pcall(require, "luacov")
if has_luacov then
  vim.notify("LuaCov loaded for coverage tracking", vim.log.levels.DEBUG)

  -- Ensure stats are flushed on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      local runner = require("luacov.runner")
      if runner and runner.save_stats then
        runner.save_stats()
      end
    end,
  })
else
  vim.notify("LuaCov not available (install with: luarocks install luacov)", vim.log.levels.DEBUG)
end

-- Set up isolated test environment
vim.env.LAZY_STDPATH = ".tests"

-- Bootstrap lazy.nvim
-- Prefer local development copy if available (via LAZY_PATH env var), otherwise download
if vim.env.LAZY_PATH then
  local bootstrap_path = vim.env.LAZY_PATH .. "/bootstrap.lua"
  if vim.fn.isdirectory(vim.env.LAZY_PATH) == 1 and vim.fn.filereadable(bootstrap_path) == 1 then
    vim.notify("Using local lazy.nvim from: " .. vim.env.LAZY_PATH, vim.log.levels.INFO)
    loadfile(bootstrap_path)()
  else
    error("LAZY_PATH is set but bootstrap.lua not found at: " .. bootstrap_path)
  end
else
  -- Download and run bootstrap
  vim.notify("Downloading lazy.nvim bootstrap...", vim.log.levels.INFO)
  local bootstrap_code = vim.fn.system({
    "curl",
    "-s",
    "https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua",
  })
  if vim.v.shell_error ~= 0 then
    error("Failed to download lazy.nvim bootstrap: " .. bootstrap_code)
  end
  load(bootstrap_code, "bootstrap.lua")()
end

-- Setup lazy.nvim with our plugin and test dependencies
require("lazy.minit").setup({
  spec = {
    -- Add mini.diff as a dependency for golf mode
    "echasnovski/mini.diff",

    -- Load buffergolf.nvim from current directory
    {
      dir = vim.uv.cwd(),
      name = "buffergolf.nvim",
      opts = {
        -- Test-specific config if needed
      },
    },
  },
})

-- The lazy.minit module will automatically:
-- 1. Detect the --minitest flag
-- 2. Install and setup mini.test + luassert
-- 3. Run all *_spec.lua files it finds
