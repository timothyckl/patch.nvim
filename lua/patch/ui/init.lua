local input = require("patch.ui.input")
local menu = require("patch.ui.menu")

local M = {}

--- Open the instruction input and deliver its submitted value.
---
--- @param model string
--- @param on_submit fun(instruction: string)
--- @param on_close fun()
function M.open_input(model, on_submit, on_close)
  input.open(model, on_submit, on_close)
end

--- Open a menu containing Pi models.
---
---@param models PatchModel[]
---@param on_submit fun(model: PatchModel)
function M.open_menu(models, on_submit)
  menu.open(models, on_submit)
end

return M
