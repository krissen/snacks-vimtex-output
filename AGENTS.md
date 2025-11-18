# Contributor Guidance

## Purpose
- This repository ships the `output-panel.nvim` module described in [README.md](README.md). Keep every change aligned with the stated goal: provide a commented, well-documented Neovim helper that renders VimTeX compiler output and arbitrary shell logs inside lightweight floating windows. Snacks support stays optional—a pleasant notifier treat, but never the defining UI layer.

## Coding Standards
- Write idiomatic Lua that follows general Neovim and VimTeX best practices, with Snacks integration remaining purely optional.
- Favor DRY solutions; extract helpers whenever logic is reused.
- Every code block you touch **must be commented** in English to explain intent.
- Never wrap imports in `pcall`-based try/catch purely for style reasons—only when guarding optional dependencies.
- Follow the existing code style: 2-space indentation, consistent naming conventions.
- Use StyLua for formatting before committing (`stylua lua/`).

## Documentation
- Documentation and comments are always written in English.
- Update documentation whenever functionality or defaults change.
- Example configurations must always reflect the current defaults unless you explicitly document a non-default use case.
- README is the canonical place for describing project purpose, defaults, and usage; keep it synchronized with the implementation.
- When changing default values in `init.lua`, immediately update the corresponding documentation in README.md.
- Add inline comments for complex logic, especially for window positioning, polling mechanisms, and state management.

## Architecture & Key Concepts

### State Management
- The plugin maintains a single global `state` table tracking window, buffer, compilation status, timers, and notification references.
- State transitions follow: `idle` → `running` → `success`/`failure` → `idle`
- Never modify state directly without considering concurrent operations (timers, autocmds).

### Window Modes
- **Mini mode**: Compact, unfocused overlay for quick status checks (default when showing)
- **Focus mode**: Larger, interactive window for detailed log inspection
- Transitions between modes preserve window state and cursor position where appropriate.

### Polling & Live Updates
- A timer-based polling loop updates the buffer from the log file while the window is visible.
- The timer stops automatically when the window closes or compilation finishes.
- Retry logic handles race conditions when VimTeX recreates log files during compilation.

### Event Handling
- VimTeX events (`VimtexEventCompiling`, `VimtexEventCompileSuccess`, etc.) drive state transitions.
- Multiple event handlers may fire in quick succession; use token-based cancellation for deferred operations.

## Common Tasks

### Adding a new configuration option
1. Add the option to `default_config` in `init.lua` with a sensible default
2. Document it in the Configuration section of README.md
3. Add example usage in the Tips section if it solves a common use case
4. Consider adding a troubleshooting entry if users might misconfigure it

### Modifying window behavior
1. Window dimensions are calculated in `window_dimensions()` based on `config.mini` or `config.focus`
2. Position logic uses `row_anchor`, `row_offset`, `horizontal_align`, and `col_offset`
3. Always test with various terminal sizes and `cmdheight` settings
4. Update Tips section if the change affects common customization patterns

### Changing notification behavior
1. Notifications go through the `notify()` helper, which checks `config.notifications.enabled`
2. The `notifier()` function handles snacks.nvim detection and fallback to `vim.notify`
3. Failure notifications use `persist_failure` to optionally stay visible
4. Update README if changing default notification behavior

## Testing Guidelines
- Manually test with various VimTeX configurations (different compilers, output paths)
- Test both auto-open enabled and disabled scenarios
- Verify behavior with snacks.nvim present and absent
- Test window resizing and Neovim reloads
- Check error handling when log files are missing or inaccessible

## Workflow
- Prefer commit messages prefixed with a concise scope tag such as `(docs)`, `(window)`, `(notify)`, or `(state)` followed by a short description.
- Keep pull request summaries aligned with the actual behavior changes.
- Run `stylua lua/` before committing to ensure consistent formatting.
- Reference related issues or discussions in commit messages when applicable.

## Platform-Specific Instructions

This repository uses centralized agent instructions that work across multiple AI coding assistants. The core guidance above applies to all agents. For platform-specific integrations:

- **GitHub Copilot**: Refer to `.github/copilot-instructions.md` for workspace-specific instructions
- **ChatGPT / Codex**: This file serves as the primary instruction source

When adding new agent-specific instructions, update both this file (for general guidance) and platform-specific files (for platform-unique features). Avoid duplicating architectural or coding standard information.
