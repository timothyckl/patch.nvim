local prompt = require("patch.prompt")
local selection = require("patch.selection")
local client = require("patch.client")
local replacement = require("patch.replacement")
local ui = require("patch.ui")
local notify = require("patch.notify")

local M = {}
local active_proposal = nil
local active_message = nil
local active_request = nil
local requesting = false

---@class PatchOptions
---@field notify? function|table notification provider compatible with vim.notify

---@param opts? PatchOptions
function M.setup(opts)
  opts = opts or {}
  notify.setup(opts.notify)
end

---@param message string
local function warn(message)
  notify.send("patch: " .. message, vim.log.levels.WARN)
end

local function clear_active_patch()
  active_proposal = nil
  active_message = nil
end

-- TODO: If the submitted instruction is empty or whitespace-only, halt without starting generation.
--       See lua/patch/ui/
--- Capture a visual selection, request a replacement, and apply it to the tracked range.
function M.start()
  if requesting then
    warn("a replacement is already being generated")
    return
  end

  if active_proposal then
    warn("accept or reject the active proposal first")
    return
  end

  local capture = selection.capture()

  if not capture then
    warn("no selection found")
    return
  end

  ui.open_input(function(instruction)
    local message = prompt.build(capture, instruction)
    requesting = true

    local request
    request = client.request(message, function(res, err)
      if active_request ~= request then
        return
      end

      active_request = nil
      requesting = false

      if err then
        selection.clear(capture.location)
        return
      end

      local proposal = replacement.apply(capture.location, res)
      if not proposal then
        notify.send("patch: selection no longer exists", vim.log.levels.ERROR)
        return
      end

      active_proposal = proposal
      active_message = message
      notify.send("patch: complete", vim.log.levels.INFO)
    end)
    active_request = request
  end)
end

--- Accept the active replacement proposal.
function M.accept()
  if not active_proposal then
    warn("no active proposal to accept")
    return
  end

  if replacement.accept(active_proposal) then
    clear_active_patch()
  else
    warn("the active proposal cannot be accepted")
  end
end

--- Reject the active replacement proposal.
function M.reject()
  if not active_proposal then
    warn("no active proposal to reject")
    return
  end

  if replacement.reject(active_proposal) then
    clear_active_patch()
  else
    warn("the active proposal cannot be rejected")
  end
end

--- Request another replacement for the active proposal.
function M.retry()
  if not active_proposal or not active_message then
    warn("no active proposal to retry")
    return
  end

  local retried_proposal = active_proposal
  local request = replacement.retry(retried_proposal, client, active_message, function(settled_request)
    if active_request == settled_request then
      active_request = nil
    end

    if active_proposal == retried_proposal and retried_proposal.status == "finished" then
      clear_active_patch()
    end
  end)

  if not request then
    warn("the active proposal cannot be retried")
    return
  end

  active_request = request
end

--- Cancel the active replacement request, if one exists.
function M.cancel()
  if not active_request or not client.cancel(active_request) then
    warn("nothing to cancel")
    return
  end

  notify.send("patch: cancelled", vim.log.levels.INFO)
end

return M
