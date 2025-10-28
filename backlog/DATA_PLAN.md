# BufferGolf.nvim Stats Implementation Plan

## Overview

Implement persistent session statistics tracking with per-key metrics and rich visualization dashboard, enabling detailed typing performance analysis through interactive visualizations.

## Architecture Overview

```
lua/buffergolf/
├── stats/
│   ├── persistence.lua     # NDJSON storage for sessions
│   ├── keystroke_data.lua  # Per-key tracking and storage
│   └── query.lua          # Data filtering and aggregation
├── analysis/              # Root-level analysis module
│   ├── init.lua           # Main window and tab orchestration
│   ├── filters.lua        # Filter system implementation
│   └── tabs/
│       ├── activity.lua   # Git-style activity heatmap
│       ├── keyboard.lua   # Per-key WPM/accuracy heatmap
│       └── dashboard.lua  # Aggregated statistics
└── session/
    └── keystroke.lua      # Enhanced with per-key tracking

```

## Part 1: Session Stats Persistence

### 1.1 Data Schema

**Session Record** (`sessions.ndjson`):
```json
{
  "schema_version": 1,
  "timestamp": 1234567890,
  "session_id": "uuid-v4",
  "mode": "typing|golf",
  "file_identifier": "path/to/file.lua",
  "file_extension": ".lua",
  "reference_size": 450,
  "par": 455,
  "keystrokes": 478,
  "wpm": 65.5,
  "accuracy": 0.945,
  "duration": 45.2,
  "difficulty": "medium",
  "countdown_seconds": null,
  "completion_status": "completed|timeout",
  "correct_chars": 425,
  "incorrect_keystrokes": 23,
  "golf_stats": {
    "score_percentage": 85.2,
    "hunks": { "added": 5, "deleted": 2, "changed": 3 }
  }
}
```

**Keystroke Record** (`keystrokes.ndjson`):
```json
{
  "session_id": "uuid-v4",
  "timestamp": 1234567890.123,
  "key": "a",
  "key_raw": "a",
  "expected": "a",
  "correct": true,
  "position": 42,
  "elapsed_ms": 1250,
  "modifiers": []
}
```

### 1.2 Storage Strategy

- **Location**: `vim.fn.stdpath("data") .. "/buffergolf/"`
- **Files**:
  - `sessions.ndjson` - Session summaries
  - `keystrokes.ndjson` - Individual keystroke data (typing mode only)
  - `aggregates.json` - Pre-computed daily/weekly aggregates
- **Rotation**: Monthly rotation with archival (`sessions_2024_01.ndjson.gz`)
- **Lazy Loading**: Load only required date ranges for visualization

### 1.3 Implementation: `lua/buffergolf/stats/persistence.lua`

```lua
-- Core functions to implement:
M.build_session_summary(session) --> table
M.store_session(summary) --> boolean
M.store_keystroke(keystroke_data) --> boolean
M.load_sessions(filter) --> iterator
M.load_keystrokes(session_id) --> iterator
M.ensure_storage_directory() --> boolean
M.rotate_if_needed() --> boolean
```

### 1.4 Integration Points

**In `timer/control.lua:complete_session()`**:
- Call `persistence.store_session(persistence.build_session_summary(session))`
- Handle errors with single `vim.notify` per session

**In `init.lua`**:
- Add `:BuffergolfStats` command that shows recent sessions in scratch buffer

## Part 2: Per-Key Metrics Tracking

### 2.1 Enhanced Keystroke Tracking

**Challenges**:
- Must capture actual key pressed vs expected character
- Handle vim operators (p, dd, yy, etc.)
- Track autocompletion (blink.cmp, native completion)
- Differentiate between navigation and input keystrokes

**Strategy**:
```lua
-- Enhanced keystroke.lua structure
local keystroke_buffer = {}  -- Ring buffer of last N keystrokes

function track_keystroke(session, raw_key, key_name)
  -- 1. Get current cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2]

  -- 2. Determine expected character from reference
  local expected = get_expected_char(session, row, col)

  -- 3. Determine if this is an input keystroke
  local is_input = determine_if_input(key_name, vim.fn.mode())

  -- 4. Store keystroke data
  if is_input and session.mode == "typing" then
    local keystroke = {
      session_id = session.id,
      timestamp = vim.loop.hrtime() / 1e9,
      key = key_name,
      key_raw = raw_key,
      expected = expected,
      correct = nil,  -- Determined later after buffer update
      position = get_linear_position(row, col),
      elapsed_ms = get_elapsed_ms(session),
      modifiers = get_active_modifiers()
    }
    table.insert(keystroke_buffer, keystroke)
  end
end

function post_buffer_update(session)
  -- After buffer changes, determine correctness of buffered keystrokes
  -- by comparing new buffer state with expected state
  for _, ks in ipairs(keystroke_buffer) do
    ks.correct = determine_correctness(ks, session)
    persistence.store_keystroke(ks)
  end
  keystroke_buffer = {}
end
```

