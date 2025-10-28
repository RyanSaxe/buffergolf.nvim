local Aggregate = require("buffergolf.stats.aggregate")
local assert = require("luassert")
local helpers = require("tests.helpers")

describe("stats aggregate", function()
  local session

  before_each(function()
    session = helpers.create_mock_session("typing")
    session.reference_lines = { "hello world" }
    session.timer_state.start_time = vim.uv.hrtime() - (60 * 1000000000)
    vim.api.nvim_buf_set_lines(session.practice_buf, 0, -1, false, { "hello world" })
  end)

  after_each(function()
    helpers.cleanup_session(session)
  end)

  describe("get_stats", function()
    it("returns all stats with correct types and values", function()
      local stats = Aggregate.get_stats(session)

      assert.is_number(stats.correct_chars)
      assert.is_number(stats.wpm)
      assert.is_number(stats.keystrokes)
      assert.is_number(stats.par)

      assert.equal(11, stats.correct_chars)
      assert.equal(12, stats.par)
      assert.equal(0, stats.keystrokes)
    end)

    it("uses pre-calculated par if available", function()
      session.par = 42

      local stats = Aggregate.get_stats(session)

      assert.equal(42, stats.par)
    end)

    it("calculates par if not available", function()
      session.par = nil

      local stats = Aggregate.get_stats(session)

      assert.equal(12, stats.par)
    end)

    it("counts correct characters", function()
      local stats = Aggregate.get_stats(session)
      assert.equal(11, stats.correct_chars)
    end)

    it("returns zero for empty values", function()
      vim.api.nvim_buf_set_lines(session.practice_buf, 0, -1, false, { "" })
      session.timer_state.frozen_keystrokes = nil

      local stats = Aggregate.get_stats(session)

      assert.equal(0, stats.correct_chars)
      assert.equal(0, stats.keystrokes)
    end)

    it("calculates WPM", function()
      local stats = Aggregate.get_stats(session)
      assert.is_near(2.2, stats.wpm, 0.1)
    end)

    it("uses frozen keystroke count when available", function()
      session.timer_state.frozen_keystrokes = 100

      local stats = Aggregate.get_stats(session)

      assert.equal(100, stats.keystrokes)
    end)

    it("handles golf mode session", function()
      session.mode = "golf"
      session.start_lines = { "original" }
      session.reference_lines = { "modified" }

      local stats = Aggregate.get_stats(session)

      assert.is_number(stats.correct_chars)
      assert.is_number(stats.wpm)
      assert.is_number(stats.keystrokes)
      assert.is_number(stats.par)
    end)

    it("handles zero elapsed time", function()
      session.timer_state.elapsed = 0

      local stats = Aggregate.get_stats(session)

      assert.equal(0, stats.wpm)
      assert.is_number(stats.correct_chars)
      assert.is_number(stats.keystrokes)
      assert.is_number(stats.par)
    end)
  end)
end)
