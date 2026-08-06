local input = require("patch.ui.input")
local menu = require("patch.ui.menu")

local M = {}

--- Open the instruction input and deliver its submitted value.
---
--- @param on_submit fun(instruction: string)
function M.open_input(on_submit)
  input.open(on_submit)
end

return M
