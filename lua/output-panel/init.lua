-- output-panel
-- Stream VimTeX compiler output and arbitrary shell commands inside a floating overlay with notification feedback.

local M = {}

local uv = vim.uv or vim.loop
-- Shared helpers provide consistent command normalization and notifier detection across modules.
local util = require("output-panel.util")
local normalize_command = util.normalize_command

local default_config = {
  -- Dimensions for the unfocused mini overlay
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
  -- Dimensions for the focused/interactive overlay
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
  -- Extra cursor padding so the overlay never hides the cursor
  scrolloff_margin = 5,
  -- Retry logic for auto-opening when the log file is recreated lazily
  auto_open = {
    enabled = false,
    retries = 6,
    delay = 150,
  },
  -- Automatically hide the floating window after a successful build
  auto_hide = {
    enabled = true,
    delay = 3000,
  },
  -- Notification configuration and override hook
  notifications = {
    enabled = true,
    title = "VimTeX",
    persist_failure = true,
  },
  notifier = nil,
  border_highlight = "FloatBorder",
  follow = {
    enabled = true,
  },
  max_lines = 4000,
  open_on_error = true,
  profiles = {},
}

local config = vim.deepcopy(default_config)
M.config = config

local function assign_config(new_config)
  for key in pairs(config) do
    config[key] = nil
  end
  for key, value in pairs(new_config) do
    config[key] = value
  end
end

local state = {
  win = nil,
  buf = nil,
  hide_token = 0,
  started_at = nil,
  elapsed = nil,
  target = nil,
  timer = nil,
  last_stat = nil,
  status = "idle",
  focused = false,
  follow = true,
  prev_win = nil,
  border_hl = config.border_highlight,
  scrolloff_restore = nil,
  render_retry_token = 0,
  last_close_reason = nil,
  augroup = nil,
  notify = nil,
  failure_notification = nil,
  running_notified = false,
  active_config = nil,
  job = nil,
}

local function current_config()
  return state.active_config or config
end

local function set_active_config(overrides)
  if overrides and next(overrides) ~= nil then
    state.active_config = vim.tbl_deep_extend("force", vim.deepcopy(config), overrides)
  else
    state.active_config = nil
  end
  state.notify = nil
end

local function command_job_active()
  return state.job and state.job.kind == "command" and state.job.active ~= false
end

local function open_log_file(path)
  local target = path or (vim.fn.tempname() .. ".log")
  local ok, handle = pcall(io.open, target, "w+")
  if not ok or not handle then
    return nil, nil
  end
  handle:write("")
  handle:flush()
  return target, handle
end

local function append_log(handle, chunk)
  if not handle or not chunk or chunk == "" then
    return
  end
  handle:write(chunk)
  handle:flush()
end

local function auto_open_enabled()
  local cfg = current_config()
  if not cfg.auto_open then
    return false
  end
  return cfg.auto_open.enabled == true
end

-- Lazy-load and cache the notification backend (custom, snacks.nvim, or vim.notify fallback).
-- The notifier abstraction allows users to provide their own notification functions while
-- automatically detecting and using snacks.nvim when available, falling back to vim.notify otherwise.
local function notifier()
  if state.notify then
    return state.notify
  end
  local cfg = current_config()
  -- Use custom notifier if provided in config
  if cfg.notifier then
    state.notify = cfg.notifier
    return state.notify
  end
  -- Fallback to the shared helper so snacks/vim.notify auto-detection stays in sync with knit.run
  state.notify = util.resolve_notifier()
  return state.notify
end

-- Send a notification at the specified level (info/warn/error) with optional config overrides.
-- Respects config.notifications.enabled and automatically adds title if not provided.
local function notify(level, msg, opts)
  local cfg = current_config()
  local notifications = cfg.notifications or {}
  if notifications.enabled == false then
    return
  end
  opts = opts or {}
  if not opts.title then
    opts.title = notifications.title or "VimTeX"
  end
  local handler = notifier()[level]
  if handler then
    local ok, result = pcall(handler, msg, opts)
    if ok then
      return result
    end
  end
  return nil
end

