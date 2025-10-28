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
      assert.same(input, Buffer.dedent_lines(input))
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
        "    ",
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
    local cases = {
      { auto_dedent = true, input = { "  indented", "    more" }, expected = { "indented", "  more" } },
      { auto_dedent = false, input = { "  indented", "    more" }, expected = { "  indented", "    more" } },
      { auto_dedent = nil, input = { "  indented" }, expected = { "  indented" } },
    }

    for _, case in ipairs(cases) do
      it(string.format("dedents when auto_dedent=%s", case.auto_dedent), function()
        local config = { auto_dedent = case.auto_dedent }
        assert.same(case.expected, Buffer.prepare_lines(case.input, nil, config))
      end)
    end
  end)

  describe("generate_buffer_name", function()
    it("generates name for unnamed buffer with filetype", function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })

      local name = Buffer.generate_buffer_name(buf, "_practice")
      assert.matches("unnamed_practice%.lua", name)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("generates name for unnamed buffer without filetype", function()
      local buf = vim.api.nvim_create_buf(true, false)

      local name = Buffer.generate_buffer_name(buf, "_practice")
      assert.matches("unnamed_practice%.txt", name)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("generates name for named buffer", function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, "/tmp/test.lua")

      local name = Buffer.generate_buffer_name(buf, ".practice")
      assert.matches("test%.practice%.lua$", name)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
