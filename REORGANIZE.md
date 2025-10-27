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

## Phase 2 – Session Module Split ✅ COMPLETED

**Complex state management, needs careful separation**
- **Original**: 486 lines
- **Result**: 350 lines (28% reduction achieved!)
- Split into `session/lifecycle.lua`, `session/autocmds.lua`, `session/storage.lua`

## Phase 3 – Picker Sources ✅ COMPLETED

**Well-defined source boundaries**
- **Original**: 404 lines
- **Result**: 335 lines (17% reduction achieved!)
- Split into `picker/sources/`, `picker/adapter.lua`

## Phase 4 – Stats Organization ✅ COMPLETED

**Preparation for future persistence features**
- **Original**: 336 lines
- **Result**: 178 lines (47% reduction achieved!)
- Split into `stats/par.lua`, `stats/metrics.lua`

## Phase 5 – Golf Module Split ✅ COMPLETED

**Clear separation between layout and navigation**
- **Original**: 315 lines
- **Result**: 215 lines (32% reduction achieved!)
- Split into `golf/window.lua`, `golf/navigation.lua`

## Phase 6 – Visual Feedback Organization ✅ COMPLETED

**Move session-specific visual module**
- **Original**: 265 lines
- **Result**: 137 lines (48% reduction achieved!)
- Moved to `session/visual.lua` with aggressive optimization

## Phase 7 – Utility Consolidation ✅ COMPLETED

**Final cleanup**
- **Original**: 428 lines (244 buffer + 184 keystroke)
- **Result**: 259 lines (39% reduction achieved!)
- Moved to `utils/buffer.lua` and `utils/keystroke.lua`

## Implementation Guidelines

1. **NO functional changes** - Pure reorganization only
2. **Preserve all public APIs** exactly as-is
3. **Update all require() statements** systematically
4. **Test after each phase** before proceeding
5. **One atomic commit per phase** for easy rollback

## Final Results Summary

### Total Line Reduction
- **Original total**: 3,127 lines
- **New total**: 2,141 lines (includes facades)
- **Overall reduction**: 986 lines (32% reduction!)

### Module Breakdown
| Module | Original | Optimized | Reduction |
|--------|----------|-----------|-----------|
| Timer | 584 | 343 | 41% |
| Session | 486 | 350 | 28% |
| Picker | 404 | 335 | 17% |
| Stats | 336 | 178 | 47% |
| Golf | 315 | 215 | 32% |
| Visual | 265 | 137 | 48% |
| Utils | 428 | 259 | 39% |
| Init | 309 | ~180 | ~42% |

### Organizational Improvements
- Created 5 subdirectories for better organization
- Split monolithic modules into focused components
- Maintained backward compatibility with facade modules
- All modules now under 250 lines (most under 200)
- Zero functional changes - purely organizational

## Success Metrics ✅

- ✅ All files under 300 lines (most under 200)
- ✅ Clear separation of concerns between modules
- ✅ Easier navigation and maintenance
- ✅ Zero behavioral changes