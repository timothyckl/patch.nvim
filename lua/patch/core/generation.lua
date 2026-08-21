local client = require("patch.pi.client")
local prompt = require("patch.pi.prompt")

local M = {}

---@class PatchGenerationCallbacks
---@field is_current fun(request: PatchRequest): boolean
---@field apply_response fun(response: string): PatchProposal|nil, string|nil
---@field on_failure fun(err: string, kind: "request"|"application")
---@field on_complete fun()

---Build a generation prompt from captured content and an instruction.
---
---@param content PatchContent
---@param instruction string
---@return string message
function M.build(content, instruction)
  return prompt.build(content, instruction)
end

---Run a generation request and return the workflow to review when it succeeds.
---
---@param workflow PatchWorkflow
---@param phase "generating"|"retrying"
---@param callbacks PatchGenerationCallbacks
function M.run(workflow, phase, callbacks)
  workflow.phase = phase

  local request
  request = client.request(workflow.message, function(response, err)
    if not callbacks.is_current(request) then
      return
    end

    workflow.request = nil

    if err then
      callbacks.on_failure(err, "request")
      return
    end

    local completed, completion_error = callbacks.apply_response(response)
    if not completed then
      callbacks.on_failure(tostring(completion_error), "application")
      return
    end

    workflow.phase = "reviewing"
    callbacks.on_complete()
  end)
  workflow.request = request
end

---Cancel an active generation request.
---
---@param request PatchRequest
---@return boolean cancelled
function M.cancel(request)
  return client.cancel(request)
end

return M
