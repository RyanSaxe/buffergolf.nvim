-- Session actions
local storage = require("buffergolf.session.storage")
local timer = require("buffergolf.timer.control")

local M = {}

function M.start_countdown(bufnr, seconds)
  local session = storage.get(bufnr)
  if not session then
    vim.notify("No active buffergolf session", vim.log.levels.WARN, { title = "buffergolf" })
    return false
  end
  timer.start_countdown(session, seconds)
  return true
end

function M.pause_session(bufnr)
  local session = storage.get(bufnr)
  if not session then
    vim.notify("No active buffergolf session", vim.log.levels.WARN, { title = "buffergolf" })
    return false
  end

  if session.timer_state and session.timer_state.start_time then
    session.timer_state.paused = true
    session.timer_state.pause_time = vim.uv.hrtime()
    return true
  end

  return false
end

function M.resume_session(bufnr)
  local session = storage.get(bufnr)
  if not session then
    vim.notify("No active buffergolf session", vim.log.levels.WARN, { title = "buffergolf" })
    return false
  end

  if session.timer_state and session.timer_state.paused then
    local pause_duration = vim.uv.hrtime() - session.timer_state.pause_time
    session.timer_state.start_time = session.timer_state.start_time + pause_duration
    session.timer_state.paused = false
    session.timer_state.pause_time = nil
    return true
  end

  return false
end

function M.get_session_info(bufnr)
  local session = storage.get(bufnr)
  if not session then
    return nil
  end

  return {
    mode = session.mode,
    origin_buf = session.origin_buf,
    practice_buf = session.practice_buf,
    has_reference = session.reference_buf ~= nil,
    is_active = true,
    paused = session.timer_state and session.timer_state.paused or false,
  }
end

return M
