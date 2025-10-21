-- Keystroke tracking - completely new approach
-- We track "command initiation" - the first key in any sequence

local M = {}

-- Session-specific state
local active_sessions = {} -- [practice_buf] = session_state

-- Global state for command tracking
local command_depth = 0
local depth_reset_timer = nil

-- Initialize keystroke tracking for a session
function M.init_session(session)
  if not session or not session.practice_buf then
    return
  end

  local practice_buf = session.practice_buf

  -- Initialize session state
  active_sessions[practice_buf] = {
    count = 0,
    debug_keys = {}, -- for debugging
    tracking_enabled = true,  -- Add tracking control flag
  }

  -- Create namespace for this session's vim.on_key handler
  local ns = vim.api.nvim_create_namespace(string.format("BuffergolfKeystroke_%d", practice_buf))
  session.ns_keystroke = ns

  -- Track "command initiation" - only the first key in any rapid sequence
  vim.on_key(function(raw_key)
    -- Check if we're in the practice buffer
    local ok, current_buf = pcall(vim.api.nvim_get_current_buf)
    if not ok or current_buf ~= practice_buf then
      return
    end

    local state = active_sessions[practice_buf]
    if not state then
      return
    end

    -- Ignore macro playback
    if vim.fn.reg_executing() ~= "" then
      return
    end

    -- Convert to readable key name
    local key_name = vim.fn.keytrans(raw_key)

    -- Ignore special internal keys and mouse
    if key_name == "<Ignore>" or key_name:match("^<.*Mouse.*>$") then
      return
    end

    -- Skip empty keys
    if raw_key == "" or key_name == "" then
      return
    end

    -- APPROACH 1: Command depth tracking
    -- Only count if this is the start of a new command sequence
    if command_depth == 0 then
      -- Only increment count if tracking is enabled
      if state.tracking_enabled then
        -- This is a user-initiated keystroke
        state.count = state.count + 1
        table.insert(state.debug_keys, string.format("[%d] %s", state.count, key_name))
        if #state.debug_keys > 30 then
          table.remove(state.debug_keys, 1)
        end
      end

      -- Always increment depth to mark we're in a command (regardless of tracking)
      command_depth = command_depth + 1

      -- Reset depth after 50ms (most vim operations complete within this)
      if depth_reset_timer then
        vim.loop.timer_stop(depth_reset_timer)
      end
      depth_reset_timer = vim.defer_fn(function()
        command_depth = 0
        depth_reset_timer = nil
      end, 50)
    end
  end, ns)
end

-- Alternative approach 2: Track input at a lower level using getchar()
function M.init_session_getchar(session)
  -- This would use vim.fn.getchar() in a loop
  -- But this blocks the UI, so it's not practical
end

-- Alternative approach 3: Track only buffer-modifying operations
function M.init_session_changes(session)
  if not session or not session.practice_buf then
    return
  end

  local practice_buf = session.practice_buf

  -- Initialize session state
  active_sessions[practice_buf] = {
    count = 0,
    debug_keys = {},
    last_lines = {},
    mode_counts = { n = 0, i = 0, v = 0 },
  }

  local state = active_sessions[practice_buf]

  -- Track buffer changes for insert mode
  vim.api.nvim_buf_attach(practice_buf, false, {
    on_lines = function(_, _, _, first_line, last_line, last_line_new, byte_count)
      -- Count characters added/removed
      -- This gives us accurate insert mode counting
      if byte_count > 0 then
        state.mode_counts.i = state.mode_counts.i + 1
      end
    end
  })

  -- Track mode changes and commands
  local ns = vim.api.nvim_create_namespace(string.format("BuffergolfKeystroke_%d", practice_buf))
  session.ns_keystroke = ns

  local last_mode = "n"
  vim.on_key(function(raw_key)
    local ok, current_buf = pcall(vim.api.nvim_get_current_buf)
    if not ok or current_buf ~= practice_buf then
      return
    end

    local mode = vim.api.nvim_get_mode().mode

    -- Detect mode changes
    if mode ~= last_mode then
      state.mode_counts[mode] = (state.mode_counts[mode] or 0) + 1
      last_mode = mode
    end
  end, ns)
end

-- Clean up keystroke tracking for a session
function M.cleanup_session(session)
  if not session or not session.practice_buf then
    return
  end

  local practice_buf = session.practice_buf

  -- Stop any active timer
  if depth_reset_timer then
    vim.loop.timer_stop(depth_reset_timer)
    depth_reset_timer = nil
  end

  -- Reset command depth
  command_depth = 0

  -- Remove from active sessions
  active_sessions[practice_buf] = nil

  -- Unregister vim.on_key handler
  if session.ns_keystroke then
    pcall(vim.on_key, nil, session.ns_keystroke)
  end
end

-- Get keystroke count for a session
function M.get_count(session)
  if not session or not session.practice_buf then
    return 0
  end

  local state = active_sessions[session.practice_buf]
  return state and state.count or 0
end

-- Reset keystroke count for a session
function M.reset_count(session)
  if not session or not session.practice_buf then
    return
  end

  local state = active_sessions[session.practice_buf]
  if state then
    state.count = 0
    state.debug_keys = {}
    if state.mode_counts then
      state.mode_counts = { n = 0, i = 0, v = 0 }
    end
  end
end

-- DEBUG: Get debug keys for a session
function M.get_debug_keys(session)
  if not session or not session.practice_buf then
    return nil
  end

  local state = active_sessions[session.practice_buf]
  return state and state.debug_keys or nil
end

-- Set tracking enabled state for a session
function M.set_tracking_enabled(session, enabled)
  if not session or not session.practice_buf then
    return
  end

  local state = active_sessions[session.practice_buf]
  if state then
    state.tracking_enabled = enabled
  end
end

-- Get tracking enabled state for a session
function M.is_tracking_enabled(session)
  if not session or not session.practice_buf then
    return false
  end

  local state = active_sessions[session.practice_buf]
  return state and state.tracking_enabled or false
end

return M