local function clamp(value, min_value, max_value)
  if min_value then
    value = math.max(min_value, value)
  end
  if max_value and max_value > 0 then
    value = math.min(max_value, value)
  end
  return value
end

local function current_time()
  if uv and uv.hrtime then
    return uv.hrtime()
  end
  return nil
end

local function elapsed_seconds()
  if state.status == "running" and state.started_at then
    local now = current_time()
    if now then
      return math.max(0, (now - state.started_at) / 1e9)
    end
  end
  return state.elapsed
end

local function format_duration_suffix()
  local elapsed = elapsed_seconds()
  if not elapsed then
    return ""
  end
  return string.format(" (%.1fs)", elapsed)
end

local status_labels = {
  running = "Building",
  success = "Done",
  failure = "Error",
}

local function status_title()
  local label = status_labels[state.status]
  local elapsed = elapsed_seconds()
  local base
  if state.job and state.job.window_title then
    base = state.job.window_title
  else
    local cfg = current_config()
    local notifications = cfg.notifications or {}
    base = notifications.title or "Output"
  end
  if label and elapsed then
    return string.format("%s · %s · %.1fs", base, label, elapsed)
  elseif label then
    return string.format("%s · %s", base, label)
  end
  return base
end

local function refresh_window_title()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_config, state.win, { title = status_title() })
  end
end

local function restore_previous_window()
  local target = state.prev_win
  state.prev_win = nil
  if target and vim.api.nvim_win_is_valid(target) then
    pcall(vim.api.nvim_set_current_win, target)
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= state.win then
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      if ok and cfg.relative == "" then
        pcall(vim.api.nvim_set_current_win, win)
        return
      end
    end
  end
end

local function stop_polling()
  if state.timer then
    state.timer:stop()
    if state.timer.close then
      state.timer:close()
    end
    state.timer = nil
  end
end

local function close_window(opts)
  opts = opts or {}
  stop_polling()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.focused = false
  state.render_retry_token = state.render_retry_token + 1
  state.last_close_reason = opts.reason
  if state.scrolloff_restore ~= nil then
    vim.o.scrolloff = state.scrolloff_restore
    state.scrolloff_restore = nil
  end
  restore_previous_window()
end

local function schedule_hide(delay)
  local cfg = current_config()
  if not cfg.auto_hide or cfg.auto_hide.enabled == false then
    return
  end
  state.hide_token = state.hide_token + 1
  local token = state.hide_token
  local hide_delay = delay or cfg.auto_hide.delay or 2000
  vim.defer_fn(function()
    if state.hide_token == token and not state.focused then
      close_window({ reason = "auto_success" })
    end
  end, hide_delay)
end

local function normalized_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

local function compiler_output_path(bufnr)
  local vt
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local ok, buf_vt = pcall(vim.api.nvim_buf_get_var, bufnr, "vimtex")
    if ok then
      vt = buf_vt
    end
  end
  vt = vt or vim.b.vimtex
  if not vt or not vt.compiler or not vt.compiler.output then
    return nil
  end
  return normalized_path(vt.compiler.output)
end

local function set_target(path)
  local normalized = normalized_path(path)
  if not normalized then
    return nil
  end
  if state.target ~= normalized then
    state.target = normalized
    state.last_stat = nil
  end
  return normalized
end

local function resolve_target(path, source_buf)
  local normalized = set_target(path)
  if normalized then
    return normalized
  end
  local from_source = compiler_output_path(source_buf)
  if from_source then
    return set_target(from_source)
  end
  if state.target then
    return state.target
  end
  local current = compiler_output_path()
  if current then
    return set_target(current)
  end
  return nil
end

-- Ensure a reusable scratch buffer exists so the panel can reopen previous output on demand.
local function ensure_output_buffer()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  -- Hide the buffer when unfocused instead of wiping so users can manually revisit output later.
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "vimtexoutput", { buf = buf })
  state.buf = buf
  return buf
end

-- Apply a callback to the scratch buffer while safely toggling the modifiable flag.
local function apply_to_buffer(buf, cb)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or type(cb) ~= "function" then
    return
  end
  local function run()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = buf })
    if not was_modifiable then
      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    end
    local ok, err = pcall(cb, buf)
    if not ok then
      vim.schedule(function()
        notify("error", string.format("output-panel buffer update failed: %s", err))
      end)
    end
    if not was_modifiable and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_set_option_value("modified", false, { buf = buf })
    end
  end
  if vim.in_fast_event() then
    vim.schedule(run)
  else
    run()
  end
