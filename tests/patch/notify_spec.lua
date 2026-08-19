describe("patch.notify", function()
  local notify
  local original_notify

  before_each(function()
    package.loaded["patch.notify"] = nil
    notify = require("patch.notify")
    original_notify = vim.notify
  end)

  after_each(function()
    vim.notify = original_notify
    notify.setup(nil)
  end)

  it("uses vim.notify with the default title", function()
    local received
    vim.notify = function(message, level, options)
      received = { message, level, options }
    end

    notify.send("message", vim.log.levels.INFO)

    assert.are.equal("message", received[1])
    assert.are.equal(vim.log.levels.INFO, received[2])
    assert.are.same({ title = "patch.nvim" }, received[3])
  end)

  it("uses a configured callable provider and preserves options", function()
    local received
    notify.setup(function(message, level, options)
      received = { message, level, options }
    end)

    notify.send("warning", vim.log.levels.WARN, { title = "custom", timeout = 10 })

    assert.are.equal("warning", received[1])
    assert.are.equal(vim.log.levels.WARN, received[2])
    assert.are.same({ title = "custom", timeout = 10 }, received[3])
  end)
end)
