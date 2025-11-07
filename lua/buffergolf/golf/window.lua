local buffer = require("buffergolf.session.buffer")

local M = {}

local function validate_window_config(config)
  if not config then
    return false, "No window config provided"
  end

  local position = config.position
  if position and not vim.tbl_contains({ "left", "right", "top", "bottom" }, position) then
    return false, "Invalid window position: " .. tostring(position)
  end

  local size = config.size
  if size and (type(size) ~= "number" or size <= 0 or size > 100) then
    return false, "Invalid window size: " .. tostring(size)
  end

  return true, nil
end

local function apply_border(win, border_style)
  if not border_style or border_style == "none" then
    return
  end

  pcall(vim.api.nvim_win_set_config, win, {
    border = border_style,
  })
end

-- Creates a split window to display the reference text in golf mode
function M.create_reference_window(session)
  local ref_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(ref_buf, buffer.generate_buffer_name(session.origin_buf, ".golf.ref"))
  vim.api.nvim_buf_set_lines(ref_buf, 0, -1, false, session.reference_lines)

  local buf_opts = { modifiable = false, buftype = "nofile", bufhidden = "wipe", swapfile = false }
  for opt, val in pairs(buf_opts) do
    vim.api.nvim_set_option_value(opt, val, { buf = ref_buf })
  end

  local ft = vim.api.nvim_get_option_value("filetype", { buf = session.practice_buf })
  if ft and ft ~= "" then
    vim.api.nvim_set_option_value("filetype", ft, { buf = ref_buf })
  end

  local ref_config = (session.config.windows and session.config.windows.reference) or {}
  local position, size = ref_config.position or "right", ref_config.size or 50
  local border = ref_config.border or "none"

  local is_valid, err = validate_window_config(ref_config)
  if not is_valid then
    vim.notify("Window config warning: " .. err, vim.log.levels.WARN)
  end

  local split_cmds =
    { left = "leftabove vsplit", top = "leftabove split", bottom = "rightbelow split", right = "rightbelow vsplit" }
  vim.cmd(split_cmds[position] or split_cmds.right)

  local ref_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ref_win, ref_buf)

  if position == "left" or position == "right" then
    vim.api.nvim_win_set_width(ref_win, math.floor(vim.o.columns * size / 100))
  else
    local height = size <= 100 and math.floor(vim.o.lines * size / 100) or size
    vim.api.nvim_win_set_height(ref_win, height)
  end

  local win_opts = { number = true, relativenumber = false, signcolumn = "yes:1", foldcolumn = "0" }
  for opt, val in pairs(win_opts) do
    vim.api.nvim_set_option_value(opt, val, { win = ref_win })
  end

  vim.api.nvim_buf_set_var(ref_buf, "buffergolf_reference", true)
  vim.api.nvim_set_current_win(session.practice_win)
  vim.api.nvim_win_set_cursor(session.practice_win, { 1, 0 })

  apply_border(ref_win, border)

  session.reference_buf, session.reference_win = ref_buf, ref_win
  return ref_buf, ref_win
end

function M.update_reference_content(session, new_lines)
  if not session or not session.reference_buf then
    return false
  end

  if not buffer.buf_valid(session.reference_buf) then
    return false
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = session.reference_buf })
  vim.api.nvim_buf_set_lines(session.reference_buf, 0, -1, false, new_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = session.reference_buf })

  return true
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
    minidiff.setup({ view = { style = "sign", signs = { add = "│", change = "│", delete = "│" } } })
  end

  local source = minidiff.gen_source.none()
  local configs = {
    [session.reference_buf] = {
      source = source,
      view = { style = "sign", signs = { add = "▒", change = "▒", delete = "▒" } },
    },
    [session.practice_buf] = {
      source = source,
      view = { style = "sign", signs = { add = "│", change = "│", delete = "│" } },
    },
  }

  for buf, config in pairs(configs) do
    vim.b[buf].minidiff_config = config
    if buf == session.reference_buf then
      minidiff.enable(buf)
    end
  end

  local practice_lines = vim.api.nvim_buf_get_lines(session.practice_buf, 0, -1, false)
  minidiff.set_ref_text(session.reference_buf, practice_lines)
  minidiff.set_ref_text(session.practice_buf, session.reference_lines)

  vim.defer_fn(function()
    for _, buf in ipairs({ session.reference_buf, session.practice_buf }) do
      if buffer.buf_valid(buf) then
        local buf_data = buf == session.practice_buf and minidiff.get_buf_data(buf)
        if buf == session.reference_buf or (buf_data and buf_data.overlay) then
          minidiff.toggle_overlay(buf)
        end
      end
    end
  end, 100) -- milliseconds delay for overlay setup

  session.minidiff_enabled = true
  session.update_mini_diff = function()
    if
      session.minidiff_enabled
      and buffer.buf_valid(session.practice_buf)
      and buffer.buf_valid(session.reference_buf)
    then
      minidiff.set_ref_text(session.reference_buf, vim.api.nvim_buf_get_lines(session.practice_buf, 0, -1, false))
    end
  end
end

return M
