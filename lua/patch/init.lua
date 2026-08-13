local prompt = require("patch.prompt")
local selection = require("patch.selection")
local client = require("patch.client")
local replacement = require("patch.replacement")
local ui = require("patch.ui")
local notify = require("patch.notify")

local M = {}
local active_proposal = nil
local active_message = nil
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

    client.request(message, function(res, err)
      requesting = false

      if err then
        return
      end

      local proposal = replacement.apply(capture.location, res)
      if not proposal then
        notify.send("patch: selection no longer exists", vim.log.levels.ERROR)
        return
      end

      active_proposal = proposal
      active_message = message
    end)
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

  if not replacement.retry(active_proposal, client, active_message) then
    warn("the active proposal cannot be retried")
  end
end

--- Cancel the active replacement request, if one exists.
function M.cancel()
  client.cancel()
end

return M
