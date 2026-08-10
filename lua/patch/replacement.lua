local M = {}

local namespace = vim.api.nvim_create_namespace("patch-replacement")

---@class PatchProposal
---@field location PatchLocation
---@field generated_mark integer|nil
---@field actions_mark integer
---@field status "pending"|"retrying"|"finished"

--- Convert model output into lines accepted by nvim_buf_set_lines.
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

--- TODO: Map actions to options
--- TODO: Document this function 
--- Resolve a tracked selection and replace its current line range.
---
--- @param location PatchLocation
--- @param response string
--- @return PatchProposal
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

  local patch_mark

  if #lines > 0 then
    patch_mark = vim.api.nvim_buf_set_extmark(
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

  local options_mark = vim.api.nvim_buf_set_extmark(
    location.source_buf,
    namespace,
    range.end_row + #lines - 1,
    0,
    {
      virt_lines = {
        {
          { "[a] Accept   [r] Reject   [R] Retry", "Comment" },
        },
      },
    }
  )

  return {
    location = location,
    generated_mark = patch_mark,
    actions_mark = options_mark,
    status = "pending"
  }
end

function M.accept(proposal)
  if proposal.status ~= "pending" then
    return
  end

  local location = proposal.location
  local source_buf = location.source_buf
  local range = resolve_range(location)

  -- remove original selected lines. replacement will take over.
  vim.api.nvim_buf_set_lines(
    source_buf,
    range.start_row,
    range.end_row,
    false,
    {}
  )

  -- clear "patch" namespace
  vim.api.nvim_buf_clear_namespace(
    source_buf,
    location.namespace,
    range.start_row,
    range.end_row
  )

  -- delete extmark tracking selected lines in "patch" namespace
  vim.api.nvim_buf_del_extmark(
    source_buf,
    location.namespace,
    location.extmark_id
  )

  -- clear generated replacement and action prompt extmarks
  if proposal.generated_mark then
    vim.api.nvim_buf_del_extmark(
      source_buf,
      namespace,
      proposal.generated_mark
    )
  end

  -- remove action prompt extmark
  vim.api.nvim_buf_del_extmark(
    source_buf,
    namespace,
    proposal.actions_mark
  )

  proposal.status = "finished"
end

function M.reject(proposal)
  if proposal.status ~= "pending" then
    return
  end

  -- ...

  proposal.status = "finished"
end

function M.retry(proposal)
  if proposal.status ~= "pending" then
    return
  end

  -- ...

  proposal.status = "retrying"
end

return M
