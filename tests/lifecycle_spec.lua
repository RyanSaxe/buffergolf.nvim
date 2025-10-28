local assert = require("luassert")
local mock = require("luassert.mock")

local function setup_lifecycle_mocks()
  local m = {}
  m.storage = mock(require("buffergolf.session.storage"), true)
  m.keystroke = mock(require("buffergolf.session.keystroke"), true)
  m.timer = mock(require("buffergolf.timer.control"), true)
  m.visual = mock(require("buffergolf.session.visual"), true)
  m.autocmds = mock(require("buffergolf.session.autocmds"), true)
  m.buffer = mock(require("buffergolf.session.buffer"), true)
  m.config = mock(require("buffergolf.config"), true)

  m.config.get.returns({
    disabled_plugins = "auto",
    auto_dedent = false,
    keymaps = { golf = {} },
  })

  m.buffer.buf_valid.returns(true)
  m.buffer.win_valid.returns(true)
  m.buffer.generate_buffer_name.returns("test.practice.lua")
  m.buffer.prepare_lines.returns({ "test line" })
  m.buffer.normalize_lines = function(lines, _)
    return lines or {}
  end

  return m
end

describe("session lifecycle", function()
  local lifecycle
  local mocks = {}

  before_each(function()
    mocks = setup_lifecycle_mocks()

    vim.defer_fn = function(fn, _)
      fn()
    end

    package.loaded["buffergolf.session.lifecycle"] = nil
    lifecycle = require("buffergolf.session.lifecycle")
  end)

  after_each(function()
    for _, m in pairs(mocks) do
      mock.revert(m)
    end

    package.loaded["buffergolf.session.lifecycle"] = nil
  end)

  describe("clear_state", function()
    it("cleans up all session resources", function()
      local session = {
        practice_buf = 1,
        reference_buf = 2,
        practice_win = 1001,
        augroup = 100,
        change_attached = true,
        mode = "typing",
      }

      lifecycle.clear_state(session)

      assert.stub(mocks.timer.cleanup).was_called()
      assert.stub(mocks.keystroke.cleanup_session).was_called()
      assert.stub(mocks.storage.clear).was_called()

      assert.is_nil(session.change_attached)
      assert.is_nil(session.refreshing)
      assert.is_nil(session.refresh_scheduled)
      assert.is_nil(session.on_keystroke)
    end)

    it("handles cleanup errors gracefully", function()
      local session = {
        practice_buf = 1,
        mode = "typing",
      }

      mocks.timer.cleanup.invokes(function()
        error("cleanup failed")
      end)

      assert.has_no_errors(function()
        lifecycle.clear_state(session)
      end)

      assert.stub(mocks.keystroke.cleanup_session).was_called()
      assert.stub(mocks.storage.clear).was_called()
    end)
  end)

  describe("stop", function()
    it("stops an active session", function()
      local session = {
        origin_buf = 1,
        practice_buf = 2,
        practice_win = 1001,
        mode = "typing",
      }

      mocks.storage.get.returns(session)

      local current_win = 1000
      vim.api.nvim_get_current_win = function()
        return current_win
      end
      vim.api.nvim_win_is_valid = function(win)
        return win == 1001
      end
      vim.api.nvim_buf_is_valid = function(buf)
        return buf <= 2
      end
      vim.api.nvim_win_get_buf = function()
        return 2
      end
      vim.api.nvim_set_current_win = function() end
      vim.api.nvim_buf_delete = function() end

      lifecycle.stop(1)

      assert.stub(mocks.storage.get).was_called_with(1)
      assert.stub(mocks.timer.cleanup).was_called()
      assert.stub(mocks.keystroke.cleanup_session).was_called()
      assert.stub(mocks.storage.clear).was_called()
    end)

    it("returns nil when no session exists", function()
      mocks.storage.get.returns(nil)

      local result = lifecycle.stop(999)

      assert.is_nil(result)
      assert.stub(mocks.storage.get).was_called_with(999)
      assert.stub(mocks.timer.cleanup).was_not_called()
    end)
  end)

  describe("basic start flow", function()
    it("creates a typing session", function()
      local origin_buf = vim.api.nvim_create_buf(true, false)
      local practice_buf = vim.api.nvim_create_buf(true, false)

      mocks.storage.is_active.returns(false)

      local orig_create_buf = vim.api.nvim_create_buf
      vim.api.nvim_create_buf = function()
        return practice_buf
      end

      vim.api.nvim_get_current_win = function()
        return 1000
      end
      vim.api.nvim_open_win = function()
        return 1001
      end
      vim.api.nvim_win_set_buf = function() end
      vim.api.nvim_set_current_win = function() end
      vim.api.nvim_buf_get_name = function()
        return ""
      end
      vim.api.nvim_buf_set_name = function() end
      vim.api.nvim_buf_set_lines = function() end
      vim.api.nvim_buf_get_lines = function()
        return { "hello", "world" }
      end
      vim.api.nvim_get_option_value = function()
        return ""
      end
      vim.api.nvim_set_option_value = function() end
      vim.api.nvim_create_augroup = function()
        return 100
      end
      vim.api.nvim_buf_attach = function()
        return true
      end
      vim.cmd = function() end

      mocks.buffer.copy_indent_options = function() end

      local test_config = { auto_dedent = false }
      local target_lines = { "hello", "world" }

      lifecycle.start(origin_buf, test_config, target_lines)

      assert.stub(mocks.storage.store).was_called()
      assert.stub(mocks.keystroke.init_session).was_called()
      assert.stub(mocks.timer.init).was_called()
      assert.stub(mocks.visual.refresh).was_called()
      assert.stub(mocks.autocmds.setup).was_called()

      local stored_call = mocks.storage.store.calls[1]
      if stored_call then
        local stored_session = stored_call.vals[1]
        assert.equal("typing", stored_session.mode)
        assert.equal(origin_buf, stored_session.origin_buf)
        assert.equal(practice_buf, stored_session.practice_buf)
        assert.same({ "hello", "world" }, stored_session.reference_lines)
      end

      vim.api.nvim_create_buf = orig_create_buf
      if vim.api.nvim_buf_is_valid(origin_buf) then
        vim.api.nvim_buf_delete(origin_buf, { force = true })
      end
      if vim.api.nvim_buf_is_valid(practice_buf) then
        vim.api.nvim_buf_delete(practice_buf, { force = true })
      end
    end)
  end)
end)
