local M = {}
local notify = require("patch.notify")

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

---@param proposal PatchProposal
---@return boolean rendered
local function render_preview(proposal)
  local range = resolve_range(proposal.location)
  if not range then
    return false
  end

  local source_buf = proposal.location.source_buf
  vim.api.nvim_buf_set_extmark(
    source_buf,
    proposal.location.namespace,
    range.start_row,
    0,
    {
      id = proposal.location.extmark_id,
      end_row = range.end_row,
      end_col = 0,
      right_gravity = true,
      end_right_gravity = false,
      hl_group = "DiffDelete",
      hl_eol = true,
    }
  )

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
  local range = resolve_range(proposal.location)
  if not range then
    return false
  end

  local source_buf = proposal.location.source_buf

  if proposal.generated_mark then
    vim.api.nvim_buf_del_extmark(source_buf, namespace, proposal.generated_mark)
    proposal.generated_mark = nil
  end

  vim.api.nvim_buf_set_extmark(
    source_buf,
    proposal.location.namespace,
    range.start_row,
    0,
    {
      id = proposal.location.extmark_id,
      end_row = range.end_row,
      end_col = 0,
      right_gravity = true,
      end_right_gravity = false,
    }
  )

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

    vim.api.nvim_buf_del_extmark(
      source_buf,
      proposal.location.namespace,
      proposal.location.extmark_id
    )
  end
end

--- Preview a generated replacement after a tracked selection.
---
---@param location PatchLocation
---@param response string
---@return PatchProposal|nil proposal
function M.apply(location, response)
  local range = resolve_range(location)
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
  render_preview(proposal)
  return proposal
end

--- Replace a proposal's generated preview with a new response.
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

  proposal.generated_lines = to_lines(response)
  render_preview(proposal)
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

  local range = resolve_range(proposal.location)
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

--- Request another response and update a proposal in place.
---
---@param proposal PatchProposal
---@param client table client exposing request(message, on_complete)
---@param message string original prompt message
---@param on_settled? fun(request: PatchRequest)
---@return PatchRequest|nil request
function M.retry(proposal, client, message, on_settled)
  if proposal.status ~= "pending" then
    return nil
  end

  if not hide_preview(proposal) then
    return nil
  end

  proposal.status = "retrying"

  local request

  local function settle()
    if on_settled then
      on_settled(request)
    end
  end

  request = client.request(message, function(res, err)
    if proposal.status ~= "retrying" then
      settle()
      return
    end

    if err then
      proposal.status = "finished"
      clear_preview(proposal)
      settle()
      return
    end

    local updated, update_error = M.update(proposal, res)

    if not updated then
      proposal.status = "finished"
      clear_preview(proposal)
      notify.send(tostring(update_error), vim.log.levels.ERROR)
      settle()
      return
    end

    proposal.status = "pending"
    notify.send("patch: complete", vim.log.levels.INFO)
    settle()
  end)

  return request
end

return M
