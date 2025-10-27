# buffergolf.nvim

**A Neovim plugin for deliberate touch-typing and vim practice on actual code.**

Transform any buffer into an interactive practice environment. There are two modes:

1. Typing: Practice re-typing source code from scratch while seeing the reference text as ghost text. Get real-time feedback on your WPM and challenge yourself with countdown timers.
2. Golf: Open up a vertical split to compare two pieces of text (coming from buffers, registers, files, git commits, etc.). Try and convert the practice buffer to the reference buffer with the least amount of keystrokes. The reference buffer will have a git diff overlay for convenience.

INSERT DEMO VIDEO HERE.

## Requirements

- Neovim 0.11+
- [mini.diff](https://github.com/nvim-mini/mini.diff) (required for golf mode visualization)

## Installation

### lazy.nvim

#### Minimal Setup (Zero Configuration)

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
    config = true, -- uses default configuration
  },
}
```

#### Custom Setup

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
      -- Default values shown, all are optional
      disabled_plugins = "auto", -- auto-detect and disable conflicting plugins
      auto_dedent = true, -- auto-dedent practice buffer for consistent indentation
      keymaps = {
        toggle = "<leader>bg",
        countdown = "<leader>bG",
        golf = {
          next_hunk = "]h",
          prev_hunk = "[h",
          first_hunk = "[H",
          last_hunk = "]H",
        },
      },
      windows = {
        reference = {
          position = "right", -- "right", "left", "top", "bottom"
          size = 50, -- width for left/right, height for top/bottom
        },
        stats = {
          position = "top", -- "top" or "bottom"
          height = 3,
        },
      },
      -- Mode-specific overrides
      typing_mode = {
        disabled_plugins = {
          matchparen = true, -- disable match parens in typing mode
          treesitter_context = true, -- disable context in typing mode
        },
      },
      golf_mode = {
        disabled_plugins = {
          matchparen = false, -- keep match parens in golf mode
        },
      },
    },
  },
}
```

## Usage

### Quick Start

1. Open any file you want to practice with
2. Run `:Buffergolf` or press `<leader>bg` (default keymap). Your target text will be your buffer, or if in visual mode, it will be your visual selection.
3. Start typing! Your WPM and keystrokes are tracked as you type
4. The session completes automatically when you match the reference text

### Golf Mode Navigation

When practicing code transformation (golf mode), use these commands:

| Command | Default Keymap | Description |
|---------|----------------|-------------|
| `:BuffergolfNextHunk` | `]h` | Navigate to next diff |
| `:BuffergolfPrevHunk` | `[h` | Navigate to previous diff |
| `:BuffergolfFirstHunk` | `[H` | Navigate to first diff |
| `:BuffergolfLastHunk` | `]H` | Navigate to last diff |
| `:BuffergolfToggleOverlay` | `<leader>do` | Toggle diff overlay |

## Configuration

For detailed configuration options including:

- Plugin disabling customization
- Mode-specific settings
- Window positioning

See the **[Configuration Guide](docs/configuration.md)**.

## Keystroke Tracking & Golf Scoring

The plugin tracks every keystroke during practice, enabling golf-style scoring where the goal is to complete the text in the fewest keystrokes possible.

- **Keystroke Counter**: Real-time count in stats window
- **Par Calculation**: Shows "optimal" keystrokes min(character count + newlines + 1, character edit distance)
- **Golf Scoring**: Compare your count against par for efficiency

### Known Limitations

Some vim motion commands (like `G`, `gg`, `<C-u/d>`) may count as 3-5 keystrokes instead of 1 due to terminal escape sequences. This is a known limitation of tracking keystrokes at the vim level. Eventually will figure out a way for this to not be like that.

## Commands


| Command | Description |
|---------|-------------|
| `:Buffergolf` | Toggle practice session with mode selection |
| `:BuffergolfStop` | Stop active practice session |
| `:BuffergolfCountdown` | Start countdown timer practice |
| `:BuffergolfTyping` | Start typing practice (empty buffer) |


NOTE: `BufferGolfCountdown` will have unlimited time if you hit enter without putting in any time. Additionally, if you use `BufferGolfCountdown` on an active golf session, it will restart the session for you to try again from the beginning.

## Buffer Variables

The plugin sets `vim.b.buffergolf_practice = true` in practice buffers. Use this to conditionally disable conflicting plugins:

```lua
-- Example: Disable plugin in buffergolf practice buffers
if vim.b.buffergolf_practice then
  return
end
```

## Compatibility

You may find that you have some plugins that mess with ghost text or do things that you want disabled during golf sessions. For example, match parens in typing mode can actually be a little annoying. BufferGolf automatically detects and can disable many common plugins that might interfere with practice sessions. See the [Configuration Guide](docs/configuration.md#supported-plugins) for the full list of supported plugins and how to customize the behavior.

