# Testing Plan for buffergolf.nvim

## Overview

This testing plan covers the complete modular rewrite of buffergolf.nvim, encompassing 22 Lua modules organized across 8 subdirectories with ~2,100 lines of code. The plan establishes a comprehensive testing framework using Plenary.nvim's busted harness for both unit and integration testing.

## Architecture Summary

The plugin has been reorganized into focused modules:
- **session/** - Lifecycle, storage, keystroke tracking, buffer utilities, visual feedback
- **timer/** - Countdown/count-up control, stats display window
- **stats/** - Metrics calculation (WPM, par, edit distance)
- **golf/** - Reference window creation, synchronized navigation
- **picker/** - UI orchestration with multiple content sources (buffer, file, git, register)

## Test Infrastructure

### Tooling Stack
- **Test Runner**: Plenary.nvim busted harness (`:PlenaryBustedDirectory`)
- **Execution**: `nvim --headless` for CI/CD and local runs
- **Dependencies**:
  - `nvim-lua/plenary.nvim` (test framework)
  - `echasnovski/mini.diff` (runtime dependency for golf mode)
- **Mock Framework**: Custom stubs in `tests/helpers.lua`
- **CI Platform**: GitHub Actions with matrix testing

### Directory Structure
```
tests/
├── minimal_init.lua          # Headless Neovim bootstrap
├── helpers.lua               # Shared test utilities and mocks
├── fixtures/                 # Sample files for testing
│   ├── sample_code.lua
│   ├── indented_text.txt
│   └── tabs_and_spaces.txt
├── deps/                     # Test dependencies (git clones)
│   ├── plenary.nvim/
│   └── mini.diff/
├── unit/                     # Pure Lua logic tests
│   ├── buffer_spec.lua
│   ├── stats_spec.lua
│   ├── keystroke_spec.lua
│   └── par_spec.lua
└── integration/              # Tests requiring vim context
    ├── session_lifecycle_spec.lua
    ├── visual_feedback_spec.lua
    ├── timer_completion_spec.lua
    ├── golf_navigation_spec.lua
    ├── picker_flow_spec.lua
    └── autocmds_spec.lua
```

## Test Suites

### Unit Tests (Pure Lua Logic)

#### 1. Buffer Utilities (`tests/unit/buffer_spec.lua`)
- **Module**: `lua/buffergolf/session/buffer.lua`
- **Test Cases**:
  - `generate_buffer_name()`:
    - Named buffers with custom prefixes
    - Unnamed buffers with incrementing numbers
    - File collision warnings when name exists on disk
    - Empty name handling
  - `dedent_lines()`:
    - Common leading whitespace removal
    - Mixed indentation levels
    - All-whitespace line preservation
    - Empty buffer handling
    - Single-line content
  - `normalize_lines()`:
    - Tab-to-space expansion with various tabstop values (2, 4, 8)
    - Mixed tabs and spaces
    - Preservation of non-whitespace content
    - Unicode character handling
  - `prepare_lines()`:
    - Combined dedent and normalize behavior
    - Option flag testing (auto_dedent true/false)

#### 2. Statistics Calculations (`tests/unit/stats_spec.lua`)
- **Modules**: `lua/buffergolf/stats/metrics.lua`, `lua/buffergolf/stats/par.lua`
- **Test Cases**:
  - `calculate_wpm()`:
    - Standard calculation: (correct_chars / 5) / (seconds / 60)
    - Edge cases: zero time, zero characters
    - Fractional seconds handling
    - Large text performance
  - `count_correct_characters()`:
    - Exact prefix matching
    - Mismatch detection at various positions
    - Whitespace-only line handling
    - Empty buffer comparison
    - Unicode character counting
  - `calculate_par()`:
    - Typing mode: char_count + newline_count + 1
    - Golf mode with mini.diff hunks
    - Golf mode fallback (nuclear option)
    - Difficulty multipliers (0.33x to 1.0x)
    - Empty buffer edge cases

#### 3. Edit Distance (`tests/unit/par_spec.lua`)
- **Module**: `lua/buffergolf/stats/par.lua`
- **Test Cases**:
  - Levenshtein distance implementation:
    - Insert operations
    - Delete operations
    - Replace operations
    - Complex transformations
    - Identical strings (distance = 0)
    - Empty string handling

#### 4. Keystroke Tracking (`tests/unit/keystroke_spec.lua`)
- **Module**: `lua/buffergolf/session/keystroke.lua`
- **Test Cases**:
  - Counter increments:
    - Normal mode keys
    - Insert mode keys
    - Visual mode keys
  - Special key filtering:
    - `<Ignore>` events
    - Mouse events (`<ScrollWheel*>`, `<*Mouse*>`)
    - Command depth filtering
  - State management:
    - Enable/disable tracking
    - Reset counter
    - Buffer-specific handlers
  - `with_keys_disabled()`:
    - Temporary suspension for navigation
    - Automatic re-enabling

### Integration Tests (Vim Context Required)

#### 1. Session Lifecycle (`tests/integration/session_lifecycle_spec.lua`)
- **Module**: `lua/buffergolf/session/lifecycle.lua`
- **Test Cases**:
  - `start()` (typing mode):
    - Practice buffer creation
    - Option configuration (diagnostics, inlay hints, autopairs disabled)
    - Ghost text initialization
    - Timer setup
    - Keystroke handler registration
  - `start_golf()` (transformation mode):
    - Reference window creation
    - Mini.diff initialization
    - Synchronized navigation setup
    - Par calculation with hunks
  - `stop()`:
    - Buffer restoration to origin
    - Window cleanup
    - Timer cancellation
    - Handler deregistration
    - State clearing
  - `reset_to_start()`:
    - Content restoration
    - Keystroke counter reset
    - Visual state refresh
    - Mode-specific behavior (typing vs golf)
  - Multiple concurrent sessions:
    - Independent state tracking
    - Cross-buffer interference prevention

#### 2. Visual Feedback (`tests/integration/visual_feedback_spec.lua`)
- **Module**: `lua/buffergolf/session/visual.lua`
- **Test Cases**:
  - Ghost text rendering:
    - Inline virtual text at line ends
    - Multi-line ghost text
    - Tab character display
    - Empty line handling
  - Mismatch highlighting:
    - Character-level mismatches
    - Range calculation
    - Highlight group application
    - Clear on correction
  - Change watcher:
    - TextChanged event handling
    - Debounced updates
    - Insert vs Normal mode behavior

#### 3. Timer & Completion (`tests/integration/timer_completion_spec.lua`)
- **Module**: `lua/buffergolf/timer/control.lua`
- **Test Cases**:
  - Timer initialization:
    - First keystroke detection
    - Gap time calculation
    - Stats window creation
  - Countdown mode:
    - Decrement from specified seconds
    - Expiration detection
    - Session locking on timeout
  - Count-up mode:
    - Increment from zero
    - Continuous updates (250ms interval)
  - Completion detection:
    - Exact match verification
    - Stats freezing
    - Buffer becoming read-only
    - Celebration notification
  - Stats display updates:
    - WPM calculation
    - Keystroke count
    - Par percentage
    - Diff summary (golf mode)

#### 4. Golf Navigation (`tests/integration/golf_navigation_spec.lua`)
- **Module**: `lua/buffergolf/golf/navigation.lua`, `lua/buffergolf/golf/window.lua`
- **Test Cases**:
  - Reference window:
    - Position options (left, right, top, bottom)
    - Size configuration (percentage or fixed)
    - Read-only enforcement
    - Filetype preservation
  - Synchronized navigation:
    - Next/previous hunk movement
    - First/last hunk jumps
    - Line offset calculation with additions/deletions
    - Viewport synchronization
  - Mini.diff integration:
    - Overlay visualization
    - Hunk detection
    - Toggle overlay command

#### 5. Picker Flow (`tests/integration/picker_flow_spec.lua`)
- **Module**: `lua/buffergolf/picker/ui.lua` and sources
- **Test Cases**:
  - Visual selection:
    - Range detection
    - Content extraction
    - Mode preservation
  - Source selection:
    - Empty start
    - Buffer list (excluding current)
    - File picker
    - Register content
    - Git history (repo detection)
  - Session initialization:
    - Correct mode selection
    - Content preparation
    - Countdown integration

#### 6. Autocmds (`tests/integration/autocmds_spec.lua`)
- **Module**: `lua/buffergolf/session/autocmds.lua`
- **Test Cases**:
  - Buffer lifecycle:
    - BufEnter (focus tracking)
    - BufLeave (pause behavior)
    - BufWipeout (cleanup)
  - LSP interaction:
    - LspAttach (diagnostics suppression)
    - Inlay hints disabling
  - Save prevention:
    - BufWriteCmd interception
    - Warning notification

## Edge Cases & Error Scenarios

### Buffer Edge Cases
- Empty buffers (common in typing mode)
- Single character content
- Very large files (>10,000 lines)
- Binary content handling
- Files with mixed line endings (CRLF vs LF)
- Unicode and multi-byte characters
- Buffers modified during session
- Deleted origin buffers

### Timing Edge Cases
- Sub-second completion
- Very long sessions (>1 hour)
- System clock changes during session
- Timer overflow handling

### Concurrency Issues
- Multiple sessions in split windows
- Rapid session start/stop
- Buffer switching during countdown
- Window closing during active session

## Mock & Stub Strategy

### Required Mocks
```lua
-- tests/helpers.lua
local M = {}

-- Mock vim.api buffer operations
M.mock_buffer = function()
  local buffers = {}
  local buffer_counter = 1

  vim.api.nvim_create_buf = function(listed, scratch)
    local bufnr = buffer_counter
    buffer_counter = buffer_counter + 1
    buffers[bufnr] = {
      lines = {},
      options = {},
      listed = listed,
      scratch = scratch
    }
    return bufnr
  end

  vim.api.nvim_buf_set_lines = function(bufnr, start, end_, strict, lines)
    buffers[bufnr].lines = lines
  end

  return buffers
end

-- Mock vim.loop.hrtime for deterministic timing
M.mock_time = function(increments)
  local time_index = 0
  vim.loop.hrtime = function()
    time_index = time_index + 1
    return (increments[time_index] or 0) * 1e9
  end
end

-- Mock mini.diff module
M.mock_mini_diff = function()
  _G.MiniDiff = {
    enable = function() return true end,
    disable = function() return true end,
    get_buf_data = function()
      return {
        hunks = {
          { start = 1, count = 3, type = "add" },
          { start = 10, count = 2, type = "delete" }
        }
      }
    end
  }
end

-- Mock vim.on_key handler
M.mock_on_key = function()
  local handlers = {}
  local handler_id = 0

  vim.on_key = function(callback, namespace)
    handler_id = handler_id + 1
    handlers[handler_id] = { callback = callback, namespace = namespace }
    return handler_id
  end

  vim.on_key(nil, handler_id) -- Unregister

  return {
    trigger = function(key)
      for _, handler in pairs(handlers) do
        handler.callback(key)
      end
    end
  }
end

return M
```

## GitHub Actions Workflow

### `.github/workflows/test.yml`
```yaml
name: Tests

on:
  push:
    branches: [ main, rewrite ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        neovim_version: ['v0.9.5', 'v0.10.2', 'nightly']

    steps:
    - uses: actions/checkout@v4

    - name: Install Neovim
      uses: rhysd/action-setup-nvim@v1
      with:
        version: ${{ matrix.neovim_version }}

    - name: Cache test dependencies
      uses: actions/cache@v4
      with:
        path: tests/deps
        key: ${{ runner.os }}-test-deps-${{ hashFiles('tests/minimal_init.lua') }}

    - name: Run tests
      run: make test

    - name: Upload test results
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: test-results-${{ matrix.neovim_version }}
        path: tests/results/

  coverage:
    runs-on: ubuntu-latest
    needs: test
    steps:
    - uses: actions/checkout@v4

    - name: Install Neovim
      uses: rhysd/action-setup-nvim@v1
      with:
        version: 'v0.10.2'

    - name: Install coverage tools
      run: |
        luarocks install luacov
        luarocks install luacov-console

    - name: Run tests with coverage
      run: make test-coverage

    - name: Generate coverage report
      run: luacov-console -s tests/

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v4
      with:
        files: ./luacov.report.out
```

## Makefile Targets

```makefile
.PHONY: test test-unit test-integration test-watch test-coverage clean-test

# Run all tests
test:
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Run only unit tests
test-unit:
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/unit/ {minimal_init = 'tests/minimal_init.lua'}"

# Run only integration tests
test-integration:
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/integration/ {minimal_init = 'tests/minimal_init.lua'}"

# Watch mode for development
test-watch:
	@find lua/ tests/ -name "*.lua" | entr make test

# Run tests with coverage
test-coverage:
	@nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "lua require('luacov')" \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Clean test artifacts
clean-test:
	@rm -rf tests/results/
	@rm -f luacov.*.out
```

## Implementation Checklist

- [ ] Create `tests/` directory structure
- [ ] Write `minimal_init.lua` bootstrap script
- [ ] Implement `helpers.lua` with mocks and utilities
- [ ] Add fixture files for testing
- [ ] Clone test dependencies (plenary.nvim, mini.diff)

### Unit Test Implementation
- [ ] `buffer_spec.lua` - Buffer utilities (dedent, normalize, naming)
- [ ] `stats_spec.lua` - WPM and keystroke calculations
- [ ] `par_spec.lua` - Par calculation and edit distance
- [ ] `keystroke_spec.lua` - Keystroke tracking logic

### Integration Test Implementation
- [ ] `session_lifecycle_spec.lua` - Session start/stop/reset
- [ ] `visual_feedback_spec.lua` - Ghost text and highlights
- [ ] `timer_completion_spec.lua` - Timer and completion detection
- [ ] `golf_navigation_spec.lua` - Reference window and navigation
- [ ] `picker_flow_spec.lua` - Picker UI and source selection
- [ ] `autocmds_spec.lua` - Autocmd behavior

### CI/CD Setup
- [ ] Create `.github/workflows/test.yml`
- [ ] Configure matrix testing for multiple Neovim versions
- [ ] Set up dependency caching
- [ ] Add coverage reporting
- [ ] Configure PR status checks

### Documentation
- [ ] Update README with testing instructions
- [ ] Add contributing guidelines
- [ ] Document coverage goals (target: 80%+)
- [ ] Create test writing guide for contributors

## Success Metrics

- **Coverage Target**: 80% or higher for core functionality
- **CI Performance**: Tests complete in under 2 minutes
- **Reliability**: Zero flaky tests in CI
- **Maintainability**: Clear test names and documentation
- **Speed**: Unit tests < 100ms, Integration tests < 1s each

## Future Enhancements

1. **Performance Testing**: Benchmark large file handling
2. **Stress Testing**: Multiple concurrent sessions
3. **Visual Regression**: Screenshot-based testing for UI elements
4. **Property-Based Testing**: Fuzz testing for edge cases
5. **Mutation Testing**: Verify test quality
6. **E2E Testing**: Full user workflow scenarios