# Keymash.nvim

Practice typing any buffer’s contents directly inside Neovim without changing the file. The text appears dim; as you type, correct characters reveal the original syntax colors and mistakes show in red.

## Features
- Overtype practice in-place: no edits to the buffer
- Dimmed text reveals on correct keystrokes; wrong chars marked red
- Uses your filetype’s syntax highlighting for “correct” text
- Simple start/stop commands and safe cleanup
- Works across colorschemes (reacts to `ColorScheme`)

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

Type in Insert mode:
- Matching characters reveal original syntax colors
- Mismatches show as red overlays
- Backspace clears the last typed character and returns it to dim

## Configuration
```lua
require("keymash").setup({
  dim_hl = "KeymashDim",      -- dim highlight group (defaults link to Comment)
  correct_hl = "KeymashCorrect", -- used only for error fallback; correct reveals syntax
  error_hl = "KeymashError",    -- red overlay for incorrect chars
  cursor_hl = "KeymashCursor",  -- optional helper group
  dim_blend = 70,               -- intensity for dim fallback
  auto_tab = true,              -- treat <Tab>/space as correct when expected is a tab
  auto_scroll = true,           -- keep folds opened as you type (future use)
})
```
All highlight groups include cterm fallbacks and are re-applied on `ColorScheme`.

## How It Works
- Captures the current buffer’s text and opens a scratch practice buffer
- Applies a full-line dim highlight via namespace
- Intercepts typing (`InsertCharPre`) and cancels insertion, advancing the cursor
- For correct chars, it removes the dim at that column so your syntax color shows
- For errors, it overlays a red 1‑char extmark

## Roadmap
- Visual selection support (`start_visual`) to practice ranges
- Optional floating window UI
- Stats (accuracy/WPM) per session

## Contributing
Issues and PRs are welcome. Please include a minimal reproduction for visual or highlight issues (Neovim version, colorscheme, and a short snippet). Thanks!
