local M = {}
local buffer = require("buffergolf.buffer")

-- Cache for git repository check
local git_repo_cache = {}

-- Check if Snacks.nvim is available
local function has_snacks()
  return pcall(require, 'snacks.picker')
end

-- Check if we're in a git repository (with caching)
local function is_git_repo()
  local cwd = vim.fn.getcwd()

  -- Return cached result if available
  if git_repo_cache[cwd] ~= nil then
    return git_repo_cache[cwd]
  end

  -- Check git repository status
  vim.fn.system({"git", "rev-parse", "--is-inside-work-tree"})
  local is_repo = vim.v.shell_error == 0

  -- Cache the result
  git_repo_cache[cwd] = is_repo

  return is_repo
end

-- Start typing practice mode (empty buffer)
local function start_typing_mode(origin_buf, target_lines, config)
  local Session = require("buffergolf.session")
  Session.start(origin_buf, config, target_lines)

  -- Apply countdown if configured
  if config.countdown_mode and config.countdown_seconds then
    local new_bufnr = vim.api.nvim_get_current_buf()
    Session.start_countdown(new_bufnr, config.countdown_seconds)
  end
end

-- Start golf mode with given starting content
local function start_golf_mode(origin_buf, start_lines, target_lines, config)
  local Session = require("buffergolf.session")

  -- Apply formatting/dedenting to start lines (target already formatted in show_picker)
  start_lines = buffer.prepare_lines(start_lines, origin_buf, config)

  Session.start_golf(origin_buf, start_lines, target_lines, config)

  -- Apply countdown if configured
  if config.countdown_mode and config.countdown_seconds then
    local new_bufnr = vim.api.nvim_get_current_buf()
    Session.start_countdown(new_bufnr, config.countdown_seconds)
  end
end

-- File picker using Snacks or native fallback
local function select_file_with_preview(origin_buf, target_lines, config)
  if has_snacks() then
    local snacks = require('snacks.picker')

    -- Use Snacks file picker with custom action
    snacks.files({
      confirm = function(picker)
        local item = picker:current()
        if item and item.file then
          local ok, lines = pcall(vim.fn.readfile, item.file)
          if ok then
            picker:close()
            start_golf_mode(origin_buf, lines, target_lines, config)
          else
            vim.notify("Failed to read file: " .. item.file, vim.log.levels.ERROR, { title = "buffergolf" })
          end
        end
      end
    })
  else
    -- Native fallback
    vim.ui.input({ prompt = "Enter file path: " }, function(input)
      if not input or input == "" then
        return
      end

      local ok, lines = pcall(vim.fn.readfile, input)
      if ok then
        start_golf_mode(origin_buf, lines, target_lines, config)
      else
        vim.notify("Failed to read file: " .. input, vim.log.levels.ERROR, { title = "buffergolf" })
      end
    end)
  end
end

-- Buffer picker using Snacks or native fallback
local function select_buffer_with_preview(origin_buf, target_lines, config)
  if has_snacks() then
    local snacks = require('snacks.picker')

    -- Use Snacks buffer picker with custom action
    snacks.buffers({
      confirm = function(picker)
        local item = picker:current()
        if item and item.buf then
          -- Don't allow selecting the current buffer as starting point
          if item.buf == origin_buf then
            vim.notify("Cannot use current buffer as starting point", vim.log.levels.WARN, { title = "buffergolf" })
            return
          end

          -- Ensure buffer is loaded before reading
          if not vim.api.nvim_buf_is_loaded(item.buf) then
            vim.fn.bufload(item.buf)
          end

          local start_lines = vim.api.nvim_buf_get_lines(item.buf, 0, -1, false)

          picker:close()
          start_golf_mode(origin_buf, start_lines, target_lines, config)
        end
      end
    })
  else
    -- Native fallback
    local buffers = vim.api.nvim_list_bufs()
    local buffer_options = {}

    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_loaded(buf) and
         vim.api.nvim_get_option_value("buflisted", { buf = buf }) and
         buf ~= origin_buf then
        local name = vim.api.nvim_buf_get_name(buf)
        if name == "" then
          name = "[No Name #" .. buf .. "]"
        else
          name = vim.fn.fnamemodify(name, ":~:.")
        end

        table.insert(buffer_options, {
          label = name,
          value = buf,
        })
      end
    end

    if #buffer_options == 0 then
      vim.notify("No other buffers available", vim.log.levels.WARN, { title = "buffergolf" })
      return
    end

    vim.ui.select(buffer_options, {
      prompt = "Select buffer as starting point:",
      format_item = function(item) return item.label end,
    }, function(choice)
      if choice then
        local start_lines = vim.api.nvim_buf_get_lines(choice.value, 0, -1, false)
        start_golf_mode(origin_buf, start_lines, target_lines, config)
      end
    end)
  end
end

-- Register picker using Snacks or native fallback
local function select_register_with_preview(origin_buf, target_lines, config)
  if has_snacks() then
    local snacks = require('snacks.picker')

    -- Use Snacks registers picker with custom action
    snacks.registers({
      confirm = function(picker)
        local item = picker:current()
        if item and item.reg then
          local content = vim.fn.getreg(item.reg)
          if content and content ~= "" then
            local start_lines = vim.split(content, "\n", { plain = true })
            picker:close()
            start_golf_mode(origin_buf, start_lines, target_lines, config)
          end
        end
      end
    })
  else
    -- Native fallback
    local registers = {'"', '+', '*', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                       'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
                       'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'}

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
      format_item = function(item) return item.label end,
    }, function(choice)
      if choice then
        local content = vim.fn.getreg(choice.value)
        local start_lines = vim.split(content, "\n", { plain = true })
        start_golf_mode(origin_buf, start_lines, target_lines, config)
      end
    end)
  end
