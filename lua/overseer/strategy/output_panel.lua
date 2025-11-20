-- output_panel strategy for Overseer
-- Route Overseer task output through output-panel.nvim so users can reuse the
-- floating overlay instead of a terminal buffer.

local log = require("overseer.log")
local panel = require("output-panel")
local normalize_command = require("output-panel.util").normalize_command

---@class overseer.OutputPanelStrategy : overseer.Strategy
---@field handle? number|vim.SystemObj
---@field opts {profile?:string, focus?:boolean, open?:boolean}
local OutputPanelStrategy = {}

---Create a new strategy instance with user overrides merged in.
---@param opts? {profile?:string, focus?:boolean, open?:boolean}
---@return overseer.Strategy
function OutputPanelStrategy.new(opts)
  local strategy = {
    handle = nil,
    opts = opts or {},
  }
  setmetatable(strategy, { __index = OutputPanelStrategy })
  return strategy
end

-- Reset the strategy between runs by stopping any active job handle.
function OutputPanelStrategy:reset()
  self:stop()
end

-- Surface the current output-panel buffer so Overseer can open it from the task list.
function OutputPanelStrategy:get_bufnr()
  if panel.get_buffer then
    return panel.get_buffer()
  end
  return nil
end

---Start an Overseer task inside output-panel's window.
---@param task overseer.Task
function OutputPanelStrategy:start(task)
  local cmd = normalize_command(task.cmd)
  if not cmd then
    log.error("Invalid command for task '%s'", task.name)
    task:on_exit(1)
    return
  end

  -- Merge strategy-local overrides with the panel's Overseer defaults.
  local cfg = (panel.config and panel.config.overseer) or {}
  if cfg.enabled == false then
    cfg = {}
  end
  local focus = self.opts.focus
  if focus == nil then
    focus = cfg.focus
  end
  local open = self.opts.open
  if open == nil then
    open = cfg.open
  end
  if open == nil then
    open = true
  end

  -- Forward every chunk to Overseer subscribers so components still receive live output events.
  local function forward_lines(lines)
    if not lines or vim.tbl_isempty(lines) then
      return
    end
    task:dispatch("on_output", lines)
    task:dispatch("on_output_lines", lines)
  end

  -- Ensure Overseer observes the final status once the output-panel job finishes.
  local function handle_exit(obj)
    self.handle = nil
    if vim.v.exiting ~= vim.NIL then
      return
    end
    task:on_exit(obj.code or 0)
  end

  self.handle = panel.run({
    cmd = cmd,
    cwd = task.cwd,
    env = task.env,
    title = task.name,
    window_title = task.name,
    profile = self.opts.profile or cfg.profile,
    focus = focus,
    open = open,
    notify_start = false,
    on_output = forward_lines,
    on_output_lines = forward_lines,
    on_exit = handle_exit,
  })

  if not self.handle then
    log.error("Failed to start output-panel strategy for task '%s'", task.name)
    task:on_exit(1)
  end
end

-- Stop the running job when Overseer requests a termination.
function OutputPanelStrategy:stop()
  if not self.handle then
    return
  end
  if type(self.handle) == "number" then
    vim.fn.jobstop(self.handle)
  elseif type(self.handle) == "userdata" and self.handle.kill then
    pcall(self.handle.kill, self.handle)
  end
  self.handle = nil
end

-- Dispose resets any lingering handles; output-panel owns the buffer lifecycle.
function OutputPanelStrategy:dispose()
  self:stop()
end

return OutputPanelStrategy