end

-- Replace the entire buffer with a new set of lines (within apply_to_buffer safeguards).
local function replace_buffer_lines(buf, lines)
  apply_to_buffer(buf, function(target)
    vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
  end)
end

-- Trim the newest lines to keep the buffer below the configured max line count.
local function clamp_lines(lines)
  local cfg = current_config()
  local limit = cfg.max_lines
  if not limit or limit <= 0 or not lines then
    return lines
  end
  if #lines <= limit then
    return lines
  end
  local start = #lines - limit + 1
  local trimmed = {}
  for i = start, #lines do
    trimmed[#trimmed + 1] = lines[i]
  end
  return trimmed
end

-- Determine whether follow/tail mode should be enabled by default.
local function follow_default()
  local cfg = current_config()
  local follow_cfg = cfg.follow or {}
  return follow_cfg.enabled ~= false
end

-- Update follow mode, defaulting to the configured preference when value is nil.
local function set_follow(value)
  if value == nil then
    state.follow = follow_default()
  else
    state.follow = value and true or false
  end
end

local function scroll_to_bottom()
  if
    not state.follow
    or state.focused
    or not state.win
    or not vim.api.nvim_win_is_valid(state.win)
  then
    return
  end
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  if line_count == 0 then
    return
  end
  pcall(vim.api.nvim_win_set_cursor, state.win, { line_count, 0 })
end

local function update_buffer_from_file(force)
  local target = state.target
  if not target then
    return false
  end
  local buf = ensure_output_buffer()
  if not buf then
    return false
  end
  local stat = uv and target and uv.fs_stat(target) or nil
  if not stat then
    return false
  end
  local changed = force
    or not state.last_stat
    or stat.mtime.sec ~= state.last_stat.mtime.sec
    or stat.mtime.nsec ~= state.last_stat.mtime.nsec
    or stat.size ~= state.last_stat.size
  if not changed then
    return true
  end
  local ok, lines = pcall(vim.fn.readfile, target)
  if not ok then
    return false
  end
  if #lines == 0 then
    lines = { "" }
  end
  lines = clamp_lines(lines)
  replace_buffer_lines(buf, lines)
  state.last_stat = stat
  scroll_to_bottom()
  return true
end

-- Keep a lightweight polling loop running while the overlay is visible so the
-- buffer stays in sync with latexmk's stdout and the title timer keeps
-- updating. The timer exits automatically when the floating window disappears
-- (either because the user hid it or VimTeX stopped the build) and spins up
-- again the next time `render_window` requests live updates.
local function start_polling()
  if state.timer or not uv then
    return
  end
  local timer = uv.new_timer()
  state.timer = timer
  timer:start(0, 250, function()
    vim.schedule(function()
      local win_open = state.win and vim.api.nvim_win_is_valid(state.win)
      if not win_open then
        stop_polling()
        return
      end
      if not state.target then
        stop_polling()
        return
      end
      local buf = ensure_output_buffer()
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        stop_polling()
        return
      end
      update_buffer_from_file(false)
      refresh_window_title()
    end)
  end)
end

local function ensure_output_ready(opts)
  opts = opts or {}
  local target = resolve_target(opts.target, opts.source_buf)
  if not target then
    if not opts.quiet then
      notify("warn", "VimTeX does not expose a compiler output log")
    end
    return nil
  end
  local buf = ensure_output_buffer()
  if not buf then
    return nil
  end
  update_buffer_from_file(true)
  return buf
end

-- Calculate window dimensions and position based on current terminal size and layout config.
-- @param focused boolean: true for focus mode (large interactive window), false for mini mode (compact overlay)
-- @return width, height, row, col: dimensions and position for nvim_open_win
local function window_dimensions(focused)
  local cfg = current_config()
  local layout = focused and cfg.focus or cfg.mini
  local cols = vim.o.columns
  local lines = vim.o.lines

  -- Calculate width as a percentage of terminal width, then clamp to min/max bounds
  local width = math.floor(cols * (layout.width_scale or 0.75))
  width = clamp(width, layout.width_min or 40, layout.width_max or cols)

  -- Calculate height as a percentage of terminal height, then clamp to min/max bounds
  local height = math.floor(lines * (layout.height_ratio or 0.3))
  height = clamp(height, layout.height_min or 6, layout.height_max or math.max(2, lines - 2))

  -- Horizontal positioning: align is a 0-1 value where 0=left, 0.5=center, 1=right
  -- Then apply col_offset as a fine-tuning adjustment
  local align = clamp(layout.horizontal_align or 0.5, 0, 1)
  local col = math.floor((cols - width) * align + (layout.col_offset or 0))
  col = clamp(col, 0, math.max(0, cols - width))

  -- Vertical positioning: anchor determines where row_offset is measured from
  -- top: offset from top edge; center: offset from vertical center; bottom: offset from bottom edge
  local anchor = layout.row_anchor or "bottom"
  local row_offset = layout.row_offset or 0
  local row
  if anchor == "top" then
    row = row_offset
  elseif anchor == "center" then
    row = math.floor((lines - height) / 2) + row_offset
  else
    row = lines - height - row_offset
  end
  row = clamp(row, 0, math.max(0, lines - height))

  return width, height, row, col
end

-- Temporarily increase scrolloff in mini mode to prevent the overlay from covering the cursor.
-- In focus mode, the user controls cursor position, so we restore the original scrolloff.
-- This ensures the cursor always has enough padding when typing while the mini overlay is visible.
local function apply_cursor_guard(height, focused)
  if focused then
    -- Restore original scrolloff when entering focus mode
    if state.scrolloff_restore ~= nil then
      vim.o.scrolloff = state.scrolloff_restore
      state.scrolloff_restore = nil
    end
    return
  end
  -- In mini mode, ensure scrolloff is large enough to keep cursor visible above the overlay
  local cfg = current_config()
  local margin = cfg.scrolloff_margin or 1
  local needed = math.max(0, height + margin)
  if needed == 0 then
    return
  end
  -- Save original scrolloff only once (when first showing mini overlay)
  if state.scrolloff_restore == nil then
    state.scrolloff_restore = vim.o.scrolloff
  end
  -- Increase scrolloff if current value is too small
  if vim.o.scrolloff < needed then
    vim.o.scrolloff = needed
  end
end

local function render_window(opts)
  opts = opts or {}
  local should_poll = opts.poll
  if should_poll == nil then
    should_poll = state.status == "running"
  end
  local buf = ensure_output_ready({
    target = opts.target,
    source_buf = opts.source_buf,
    quiet = opts.quiet,
  })
  if not buf then
    return nil
  end

  local desired_focus = opts.focus
  if desired_focus == nil then
    desired_focus = state.focused
  end

  local entering_focus = desired_focus and not state.focused
  local leaving_focus = state.focused and not desired_focus

  if entering_focus then
    local current = vim.api.nvim_get_current_win()
    if current ~= state.win then
      state.prev_win = current
    end
  end

  local width, height, row, col = window_dimensions(desired_focus)
  local win_config = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    focusable = desired_focus,
    style = "minimal",
    title = opts.title or status_title(),
  }

  local border_hl = opts.border_hl
    or state.border_hl
    or current_config().border_highlight
    or "FloatBorder"
  state.border_hl = border_hl

  local win_exists = state.win and vim.api.nvim_win_is_valid(state.win)
  if win_exists then
    vim.api.nvim_win_set_buf(state.win, buf)
    vim.api.nvim_win_set_config(state.win, win_config)
  else
    if opts.follow ~= nil then
      set_follow(opts.follow)
    else
      set_follow(nil)
    end
    local open_config = vim.deepcopy(win_config)
    open_config.noautocmd = true
    state.win = vim.api.nvim_open_win(buf, desired_focus, open_config)
  end

  vim.api.nvim_set_option_value("wrap", false, { win = state.win })
  vim.api.nvim_set_option_value("cursorline", desired_focus, { win = state.win })
  vim.api.nvim_set_option_value(
    "winhl",
    string.format("Normal:NormalFloat,FloatBorder:%s", border_hl),
    { win = state.win }
  )

  if desired_focus then
    if vim.api.nvim_get_current_win() ~= state.win then
      vim.api.nvim_set_current_win(state.win)
    end
  elseif leaving_focus then
    restore_previous_window()
  end

  apply_cursor_guard(height, desired_focus)
  state.focused = desired_focus
  refresh_window_title()
  if not desired_focus then
    scroll_to_bottom()
  end
  if should_poll then
    start_polling()
  end
  state.last_close_reason = nil
  return state.win
