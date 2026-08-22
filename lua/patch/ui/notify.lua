local M = {}

local provider = nil

---@param notify_provider function|table|nil
function M.setup(notify_provider)
  provider = notify_provider
end

---@param message string
---@param level integer
---@param opts? table
function M.send(message, level, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    title = "patch.nvim",
    render = "compact",
  })
  local notifier = provider or vim.notify
  notifier(message, level, opts)
end

return M
