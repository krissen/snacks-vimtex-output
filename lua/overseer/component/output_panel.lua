-- overseer/component/output_panel
-- Stream Overseer task output through output-panel.nvim so toggles and overlays
-- stay in sync with ad-hoc command runs.

local constants = require("overseer.constants")
local panel = require("output-panel")

return {
  desc = "Send task output to output-panel.nvim",
  params = {
    open = {
      desc = "Show the panel when the task starts",
      type = "boolean",
      default = true,
    },
    focus = {
      desc = "Open the panel in focus mode instead of mini mode",
      type = "boolean",
      default = false,
    },
    profile = {
      desc = "Profile name to apply when streaming this task",
      type = "string",
      default = "overseer",
      optional = true,
    },
    config = {
      desc = "Configuration overrides applied only for this task",
      type = "table",
      optional = true,
    },
    title = {
      desc = "Override the notification/panel title",
      type = "string",
      optional = true,
    },
    window_title = {
      desc = "Custom window title shown in the floating border",
      type = "string",
      optional = true,
    },
    success = {
      desc = "Success notification label",
      type = "string",
      default = "Task finished",
      optional = true,
    },
    error = {
      desc = "Failure notification label",
      type = "string",
      default = "Task failed",
      optional = true,
    },
    start_message = {
      desc = "Notification to show when the task launches",
      type = "string",
      optional = true,
    },
    notify_start = {
      desc = "Show start notifications when true",
      type = "boolean",
      default = true,
    },
    border_hl = {
      desc = "Custom border highlight group",
      type = "string",
      optional = true,
    },
  },
  constructor = function(params)
    return {
      stream = nil,
      on_reset = function(self, _)
        -- Clear any stale stream handles when a task restarts.
        self.stream = nil
      end,
      on_start = function(self, task)
        -- Check if the overseer adapter is enabled before streaming
        if not panel.adapter_enabled("overseer") then
          vim.notify(
            "output-panel.nvim: Overseer adapter is disabled. Enable it with profiles.overseer.enabled = true",
            vim.log.levels.WARN
          )
          return
        end

        -- Begin streaming when Overseer launches the task. Respect panel
        -- profiles/config overrides so users can tailor the view per task.
        self.stream = panel.stream({
          kind = "overseer",
          title = params.title or task.name or "Overseer task",
          window_title = params.window_title or task.name,
          profile = params.profile,
          config = params.config,
          notify_start = params.notify_start,
          start = params.start_message,
          success = params.success,
          error = params.error,
          focus = params.focus,
          open = params.open,
          border_hl = params.border_hl,
        })
        if not self.stream then
          vim.notify(
            "output-panel.nvim could not attach to the Overseer task (another job is active?)",
            vim.log.levels.WARN
          )
        end
      end,
      on_output = function(self, _, data, stream)
        -- Mirror incremental output into the panel buffer.
        if not self.stream then
          return
        end
        if stream == "stderr" then
          self.stream:append_stderr(data)
        else
          self.stream:append_stdout(data)
        end
      end,
      on_output_lines = function(self, task, lines, stream)
        -- Ensure multi-line batches from Overseer land in the same buffer.
        self:on_output(task, lines, stream)
      end,
      on_complete = function(self, _, status, result)
        -- Finalize the session so notifications and border colors reflect exit status.
        -- Overseer reports string statuses; translate to an exit code so the panel UI
        -- can color the border and emit notifications accurately.
        if not self.stream then
          return
        end

        local exit_code
        if status == constants.STATUS.SUCCESS then
          exit_code = 0
        elseif type(result) == "table" and type(result.exit_code) == "number" then
          exit_code = result.exit_code
        else
          exit_code = 1
        end

        self.stream:finish({ code = exit_code })
        self.stream = nil
      end,
      on_dispose = function(self, _)
        -- Drop references when Overseer frees the component instance.
        self.stream = nil
      end,
    }
  end,
}
