# buffergolf.nvim

**A Neovim plugin for deliberate touch-typing practice, and vim practice, on actual code.**

Transform any buffer into an interactive typing practice environment. Practice re-typing source code from scratch while seeing the reference text as ghost text. Get real-time feedback on your WPM and challenge yourself with countdown timers.

INSERT DEMO VIDEO HERE.

## Features

- **Ghost Text Practice**: Reference text appears inline beyond what you've typed
- **Real-time Feedback**: Mismatched characters highlighted in red with underline
- **Live Statistics**: Floating window shows elapsed time, WPM, keystroke count, and par as you type
- **Visual Selection Support**: Practice on specific lines by making a visual selection
- **Countdown Mode**: Practice with time pressure
- **LSP-Friendly**: Practice buffer maintains normal functionality - completion, semantic features, and keymaps all work
- **Distraction-Free**: Diagnostics, inlay hints, and conflicting plugins automatically disabled
- **Auto-Completion Detection**: Session automatically locks when you match the reference perfectly
- **Filetype Preservation**: Practice buffer keeps the same filetype for syntax highlighting

NOTE: you may have to disable AI completion plugins (e.g., Copilot, Codeium) in practice buffers to avoid interference. See the [installation section](#installation) for examples.

## Keystroke Tracking & Golf Scoring

The plugin tracks every keystroke you make during practice sessions, enabling golf-style scoring where the goal is to complete the text in the fewest keystrokes possible.

### Features

- **Keystroke Counter**: Displays real-time keystroke count in the stats window
- **Par Calculation**: Shows the "optimal" number of keystrokes needed (calculated as character count + newlines + 1 for entering insert mode)
- **Golf Scoring**: Compare your keystroke count against par to see how efficiently you're typing

### Known Limitations

**Motion Command Counting**: Some vim motion commands (like `G` to go to end of file, `gg` to go to beginning) may count as 3-5 keystrokes instead of 1. This is due to terminal escape sequences that vim uses internally for cursor positioning that are difficult to filter out completely.

- Insert mode counting is accurate (every key you type counts as 1)
- Most normal mode commands count correctly
- Large cursor movements (G, gg, H, M, L) may over-count by a few keystrokes
- This is a known limitation of tracking keystrokes at the vim level

The keystroke tracking uses a "command depth" approach with a timer to filter out most internal vim operations, but some escape sequences still get through, especially for large cursor movements. Despite this limitation, the counts are consistent and useful for tracking your improvement over time.

## Requirements

- Neovim 0.11+
- [mini.diff](https://github.com/nvim-mini/mini.diff) (required for golf mode visualization)

## Installation

### lazy.nvim (LazyVim)

**Basic Setup**

Add to your `~/.config/nvim/lua/plugins/buffergolf.lua`:

```lua
return {
  {
    "nvim-mini/mini.diff",
    config = function()
      require('mini.diff').setup()
    end,
  },
  {
    "ryansaxe/buffergolf.nvim",
    dependencies = { "nvim-mini/mini.diff" },
    opts = {},
  },
}
```

**Custom Configuration**

```lua
return {
  {
    "nvim-mini/mini.diff",
    config = function()
      require('mini.diff').setup()
    end,
  },
  {
    "ryansaxe/buffergolf.nvim",
    dependencies = { "nvim-mini/mini.diff" },
    opts = {
      -- Highlight groups
      ghost_hl = "BuffergolfGhost",
      mismatch_hl = "BuffergolfMismatch",

      -- Disable distracting features
      disable_diagnostics = true,
      disable_inlay_hints = true,
      disable_matchparen = true,

      -- Automatically remove common leading whitespace
      auto_dedent = true,

      -- Keymaps (set to false to disable default keymaps)
      keymaps = {
        toggle = "<leader>bg",     -- Toggle practice session
        countdown = "<leader>bG",  -- Start countdown mode

        -- Golf mode navigation (only active during golf sessions)
        golf_mode = {
          next_hunk = "]h",        -- Go to next diff hunk
          prev_hunk = "[h",        -- Go to previous diff hunk
          first_hunk = "[H",       -- Go to first diff hunk
          last_hunk = "]H",        -- Go to last diff hunk
          toggle_overlay = "<leader>do", -- Toggle diff overlay
        },
      },
    },
  },
}
```

**Disable Copilot in Practice Buffers**

If you use Copilot, disable it in practice buffers using an autocmd:

```lua
return {
  "ryansaxe/buffergolf.nvim",
  opts = {},
  config = function(_, opts)
    require("buffergolf").setup(opts)

    -- Disable Copilot in practice buffers
    local group = vim.api.nvim_create_augroup("BufferGolfCopilotMute", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
      group = group,
      callback = function(event)
        local buf = event.buf
        local ok, is_practice = pcall(vim.api.nvim_buf_get_var, buf, "buffergolf_practice")
        if ok and is_practice then
          vim.b[buf].copilot_enabled = false
        else
          pcall(vim.api.nvim_buf_del_var, buf, "copilot_enabled")
        end
      end,
    })
  end,
}
```

## Usage

### Starting a Practice Session

**Method 1: Command**

```vim
:Buffergolf
```

**Method 2: Keymap** (default: `<leader>bg`)

```
<leader>bg
```

**What happens:**

1. Current buffer becomes the reference
2. Empty scratch buffer opens with the same filetype
3. Reference text appears as ghost text
4. Timer starts on your first keystroke
5. Mismatches highlighted in real-time
6. Stats window shows time, WPM, keystroke count, and par

### Visual Selection Mode

Practice on specific lines instead of the entire buffer:

**Method 1: Visual Mode + Keymap**

1. Select lines in visual mode (`V` for line-wise)
2. Press `<leader>bg` to start practice session
3. Or press `<leader>bG` for countdown mode

**Method 2: Command with Range**

```vim
:5,20Buffergolf           " Practice lines 5-20
:5,20BuffergolfCountdown  " Countdown mode on lines 5-20
```

The selected lines become your practice target while the rest of the buffer is ignored.

### Countdown Mode

Challenge yourself with a time limit:

```vim
:BuffergolfCountdown
" Enter duration in seconds (e.g., 60 for 1 minute)
```

Or use the keymap (default: `<leader>bG`):

```
<leader>bG
```

Timer counts down and session locks when time expires.

### Stopping a Session

**Method 1: Toggle off**

```vim
:Buffergolf  " or <leader>bg
```

**Method 2: Explicit stop**

```vim
:BuffergolfStop
```

Practice buffer closes without saving prompts and returns to original buffer.

### Completion

When your practice buffer exactly matches the reference:

- Buffer automatically locks
- Stats freeze with final time and WPM
- Green checkmark appears in stats window
- Notification: "Completed!"

## Configuration

### Default Configuration

```lua
return {
  "ryansaxe/buffergolf.nvim",
  opts = {
    -- Highlight for reference ghost text (linked to Comment by default)
    ghost_hl = "BuffergolfGhost",

    -- Highlight for mismatched characters (red + underline by default)
    mismatch_hl = "BuffergolfMismatch",

    -- Disable LSP diagnostics in practice buffer (recommended)
    disable_diagnostics = true,

    -- Disable LSP inlay hints in practice buffer (recommended)
    disable_inlay_hints = true,

    -- Disable matchparen highlighting (keeps ghost text clean)
    disable_matchparen = true,

    -- Automatically remove common leading whitespace from practice text
    auto_dedent = true,

    -- Keymaps
    keymaps = {
      toggle = "<leader>bg",     -- Toggle practice session
      countdown = "<leader>bG",  -- Start countdown mode
    },
  },
}
```

### Custom Highlight Colors

To customize the appearance:

```lua
-- After calling setup(), or in your colorscheme config
vim.api.nvim_set_hl(0, "BuffergolfGhost", { fg = "#5c6370", italic = true })
vim.api.nvim_set_hl(0, "BuffergolfMismatch", { fg = "#e06c75", underline = true, bg = "#3e2929" })
```

### Lualine Configuration

If you use lualine.nvim for your statusline, you'll need to add `BuffergolfStats` to your disabled filetypes to prevent lualine from showing on the stats window:

```lua
require('lualine').setup {
  options = {
    disabled_filetypes = {
      statusline = { "BuffergolfStats", ... },  -- Add to your existing list
      winbar = { "BuffergolfStats", ... },      -- Add to your existing list
    },
  },
}
```

This ensures the stats window displays cleanly without any statusline or winbar interference.

### Disable Default Keymaps

```lua
return {
  "ryansaxe/buffergolf.nvim",
  opts = {
    keymaps = {
      toggle = false,     -- Disable default toggle keymap
      countdown = false,  -- Disable default countdown keymap
    },
  },
  keys = {
    { "<leader>tp", "<cmd>Buffergolf<cr>", desc = "Toggle Buffergolf" },
    { "<leader>tc", "<cmd>BuffergolfCountdown<cr>", desc = "Buffergolf Countdown" },
  },
}
```

## Commands

### Global Commands

| Command | Description |
|---------|-------------|
| `:Buffergolf` | Toggle practice session for current buffer (supports range, e.g., `:5,20Buffergolf`) |
| `:BuffergolfStop` | Stop active practice session |
| `:BuffergolfCountdown` | Start countdown timer practice (supports range, e.g., `:5,20BuffergolfCountdown`) |
| `:BuffergolfTyping` | Start typing practice (empty starting buffer) |

### Golf Mode Commands

When in golf mode (practicing code transformation), these buffer-local commands are available:

| Command | Description | Default Keymap |
|---------|-------------|----------------|
| `:BuffergolfNextHunk` | Navigate to next diff hunk (synchronized) | `]h` |
| `:BuffergolfPrevHunk` | Navigate to previous diff hunk (synchronized) | `[h` |
| `:BuffergolfFirstHunk` | Navigate to first diff hunk (synchronized) | `[H` |
| `:BuffergolfLastHunk` | Navigate to last diff hunk (synchronized) | `]H` |
| `:BuffergolfToggleOverlay` | Toggle mini.diff overlay visualization | `<leader>do` |

**Golf Mode Features:**
- **Synchronized Navigation**: When navigating to hunks, both practice and reference windows scroll together, accounting for line additions/deletions
- **Keystroke-Free Navigation**: Navigation commands don't count toward your keystroke score
- **Diff Overlay**: Shows detailed word-level differences between buffers (enabled by default)
- **Customizable Keymaps**: All navigation keymaps can be customized or disabled in config

## How It Works

1. **Session Creation**: Captures current buffer content as reference
2. **Scratch Buffer**: Opens unlisted scratch buffer with same filetype
3. **Visual Rendering**: Uses extmarks for ghost text, highlights for mismatches
4. **Change Detection**: Attaches to buffer events, updates visuals on every keystroke
5. **Statistics**: Calculates WPM as `(correct_chars / 5) / minutes`
6. **Completion Check**: Compares buffer to reference on every change
7. **Cleanup**: Removes extmarks, highlights, and autocommands on session end

## Module Architecture

- `lua/buffergolf/session.lua` orchestrates session lifecycle, wiring timer and keystroke modules.
- `lua/buffergolf/visual.lua` manages ghost text extmarks, mismatch highlights, and buffer change watchers.
- `lua/buffergolf/golf.lua` handles golf-mode reference windows, mini.diff integration, and synchronized navigation.
- `lua/buffergolf/buffer.lua` provides shared buffer/window helpers reused across modules.
- `lua/buffergolf/keystroke.lua` tracks command initiations, including the shared `with_keys_disabled` helper.
- `lua/buffergolf/timer.lua` renders timer overlays and session statistics.

## Buffer Variables

The plugin sets `vim.b.buffergolf_practice = true` in practice buffers. Use this to conditionally disable conflicting plugins:

```lua
-- Example: Disable plugin in buffergolf practice buffers
if vim.b.buffergolf_practice then
  return
end
```

## Compatibility

The plugin automatically handles common compatibility issues:

**Automatically Disabled:**

- `mini.pairs` autopairs
- `nvim-autopairs`
- `nvim-matchup` bracket matching
- Builtin MatchParen highlighting
- LSP diagnostics (configurable)
- LSP inlay hints (configurable)
- Copilot

You can re-enable these features in practice buffers by setting the respective options to `false` in the setup configuration. I just find, when practicing, these are more distracting than helpful due to how that can interfere with the ghost text and visual clarity.

**Recommended Manual Disabling:**

If you have any plugins that add ghost text, I suggest disabling them in practice buffers. These buffers work fine with completion (e.g. blink.cmp), but you should disable the ghost-text features to avoid visual clutter and interference.

See the [installation section](#installation) for examples.
