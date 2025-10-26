local buffer = require("buffergolf.buffer")
local keystroke = require("buffergolf.keystroke")

local M = {}

local buf_valid = buffer.buf_valid
local win_valid = buffer.win_valid

function M.create_reference_window(session)
  local ref_buf = vim.api.nvim_create_buf(false, true)

  local ref_name = buffer.generate_buffer_name(session.origin_buf, ".golf.ref")
  vim.api.nvim_buf_set_name(ref_buf, ref_name)

  vim.api.nvim_buf_set_lines(ref_buf, 0, -1, false, session.reference_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ref_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = ref_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = ref_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = ref_buf })

  local ft = vim.api.nvim_get_option_value("filetype", { buf = session.practice_buf })
  if ft and ft ~= "" then
    vim.api.nvim_set_option_value("filetype", ft, { buf = ref_buf })
  end

  local ref_config = session.config.reference_window or {}
  local position = ref_config.position or "right"
  local size = ref_config.size or 50

  if position == "left" then
    vim.cmd("leftabove vsplit")
  elseif position == "top" then
    vim.cmd("leftabove split")
  elseif position == "bottom" then
    vim.cmd("rightbelow split")
  else
    vim.cmd("rightbelow vsplit")
  end

  local ref_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ref_win, ref_buf)

  if position == "left" or position == "right" then
    local screen_width = vim.api.nvim_get_option("columns")
    local win_width = math.floor(screen_width * size / 100)
    vim.api.nvim_win_set_width(ref_win, win_width)
  else
    if size <= 100 then
      local screen_height = vim.api.nvim_get_option("lines")
      local win_height = math.floor(screen_height * size / 100)
      vim.api.nvim_win_set_height(ref_win, win_height)
    else
      vim.api.nvim_win_set_height(ref_win, size)
    end
  end

  vim.api.nvim_set_option_value("number", true, { win = ref_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = ref_win })
  vim.api.nvim_set_option_value("signcolumn", "yes:1", { win = ref_win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = ref_win })

  vim.api.nvim_buf_set_var(ref_buf, "buffergolf_reference", true)

  vim.api.nvim_set_current_win(session.practice_win)

  session.reference_buf = ref_buf
  session.reference_win = ref_win

  return ref_buf, ref_win
end

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
    if win_valid(ref_win) then
      vim.api.nvim_set_current_win(ref_win)

      local goto_ok = pcall(minidiff.goto_hunk, direction)

      if goto_ok then
        local ref_line = vim.api.nvim_win_get_cursor(ref_win)[1]

        local buf_data = minidiff.get_buf_data(session.reference_buf)

        if buf_data and buf_data.hunks then
          local practice_line = ref_line
          local line_offset = 0

          for _, hunk in ipairs(buf_data.hunks) do
            if hunk.buf_start and hunk.buf_start < ref_line then
              local buf_lines = hunk.buf_count or 0
              local ref_lines = hunk.ref_count or 0

              line_offset = line_offset + (ref_lines - buf_lines)

              if hunk.buf_start <= ref_line and ref_line < hunk.buf_start + buf_lines then
                local hunk_position = ref_line - hunk.buf_start
                practice_line = (hunk.ref_start or 1) + hunk_position + line_offset
                break
              end
            else
              break
            end
          end

          if line_offset ~= 0 then
            practice_line = ref_line + line_offset
          end

          local practice_lines = vim.api.nvim_buf_line_count(session.practice_buf)
          practice_line = math.max(1, math.min(practice_line, practice_lines))

          vim.api.nvim_set_current_win(orig_win)
          vim.api.nvim_win_set_cursor(orig_win, { practice_line, 0 })
          vim.cmd("normal! zz")
        else
          vim.api.nvim_set_current_win(orig_win)
          local practice_lines = vim.api.nvim_buf_line_count(session.practice_buf)
          local target_line = math.min(ref_line, practice_lines)
          vim.api.nvim_win_set_cursor(orig_win, { target_line, 0 })
          vim.cmd("normal! zz")
        end

        vim.api.nvim_set_current_win(ref_win)
        vim.cmd("normal! zz")

        vim.api.nvim_set_current_win(orig_win)
      else
        vim.api.nvim_set_current_win(orig_win)
      end
    end
  end)
end

