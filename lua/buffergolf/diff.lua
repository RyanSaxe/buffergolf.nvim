local M = {}

-- Create highlight groups for diff display
local function setup_highlights()
  -- Line added (green)
  if not pcall(vim.api.nvim_get_hl, 0, { name = "BuffergolfDiffAdd" }) then
    vim.api.nvim_set_hl(0, "BuffergolfDiffAdd", {
      bg = "#1a3d1a",
      fg = "#7fdc7f",
    })
  end

  -- Line changed (yellow/orange)
  if not pcall(vim.api.nvim_get_hl, 0, { name = "BuffergolfDiffChange" }) then
    vim.api.nvim_set_hl(0, "BuffergolfDiffChange", {
      bg = "#3d3d1a",
      fg = "#dcdc7f",
    })
  end

  -- Line deleted indicator (red) - shown in gutter or as virtual text
  if not pcall(vim.api.nvim_get_hl, 0, { name = "BuffergolfDiffDelete" }) then
    vim.api.nvim_set_hl(0, "BuffergolfDiffDelete", {
      bg = "#3d1a1a",
      fg = "#dc7f7f",
    })
  end

  -- Text added within a line (bright green)
  if not pcall(vim.api.nvim_get_hl, 0, { name = "BuffergolfDiffTextAdd" }) then
    vim.api.nvim_set_hl(0, "BuffergolfDiffTextAdd", {
      bg = "#2a4d2a",
      fg = "#9ffc9f",
      bold = true,
    })
  end

  -- Text deleted within a line (bright red)
  if not pcall(vim.api.nvim_get_hl, 0, { name = "BuffergolfDiffTextDelete" }) then
    vim.api.nvim_set_hl(0, "BuffergolfDiffTextDelete", {
      bg = "#4d2a2a",
      fg = "#fc9f9f",
      bold = true,
    })
  end
end

