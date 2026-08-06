local prompt = require("patch.prompt")
local selection = require("patch.selection")
local client = require("patch.client")
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

    client.request(message, function(replacement)
      -- Resolve the extmark after generation so edits outside the selection are reflected.
      local position = vim.api.nvim_buf_get_extmark_by_id(
        capture.location.source_buf,
        capture.location.namespace,
        capture.location.extmark_id,
        { details = true }
      )

      local start_row = position[1]
      local details = position[3]
      local end_row = details.end_row
      local strict_indexing = true

      -- A terminal newline belongs to the textual response, not a new buffer line.
      local stripped = replacement:gsub("\r?\n$", "")

      local replacement_lines = stripped == ""
        and {}
        or vim.split(stripped, "\n", { plain = true })

      vim.api.nvim_buf_set_lines(
        capture.location.source_buf,
        start_row,
        end_row,
        strict_indexing,
        replacement_lines
      )

      vim.api.nvim_buf_del_extmark(
        capture.location.source_buf,
        capture.location.namespace,
        capture.location.extmark_id
      )
    end)
  end)

end

return M
