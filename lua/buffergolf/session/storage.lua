local M = {}

local sessions_by_origin, sessions_by_practice = {}, {}

function M.get(bufnr)
  return sessions_by_origin[bufnr] or sessions_by_practice[bufnr]
end

function M.is_active(bufnr)
  return M.get(bufnr) ~= nil
end

function M.store(session)
  sessions_by_origin[session.origin_buf] = session
  sessions_by_practice[session.practice_buf] = session
end

function M.clear(session)
  sessions_by_origin[session.origin_buf] = nil
  sessions_by_practice[session.practice_buf] = nil
end

function M.by_practice(bufnr)
  return sessions_by_practice[bufnr]
end

return M