-- Simple line-level diff algorithm
local function compute_line_diff(practice_lines, target_lines)
  local diff_info = {}
  local max_lines = math.max(#practice_lines, #target_lines)

  for i = 1, max_lines do
    local practice_line = practice_lines[i] or ""
    local target_line = target_lines[i] or ""

    if i > #practice_lines then
      -- Line needs to be added (doesn't exist in practice)
      table.insert(diff_info, {
        line = i,
        type = "add",
        target = target_line,
      })
    elseif i > #target_lines then
      -- Line needs to be deleted (exists in practice but not target)
      -- Can't highlight in target buffer since line doesn't exist there
      table.insert(diff_info, {
        line = i,
        type = "delete",
        practice = practice_line,
      })
    elseif practice_line ~= target_line then
      -- Line needs to be changed
      table.insert(diff_info, {
        line = i,
        type = "change",
        practice = practice_line,
        target = target_line,
      })
    else
      -- Lines match - no diff
      table.insert(diff_info, {
        line = i,
        type = "match",
      })
    end
  end

  return diff_info
end

-- Get character-level differences within a line
local function get_inline_diff(practice_line, target_line)
  if not practice_line or not target_line then
    return nil
  end

  local highlights = {}

  -- Simple character-by-character comparison
  -- For a more sophisticated approach, we could use a proper diff algorithm
  local min_len = math.min(#practice_line, #target_line)
  local start_diff = nil

  for i = 1, min_len do
    local p_char = practice_line:sub(i, i)
    local t_char = target_line:sub(i, i)

    if p_char ~= t_char then
      if not start_diff then
        start_diff = i - 1  -- 0-indexed for highlights
      end
    elseif start_diff then
      -- End of difference region
      table.insert(highlights, { start = start_diff, finish = i - 1 })
      start_diff = nil
    end
  end

  -- Handle remaining characters if one line is longer
  if start_diff then
    table.insert(highlights, { start = start_diff, finish = min_len })
    start_diff = nil
  end

  if #target_line > #practice_line then
    table.insert(highlights, { start = #practice_line, finish = #target_line })
  end

  return highlights
end

-- Apply diff highlights to the reference buffer
function M.apply_diff_highlights(session)
  if not session.reference_buf or not vim.api.nvim_buf_is_valid(session.reference_buf) then
    vim.notify("BufferGolf: No valid reference buffer for diff highlights", vim.log.levels.DEBUG)
    return
  end

  local ns = session.ns_diff
  if not ns then
    session.ns_diff = vim.api.nvim_create_namespace("BuffergolfDiffNS")
    ns = session.ns_diff
  end

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(session.reference_buf, ns, 0, -1)

  -- Setup highlight groups
  setup_highlights()

  -- Get current lines from both buffers
  local ok_practice, practice_lines = pcall(vim.api.nvim_buf_get_lines, session.practice_buf, 0, -1, false)
  local ok_target, target_lines = pcall(vim.api.nvim_buf_get_lines, session.reference_buf, 0, -1, false)

  if not ok_practice or not ok_target then
    return
  end

  -- Compute the diff
  local diff_info = compute_line_diff(practice_lines, target_lines)

  -- Count diff types for debugging
  local diff_counts = { add = 0, change = 0, delete = 0, match = 0 }
  for _, diff in ipairs(diff_info) do
    diff_counts[diff.type] = (diff_counts[diff.type] or 0) + 1
  end

  -- Log diff summary (only in debug mode if needed)
  if vim.g.buffergolf_debug then
    vim.notify(string.format("BufferGolf diff: %d adds, %d changes, %d deletes, %d matches",
      diff_counts.add, diff_counts.change, diff_counts.delete, diff_counts.match), vim.log.levels.DEBUG)
  end

  -- Apply highlights based on diff
  for _, diff in ipairs(diff_info) do
    local line_num = diff.line - 1  -- 0-indexed for nvim API

    if line_num < #target_lines then  -- Can only highlight lines that exist
      if diff.type == "add" then
        -- Highlight entire line as needing to be added
        local line_text = target_lines[line_num + 1] or ""
        vim.api.nvim_buf_set_extmark(
          session.reference_buf,
          ns,
          line_num,
          0,
          {
            end_col = #line_text,
            hl_eol = true,  -- Highlight to end of line including EOL
            hl_group = "BuffergolfDiffAdd",
            priority = 100
          }
        )
      elseif diff.type == "change" then
        -- Highlight line as needing changes
        local line_text = target_lines[line_num + 1] or ""
        vim.api.nvim_buf_set_extmark(
          session.reference_buf,
          ns,
          line_num,
          0,
          {
            end_col = #line_text,
            hl_eol = true,  -- Highlight to end of line including EOL
            hl_group = "BuffergolfDiffChange",
            priority = 100
          }
        )

        -- Add inline diff highlights if lines are similar enough
        local inline_diffs = get_inline_diff(diff.practice, diff.target)
        if inline_diffs and #inline_diffs > 0 then
          for _, range in ipairs(inline_diffs) do
            vim.api.nvim_buf_set_extmark(
              session.reference_buf,
              ns,
              line_num,
              range.start,
              {
                end_col = range.finish,
                hl_group = "BuffergolfDiffTextAdd",
                priority = 110  -- Higher priority for inline diffs
              }
            )
          end
        end
      end
    end

    -- For delete type, we could add virtual text or signs, but for now we'll skip
    -- since the line doesn't exist in the reference buffer
  end

  -- Add virtual text indicators for lines that need to be deleted
  local delete_count = 0
  for _, diff in ipairs(diff_info) do
    if diff.type == "delete" then
      delete_count = delete_count + 1
    end
  end

  if delete_count > 0 then
    -- Add a virtual text at the end showing deletion needed
    local last_line = #target_lines - 1
    if last_line >= 0 then
      vim.api.nvim_buf_set_extmark(
        session.reference_buf,
        ns,
        last_line,
        0,
        {
          virt_text = { { string.format(" [%d line(s) to delete]", delete_count), "BuffergolfDiffDelete" } },
          virt_text_pos = "eol",
        }
      )
    end
  end
end

-- Clear diff highlights
function M.clear_diff_highlights(session)
  if session.ns_diff and session.reference_buf and vim.api.nvim_buf_is_valid(session.reference_buf) then
    vim.api.nvim_buf_clear_namespace(session.reference_buf, session.ns_diff, 0, -1)
  end
end

-- Initialize diff highlighting for a session
function M.init(session)
  setup_highlights()
  session.ns_diff = vim.api.nvim_create_namespace("BuffergolfDiffNS")
end

return M