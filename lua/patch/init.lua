local prompt = require("patch.prompt")
local selection = require("patch.selection")

local M = {}

--- Capture the current buffer around its visual selection and print each group.
function M.capture_selection()
  -- local source_buf = vim.api.nvim_get_current_buf()
  -- leave_visual_mode()
  --
  -- local first_line, last_line = get_selection_lines()
  local capture = selection.capture()
  if not capture then
    print("patch: no visual selection found")
    return
  end

    print(prompt.format_capture(capture))
  end

return M
