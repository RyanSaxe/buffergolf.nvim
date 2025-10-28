local Keystroke = require("buffergolf.session.keystroke")
local assert = require("luassert")
local helpers = require("tests.helpers")

describe("keystroke tracking", function()
  local session

  before_each(function()
    local practice_buf = vim.api.nvim_create_buf(true, false)
    session = {
      practice_buf = practice_buf,
      origin_buf = 1,
      mode = "typing",
    }
  end)

  after_each(function()
    if session then
      Keystroke.cleanup_session(session)
      helpers.cleanup_session(session)
    end
  end)

  describe("init_session", function()
    it("initializes with tracking enabled and count at 0", function()
      Keystroke.init_session(session)

      assert.equal(0, Keystroke.get_count(session))
      assert.is_true(Keystroke.is_tracking_enabled(session))
    end)

    it("handles session without practice_buf", function()
      local bad_session = { origin_buf = 1 }
      assert.has_no_errors(function()
        Keystroke.init_session(bad_session)
      end)
      assert.equal(0, Keystroke.get_count(bad_session))
    end)
  end)

  describe("get_count and reset_count", function()
    it("returns 0 for uninitialized session", function()
      assert.equal(0, Keystroke.get_count(session))
    end)

    it("resets count to 0", function()
      Keystroke.init_session(session)
      Keystroke.reset_count(session)
      assert.equal(0, Keystroke.get_count(session))
    end)
  end)

  describe("tracking enabled/disabled", function()
    it("toggles tracking state", function()
      Keystroke.init_session(session)

      assert.is_true(Keystroke.is_tracking_enabled(session))

      Keystroke.set_tracking_enabled(session, false)
      assert.is_false(Keystroke.is_tracking_enabled(session))

      Keystroke.set_tracking_enabled(session, true)
      assert.is_true(Keystroke.is_tracking_enabled(session))
    end)

    it("returns false for uninitialized session", function()
      assert.is_false(Keystroke.is_tracking_enabled(session))
    end)
  end)

  describe("with_keys_disabled", function()
    it("disables tracking during function execution", function()
      Keystroke.init_session(session)

      local disabled = false
      Keystroke.with_keys_disabled(session, function()
        disabled = not Keystroke.is_tracking_enabled(session)
      end)

      assert.is_true(disabled)
      assert.is_true(Keystroke.is_tracking_enabled(session))
    end)

    it("restores previous state after execution", function()
      Keystroke.init_session(session)
      Keystroke.set_tracking_enabled(session, false)

      Keystroke.with_keys_disabled(session, function()
        assert.is_false(Keystroke.is_tracking_enabled(session))
      end)

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
      assert.is_true(Keystroke.is_tracking_enabled(session))
    end)

    it("returns value from wrapped function", function()
      Keystroke.init_session(session)

      local result = Keystroke.with_keys_disabled(session, function()
        return "test value"
      end)

      assert.equal("test value", result)
    end)
  end)

  describe("cleanup_session", function()
    it("cleans up session state", function()
      Keystroke.init_session(session)

      Keystroke.cleanup_session(session)

      assert.equal(0, Keystroke.get_count(session))
      assert.is_false(Keystroke.is_tracking_enabled(session))
    end)

    it("handles session without practice_buf", function()
      local bad_session = { origin_buf = 1 }
      assert.has_no_errors(function()
        Keystroke.cleanup_session(bad_session)
      end)
    end)
  end)

  describe("nil handling", function()
    it("handles nil safely", function()
      assert.has_no_errors(function()
        Keystroke.init_session(nil)
        Keystroke.reset_count(nil)
        Keystroke.set_tracking_enabled(nil, true)
        Keystroke.cleanup_session(nil)
      end)

      assert.equal(0, Keystroke.get_count(nil))
      assert.is_false(Keystroke.is_tracking_enabled(nil))

      local result = Keystroke.with_keys_disabled(nil, function()
        return "success"
      end)
      assert.equal("success", result)
    end)
  end)
end)
