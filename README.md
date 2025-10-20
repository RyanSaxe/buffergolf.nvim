# Keymash.nvim (buffergolf prototype)

Practice re-typing any buffer from scratch inside a dedicated scratch buffer. The reference text appears as ghost text; you type into a normal buffer with your usual plugins and keymaps. Any character that diverges from the reference is highlighted in red with an underline.

## Features
- Scratch buffer mirrors the source filetype but starts empty
- Reference text displayed as inline ghost text (per-line preview)
- Divergent characters are highlighted with a customizable group (red + underline by default)
- Diagnostics and other ghost text sources (cmp, Copilot) disabled inside the practice buffer
- Buffer is marked `buftype=nofile` so it cannot be written accidentally

## Requirements
- Neovim 0.9+ (API used: `nvim_set_hl`, extmarks, autocmds)

## Install
### lazy.nvim
```lua
{
  "yourname/keymash.nvim",
  config = function()
    require("keymash").setup()
  end,
}
```

### packer.nvim
```lua
use {
  "yourname/keymash.nvim",
  config = function()
    require("keymash").setup()
  end,
}
```

## Usage
- `:Keymash` — toggle practice for the current buffer
- `:KeymashStop` — stop the session if active

What happens when you start a session:
- A new scratch buffer replaces the current window (the original buffer stays untouched)
- The scratch buffer keeps the same `filetype`, so Treesitter, keymaps, and commands continue to work
- Reference text appears as ghost text past the portion you have already typed
- Any mismatching characters in your buffer are highlighted red+underline via `BuffergolfMismatch`

## Configuration
```lua
require("keymash").setup({
  ghost_hl = "BuffergolfGhost",          -- highlight for reference ghost text (defaults link to Comment)
  mismatch_hl = "BuffergolfMismatch",    -- highlight for mismatched characters (defaults red + underline)
  disable_diagnostics = true,            -- disable LSP diagnostics in the practice buffer
  disable_external_ghost = true,         -- turn off common ghost text providers (cmp, Copilot, etc.)
})
```
Both highlight groups include cterm fallbacks and are re-applied on `ColorScheme`.

### Compatibility notes
- Typing happens in a normal modifiable buffer—no more overtype tricks or blocked normal-mode operators.
- When `disable_external_ghost` is `true`, the buffer sets common `b:*` flags to disable nvim-cmp ghost text and GitHub Copilot inline suggestions. If your setup uses a different namespace, add your own tweak via an autocmd on `User KeymashStarted` (planned) or by editing `session.lua`.
- Diagnostics are disabled per-buffer so LSP servers do not flood the buffer with warnings as you type.

## How It Works
- Captures the current buffer’s contents as reference lines
- Opens a `buftype=nofile` scratch buffer that shares the original `filetype`
- Renders reference text as per-line ghost text using extmarks
- Re-computes a simple per-line diff on every text change; mismatched characters receive a highlight overlay
- Keeps the buffer length in sync with the reference so you always see upcoming ghost text

## Roadmap
- Provide an API to supply custom reference text (instead of reading from the current buffer)
- Add lightweight stats (accuracy/WPM) for completed runs
- Optional rename to `buffergolf.nvim` with a migration alias

## Contributing
Issues and PRs are welcome. Please include a minimal reproduction for visual or highlight issues (Neovim version, colorscheme, and a short snippet). Thanks!
