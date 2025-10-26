# REORGANIZE PLAN

NOTE: after the completion of each phase, pause and ask the user to verify correctness before proceeding. This means that each phase should be not just easy to review, but fully functional and testable on its own.

## Phase 1 – Scope & Interfaces

- Inventory every public function in `session`, `timer`, `stats`, `golf`, and `picker`; note which modules consume each API.
- Capture the mapping in a short doc to prevent accidental API regressions during refactors.
- Add lightweight assertions or sanity checks at key call sites where modules will be split to help catch wiring issues early.

## Phase 2 – Session Split

- Create `lua/buffergolf/session/` with:
  - `buffer.lua`: buffer creation, option propagation, default settings.
  - `events.lua`: autocmds, user commands, and refresh scheduling.
  - `modes.lua`: typing vs golf initialization, reset handling, and shared utilities.
- Keep `session.lua` as the orchestrator that constructs the session table, delegates to helpers, and exposes the public API.
- Goal: shrink `session.lua` to ≲250 lines without behavioral changes.

## Phase 3 – Timer & UI Separation

- Extract float geometry, padding helpers, highlight configuration, and rendering into `timer/ui.lua`.
- Leave `timer.lua` with lifecycle management: start/stop, countdown mode, completion checks, and stats queries.
- Surface a slim UI API (e.g. `ui.ensure(session)`, `ui.render(session, data)`) so presentation logic is isolated from timing state.
- Goal: reduce `timer.lua` to ≲300 lines and make the UI module independently tweakable.

## Phase 4 – Stats Layering

- Introduce `stats/par.lua` for par estimation (typing mode, golf/diff-based calculations) and related edit-distance helpers.
- Keep runtime metrics (WPM, keystrokes, score struct assembly) in `stats/core.lua`, delegating to `par.lua` when needed.
- Update callers to require only the portion they rely on, preserving the existing outward-facing API via a façade if necessary.
- Goal: each stats file under ≲200 lines with clearly separated responsibilities.

## Phase 5 – Golf Utilities

- Split `golf.lua` into:
  - `golf/layout.lua`: reference window creation, sizing logic, mini.diff setup.
  - `golf/navigation.lua`: synchronized hunk navigation, keymaps, and commands.
- Keep a thin `golf.lua` façade that wires both modules and preserves the current API.
- Goal: simplify reasoning about mini.diff upkeep versus navigation controls, easing future UI tweaks.

## Phase 6 – Picker Simplification

- Design a lightweight picker source interface (e.g. `pickers/sources/file.lua`, `buffer.lua`, `register.lua`, `git.lua`) that each implements `gather()`/`confirm()` logic.
- Centralize shared countdown/start glue so Snacks vs native behavior is handled once per source or via a small adapter.
- Goal: shrink `picker.lua` to ≲200 lines and make each picker source testable in isolation.
