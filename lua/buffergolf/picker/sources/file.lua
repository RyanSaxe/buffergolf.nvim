local adapter = require("buffergolf.picker.adapter")

local M = {}

function M.select(origin_buf, target_lines, config, start_golf_fn)
	adapter.run_picker("files",
		function(picker)
			local item = picker:current()
			if item and item.file then
				local ok, lines = pcall(vim.fn.readfile, item.file)
				if ok then
					picker:close()
					start_golf_fn(origin_buf, lines, target_lines, config)
				else
					vim.notify("Failed to read file: " .. item.file, vim.log.levels.ERROR, { title = "buffergolf" })
				end
			end
		end,
		function()
			vim.ui.input({ prompt = "Enter file path: " }, function(input)
				if not input or input == "" then return end
				local ok, lines = pcall(vim.fn.readfile, input)
				if ok then
					start_golf_fn(origin_buf, lines, target_lines, config)
				else
					vim.notify("Failed to read file: " .. input, vim.log.levels.ERROR, { title = "buffergolf" })
				end
			end)
		end
	)
end

return M