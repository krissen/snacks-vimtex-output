# snacks-vimtex-output

Snacks-style floating overlay for [VimTeX](https://github.com/lervag/vimtex) compiler output. The plugin mirrors the familiar snacks.notify aesthetic and streams `latexmk` logs into a minimal floating window that can expand for focused inspection while surfacing build status via notifications.

## Requirements

- Neovim 0.9 or newer (0.10+ recommended for the best floating window APIs)
- [VimTeX](https://github.com/lervag/vimtex)
- [snacks.nvim](https://github.com/folke/snacks.nvim) for fancy notifications (falls back to `vim.notify` automatically)

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
        width_scale = 0.6,
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

Run `require("snacks-vimtex-output").setup()` once (e.g., inside your plugin manager config). After that the overlay opens automatically when VimTeX starts compiling, streams log updates while the build is running, and closes itself a few seconds after a successful compile. Failures stay visible until dismissed.

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
| `:VimtexOutputShow` | Open the overlay in mini mode. |
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
    width_scale = 0.55,
    width_min = 48,
    width_max = 120,
    height_ratio = 0.22,
    height_min = 5,
    height_max = 14,
    row_anchor = "bottom",
    row_offset = 3,
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
  scrolloff_margin = 2, -- extra cursor padding while the mini overlay is visible
  border_highlight = "FloatBorder", -- default window border highlight group
  auto_open = {
    enabled = true,
    retries = 6, -- how many times to retry opening while latexmk creates the log file
    delay = 150, -- milliseconds between retries
  },
  auto_hide = {
    enabled = true,
    delay = 3000, -- milliseconds before hiding after a successful build
  },
  notifications = {
    enabled = true,
    title = "VimTeX", -- label injected into notification popups
  },
  notifier = nil, -- table with info/warn/error overrides (falls back to snacks.notify/vim.notify)
})
```

### Tips

- Increase `mini.height_ratio` if your TeX toolchain is especially chatty.
- Set `auto_hide.enabled = false` to keep successful builds on screen until you close them.
- Provide a `notifier` table if you want to integrate with another notification framework.
- All helpers live on the module table, so you can call them from custom commands or statuslines.

## Development

Formatting is enforced through [Stylua](https://github.com/JohnnyMorganz/StyLua). Run `stylua lua/` before committing.
