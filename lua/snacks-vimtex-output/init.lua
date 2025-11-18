-- lua/plugin_configs/vimtex_output.lua
-- Render VimTeX compiler output in an unfocusable floating window
-- and surface build status through Snacks notifications.

local M = {}

local uv = vim.uv or vim.loop

local config = {
	-- Dimensions for the unfocused mini overlay
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
	-- Dimensions for the focused/interactive overlay
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
	-- Extra cursor padding so the overlay never hides the cursor
	scrolloff_margin = 5,
	-- Retry logic for auto-opening when the log file is recreated lazily
	auto_open = {
		retries = 6,
		delay = 150,
	},
}

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
	prev_win = nil,
	border_hl = "FloatBorder",
	scrolloff_restore = nil,
	render_retry_token = 0,
	last_close_reason = nil,
}

local function notifier()
	if state.notify then
		return state.notify
	end
	local notify = {
		info = function(msg, opts)
			vim.notify(msg, vim.log.levels.INFO, opts)
		end,
		warn = function(msg, opts)
			vim.notify(msg, vim.log.levels.WARN, opts)
		end,
		error = function(msg, opts)
			vim.notify(msg, vim.log.levels.ERROR, opts)
		end,
	}
	local ok, snacks = pcall(require, "snacks")
	if ok and snacks.notify then
		notify.info = function(msg, opts)
			snacks.notify.info(msg, opts)
		end
		notify.warn = function(msg, opts)
			snacks.notify.warn(msg, opts)
		end
		notify.error = function(msg, opts)
			snacks.notify.error(msg, opts)
		end
	end
	state.notify = notify
	return notify
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
	local uv = vim.uv or vim.loop
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
	running = "Bygger",
	success = "Klar",
	failure = "Fel",
}

local function status_title()
	local label = status_labels[state.status]
	local elapsed = elapsed_seconds()
	if label and elapsed then
		return string.format("VimTeX · %s · %.1fs", label, elapsed)
	elseif label then
		return string.format("VimTeX · %s", label)
	end
	return "VimTeX"
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

local function close_window(opts)
	opts = opts or {}
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.focused = false
	state.status = state.status ~= "running" and state.status or "idle"
	state.render_retry_token = state.render_retry_token + 1
	state.last_close_reason = opts.reason
	if state.scrolloff_restore ~= nil then
		vim.o.scrolloff = state.scrolloff_restore
		state.scrolloff_restore = nil
	end
	restore_previous_window()
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

local function schedule_hide(delay)
	state.hide_token = state.hide_token + 1
	local token = state.hide_token
	vim.defer_fn(function()
		if state.hide_token == token and not state.focused then
			close_window({ reason = "auto_success" })
		end
	end, delay or 2000)
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

local function ensure_output_buffer()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		return state.buf
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "vimtexoutput", { buf = buf })
	state.buf = buf
	return buf
end

local function scroll_to_bottom()
	if state.focused or not state.win or not vim.api.nvim_win_is_valid(state.win) then
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
	local mod = vim.api.nvim_get_option_value("modifiable", { buf = buf })
	if not mod then
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modified", false, { buf = buf })
	if not mod then
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end
	state.last_stat = stat
	scroll_to_bottom()
	return true
end

