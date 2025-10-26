# Testing Plan

## Goals

- Establish a headless Neovim testing harness so Lua modules can run inside a real `vim` context.
- Provide fast local test execution plus automated validation in CI (GitHub Actions).
- Cover both pure Lua utilities and session-oriented workflows that manipulate buffers, windows, and timers.

## Tooling Overview

- **Test runner:** `plenary.nvim` busted harness (`:PlenaryBustedDirectory`) executed via `nvim --headless`.
- **Runtime bootstrap:** `tests/minimal_init.lua` to configure `runtimepath`, stub noisy APIs, and load plugin dependencies.
- **Dependencies:** clone `nvim-lua/plenary.nvim` (test harness) and `nvim-mini/mini.diff` (runtime requirement) into `tests/deps`.
- **Helpers:** `tests/helpers.lua` with utilities to create scratch buffers, build faux session tables, override `vim.notify`, and stub optional modules such as `mini.diff`.
- **Make target:** `make test` (or equivalent `just`/shell script) invoking the headless command for parity with CI.

## Test Suite Layout

```
tests/
  minimal_init.lua     -- headless bootstrap
  helpers.lua          -- shared utilities/mocks
  unit/
    buffer_spec.lua
    stats_spec.lua
  integration/
    session_spec.lua
    golf_spec.lua
    timer_spec.lua
```

### Unit Candidates

- `lua/buffergolf/buffer.lua`
  - `generate_buffer_name` (named & unnamed buffers, existing file warning).
  - `dedent_lines` and `prepare_lines` (auto-dedent logic, tab expansion, edge cases).
- `lua/buffergolf/stats.lua`
  - `calculate_edit_distance`, `calculate_par` (difficulty multipliers, fallback without `mini.diff`).
  - `count_correct_characters` (mismatch halting, whitespace trimming).

### Integration Candidates

- `lua/buffergolf/session.lua`
  - `start` / `stop`: buffer options, ghost text refresh, namespace setup.
  - `reset_to_start`: mode-specific content reset, keystroke counters, timer state.
- `lua/buffergolf/golf.lua`
  - `create_reference_window` & `setup_navigation`: split placement, synchronized movement (with stubbed hunks).
- `lua/buffergolf/timer.lua`
  - Countdown lifecycle: buffer locking, frozen stats, notifications.
- Shared keystroke tracking: ensure `vim.on_key` handler increments and respects lock state (guard against multiple registrations).

## GitHub Actions Workflow

- Trigger on `push` and `pull_request`.
- Steps:
  1. `actions/checkout@v4`
  2. `neovim/setup-neovim@v1` (pin to latest stable or 0.11).
  3. Cache `tests/deps` to avoid repeated plugin clones.
  4. Run `make test`.
  5. Optionally upload test logs/artifacts for debugging failures.

## Implementation Checklist

1. Add `tests/` scaffold (`minimal_init.lua`, `helpers.lua`, directory structure).
2. Script dependency bootstrap inside `minimal_init.lua` (ensure idempotent clones).
3. Write unit specs for buffer/stat helpers.
4. Add integration specs exercising session lifecycle, golf navigation, and timer completion.
5. Create `Makefile` (or update existing tooling) with a `test` target calling the headless command.
6. Introduce GitHub Action workflow running the new tests.
7. Expand coverage incrementally (e.g., picker workflows) once core suite is stable.
