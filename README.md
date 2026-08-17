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
      -- system_prompt = "Custom system instructions...",
      -- model = "openai/gpt-5.6-sol",
    })

    vim.keymap.set("x", "<leader>p", "<Cmd>PatchCapture<CR>", { desc = "Capture selection and request a patch" })
    vim.keymap.set("n", "<leader>pa", "<Cmd>PatchAccept<CR>", { desc = "Accept the active patch proposal" })
    vim.keymap.set("n", "<leader>pr", "<Cmd>PatchReject<CR>", { desc = "Reject the active patch and restore the original" })
    vim.keymap.set("n", "<leader>pR", "<Cmd>PatchRetry<CR>", { desc = "Generate a new active patch proposal" })
    vim.keymap.set("n", "<leader>pc", "<Cmd>PatchCancel<CR>", { desc = "Cancel the active patch generation request" })
    vim.keymap.set("n", "<leader>pm", "<Cmd>PatchMenu<CR>", { desc = "Select the model used for patch requests" })
  end,
}
```

`system_prompt` is optional. When set, it completely replaces Patch's built-in system prompt.

`model` is optional. When omitted, Patch uses Pi's primary model. `PatchMenu` marks the effective model and allows selecting an override for the current Neovim session.

## To-do

- [ ] Add codebase-relevant context gathering on top of the separate buffer-context and prompt-construction stages.
- [x] Reject empty or whitespace-only instructions before starting generation.
- [x] Make cancellation request-scoped instead of global.
- [x] Add a model-selection UI for choosing the model used by Patch requests, with optional configuration and Pi's primary model as the default.
- [x] Clean up undo behavior so undoing an accepted patch restores the original text like rejection does, without leaving or duplicating generated content.
- [x] Improve retry feedback by temporarily turning off the existing diff preview while a new replacement is being generated, then displaying the updated preview when the retry completes.
- [x] Expose the system prompt to users as a setup configuration option.
- [x] Show a notification when a replacement has finished generating and is ready for review.