local function start_polling()
	if state.timer or not uv then
		return
	end
	local timer = uv.new_timer()
	state.timer = timer
	timer:start(0, 250, function()
		vim.schedule(function()
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
			notifier().warn("VimTeX saknar känt output-spår", { title = "VimTeX" })
		end
		return nil
	end
	local buf = ensure_output_buffer()
	if not buf then
		return nil
	end
	update_buffer_from_file(true)
	if opts.poll then
		start_polling()
	end
	return buf
end

local function window_dimensions(focused)
	local layout = focused and config.focus or config.mini
	local cols = vim.o.columns
	local lines = vim.o.lines

	local width = math.floor(cols * (layout.width_scale or 0.75))
	width = clamp(width, layout.width_min or 40, layout.width_max or cols)

	local height = math.floor(lines * (layout.height_ratio or 0.3))
	height = clamp(height, layout.height_min or 6, layout.height_max or math.max(2, lines - 2))

	local align = clamp(layout.horizontal_align or 0.5, 0, 1)
	local col = math.floor((cols - width) * align + (layout.col_offset or 0))
	col = clamp(col, 0, math.max(0, cols - width))

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

local function apply_cursor_guard(height, focused)
	if focused then
		if state.scrolloff_restore ~= nil then
			vim.o.scrolloff = state.scrolloff_restore
			state.scrolloff_restore = nil
		end
		return
	end
	local margin = config.scrolloff_margin or 1
	local needed = math.max(0, height + margin)
	if needed == 0 then
		return
	end
	if state.scrolloff_restore == nil then
		state.scrolloff_restore = vim.o.scrolloff
	end
	if vim.o.scrolloff < needed then
		vim.o.scrolloff = needed
	end
end

local function render_window(opts)
	opts = opts or {}
	local buf = ensure_output_ready({
		target = opts.target,
		source_buf = opts.source_buf,
		poll = opts.poll,
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
	local config = {
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

	local border_hl = opts.border_hl or state.border_hl or "FloatBorder"
	state.border_hl = border_hl

	local win_exists = state.win and vim.api.nvim_win_is_valid(state.win)
	if win_exists then
		vim.api.nvim_win_set_buf(state.win, buf)
		vim.api.nvim_win_set_config(state.win, config)
	else
		local open_config = vim.deepcopy(config)
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
	state.last_close_reason = nil
	return state.win
end

function M.show()
	state.hide_token = state.hide_token + 1
	state.render_retry_token = state.render_retry_token + 1
	render_window({ source_buf = vim.api.nvim_get_current_buf(), focus = false })
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

function M.toggle_focus()
	state.hide_token = state.hide_token + 1
	state.render_retry_token = state.render_retry_token + 1
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		render_window({ source_buf = vim.api.nvim_get_current_buf(), focus = false })
		return
	end
	render_window({ focus = not state.focused })
end

local function render_with_retry(opts)
	opts = opts or {}
	local attempts = opts.retry_count or 0
	local delay = opts.retry_delay or 100
	local render_opts = vim.deepcopy(opts)
	render_opts.retry_count = nil
	render_opts.retry_delay = nil
	if render_window(render_opts) then
		return
	end
	if attempts <= 0 then
		return
	end
	state.render_retry_token = state.render_retry_token + 1
	local token = state.render_retry_token
	local function retry(remaining)
		if remaining <= 0 then
			return
		end
		vim.defer_fn(function()
			if state.render_retry_token ~= token or state.status ~= "running" then
				return
			end
			if render_window(render_opts) then
				state.render_retry_token = state.render_retry_token + 1
				return
			end
			retry(remaining - 1)
		end, delay)
	end
	retry(attempts)
end

local function format_duration()
	return format_duration_suffix()
end

local function event_context(event)
	local buf = event and event.buf and event.buf ~= 0 and event.buf or nil
	local target = compiler_output_path(buf)
	if target then
		set_target(target)
	end
	return { target = target or state.target, source_buf = buf }
end

local function on_compile_started(event)
	local ctx = event_context(event)
	state.started_at = current_time()
	state.elapsed = nil
	state.status = "running"
	state.border_hl = "FloatBorder"
	state.hide_token = state.hide_token + 1
	render_with_retry({
		target = ctx.target,
		source_buf = ctx.source_buf,
		poll = true,
		focus = state.focused,
		quiet = true,
		retry_count = (config.auto_open and config.auto_open.retries) or 0,
		retry_delay = (config.auto_open and config.auto_open.delay) or 120,
	})
	notifier().info("Bygger LaTeX…", { title = "VimTeX" })
end

local function on_compile_succeeded(event)
	local ctx = event_context(event)
	local elapsed = elapsed_seconds()
	state.elapsed = elapsed
	state.started_at = nil
	state.status = "success"
	stop_polling()
	render_window({
		border_hl = "DiagnosticOk",
		target = ctx.target,
		source_buf = ctx.source_buf,
		focus = state.focused,
	})
	notifier().info("LaTeX-bygget klart" .. format_duration(), { title = "VimTeX" })
	schedule_hide(3000)
end

local function on_compile_failed(event)
	local ctx = event_context(event)
	local elapsed = elapsed_seconds()
	state.elapsed = elapsed
	state.started_at = nil
	state.status = "failure"
	stop_polling()
	state.hide_token = state.hide_token + 1
	render_window({
		border_hl = "DiagnosticError",
		target = ctx.target,
		source_buf = ctx.source_buf,
		focus = state.focused,
	})
	notifier().error("LaTeX-bygget misslyckades" .. format_duration(), {
		title = "VimTeX",
		timeout = false,
		keep = true,
	})
end

local function on_compile_stopped()
	local was_running = state.status == "running"
	state.status = was_running and "idle" or state.status
	state.started_at = nil
	state.elapsed = was_running and nil or state.elapsed
	stop_polling()
	if was_running or state.win then
		close_window({ reason = "stopped" })
	else
		refresh_window_title()
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("vimtex_output_float", { clear = true })
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

	vim.api.nvim_create_user_command("VimtexOutputShow", function()
		M.show()
	end, {})
	vim.api.nvim_create_user_command("VimtexOutputHide", function()
		M.hide()
	end, {})
	vim.api.nvim_create_user_command("VimtexOutputToggle", function()
		M.toggle()
	end, {})
	vim.api.nvim_create_user_command("VimtexOutputToggleFocus", function()
		M.toggle_focus()
	end, {})
end

return M

-- vim: ts=2 sts=2 sw=2 et
