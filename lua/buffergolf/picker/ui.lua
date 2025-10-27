-- Picker UI orchestration
local buffer = require("buffergolf.session.buffer")
local file_source = require("buffergolf.picker.sources.file")
local buffer_source = require("buffergolf.picker.sources.buffer")
local register_source = require("buffergolf.picker.sources.register")
local git_source = require("buffergolf.picker.sources.git")

local M = {}

local git_repo_cache = {}

local function is_git_repo()
	local cwd = vim.fn.getcwd()
	if git_repo_cache[cwd] ~= nil then return git_repo_cache[cwd] end
	vim.fn.system({"git", "rev-parse", "--is-inside-work-tree"})
	git_repo_cache[cwd] = vim.v.shell_error == 0
	return git_repo_cache[cwd]
end

local function start_session(origin_buf, target_lines, config, is_typing, start_lines)
	local lifecycle = require("buffergolf.session.lifecycle")
	if is_typing then
		lifecycle.start(origin_buf, config, target_lines)
	else
		start_lines = buffer.prepare_lines(start_lines, origin_buf, config)
		lifecycle.start_golf(origin_buf, start_lines, target_lines, config)
	end
	if config.countdown_mode and config.countdown_seconds then
		local actions = require("buffergolf.session.actions")
		actions.start_countdown(vim.api.nvim_get_current_buf(), config.countdown_seconds)
	end
end

local function show_start_state_picker(origin_buf, target_lines, is_selection, config)
	local start_golf_fn = function(buf, lines, target, cfg)
		start_session(buf, target, cfg, false, lines)
	end

	local options = {
		{ label = "Empty", value = "empty", description = "Typing practice - start from blank buffer" },
		{ label = "File...", value = "file", description = "Choose a file as starting state" },
		{ label = "Buffer...", value = "buffer", description = "Choose an open buffer" },
		{ label = "Register...", value = "register", description = "Use register content" },
	}

	if is_git_repo() and vim.api.nvim_buf_get_name(origin_buf) ~= "" then
		table.insert(options, { label = "Git commit...", value = "git", description = "Choose from file history" })
	end

	vim.ui.select(options, {
		prompt = is_selection and "Select start state (target: selection):" or "Select start state:",
		format_item = function(item) return item.label .. " - " .. item.description end,
	}, function(choice)
		if not choice then return end
		local sources = {
			empty = function() start_session(origin_buf, target_lines, config, true) end,
			file = function() file_source.select(origin_buf, target_lines, config, start_golf_fn) end,
			buffer = function() buffer_source.select(origin_buf, target_lines, config, start_golf_fn) end,
			register = function() register_source.select(origin_buf, target_lines, config, start_golf_fn) end,
			git = function() git_source.select(origin_buf, target_lines, config, start_golf_fn) end,
		}
		if sources[choice.value] then sources[choice.value]() end
	end)
end

function M.show_picker(bufnr, start_line, end_line, config)
	local target_lines
	local is_visual = false

	if start_line and end_line and start_line > 0 and end_line > 0 then
		target_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
		is_visual = true
	else
		local mode = vim.api.nvim_get_mode().mode
		if mode:match("^[vV\026]") or (vim.fn.line("'<") > 0 and vim.fn.line("'>") > 0) then
			local mark_start, mark_end = vim.fn.line("'<"), vim.fn.line("'>")
			if mark_start > 0 and mark_end > 0 then
				if mode:match("^[vV\026]") then
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
				end
				target_lines = vim.api.nvim_buf_get_lines(bufnr, mark_start - 1, mark_end, false)
				is_visual = true
			end
		end
	end

	target_lines = target_lines or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	target_lines = buffer.prepare_lines(target_lines, bufnr, config)

	show_start_state_picker(bufnr, target_lines, is_visual, config)
end

function M.start_empty(bufnr, config)
	start_session(bufnr, nil, config, true)
end

return M