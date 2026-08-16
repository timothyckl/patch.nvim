# patch

A simple agentic inline code editor for Neovim.

Built with the [pi-ai](https://github.com/earendil-works/pi/tree/main/packages/ai) package.

## How it works

1. Enter Visual Line (`Shift + v`) mode and highlight some text or empty space.
2. Send an instruction, such as “Refactor this function” or “Add type hints.”
3. Wait for the suggestion, then accept, reject, or retry it.

## Authentication

Authenticate through the Pi coding agent before using patch.nvim. Start Pi, enter `/login` (or `/login <provider>`), and follow the prompts:

```sh
pi
```

Alternatively, authenticate an OAuth provider from the command line:

```sh
cd ~/.pi/agent
npx @earendil-works/pi-ai login [provider]
```

## Configuration

```lua
{
  "tim/tau.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
  config = function()
    require("patch").setup({
      notify = require("notify"),
    })

    vim.keymap.set("x", "<leader>p", "<Cmd>PatchCapture<CR>", { desc = "Capture selection and request a patch" })
    vim.keymap.set("n", "<leader>pa", "<Cmd>PatchAccept<CR>", { desc = "Accept the active patch proposal" })
    vim.keymap.set("n", "<leader>pr", "<Cmd>PatchReject<CR>", { desc = "Reject the active patch and restore the original" })
    vim.keymap.set("n", "<leader>pR", "<Cmd>PatchRetry<CR>", { desc = "Generate a new active patch proposal" })
    vim.keymap.set("n", "<leader>pc", "<Cmd>PatchCancel<CR>", { desc = "Cancel the active patch generation request" })
  end,
}
```

## To-do

- [ ] Build codebase-relevant context separately from prompt construction.
- [ ] Reject empty or whitespace-only instructions before starting generation.
- [x] Make cancellation request-scoped instead of global.
- [ ] Add a model-selection UI and mappable commands that let users choose or cycle the model used for Patch requests. By default, Patch uses Pi's primary model.
- [x] Clean up undo behavior so undoing an accepted patch restores the original text like rejection does, without leaving or duplicating generated content.
- [x] Improve retry feedback by temporarily turning off the existing diff preview while a new replacement is being generated, then displaying the updated preview when the retry completes.
- [ ] Expose the system prompt to users as a setup configuration option.
- [x] Show a notification when a replacement has finished generating and is ready for review.
