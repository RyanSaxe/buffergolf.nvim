local Session = require("buffergolf.session")
local Picker = require("buffergolf.picker")

local M = {}

local default_config = {
	ghost_hl = "BuffergolfGhost",
	mismatch_hl = "BuffergolfMismatch",
	disable_diagnostics = true,
	disable_inlay_hints = true,
	disable_matchparen = true,
	difficulty = "medium",  -- "easy" (1.0x), "medium" (0.67x), "hard" (0.5x), "expert" (0.33x)
	keymaps = {
		toggle = "<leader>bg",
		countdown = "<leader>bG",
	},
	reference_window = {
		position = "right",  -- "right", "left", "top", "bottom"
		size = 50,          -- percentage of screen for vertical splits, or lines for horizontal
	},
	stats_float = {
		position = "bottom-right",  -- "bottom-right", "bottom-left", "top-right", "top-left"
		offset_x = 2,               -- horizontal padding from window edge
		offset_y = 1,               -- vertical padding from window edge
	},
	score_colors = {
		-- Colors for score percentage display (golf mode only)
		-- Score = (par - keystrokes) / par * 100
		very_bad = "#ff0000",      -- < -50%: bright red
		bad = "#ff5555",           -- -50% to -25%: red
		poor = "#ffaa00",          -- -25% to 0%: orange
		okay = "#88ccff",          -- 0% to 25%: light blue
		good = "#5555ff",          -- 25% to 50%: blue
		great = "#00ff00",         -- 50% to 75%: green
	},
	auto_dedent = true,            -- Strip common leading whitespace
}

local configured = false

local function hl_exists(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	return ok and hl and next(hl) ~= nil
end

local function can_link(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
	return ok and hl ~= nil
end

local function ensure_highlights(opts)
	if not hl_exists(opts.ghost_hl) then
		if can_link("Comment") then
			vim.api.nvim_set_hl(0, opts.ghost_hl, { link = "Comment" })
		else
			vim.api.nvim_set_hl(0, opts.ghost_hl, { fg = "#555555", ctermfg = 8 })
		end
	end

	if not hl_exists(opts.mismatch_hl) then
		vim.api.nvim_set_hl(0, opts.mismatch_hl, {
			fg = "#ff5f6d",
			ctermfg = 1,
			underline = true,
		})
	end
end

function M.setup(opts)
	if configured then
		return
	end

	M.config = vim.tbl_deep_extend("force", {}, default_config, opts or {})
	ensure_highlights(M.config)

	local keymaps = M.config.keymaps or {}
	local toggle_key = keymaps.toggle

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("BuffergolfHL", { clear = true }),
		callback = function()
			ensure_highlights(M.config)
		end,
	})

	vim.api.nvim_create_user_command("Buffergolf", function(opts)
		if opts.range > 0 then
			M.toggle_with_picker(opts.line1, opts.line2)
		else
			M.toggle_with_picker()
		end
	end, { desc = "Start buffergolf practice with picker", range = true })

	vim.api.nvim_create_user_command("BuffergolfStop", function()
		M.stop()
	end, { desc = "Stop buffergolf practice buffer" })

	vim.api.nvim_create_user_command("BuffergolfCountdown", function(opts)
		if opts.range > 0 then
			M.start_countdown(opts.line1, opts.line2)
		else
			M.start_countdown()
		end
	end, { desc = "Start countdown timer for buffergolf practice buffer", range = true })

	vim.api.nvim_create_user_command("BuffergolfTyping", function()
		M.start_typing()
	end, { desc = "Start buffergolf typing practice (empty start)" })

	if toggle_key and toggle_key ~= "" then
		vim.keymap.set("n", toggle_key, M.toggle, {
			desc = "Toggle buffergolf practice buffer",
			silent = true,
		})
		vim.keymap.set("x", toggle_key, function()
			vim.cmd('normal! \027')
			local start_line = vim.fn.line("'<")
			local end_line = vim.fn.line("'>")
			M.toggle_with_picker(start_line, end_line)
		end, {
			desc = "Toggle buffergolf with visual selection",
			silent = true,
		})
	end

	local countdown_key = keymaps.countdown
	if countdown_key and countdown_key ~= "" then
		vim.keymap.set("n", countdown_key, M.start_countdown, {
			desc = "Start countdown timer",
			silent = true,
		})
		vim.keymap.set("x", countdown_key, function()
			vim.cmd('normal! \027')
			local start_line = vim.fn.line("'<")
			local end_line = vim.fn.line("'>")
			M.start_countdown(start_line, end_line)
		end, {
			desc = "Start countdown timer with visual selection",
			silent = true,
		})
	end

	configured = true
end

-- Legacy toggle function for backward compatibility
function M.toggle()
	local bufnr = vim.api.nvim_get_current_buf()
	if Session.is_active(bufnr) then
		Session.stop(bufnr)
	else
		-- Use picker for new behavior
		M.toggle_with_picker()
	end
end

-- New toggle function that shows the picker
function M.toggle_with_picker(start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()
	if Session.is_active(bufnr) then
		Session.stop(bufnr)
	else
		Picker.show_picker(bufnr, start_line, end_line, M.config)
	end
end

-- Direct start without picker (for backward compatibility)
function M.toggle_legacy()
	local bufnr = vim.api.nvim_get_current_buf()
	if Session.is_active(bufnr) then
		Session.stop(bufnr)
	else
		Session.start(bufnr, M.config)
	end
end

function M.start()
	Session.start(vim.api.nvim_get_current_buf(), M.config)
end

function M.stop()
	Session.stop(vim.api.nvim_get_current_buf())
end

-- Start typing practice (empty start) without picker
function M.start_typing()
	local bufnr = vim.api.nvim_get_current_buf()
	if Session.is_active(bufnr) then
		Session.stop(bufnr)
	end
	Session.start(bufnr, M.config)
end

function M.start_countdown(start_line, end_line)
	local bufnr = vim.api.nvim_get_current_buf()

	vim.ui.input({ prompt = "Countdown duration (seconds): " }, function(input)
		-- Handle ESC/cancel - do nothing
		if input == nil then
			return
		end

		-- Check if there's already an active session
		if Session.is_active(bufnr) then
			-- Reset the session to start
			Session.reset_to_start(bufnr)

			-- Handle empty input - count-up mode
			if input == "" then
				-- Start count-up mode (no countdown)
				Session.start_countdown(bufnr, nil)
			else
				-- Handle numeric input - countdown mode
				local seconds = tonumber(input)
				if not seconds or seconds <= 0 then
					vim.notify("Invalid duration. Please enter a positive number.", vim.log.levels.ERROR, { title = "buffergolf" })
					return
				end
				Session.start_countdown(bufnr, seconds)
			end
		else
			-- No active session - show picker for new session
			if input == "" then
				-- Count-up mode for new session
				local config_with_countup = vim.tbl_extend("force", M.config, {
					countdown_mode = false
				})
				Picker.show_picker(bufnr, start_line, end_line, config_with_countup)
			else
				-- Countdown mode for new session
				local seconds = tonumber(input)
				if not seconds or seconds <= 0 then
					vim.notify("Invalid duration. Please enter a positive number.", vim.log.levels.ERROR, { title = "buffergolf" })
					return
				end

				local config_with_countdown = vim.tbl_extend("force", M.config, {
					countdown_seconds = seconds,
					countdown_mode = true
				})
				Picker.show_picker(bufnr, start_line, end_line, config_with_countdown)
			end
		end
	end)
end

return M
