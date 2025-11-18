# GitHub Copilot Workspace Instructions

This file provides GitHub Copilot-specific guidance for the `snacks-vimtex-output` repository.

## Core Guidance

For architectural decisions, coding standards, and general contribution guidelines, see [AGENTS.md](../AGENTS.md) in the repository root. This file contains only Copilot-specific instructions and workspace context.

## Workspace Context

- **Language**: Lua (Neovim plugin)
- **Primary file**: `lua/snacks-vimtex-output/init.lua`
- **Dependencies**: VimTeX, snacks.nvim (optional), Neovim 0.9+
- **Formatting**: StyLua (run `stylua lua/` before committing)

## Copilot-Specific Best Practices

### Code Suggestions

When suggesting code completions:

1. **Match existing patterns**: The codebase uses specific patterns for state management, window creation, and event handling. Follow these patterns rather than introducing new approaches.

2. **Preserve comments**: When modifying functions, maintain or enhance existing comments. Comments explain *why*, not just *what*.

3. **Window configuration**: Window dimension calculations are complex. When suggesting changes to `window_dimensions()` or related functions, consider all edge cases (small terminals, large monitors, different anchors).

4. **State token patterns**: The codebase uses token-based cancellation (e.g., `hide_token`, `render_retry_token`). When suggesting async operations, follow this pattern.

### Testing Suggestions

Suggest manual testing approaches when relevant:

- Test with and without snacks.nvim installed
- Test auto-open enabled and disabled
- Test with various window sizes
- Test rapid compilation triggers (save spam)
- Test with missing or inaccessible log files

### Documentation

When suggesting documentation changes:

- Ensure README examples match actual code defaults
- Add troubleshooting entries for edge cases you discover
- Update the Alternatives section if behavior changes affect the comparison

## Quick Reference

### Key Functions

- `M.setup(opts)`: Main entry point, merges user config with defaults
- `render_window(opts)`: Creates or updates the floating window
- `update_buffer_from_file(force)`: Polls log file and updates buffer
- `start_polling()`: Initiates live update loop
- `on_compile_*()`: Event handlers for VimTeX compilation events

### State Variables

- `state.win`: Window handle (or nil if closed)
- `state.buf`: Buffer handle for log content
- `state.status`: "idle" | "running" | "success" | "failure"
- `state.focused`: Boolean for mini vs. focus mode
- `state.timer`: uv timer for polling loop

### Configuration Sections

- `config.mini`: Compact overlay dimensions
- `config.focus`: Expanded overlay dimensions
- `config.auto_open`: Auto-show on compilation start
- `config.auto_hide`: Auto-hide on successful builds
- `config.notifications`: Notification behavior

## Common Pitfalls

1. **Don't break state isolation**: The module maintains a single global state. Avoid introducing module-level variables that bypass state management.

2. **Don't assume synchronous operations**: File polling, timers, and autocmds are all asynchronous. Use tokens for cancellation and avoid race conditions.

3. **Don't hardcode dimensions**: All window dimensions come from config. Don't suggest magic numbers; use config values or calculated dimensions.

4. **Don't forget error handling**: pcall is used extensively for Neovim API calls. Maintain this pattern for robustness.

## Integration Points

This plugin integrates with:

- **VimTeX**: Reads `vim.b.vimtex.compiler.output` for log file path, listens to VimTeX autocmd events
- **snacks.nvim**: Optional dependency for notifications (falls back to `vim.notify`)
- **Neovim APIs**: Uses floating windows, buffers, timers, and autocmds

When suggesting changes, be mindful of these integration boundaries and test compatibility.

## Commit Message Format (MANDATORY)

All commit messages **must** follow this exact format:
```
(scope) Brief description of the change
```

**Rules:**
- The scope **must** be a single word enclosed in parentheses
- The scope should be lowercase
- Use a compound word (e.g., `auto-hide`, `config-merge`) only if absolutely necessary
- There must be exactly one space between the closing parenthesis and the description
- The description should be concise and written in imperative mood

**Common scopes:**
- `docs` - Documentation changes
- `config` - Configuration-related changes
- `window` - Window rendering or positioning
- `notify` - Notification system changes
- `state` - State management changes
- `poll` - Polling mechanism changes
- `event` - Event handler changes
- `fix` - Bug fixes
- `refactor` - Code refactoring
- `meta` - Repository meta files or tooling

**Examples:**
- `(docs) Fix default value inconsistencies in README`
- `(config) Add auto_hide option for successful builds`
- `(window) Adjust mini mode dimensions for small terminals`
- `(notify) Implement persist_failure configuration`
