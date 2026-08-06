local M = {}

local namespace = vim.api.nvim_create_namespace("patch")

--- @class PatchLocation
--- @field source_buf integer source buffer handle
--- @field namespace integer extmark namespace
--- @field extmark_id integer selection range extmark

--- @class PatchContent
--- @field before string[] lines before the selection
--- @field selected string[] selected lines
--- @field after string[] lines after the selection

--- @class PatchCapture
--- @field location PatchLocation source buffer and selected range
--- @field content PatchContent captured buffer contents

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
--- Normalises the range so that start_line <= end_line.
---
--- @return integer|nil start_line 1-indexed first line of the selection
--- @return integer|nil end_line 1-indexed last line of the selection
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
--- The extmark keeps the selected line range anchored while surrounding lines change.
---
--- @return PatchCapture|nil capture
function M.capture()
  local source_buf = vim.api.nvim_get_current_buf()
  leave_visual_mode()

  local start_line, end_line = get_selection_lines()
  if not start_line then
    return nil
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(
    source_buf,
    namespace,
    start_line - 1,
    0,
    {
      end_row = end_line,
      end_col = 0,
      right_gravity = true,
      end_right_gravity = false,
    }
  )

  return {
    location = {
      source_buf = source_buf,
      namespace = namespace,
      extmark_id = extmark_id,
    },
    content = {
      before = vim.api.nvim_buf_get_lines(source_buf, 0, start_line - 1, false),
      selected = vim.api.nvim_buf_get_lines(source_buf, start_line - 1, end_line, false),
      after = vim.api.nvim_buf_get_lines(source_buf, end_line, -1, false),
    },
  }
end

return M
