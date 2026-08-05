local prompt = require("patch.prompt")
local selection = require("patch.selection")
local client = require("patch.client")
local ui = require("patch.ui")

local M = {}

function M.start()
  local capture = selection.capture()

  if not capture then
    print("patch: no selection found.")
    return
  end

  ui.open_input(function(instruction)
    local message = prompt.build(capture, instruction)

    client.request(message, function(replacement)
      print(replacement)
    end)
  end)

end

return M
