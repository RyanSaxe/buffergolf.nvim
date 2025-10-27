local M = {}

local has_snacks = pcall(require, 'snacks.picker')

function M.has_snacks()
	return has_snacks
end

function M.run_picker(picker_type, custom_confirm, fallback)
	if has_snacks then
		local snacks = require('snacks.picker')
		snacks[picker_type]({ confirm = custom_confirm })
	else
		fallback()
	end
end

return M