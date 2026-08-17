local M = {}
local selection = require("patch.selection")

local namespace = vim.api.nvim_create_namespace("patch-replacement")
local previews = {}

---@class PatchProposal
---@field location PatchLocation
---@field generated_mark integer|nil
---@field generated_lines string[]
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

---@param proposal PatchProposal
---@return boolean rendered
local function render_preview(proposal)
  local range = selection.resolve(proposal.location)
  if not range then
    return false
  end

  local source_buf = range.source_buf
  if not selection.decorate(proposal.location, {
    hl_group = "DiffDelete",
    hl_eol = true,
  }) then
    return false
  end

  if #proposal.generated_lines == 0 then
    if proposal.generated_mark then
      vim.api.nvim_buf_del_extmark(source_buf, namespace, proposal.generated_mark)
      proposal.generated_mark = nil
    end

    return true
  end

  -- Neovim clips the highlighted padding at each window edge, matching hl_eol.
  local padding = string.rep(" ", vim.o.columns)
  local virtual_lines = {}

  for index, line in ipairs(proposal.generated_lines) do
    virtual_lines[index] = {
      { line, "DiffAdd" },
      { padding, "DiffAdd" },
    }
  end

  local options = {
    right_gravity = true,
    virt_lines = virtual_lines,
  }

  if proposal.generated_mark then
    options.id = proposal.generated_mark
  end

  proposal.generated_mark = vim.api.nvim_buf_set_extmark(
    source_buf,
    namespace,
    math.max(range.end_row - 1, 0),
    0,
    options
  )

  return true
end

local group = vim.api.nvim_create_augroup("patch-replacement", { clear = true })
vim.api.nvim_create_autocmd("VimResized", {
  group = group,
  callback = function()
    for _, proposal in pairs(previews) do
      if proposal.status == "pending" then
        render_preview(proposal)
      end
    end
  end,
})

--- Remove a proposal's decorations while retaining its tracked selection.
---
---@param proposal PatchProposal
---@return boolean hidden
local function hide_preview(proposal)
  local range = selection.resolve(proposal.location)
  if not range then
    return false
  end

  local source_buf = range.source_buf

  if proposal.generated_mark then
    vim.api.nvim_buf_del_extmark(source_buf, namespace, proposal.generated_mark)
    proposal.generated_mark = nil
  end

  if not selection.decorate(proposal.location) then
    return false
  end

  proposal.generated_lines = {}
  return true
end

---@param proposal PatchProposal
local function clear_preview(proposal)
  local source_buf = proposal.location.source_buf

  if previews[source_buf] == proposal then
    previews[source_buf] = nil
  end

  if vim.api.nvim_buf_is_valid(source_buf) then
    if proposal.generated_mark then
      vim.api.nvim_buf_del_extmark(source_buf, namespace, proposal.generated_mark)
      proposal.generated_mark = nil
    end

    selection.clear(proposal.location)
  end
end

--- Preview a generated replacement after a tracked selection.
---
---@param location PatchLocation
---@param response string
---@return PatchProposal|nil proposal
function M.apply(location, response)
  local range = selection.resolve(location)
  if not range then
    return nil
  end

  local proposal = {
    location = location,
    generated_mark = nil,
    generated_lines = to_lines(response),
    status = "pending",
  }

  previews[location.source_buf] = proposal
  if not render_preview(proposal) then
    previews[location.source_buf] = nil
    return nil
  end

  return proposal
end

--- Replace a proposal's generated preview with a new response.
---
---@param proposal PatchProposal
---@param response string
---@return PatchProposal|nil proposal
---@return string|nil error_message
function M.update(proposal, response)
  local original_range = selection.resolve(proposal.location)
  if not original_range then
    return nil, "original selection no longer exists"
  end

  proposal.generated_lines = to_lines(response)
  if not render_preview(proposal) then
    return nil, "original selection no longer exists"
  end

  return proposal
end

--- Accept a proposal by replacing the original selected lines.
---
---@param proposal PatchProposal
---@return boolean accepted
function M.accept(proposal)
  if proposal.status ~= "pending" then
    return false
  end

  local range = selection.resolve(proposal.location)
  if not range then
    return false
  end

  local source_buf = proposal.location.source_buf
  proposal.status = "finished"
  clear_preview(proposal)

  vim.api.nvim_buf_set_lines(
    source_buf,
    range.start_row,
    range.end_row,
    false,
    proposal.generated_lines
  )

  return true
end

--- Reject a proposal by removing its preview.
---
---@param proposal PatchProposal
---@return boolean rejected
function M.reject(proposal)
  if proposal.status ~= "pending" then
    return false
  end

  local source_buf = proposal.location.source_buf
  if not vim.api.nvim_buf_is_valid(source_buf) then
    return false
  end

  proposal.status = "finished"
  clear_preview(proposal)
  return true
end

--- Hide a proposal while another response is requested.
---
---@param proposal PatchProposal
---@return boolean started
function M.begin_retry(proposal)
  if proposal.status ~= "pending" then
    return false
  end

  if not hide_preview(proposal) then
    return false
  end

  proposal.status = "retrying"
  return true
end

--- Render a successful retry response.
---
---@param proposal PatchProposal
---@param response string
---@return PatchProposal|nil proposal
---@return string|nil error_message
function M.complete_retry(proposal, response)
  if proposal.status ~= "retrying" then
    return nil, "proposal is not being retried"
  end

  local updated, update_error = M.update(proposal, response)
  if not updated then
    return nil, update_error
  end

  proposal.status = "pending"
  return proposal
end

--- Remove a proposal whose retry did not complete.
---
---@param proposal PatchProposal
---@return boolean aborted
function M.abort_retry(proposal)
  if proposal.status ~= "retrying" then
    return false
  end

  proposal.status = "finished"
  clear_preview(proposal)
  return true
end

return M
