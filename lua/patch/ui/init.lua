local input = require("patch.ui.input")
local menu = require("patch.ui.menu")


local M = {}

function M.open_input(on_submit)
  input.open(on_submit)
end

return M
