describe("plugin/patch.lua", function()
  local calls
  local command_names = {
    "PatchCapture", "PatchAccept", "PatchReject", "PatchRetry", "PatchCancel", "PatchMenu",
  }

  local function clear_commands()
    for _, name in ipairs(command_names) do
      pcall(vim.api.nvim_del_user_command, name)
    end
  end

  before_each(function()
    clear_commands()
    calls = {}
    package.loaded["patch"] = {
      start = function() calls.start = true end,
      accept = function() calls.accept = true end,
      reject = function() calls.reject = true end,
      retry = function() calls.retry = true end,
      cancel = function() calls.cancel = true end,
      open_menu = function() calls.open_menu = true end,
    }

    dofile(vim.fn.getcwd() .. "/plugin/patch.lua")
  end)

  after_each(function()
    clear_commands()
    package.loaded["patch"] = nil
  end)

  it("registers the documented user commands", function()
    local commands = vim.api.nvim_get_commands({})

    for _, name in ipairs(command_names) do
      assert.is_table(commands[name])
      assert.is_string(commands[name].definition)
    end
  end)

  it("routes commands to the plugin entrypoints", function()
    vim.cmd.PatchCapture()
    vim.cmd.PatchAccept()
    vim.cmd.PatchReject()
    vim.cmd.PatchRetry()
    vim.cmd.PatchCancel()
    vim.cmd.PatchMenu()

    assert.are.same({
      start = true,
      accept = true,
      reject = true,
      retry = true,
      cancel = true,
      open_menu = true,
    }, calls)
  end)
end)
