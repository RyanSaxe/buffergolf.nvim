#!/usr/bin/env -S nvim -l

-- Setup package paths for luacov when running with nvim -l
local function setup_luacov_paths()
  -- Get luarocks paths if not already set
  if not vim.env.LUA_PATH or vim.env.LUA_PATH == "" then
    local handle = io.popen("luarocks path --lr-path 2>/dev/null")
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result and result ~= "" then
        result = result:gsub("[\n\r]+$", "") .. ";;"
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
        result = result:gsub("[\n\r]+$", "") .. ";;"
        package.cpath = result .. package.cpath
      end
    end
  end
end

-- Load luacov for coverage tracking
setup_luacov_paths()
local has_luacov = pcall(require, "luacov")
if has_luacov then
  -- Ensure stats are flushed on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      local runner = require("luacov.runner")
      if runner and runner.save_stats then
        runner.save_stats()
      end
    end,
  })
end

-- Set up isolated test environment
vim.env.LAZY_STDPATH = ".tests"

-- Bootstrap lazy.nvim
if vim.env.LAZY_PATH then
  local bootstrap_path = vim.env.LAZY_PATH .. "/bootstrap.lua"
  if vim.fn.isdirectory(vim.env.LAZY_PATH) == 1 and vim.fn.filereadable(bootstrap_path) == 1 then
    loadfile(bootstrap_path)()
  else
    error("LAZY_PATH is set but bootstrap.lua not found at: " .. bootstrap_path)
  end
else
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

-- Setup lazy.nvim with test dependencies
require("lazy.minit").setup({
  spec = {
    "echasnovski/mini.diff",
    {
      "echasnovski/mini.test",
      rocks = { "luassert" },
    },
    {
      dir = vim.uv.cwd(),
      name = "buffergolf.nvim",
      opts = {},
    },
  },
  rocks = {
    enabled = true,
  },
})
