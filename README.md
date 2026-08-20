# patch.nvim

A simple agentic inline code editor for Neovim.

Requires Neovim 0.10+, [nui.nvim](https://github.com/MunifTanjim/nui.nvim), and an authenticated [Pi](https://github.com/earendil-works/pi) installation.

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

## Installation

[nvim-notify](https://github.com/rcarriga/nvim-notify) is optional. Omit it from the examples below and remove the `notify` option from the configuration to use `vim.notify` instead.

### lazy.nvim

```lua
{
  "timothyckl/patch.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
}
```

### packer.nvim

```lua
use({
  "timothyckl/patch.nvim",
  requires = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
})
```

### vim-plug

```vim
Plug 'MunifTanjim/nui.nvim'
Plug 'rcarriga/nvim-notify'
Plug 'timothyckl/patch.nvim'
```

## Configuration

```lua
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
```

`system_prompt` is optional. When set, it completely replaces Patch's built-in system prompt.

`model` is optional. When omitted, Patch uses Pi's primary model. `PatchMenu` marks the effective model and allows selecting an override for the current Neovim session.
