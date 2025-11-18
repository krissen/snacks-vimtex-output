-- knit.run - asynchronous runner for knit/compile workflows.
--
-- Provides a light wrapper around vim.system/vim.fn.jobstart so long-running knit,
-- build, or export commands can surface progress through Snacks notifications (or
-- fall back to vim.notify). Commands can be supplied as strings, argument tables,
-- or functions that return either form, and callers may customise success/error
-- labels, timeouts, completion callbacks, and output-panel streaming.

local uv = vim.uv or vim.loop
-- Share helpers with output-panel so command normalisation and notifier detection behave identically.
local util = require("output-panel.util")
local normalize_cmd = util.normalize_command
local resolve_notifier = util.resolve_notifier

local M = {}

local function format_duration(duration)
  if not duration then
    return ""
  end
  return string.format(" (%.1fs)", duration)
end

local function format_output(output)
  if not output or output == "" then
    return nil
  end
  return output
end

-- Execute the command while surfacing only notifications (no panel streaming).
local function run_without_panel(opts, command, title)
  local notify = resolve_notifier()
  local started = uv and uv.hrtime and uv.hrtime() or nil
  local function duration_suffix()
    if not started or not uv or not uv.hrtime then
      return ""
    end
    local elapsed = (uv.hrtime() - started) / 1e9
    return format_duration(elapsed)
  end

  local notify_opts = { title = title }
  if opts.notify_start ~= false then
    local start_message = opts.start or opts.start_message or (title .. " started…")
    notify.info(start_message, notify_opts)
  end

  local function handle_result(obj)
    local success_timeout = opts.success_timeout
      or (obj.code == 0 and (duration_suffix() ~= "" and 9000 or 4500) or 4500)
    local error_timeout = opts.error_timeout or math.ceil(success_timeout * 1.5)
    if obj.code == 0 then
      notify_opts.timeout = success_timeout
      if opts.show_output then
        notify_opts.body = format_output(obj.stdout)
      end
      notify.info((opts.success or "Job complete") .. duration_suffix(), notify_opts)
    else
      notify_opts.timeout = error_timeout
      local body = format_output(obj.stderr) or format_output(obj.stdout)
      notify_opts.body = opts.show_output and body or nil
      notify.error((opts.error or "Job failed") .. duration_suffix(), notify_opts)
    end
    if opts.on_exit then
      opts.on_exit(obj)
    end
  end

  if type(vim.system) == "function" then
    local ok, handle = pcall(vim.system, command, {
      text = true,
      cwd = opts.cwd,
      env = opts.env,
    }, function(obj)
      vim.schedule(function()
        handle_result(obj)
      end)
    end)
    if not ok then
      notify.error(handle or "vim.system failed", notify_opts)
    end
    return
  end

  -- Fallback for Neovim <0.10: capture stdout/stderr manually via jobstart
  local stdout, stderr = {}, {}
  local function append(target, data)
    if not data then
      return
    end
    for _, chunk in ipairs(data) do
      if chunk ~= "" then
        table.insert(target, chunk)
      end
    end
  end
  local jobid = vim.fn.jobstart(command, {
    cwd = opts.cwd,
    env = opts.env,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      append(stdout, data)
    end,
    on_stderr = function(_, data)
      append(stderr, data)
    end,
    on_exit = function(_, code)
      handle_result({
        code = code,
        stdout = table.concat(stdout, "\n"),
        stderr = table.concat(stderr, "\n"),
      })
    end,
  })
  if jobid <= 0 then
    notify.error("jobstart failed to run command", notify_opts)
  end
end

---Run an external command asynchronously. Set opts.output_panel/opts.live_output to true
---to stream output via output-panel.nvim. When unset, only notifications fire.
---@param opts {cmd:string|string[]|fun():string|string[], title?:string, success?:string, error?:string, cwd?:string, env?:table<string,string>, show_output?:boolean, success_timeout?:number, error_timeout?:number, on_exit?:fun(obj:vim.SystemCompleted), output_panel?:boolean, live_output?:boolean, profile?:string, panel?:table, notify_start?:boolean, focus?:boolean}
-- Public entrypoint; optionally streams via output-panel when requested.
function M.run(opts)
  opts = opts or {}
  if not opts.cmd then
    vim.notify("knit.run requires a cmd option", vim.log.levels.ERROR)
    return
  end
  local command = normalize_cmd(opts.cmd)
  if not command then
    vim.notify(
      "knit.run requires cmd to be a string, table or function returning a command",
      vim.log.levels.ERROR
    )
    return
  end
  local title = opts.title or "knit.run"
  local wants_panel = opts.output_panel or opts.live_output
  if wants_panel then
    local ok, panel = pcall(require, "output-panel")
    if ok and panel and panel.run then
      local panel_opts = vim.tbl_deep_extend("force", {
        cmd = command,
        title = title,
        success = opts.success,
        error = opts.error,
        cwd = opts.cwd,
        env = opts.env,
        on_exit = opts.on_exit,
        profile = opts.profile or "knit",
        notify_start = opts.notify_start,
        focus = opts.focus,
        open = opts.open,
      }, opts.panel or {})
      panel.run(panel_opts)
      return
    end
  end
  run_without_panel(opts, command, title)
end

return M

-- vim:ts=2 sw=2 et
