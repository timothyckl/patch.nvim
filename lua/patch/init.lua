local prompt = require("patch.prompt")
local selection = require("patch.selection")
local context = require("patch.context")
local client = require("patch.client")
local replacement = require("patch.replacement")
local ui = require("patch.ui")
local notify = require("patch.notify")

local M = {}

---@class PatchWorkflow
---@field phase "input"|"generating"|"reviewing"|"retrying"
---@field location PatchLocation
---@field content? PatchContent
---@field message? string
---@field request? PatchRequest
---@field proposal? PatchProposal

---@type PatchWorkflow|nil
local active_workflow

---@class PatchOptions
---@field notify? function|table notification provider compatible with vim.notify
---@field system_prompt? string custom Pi system prompt
---@field model? string Pi model selector in provider/model format

---@param opts? PatchOptions
function M.setup(opts)
  opts = opts or {}
  notify.setup(opts.notify)
  client.setup({
    system_prompt = opts.system_prompt,
    model = opts.model,
  })
end

---@param message string
local function warn(message)
  notify.send("patch: " .. message, vim.log.levels.WARN)
end

---@param message string
local function report_error(message)
  notify.send("patch: " .. message, vim.log.levels.ERROR)
end

---@param message string
local function report_info(message)
  notify.send("patch: " .. message, vim.log.levels.INFO)
end

---@param err string|nil
local function report_request_error(err)
  if err and err ~= "cancelled" then
    report_error(err)
  end
end

--- Open a menu containing the models available to Pi.
function M.open_menu()
  if active_workflow and active_workflow.phase == "input" then
    warn("submit or close the active instruction first")
    return
  end

  client.resolve_model(function(selected_model, model_error)
    if active_workflow and active_workflow.phase == "input" then
      warn("submit or close the active instruction first")
      return
    end

    if model_error then
      report_error(model_error)
      return
    end

    client.get_available_models(function(models, err)
      if active_workflow and active_workflow.phase == "input" then
        warn("submit or close the active instruction first")
        return
      end

      if err then
        report_error(err)
        return
      end

      if not models or #models == 0 then
        warn("Pi reported no available models")
        return
      end

      ui.open_menu(models, selected_model, function(model)
        local selected = client.select_model(model)
        report_info("using " .. selected)
      end)
    end)
  end)
end

---@return boolean blocked
local function block_start_for_active_workflow()
  if not active_workflow then
    return false
  end

  if active_workflow.phase == "input" then
    warn("submit or close the active instruction first")
  elseif active_workflow.phase == "reviewing" then
    warn("accept or reject the active proposal first")
  else
    warn("a replacement is already being generated")
  end

  return true
end

--- Capture a visual selection, request a replacement, and preview it at the tracked range.
function M.start()
  if block_start_for_active_workflow() then
    return
  end

  local location = selection.capture()
  if not location then
    warn("no selection found")
    return
  end

  local content = context.capture(location)
  if not content then
    selection.clear(location)
    warn("no selection found")
    return
  end

  local workflow = {
    phase = "input",
    location = location,
    content = content,
  }
  active_workflow = workflow

  ui.open_input(function(instruction)
    if active_workflow ~= workflow or workflow.phase ~= "input" then
      return
    end

    workflow.message = prompt.build(workflow.content, instruction)
    workflow.content = nil
    workflow.phase = "generating"
    report_info("generating...")

    local request
    request = client.request(workflow.message, function(response, err)
      if active_workflow ~= workflow
          or workflow.phase ~= "generating"
          or workflow.request ~= request then
        return
      end

      workflow.request = nil

      if err then
        active_workflow = nil
        selection.clear(workflow.location)
        report_request_error(err)
        return
      end

      local proposal = replacement.apply(workflow.location, response)
      if not proposal then
        active_workflow = nil
        selection.clear(workflow.location)
        report_error("selection no longer exists")
        return
      end

      workflow.phase = "reviewing"
      workflow.proposal = proposal
      report_info("complete")
    end)
    workflow.request = request
  end, function()
    if active_workflow ~= workflow or workflow.phase ~= "input" then
      return
    end

    active_workflow = nil
    selection.clear(workflow.location)
  end)
end

--- Accept the active replacement proposal.
function M.accept()
  local workflow = active_workflow
  if not workflow or not workflow.proposal then
    warn("no active proposal to accept")
    return
  end

  if replacement.accept(workflow.proposal) then
    active_workflow = nil
  elseif workflow.phase == "retrying" then
    warn("the active proposal cannot be accepted")
  else
    -- The proposal was finalized because its source buffer is unavailable.
    active_workflow = nil
    warn("the active proposal cannot be accepted")
  end
end

--- Reject the active replacement proposal.
function M.reject()
  local workflow = active_workflow
  if not workflow or not workflow.proposal then
    warn("no active proposal to reject")
    return
  end

  if replacement.reject(workflow.proposal) then
    active_workflow = nil
  else
    warn("the active proposal cannot be rejected")
  end
end

--- Request another replacement for the active proposal.
function M.retry()
  local workflow = active_workflow
  if not workflow or not workflow.proposal or not workflow.message then
    warn("no active proposal to retry")
    return
  end

  if not replacement.begin_retry(workflow.proposal) then
    if workflow.phase == "retrying" then
      warn("the active proposal cannot be retried")
      return
    end

    -- The proposal was finalized because its source buffer is unavailable.
    active_workflow = nil
    warn("the active proposal cannot be retried")
    return
  end

  workflow.phase = "retrying"
  report_info("generating...")

  local request
  request = client.request(workflow.message, function(response, err)
    if active_workflow ~= workflow
        or workflow.phase ~= "retrying"
        or workflow.request ~= request then
      return
    end

    workflow.request = nil

    if err then
      replacement.abort_retry(workflow.proposal)
      active_workflow = nil
      report_request_error(err)
      return
    end

    local updated, update_error = replacement.complete_retry(workflow.proposal, response)
    if not updated then
      replacement.abort_retry(workflow.proposal)
      active_workflow = nil
      report_error(tostring(update_error))
      return
    end

    workflow.phase = "reviewing"
    report_info("complete")
  end)
  workflow.request = request
end

--- Cancel the active replacement request, if one exists.
function M.cancel()
  local workflow = active_workflow
  if not workflow or not workflow.request or not client.cancel(workflow.request) then
    warn("nothing to cancel")
    return
  end

  report_info("cancelled")
end

return M
