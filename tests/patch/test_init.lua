local eq = MiniTest.expect.equality
local patch
local calls
local client
local notify

local function reset()
  calls = {}
  client = {
    setup = function(options)
      calls.client_setup = options
    end,
  }
  notify = {
    setup = function(provider)
      calls.notify_setup = provider
    end,
  }

  package.loaded["patch.core.workflow"] = {
    start = function() calls.start = true end,
    accept = function() calls.accept = true end,
    reject = function() calls.reject = true end,
    retry = function() calls.retry = true end,
    cancel = function() calls.cancel = true end,
    open_menu = function() calls.open_menu = true end,
  }
  package.loaded["patch.pi.client"] = client
  package.loaded["patch.ui.notify"] = notify
  package.loaded["patch"] = nil
  patch = require("patch")
end

local function cleanup()
  for _, name in ipairs({
    "patch", "patch.core.workflow", "patch.pi.client", "patch.ui.notify",
  }) do
    package.loaded[name] = nil
  end
end

local T = MiniTest.new_set({ hooks = { pre_case = reset, post_case = cleanup } })

T["passes configuration to notification and client modules"] = function()
  local provider = function() end
  patch.setup({ notify = provider, system_prompt = "system", model = "provider/model" })

  eq(calls.notify_setup, provider)
  eq(calls.client_setup, { system_prompt = "system", model = "provider/model" })
end

T["delegates public commands to the workflow"] = function()
  patch.start()
  patch.accept()
  patch.reject()
  patch.retry()
  patch.cancel()
  patch.open_menu()

  eq(calls, {
    start = true,
    accept = true,
    reject = true,
    retry = true,
    cancel = true,
    open_menu = true,
  })
end

return T
