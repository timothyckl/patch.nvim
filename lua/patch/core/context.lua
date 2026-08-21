local M = {}

local selection = require("patch.core.selection")

--- @class PatchContent
--- @field before string[] lines before the selection
--- @field selected string[] selected lines
--- @field after string[] lines after the selection

--- Capture the current buffer contents around a tracked selection.
---
--- @param location PatchLocation
--- @return PatchContent|nil content
function M.capture(location)
  local range = selection.resolve(location)
  if not range then
    return nil
  end

  return {
    before = vim.api.nvim_buf_get_lines(range.source_buf, 0, range.start_row, false),
    selected = vim.api.nvim_buf_get_lines(range.source_buf, range.start_row, range.end_row, false),
    after = vim.api.nvim_buf_get_lines(range.source_buf, range.end_row, -1, false),
  }
end

return M
