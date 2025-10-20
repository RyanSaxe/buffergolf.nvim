# buffergolf.nvim

**A Neovim plugin for deliberate touch-typing practice, and vim practice, on actual code.**

Transform any buffer into an interactive typing practice environment. Practice re-typing source code from scratch while seeing the reference text as ghost text. Get real-time feedback on your WPM and challenge yourself with countdown timers.

INSERT DEMO VIDEO HERE.

## Features

- **Ghost Text Practice**: Reference text appears inline beyond what you've typed
- **Real-time Feedback**: Mismatched characters highlighted in red with underline
- **Live Statistics**: Floating window shows elapsed time and WPM as you type
- **Countdown Mode**: Practice with time pressure
- **LSP-Friendly**: Practice buffer maintains normal functionality - completion, semantic features, and keymaps all work
- **Distraction-Free**: Diagnostics, inlay hints, and conflicting plugins automatically disabled
- **Auto-Completion Detection**: Session automatically locks when you match the reference perfectly
- **Filetype Preservation**: Practice buffer keeps the same filetype for syntax highlighting

NOTE: you may have to disable AI completion plugins (e.g., Copilot, Codeium) in practice buffers to avoid interference. See the [installation section](#installation) for examples.

## Requirements

- Neovim 0.11+

## Installation

### lazy.nvim (LazyVim)

**Basic Setup**

Add to your `~/.config/nvim/lua/plugins/buffergolf.lua`:

```lua
return {
  "ryansaxe/buffergolf.nvim",
  opts = {},
}
```

**Custom Configuration**

```lua
return {
  "ryansaxe/buffergolf.nvim",
  opts = {
    -- Highlight groups
    ghost_hl = "BuffergolfGhost",
    mismatch_hl = "BuffergolfMismatch",

    -- Disable distracting features
    disable_diagnostics = true,
    disable_inlay_hints = true,
    disable_matchparen = true,

    -- Keymaps (set to false to disable default keymaps)
    keymaps = {
      toggle = "<leader>bg",     -- Toggle practice session
      countdown = "<leader>bG",  -- Start countdown mode
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
6. Stats window shows time and WPM

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

| Command | Description |
|---------|-------------|
| `:Buffergolf` | Toggle practice session for current buffer |
| `:BuffergolfStop` | Stop active practice session |
| `:BuffergolfCountdown` | Start countdown timer practice |

## How It Works

1. **Session Creation**: Captures current buffer content as reference
2. **Scratch Buffer**: Opens unlisted scratch buffer with same filetype
3. **Visual Rendering**: Uses extmarks for ghost text, highlights for mismatches
4. **Change Detection**: Attaches to buffer events, updates visuals on every keystroke
5. **Statistics**: Calculates WPM as `(correct_chars / 5) / minutes`
6. **Completion Check**: Compares buffer to reference on every change
7. **Cleanup**: Removes extmarks, highlights, and autocommands on session end

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