### 2.2 Accuracy Calculation

**Per-Session Accuracy**:
```lua
accuracy = correct_keystrokes / total_input_keystrokes
```

**Per-Key Accuracy** (aggregated across sessions):
```lua
key_accuracy[key] = correct_count[key] / total_count[key]
```

### 2.3 WPM Per Key

**Calculation**:
```lua
-- For each key, track:
-- 1. Time between keystroke and next keystroke (inter-key interval)
-- 2. Whether the key was part of a correctly typed word

key_wpm = (correct_key_presses / 5) / (total_key_time_minutes)
```

## Part 3: Visual Analysis Dashboard

### 3.1 Window Structure

```
┌─────────────────────────────────────────────────────┐
│ [Activity] [Keyboard] [Dashboard]         [Filters] │
├─────────────────────────────────────────────────────┤
│                                                     │
│                   Tab Content Area                 │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 3.2 Filter System (`analysis/filters.lua`)

**Filters**:
```lua
{
  date_range = { start = nil, end = nil },  -- nil = all time
  file_types = { ".lua", ".py" },  -- multi-select
  modes = { "typing", "golf" },  -- multi-select
  countdown = { min = nil, max = nil },
  difficulty = { "easy", "medium", "hard", "expert" }
}
```

**Filter Application**:
- Filters apply to ALL tabs simultaneously
- Use memoization for expensive aggregations
- Update tabs reactively on filter change

### 3.3 Activity Heatmap Tab

**Implementation**:
```lua
-- 52-week calendar grid (GitHub contributions style)
-- Each cell shows session count for that day
-- Color intensity via highlight groups:
BuffergolfHeatmap0  -- No activity
BuffergolfHeatmap1  -- 1-2 sessions
BuffergolfHeatmap2  -- 3-5 sessions
BuffergolfHeatmap3  -- 6-10 sessions
BuffergolfHeatmap4  -- 10+ sessions

-- Hover detail (virtual text):
"2024-01-15: 5 sessions, 45 min, avg 72 WPM"
```

### 3.4 Keyboard Heatmap Tab

**QWERTY Layout Visualization**:
```
  1 2 3 4 5 6 7 8 9 0 - =
   q w e r t y u i o p [ ]
    a s d f g h j k l ; '
     z x c v b n m , . /
         [space]
```

**Shift State Handling**:
- Toggle button: [Normal] / [Shift]
- When Shift active, show uppercase letters and symbols
- Different color scales for WPM vs Accuracy modes

**Color Mapping**:
```lua
-- Highlight groups for keyboard heatmap
BuffergolfKeyWPM0   -- 0-20 WPM (red)
BuffergolfKeyWPM1   -- 20-40 WPM (orange)
BuffergolfKeyWPM2   -- 40-60 WPM (yellow)
BuffergolfKeyWPM3   -- 60-80 WPM (light green)
BuffergolfKeyWPM4   -- 80+ WPM (green)

BuffergolfKeyAcc0   -- 0-60% accuracy (red)
BuffergolfKeyAcc1   -- 60-75% accuracy (orange)
BuffergolfKeyAcc2   -- 75-85% accuracy (yellow)
BuffergolfKeyAcc3   -- 85-95% accuracy (light green)
BuffergolfKeyAcc4   -- 95-100% accuracy (green)
```

**Data Aggregation**:
```lua
-- Per-key metrics (typing mode only)
key_stats = {
  ["a"] = {
    total_presses = 1523,
    correct_presses = 1456,
    accuracy = 0.956,
    total_time_ms = 45230,
    wpm = 67.2
  },
  -- ... for each key
}
```

### 3.5 Dashboard Tab

**Layout**:
```
┌─────────────────┬─────────────────┬─────────────────┐
│   Total Time    │  Sessions       │  Average WPM    │
│   45h 23m       │  523            │  72.3           │
├─────────────────┼─────────────────┼─────────────────┤
│  Best WPM       │  Best Score     │  Accuracy       │
│  89.2           │  94.5%          │  96.7%          │
└─────────────────┴─────────────────┴─────────────────┘

Top Files:                    Recent Progress:
1. init.lua     (45 sessions) ┌────────────────────┐
2. config.lua   (32 sessions) │ WPM over last 30d  │
3. utils.lua    (28 sessions) │ [line graph here]  │
                               └────────────────────┘
