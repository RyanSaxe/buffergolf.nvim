local adapter = require("buffergolf.picker.adapter")

local M = {}

local registers = {
  '"',
  "+",
  "*",
  "0",
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "a",
  "b",
  "c",
  "d",
  "e",
  "f",
  "g",
  "h",
  "i",
  "j",
  "k",
  "l",
  "m",
  "n",
  "o",
  "p",
  "q",
  "r",
  "s",
  "t",
  "u",
  "v",
  "w",
  "x",
  "y",
  "z",
}

function M.select(origin_buf, target_lines, config, start_golf_fn)
  adapter.run_picker("registers", function(picker)
    local item = picker:current()
    if item and item.reg then
      local content = vim.fn.getreg(item.reg)
      if content and content ~= "" then
        picker:close()
        start_golf_fn(origin_buf, vim.split(content, "\n", { plain = true }), target_lines, config)
      end
    end
  end, function()
    local reg_options = {}
    for _, reg in ipairs(registers) do
      local content = vim.fn.getreg(reg)
      if content and content ~= "" then
        local preview = content:gsub("\n", "↵"):sub(1, 50)
        if #content > 50 then
          preview = preview .. "..."
        end
        table.insert(reg_options, {
          label = string.format('"%s: %s', reg, preview),
          value = reg,
        })
      end
    end

    if #reg_options == 0 then
      vim.notify("No registers with content found", vim.log.levels.WARN, { title = "buffergolf" })
      return
    end

    vim.ui.select(reg_options, {
      prompt = "Select register as starting point:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        start_golf_fn(origin_buf, vim.split(vim.fn.getreg(choice.value), "\n", { plain = true }), target_lines, config)
      end
    end)
  end)
end

return M
