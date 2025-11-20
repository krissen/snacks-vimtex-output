# output-panel.nvim

A configurable floating output window for Neovim jobs. The plugin began life as a
VimTeX helper but now exposes a generic runner so any long-running shell
command—`Rscript`, `pandoc`, custom build scripts, etc.—can stream their stdout
and stderr into the same lightweight panel while surfacing success/failure
notifications, with Snacks support kept as an optional treat for extra polish.
The original VimTeX integration
remains available as a preconfigured profile and example workflow.

## Requirements

- Neovim **0.8+** (`vim.fn.jobstart` powers live streaming; `vim.system`
  integrations kick in automatically when available)
- [snacks.nvim](https://github.com/folke/snacks.nvim) *(optional)* — richer
  notifications if you want that extra treat
- [VimTeX](https://github.com/lervag/vimtex) *(optional)* — only needed if you
  want automatic LaTeX compiler integration

## Highlights

- **General runner** – `require("output-panel").run()` executes any shell
  command asynchronously, streams live output, colours the border based on exit
  status, and fires notifications.
- **Profiles & overrides** – Define reusable configuration profiles and apply
  them per command so each workflow can tweak window geometry, notification
  titles, auto-hide timing, etc.
- **Notifier fallback chain** – Works out of the box with `vim.notify`, happily
  upgrades to `snacks.notify` when available, and accepts any custom notifier you
  want to plug in.
- **VimTeX aware** – Ships the original auto-open, auto-hide, and command suite
  for `latexmk` logs, now powered by the same configurable panel.
- **Knit helper** – `require("knit.run")` is a zero-dependency runner that
  hooks into the panel only when you opt-in to live output.

## Installation

### lazy.nvim

```lua
{
  "krissen/output-panel.nvim",
  dependencies = {
    -- Optional, but recommended for LaTeX workflows
    "lervag/vimtex",
    -- Optional notifications/popup helpers
    "folke/snacks.nvim",
  },
  config = function()
    require("output-panel").setup({
      -- global options go here; see below for the full list
    })
  end,
}
```

> Existing configs that still `require("snacks-vimtex-output")` continue to
> work via a compatibility shim, but new setups should switch to
> `require("output-panel")`.

## Usage

### Running arbitrary commands

Call `run()` with the command you want to execute. Output streams into the
panel, and notifications summarise the exit status.

```lua
local panel = require("output-panel")

-- Knit the current RMarkdown file using Rscript
vim.keymap.set("n", "<leader>rk", function()
  panel.run({
    cmd = { "Rscript", "bifrost__knit.R", "-r", vim.fn.expand("%") },
    profile = "knit", -- optional profile defined in setup()
    success = "Document knitted",
    error = "Knitting failed",
    start = "Knitting…",
  })
end, { desc = "Knit document" })
```

Key behaviours:

- `cmd` accepts a string, list, or function returning either. Strings run inside
  `sh -c` (or `cmd.exe /c` on Windows).
- Notifications inherit their title/timeouts from the active profile. Provide
  `success`/`error` strings for custom labels.
- Set `open = false` to keep the panel hidden until you manually call
  `require("output-panel").show()`.
- Each run gets its own temporary log file, so you can revisit the output even
  after the command completes.

### Knit helper

`lua/knit/run.lua` ships a lightweight wrapper for RMarkdown/Quarto workflows.
It mirrors the `run()` API but defaults to plain notifications unless you set
`output_panel`/`live_output = true`, in which case it proxies to the panel.

```lua
local knit_run = require("knit.run")

vim.keymap.set("n", "<leader>rk", function()
  knit_run.run({
    cmd = { "Rscript", "bifrost__knit.R", "-r", vim.fn.expand("%") },
    title = "Knit document",
    success = "Document knitted",
    error = "Knitting failed",
    output_panel = true, -- live stream via output-panel.nvim
    panel = {
      profile = "knit",
      focus = false,
    },
  })
end, { desc = "Knit document" })
```

Without `output_panel` it simply routes notifications through the usual fallback
chain (Snacks first if installed, otherwise `vim.notify`) while still respecting
the provided titles/timeouts. Use the `panel` table to
adjust the window when live streaming (e.g. set a dedicated profile, tweak
layout, or disable `notify_start`).

### VimTeX integration

Install VimTeX, call `setup()`, and the panel automatically follows
`VimtexEventCompiling`, `VimtexEventCompileSuccess`, etc. The plugin now exposes
general commands while keeping the VimTeX-prefixed aliases for compatibility:

| Command | Description |
| --- | --- |
| `:OutputPanelShow` | Open the panel for the active VimTeX buffer or last command. |
| `:OutputPanelHide` | Close the panel. |
| `:OutputPanelToggle` | Toggle visibility. |
| `:OutputPanelToggleFocus` | Switch between mini/focus layouts. |
| `:OutputPanelToggleFollow` | Toggle follow/tail mode. |

Legacy `:VimtexOutput*` commands remain as aliases so existing mappings keep
working.

Press `<Esc>` while focused to drop back to the compact mini overlay without closing
the panel.

The overlay attaches to VimTeX's compiler log (usually the `latexmk` stdout
buffer) and retains all prior behaviours—auto-open on compilation, optional
auto-hide on success, green/red borders, and persistent error notifications.

### API helpers

```lua
local panel = require("output-panel")
panel.show()          -- open panel for the current target
panel.hide()          -- hide panel
panel.toggle()        -- toggle visibility
panel.toggle_follow() -- toggle follow/tail mode
panel.toggle_focus()  -- swap between mini/focus layouts
panel.run({...})      -- run arbitrary commands (see above)
```

## Configuration

`setup()` merges your overrides with the defaults below. Profiles are deep
merged, so you can inherit global values and tweak only what each workflow
needs.

```lua
require("output-panel").setup({
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
  scrolloff_margin = 5,
  border_highlight = "FloatBorder",
  auto_open = {
    enabled = false,
    retries = 6,
    delay = 150,
  },
  auto_hide = {
    enabled = true,
    delay = 3000,
  },
  notifications = {
    enabled = true,
    title = "VimTeX",
    persist_failure = 45,
  },
  follow = {
    enabled = true,
  },
  poll = {
    interval = 150,
  },
  max_lines = 4000,
  open_on_error = true,
  notifier = nil,
  profiles = {
    knit = {
      notifications = { title = "Knit" },
      auto_hide = { enabled = false },
    },
  },
})
```

`follow.enabled` keeps the panel in tail/follow mode whenever it's opened.
`poll.interval` controls how often (in milliseconds) the plugin refreshes the
log buffer while the window is visible—lower values update faster but run the
timer more frequently. `notifications.persist_failure` accepts `false` to skip
sticky errors, `0`, `-1`, or `true` to keep them indefinitely, and positive
numbers for the number of seconds (45 by default) before dismissing the toast.
Failure notifications are scoped per build/command, so rerunning the same job,
letting a watcher (like VimTeX's continuous `latexmk`) kick off another cycle,
or simply finishing successfully immediately clears the stale error. Clearing a
toast never prunes Snacks' history viewer, so you can still audit prior errors
while unrelated tasks keep their own entries. Toggle it ad-hoc via
`:OutputPanelToggleFollow` (alias: `:VimtexOutputToggleFollow`) or
`require("output-panel").toggle_follow()`. `max_lines` trims the scratch buffer
so very chatty commands never retain more than the configured line count, and
`open_on_error` makes failures pop the panel even if live output was disabled
while the job ran.

### Profiles

Profiles are arbitrary tables merged into the active configuration whenever you
call `run({ profile = "name" })`. Use them to change the notification title,
auto-hide behaviour, or window layout for a specific workflow without touching
other commands.

You can also bypass profiles and pass `config = { ... }` directly to `run()` for
one-off overrides.

### Notification backends

Notifications follow a fallback chain:

1. Custom notifier provided via `setup({ notifier = { info=…, warn=…, error=… } })`
2. `snacks.notify` (if Snacks is installed and exposes it)
3. `vim.notify`

This applies everywhere—VimTeX events and manual command runs.

### Tips

- Increase `mini.height_ratio` or `mini.height_max` if your commands are chatty.
- Bump `scrolloff_margin` if the mini panel covers your cursor.
- Set `auto_open.enabled = true` to auto-pop the panel whenever VimTeX begins
  compiling.
- Disable `auto_hide` globally or per profile if you want successful runs to
  stay visible.
- Toggle follow mode with `:OutputPanelToggleFollow` (alias:
  `:VimtexOutputToggleFollow`) before scrolling through older log lines.
- Lower `max_lines` if you're running extremely verbose scripts and want to keep
  the scratch buffer tighter.
- Assign `notifier` to integrate with `noice.nvim`, `rcarriga/nvim-notify`, or
  any custom logger.

## Troubleshooting

- **Nothing shows up when running a command** – Ensure you're on Neovim 0.8+
  and that the command exists in your `$PATH`. The panel writes every chunk to a
  temp file; open it via `:edit {path}` to inspect raw output.
- **VimTeX overlay never opens** – Set `auto_open.enabled = true` or run one of
  the `:OutputPanel*` commands manually (legacy `:VimtexOutput*` aliases also
  work). Verify `vim.b.vimtex.compiler.output` is populated in your TeX buffer.
- **Notifications missing** – Confirm `notifications.enabled = true` and that
  your custom notifier isn't erroring. The plugin logs failures inside the panel.
- **Want different layouts per workflow** – Define multiple profiles and pass
  `profile = "name"` when calling `run()`.

## Why keep the VimTeX docs?

The project started as *snacks-vimtex-output*, and the LaTeX workflow remains a
first-class citizen. VimTeX already streams compiler logs to splits, but the
panel provides:

| Feature | Panel | VimTeX stock output |
| --- | --- | --- |
| Display | Floating mini/focus overlay | Regular splits |
| Auto-hide | Yes (configurable) | No |
| Visual status | Border colours + notifications | Messages only |
| Buffer type | Scratch, hidden by default | Normal buffer |

Use whichever suits your workflow—the panel simply adds a custom floating skin
on top of VimTeX's reliable compilation backend while now powering any other
command you want to monitor.

## How does this compare to other plugins?

Neovim already offers several ways to run commands asynchronously. The panel
deliberately fills the gap between a full task manager and raw quickfix output.
In particular, [Overseer.nvim](https://github.com/stevearc/overseer.nvim) should
be your first stop whenever you want templated builds, task registries, file
watchers, or an interactive dashboard. Reach for output-panel.nvim when you only
need a single command (or VimTeX) log visible in the background with minimal
setup and no extra UI to manage.

### Overseer.nvim

[Overseer](https://github.com/stevearc/overseer.nvim) is the closest feature
match: it manages a registry of tasks, templates, diagnostics integration, and
per-task metadata while exposing quick actions (rerun, stop, restart, watch on
save) and a toggleable dashboard (`:OverseerToggle`) that lists every job. That
power comes at the cost of additional configuration (`use_terminal`, component
pipelines, task bundles, recommended dependencies like `plenary.nvim` and
`nvim-notify`, etc.) and a larger UI footprint. If you want that level of
control—multiple concurrent builds, VS Code-style task definitions, or a central
place to inspect historical runs—Overseer is absolutely the better fit.

output-panel.nvim intentionally stops earlier: no task list, no history, just a
single scratch buffer that auto-opens on failure/success and can be wired
directly to VimTeX hooks or ad-hoc shell commands. It excels when you prefer to
trigger commands via existing mappings (`:VimtexCompile`, custom keymaps, save
autocmds) and simply want to watch stdout scroll in a compact overlay without
learning a new task abstraction. Overseer can be configured to behave similarly,
but doing so typically requires authoring task definitions and tweaking layout
settings—effort that outweighs the benefit when you only need a “fire-and-forget”
pane.

#### Streaming Overseer tasks into the panel

The plugin ships an Overseer component called `output_panel`. Include it in your
task components to stream output into the same floating buffer used by
`:OutputPanelToggle`/`:OutputPanelShow`:

```lua
require("overseer").setup({
  component_aliases = {
    default = { "default", { "output_panel", open = true } },
  },
})
```

You can also attach it to individual tasks via `components = { "default",
{ "output_panel", focus = false } }` when calling `overseer.run_template()`.

### ToggleTerm and generic terminals

[toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) (and plain
`:terminal`) provide real shells. They shine when you want an interactive REPL
or when a command expects input, but that also means the buffer is stateful: you
can accidentally send keystrokes to the shell, scrollback is persistent across
runs, and you have to manually reset the prompt. The output panel is a
read-only, auto-trimmed buffer that is recreated for every run, so it behaves
more like an IDE build pane than a terminal emulator.

### Quickfix/location list (asyncrun.vim, vim-dispatch)

Plugins such as [asyncrun.vim](https://github.com/skywind3000/asyncrun.vim) and
[vim-dispatch](https://github.com/tpope/vim-dispatch) stream output into the
quickfix list. That is perfect when you want structured error navigation, but it
comes with trade-offs: multi-line logs are flattened into entries, colouring and
formatting are lost, and you can easily clobber the quickfix list that LSP or
other commands rely on. The output panel sidesteps those issues by maintaining a
separate scratch buffer with optional syntax highlighting while still sending
success/failure notifications like dispatch.

### Trouble.nvim and diagnostics explorers

[Trouble.nvim](https://github.com/folke/trouble.nvim) and similar explorers
excel at visualising diagnostics, references, and quickfix/location lists. They
are intentionally opinionated about structure (severity grouping, jump lists,
filters), whereas the panel intentionally avoids parsing. Use Trouble when you
want to triage issues; use the panel when you want the raw log for debugging.

### Noice.nvim and notification UIs

[Noice](https://github.com/folke/noice.nvim) re-skins Neovim’s messages and can
proxy `vim.notify`, so it compliments output-panel.nvim by rendering the panel’s
completion notifications. It does not, however, provide an output buffer or task
runner. If you already run Noice, the panel’s notifier fallback (Snacks first if
present, otherwise `vim.notify`) means your completion alerts flow through Noice
without any special setup.

## Development

- Format with `stylua lua/`.
- Run different commands/profiles manually to test notification paths.
- Verify behaviour with and without Snacks and VimTeX loaded.
