local assert = require("luassert")
local mock = require("luassert.mock")

describe("session lifecycle", function()
  local lifecycle
  local mocks = {}

  before_each(function()
    -- Mock ALL dependencies to isolate lifecycle logic
    mocks.storage = mock(require("buffergolf.session.storage"), true)
    mocks.keystroke = mock(require("buffergolf.session.keystroke"), true)
    mocks.timer = mock(require("buffergolf.timer.control"), true)
    mocks.visual = mock(require("buffergolf.session.visual"), true)
    mocks.autocmds = mock(require("buffergolf.session.autocmds"), true)
    mocks.buffer = mock(require("buffergolf.session.buffer"), true)
    mocks.config = mock(require("buffergolf.config"), true)

    -- Mock defer_fn to execute immediately for testing
    vim.defer_fn = function(fn, _)
      fn()
    end

    -- Set up minimal config mock response
    mocks.config.get.returns({
      disabled_plugins = "auto",
      auto_dedent = false,
      keymaps = { golf = {} },
    })

    -- Set up buffer mock responses
    mocks.buffer.buf_valid.returns(true)
    mocks.buffer.win_valid.returns(true)
    mocks.buffer.generate_buffer_name.returns("test.practice.lua")
    mocks.buffer.prepare_lines.returns({ "test line" })
    -- normalize_lines is crucial - it processes the reference lines
    mocks.buffer.normalize_lines = function(lines, _)
      return lines or {}
    end

    -- Load lifecycle after mocks are set up
    package.loaded["buffergolf.session.lifecycle"] = nil
    lifecycle = require("buffergolf.session.lifecycle")
  end)

  after_each(function()
    -- Restore all mocks
    for _, m in pairs(mocks) do
      mock.revert(m)
    end

    -- Clean up package cache
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

      -- Verify cleanup functions were called
      assert.stub(mocks.timer.cleanup).was_called()
      assert.stub(mocks.keystroke.cleanup_session).was_called()
      assert.stub(mocks.storage.clear).was_called()

      -- Verify state was cleared
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

      -- Make timer.cleanup throw an error
      mocks.timer.cleanup.invokes(function()
        error("cleanup failed")
      end)

      -- Should not throw, other cleanup should still happen
      assert.has_no_errors(function()
        lifecycle.clear_state(session)
      end)

      -- Other cleanup should still be called
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

      -- Mock storage to return our session
      mocks.storage.get.returns(session)

      -- Create mock windows/buffers
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

      lifecycle.stop(1) -- Stop by origin buffer

      -- Verify session was retrieved and cleared
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
      -- Cleanup functions should not be called
      assert.stub(mocks.timer.cleanup).was_not_called()
    end)
  end)

  describe("basic start flow", function()
    it("creates a typing session with minimal setup", function()
      local origin_buf = vim.api.nvim_create_buf(true, false)
      local practice_buf = vim.api.nvim_create_buf(true, false)

      -- Mock that no session exists yet
      mocks.storage.is_active.returns(false)

      -- Mock buffer creation
      local orig_create_buf = vim.api.nvim_create_buf
      vim.api.nvim_create_buf = function()
        return practice_buf
      end

      -- Mock window functions
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

      -- Mock copy_indent_options
      mocks.buffer.copy_indent_options = function() end

      local test_config = { auto_dedent = false }
      local target_lines = { "hello", "world" }

      -- The start function doesn't return anything, it just creates the session
      lifecycle.start(origin_buf, test_config, target_lines)

      -- Verify key components were initialized
      assert.stub(mocks.storage.store).was_called()
      assert.stub(mocks.keystroke.init_session).was_called()
      assert.stub(mocks.timer.init).was_called()
      assert.stub(mocks.visual.refresh).was_called()
      assert.stub(mocks.autocmds.setup).was_called()

      -- Verify a session was stored
      assert.stub(mocks.storage.store).was_called(1)

      -- Get the session that was stored to verify its properties
      local stored_call = mocks.storage.store.calls[1]
      if stored_call then
        local stored_session = stored_call.vals[1]
        assert.equal("typing", stored_session.mode)
        assert.equal(origin_buf, stored_session.origin_buf)
        assert.equal(practice_buf, stored_session.practice_buf)
        assert.same({ "hello", "world" }, stored_session.reference_lines)
      end

      -- Cleanup
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
