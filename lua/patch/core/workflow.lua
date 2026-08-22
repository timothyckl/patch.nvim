local generation = require("patch.core.generation")
local selection = require("patch.core.selection")
local context = require("patch.core.context")
local client = require("patch.pi.client")
local replacement = require("patch.core.replacement")
local ui = require("patch.ui")
local notify = require("patch.ui.notify")

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

---@param message string
local function warn(message)
  notify.send(message, vim.log.levels.WARN)
end

---@param message string
local function report_error(message)
  notify.send(message, vim.log.levels.ERROR)
end

---@param message string
local function report_info(message)
  notify.send(message, vim.log.levels.INFO)
end

---@param err string|nil
local function report_request_error(err)
  if err and err ~= "cancelled" then
    report_error(err)
  end
end

---@return boolean blocked
local function block_menu_for_active_input()
  if not active_workflow or active_workflow.phase ~= "input" then
    return false
  end

  warn("submit or close the active instruction first")
  return true
end

--- Open a menu containing the models available to Pi.
function M.open_menu()
  if block_menu_for_active_input() then
    return
  end

  client.resolve_model(function(selected_model, model_error)
    if block_menu_for_active_input() then
      return
    end

    if model_error then
      report_error(model_error)
      return
    end

    client.get_available_models(function(models, err)
      if block_menu_for_active_input() then
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

--- Run a generation request and return the workflow to review when it succeeds.
---
---@param workflow PatchWorkflow
---@param phase "generating"|"retrying"
---@param apply_response fun(response: string): PatchProposal|nil, string|nil
---@param abort fun()
local function generate(workflow, phase, apply_response, abort)
  report_info("generating...")

  generation.run(workflow, phase, {
    is_current = function(request)
      return active_workflow == workflow
          and workflow.phase == phase
          and workflow.request == request
    end,
    apply_response = apply_response,
    on_failure = function(err, kind)
      abort()
      active_workflow = nil

      if kind == "request" then
        report_request_error(err)
      else
        report_error(err)
      end
    end,
    on_complete = function()
      report_info("complete")
    end,
  })
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

    workflow.message = generation.build(workflow.content, instruction)
    workflow.content = nil

    generate(workflow, "generating", function(response)
      local proposal = replacement.apply(workflow.location, response)
      if not proposal then
        return nil, "selection no longer exists"
      end

      workflow.proposal = proposal
      return proposal
    end, function()
      selection.clear(workflow.location)
    end)
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
    return
  end

  if workflow.proposal.status == "finished" then
    -- The proposal was finalized because its source buffer is unavailable.
    active_workflow = nil
  end

  warn("the active proposal cannot be accepted")
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

  generate(workflow, "retrying", function(response)
    return replacement.complete_retry(workflow.proposal, response)
  end, function()
    replacement.abort_retry(workflow.proposal)
  end)
end

--- Cancel the active replacement request, if one exists.
function M.cancel()
  local workflow = active_workflow
  if not workflow or not workflow.request or not generation.cancel(workflow.request) then
    warn("nothing to cancel")
    return
  end

  report_info("cancelled")
end

return M
