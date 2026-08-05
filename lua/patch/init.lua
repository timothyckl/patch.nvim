local prompt = require("patch.prompt")
local selection = require("patch.selection")
local client = require("patch.client")

local M = {}

--- Abort the active patch request, if one exists.
function M.cancel()
  client.cancel()
end

--- Capture the visual selection and send it to the patch client with buffer context.
function M.capture_selection()
  local capture = selection.capture()

  if not capture then
    print("patch: no visual selection found")
    return
  end

  client.request(prompt.format_capture(capture))
end

return M
