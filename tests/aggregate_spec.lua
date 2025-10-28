local Aggregate = require("buffergolf.stats.aggregate")
local assert = require("luassert")

describe("stats aggregate", function()
  local session

  before_each(function()
    -- Create a mock session with the necessary fields
    local practice_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(practice_buf, 0, -1, false, { "hello world" })

    session = {
      practice_buf = practice_buf,
      reference_lines = { "hello world" },
      mode = "typing",
      timer_state = {
        start_time = vim.uv.hrtime() - (60 * 1000000000), -- Started 60 seconds ago
        elapsed = 60 * 1000000000, -- 60 seconds
        is_running = false,
        stats_frozen = false,
        frozen_keystrokes = nil,
      },
      par = nil, -- Will be calculated
    }
  end)

  after_each(function()
    if session and session.practice_buf then
      if vim.api.nvim_buf_is_valid(session.practice_buf) then
        vim.api.nvim_buf_delete(session.practice_buf, { force = true })
      end
    end
  end)

  describe("get_stats", function()
    it("aggregates all stats correctly", function()
      local stats = Aggregate.get_stats(session)

      -- Should have all expected fields
      assert.is_not_nil(stats.correct_chars)
      assert.is_not_nil(stats.wpm)
      assert.is_not_nil(stats.keystrokes)
      assert.is_not_nil(stats.par)

      -- Check types
      assert.is_number(stats.correct_chars)
      assert.is_number(stats.wpm)
      assert.is_number(stats.keystrokes)
      assert.is_number(stats.par)
    end)

    it("uses pre-calculated par if available", function()
      session.par = 42

      local stats = Aggregate.get_stats(session)

      assert.equal(42, stats.par)
    end)

    it("calculates par if not available", function()
      session.par = nil

      local stats = Aggregate.get_stats(session)

      -- Should calculate par (typing mode: chars + 1 for insert mode)
      -- "hello world" = 11 chars + 1 = 12
      assert.equal(12, stats.par)
    end)

    it("returns correct character count for matching text", function()
      -- Practice buffer matches reference
      local stats = Aggregate.get_stats(session)

      -- All 11 characters match
      assert.equal(11, stats.correct_chars)
    end)

    it("returns zero characters for empty practice buffer", function()
      vim.api.nvim_buf_set_lines(session.practice_buf, 0, -1, false, { "" })

      local stats = Aggregate.get_stats(session)

      assert.equal(0, stats.correct_chars)
    end)

    it("calculates WPM correctly", function()
      -- 11 chars / 5 = 2.2 words
      -- 2.2 words / 1 minute = 2.2 WPM
      local stats = Aggregate.get_stats(session)

      -- WPM calculation
      assert.is_true(stats.wpm > 0)
    end)

    it("uses frozen keystroke count when available", function()
      session.timer_state.frozen_keystrokes = 100

      local stats = Aggregate.get_stats(session)

      assert.equal(100, stats.keystrokes)
    end)

    it("returns zero keystrokes when no frozen count", function()
      session.timer_state.frozen_keystrokes = nil

      local stats = Aggregate.get_stats(session)

      -- No keystroke tracking initialized, should be 0
      assert.equal(0, stats.keystrokes)
    end)

    it("handles golf mode session", function()
      session.mode = "golf"
      session.start_lines = { "original" }
      session.reference_lines = { "modified" }

      local stats = Aggregate.get_stats(session)

      -- Should still return all stats
      assert.is_not_nil(stats.correct_chars)
      assert.is_not_nil(stats.wpm)
      assert.is_not_nil(stats.keystrokes)
      assert.is_not_nil(stats.par)
    end)

    it("handles session with zero elapsed time", function()
      session.timer_state.start_time = vim.uv.hrtime() -- Just started
      session.timer_state.elapsed = 0

      local stats = Aggregate.get_stats(session)

      -- Should handle gracefully
      assert.equal(0, stats.wpm) -- No time elapsed, WPM is 0
      assert.is_number(stats.correct_chars)
      assert.is_number(stats.keystrokes)
      assert.is_number(stats.par)
    end)
  end)
end)
