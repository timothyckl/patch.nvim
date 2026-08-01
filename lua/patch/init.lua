local M = {}

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
--- @return integer|nil first_line  1-indexed first line of the selection
--- @return integer|nil last_line   1-indexed last line of the selection
local function get_selection_lines()
  local _, start_line = unpack(vim.fn.getpos("'<"))
  local _, end_line = unpack(vim.fn.getpos("'>"))

  if start_line == 0 then
    return nil, nil
  end

  return math.min(start_line, end_line), math.max(start_line, end_line)
end

--- Create a listed scratch buffer containing the given lines.
---
--- @param lines string[] lines to write into the buffer
local function write_scratch_buffer(lines)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

--- Capture the current visual selection into a scratch buffer and print it.
function M.capture_selection()
  leave_visual_mode()

  local first_line, last_line = get_selection_lines()
  if not first_line then
    print("patch: no visual selection found")
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)

  write_scratch_buffer(lines)

  print(table.concat(lines, "\n"))
end

return M
