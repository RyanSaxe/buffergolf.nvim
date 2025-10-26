# BufferGolf Config Flexibility Plan

## Goal

Enable users to declaratively customize what gets disabled or tweaked when a BufferGolf session starts, without hand-rolled autocommands. The new API should:

- Cover common toggles (diagnostics, inlay hints, matchparen, autopairs, Copilot, Blink, CMP, etc.).
- Allow arbitrary user logic with minimal boilerplate.
- Run safely inside BufferGolf’s session lifecycle (creation, enter/leave, teardown).
- Remain backwards compatible with today’s `disable_*` booleans.

## High-Level Approach

1. **Restructure configuration** under `practice_buffer` and `reference_buffer` tables that hold:
   - `disable` (booleans/strings that map to built-in handlers).
   - `integrations` (shorthand for known plugins, or custom callback).
   - Lifecycle hooks (`on_create`, `on_enter`, `on_leave`, `on_exit`).
   - Mode-specific overrides (`typing_mode`, `golf_mode`) for settings that differ between modes.
2. **Introduce a hook context object** passed to callbacks. Context provides:
   - `ctx.buf`, `ctx.win`, `ctx.mode`, `ctx.origin_buf`.
   - Helpers `ctx:set_opt()`, `ctx:set_var()`, `ctx:disable(<integration>)`, `ctx:notify_err()`.
3. **Create an integration registry** mapping integration keys to handler functions. Ship defaults for popular plugins (Copilot, nvim-cmp, blink.cmp, mini.pairs, nvim-autopairs, codeium, etc.) and let users extend via `integrations.custom = { my_key = function(ctx) ... end }`.
4. **Bridge legacy booleans** by translating `setup` options (`disable_diagnostics`, `disable_inlay_hints`, etc.) into the new `practice_buffer.disable` table.
5. **Support mode-specific configuration** allowing different behavior for typing mode (empty buffer) vs golf mode (code transformation).

## Mode-Specific Configuration Rationale

Different practice modes have different needs:

**Typing Mode** (empty buffer, retyping from scratch):

- Matchparen less useful with empty buffer
- Focus on muscle memory and accuracy
- Minimal visual distractions preferred

**Golf Mode** (editing existing code):

- Matchparen helpful for bracket navigation
- Code transformation context
- Diff visualization relevant

The config system should support both common settings and mode-specific overrides.

## Example Configuration

```lua
require("buffergolf").setup({
  practice_buffer = {
    -- Common settings (apply to both modes unless overridden)
    disable = {
      diagnostics = true,
      inlay_hints = true,
      autopairs = true,
    },

    -- Mode-specific overrides
    typing_mode = {
      disable = {
        matchparen = true,  -- disable in typing mode
      },
    },
    golf_mode = {
      disable = {
        -- matchparen stays enabled (not in disable list)
      },
    },

    -- Plugin integrations
    integrations = {
      copilot = true,          -- built-in helper sets buffer vars
      blink = true,            -- shim runs BlinkDisable/Enable
      cmp = function(ctx)      -- per-buffer custom logic
        ctx:disable("cmp")     -- reuse registry helper
        ctx:set_var("cmp_muted", true)
      end,
    },

    -- Lifecycle hooks with mode awareness
    on_create = function(ctx)
      ctx:set_opt("relativenumber", false)

      -- Mode-specific logic via hooks
      if ctx.mode == "typing" then
        ctx:set_var("typing_mode_active", true)
      end
    end,
    on_enter = function(ctx)
      ctx:set_var("my_plugin_off", true)
    end,
    on_exit = function(ctx)
      ctx:disable("copilot", { enable = true }) -- optional custom flags
    end,
  },
  reference_buffer = {
    disable = { diagnostics = true },
  },
})
```

## Implementation Steps

1. **Configuration Parsing**
   - Merge user opts with defaults using the new nested structure.
   - Convert legacy booleans into `practice_buffer.disable`.
   - Parse mode-specific blocks (`typing_mode`, `golf_mode`) and merge with common settings.
   - Validate user-provided tables/functions with descriptive error messages.
2. **Hook & Integration Module**
   - Add `lua/buffergolf/hooks.lua` to build contexts and run callbacks (`pcall` + `vim.notify`).
   - Define the integration registry and exposed helper methods.
3. **Session Wiring**
   - Update `Session.start`, `buffer.apply_defaults`, and teardown (`clear_state`) to invoke disable handlers and hooks at the correct lifecycle points.
   - Select appropriate mode-specific config based on `session.mode` ("typing" vs "golf").
   - Ensure hooks run on `BufEnter`, `BufLeave`, `LspAttach`, and final cleanup.
4. **Reference Buffer Support**
   - Mirror disable/integration logic for reference windows using `reference_buffer` config.
5. **Documentation & Examples**
   - Rewrite README configuration section with migration notes, lifecycle diagrams, and real-world snippets.
   - Highlight common integrations (Copilot, blink.cmp, nvim-cmp).
6. **Testing & Validation**
   - Add targeted unit/integration tests (if feasible) covering:
     - Legacy config compatibility.
     - Hook execution order and error handling.
     - Integration toggles running even when plugin is missing (no crash).
   - Manual smoke test with personal dotfiles as validation.

## Open Questions

- Should we auto-detect integrations by checking for global variables/commands, or always require explicit opt-in?
- Should disabling matchparen remain a window-level helper or move fully into integrations?
- **Mode-specific config precedence**: Should `typing_mode`/`golf_mode` blocks completely override common `disable` settings, or merge with them (mode settings taking precedence on conflicts)?
- **Mode-specific integrations**: Should we support mode-specific integration configs, or rely solely on `ctx.mode` checks within integration callbacks?
- **Default mode behavior**: Should we ship with opinionated defaults where typing mode disables more than golf mode, or keep them identical by default?
