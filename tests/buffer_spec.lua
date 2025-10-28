local Buffer = require("buffergolf.session.buffer")
local assert = require("luassert")

describe("buffer utilities", function()
  describe("dedent_lines", function()
    it("removes common leading whitespace", function()
      local input = {
        "  function test()",
        "    return true",
        "  end",
      }
      local expected = {
        "function test()",
        "  return true",
        "end",
      }
      assert.same(expected, Buffer.dedent_lines(input))
    end)

    it("handles lines with no indent", function()
      local input = { "no indent", "  indented" }
      assert.same(input, Buffer.dedent_lines(input)) -- no common indent, returns as-is
    end)

    it("preserves empty and whitespace-only lines", function()
      local input = {
        "  code",
        "",
        "    ",
        "  more",
      }
      local expected = {
        "code",
        "",
        "    ", -- whitespace-only lines are preserved as-is
        "more",
      }
      assert.same(expected, Buffer.dedent_lines(input))
    end)

    it("handles empty input", function()
      assert.same({}, Buffer.dedent_lines({}))
    end)
  end)

  describe("strip_trailing_empty_lines", function()
    it("removes trailing empty lines", function()
      local input = { "text", "", "more", "", "" }
      local expected = { "text", "", "more" }
      assert.same(expected, Buffer.strip_trailing_empty_lines(input))
    end)

    it("preserves non-trailing empty lines", function()
      local input = { "text", "", "more" }
      assert.same(input, Buffer.strip_trailing_empty_lines(input))
    end)

    it("handles all empty lines", function()
      assert.same({}, Buffer.strip_trailing_empty_lines({ "", "", "" }))
    end)

    it("handles no trailing empty lines", function()
      local input = { "one", "two", "three" }
      assert.same(input, Buffer.strip_trailing_empty_lines(input))
    end)
  end)

  describe("prepare_lines", function()
    it("applies dedent when auto_dedent is true", function()
      local config = { auto_dedent = true }
      local input = { "  indented", "    more" }
      local expected = { "indented", "  more" }

      assert.same(expected, Buffer.prepare_lines(input, nil, config))
    end)

    it("skips dedent when auto_dedent is false", function()
      local config = { auto_dedent = false }
      local input = { "  indented", "    more" }

      assert.same(input, Buffer.prepare_lines(input, nil, config))
    end)

    it("skips dedent when auto_dedent not specified", function()
      local config = {}
      local input = { "  indented" }

      assert.same(input, Buffer.prepare_lines(input, nil, config))
    end)
  end)

  describe("generate_buffer_name", function()
    it("generates name for unnamed buffer with filetype", function()
      -- Create a mock buffer
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })

      local name = Buffer.generate_buffer_name(buf, "_practice")
      assert.matches("unnamed_practice%.lua", name)

      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("generates name for unnamed buffer without filetype", function()
      local buf = vim.api.nvim_create_buf(true, false)

      local name = Buffer.generate_buffer_name(buf, "_practice")
      assert.matches("unnamed_practice%.txt", name)

      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("generates name for named buffer", function()
      local buf = vim.api.nvim_create_buf(true, false)
      -- Set a buffer name
      vim.api.nvim_buf_set_name(buf, "/tmp/test.lua")

      local name = Buffer.generate_buffer_name(buf, ".practice")
      -- On macOS, /tmp is a symlink to /private/tmp
      assert.matches("test%.practice%.lua$", name)

      -- Cleanup
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
