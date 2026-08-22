local eq = MiniTest.expect.equality
local notify
local original_notify

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      package.loaded["patch.ui.notify"] = nil
      notify = require("patch.ui.notify")
      original_notify = vim.notify
    end,
    post_case = function()
      vim.notify = original_notify
      notify.setup(nil)
    end,
  },
})

T["uses vim.notify with the default title"] = function()
  local received
  vim.notify = function(message, level, options)
    received = { message, level, options }
  end

  notify.send("message", vim.log.levels.INFO)

  eq(received[1], "message")
  eq(received[2], vim.log.levels.INFO)
  eq(received[3], { title = "patch.nvim", render = "compact" })
end

T["uses a configured callable provider and preserves options"] = function()
  local received
  notify.setup(function(message, level, options)
    received = { message, level, options }
  end)

  notify.send("warning", vim.log.levels.WARN, { title = "custom", timeout = 10 })

  eq(received[1], "warning")
  eq(received[2], vim.log.levels.WARN)
  eq(received[3], { title = "custom", timeout = 10, render = "compact" })
end

return T
