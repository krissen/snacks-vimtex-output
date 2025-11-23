# GitHub Copilot Workspace Instructions

This file provides GitHub Copilot-specific guidance for the `output-panel.nvim` repository.

## ⚠️ Primary Reference

**For all general guidance, read [AGENTS.md](../AGENTS.md) first.** That file is the single source of truth for:
- Repository purpose and architecture
- Coding standards and best practices
- Testing guidelines
- Commit message format (MANDATORY)
- Common development tasks

This file contains **only Copilot-specific** workspace context and quick references to assist with code completions.

## Copilot-Specific Tips

When providing code completions and suggestions:

1. **Preserve comments**: Maintain or enhance existing comments explaining *why*, not just *what*
2. **Use existing patterns**: Follow established patterns for state management, window creation, event handling
3. **Token-based cancellation**: Use tokens (e.g., `hide_token`, `render_retry_token`) for async operations
4. **No hardcoded values**: Use config values or calculations for all dimensions and timeouts
5. **Error handling**: Wrap Neovim API calls in pcall for robustness
6. **Adapter separation**: Keep adapter-specific logic separate from core command execution

## Quick Reference

### Key Public Functions

- `M.setup(opts)`: Main entry point, merges user config with defaults
- `M.run(opts)`: Execute arbitrary shell commands with live output streaming
- `M.stream(opts)`: Lower-level API for custom adapters to stream output
- `M.make(args)`: Run Neovim's makeprg through the panel (`:Make` command)
- `M.show()`: Open the panel for the current target
- `M.hide()`: Close the panel
- `M.toggle()`: Toggle panel visibility
- `M.toggle_follow()`: Toggle follow/tail mode
- `M.toggle_focus()`: Switch between mini and focus modes
- `M.adapter_enabled(name)`: Check if a profile/adapter is enabled

### Key Internal Functions

- `render_window(opts)`: Creates or updates the floating window
- `update_buffer_from_file(force)`: Polls log file and updates buffer
- `start_polling()`: Initiates live update loop
- `on_compile_*()`: Event handlers for VimTeX compilation events
- `window_dimensions()`: Calculates window size and position
- `notifier()`: Returns the active notification backend
- `current_config()`: Returns the merged configuration for current context

### State Variables

- `state.win`: Window handle (or nil if closed)
- `state.buf`: Buffer handle for log content
- `state.buffer_targets`: Map of buffer numbers to their target output paths
- `state.status`: "idle" | "running" | "success" | "failure"
- `state.focused`: Boolean for mini vs. focus mode
- `state.follow`: Boolean for tail/follow mode
- `state.timer`: uv timer for polling loop
- `state.target`: Current output file path
- `state.job`: Active command job handle
- `state.active_config`: Merged configuration for current context
- `state.failure_notifications`: Map of scoped failure notifications
- `state.hide_token`: Cancellation token for auto-hide
- `state.render_retry_token`: Cancellation token for render retries

---

**💡 For detailed architecture explanations, coding standards, and workflow requirements, see [AGENTS.md](../AGENTS.md)**
