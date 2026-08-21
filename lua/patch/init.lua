local workflow = require("patch.core.workflow")
local client = require("patch.pi.client")
local notify = require("patch.ui.notify")

local M = {}

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

---Capture a visual selection and request a replacement.
function M.start()
  workflow.start()
end

---Accept the active replacement proposal.
function M.accept()
  workflow.accept()
end

---Reject the active replacement proposal.
function M.reject()
  workflow.reject()
end

---Request another replacement for the active proposal.
function M.retry()
  workflow.retry()
end

---Cancel the active generation request.
function M.cancel()
  workflow.cancel()
end

---Open the Pi model selection menu.
function M.open_menu()
  workflow.open_menu()
end

return M
