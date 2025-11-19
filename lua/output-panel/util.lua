-- output-panel.util
-- Shared helper utilities reused across output-panel.nvim modules.

local M = {}

-- Normalize user-supplied commands into a vim.fn.jobstart/vim.system friendly table.
-- Accepts strings, tables, or functions returning either and wraps shell execution on demand.
function M.normalize_command(cmd)
  if type(cmd) == "function" then
    cmd = cmd()
  end
  if type(cmd) == "string" then
    if vim.fn.has("win32") == 1 then
      cmd = { "cmd.exe", "/c", cmd }
    else
      cmd = { "sh", "-c", cmd }
    end
  end
  if type(cmd) ~= "table" then
    return nil
  end
  return cmd
end

-- Resolve snacks.notify when installed and fall back to vim.notify while keeping
-- a consistent info/warn/error interface for callers.
function M.resolve_notifier()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.notify and snacks.notifier then
    return {
      backend = "snacks",
      info = function(msg, opts)
        return snacks.notify.info(msg, opts)
      end,
      warn = function(msg, opts)
        return snacks.notify.warn(msg, opts)
      end,
      error = function(msg, opts)
        return snacks.notify.error(msg, opts)
      end,
      hide = function(handle)
        local token = handle
        if type(token) == "table" then
          token = token.id or token.handle or token
        end
        snacks.notifier.hide(token)
      end,
    }
  end

  return {
    backend = "vim",
    info = function(msg, opts)
      return vim.notify(msg, vim.log.levels.INFO, opts)
    end,
    warn = function(msg, opts)
      return vim.notify(msg, vim.log.levels.WARN, opts)
    end,
    error = function(msg, opts)
      return vim.notify(msg, vim.log.levels.ERROR, opts)
    end,
  }
end

return M
