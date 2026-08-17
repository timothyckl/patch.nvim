local Menu = require("nui.menu")
local event = require("nui.utils.autocmd").event

local M = {}

local popup_options = {
  relative = "editor",
  position = "50%",
  size = {
    width = 40,
  },
  padding = {
    top = 1,
    right = 2,
    bottom = 1,
    left = 2,
  },
  border = {
    style = "single",
    text = {
      top = "[Choose Item]",
      top_align = "center",
    },
  },
  win_options = {
    winhighlight = "Normal:Normal",
  },
}

--- Open a menu containing Pi models.
---
---@param models PatchModel[]
---@param on_submit fun(model: PatchModel)
function M.open(models, on_submit)
  local lines = {}

  for _, model in ipairs(models) do
    table.insert(lines, Menu.item(model.id, {
      model = model,
    }))
  end

  local menu = Menu(popup_options, {
    lines = lines,
    max_width = 20,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>" },
      submit = { "<CR>", "<Space>" },
    },
    on_submit = function(item)
      on_submit(item.model)
    end,
  })

  menu:on(event.BufLeave, function()
    menu:unmount()
  end)

  menu:mount()

  for row, model in ipairs(models) do
    vim.api.nvim_buf_set_extmark(menu.bufnr, menu.ns_id, row - 1, 0, {
      virt_text = { { model.provider, "Comment" } },
      virt_text_pos = "right_align",
    })
  end
end

return M
