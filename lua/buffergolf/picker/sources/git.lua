local adapter = require("buffergolf.picker.adapter")

local M = {}

local function get_relative_path(filepath, git_root)
  if filepath:sub(1, #git_root) == git_root then
    return filepath:sub(#git_root + 2)
  end
  return vim.fn.fnamemodify(filepath, ":.")
end

local function get_file_at_commit(commit, relative_path)
  local git_object = string.format("%s:%s", commit, relative_path)
  local lines = vim.fn.systemlist({ "git", "show", git_object })
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get file at commit " .. commit, vim.log.levels.ERROR, { title = "buffergolf" })
    return nil
  end
  return lines
end

function M.select(origin_buf, target_lines, config, start_golf_fn)
  local filepath = vim.api.nvim_buf_get_name(origin_buf)
  if filepath == "" then
    vim.notify("Current buffer has no file path", vim.log.levels.WARN, { title = "buffergolf" })
    return
  end

  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if vim.v.shell_error ~= 0 then
    vim.notify("Not in a git repository", vim.log.levels.WARN, { title = "buffergolf" })
    return
  end

  local relative_path = get_relative_path(filepath, git_root)

  if adapter.has_snacks() then
    local snacks = require("snacks.picker")
    snacks.git_log_file({
      file = filepath,
      confirm = function(picker, item)
        if item and item.commit then
          local lines = get_file_at_commit(item.commit, relative_path)
          if lines then
            picker:close()
            start_golf_fn(origin_buf, lines, target_lines, config)
          end
        else
          vim.notify("Failed to resolve commit for selection", vim.log.levels.WARN, { title = "buffergolf" })
        end
      end,
    })
  else
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
        table.insert(commit_options, { label = commit_line, value = hash })
      end
    end

    vim.ui.select(commit_options, {
      prompt = "Select commit as starting point:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        local lines = get_file_at_commit(choice.value, relative_path)
        if lines then
          start_golf_fn(origin_buf, lines, target_lines, config)
        end
      end
    end)
  end
end

function M.is_available()
  local cwd = vim.fn.getcwd()
  vim.fn.system({ "git", "rev-parse", "--is-inside-work-tree" })
  return vim.v.shell_error == 0
end

return M
