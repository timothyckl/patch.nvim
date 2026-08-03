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

--- Format a named capture group for display.
---
--- @param name
--- @param lines string[] captured lines
--- @return string formatted_group
local function format_capture_group(name, lines)
  local contents = #lines > 0 and table.concat(lines, "\n") or "(empty)"
  return string.format("--- %s ---\n%s", name, contents)
end

--- Capture the current buffer around its visual selection and print each group.
function M.capture_selection()
  local source_buf = vim.api.nvim_get_current_buf()
  leave_visual_mode()

  local first_line, last_line = get_selection_lines()
  if not first_line then
    print("patch: no visual selection found")
    return
  end

  local capture = {
    before = vim.api.nvim_buf_get_lines(source_buf, 0, first_line - 1, false),
    selected = vim.api.nvim_buf_get_lines(source_buf, first_line - 1, last_line, false),
    after = vim.api.nvim_buf_get_lines(source_buf, last_line, -1, false)
  }

  print(table.concat({
    format_capture_group("BEFORE", capture.before),
    format_capture_group("SELECTED", capture.selected),
    format_capture_group("AFTER", capture.after),
  }, "\n"))end

return M
