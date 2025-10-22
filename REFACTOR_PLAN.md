# BufferGolf.nvim Refactor Plan

## Goals

- Preserve all behaviour while stripping debug noise and unused paths.
- Shrink the surface area of `session.lua` by moving focused concerns into dedicated modules.
- Remove duplicated helpers so shared logic lives in a single location.
- End with a codebase that is easier to read, test, and extend without altering user-facing features.

## Current Findings

- File sizes (current): `lua/buffergolf/session.lua` 993 lines, `lua/buffergolf/picker.lua` 382, `lua/buffergolf/stats.lua` 333, `lua/buffergolf/timer.lua` 536, `lua/buffergolf/keystroke.lua` 155, `lua/buffergolf/init.lua` 226, `lua/buffergolf/buffer.lua` 200.
- Phase 1 cleanup removed the lingering debug scaffolding from picker, stats, init, session, and keystroke modules.
- `lua/buffergolf/buffer.lua` now owns shared buffer/window helpers, while `lua/buffergolf/session.lua` still orchestrates visual overlays, diff navigation, timers, and keystroke gating—prime candidates for Phase 3 extraction.
- Alternative keystroke-tracking approaches were removed; the module now exposes only the active implementation.
- `lua/buffergolf/compat.lua` has been deleted with no remaining references.

## Refactor Strategy

### Phase 1 – Trim instrumentation and unused code ✅

- [x] 1.1 Remove throwaway DEBUG notifications around `lua/buffergolf/picker.lua:244`, keeping only real error messages.
- [x] 1.2 Delete the temporary JSON dump beginning at `lua/buffergolf/stats.lua:125`.
- [x] 1.3 Drop the `:BuffergolfDebug` user command defined at `lua/buffergolf/init.lua:103`.
- [x] 1.4 Remove `Session.debug_keys()` in `lua/buffergolf/session.lua:1141` and any call sites.
- [x] 1.5 Prune `debug_keys` handling and the unused reset logic from `lua/buffergolf/keystroke.lua:22`, `lua/buffergolf/keystroke.lua:70`, and `lua/buffergolf/keystroke.lua:189`.
- [x] 1.6 Delete unused experimental entry points `init_session_getchar` and `init_session_changes` from `lua/buffergolf/keystroke.lua:91` and `lua/buffergolf/keystroke.lua:98`.
- [x] 1.7 Confirm `lua/buffergolf/compat.lua` has no remaining references and remove it from the repository.

### Phase 2 – Consolidate shared helpers ✅

- [x] 2.1 Introduced `lua/buffergolf/buffer.lua` to host buffer-scoped helpers formerly embedded in `session.lua` (indent alignment, buffer naming, default option management, and matchparen control).
- [x] 2.2 Moved tab and whitespace normalisation helpers plus `buf_valid`/`win_valid` checks into the buffer module and updated `session.lua`/`timer.lua` to call through the shared API.
- [x] 2.3 Updated `timer.lua` to rely on the shared helpers, removing its duplicate normalization and strip logic.
- [x] 2.4 Added a module-level comment describing the responsibilities of the new buffer helper module.

### Phase 3 – Extract focused session submodules

- [ ] 3.1 Create `lua/buffergolf/visual.lua` for ghost text management (`clear_ghost_mark`, `expand_ghost_text`, `set_ghost_mark`, `refresh_visuals`, `attach_change_watcher`).
- [ ] 3.2 Create `lua/buffergolf/golf.lua` for golf-mode-specific behaviour (`create_reference_window`, `setup_mini_diff_for_golf`, `setup_golf_navigation`, `goto_hunk_sync`).
- [ ] 3.3 Keep session orchestration (`sessions_by_origin`, lifecycle functions, keystroke gating, timer hooks) inside a slimmed `session.lua` that wires together `buffer`, `visual`, `golf`, `timer`, and `keystroke`.
- [ ] 3.4 Replace direct calls in `session.lua` with the new module APIs and ensure module requires are updated at the top of the file.
- [ ] 3.5 Ensure `with_keys_disabled` remains available where navigation needs to avoid counting keystrokes and lives in whichever module now owns keystroke helpers (likely `keystroke.lua`).

### Phase 4 – Polish and verification

- [ ] 4.1 Sweep for any leftover references to removed helpers (`debug_keys`, alternative keystroke paths) and clean up dead code.
- [ ] 4.2 Update documentation (`README.md`) if the public surface or configuration examples mention removed commands or highlight new module responsibilities.
- [ ] 4.3 Run manual smoke tests: typing mode entry/exit, golf mode with git history selection, countdown timers, and keystroke tracking to confirm behaviour parity.
- [ ] 4.4 Audit requires to make sure no stale module names remain after the extraction work.

## Expected Outcomes

- `lua/buffergolf/session.lua` shrinks to orchestration-only logic with <400 lines once helpers are moved.
- Shared helpers reduce duplication between `session.lua` and `timer.lua`, lowering risk of subtle divergence.
- Debug artefacts and unused experiments are removed, keeping runtime paths lean.
- The directory gains clear modules (`buffer`, `visual`, `golf`) with concise responsibilities, improving maintainability.

## Notes

- Execute phases sequentially; avoid major refactors before instrumentation is removed so diffs stay readable.
- Run any suggested code changes by the user before implementation, per request.
