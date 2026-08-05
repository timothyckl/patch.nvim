--- NOTE: Cancelling still occurs globally. Need to revisit this.
---       For now, assume patches cannot be cancelled mid-flight.
-- vim.keymap.set("n", "<C-c>", require("patch").cancel)

vim.keymap.set("x", "<leader>p", require("patch").start)