end

-- Attempt to render the window with retry logic to handle race conditions.
-- VimTeX sometimes recreates the log file during compilation startup, causing the initial
-- render to fail because the file doesn't exist yet. This function retries after a delay.
-- Uses token-based cancellation to abort retries if the window is closed or compilation stops.
local function render_with_retry(opts)
  opts = opts or {}
  local attempts = opts.retry_count or 0
  local delay = opts.retry_delay or 100
  -- Strip retry parameters before passing to render_window
  local render_opts = vim.deepcopy(opts)
  render_opts.retry_count = nil
  render_opts.retry_delay = nil
  -- Try rendering immediately first
  if render_window(render_opts) then
    return
  end
  -- If no retries configured or render succeeded, we're done
  if attempts <= 0 then
    return
  end
  -- Increment token to cancel any previous retry loops
  state.render_retry_token = state.render_retry_token + 1
  local token = state.render_retry_token
  -- Recursive retry function with token-based cancellation
  local function retry(remaining)
    if remaining <= 0 then
      return
    end
    vim.defer_fn(function()
      -- Abort if token changed (window closed) or compilation stopped
      if state.render_retry_token ~= token or state.status ~= "running" then
        return
      end
      if render_window(render_opts) then
        -- Success! Invalidate this retry chain
        state.render_retry_token = state.render_retry_token + 1
        return
      end
      -- Still failing, try again
      retry(remaining - 1)
    end, delay)
  end
  retry(attempts)
