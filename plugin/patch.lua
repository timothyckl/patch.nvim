--- Submit the current visual selection and its buffer context for patching.
vim.keymap.set("x", "<leader>p", require("patch").capture_selection)

--- Cancel the active patch request from normal mode.
vim.keymap.set("n", "<C-c>", require("patch").cancel)
