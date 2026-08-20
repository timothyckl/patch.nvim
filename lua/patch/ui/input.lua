local M = {}

local Input = require("nui.input")
local PROMPT = "> "

local popup_options = {
  relative = "cursor",
  size = 50,
  position = {
    row = 2,
    col = 1,
  },
  border = {
    style = "single",
    text = {
      top = " Instruction ",
      top_align = "left",
    },
  },
  win_options = {
    cursorline = true,
    wrap = false,
  }
}

---@param input NuiInput
---@return string key
local function submit_key(input)
  local line = vim.api.nvim_buf_get_lines(input.bufnr, 0, 1, false)[1] or ""
  local instruction = line:sub(#PROMPT + 1)
  return instruction:find("%S") and "\r" or ""
end

--- Open the instruction input and deliver its submitted value.
---
--- @param on_submit fun(instruction: string)
--- @param on_close fun()
function M.open(on_submit, on_close)
  local input = Input(vim.deepcopy(popup_options), {
    prompt = PROMPT,
    default_value = "",
    on_submit = on_submit,
    on_close = on_close,
  })

  for _, mode in ipairs({ "i", "n" }) do
    input:map(mode, "<CR>", function()
      return submit_key(input)
    end, { expr = true, noremap = true })
  end

  -- unmount input by pressing `<Esc>` in normal mode
  input:map("n", "<Esc>", function()
    input:unmount()
  end, { noremap = true })

  input:mount()
  vim.schedule(vim.cmd.startinsert)
end

return M
