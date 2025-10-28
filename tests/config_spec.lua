local Config = require("buffergolf.config")
local assert = require("luassert")

describe("config", function()
  -- Reset config before each test
  before_each(function()
    -- Clear the config to defaults
    Config.setup({})
  end)

  describe("setup", function()
    it("uses default values when no opts provided", function()
      Config.setup()
      local config = Config.get()

      -- Check a few key defaults
      assert.equal("auto", config.disabled_plugins)
      assert.equal(true, config.auto_dedent)
      assert.equal("<leader>bg", config.keymaps.toggle)
      assert.equal("right", config.windows.reference.position)
    end)

    it("merges user config with defaults", function()
      Config.setup({
        auto_dedent = false,
        keymaps = {
          toggle = "<C-b>",
        },
      })

      local config = Config.get()

      -- User overrides should be applied
      assert.equal(false, config.auto_dedent)
      assert.equal("<C-b>", config.keymaps.toggle)

      -- Other defaults should remain
      assert.equal("auto", config.disabled_plugins)
      assert.equal("<leader>bG", config.keymaps.countdown)
    end)

    it("validates disabled_plugins configuration", function()
      -- Should accept "auto"
      assert.has_no_errors(function()
        Config.setup({ disabled_plugins = "auto" })
      end)

      -- Should accept table
      assert.has_no_errors(function()
        Config.setup({ disabled_plugins = { matchparen = true } })
      end)

      -- Should reject invalid string
      assert.has_error(function()
        Config.setup({ disabled_plugins = "invalid" })
      end, "disabled_plugins must be 'auto'")

      -- Should reject invalid type
      assert.has_error(function()
        Config.setup({ disabled_plugins = 123 })
      end, "disabled_plugins must be 'auto' or a table")
    end)
  end)

  describe("get_mode_config", function()
    it("applies mode-specific overrides with inheritance", function()
      Config.setup({
        disabled_plugins = { diagnostics = true },
        typing_mode = {
          disabled_plugins = {
            _inherit = true,
            matchparen = true,
          },
        },
      })

      local typing_config = Config.get_mode_config("typing")

      -- Should inherit base disabled_plugins and add mode-specific ones
      assert.is_table(typing_config.disabled_plugins)
      assert.equal(true, typing_config.disabled_plugins.diagnostics) -- inherited
      assert.equal(true, typing_config.disabled_plugins.matchparen) -- mode-specific
    end)

    it("replaces config when _inherit is false", function()
      Config.setup({
        disabled_plugins = { diagnostics = true },
        golf_mode = {
          disabled_plugins = {
            _inherit = false,
            matchparen = false,
          },
        },
      })

      local golf_config = Config.get_mode_config("golf")

      -- Should NOT inherit, only have mode-specific
      assert.equal(false, golf_config.disabled_plugins.matchparen)
      assert.is_nil(golf_config.disabled_plugins.diagnostics) -- not inherited
    end)

    it("returns base config when mode config not defined", function()
      Config.setup({
        auto_dedent = false,
        disabled_plugins = "auto",
      })

      local unknown_config = Config.get_mode_config("unknown")

      -- Should return a copy of the base config
      assert.equal(false, unknown_config.auto_dedent)
      assert.equal("auto", unknown_config.disabled_plugins)
    end)
  end)

  describe("merge_disabled_plugins", function()
    it("handles string override", function()
      local result = Config.merge_disabled_plugins({ foo = true }, "auto")
      assert.equal("auto", result)
    end)

    it("inherits from base when _inherit is true", function()
      local base = { diagnostics = true, inlay_hints = false }
      local override = { _inherit = true, matchparen = true }

      local result = Config.merge_disabled_plugins(base, override)

      assert.equal(true, result.diagnostics) -- inherited
      assert.equal(false, result.inlay_hints) -- inherited
      assert.equal(true, result.matchparen) -- from override
      assert.is_nil(result._inherit) -- _inherit flag removed
    end)

    it("replaces base when _inherit is not set", function()
      local base = { diagnostics = true }
      local override = { matchparen = false }

      local result = Config.merge_disabled_plugins(base, override)

      assert.equal(false, result.matchparen)
      assert.is_nil(result.diagnostics) -- not inherited without _inherit
    end)
  end)
end)
