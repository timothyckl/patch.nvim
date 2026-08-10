local prompt = require("patch.prompt")
local selection = require("patch.selection")
local client = require("patch.client")
local replacement = require("patch.replacement")
local ui = require("patch.ui")

local M = {}

-- TODO: If the submitted instruction is empty or whitespace-only, halt without starting generation.
--       See lua/patch/ui/
--- Capture a visual selection, request a replacement, and apply it to the tracked range.
function M.start()
  local capture = selection.capture()

  if not capture then
    print("patch: no selection found.")
    return
  end

  ui.open_input(function(instruction)
    local message = prompt.build(capture, instruction)

    client.request(message, function(res, err)
      if err then
        return
      end

      local proposal = replacement.apply(capture.location, res)
      if not proposal then
        vim.notify("patch: selection no longer exists", vim.log.levels.ERROR)
        return
      end

      -- TODO: Connect these actions to user input.
      -- replacement.accept(proposal)
      -- replacement.reject(proposal)
      -- replacement.retry(proposal, client, message)
    end)
  end)
end

return M
