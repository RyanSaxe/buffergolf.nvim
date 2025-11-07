# BufferGolf Configuration Guide

BufferGolf uses a flexible configuration system that allows you to customize how the plugin behaves during practice sessions.

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration Options](#configuration-options)
- [Mode-Specific Configuration](#mode-specific-configuration)
- [Window Configuration](#window-configuration)
- [Advanced Usage](#advanced-usage)

## Quick Start

Most users only need to configure keymaps. BufferGolf automatically handles plugin disabling and provides sensible defaults:

```lua
require("buffergolf").setup({
  -- Just set your preferred keymaps
  keymaps = {
    toggle = "<leader>bg",
    countdown = "<leader>bG",
    reset = "<leader>br",
  },
})
```

The default configuration automatically:

- Detects and disables interfering plugins during practice (`disabled_plugins = "auto"`)
- Provides appropriate mode-specific settings
- Uses sensible window positioning and highlights
- Tracks WPM, keystrokes, and accuracy metrics

## Configuration Options

### `disabled_plugins`

Controls which plugins and features are disabled during practice sessions. This helps create a distraction-free environment for focused practice.

#### Auto Mode (Default)

```lua
disabled_plugins = "auto"  -- Auto-detect and disable all known plugins
```

#### Selective Disabling

```lua
disabled_plugins = {
  copilot = true,
  diagnostics = true,
  inlay_hints = true,
  matchparen = true,
}
```

#### Auto with Exceptions

```lua
disabled_plugins = {
  _auto = true,        -- Start with auto-detection
  copilot = false,     -- But keep Copilot enabled
  cmp = false,         -- And keep completion
}
```

#### Custom Disable Functions

```lua
disabled_plugins = {
  _auto = true,
  my_plugin = function(ctx)
    -- Custom logic using context
    ctx:set_var("my_plugin_active", false)
    vim.cmd("MyPluginDisable")
  end,
}
```

### Mode-Specific Configuration

For advanced users who want different settings per mode, you can use `_inherit` to extend the base configuration:

```lua
{
  -- Common settings for both modes
  disabled_plugins = "auto",

  -- Typing mode specific (empty buffer)
  typing_mode = {
    disabled_plugins = {
      _inherit = true,           -- Inherit parent settings
      matchparen = true,         -- Additionally disable
      treesitter_context = true,
    }
  },

  -- Golf mode specific (code transformation)
  golf_mode = {
    disabled_plugins = {
      _inherit = true,
      matchparen = false,  -- Keep enabled for bracket navigation
    }
  }
}
```

### Keymaps

```lua
keymaps = {
  toggle = "<leader>bg",      -- Toggle practice mode
  countdown = "<leader>bG",    -- Start countdown timer
  golf = {                    -- Golf mode navigation
    next_hunk = "]h",
    prev_hunk = "[h",
    first_hunk = "[H",
    last_hunk = "]H",
    toggle_overlay = "<leader>do",
  }
}
```

### Window Positioning

```lua
windows = {
  reference = {
    position = "right",  -- "right", "left", "top", "bottom"
    size = 50,          -- percentage for vertical, lines for horizontal
  },
  stats = {
    position = "top",    -- "top", "bottom"
    height = 3,          -- number of lines
  },
}
```

### Other Options

```lua
{
  auto_dedent = true,  -- Strip common leading whitespace
}
```

### Customizing Appearance

BufferGolf uses the following highlight groups that you can customize in your colorscheme:

- `BuffergolfGhost` - Ghost text showing what to type next (defaults to Comment)
- `BuffergolfMismatch` - Incorrect characters (defaults to red with underline)
- `BuffergolfStatsFloat` - Stats window text
- `BuffergolfStatsBorder` - Stats window border
- `BuffergolfStatsComplete` - Stats when completed
- `BuffergolfStatsBorderComplete` - Border when completed

Example customization in your Neovim config:

```lua
vim.api.nvim_set_hl(0, "BuffergolfGhost", { fg = "#5c6370", italic = true })
vim.api.nvim_set_hl(0, "BuffergolfMismatch", { fg = "#e06c75", bg = "#3e2929", underline = true })
```

## Supported Plugins

BufferGolf can automatically detect and disable the following plugins:

### AI Assistants

- `copilot` - GitHub Copilot
- `codeium` - Codeium AI
- `supermaven` - Supermaven

### Completion

- `cmp` - nvim-cmp
- `blink` - blink.cmp
- `coq` - coq_nvim

### Auto-pairs

- `autopairs` - nvim-autopairs
- `minipairs` - mini.pairs
- `endwise` - vim-endwise

### Visual/UI

- `treesitter_context` - Treesitter context
- `indent_blankline` - Indent guides
- `cursorline` - Cursor line highlighting
- `colorcolumn` - Column markers
- `matchparen` - Bracket matching

### LSP Features

- `diagnostics` - Error/warning indicators
- `inlay_hints` - Type hints
- `matchup` - Enhanced % matching

### Other

- `closetag` - Auto-close HTML tags

## Context Object

When writing custom disable functions, you receive a context object with:

```lua
ctx = {
  buf = practice_buffer_id,      -- Practice buffer
  win = practice_window_id,      -- Practice window
  mode = "typing" or "golf",     -- Current mode
  origin_buf = original_buffer,  -- Original buffer

  -- Helper methods
  set_opt = function(option, value)    -- Set buffer option
  set_var = function(var, value)       -- Set buffer variable
  set_winvar = function(var, value)    -- Set window variable
  notify_err = function(msg)           -- Show error notification
}
```

## Complete Example

```lua
require("buffergolf").setup({
  -- Auto-detect and disable most plugins
  disabled_plugins = {
    _auto = true,
    cmp = false,  -- Keep completion enabled
  },

  -- Mode-specific settings
  typing_mode = {
    disabled_plugins = {
      _inherit = true,
      matchparen = true,
      treesitter_context = true,
    }
  },

  golf_mode = {
    disabled_plugins = {
      _inherit = true,
      matchparen = false,  -- Keep for navigation
    }
  },

  -- Custom keymaps
  keymaps = {
    toggle = "<leader>bg",
    countdown = "<leader>bG",
    golf = {
      next_hunk = "]h",
      prev_hunk = "[h",
    }
  },

  -- Window layout
  windows = {
    reference = {
      position = "right",
      size = 40,
    },
    stats = {
      position = "top",
      height = 3,
    },
  },

  -- Strip leading whitespace
  auto_dedent = true,
})
```

## Backwards Compatibility

The old configuration format is still supported and will be automatically converted:

```lua
-- Old format (still works)
{
  disable_diagnostics = true,
  disable_inlay_hints = true,
  disable_matchparen = true,
}

-- Converted to new format internally
{
  disabled_plugins = {
    diagnostics = true,
    inlay_hints = true,
    matchparen = true,
  }
}
```

## Adding Custom Plugins

You can register custom plugin handlers:

```lua
local disabled_plugins = require("buffergolf.disabled_plugins")

disabled_plugins.register("my_plugin", {
  detect = function()
    return vim.g.my_plugin_loaded == 1
  end,
  disable = function(ctx)
    ctx:set_var("my_plugin_enabled", false)
  end,
})
```