end

-- Git commit picker using Snacks or native fallback
local function select_git_commit_with_preview(origin_buf, target_lines, config)
  local filepath = vim.api.nvim_buf_get_name(origin_buf)

  if filepath == "" then
    vim.notify("Current buffer has no file path", vim.log.levels.WARN, { title = "buffergolf" })
    return
  end

  -- Get git root directory
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error ~= 0 then
    vim.notify("Not in a git repository", vim.log.levels.WARN, { title = "buffergolf" })
    return
  end

  -- Convert to relative path from git root
  local relative_path
  if filepath:sub(1, #git_root) == git_root then
    -- Remove git root prefix and leading slash to get relative path
    relative_path = filepath:sub(#git_root + 2)
  else
    -- Fallback: try to get relative path using vim functions
    relative_path = vim.fn.fnamemodify(filepath, ":.")
  end

  if has_snacks() then
    local snacks = require('snacks.picker')

    -- Use Snacks git log picker with custom confirm function
    snacks.git_log_file({
      file = filepath,
      confirm = function(picker, item)
        if item and item.commit then
          local git_object = string.format("%s:%s", item.commit, relative_path)
          local start_lines = vim.fn.systemlist({ "git", "show", git_object })

          if vim.v.shell_error ~= 0 then
            vim.notify("Failed to get file at commit " .. item.commit, vim.log.levels.ERROR, { title = "buffergolf" })
            return
          end

          picker:close()
          start_golf_mode(origin_buf, start_lines, target_lines, config)
        else
          vim.notify("Failed to resolve commit for selection", vim.log.levels.WARN, { title = "buffergolf" })
        end
      end,
    })
  else
    -- Native fallback
    local commits = vim.fn.systemlist({
      "git",
      "log",
      "--oneline",
      "--follow",
      "-n",
      "20",
      "--",
      relative_path,
    })

    if vim.v.shell_error ~= 0 or #commits == 0 then
      vim.notify("No git history found for this file", vim.log.levels.WARN, { title = "buffergolf" })
      return
    end

    local commit_options = {}
    for _, commit_line in ipairs(commits) do
      local hash = commit_line:match("^(%S+)")
      if hash then
        table.insert(commit_options, {
          label = commit_line,
          value = hash,
        })
      end
    end

    vim.ui.select(commit_options, {
      prompt = "Select commit as starting point:",
      format_item = function(item) return item.label end,
    }, function(choice)
      if choice then
        local git_object = string.format("%s:%s", choice.value, relative_path)
        local start_lines = vim.fn.systemlist({ "git", "show", git_object })

        if vim.v.shell_error ~= 0 then
          vim.notify("Failed to get file at commit " .. choice.value, vim.log.levels.ERROR, { title = "buffergolf" })
          return
        end

        start_golf_mode(origin_buf, start_lines, target_lines, config)
      end
    end)
  end
end

-- Main picker function
local function show_start_state_picker(origin_buf, target_lines, is_selection, config)
  local options = {
    { label = "Empty", value = "empty", description = "Typing practice - start from blank buffer" },
    { label = "File...", value = "file", description = "Choose a file as starting state" },
    { label = "Buffer...", value = "buffer", description = "Choose an open buffer" },
    { label = "Register...", value = "register", description = "Use register content" },
  }

  -- Add git option if in a repo and buffer has a file
  if is_git_repo() and vim.api.nvim_buf_get_name(origin_buf) ~= "" then
    table.insert(options, {
      label = "Git commit...",
      value = "git",
      description = "Choose from file history"
    })
  end

  -- Use vim.ui.select (integrates with telescope/fzf if available)
  vim.ui.select(options, {
    prompt = is_selection and "Select start state (target: selection):" or "Select start state:",
    format_item = function(item)
      return item.label .. " - " .. item.description
    end,
  }, function(choice)
    if not choice then
      return
    end

    if choice.value == "empty" then
      start_typing_mode(origin_buf, target_lines, config)
    elseif choice.value == "file" then
      select_file_with_preview(origin_buf, target_lines, config)
    elseif choice.value == "buffer" then
      select_buffer_with_preview(origin_buf, target_lines, config)
    elseif choice.value == "register" then
      select_register_with_preview(origin_buf, target_lines, config)
    elseif choice.value == "git" then
      select_git_commit_with_preview(origin_buf, target_lines, config)
    end
  end)
end

-- Entry point with visual selection support
function M.show_picker(bufnr, start_line, end_line, config)
  local target_lines
  local is_visual_selection = false

  -- Prioritize explicit range parameters
  if start_line and end_line and start_line > 0 and end_line > 0 then
    target_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    is_visual_selection = true
  else
    -- Fall back to mark detection
    local mode = vim.api.nvim_get_mode().mode
    if mode:match("^[vV\026]") or (vim.fn.line("'<") > 0 and vim.fn.line("'>") > 0) then
      local mark_start = vim.fn.line("'<")
      local mark_end = vim.fn.line("'>")
      if mark_start > 0 and mark_end > 0 then
        if mode:match("^[vV\026]") then
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
        end
        target_lines = vim.api.nvim_buf_get_lines(bufnr, mark_start - 1, mark_end, false)
        is_visual_selection = true
      end
    end
  end

  -- If no visual selection, use whole buffer
  if not target_lines then
    target_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  -- Apply formatting/dedenting to target lines
  target_lines = buffer.prepare_lines(target_lines, bufnr, config)

  show_start_state_picker(bufnr, target_lines, is_visual_selection, config)
end

-- Direct access function for starting with whole buffer (backward compatibility)
function M.start_empty(bufnr, config)
  start_typing_mode(bufnr, nil, config)
end

return M
