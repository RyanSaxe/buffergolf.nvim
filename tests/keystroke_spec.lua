local Keystroke = require("buffergolf.session.keystroke")
local assert = require("luassert")

describe("keystroke tracking", function()
  local session

  before_each(function()
    -- Create a mock session with a real buffer
    local practice_buf = vim.api.nvim_create_buf(true, false)
    session = {
      practice_buf = practice_buf,
      origin_buf = 1,
      mode = "typing",
    }
  end)

  after_each(function()
    -- Cleanup the session
    if session and session.practice_buf then
      Keystroke.cleanup_session(session)
      if vim.api.nvim_buf_is_valid(session.practice_buf) then
        vim.api.nvim_buf_delete(session.practice_buf, { force = true })
      end
    end
  end)

  describe("init_session", function()
    it("initializes tracking for a session", function()
      Keystroke.init_session(session)

      -- Should start with count at 0
      assert.equal(0, Keystroke.get_count(session))

      -- Should have tracking enabled by default
      assert.is_true(Keystroke.is_tracking_enabled(session))
    end)

    it("handles nil session gracefully", function()
      assert.has_no_errors(function()
        Keystroke.init_session(nil)
      end)
    end)

    it("handles session without practice_buf gracefully", function()
      local bad_session = { origin_buf = 1 }
      assert.has_no_errors(function()
        Keystroke.init_session(bad_session)
      end)
      assert.equal(0, Keystroke.get_count(bad_session))
    end)
  end)

  describe("get_count and reset_count", function()
    it("tracks keystroke count", function()
      Keystroke.init_session(session)

      -- Manually increment count (simulating keystrokes)
      -- We can't easily trigger vim.on_key in tests, so we'll test the API
      assert.equal(0, Keystroke.get_count(session))

      -- Reset should set count to 0
      Keystroke.reset_count(session)
      assert.equal(0, Keystroke.get_count(session))
    end)

    it("returns 0 for uninitialized session", function()
      assert.equal(0, Keystroke.get_count(session))
    end)

    it("handles nil session in get_count", function()
      assert.equal(0, Keystroke.get_count(nil))
    end)

    it("handles nil session in reset_count", function()
      assert.has_no_errors(function()
        Keystroke.reset_count(nil)
      end)
    end)
  end)

  describe("tracking enabled/disabled", function()
    it("can enable and disable tracking", function()
      Keystroke.init_session(session)

      -- Should be enabled by default
      assert.is_true(Keystroke.is_tracking_enabled(session))

      -- Disable tracking
      Keystroke.set_tracking_enabled(session, false)
      assert.is_false(Keystroke.is_tracking_enabled(session))

      -- Re-enable tracking
      Keystroke.set_tracking_enabled(session, true)
      assert.is_true(Keystroke.is_tracking_enabled(session))
    end)

    it("returns false for uninitialized session", function()
      assert.is_false(Keystroke.is_tracking_enabled(session))
    end)

    it("handles nil session in tracking functions", function()
      assert.is_false(Keystroke.is_tracking_enabled(nil))

      assert.has_no_errors(function()
        Keystroke.set_tracking_enabled(nil, true)
      end)
    end)
  end)

  describe("with_keys_disabled", function()
    it("temporarily disables tracking during function execution", function()
      Keystroke.init_session(session)
      assert.is_true(Keystroke.is_tracking_enabled(session))

      local was_disabled_during_call = false
      Keystroke.with_keys_disabled(session, function()
        was_disabled_during_call = not Keystroke.is_tracking_enabled(session)
      end)

      assert.is_true(was_disabled_during_call)
      assert.is_true(Keystroke.is_tracking_enabled(session)) -- re-enabled after
    end)

    it("restores previous state after execution", function()
      Keystroke.init_session(session)
      Keystroke.set_tracking_enabled(session, false)

      Keystroke.with_keys_disabled(session, function()
        -- Should still be disabled
        assert.is_false(Keystroke.is_tracking_enabled(session))
      end)

      -- Should remain disabled (was disabled before)
      assert.is_false(Keystroke.is_tracking_enabled(session))
    end)

    it("propagates errors from wrapped function", function()
      Keystroke.init_session(session)

      local success, err = pcall(function()
        Keystroke.with_keys_disabled(session, function()
          error("test error")
        end)
      end)

      assert.is_false(success)
      assert.matches("test error", err)

      -- Should still restore tracking state
      assert.is_true(Keystroke.is_tracking_enabled(session))
    end)

    it("returns value from wrapped function", function()
      Keystroke.init_session(session)

      local result = Keystroke.with_keys_disabled(session, function()
        return "test value"
      end)

      assert.equal("test value", result)
    end)

    it("handles nil session", function()
      local called = false
      local result = Keystroke.with_keys_disabled(nil, function()
        called = true
        return "success"
      end)

      assert.is_true(called)
      assert.equal("success", result)
    end)
  end)

  describe("cleanup_session", function()
    it("cleans up session state", function()
      Keystroke.init_session(session)
      assert.equal(0, Keystroke.get_count(session))

      Keystroke.cleanup_session(session)

      -- After cleanup, should return 0 (no state)
      assert.equal(0, Keystroke.get_count(session))
      assert.is_false(Keystroke.is_tracking_enabled(session))
    end)

    it("handles nil session gracefully", function()
      assert.has_no_errors(function()
        Keystroke.cleanup_session(nil)
      end)
    end)

    it("handles session without practice_buf", function()
      local bad_session = { origin_buf = 1 }
      assert.has_no_errors(function()
        Keystroke.cleanup_session(bad_session)
      end)
    end)
  end)
end)
