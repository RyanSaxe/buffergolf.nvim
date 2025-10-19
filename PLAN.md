# Keymash.nvim Refactor Plan

## Goal
Build a Neovim 0.11+ plugin that lets users practice typing any snippet or buffer region inside an isolated practice buffer. The buffer should present the text dimmed by default, reveal correctly typed characters, and mark mistakes in red while preserving normal Neovim behavior and navigation.

## High-Level Workflow
1. User runs a command (e.g., `:Keymash`) optionally passing text. Defaults to current buffer contents, with helper for visual selections.
2. Plugin opens a scratch practice buffer with filetype `keymash`, `buftype=acwrite`, `bufhidden=wipe`, and no swapfile.
3. Text is inserted, fully dimmed, and event handlers track typing to toggle highlights.
4. Users type like normal—correct characters turn default color, incorrect ones become red until fixed. Normal mode navigation remains accessible.

## Core Modules
- `lua/keymash/init.lua`: setup, user commands, extraction helpers for buffer/selection text, exposes `start_text(text)`.
- `lua/keymash/buffer.lua`: creates practice buffer, configures options, manages highlight namespaces, handles lifecycle.
- `lua/keymash/highlight.lua` (optional utility) to centralize dim/correct/error highlight updates.

## Configuration
- `auto_tab = true`: when expected char is `\t`, automatically insert a literal tab even if user presses spaces (configurable).
- Highlight group overrides: `dim_hl`, `correct_hl`, `error_hl` with default colors and dim intensity.
- Optional mapping toggles (e.g., `vim.keymap.set("x", ...)` for visual selections).

## Practice Buffer Behavior
### Buffer Setup
- Clear scratch buffer, set filetype `keymash`, disable number columns, signcolumn, list, etc.
- Apply dim highlight over entire buffer via namespace (e.g., extmarks with `hl_eol=true`).

### Event Handling
- `InsertEnter`: capture expected text snapshot (array of characters indexed per byte position) and initialize state.
- `InsertCharPre`: determine typed character vs expected char at cursor (account for `\n`, `\t`).
  - If match: change highlight at that position to `correct_hl`.
  - If mismatch: leave typed char, highlight as `error_hl`.
- `TextChangedI`/`TextChanged`: re-evaluate affected line(s) to keep highlights accurate when user edits/deletes.
- `CursorMoved`/`CursorMovedI`: ensure cursor remains within text; optionally show ghost highlight.

### Highlight Management
- Dim namespace covers buffer initially.
- Correct highlights use `hl_mode='combine'` to overlay original text color.
- Errors override with `error_hl`.
- Recompute per character by tracking buffer text vs original sequence (array or rope).

### Auto Tab Handling
- When `auto_tab` enabled and expected char is `\t`, intercept spaces/tabs to insert actual tab and keep highlight correct.
- Optionally respect indentation width if user prefers spaces (`auto_tab=false`).

## Commands & Helpers
- `:Keymash [text]`: start practice with provided text (string argument or current buffer if empty).
- `require('keymash').start_range(bufnr, start_pos, end_pos)`: programmatic API.
- Default visual mapping: `xnoremap <leader>km :<C-u>lua require('keymash').start_visual()<CR>`.

## State Management
- Store active practice buffer id, original text, highlight metadata in module-level tables keyed by buffer.
- Clear state on buffer wipeout or command exit.

## Cleanup
- Autocommands for `BufWipeout` and `BufLeave` to remove namespaces and state.
- Provide `:KeymashStop` to manually exit.

## Testing Strategy
- Manual: start practice buffer from various files, ensure correct/incorrect highlighting, normal-mode navigation, undo/redo.
- Automated (later): use busted/plenary to simulate buffer edits verifying highlight updates.

## Future Enhancements
1. Stats tracking per session (accuracy, WPM) and persistent storage.
2. Animated average-speed cursor using timers.
3. Syntax-aware dimming by capturing treesitter highlight info before conversion.
