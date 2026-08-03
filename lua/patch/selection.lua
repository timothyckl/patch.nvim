local M = {}

--- @class PatchCapture
--- @field before string[] lines before the selection
--- @field selected string[] selected lines
--- @field after string[] lines after the selection

--- Exit visual mode and reset the selection highlight.
local function leave_visual_mode()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
    "nx",
    false
  )
end

--- Read the most recent visual selection from the '< and '> marks.
---
--- Normalises the start and end so that first_line <= last_line.
---
--- @return integer|nil first_line 1-indexed first line of the selection
--- @return integer|nil last_line 1-indexed last line of the selection
local function get_selection_lines()
  local _, start_line = unpack(vim.fn.getpos("'<"))
  local _, end_line = unpack(vim.fn.getpos("'>"))

  if start_line == 0 then
    return nil, nil
  end

  return math.min(start_line, end_line), math.max(start_line, end_line)
end

--- Capture the current buffer around its visual selection.
---
--- @return PatchCapture|nil capture
function M.capture()
  local source_buf = vim.api.nvim_get_current_buf()
  leave_visual_mode()

  local first_line, last_line = get_selection_lines()
  if not first_line then
    return nil
  end

  return {
    before = vim.api.nvim_buf_get_lines(source_buf, 0, first_line - 1, false),
    selected = vim.api.nvim_buf_get_lines(source_buf, first_line - 1, last_line, false),
    after = vim.api.nvim_buf_get_lines(source_buf, last_line, -1, false),
  }
end

return M
