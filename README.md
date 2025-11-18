# snacks-vimtex-output

Render VimTeX compiler output inside Neovim using a distraction-free floating window while surfacing build status via Snacks notifications. The module provides a mini overlay that tracks compilation progress automatically, expands into a focusable view for inspection, and mirrors the status of your LaTeX builds through highlights and notifications.

## Features
- **Mini overlay:** Displays the tail of the compiler log in an unfocusable window that hugs the bottom of the editor.
- **Focusable view:** Toggle into a larger floating window to scroll through the full log without leaving your buffer.
- **Automatic updates:** Watches the VimTeX compiler output file, auto-opens during builds, and retries if the log is created lazily.
- **Status-aware UI:** Adjusts border highlights based on success or failure, and hides automatically after successful builds.
- **Snacks integration:** Uses Snacks notifications when available and falls back to `vim.notify` otherwise.

## Installation
Use your preferred plugin manager. Example with **lazy.nvim**:

```lua
{
  "user/snacks-vimtex-output",
  config = function()
    require("snacks-vimtex-output").setup()
  end,
  dependencies = {
    "lervag/vimtex",
    "folke/snacks.nvim",
  },
}
```

## Configuration
The module currently exposes a single `setup()` entry point and relies on the defaults below. Keep documentation in sync with `lua/snacks-vimtex-output/init.lua` before describing overrides.

```lua
local config = {
  mini = {
    width_scale = 0.9,
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
    height_ratio = 0.75,
    height_min = 14,
    height_max = 0,
    row_anchor = "center",
    row_offset = -1,
    horizontal_align = 0.5,
    col_offset = 0,
  },
  scrolloff_margin = 5,
  auto_open = {
    retries = 6,
    delay = 150,
  },
}
```

Override pieces by copying the relevant tables and calling `vim.tbl_deep_extend` or similar in your config. Remember to keep documentation examples synchronized whenever defaults evolve.

## Usage
The plugin registers the following commands after `setup()`:

- `:VimtexOutputShow` — open the mini overlay.
- `:VimtexOutputHide` — close the window.
- `:VimtexOutputToggle` — toggle visibility.

During VimTeX builds the overlay opens automatically, updates in real time, and reports results via notifications. Use `require("snacks-vimtex-output").toggle_focus()` to switch between the compact overlay and the larger focusable window.
