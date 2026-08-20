local input = require("patch.ui.input")
local menu = require("patch.ui.menu")

local M = {}

--- Open the instruction input and deliver its submitted value.
---
--- @param on_submit fun(instruction: string)
--- @param on_close fun()
function M.open_input(on_submit, on_close)
  input.open(on_submit, on_close)
end

--- Open a menu containing Pi models.
---
---@param models PatchModel[]
---@param selected_model string effective model selector
---@param on_submit fun(model: PatchModel)
function M.open_menu(models, selected_model, on_submit)
  menu.open(models, selected_model, on_submit)
end

return M