end

local function open_overlay(opts)
  opts = opts or {}
  if opts.focus == nil then
    opts.focus = false
  end
  if opts.follow ~= nil then
    set_follow(opts.follow)
  else
    set_follow(nil)
  end
  opts.source_buf = opts.source_buf or vim.api.nvim_get_current_buf()
  if state.status == "running" then
    opts.poll = true
    local cfg = current_config()
    opts.retry_count = opts.retry_count or (cfg.auto_open and cfg.auto_open.retries) or 0
    opts.retry_delay = opts.retry_delay or (cfg.auto_open and cfg.auto_open.delay) or 120
    render_with_retry(opts)
  else
    render_window(opts)
  end
end

function M.show()
  state.hide_token = state.hide_token + 1
  state.render_retry_token = state.render_retry_token + 1
  open_overlay()
end

function M.hide()
  state.hide_token = state.hide_token + 1
  close_window({ reason = "manual" })
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.hide()
  else
    M.show()
  end
end

-- Toggle follow/tail mode so users can inspect earlier lines without auto-scroll.
function M.toggle_follow()
  state.follow = not state.follow
  if state.follow then
    scroll_to_bottom()
  end
  notify("info", string.format("Output follow %s", state.follow and "enabled" or "disabled"))
end

function M.toggle_focus()
  state.hide_token = state.hide_token + 1
  state.render_retry_token = state.render_retry_token + 1
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    open_overlay()
    return
  end
  render_window({ focus = not state.focused })
end

