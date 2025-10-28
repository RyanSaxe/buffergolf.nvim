#!/usr/bin/env -S nvim -l

-- Always try to load luacov for coverage tracking (if available)
-- This is lightweight and doesn't affect test performance
pcall(require, "luacov")

-- Set up isolated test environment
vim.env.LAZY_STDPATH = ".tests"
vim.env.LAZY_PATH = vim.env.LAZY_PATH or vim.fs.normalize("~/projects/lazy.nvim")

-- Bootstrap lazy.nvim
-- Prefer local development copy if available, otherwise download
local bootstrap_path = vim.env.LAZY_PATH .. "/bootstrap.lua"
if vim.fn.isdirectory(vim.env.LAZY_PATH) == 1 and vim.fn.filereadable(bootstrap_path) == 1 then
  vim.notify("Using local lazy.nvim from: " .. vim.env.LAZY_PATH, vim.log.levels.INFO)
  loadfile(bootstrap_path)()
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
