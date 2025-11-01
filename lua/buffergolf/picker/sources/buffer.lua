local adapter = require("buffergolf.picker.adapter")

local M = {}

local function get_buffer_name(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name == "" and ("[No Name #" .. buf .. "]") or vim.fn.fnamemodify(name, ":~:.")
end

function M.select(origin_buf, target_lines, config, start_golf_fn)
  adapter.run_picker("buffers", function(picker)
    local item = picker:current()
    if item and item.buf then
      if item.buf == origin_buf then
        vim.notify("Cannot use current buffer as starting point", vim.log.levels.WARN, { title = "buffergolf" })
        return
      end
      if not vim.api.nvim_buf_is_loaded(item.buf) then
        vim.fn.bufload(item.buf)
      end
      picker:close()
      start_golf_fn(origin_buf, vim.api.nvim_buf_get_lines(item.buf, 0, -1, false), target_lines, config)
    end
  end, function()
    local buffer_options = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_loaded(buf)
        and vim.api.nvim_get_option_value("buflisted", { buf = buf })
        and buf ~= origin_buf
        and not vim.b[buf].buffergolf_practice -- Exclude practice buffers
      then
        table.insert(buffer_options, { label = get_buffer_name(buf), value = buf })
      end
    end

    if #buffer_options == 0 then
      vim.notify("No other buffers available", vim.log.levels.WARN, { title = "buffergolf" })
      return
    end

    vim.ui.select(buffer_options, {
      prompt = "Select buffer as starting point:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        start_golf_fn(origin_buf, vim.api.nvim_buf_get_lines(choice.value, 0, -1, false), target_lines, config)
      end
    end)
  end)
end

return M