function M.setup_mini_diff(session)
  local ok, minidiff = pcall(require, "mini.diff")
  if not ok then
    vim.notify(
      "BufferGolf: mini.diff is required for golf mode visualization. Please install nvim-mini/mini.diff",
      vim.log.levels.WARN
    )
    return
  end

  if not minidiff.config then
    minidiff.setup({
      view = {
        style = "sign",
        signs = { add = "│", change = "│", delete = "│" },
      },
    })
  end

  local source = minidiff.gen_source.none()

  vim.b[session.reference_buf].minidiff_config = {
    source = source,
    view = {
      style = "sign",
      signs = { add = "▒", change = "▒", delete = "▒" },
    },
  }

  minidiff.enable(session.reference_buf)

  local practice_lines = vim.api.nvim_buf_get_lines(session.practice_buf, 0, -1, false)
  minidiff.set_ref_text(session.reference_buf, practice_lines)

  vim.b[session.practice_buf].minidiff_config = {
    source = source,
    view = {
      style = "sign",
      signs = { add = "│", change = "│", delete = "│" },
    },
  }

  minidiff.set_ref_text(session.practice_buf, session.reference_lines)

  vim.defer_fn(function()
    if buf_valid(session.reference_buf) then
      minidiff.toggle_overlay(session.reference_buf)
    end
    if buf_valid(session.practice_buf) then
      local buf_data = minidiff.get_buf_data(session.practice_buf)
      if buf_data and buf_data.overlay then
        minidiff.toggle_overlay(session.practice_buf)
      end
    end
  end, 100)

  session.minidiff_enabled = true

  local update_diff = function()
    if not session.minidiff_enabled then
      return
    end
    if not buf_valid(session.practice_buf) or not buf_valid(session.reference_buf) then
      return
    end

    local new_practice_lines = vim.api.nvim_buf_get_lines(session.practice_buf, 0, -1, false)
    minidiff.set_ref_text(session.reference_buf, new_practice_lines)
  end

  session.update_mini_diff = update_diff
end

function M.setup_navigation(session)
  if not session or not session.practice_buf then
    return
  end

  local config = session.config or {}
  local keymaps = config.keymaps and config.keymaps.golf_mode or {}

  local defaults = {
    next_hunk = "]h",
    prev_hunk = "[h",
    first_hunk = "[H",
    last_hunk = "]H",
    toggle_overlay = "<leader>do",
  }

  for key, default in pairs(defaults) do
    if keymaps[key] == nil then
      keymaps[key] = default
    end
  end

  vim.api.nvim_buf_create_user_command(session.practice_buf, "BuffergolfNextHunk", function()
    M.goto_hunk_sync(session, "next")
  end, { desc = "Go to next diff hunk (synchronized)" })

  vim.api.nvim_buf_create_user_command(session.practice_buf, "BuffergolfPrevHunk", function()
    M.goto_hunk_sync(session, "prev")
  end, { desc = "Go to previous diff hunk (synchronized)" })

  vim.api.nvim_buf_create_user_command(session.practice_buf, "BuffergolfFirstHunk", function()
    M.goto_hunk_sync(session, "first")
  end, { desc = "Go to first diff hunk (synchronized)" })

  vim.api.nvim_buf_create_user_command(session.practice_buf, "BuffergolfLastHunk", function()
    M.goto_hunk_sync(session, "last")
  end, { desc = "Go to last diff hunk (synchronized)" })

  vim.api.nvim_buf_create_user_command(session.practice_buf, "BuffergolfToggleOverlay", function()
    local ok, minidiff = pcall(require, "mini.diff")
    if ok and session.reference_buf and buf_valid(session.reference_buf) then
      minidiff.toggle_overlay(session.reference_buf)
    end
  end, { desc = "Toggle mini.diff overlay" })

  local opts = { buffer = session.practice_buf, silent = true }

  if keymaps.next_hunk and keymaps.next_hunk ~= "" then
    vim.keymap.set(
      "n",
      keymaps.next_hunk,
      "<cmd>BuffergolfNextHunk<cr>",
      vim.tbl_extend("force", opts, { desc = "BufferGolf: Next hunk" })
    )
  end

  if keymaps.prev_hunk and keymaps.prev_hunk ~= "" then
    vim.keymap.set(
      "n",
      keymaps.prev_hunk,
      "<cmd>BuffergolfPrevHunk<cr>",
      vim.tbl_extend("force", opts, { desc = "BufferGolf: Previous hunk" })
    )
  end

  if keymaps.first_hunk and keymaps.first_hunk ~= "" then
    vim.keymap.set(
      "n",
      keymaps.first_hunk,
      "<cmd>BuffergolfFirstHunk<cr>",
      vim.tbl_extend("force", opts, { desc = "BufferGolf: First hunk" })
    )
  end

  if keymaps.last_hunk and keymaps.last_hunk ~= "" then
    vim.keymap.set(
      "n",
      keymaps.last_hunk,
      "<cmd>BuffergolfLastHunk<cr>",
      vim.tbl_extend("force", opts, { desc = "BufferGolf: Last hunk" })
    )
  end

  if keymaps.toggle_overlay and keymaps.toggle_overlay ~= "" then
    vim.keymap.set(
      "n",
      keymaps.toggle_overlay,
      "<cmd>BuffergolfToggleOverlay<cr>",
      vim.tbl_extend("force", opts, { desc = "BufferGolf: Toggle diff overlay" })
    )
  end
end

return M
