vim.keymap.set("x", "<leader>p", function()
  require("patch").capture_selection()
end, { silent = true, desc = "Patch: capture selection" })
