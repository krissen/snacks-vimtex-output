# output-panel.nvim

A configurable floating output window for Neovim jobs that combines **optional adapters** for VimTeX and Overseer with a **generic run() API** and **:Make helper** for everything else.

<br>

<p align="center">
  <img src="./.github/assets/demo.gif" width="90%" alt="Demo" />
</p>

<br>

The plugin focuses on keeping a single pane of live output available no matter how the work was started—ad-hoc shell commands, VimTeX builds, Neovim's built-in `:make`, or Overseer tasks all feed into the same scratch buffer and share the same notification pipeline.

**Core features:**
- **Generic `run()` API** – Execute any shell command with live output streaming
- **VimTeX adapter** – Automatically displays LaTeX compilation output (optional)
- **Overseer adapter** – Stream task output into the panel (optional, opt-in)
- **:Make helper** – Run `makeprg` with panel output instead of quickfix
- **Extensible** – Write your own adapters for LSP, Neotest, or any build system

## Requirements

- Neovim **0.8+** (`vim.fn.jobstart` powers live streaming; `vim.system`
  integrations kick in automatically when available)
- [snacks.nvim](https://github.com/folke/snacks.nvim) *(optional)* — richer
  notifications if you want that extra treat
- [VimTeX](https://github.com/lervag/vimtex) *(optional adapter)* — enables
  automatic LaTeX compiler integration
- [Overseer.nvim](https://github.com/stevearc/overseer.nvim) *(optional
  adapter)* — streams task output into the same panel

## Highlights

- **Generic command runner** – `run()` executes any shell command with live output streaming, notifications, and configurable behavior. No adapters required.
- **Output-first UI** – Everything funnels into a lightweight floating pane that follows the latest job. Toggle mini/focus modes to watch logs without managing extra splits or terminals.
- **Optional adapters** – Built-in adapters understand VimTeX and Overseer when installed, but the plugin works standalone. Write your own adapters for other tools using the `stream()` API.
- **Profiles & overrides** – Define reusable configuration profiles and apply them per command so each workflow can tweak window geometry, notification titles, auto-hide timing, etc.
- **Notifier fallback chain** – Works out of the box with `vim.notify`, happily upgrades to `snacks.notify` when available, and accepts any custom notifier you want to plug in.

## Architecture: Generic API + Optional Adapters

The plugin is built around a **generic command runner** (`run()`) that works standalone. Adapters and helpers are optional integrations that hook specific tools into this shared output system:

### Generic API

- **`run({cmd, ...})`** – Execute any shell command with live output, notifications, and configurable window behavior. Works without any adapters installed.
- **`stream({...})`** – Lower-level API for external tools to stream output into the panel. Used by adapters and available for custom integrations.

### Built-in Adapters & Helpers

- **VimTeX adapter** (optional, automatic)  
  Hooks into VimTeX compile events when VimTeX is loaded. Non-invasive: VimTeX commands continue to work normally, the panel just displays the output.

- **Overseer adapter** (optional, opt-in)  
  Component (`output_panel`) that you add to tasks you want to stream. Overseer works normally by default; you choose which tasks use the panel.

- **:Make helper** (built-in)  
  Provides a `:Make` command that wraps Neovim's built-in `makeprg` and streams output to the panel. The native `:make` command remains unchanged; use `:Make` when you want panel output.

All adapters and helpers can be disabled via `profiles.{name}.enabled = false` without removing their configuration. The panel works standalone for running arbitrary commands without any adapter.

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

> **Migration notes:**
> - Existing configs that still `require("snacks-vimtex-output")` continue to work via a compatibility shim, but new setups should switch to `require("output-panel")`.
> - The `knit.run` helper module has been removed. Use `output-panel.run()` directly instead. The `knit` profile is no longer included in defaults but you can keep it in your config if needed.

## Quick Start

The plugin works immediately after installation with zero configuration. Here are the most common ways to use it:

**Run any command with live output:**

```lua
:lua require("output-panel").run({ cmd = "npm run build" })
```

**Use :Make for build commands:**

```vim
:Make        " Run your makeprg and see output in the panel
:Make test   " Pass arguments to makeprg
```

**If you have VimTeX installed**, LaTeX compilation output automatically appears in the panel. Use `:OutputPanelToggle` to show/hide it, or `:OutputPanelToggleFocus` to switch between mini and focus modes.

**For custom workflows**, bind keys to `run()`:

```lua
vim.keymap.set("n", "<leader>b", function()
  require("output-panel").run({ cmd = "cargo build" })
end, { desc = "Build project" })
```

That's it! The panel handles notifications, streaming output, and visual feedback automatically. See below for more features like profiles, custom adapters, and configuration.

## Usage

### Running arbitrary commands

Call `run()` with the command you want to execute. Output streams into the
panel, and notifications summarise the exit status.

```lua
local panel = require("output-panel")

-- Render an R Markdown document
vim.keymap.set("n", "<leader>rk", function()
  panel.run({
    cmd = { "Rscript", "-e", "rmarkdown::render('" .. vim.fn.expand("%") .. "')" },
    title = "R Markdown",
    success = "Document rendered",
    error = "Rendering failed",
    start = "Rendering…",
  })
end, { desc = "Render R Markdown document" })

-- Run a Python script with live output
vim.keymap.set("n", "<leader>py", function()
  panel.run({
    cmd = { "python", vim.fn.expand("%") },
    title = "Python",
    success = "Script finished",
    error = "Script failed",
  })
end, { desc = "Run Python script" })

-- Example using a profile (profile must be defined in setup())
vim.keymap.set("n", "<leader>rb", function()
  panel.run({
    cmd = "cargo build",
    profile = "rust",  -- Uses settings from profiles.rust in setup()
  })
end, { desc = "Build Rust project" })
```

Define the profile in your setup:

```lua
require("output-panel").setup({
  profiles = {
    rust = {
      notifications = { title = "Rust Build" },
      auto_hide = { enabled = false },  -- Keep panel visible after builds
    },
  },
})
```

#### run() options

| Option | Type | Description |
|--------|------|-------------|
| `cmd` | `string|table|function` | **Required.** Command to execute. Strings run in shell (`sh -c`), tables as argv, functions return either. |
| `title` | `string` | Notification title (defaults to command) |
| `window_title` | `string` | Panel window title (defaults to `title`) |
| `profile` | `string` | Apply a named profile from setup (e.g., `"rmarkdown"`) |
| `config` | `table` | Inline configuration overrides |
| `success` | `string` | Success notification message |
| `error` | `string` | Error notification message |
| `start` | `string` | Start notification message |
| `notify_start` | `boolean` | Show start notification (default: `true`) |
| `open` | `boolean` | Show panel immediately (default: `true`) |
| `focus` | `boolean` | Open in focus mode vs mini mode (default: `false`) |
| `cwd` | `string` | Working directory for the command |
| `env` | `table` | Environment variables |
| `on_exit` | `function` | Callback when command completes: `function(result)` |

Key behaviours:

- `cmd` accepts a string, list, or function returning either. Strings run inside
  `sh -c` (or `cmd.exe /c` on Windows).
- Notifications inherit their title/timeouts from the active profile. Provide
  `success`/`error` strings for custom labels.
- Set `open = false` to keep the panel hidden until you manually call
  `require("output-panel").show()`. You can also set `auto_open.enabled` inside
  a profile or `config` override to change the default when `open` is omitted,
  letting a specific workflow stay quiet without affecting others.
- Each run gets its own temporary log file, so you can revisit the output even
  after the command completes.

### VimTeX adapter

When VimTeX is installed, `setup()` wires the panel to
`VimtexEventCompiling`, `VimtexEventCompileSuccess`, etc. The same commands work
with or without VimTeX; aliases remain for existing mappings:

| Command | Description |
| --- | --- |
| `:OutputPanelShow` | Open the panel for the active VimTeX buffer, Overseer task, or last command. |
| `:OutputPanelHide` | Close the panel. |
| `:OutputPanelToggle` | Toggle visibility. |
| `:OutputPanelToggleFocus` | Switch between mini/focus layouts. |
| `:OutputPanelToggleFollow` | Toggle follow/tail mode. |

Legacy `:VimtexOutput*` commands remain as aliases so existing mappings keep
working whether or not VimTeX is present.

Press `<Esc>` while focused to drop back to the compact mini overlay without closing
the panel.

When available, the adapter attaches to VimTeX's compiler log (usually the
`latexmk` stdout buffer) and retains all prior behaviours—auto-open on
compilation, optional auto-hide on success, green/red borders, and persistent
error notifications. Switching buffers retargets the window to whatever log is
active (VimTeX project, Overseer task, or manual command). Buffers without an
associated job leave the current output in place, avoiding unnecessary flicker.

#### How the VimTeX adapter works

The VimTeX adapter automatically hooks into VimTeX compilation events when VimTeX
is installed. It **does not replace** VimTeX's built-in commands or functionality
— VimTeX continues to work normally. The adapter simply adds the output panel as
an additional UI layer on top of VimTeX's compilation process.

- **VimTeX commands**: Continue to work as normal (`:VimtexCompile`, etc.)
- **Output panel**: Automatically shows VimTeX compilation output
- **Control**: Use `profiles.vimtex.enabled = false` to disable the adapter

The integration is non-invasive and can be toggled via the profile configuration
without affecting VimTeX's core functionality.

### Make helper

The plugin provides a `:Make` command that wraps Neovim's built-in `makeprg` and
streams the output into the panel instead of the quickfix list. This keeps you in
your current buffer while showing build output in the floating overlay.

```vim
:Make          " Run makeprg and show output in panel
:Make clean    " Pass arguments to makeprg
```

You can also call it programmatically:

```lua
local panel = require("output-panel")
panel.make()           -- Run makeprg
panel.make("clean")    -- Run with arguments
```

The Make helper uses the "make" profile by default, which you can customize in
your configuration:

```lua
require("output-panel").setup({
  profiles = {
    make = {
      notifications = { title = "Build" },
      auto_hide = { enabled = true },
      -- other config overrides...
    },
  },
})
```

The helper respects your buffer's `makeprg` setting and runs in the buffer's
directory. It supports the `$*` placeholder for arguments just like Neovim's
built-in `:make` command.

#### Optional: Remapping :make to use the panel

The `:Make` command (capital M) is intentionally separate from Neovim's built-in
`:make` to avoid breaking existing workflows. However, if you want `:make` to
use the output panel instead of the quickfix list, you can remap it:

```vim
" Safer command-line abbreviation: typing :make expands to :Make, but only for the standalone command
cnoreabbrev <expr> make getcmdtype() == ':' && getcmdline() == 'make' ? 'Make' : 'make'
```

**Note:** This conditional abbreviation ensures only the standalone `:make` command is remapped.  
The simpler `cnoreabbrev make Make` can cause unexpected behavior if `make` appears in other commands (e.g., `:!make`).

This way you keep your muscle memory but opt into the panel-based workflow.

### Overseer adapter

The Overseer adapter is **opt-in** and works differently from VimTeX and the Make
helper. Instead of automatic event hooks or command wrappers, you explicitly add
the `output_panel` component to tasks you want to stream.

**Default Overseer behavior**: Tasks run normally without the output panel.

**To use the output panel**: Include the `output_panel` component in your task
components:

```lua
require("overseer").setup({
  component_aliases = {
    default = { "default", { "output_panel", open = true } },
  },
})
```

You can also attach it to individual tasks via `components = { "default",
{ "output_panel", focus = false } }` when calling `overseer.run_template()`.

**Control**: Use `profiles.overseer.enabled = false` to disable the component
globally, even if added to tasks.

This opt-in design preserves Overseer's default workflow while making it easy to
route specific tasks to the output panel when desired.

### API helpers

```lua
local panel = require("output-panel")
panel.show()                    -- open panel for the current target
panel.hide()                    -- hide panel
panel.toggle()                  -- toggle visibility
panel.toggle_follow()           -- toggle follow/tail mode
panel.toggle_focus()            -- swap between mini/focus layouts
panel.run({...})                -- run arbitrary commands (see above)
panel.stream({...})             -- create a streaming session for external tools
panel.make(args)                -- run :make with optional arguments
panel.adapter_enabled("name")   -- check if an adapter/profile is enabled
```

#### stream() API

The `stream()` function provides a lower-level interface for external tools, adapters, or custom integrations to feed output into the panel. It returns a session handle with methods for appending output and signaling completion.

**Example: Custom adapter**

```lua
local panel = require("output-panel")

-- Start a streaming session
local session = panel.stream({
  kind = "my_tool",              -- Identifier for this adapter/tool
  title = "My Build",            -- Notification title
  window_title = "Building...",  -- Window title
  profile = "my_profile",        -- Optional profile for config overrides
  config = {},                   -- Optional inline config overrides
  notify_start = true,           -- Show "started" notification
  start = "Build started...",    -- Custom start message
  success = "Build finished",    -- Custom success message
  error = "Build failed",        -- Custom error message
  focus = false,                 -- Open in mini or focus mode
  open = true,                   -- Show panel immediately
})

if session then
  -- Append output as it arrives
  session:append_stdout("Building project...\n")
  session:append_stderr("Warning: deprecated API\n")
  
  -- Signal completion when done
  session:finish({ code = 0 })  -- 0 for success, non-zero for error
end
```

The session handle provides:
- `session:append_stdout(data)` – Add stdout data to the output
- `session:append_stderr(data)` – Add stderr data to the output  
- `session:finish(result)` – Complete the session with exit code and trigger notifications

This is the same API used internally by the Overseer adapter. See the "Writing Custom Adapters" section below for a complete example.

## Writing Custom Adapters

You can write adapters for other tools that generate output: LSP build servers, Neotest runners, custom build systems, formatters, linters, etc.

### Adapter Patterns

There are two main patterns for integrating external tools:

#### Pattern 1: Simple wrapper using `run()`

For tools where you control the command invocation, use `run()` directly:

```lua
-- Example: R Markdown rendering adapter
vim.keymap.set("n", "<leader>rr", function()
  local panel = require("output-panel")
  panel.run({
    cmd = { "Rscript", "-e", "rmarkdown::render('" .. vim.fn.expand("%") .. "')" },
    profile = "rmarkdown",
    title = "R Markdown",
    success = "Document rendered",
    error = "Rendering failed",
  })
end, { desc = "Render R Markdown document" })
```

#### Pattern 2: Event-driven adapter using `stream()`

For tools that have their own lifecycle (build servers, test runners, task systems), use `stream()` to bridge events into the panel:

```lua
-- Example: LSP build server adapter
local function setup_lsp_build_adapter()
  local panel = require("output-panel")
  local session = nil
  
  -- Hook into LSP progress notifications
  vim.api.nvim_create_autocmd("LspProgress", {
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or client.name ~= "rust_analyzer" then
        return
      end
      
      local value = args.data.params.value
      
      if value.kind == "begin" and value.title == "Building" then
        -- Start new streaming session
        session = panel.stream({
          kind = "lsp_build",
          title = "Rust Build",
          window_title = "cargo build",
          profile = "rust",
          notify_start = true,
          start = "Building Rust project...",
          success = "Build successful",
          error = "Build failed",
        })
      elseif session and value.kind == "report" then
        -- Append progress messages
        if value.message then
          session:append_stdout(value.message .. "\n")
        end
      elseif session and value.kind == "end" then
        -- Finish the session
        local code = value.message and value.message:match("error") and 1 or 0
        session:finish({ code = code })
        session = nil
      end
    end,
  })
end
```

### Full Example: Overseer Component Adapter

The built-in Overseer adapter demonstrates a complete integration. Here's how it works:

```lua
-- lua/overseer/component/my_adapter.lua
local panel = require("output-panel")

return {
  desc = "Send task output to output-panel.nvim",
  params = {
    open = { type = "boolean", default = true },
    focus = { type = "boolean", default = false },
    profile = { type = "string", default = "overseer", optional = true },
  },
  constructor = function(params)
    return {
      stream = nil,
      on_start = function(self, task)
        -- Create streaming session when task starts
        self.stream = panel.stream({
          kind = "overseer",
          title = task.name,
          profile = params.profile,
          focus = params.focus,
          open = params.open,
        })
      end,
      on_output = function(self, _, data, stream)
        -- Forward output to panel
        if not self.stream then return end
        if stream == "stderr" then
          self.stream:append_stderr(data)
        else
          self.stream:append_stdout(data)
        end
      end,
      on_complete = function(self, _, status, result)
        -- Finish session with exit code
        if not self.stream then return end
        local code = status == "SUCCESS" and 0 or 1
        self.stream:finish({ code = code })
        self.stream = nil
      end,
    }
  end,
}
```

### Adapter Best Practices

1. **Use profiles** – Define a custom profile for your adapter so users can configure it independently:
   ```lua
   require("output-panel").setup({
     profiles = {
       my_tool = {
         enabled = true,
         notifications = { title = "My Tool" },
         auto_hide = { enabled = false },
       },
     },
   })
   ```

2. **Respect enabled flag** – Check if your adapter is enabled before starting:
   ```lua
   if not panel.adapter_enabled("my_tool") then
     vim.notify("My Tool adapter is disabled", vim.log.levels.WARN)
     return
   end
   ```

3. **Handle session conflicts** – Only one command can stream at a time. `stream()` returns `nil` if another job is active.

4. **Normalize output** – The panel expects strings for `append_stdout/stderr`. Convert tables to newline-separated text if needed.

5. **Set meaningful titles** – Use different `title` (for notifications) and `window_title` (for the panel header) when appropriate.

### Sharing Adapters

If you write an adapter for a popular tool, consider:
- Publishing it as a standalone plugin (e.g., `my-tool-output-panel.nvim`)
- Documenting the required setup in your adapter's README
- Using the same patterns as the built-in adapters for consistency

The core plugin ships only VimTeX, Overseer, and Make support to keep the codebase focused.

## Configuration

`setup()` merges your overrides with the defaults below. Profiles are deep
merged, so you can inherit global values and tweak only what each workflow
needs.

### Configuration Overview

| Section | Description |
|---------|-------------|
| `mini` | Window dimensions for compact mini mode (unfocused overlay) |
| `focus` | Window dimensions for focus mode (interactive, larger window) |
| `auto_open` | Automatically show panel when commands/builds start |
| `auto_hide` | Automatically hide panel after successful builds |
| `notifications` | Notification behavior (titles, persistence for errors) |
| `follow` | Auto-scroll to bottom of output (tail mode) |
| `poll` | How often to refresh output while panel is visible |
| `max_lines` | Maximum buffer lines before trimming old output |
| `open_on_error` | Force panel open when commands fail (even if `open=false`) |
| `notifier` | Custom notification backend (Snacks auto-detected by default) |
| `window_title` | Title shown in the floating window border (defaults to `notifications.title`) |
| `profiles` | Named configuration presets for different tools/workflows |

### Default Configuration

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
    flip_row_offset = 0,
    horizontal_align = 0.55,
    col_offset = 0,
    avoid_cursor = true,
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
    vimtex = {
      enabled = true,
      notifications = { title = "VimTeX" },
      window_title = "VimTeX",
    },
    overseer = {
      enabled = true,
      notifications = { title = "Overseer" },
      window_title = "Overseer",
    },
    make = {
      enabled = true,
      notifications = { title = "Make" },
      window_title = "Make",
      auto_hide = { enabled = true },
    },
  },
})
```

While the mini overlay is visible, the plugin raises `scrolloff` to at least
the panel height plus `scrolloff_margin`, reapplying that padding if you adjust
`scrolloff` manually. Your original `scrolloff` is restored whenever the panel
closes or you enter focus mode.

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
call `run({ profile = "name" })` or when built-in adapters (VimTeX, Overseer, Make) trigger.
Use them to change the window title, notification settings, auto-hide behaviour,
or window layout for a specific workflow without touching other commands.

All profiles (including the built-in adapters `vimtex` and `overseer`, plus the
`make` helper) support an `enabled` field that allows you to temporarily disable
an adapter, helper, or profile without removing its configuration.

**Window Title Configuration:**

The floating window title (shown in the border) is determined by the following precedence:
1. Explicit `window_title` parameter passed to `run()` or `stream()`
2. Profile's `window_title` setting (e.g., `profiles.vimtex.window_title = "VimTeX"`)
3. Profile's `notifications.title` (for backwards compatibility)
4. Global `window_title` setting
5. Global `notifications.title` (defaults to "Output")

This allows each adapter to show its own title (e.g., "VimTeX · Building · 1.2s"
for LaTeX builds, "Make · Done · 0.5s" for make commands) while letting users
override titles per profile or per command.

```lua
require("output-panel").setup({
  profiles = {
    vimtex = {
      enabled = false,  -- Disable VimTeX adapter
    },
    make = {
      enabled = true,   -- Keep Make helper enabled (default)
      notifications = { title = "Build" },
      window_title = "Build",  -- Title shown in float border
    },
    my_custom_profile = {
      enabled = false,  -- Disable custom profile temporarily
      notifications = { title = "Custom Task" },
      window_title = "My Tool",  -- Custom window title
      auto_hide = { enabled = false },
    },
  },
})
```

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
- The mini overlay will flip to the opposite edge if it would hide your cursor.
  Disable this by setting `mini.avoid_cursor = false` if you prefer it to stay put near the start or end of a buffer.
- Tune `mini.flip_row_offset` if you want a different gap when the overlay flips
  to the opposite edge (defaults to no gap when flipped).
- Set `auto_open.enabled = true` to auto-pop the panel whenever VimTeX begins
  compiling.
- Disable `auto_open` inside specific profiles to keep background commands from
  popping the overlay.
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

## VimTeX adapter vs VimTeX stock output

VimTeX already streams compiler logs to splits; the adapter simply adds a
floating overlay and notification layer on top:

| Feature | Panel | VimTeX stock output |
| --- | --- | --- |
| Display | Floating mini/focus overlay | Regular splits |
| Auto-hide | Yes (configurable) | No |
| Visual status | Border colours + notifications | Messages only |
| Buffer type | Scratch, hidden by default | Normal buffer |

Use whichever suits your workflow—the panel adds a custom floating skin on top
of VimTeX's reliable compilation backend while also powering any other command
or task you want to monitor.

## How does this compare to other plugins?

Neovim already offers several ways to run commands asynchronously. The panel
deliberately fills the gap between a full task manager and raw quickfix output.
In particular, [Overseer.nvim](https://github.com/stevearc/overseer.nvim) should
be your first stop whenever you want templated builds, task registries, file
watchers, or an interactive dashboard. Reach for output-panel.nvim when you only
need a single command, VimTeX build, or Overseer task log visible in the
background with minimal setup and no extra UI to manage.

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

See the "Overseer adapter" section in the Usage guide above for complete integration instructions.

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
