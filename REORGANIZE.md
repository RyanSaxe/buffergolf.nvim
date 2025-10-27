# REORGANIZE PLAN

NOTE: After the completion of each phase, pause and ask the user to verify correctness before proceeding. This means that each phase should be not just easy to review, but fully functional and testable on its own.

## Current State Analysis
- **No floating windows** - Stats display uses split windows (top/bottom)
- **9 modules total**: init, session, timer, stats, golf, picker, buffer, keystroke, visual
- **3,127 total lines** across all modules
- **No subdirectories** yet created

## Optimization Goals
Each phase aims for ~30-40% line reduction through:
- Condensing early returns and simple functions
- Using tables/loops for repetitive patterns
- Removing unnecessary comments and whitespace
- Eliminating intermediate variables
- Simplifying conditional logic
- **NO functionality changes** - only cleaner, more concise code

## Phase 1 – Timer Module Split ✅ COMPLETED

**Largest module, clearest separation**
- **Original**: 584 lines
- **Result**: 343 lines (41% reduction achieved!)
- Split into `timer/timer.lua` and `timer/stats_display.lua`

## Phase 2 – Session Module Split

**Complex state management, needs careful separation**

Create `lua/buffergolf/session/`:
- **`lifecycle.lua`**: start(), stop(), reset_to_start(), state transitions
- **`autocmds.lua`**: Event handlers and user command registration
- **`storage.lua`**: Session lookup and management
- **`session.lua`**: Main orchestrator and public API
- **Goal**: Aggressive line reduction through optimization

## Phase 3 – Picker Sources

**Well-defined source boundaries**

Create `lua/buffergolf/picker/`:
- **`sources/file.lua`**: File selection via fd
- **`sources/buffer.lua`**: Listed buffers selection
- **`sources/register.lua`**: Register content selection
- **`sources/git.lua`**: Git commit selection
- **`adapter.lua`**: Snacks.nvim vs native handling
- **`picker.lua`**: Main entry point, routing
- **Goal**: Maximize code reuse, eliminate duplication

## Phase 4 – Stats Organization

**Preparation for future persistence features**

Create `lua/buffergolf/stats/`:
- **`par.lua`**: Edit distance, par estimation, mini.diff analysis
- **`metrics.lua`**: WPM, character counting, stats assembly
- **`stats.lua`**: Public API facade
- **Goal**: Consolidate similar calculations, reduce verbosity

## Phase 5 – Golf Module Split

**Clear separation between layout and navigation**

Create `lua/buffergolf/golf/`:
- **`window.lua`**: Reference window and mini.diff setup
- **`navigation.lua`**: Hunk navigation and keymaps
- **`golf.lua`**: Thin orchestrator
- **Goal**: Clean separation with minimal code

## Phase 6 – Visual Feedback Organization

**Move session-specific visual module**

Move `visual.lua` to `lua/buffergolf/session/visual.lua`:
- Ghost text marks management
- Mismatch highlighting
- Change watcher attachment
- Makes sense as it's tightly coupled to session state

## Phase 7 – Utility Consolidation

**Final cleanup**

Create `lua/buffergolf/utils/`:
- **`buffer.lua`**: Move existing buffer utilities
- **`keystroke.lua`**: Move existing keystroke tracking

## Implementation Guidelines

1. **NO functional changes** - Pure reorganization only
2. **Preserve all public APIs** exactly as-is
3. **Update all require() statements** systematically
4. **Test after each phase** before proceeding
5. **One atomic commit per phase** for easy rollback

## Success Metrics

- All files under 300 lines (most under 200)
- Clear separation of concerns between modules
- Easier navigation and maintenance
- Zero behavioral changes