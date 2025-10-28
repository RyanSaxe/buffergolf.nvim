local M = {}

local active_sessions = {}

function M.init_session(session)
  if not session or not session.practice_buf then
    return
  end
  local practice_buf = session.practice_buf

  active_sessions[practice_buf] = {
    count = 0,
    tracking_enabled = true,
    session = session,
    command_depth = 0,
    depth_reset_timer = nil,
  }

  local ns = vim.api.nvim_create_namespace(("BuffergolfKeystroke_%d"):format(practice_buf))
  session.ns_keystroke = ns

  vim.on_key(function(raw_key)
    local ok, current_buf = pcall(vim.api.nvim_get_current_buf)
    if not ok or current_buf ~= practice_buf then
      return
    end

    local state = active_sessions[practice_buf]
    if not state or vim.fn.reg_executing() ~= "" then
      return
    end

    local key_name = vim.fn.keytrans(raw_key)
    if key_name == "<Ignore>" or key_name:match("^<.*Mouse.*>$") or raw_key == "" or key_name == "" then
      return
    end

    if state.command_depth == 0 then
      if state.tracking_enabled then
        state.count = state.count + 1
        if state.session and state.session.on_keystroke then
          pcall(state.session.on_keystroke, state.session)
        end
      end

      state.command_depth = 1
      if state.depth_reset_timer then
        vim.fn.timer_stop(state.depth_reset_timer)
      end
      state.depth_reset_timer = vim.defer_fn(function()
        if active_sessions[practice_buf] then
          active_sessions[practice_buf].command_depth = 0
          active_sessions[practice_buf].depth_reset_timer = nil
        end
      end, 50)
    end
  end, ns)
end

function M.cleanup_session(session)
  if not session or not session.practice_buf then
    return
  end

  local state = active_sessions[session.practice_buf]
  if state and state.depth_reset_timer then
    -- Don't try to stop defer_fn timers - they're not stoppable with timer_stop
    -- The timer callback checks if the session still exists, so it's safe
    state.depth_reset_timer = nil
  end

  active_sessions[session.practice_buf] = nil

  if session.ns_keystroke then
    pcall(vim.on_key, nil, session.ns_keystroke)
  end
end

function M.get_count(session)
  if not session or not session.practice_buf then
    return 0
  end
  local state = active_sessions[session.practice_buf]
  return state and state.count or 0
end

function M.reset_count(session)
  if not session or not session.practice_buf then
    return
  end
  local state = active_sessions[session.practice_buf]
  if state then
    state.count = 0
  end
end

function M.set_tracking_enabled(session, enabled)
  if not session or not session.practice_buf then
    return
  end
  local state = active_sessions[session.practice_buf]
  if state then
    state.tracking_enabled = enabled
  end
end

function M.is_tracking_enabled(session)
  if not session or not session.practice_buf then
    return false
  end
  local state = active_sessions[session.practice_buf]
  return state and state.tracking_enabled or false
end

function M.with_keys_disabled(session, fn)
  if not session then
    local ok, result = pcall(fn)
    if not ok then
      error(result)
    end
    return result
  end

  local was_enabled = M.is_tracking_enabled(session)
  M.set_tracking_enabled(session, false)
  local ok, result = pcall(fn)
  if was_enabled then
    M.set_tracking_enabled(session, true)
  end
  if not ok then
    error(result)
  end
  return result
end

return M
