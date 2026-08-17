local M = {}

local namespace = vim.api.nvim_create_namespace("patch")

--- @class PatchLocation
--- @field source_buf integer source buffer handle
--- @field extmark_id integer selection range extmark

--- @class PatchRange
--- @field source_buf integer source buffer handle
--- @field start_row integer 0-indexed first row of the selection
--- @field end_row integer 0-indexed exclusive end row of the selection

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

--- Track the current buffer's visual selection.
---
--- The extmark keeps the selected line range anchored while surrounding lines change.
---
--- @return PatchLocation|nil location
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
    source_buf = source_buf,
    extmark_id = extmark_id,
  }
end

--- Resolve the current line range of a tracked selection.
---
--- @param location PatchLocation
--- @return PatchRange|nil range
function M.resolve(location)
  if not vim.api.nvim_buf_is_valid(location.source_buf) then
    return nil
  end

  local position = vim.api.nvim_buf_get_extmark_by_id(
    location.source_buf,
    namespace,
    location.extmark_id,
    { details = true }
  )

  if #position == 0 or not position[3] or position[3].end_row == nil then
    return nil
  end

  return {
    source_buf = location.source_buf,
    start_row = position[1],
    end_row = position[3].end_row,
  }
end

--- Update a tracked selection's extmark decoration while preserving its range.
---
--- @param location PatchLocation
--- @param decoration? table
--- @return boolean updated
function M.decorate(location, decoration)
  local range = M.resolve(location)
  if not range then
    return false
  end

  local options = vim.tbl_extend("force", {
    id = location.extmark_id,
    end_row = range.end_row,
    end_col = 0,
    right_gravity = true,
    end_right_gravity = false,
  }, decoration or {})

  vim.api.nvim_buf_set_extmark(
    location.source_buf,
    namespace,
    range.start_row,
    0,
    options
  )

  return true
end

--- Remove a tracked selection.
---
--- @param location PatchLocation
function M.clear(location)
  if vim.api.nvim_buf_is_valid(location.source_buf) then
    vim.api.nvim_buf_del_extmark(
      location.source_buf,
      namespace,
      location.extmark_id
    )
  end
end

return M
