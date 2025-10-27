local buffer = require("buffergolf.session.buffer")
local keystroke = require("buffergolf.session.keystroke")

local M = {}

function M.goto_hunk_sync(session, direction)
  if not session or not session.reference_buf or not session.practice_buf then
    return
  end

  local ok, minidiff = pcall(require, "mini.diff")
  if not ok then
    return
  end

  keystroke.with_keys_disabled(session, function()
    local orig_win = vim.api.nvim_get_current_win()
    local ref_win = session.reference_win

    if buffer.win_valid(ref_win) then
      vim.api.nvim_set_current_win(ref_win)
      local goto_ok = pcall(minidiff.goto_hunk, direction)

      if goto_ok then
        local ref_line = vim.api.nvim_win_get_cursor(ref_win)[1]
        local buf_data = minidiff.get_buf_data(session.reference_buf)
        local practice_line = ref_line
        local line_offset = 0

        if buf_data and buf_data.hunks then
          for _, hunk in ipairs(buf_data.hunks) do
            if hunk.buf_start and hunk.buf_start < ref_line then
              local buf_lines, ref_lines = hunk.buf_count or 0, hunk.ref_count or 0
              line_offset = line_offset + (ref_lines - buf_lines)
              if hunk.buf_start <= ref_line and ref_line < hunk.buf_start + buf_lines then
                practice_line = (hunk.ref_start or 1) + (ref_line - hunk.buf_start) + line_offset
                break
              end
            else
              break
            end
          end
          if line_offset ~= 0 then
            practice_line = ref_line + line_offset
          end
        end

        local practice_lines = vim.api.nvim_buf_line_count(session.practice_buf)
        practice_line = math.max(1, math.min(practice_line, practice_lines))

        vim.api.nvim_set_current_win(orig_win)
        vim.api.nvim_win_set_cursor(orig_win, { practice_line, 0 })
        vim.cmd("normal! zz")
        vim.api.nvim_set_current_win(ref_win)
        vim.cmd("normal! zz")
      end
      vim.api.nvim_set_current_win(orig_win)
    end
  end)
end

function M.setup(session)
  if not session or not session.practice_buf then
    return
  end

  local keymaps = (session.config and session.config.keymaps and session.config.keymaps.golf_mode) or {}
  local defaults = {
    next_hunk = "]h",
    prev_hunk = "[h",
    first_hunk = "[H",
    last_hunk = "]H",
    toggle_overlay = "<leader>do",
  }

  for key, default in pairs(defaults) do
    keymaps[key] = keymaps[key] or default
  end

  local commands = {
    { "BuffergolfNextHunk", "next", "Go to next diff hunk (synchronized)" },
    { "BuffergolfPrevHunk", "prev", "Go to previous diff hunk (synchronized)" },
    { "BuffergolfFirstHunk", "first", "Go to first diff hunk (synchronized)" },
    { "BuffergolfLastHunk", "last", "Go to last diff hunk (synchronized)" },
    { "BuffergolfToggleOverlay", nil, "Toggle mini.diff overlay" },
  }

  for _, cmd in ipairs(commands) do
    vim.api.nvim_buf_create_user_command(session.practice_buf, cmd[1], function()
      if cmd[2] then
        M.goto_hunk_sync(session, cmd[2])
      else
        local ok, minidiff = pcall(require, "mini.diff")
        if ok and session.reference_buf and buffer.buf_valid(session.reference_buf) then
          minidiff.toggle_overlay(session.reference_buf)
        end
      end
    end, { desc = cmd[3] })
  end

  local mappings = {
    { keymaps.next_hunk, "BuffergolfNextHunk", "Next hunk" },
    { keymaps.prev_hunk, "BuffergolfPrevHunk", "Previous hunk" },
    { keymaps.first_hunk, "BuffergolfFirstHunk", "First hunk" },
    { keymaps.last_hunk, "BuffergolfLastHunk", "Last hunk" },
    { keymaps.toggle_overlay, "BuffergolfToggleOverlay", "Toggle diff overlay" },
  }

  local opts = { buffer = session.practice_buf, silent = true }
  for _, map in ipairs(mappings) do
    if map[1] and map[1] ~= "" then
      vim.keymap.set(
        "n",
        map[1],
        "<cmd>" .. map[2] .. "<cr>",
        vim.tbl_extend("force", opts, { desc = "BufferGolf: " .. map[3] })
      )
    end
  end
end

return M
