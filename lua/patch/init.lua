local prompt = require("patch.prompt")
local selection = require("patch.selection")
local client = require("patch.client")

local M = {}

--- Capture the current buffer around its visual selection and print each group.
function M.capture_selection()
  local capture = selection.capture()

  if not capture then
    print("patch: no visual selection found")
    return
  end

  -- print(prompt.format_capture(capture))
  client.request(prompt.format_capture(capture))
end

return M
