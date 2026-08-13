local patch = require("patch")

vim.api.nvim_create_user_command("PatchCapture", patch.start, {
  desc = "Capture a selection and generate a replacement",
})

vim.api.nvim_create_user_command("PatchAccept", patch.accept, {
  desc = "Accept the active replacement proposal",
})

vim.api.nvim_create_user_command("PatchReject", patch.reject, {
  desc = "Reject the active replacement proposal",
})

vim.api.nvim_create_user_command("PatchRetry", patch.retry, {
  desc = "Retry the active replacement proposal",
})

--- NOTE: Cancelling still occurs globally. Need to revisit this.
---       For now, assume patches cannot be cancelled mid-flight.
vim.api.nvim_create_user_command("PatchCancel", patch.cancel, {
  desc = "Cancel the active replacement request",
})
