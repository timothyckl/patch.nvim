local M = {}

local namespace = vim.api.nvim_create_namespace("patch-replacement")

---@class PatchProposal
---@field location PatchLocation
---@field generated_mark integer|nil
---@field actions_mark integer|nil
---@field status "pending"|"retrying"|"finished"

--- Convert model output into lines accepted by nvim_buf_set_lines.
---
--- A terminal newline belongs to the textual response, not a new buffer line.
---
---@param response string
---@return string[] lines
local function to_lines(response)
  local stripped = response:gsub("\r?\n$", "")

  if stripped == "" then
    return {}
  end

  return vim.split(stripped, "\n", { plain = true })
end

--- Resolve the current line range of a tracked selection.
---
---@param location PatchLocation
---@return table|nil range
local function resolve_range(location)
  if not vim.api.nvim_buf_is_valid(location.source_buf) then
    return nil
  end

  local position = vim.api.nvim_buf_get_extmark_by_id(
    location.source_buf,
    location.namespace,
    location.extmark_id,
    { details = true }
  )

  if #position == 0 or not position[3] or position[3].end_row == nil then
    return nil
  end

  return {
    start_row = position[1],
    end_row = position[3].end_row,
  }
end

--- Resolve the current generated line range of a proposal.
---
---@param proposal PatchProposal
---@return table|nil range
local function resolve_generated_range(proposal)
  if not proposal.generated_mark then
    return nil
  end

  local source_buf = proposal.location.source_buf
  if not vim.api.nvim_buf_is_valid(source_buf) then
    return nil
  end

  local position = vim.api.nvim_buf_get_extmark_by_id(
    source_buf,
    namespace,
    proposal.generated_mark,
    { details = true }
  )

  if #position == 0 or not position[3] or position[3].end_row == nil then
    return nil
  end

  return {
    start_row = position[1],
    end_row = position[3].end_row,
  }
end

---@param proposal PatchProposal
local function delete_preview_marks(proposal)
  local source_buf = proposal.location.source_buf
  if not vim.api.nvim_buf_is_valid(source_buf) then
    return
  end

  if proposal.generated_mark then
    vim.api.nvim_buf_del_extmark(source_buf, namespace, proposal.generated_mark)
    proposal.generated_mark = nil
  end

  if proposal.actions_mark then
    vim.api.nvim_buf_del_extmark(source_buf, namespace, proposal.actions_mark)
    proposal.actions_mark = nil
  end
end

--- Create the generated-range and action-line extmarks for a proposal.
---
---@param proposal PatchProposal
---@param generated_start integer
---@param original_end integer
---@param line_count integer
local function create_preview_marks(proposal, generated_start, original_end, line_count)
  local source_buf = proposal.location.source_buf

  if line_count > 0 then
    proposal.generated_mark = vim.api.nvim_buf_set_extmark(
      source_buf,
      namespace,
      generated_start,
      0,
      {
        end_row = generated_start + line_count,
        end_col = 0,
        hl_group = "DiffAdd",
        hl_eol = true,
      }
    )
  end

  local actions_row = line_count > 0
      and generated_start + line_count - 1
    or math.max(original_end - 1, 0)

  proposal.actions_mark = vim.api.nvim_buf_set_extmark(
    source_buf,
    namespace,
    actions_row,
    0,
    { virt_lines = { { { "[a] Accept   [r] Reject   [R] Retry", "Comment" } } } }
  )
end

--- Insert a generated replacement after a tracked selection.
---
---@param location PatchLocation
---@param response string
---@return PatchProposal|nil proposal
function M.apply(location, response)
  local range = resolve_range(location)
  if not range then
    return nil
  end

  local lines = to_lines(response)

  vim.api.nvim_buf_set_lines(
    location.source_buf,
    range.end_row,
    range.end_row,
    false,
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

  local proposal = {
    location = location,
    generated_mark = nil,
    actions_mark = nil,
    status = "pending",
  }

  create_preview_marks(proposal, range.end_row, range.end_row, #lines)
  return proposal
end

--- Replace a proposal's generated span with a new response.
---
---@param proposal PatchProposal
---@param response string
---@return PatchProposal|nil proposal
---@return string|nil error_message
function M.update(proposal, response)
  local original_range = resolve_range(proposal.location)
  if not original_range then
    return nil, "patch: original selection no longer exists"
  end

  local generated_range = resolve_generated_range(proposal)
  if proposal.generated_mark and not generated_range then
    return nil, "patch: generated replacement no longer exists"
  end

  generated_range = generated_range or {
    start_row = original_range.end_row,
    end_row = original_range.end_row,
  }

  local lines = to_lines(response)
  delete_preview_marks(proposal)

  vim.api.nvim_buf_set_lines(
    proposal.location.source_buf,
    generated_range.start_row,
    generated_range.end_row,
    false,
    lines
  )

  create_preview_marks(
    proposal,
    generated_range.start_row,
    original_range.end_row,
    #lines
  )

  return proposal
end

--- Accept a proposal by removing the original selected lines.
---
---@param proposal PatchProposal
---@return boolean accepted
function M.accept(proposal)
  if proposal.status ~= "pending" then
    return false
  end

  local range = resolve_range(proposal.location)
  if not range then
    return false
  end

  proposal.status = "finished"
  delete_preview_marks(proposal)
  vim.api.nvim_buf_del_extmark(
    proposal.location.source_buf,
    proposal.location.namespace,
    proposal.location.extmark_id
  )

  vim.api.nvim_buf_set_lines(
    proposal.location.source_buf,
    range.start_row,
    range.end_row,
    false,
    {}
  )

  return true
end

--- Reject a proposal by removing its generated lines.
---
---@param proposal PatchProposal
---@return boolean rejected
function M.reject(proposal)
  if proposal.status ~= "pending" then
    return false
  end

  local generated_range = resolve_generated_range(proposal)
  if proposal.generated_mark and not generated_range then
    return false
  end

  local source_buf = proposal.location.source_buf
  if not vim.api.nvim_buf_is_valid(source_buf) then
    return false
  end

  proposal.status = "finished"
  delete_preview_marks(proposal)
  vim.api.nvim_buf_del_extmark(
    source_buf,
    proposal.location.namespace,
    proposal.location.extmark_id
  )

  if generated_range then
    vim.api.nvim_buf_set_lines(
      source_buf,
      generated_range.start_row,
      generated_range.end_row,
      false,
      {}
    )
  end

  return true
end

--- Request another response and update a proposal in place.
---
---@param proposal PatchProposal
---@param client table client exposing request(message, on_complete)
---@param message string original prompt message
---@return boolean started
function M.retry(proposal, client, message)
  if proposal.status ~= "pending" then
    return false
  end

  proposal.status = "retrying"

  client.request(message, function(res, err)
    if proposal.status ~= "retrying" then
      return
    end

    if err then
      proposal.status = "pending"
      return
    end

    local updated, update_error = M.update(proposal, res)
    proposal.status = "pending"

    if not updated then
      vim.notify(tostring(update_error), vim.log.levels.ERROR)
    end
  end)

  return true
end

return M
