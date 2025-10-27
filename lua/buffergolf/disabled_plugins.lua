local M = {}

local function create_ctx(opts)
  return setmetatable(opts, {
    __index = {
      set_var = function(self, k, v)
        vim.b[self.buf][k] = v
      end,
      set_opt = function(self, k, v)
        vim.api.nvim_set_option_value(k, v, { buf = self.buf })
      end,
    },
  })
end

M.registry = {
  diagnostics = {
    detect = function()
      return true
    end,
    disable = function(ctx)
      vim.diagnostic.enable(false, { bufnr = ctx.buf })
    end,
  },
  inlay_hints = {
    detect = function()
      return vim.lsp.inlay_hint
    end,
    disable = function(ctx)
      vim.lsp.inlay_hint.enable(false, { bufnr = ctx.buf })
    end,
  },
  matchparen = {
    detect = function()
      return true
    end,
    disable = function(ctx)
      local wh = vim.wo[ctx.win].winhighlight
      vim.wo[ctx.win].winhighlight = wh and wh ~= "" and wh .. ",MatchParen:None" or "MatchParen:None"
      ctx:set_var("matchup_matchparen_enabled", 0)
    end,
  },
  copilot = {
    detect = function()
      return vim.g.loaded_copilot == 1
    end,
    disable = function(ctx)
      ctx:set_var("copilot_enabled", false)
      ctx:set_var("copilot_suggestion_auto_trigger", false)
    end,
  },
  codeium = {
    detect = function()
      return vim.g.loaded_codeium == 1
    end,
    disable = function(ctx)
      ctx:set_var("codeium_enabled", false)
      pcall(vim.cmd, "CodeiumDisable")
    end,
  },
  supermaven = {
    detect = function()
      return pcall(require, "supermaven-nvim")
    end,
    disable = function(ctx)
      ctx:set_var("supermaven_enabled", false)
      local ok, sm = pcall(require, "supermaven-nvim.api")
      if ok and sm.stop then
        sm.stop()
      end
    end,
  },
  cmp = {
    detect = function()
      return pcall(require, "cmp")
    end,
    disable = function(ctx)
      local ok, cmp = pcall(require, "cmp")
      if ok then
        cmp.setup.buffer({ enabled = false })
      end
    end,
  },
  blink = {
    detect = function()
      return pcall(require, "blink.cmp")
    end,
    disable = function(ctx)
      ctx:set_var("blink_cmp_enabled", false)
      pcall(vim.cmd, "BlinkDisable")
    end,
  },
  coq = {
    detect = function()
      return vim.g.loaded_coq == 1
    end,
    disable = function(ctx)
      ctx:set_var("coq_settings", { auto_start = false })
      pcall(vim.cmd, "COQstop")
    end,
  },
  autopairs = {
    detect = function()
      return pcall(require, "nvim-autopairs")
    end,
    disable = function(ctx)
      ctx:set_var("autopairs_enabled", false)
    end,
  },
  minipairs = {
    detect = function()
      return pcall(require, "mini.pairs")
    end,
    disable = function(ctx)
      ctx:set_var("minipairs_disable", true)
    end,
  },
  endwise = {
    detect = function()
      return vim.g.loaded_endwise == 1
    end,
    disable = function(ctx)
      ctx:set_var("endwise_enabled", false)
    end,
  },
  treesitter_context = {
    detect = function()
      return pcall(require, "treesitter-context")
    end,
    disable = function(ctx)
      ctx:set_var("treesitter_context_enabled", false)
      local ok, tsc = pcall(require, "treesitter-context")
      if ok and tsc.disable then
        tsc.disable()
      end
    end,
  },
  indent_blankline = {
    detect = function()
      return pcall(require, "ibl")
    end,
    disable = function(ctx)
      ctx:set_var("indent_blankline_enabled", false)
      local ok, ibl = pcall(require, "ibl")
      if ok and ibl.setup_buffer then
        ibl.setup_buffer(ctx.buf, { enabled = false })
      end
    end,
  },
  cursorline = {
    detect = function()
      return true
    end,
    disable = function(ctx)
      vim.wo[ctx.win].cursorline = false
      vim.wo[ctx.win].cursorcolumn = false
    end,
  },
  colorcolumn = {
    detect = function()
      return true
    end,
    disable = function(ctx)
      vim.wo[ctx.win].colorcolumn = ""
    end,
  },
  matchup = {
    detect = function()
      return vim.g.loaded_matchup == 1
    end,
    disable = function(ctx)
      ctx:set_var("matchup_matchparen_enabled", 0)
      ctx:set_var("matchup_surround_enabled", 0)
    end,
  },
  closetag = {
    detect = function()
      return vim.g.loaded_closetag == 1
    end,
    disable = function(ctx)
      ctx:set_var("closetag_disable", 1)
    end,
  },
}

local function apply_plugin(name, plugin, disabled, ctx)
  local should_disable = disabled._auto and disabled[name] ~= false or disabled[name] == true
  if should_disable and pcall(plugin.detect) then
    pcall(plugin.disable, ctx)
  end
end

function M.apply(config, ctx)
  local disabled = config and config.disabled_plugins
  if not disabled then
    return
  end

  if disabled == "auto" then
    for _, plugin in pairs(M.registry) do
      if pcall(plugin.detect) then
        pcall(plugin.disable, ctx)
      end
    end
  elseif type(disabled) == "table" then
    if disabled._auto then
      for name, plugin in pairs(M.registry) do
        apply_plugin(name, plugin, disabled, ctx)
      end
    end
    for name, value in pairs(disabled) do
      if name ~= "_auto" and name ~= "_inherit" then
        if type(value) == "function" then
          pcall(value, ctx)
        elseif value == true and M.registry[name] then
          apply_plugin(name, M.registry[name], { [name] = true }, ctx)
        end
      end
    end
  end
end

M.create_context = create_ctx

function M.register(name, handler)
  handler.detect = handler.detect or function()
    return true
  end
  M.registry[name] = handler
end

return M
