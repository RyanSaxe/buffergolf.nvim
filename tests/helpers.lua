local M = {}

-- Reset buffer to a clean state
function M.reset_buffer(lines)
  -- Exit any mode and create new buffer
  vim.api.nvim_feedkeys(vim.keycode("<Ignore><C-\\><C-n><esc>"), "nx", false)
  vim.cmd("enew!")

  -- Only close other windows if there are multiple windows
  if #vim.api.nvim_list_wins() > 1 then
    vim.cmd("only")
  end

  -- Set buffer content if provided
  if lines then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end

  -- Clear any active buffergolf sessions
  local Storage = require("buffergolf.session.storage")
  Storage._sessions = {}
end

-- Create a test buffer with content
function M.create_buffer(lines, name)
  local buf = vim.api.nvim_create_buf(true, false)

  if name then
    vim.api.nvim_buf_set_name(buf, name)
  end

  if lines then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  return buf
end

-- Feed keys and wait for them to process
function M.feed(keys, mode)
  mode = mode or "n"
  vim.api.nvim_feedkeys(vim.keycode(keys), mode, false)
  vim.wait(10)
end

-- Wait for a condition to be true
function M.wait_for(condition, timeout, message)
  timeout = timeout or 1000
  local start = vim.loop.hrtime() / 1000000

  while not condition() do
    vim.wait(10)
    if vim.loop.hrtime() / 1000000 - start > timeout then
      error(message or "Timeout waiting for condition")
    end
  end
end

-- Get visible text in buffer (excluding virttext)
function M.get_buffer_lines(bufnr)
  bufnr = bufnr or 0
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

-- Check if virtual text exists at position
function M.has_virttext_at(bufnr, row, col, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { row, col }, { row, col + 1 }, { details = true })

  for _, mark in ipairs(extmarks) do
    if mark[4].virt_text and #mark[4].virt_text > 0 then
      return true
    end
  end

  return false
end

-- Get virtual text at position
function M.get_virttext_at(bufnr, row, ns_id)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { row, 0 }, { row, -1 }, { details = true })

  local result = {}
  for _, mark in ipairs(extmarks) do
    if mark[4].virt_text then
      for _, chunk in ipairs(mark[4].virt_text) do
        table.insert(result, chunk[1])
      end
    end
  end

  return table.concat(result, "")
end

-- Create a mock session for testing
function M.create_mock_session(mode, config)
  mode = mode or "typing"
  config = config or {}

  local session = {
    mode = mode,
    config = config,
    origin_buf = vim.api.nvim_get_current_buf(),
    origin_win = vim.api.nvim_get_current_win(),
    practice_buf = vim.api.nvim_create_buf(true, false),
    ns_ghost = vim.api.nvim_create_namespace("buffergolf_test_ghost"),
    ns_mismatch = vim.api.nvim_create_namespace("buffergolf_test_mismatch"),
    reference_lines = { "test", "reference", "lines" },
    ghost_marks = {},
    keystroke_count = 0,
    timer_state = {
      start_time = vim.loop.hrtime(),
      elapsed = 0,
      is_running = false,
      stats_frozen = false,
    },
  }

  if mode == "golf" then
    session.start_lines = { "start", "lines" }
    session.reference_buf = vim.api.nvim_create_buf(true, false)
  end

  return session
end

-- Cleanup a session's buffers
function M.cleanup_session(session)
  if not session then
    return
  end
  if session.practice_buf and vim.api.nvim_buf_is_valid(session.practice_buf) then
    pcall(vim.api.nvim_buf_delete, session.practice_buf, { force = true })
  end
  if session.reference_buf and vim.api.nvim_buf_is_valid(session.reference_buf) then
    pcall(vim.api.nvim_buf_delete, session.reference_buf, { force = true })
  end
end

-- Cleanup any leftover test state
function M.cleanup()
  -- Close all windows except current
  if #vim.api.nvim_list_wins() > 1 then
    vim.cmd("only")
  end

  -- Clear all buffers except current
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= vim.api.nvim_get_current_buf() and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  -- Clear session storage
  local Storage = require("buffergolf.session.storage")
  Storage._sessions = {}

  -- Reset to normal mode
  vim.cmd("stopinsert")
end

return M
