## MVP TODO

### 1. Session Stats Persistence
- [ ] Decide on storage scope (likely `vim.fn.stdpath("data") .. "/buffergolf"`). Ensure directory creation with `vim.fn.mkdir(..., "p")`.
- [ ] Define payload schema (timestamp, mode, file identifier, reference size, par, keys, wpm, duration, difficulty, countdown seconds). Keep it versioned (`schema_version = 1`).
- [ ] Teach `lua/buffergolf/stats.lua` to expose a `build_summary(session)` helper returning the payload so other modules can stay lean.
- [ ] Extend `lua/buffergolf/timer.lua` to call a new `stats.store(summary)` when `complete_session` runs (both success and timeout). Handle write errors via `vim.notify` once per session.
- [ ] Implement `stats.store(summary)` using `vim.json.encode`, appending to a newline-delimited JSON log (simpler than huge arrays, easy to tail).
- [ ] Provide a lightweight `:BuffergolfStats` command that opens the log in a scratch buffer with the most recent entries formatted in reverse chronological order. Keep pagination out of scope for now.
- [ ] Document the stats file location and command in `README.md` so early users know how to inspect their history.

### 2. Git Picker Guard
- [ ] Replace `is_git_repo()` in `lua/buffergolf/picker.lua` with an implementation that checks `vim.fn.system({"git","rev-parse","--is-inside-work-tree"})` and inspects `vim.v.shell_error`, or alternatively walks up for a `.git` directory using `vim.fs.find`.
- [ ] Update the function to cache its result per buffer invocation (optional but prevents repeated system calls when the picker runs multiple times).
- [ ] Add a protective branch so the Git option is only inserted when `is_git_repo()` returns true **and** the current buffer has an on-disk path.
- [ ] Note the behavioural change in the changelog section of `README.md` (or add a short "Unreleased" note if no changelog exists).
