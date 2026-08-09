local M = {}

local namespace = vim.api.nvim_create_namespace("patch-replacement")

--- Convert model output into lines accepted by nvim_buf_set_lines.
---
--- A terminal newline belongs to the textual response, not a new buffer line.
---
--- @param response string
--- @return string[] lines
local function to_lines(response)
  local stripped = response:gsub("\r?\n$", "")

  if stripped == "" then
    return {}
  end

  return vim.split(stripped, "\n", { plain = true })
end

--- Resolve the current line range of a tracked selection.
---
--- @param location PatchLocation
--- @return table range
local function resolve_range(location)
  local position = vim.api.nvim_buf_get_extmark_by_id(
    location.source_buf,
    location.namespace,
    location.extmark_id,
    { details = true }
  )

  return {
    start_row = position[1],
    end_row = position[3].end_row,
  }
end

--- Resolve a tracked selection and replace its current line range.
---
--- @param location PatchLocation
--- @param response string
function M.apply(location, response)
  local range = resolve_range(location)
  local lines = to_lines(response)

  vim.api.nvim_buf_set_lines(
    location.source_buf,
    range.end_row,
    range.end_row,
    true,
    lines
  )

  vim.api.nvim_buf_set_extmark(
    location.source_buf,
    location.namespace,
    range.start_row,
    0,
    {
      id = location.extmark_id,
      end_row = range.end_row,
      end_col = 0,
      right_gravity = true,
      end_right_gravity = false,
      hl_group = "DiffDelete",
      hl_eol = true,
    }
  )

  if #lines > 0 then
    vim.api.nvim_buf_set_extmark(
      location.source_buf,
      namespace,
      range.end_row,
      0,
      {
        end_row = range.end_row + #lines,
        end_col = 0,
        hl_group = "DiffAdd",
        hl_eol = true,
      }
    )
  end
end

return M
