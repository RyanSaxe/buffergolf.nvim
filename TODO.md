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

- [ ] Replace `is_git_repo()` in `lua/buffergolf/picker.lua` with an implementation that checks `vim.fn.system({"git","rev-parse","--is-inside-work-tree"})` and inspects `vim.v.shell_error`, or alternatively walks up for a `.git` directory using `vim.fs.find`. Current implementation uses hacky spawn+kill approach.
- [ ] Update the function to cache its result per buffer invocation (optional but prevents repeated system calls when the picker runs multiple times).
- [x] Add a protective branch so the Git option is only inserted when `is_git_repo()` returns true **and** the current buffer has an on-disk path.
- [ ] Note the behavioural change in the changelog section of `README.md` (or add a short "Unreleased" note if no changelog exists).
[ ]

### 3. Nice Visual Stats

[ ]

- [ ] Create a command BufferGolfAnalysis that opens a floating window showing a very very very pretty representation of your data
- [ ] The window should have the following tabs:
  - [ ] a visual representation (like the git commit chart) that shows about how many times this ways used per data
  - [ ] a visual representation of a keyboard that shows WPM per character
  - [ ] a summary dashboard that shows aggregation of lots of different stuff (e.g. WPM, Score, number of sessions, etc etc)
- [ ] The window (over all tabs) should have the ability to specify filters in which all tabs get updated according to the selection.
  - [ ] start date -> end date, with either end optional
  - [ ] multi select of file types
  - [ ] min countdown -> max countdown, with either end optional ... also an option to basically have countdown vs no countdown
  - [ ] open to many other types of filters
