# snacks-vimtex-output

Snacks-style floating overlay for [VimTeX](https://github.com/lervag/vimtex) compiler output. The plugin mirrors the familiar snacks.notify aesthetic and streams `latexmk` logs into a minimal floating window that can expand for focused inspection while surfacing build status via notifications.

## Requirements

- Neovim 0.9 or newer (0.10+ recommended for the best floating window APIs)
- [VimTeX](https://github.com/lervag/vimtex)
- [snacks.nvim](https://github.com/folke/snacks.nvim) for fancy notifications (falls back to `vim.notify` automatically)

## Alternatives & Comparison

### VimTeX's Built-in Output Buffer

VimTeX provides a stock compiler output buffer accessible via `:VimtexCompileOutput` (default keybinding `\lo`). This opens the log file in a standard Neovim buffer in a new window or split.

**How this plugin differs:**

| Feature | snacks-vimtex-output | VimTeX stock output |
|---------|---------------------|-------------------|
| **Display style** | Floating window with compact/focused modes | Traditional split/window buffer |
| **Auto-updates** | Live streaming during compilation | Live streaming during compilation |
| **UI integration** | Snacks.nvim-style notifications (persistent on errors) | Messages appear in `:messages` |
| **Auto-hide** | Automatically hides on successful builds (configurable) | Stays open until manually closed |
| **Visual feedback** | Color-coded borders (green for success, red for errors) | Standard buffer appearance |
| **Workspace impact** | Overlays workspace (may cover content) | Creates/reuses split (changes layout) |
| **Buffer type** | Read-only scratch buffer | Standard buffer in the buffer list |

**When to use this plugin:**

- You prefer floating window UIs that minimize layout changes
- You appreciate visual status indicators (border colors, notifications)
- You're already using snacks.nvim and want consistent UI aesthetics
- You want automatic cleanup (hide on success) to reduce clutter

**When to stick with VimTeX's built-in output:**

- You prefer traditional buffer-based workflows
- You want the output to persist in a predictable window/split location
- You don't want additional plugin dependencies
- You prefer complete control over when the output appears and disappears
- You want the buffer in your buffer list for standard navigation

Both approaches are valid; this plugin complements VimTeX rather than replacing its output functionality.

## Installation

### lazy.nvim

```lua
{
  "krissen/snacks-vimtex-output",
  dependencies = { "lervag/vimtex", "folke/snacks.nvim" },
  ft = "tex",
  config = function()
    require("snacks-vimtex-output").setup({
      -- optional overrides; see below for the full list
      mini = {
        width_scale = 0.75,
      },
    })
  end,
}
```

### packer.nvim

```lua
use({
  "krissen/snacks-vimtex-output",
  requires = { "lervag/vimtex", "folke/snacks.nvim" },
  config = function()
    require("snacks-vimtex-output").setup()
  end,
})
```

If you prefer another notifier (such as `noice.nvim` or a custom callback), pass a table with `info`, `warn`, and `error` functions via the `notifier` option.

## Usage

Run `require("snacks-vimtex-output").setup()` once (e.g., inside your plugin manager config).

### Default behavior

- After installation nothing pops up automatically—the plugin waits for you to call one of its helpers or commands.
- Once opened, the overlay attaches to the current VimTeX build, streams log updates live, and hides on success (if `auto_hide.enabled` is true). You can close it mid-build and reopen it later; the stream resumes immediately.
- Failed builds stay visible until you close them so you can read the error trace.
- Notifications mirror each build status without any additional configuration. Failure popups stay pinned (by default) so you can revisit the log, but a later success automatically replaces the old error.
- The overlay is read-only; hiding or reopening it never pauses or stops VimTeX builds.
- Want the overlay to appear the moment a compile starts? Set `auto_open.enabled = true` to opt in to the automatic window. The plugin listens to both `VimtexEventCompileStarted` and `VimtexEventCompiling`, so continuous latexmk rebuilds triggered by buffer writes reopen the overlay as well.

### Manual control

The module exposes helpers you may call directly if you want to wire custom logic:

```lua
local vimtex_output = require("snacks-vimtex-output")
vimtex_output.show()
vimtex_output.hide()
vimtex_output.toggle()
vimtex_output.toggle_focus()
```

### Commands

| Command | Description |
| --- | --- |
| `:VimtexOutputShow` | Show the overlay. |
| `:VimtexOutputHide` | Close the overlay. |
| `:VimtexOutputToggle` | Toggle visibility. |
| `:VimtexOutputToggleFocus` | Switch between the compact and focused layouts. |

The plugin intentionally leaves keymaps up to you. A simple example:

```lua
vim.keymap.set("n", "<leader>lo", ":VimtexOutputToggle<CR>", { silent = true })
vim.keymap.set("n", "<leader>lO", ":VimtexOutputToggleFocus<CR>", { silent = true })
```

## Configuration

`setup()` accepts a table that is deeply merged with the defaults below.

```lua
require("snacks-vimtex-output").setup({
  mini = {
    width_scale = 0.90,
    width_min = 48,
    width_max = 120,
    height_ratio = 0.10,
    height_min = 5,
    height_max = 14,
    row_anchor = "bottom",
    row_offset = 5,
    horizontal_align = 0.55,
    col_offset = 0,
  },
  focus = {
    width_scale = 0.95,
    width_min = 70,
    width_max = 220,
    height_ratio = 0.6,
    height_min = 14,
    height_max = 0,
    row_anchor = "center",
    row_offset = -1,
    horizontal_align = 0.5,
    col_offset = 0,
  },
  scrolloff_margin = 5, -- extra cursor padding while the mini overlay is visible
  border_highlight = "FloatBorder", -- default window border highlight group
  auto_open = {
    enabled = false, -- set to true to automatically pop open the overlay when VimTeX starts compiling
    retries = 6, -- how many times to retry opening while latexmk creates the log file or restarts
    delay = 150, -- milliseconds between retries
  },
  auto_hide = {
    enabled = true,
    delay = 3000, -- milliseconds before hiding after a successful build
  },
  notifications = {
    enabled = true,
    title = "VimTeX", -- label injected into notification popups
    persist_failure = true, -- keep the most recent failure notification visible until a success replaces it
  },
  notifier = nil, -- table with info/warn/error overrides (falls back to snacks.notify/vim.notify)
})
```

### Tips

- Increase `mini.height_ratio` if your TeX toolchain is especially chatty.
- Raise `mini.row_offset` (default 5) if you use a tall statusline and need extra breathing room above it.
- Set `notifications.persist_failure = false` if you prefer failure popups to fade like the rest of your notifications.
- Set `auto_hide.enabled = false` to keep successful builds on screen until you close them.
- Provide a `notifier` table if you want to integrate with another notification framework.
- All helpers live on the module table, so you can call them from custom commands or statuslines.

## Troubleshooting

### The overlay doesn't appear when compilation starts

**Possible causes:**

1. **Auto-open is disabled** (default behavior). The overlay only opens automatically if you set `auto_open.enabled = true` in your config. Otherwise, you need to manually trigger it with `:VimtexOutputToggle` or `require("snacks-vimtex-output").show()`.

2. **VimTeX is not properly initialized**. Ensure VimTeX is loaded and configured correctly. Check that `vim.b.vimtex` exists in your TeX buffer.

3. **Log file doesn't exist yet**. The plugin needs VimTeX's compiler output file. If auto-open is enabled but the overlay doesn't appear, try increasing `auto_open.retries` or `auto_open.delay` to give latexmk more time to create the log file.

### The overlay appears but shows no content

**Possible causes:**

1. **Log file is empty or being recreated**. VimTeX sometimes recreates the log file during compilation. The plugin's polling mechanism should pick up changes, but you can manually refresh by hiding and showing again.

2. **Permissions issue**. Ensure Neovim has read access to the compiler output file (typically a `.log` file in your project directory).

3. **Wrong file path**. The plugin reads from `vim.b.vimtex.compiler.output`. If VimTeX is configured with a custom output directory, ensure it's correctly set.

### Notifications aren't showing

**Possible causes:**

1. **Notifications are disabled**. Check that `notifications.enabled` is not explicitly set to `false`.

2. **snacks.nvim is not installed**. The plugin falls back to `vim.notify` if snacks is unavailable, but ensure your Neovim version supports the notify API (0.5+).

3. **Custom notifier is misconfigured**. If you provided a `notifier` table, ensure it has `info`, `warn`, and `error` functions.

### The overlay hides too quickly after successful builds

Increase the `auto_hide.delay` value (default is 3000ms):

```lua
require("snacks-vimtex-output").setup({
  auto_hide = {
    delay = 5000, -- wait 5 seconds before hiding
  },
})
```

Or disable auto-hide entirely:

```lua
require("snacks-vimtex-output").setup({
  auto_hide = {
    enabled = false,
  },
})
```

### The floating window covers my cursor

The plugin automatically increases `scrolloff` to prevent the overlay from covering the cursor in mini (unfocused) mode. If this isn't working, try increasing `scrolloff_margin`:

```lua
require("snacks-vimtex-output").setup({
  scrolloff_margin = 10, -- increase padding above the cursor
})
```

### I want to customize the window dimensions

All dimension parameters are configurable. See the Configuration section for the full list. Common adjustments:

- **Wider overlay**: Increase `mini.width_scale` or `mini.width_max`
- **Taller overlay**: Increase `mini.height_ratio` or `mini.height_max`
- **Reposition overlay**: Adjust `row_anchor`, `row_offset`, `horizontal_align`, `col_offset`

## Development

Formatting is enforced through [StyLua](https://github.com/JohnnyMorganz/StyLua). Run `stylua lua/` before committing.