---Run an arbitrary shell command and stream its output into the panel.
---@param opts {cmd:string|string[]|fun():string|string[], title?:string, window_title?:string, profile?:string, config?:table, cwd?:string, env?:table<string,string>, focus?:boolean, open?:boolean, success?:string, error?:string, start?:string, start_message?:string, notify_start?:boolean, log_path?:string, border_hl?:string, on_exit?:fun(obj:vim.SystemCompleted)}
function M.run(opts)
  opts = opts or {}
  if not opts.cmd then
    notify("error", "output-panel.run() requires a cmd option")
    return
  end
  if command_job_active() then
    notify("warn", "Another command is already running. Showing its output instead.")
    return
  end

  local command = normalize_command(opts.cmd)
  if not command then
    notify("error", "cmd must be a string, list, or function returning a command")
    return
  end

  -- Build per-run config overrides from global profiles + explicit overrides.
  set_active_config(nil)
  local overrides
  local base_profiles = config.profiles or {}
  if opts.profile and base_profiles[opts.profile] then
    overrides = vim.deepcopy(base_profiles[opts.profile])
  end
  if opts.config then
    if overrides then
      overrides = vim.tbl_deep_extend("force", overrides, opts.config)
    else
      overrides = vim.deepcopy(opts.config)
    end
  end
  if overrides then
    set_active_config(overrides)
  end

  local job_title
  if type(command) == "table" then
    job_title = opts.title or table.concat(command, " ")
  else
    job_title = opts.title or tostring(command)
  end
  local window_title = opts.window_title or job_title

  local log_path, handle = open_log_file(opts.log_path)
  if not log_path or not handle then
    notify("error", "Unable to create a log file for command output")
    set_active_config(nil)
    return
  end

  local stdout_chunks, stderr_chunks = {}, {}

  stop_polling()
  set_target(log_path)
  state.job = {
    kind = "command",
    active = true,
    title = job_title,
    window_title = window_title,
    log_path = log_path,
    log_handle = handle,
    profile = opts.profile,
  }
  state.status = "running"
  state.started_at = current_time()
  state.elapsed = nil
  state.border_hl = opts.border_hl or (current_config().border_highlight or "FloatBorder")
  state.running_notified = true
  state.hide_token = state.hide_token + 1
  state.render_retry_token = state.render_retry_token + 1

  local open_panel = opts.open ~= false
  if open_panel then
    render_window({ target = log_path, poll = true, focus = opts.focus, title = window_title })
  else
    ensure_output_ready({ target = log_path, quiet = true })
    start_polling()
  end

  if opts.notify_start ~= false then
    local start_message = opts.start or opts.start_message or (job_title .. " started…")
    notify("info", start_message)
  end

  -- Append a chunk to both the on-disk log and an in-memory accumulator for notifications.
  local function stream_chunk(target, chunk)
    if not chunk or chunk == "" then
      return
    end
    append_log(handle, chunk)
    state.last_stat = nil
    target[#target + 1] = chunk
  end

  -- Wrap vim.system callbacks so stdout/stderr share the same chunk bookkeeping.
  local function make_system_handler(target)
    return function(err, data)
      if err and err ~= "" then
        stream_chunk(stderr_chunks, err)
      end
      if data and data ~= "" then
        stream_chunk(target, data)
      end
    end
  end

  -- Convert jobstart line tables into newline-delimited text before streaming.
  local function handle_job_data(target, data)
    if type(data) ~= "table" then
      return
    end
    local parts = {}
    for _, line in ipairs(data) do
      if line and line ~= "" then
        parts[#parts + 1] = line
      end
    end
    if #parts == 0 then
      return
    end
    stream_chunk(target, table.concat(parts, "\n") .. "\n")
  end

  local function finalize_job(obj)
    if state.job and state.job.log_handle then
      pcall(state.job.log_handle.flush, state.job.log_handle)
      pcall(state.job.log_handle.close, state.job.log_handle)
      state.job.log_handle = nil
    end
    local elapsed = elapsed_seconds()
    state.elapsed = elapsed
    state.started_at = nil
    state.job = state.job or {}
    state.job.active = false
    state.running_notified = false
    stop_polling()
    local cfg = current_config()
    local window_exists = state.win and vim.api.nvim_win_is_valid(state.win)
    if obj.code == 0 then
      state.status = "success"
      state.border_hl = "DiagnosticOk"
      if open_panel or window_exists then
        render_window({ target = log_path, focus = state.focused, border_hl = state.border_hl })
      end
      if window_exists then
        schedule_hide(cfg.auto_hide and cfg.auto_hide.delay)
      end
      notify("info", (opts.success or (job_title .. " finished")) .. format_duration_suffix())
      state.failure_notification = nil
    else
      state.status = "failure"
      state.border_hl = "DiagnosticError"
      state.hide_token = state.hide_token + 1
      if open_panel or window_exists or cfg.open_on_error ~= false then
        render_window({ target = log_path, focus = state.focused, border_hl = state.border_hl })
      end
      local failure_opts = { replace = state.failure_notification }
      local notifications = cfg.notifications or {}
      if notifications.persist_failure ~= false then
        failure_opts.timeout = false
        failure_opts.keep = true
      end
      local failure_message = opts.error or (job_title .. " failed")
      state.failure_notification =
        notify("error", failure_message .. format_duration_suffix(), failure_opts)
    end
    if opts.on_exit then
      opts.on_exit(obj)
    end
    set_active_config(nil)
  end

  local use_system = type(vim.system) == "function"
  if use_system then
    local ok, handle_or_err = pcall(vim.system, command, {
      cwd = opts.cwd,
      env = opts.env,
      stdout = make_system_handler(stdout_chunks),
      stderr = make_system_handler(stderr_chunks),
    }, function(obj)
      obj.stdout = table.concat(stdout_chunks)
      obj.stderr = table.concat(stderr_chunks)
      vim.schedule(function()
        finalize_job(obj)
      end)
    end)

    if not ok then
      stream_chunk(stderr_chunks, "Failed to start command: " .. tostring(handle_or_err))
      finalize_job({
        code = -1,
        stdout = table.concat(stdout_chunks),
        stderr = table.concat(stderr_chunks),
      })
      return
    end

    state.job.handle = handle_or_err
    return handle_or_err
  end

  local jobid = vim.fn.jobstart(command, {
    cwd = opts.cwd,
    env = opts.env,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      handle_job_data(stdout_chunks, data)
    end,
    on_stderr = function(_, data)
      handle_job_data(stderr_chunks, data)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        finalize_job({
          code = code,
          signal = 0,
          stdout = table.concat(stdout_chunks),
          stderr = table.concat(stderr_chunks),
        })
      end)
    end,
  })
  if jobid <= 0 then
    notify("error", "Failed to start command with jobstart()")
    finalize_job({
      code = 1,
      signal = 0,
      stdout = table.concat(stdout_chunks),
      stderr = table.concat(stderr_chunks),
    })
    return
  end

  state.job.handle = jobid
  return jobid
end

-- Extract VimTeX event context to determine which buffer and log file to track.
-- VimTeX events include a buffer reference; we use it to find the compiler output path.
local function event_context(event)
  local buf = event and event.buf and event.buf ~= 0 and event.buf or nil
  local target = compiler_output_path(buf)
  if target then
    set_target(target)
  end
  return { target = target or state.target, source_buf = buf }
end

-- Handle VimTeX compilation start events (VimtexEventCompiling, VimtexEventCompileStarted).
-- Transitions state to "running", starts the timer if needed, and shows the overlay if configured.
local function on_compile_started(event)
  if command_job_active() then
    return
  end
  state.job = nil
  local cfg = current_config()
  local ctx = event_context(event)
  local already_running = state.status == "running"
  -- Only reset timer on the first compile event (not subsequent recompiles)
  if not already_running then
    state.started_at = current_time()
    state.elapsed = nil
  end
  state.status = "running"
  state.border_hl = cfg.border_highlight or "FloatBorder"
  state.hide_token = state.hide_token + 1 -- Cancel any pending auto-hide
  local window_exists = state.win and vim.api.nvim_win_is_valid(state.win)
  -- Show overlay if auto-open is enabled OR if the user already opened it manually
  if auto_open_enabled() or window_exists then
    render_with_retry({
      target = ctx.target,
      source_buf = ctx.source_buf,
      poll = true,
      focus = state.focused,
      quiet = true,
      retry_count = (cfg.auto_open and cfg.auto_open.retries) or 0,
      retry_delay = (cfg.auto_open and cfg.auto_open.delay) or 120,
    })
  end
  if not state.running_notified then
    notify("info", "LaTeX build started…")
    state.running_notified = true
  end
end

-- Handle VimTeX compilation success event (VimtexEventCompileSuccess).
-- Stops polling, transitions to "success" state, updates border to green, and schedules auto-hide.
-- Replaces any previous failure notification with a success message.
local function on_compile_succeeded(event)
  if command_job_active() then
    return
  end
  local cfg = current_config()
  local ctx = event_context(event)
  local elapsed = elapsed_seconds()
  state.elapsed = elapsed
  state.started_at = nil
  state.status = "success"
  state.running_notified = false
  stop_polling()
  local window_exists = state.win and vim.api.nvim_win_is_valid(state.win)
  if auto_open_enabled() or window_exists then
    render_window({
      border_hl = "DiagnosticOk", -- Green border for success
      target = ctx.target,
      source_buf = ctx.source_buf,
      focus = state.focused,
    })
    schedule_hide(cfg.auto_hide and cfg.auto_hide.delay)
  end
  -- Replace previous failure notification if one exists
  local notify_opts
  if state.failure_notification then
    notify_opts = { replace = state.failure_notification }
  end
  notify("info", "LaTeX build finished" .. format_duration_suffix(), notify_opts)
  state.failure_notification = nil
end

-- Handle VimTeX compilation failure event (VimtexEventCompileFailed).
-- Stops polling, transitions to "failure" state, updates border to red, and shows persistent notification.
-- The overlay stays visible (auto-hide is cancelled) so the user can inspect the error log.
local function on_compile_failed(event)
  if command_job_active() then
    return
  end
  local cfg = current_config()
  local ctx = event_context(event)
  local elapsed = elapsed_seconds()
  state.elapsed = elapsed
  state.started_at = nil
  state.status = "failure"
  state.running_notified = false
  stop_polling()
  state.hide_token = state.hide_token + 1 -- Cancel any pending auto-hide
  local window_exists = state.win and vim.api.nvim_win_is_valid(state.win)
  if auto_open_enabled() or window_exists or cfg.open_on_error ~= false then
    render_window({
      border_hl = "DiagnosticError", -- Red border for failure
      target = ctx.target,
      source_buf = ctx.source_buf,
      focus = state.focused,
    })
  end
  -- Show persistent failure notification (if configured) so it stays visible until next success
  local notifications = cfg.notifications or {}
  local failure_opts = {
    replace = state.failure_notification,
  }
  if notifications.persist_failure ~= false then
    failure_opts.timeout = false -- Don't auto-dismiss
    failure_opts.keep = true -- Keep in notification history
  end
  state.failure_notification =
    notify("error", "LaTeX build failed" .. format_duration_suffix(), failure_opts)
end

local function on_compile_stopped()
  if command_job_active() then
    return
  end
  local was_running = state.status == "running"
  state.status = was_running and "idle" or state.status
  state.started_at = nil
  state.elapsed = was_running and nil or state.elapsed
  state.running_notified = false
  stop_polling()
  if was_running or state.win then
    close_window({ reason = "stopped" })
  else
    refresh_window_title()
  end
end

local function setup_autocmds()
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end
  local group = vim.api.nvim_create_augroup("snacks_vimtex_output", { clear = true })
  state.augroup = group
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompiling",
    callback = on_compile_started,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompileStarted",
    callback = on_compile_started,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompileSuccess",
    callback = on_compile_succeeded,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompileFailed",
    callback = on_compile_failed,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "VimtexEventCompileStopped",
    callback = on_compile_stopped,
  })
end

local function setup_commands()
  local commands = {
    VimtexOutputShow = M.show,
    VimtexOutputHide = M.hide,
    VimtexOutputToggle = M.toggle,
    VimtexOutputToggleFocus = M.toggle_focus,
    VimtexOutputToggleFollow = M.toggle_follow,
  }
  for name in pairs(commands) do
    pcall(vim.api.nvim_del_user_command, name)
  end
  for name, fn in pairs(commands) do
    vim.api.nvim_create_user_command(name, function()
      fn()
    end, {})
  end
end

function M.setup(opts)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts or {})
  assign_config(merged)
  set_active_config(nil)
  state.border_hl = current_config().border_highlight or "FloatBorder"
  state.failure_notification = nil
  state.running_notified = false
  setup_autocmds()
  setup_commands()
  return config
end

return M

-- vim: ts=2 sts=2 sw=2 et
