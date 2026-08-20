local eq = MiniTest.expect.equality
local patch
local mocks
local notifications
local input
local requests
local proposal
local location

local function reset()
  notifications = {}
  requests = {}
  proposal = { status = "pending" }
  location = { source_buf = 1, extmark_id = 2 }

  mocks = {
    prompt = {
      build = function(_, instruction)
        return "built:" .. instruction
      end,
    },
    selection = {
      capture = function()
        return location
      end,
      clear = function(value)
        mocks.selection.cleared = value
      end,
    },
    context = {
      capture = function(value)
        eq(value, location)
        return { before = {}, selected = { "old" }, after = {} }
      end,
    },
    client = {
      setup = function(options)
        mocks.client.setup_options = options
      end,
      request = function(message, on_complete)
        local request = { message = message, on_complete = on_complete, state = "pending" }
        table.insert(requests, request)
        return request
      end,
      cancel = function(request)
        request.cancelled = true
        return true
      end,
      resolve_model = function(on_complete)
        on_complete("provider/current", nil)
      end,
      get_available_models = function(on_complete)
        on_complete({ { provider = "provider", id = "model", name = "Model" } }, nil)
      end,
      select_model = function(model)
        return model.provider .. "/" .. model.id
      end,
    },
    replacement = {
      apply = function(value, response)
        mocks.replacement.applied = { value, response }
        proposal.location = value
        return proposal
      end,
      accept = function(value)
        mocks.replacement.accepted = value
        return true
      end,
      reject = function(value)
        mocks.replacement.rejected = value
        return true
      end,
      begin_retry = function(value)
        mocks.replacement.retry_started = value
        value.status = "retrying"
        return true
      end,
      complete_retry = function(value, response)
        mocks.replacement.retry_completed = { value, response }
        value.status = "pending"
        return value
      end,
      abort_retry = function(value)
        mocks.replacement.retry_aborted = value
        value.status = "finished"
        return true
      end,
    },
    ui = {
      open_input = function(on_submit, on_close)
        input = { submit = on_submit, close = on_close }
      end,
      open_menu = function(models, selected, on_submit)
        mocks.ui.menu = { models = models, selected = selected, submit = on_submit }
      end,
    },
    notify = {
      setup = function(provider)
        mocks.notify.provider = provider
      end,
      send = function(message, level)
        table.insert(notifications, { message = message, level = level })
      end,
    },
  }

  package.loaded["patch.prompt"] = mocks.prompt
  package.loaded["patch.selection"] = mocks.selection
  package.loaded["patch.context"] = mocks.context
  package.loaded["patch.client"] = mocks.client
  package.loaded["patch.replacement"] = mocks.replacement
  package.loaded["patch.ui"] = mocks.ui
  package.loaded["patch.notify"] = mocks.notify
  package.loaded["patch"] = nil
  patch = require("patch")
end

local function cleanup()
  for _, name in ipairs({
    "patch", "patch.prompt", "patch.selection", "patch.context", "patch.client",
    "patch.replacement", "patch.ui", "patch.notify",
  }) do
  package.loaded[name] = nil
end
end

local T = MiniTest.new_set({ hooks = { pre_case = reset, post_case = cleanup } })

local function test(name, action)
  T[name] = action
end

local function notification(message, level)
  for _, item in ipairs(notifications) do
    if item.message == message and (not level or item.level == level) then
      return item
    end
  end
end

local function start_and_submit()
  patch.start()
  eq(type(input), "table")
  input.submit("change it")
  eq(#requests, 1)
end

local function complete_generation(response, err)
  requests[#requests].on_complete(response, err)
end

test("passes configuration to notification and client modules", function()
  local provider = function() end
  patch.setup({ notify = provider, system_prompt = "system", model = "provider/model" })

  eq(mocks.notify.provider, provider)
  eq(mocks.client.setup_options, { system_prompt = "system", model = "provider/model" })
end)

test("runs capture, generation, review, and acceptance", function()
  start_and_submit()

  eq(requests[1].message, "built:change it")
  assert(notification("patch: generating...", vim.log.levels.INFO))

  complete_generation("replacement", nil)
  eq(mocks.replacement.applied, { location, "replacement" })
  assert(notification("patch: complete", vim.log.levels.INFO))

  patch.accept()
  eq(mocks.replacement.accepted, proposal)

  patch.accept()
  assert(notification("patch: no active proposal to accept", vim.log.levels.WARN))
end)

test("rejects a reviewed proposal", function()
  start_and_submit()
  complete_generation("replacement", nil)

  patch.reject()

  eq(mocks.replacement.rejected, proposal)
  patch.reject()
  assert(notification("patch: no active proposal to reject", vim.log.levels.WARN))
end)

test("retries a proposal and applies the new response", function()
  start_and_submit()
  complete_generation("first", nil)

  patch.retry()
  eq(mocks.replacement.retry_started, proposal)
  eq(#requests, 2)

  complete_generation("second", nil)
  eq(mocks.replacement.retry_completed, { proposal, "second" })
  assert(notification("patch: complete", vim.log.levels.INFO))
end)

test("aborts a failed retry and reports the error", function()
  start_and_submit()
  complete_generation("first", nil)
  patch.retry()

  complete_generation(nil, "request failed")

  eq(mocks.replacement.retry_aborted, proposal)
  assert(notification("patch: request failed", vim.log.levels.ERROR))
end)

test("cancels an active request and suppresses the cancellation error", function()
  start_and_submit()

  patch.cancel()
  eq(requests[1].cancelled, true)
  assert(notification("patch: cancelled", vim.log.levels.INFO))

  complete_generation(nil, "cancelled")
  eq(mocks.selection.cleared, location)
  eq(notification("patch: cancelled", vim.log.levels.ERROR), nil)
end)

test("cleans up when input closes or generation fails", function()
  patch.start()
  input.close()
  eq(mocks.selection.cleared, location)

  mocks.selection.cleared = nil
  start_and_submit()
  complete_generation(nil, "failed")
  eq(mocks.selection.cleared, location)
  assert(notification("patch: failed", vim.log.levels.ERROR))
end)

test("blocks overlapping workflows", function()
  patch.start()
  patch.start()
  assert(notification("patch: submit or close the active instruction first", vim.log.levels.WARN))

  input.submit("change")
  patch.start()
  assert(notification("patch: a replacement is already being generated", vim.log.levels.WARN))

  complete_generation("replacement", nil)
  patch.start()
  assert(notification("patch: accept or reject the active proposal first", vim.log.levels.WARN))
end)

test("ignores stale completion callbacks", function()
  start_and_submit()
  local stale = requests[1].on_complete
  patch.cancel()
  stale(nil, "cancelled")

  patch.start()
  input.submit("new change")
  stale("stale response", nil)

  eq(mocks.replacement.applied, nil)
  eq(#requests, 2)
end)

test("opens the model menu and records a selection", function()
  patch.open_menu()

  eq(mocks.ui.menu.selected, "provider/current")
  eq(mocks.ui.menu.models[1].id, "model")
  mocks.ui.menu.submit(mocks.ui.menu.models[1])

  assert(notification("patch: using provider/model", vim.log.levels.INFO))
end)

test("warns when actions have no active workflow", function()
  patch.accept()
  patch.reject()
  patch.retry()
  patch.cancel()

  assert(notification("patch: no active proposal to accept", vim.log.levels.WARN))
  assert(notification("patch: no active proposal to reject", vim.log.levels.WARN))
  assert(notification("patch: no active proposal to retry", vim.log.levels.WARN))
  assert(notification("patch: nothing to cancel", vim.log.levels.WARN))
end)
return T