```

## Part 4: Data Optimization Strategy

### 4.1 Aggregation Layers

**Real-time** (in-memory during session):
- Current keystroke buffer
- Live WPM calculation
- Immediate accuracy feedback

**Post-session** (on completion):
- Write session summary to `sessions.ndjson`
- Write keystrokes to `keystrokes.ndjson`
- Update daily aggregate cache

**Daily Aggregates** (`aggregates.json`):
```json
{
  "2024-01-15": {
    "sessions": 5,
    "total_time": 2734,
    "total_keystrokes": 4523,
    "avg_wpm": 72.3,
    "avg_accuracy": 0.967,
    "per_key": { /* aggregated key stats */ }
  }
}
```

### 4.2 Loading Strategy

**Lazy Loading**:
- Load session summaries for date range only
- Load keystroke data only when keyboard tab accessed
- Use coroutines for non-blocking file I/O

**Caching**:
- LRU cache for recent 30 days of data
- Invalidate on new session completion
- Pre-compute common aggregations

## Part 5: Command Interface

### 5.1 Commands

```vim
:BuffergolfStats [range]      " Show session history
:BuffergolfAnalysis           " Open analysis dashboard
:BuffergolfExport <format>    " Export data (csv, json)
:BuffergolfClear <range>      " Clear historical data
```

### 5.2 Configuration

```lua
{
  stats = {
    storage_path = vim.fn.stdpath("data") .. "/buffergolf",
    retention_days = 365,

    analysis = {
      default_range = nil,  -- nil = all time
      position = "center",
      width = 0.8,
      height = 0.8,
      keyboard_layout = "qwerty"  -- only qwerty for v1
    },

    -- Highlight groups for theming
    highlights = {
      -- Heatmap colors (activity)
      heatmap = {
        [0] = "BuffergolfHeatmap0",
        [1] = "BuffergolfHeatmap1",
        -- ...
      },
      -- Keyboard colors
      keyboard_wpm = {
        [0] = "BuffergolfKeyWPM0",
        -- ...
      }
    }
  }
}
```

## Part 6: Implementation Checklist

### Core Persistence
- [ ] Create storage directory structure
- [ ] Implement NDJSON read/write utilities
- [ ] Build session summary from live session
- [ ] Store session on completion
- [ ] Add `:BuffergolfStats` command

### Per-Key Tracking
- [ ] Enhance keystroke.lua with detailed tracking
- [ ] Implement expected character detection
- [ ] Handle vim operators and special keys
- [ ] Track autocompletion events
- [ ] Calculate per-key accuracy
- [ ] Calculate per-key WPM

### Analysis Dashboard
- [ ] Create floating window framework
- [ ] Implement tab navigation
- [ ] Build filter system
- [ ] Create activity heatmap
- [ ] Create keyboard heatmap with shift states
- [ ] Build dashboard with aggregations
- [ ] Add highlight groups for theming

### Data Optimization
- [ ] Implement daily aggregation
- [ ] Add lazy loading for large datasets
- [ ] Create LRU cache for recent data
- [ ] Add file rotation for old data

### Documentation
- [ ] Document data file formats
- [ ] Add configuration examples
- [ ] Create troubleshooting guide
- [ ] Document highlight groups for theming

## Technical Considerations

### Keystroke Tracking Complexity

The most complex aspect is accurate per-key tracking because:

1. **Vim Operators**: Commands like `3dw` generate one keystroke event but affect multiple characters
2. **Paste Operations**: `p` pastes multiple characters with single keystroke
3. **Autocompletion**: Inserts text without individual keystrokes
4. **Backspace/Delete**: Must track corrections differently than forward typing

**Solution Approach**:
- Track buffer state before/after each keystroke
- Use diff to determine actual changes
- Attribute changes to keystroke events
- Flag special operations (paste, completion) separately

### Performance Considerations

1. **File I/O**: Use async I/O where possible to avoid blocking
2. **Aggregation**: Pre-compute daily stats to avoid re-processing
3. **Memory**: Keep only recent data in memory, load historical on-demand
4. **Rendering**: Use virtual text and extmarks efficiently

### Error Handling

- Graceful degradation if storage fails
- Single error notification per session
- Automatic cleanup of corrupted data
- Fallback to in-memory only mode

## Success Metrics

- Per-key accuracy and WPM tracking works with normal typing
- Visualization loads instantly for 1 year of data
- Keyboard heatmap accurately reflects problem keys
- Activity heatmap motivates consistent practice
- All data persists across Neovim restarts