local M = {}

local Input = require("nui.input")

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

local function handle_close()
  print("Input closed!")
end

local function handle_update() end

function M.open(on_submit)
  local input = Input(popup_options, {
    prompt = "> ",
    default_value = "",
    on_close = handle_close,
    on_submit = on_submit,
    on_change = handle_update,
  })

  -- unmount input by pressing `<Esc>` in normal mode
  input:map("n", "<Esc>", function()
    input:unmount()
  end, { noremap = true })

  input:mount()
  vim.schedule(vim.cmd.startinsert)
end

return M
