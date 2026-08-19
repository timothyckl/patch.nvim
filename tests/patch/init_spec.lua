describe("patch workflow", function()
  local patch
  local mocks
  local notifications
  local input
  local requests
  local proposal
  local location

  before_each(function()
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
          assert.are.equal(location, value)
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
  end)

  after_each(function()
    for _, name in ipairs({
      "patch", "patch.prompt", "patch.selection", "patch.context", "patch.client",
      "patch.replacement", "patch.ui", "patch.notify",
    }) do
      package.loaded[name] = nil
    end
  end)

  local function notification(message, level)
    for _, item in ipairs(notifications) do
      if item.message == message and (not level or item.level == level) then
        return item
      end
    end
  end

  local function start_and_submit()
    patch.start()
    assert.is_table(input)
    input.submit("change it")
    assert.are.equal(1, #requests)
  end

  local function complete_generation(response, err)
    requests[#requests].on_complete(response, err)
  end

  it("passes configuration to notification and client modules", function()
    local provider = function() end
    patch.setup({ notify = provider, system_prompt = "system", model = "provider/model" })

    assert.are.equal(provider, mocks.notify.provider)
    assert.are.same({ system_prompt = "system", model = "provider/model" }, mocks.client.setup_options)
  end)

  it("runs capture, generation, review, and acceptance", function()
    start_and_submit()

    assert.are.equal("built:change it", requests[1].message)
    assert.is_truthy(notification("patch: generating...", vim.log.levels.INFO))

    complete_generation("replacement", nil)
    assert.are.same({ location, "replacement" }, mocks.replacement.applied)
    assert.is_truthy(notification("patch: complete", vim.log.levels.INFO))

    patch.accept()
    assert.are.equal(proposal, mocks.replacement.accepted)

    patch.accept()
    assert.is_truthy(notification("patch: no active proposal to accept", vim.log.levels.WARN))
  end)

  it("rejects a reviewed proposal", function()
    start_and_submit()
    complete_generation("replacement", nil)

    patch.reject()

    assert.are.equal(proposal, mocks.replacement.rejected)
    patch.reject()
    assert.is_truthy(notification("patch: no active proposal to reject", vim.log.levels.WARN))
  end)

  it("retries a proposal and applies the new response", function()
    start_and_submit()
    complete_generation("first", nil)

    patch.retry()
    assert.are.equal(proposal, mocks.replacement.retry_started)
    assert.are.equal(2, #requests)

    complete_generation("second", nil)
    assert.are.same({ proposal, "second" }, mocks.replacement.retry_completed)
    assert.is_truthy(notification("patch: complete", vim.log.levels.INFO))
  end)

  it("aborts a failed retry and reports the error", function()
    start_and_submit()
    complete_generation("first", nil)
    patch.retry()

    complete_generation(nil, "request failed")

    assert.are.equal(proposal, mocks.replacement.retry_aborted)
    assert.is_truthy(notification("patch: request failed", vim.log.levels.ERROR))
  end)

  it("cancels an active request and suppresses the cancellation error", function()
    start_and_submit()

    patch.cancel()
    assert.is_true(requests[1].cancelled)
    assert.is_truthy(notification("patch: cancelled", vim.log.levels.INFO))

    complete_generation(nil, "cancelled")
    assert.are.equal(location, mocks.selection.cleared)
    assert.is_nil(notification("patch: cancelled", vim.log.levels.ERROR))
  end)

  it("cleans up when input closes or generation fails", function()
    patch.start()
    input.close()
    assert.are.equal(location, mocks.selection.cleared)

    mocks.selection.cleared = nil
    start_and_submit()
    complete_generation(nil, "failed")
    assert.are.equal(location, mocks.selection.cleared)
    assert.is_truthy(notification("patch: failed", vim.log.levels.ERROR))
  end)

  it("blocks overlapping workflows", function()
    patch.start()
    patch.start()
    assert.is_truthy(notification("patch: submit or close the active instruction first", vim.log.levels.WARN))

    input.submit("change")
    patch.start()
    assert.is_truthy(notification("patch: a replacement is already being generated", vim.log.levels.WARN))

    complete_generation("replacement", nil)
    patch.start()
    assert.is_truthy(notification("patch: accept or reject the active proposal first", vim.log.levels.WARN))
  end)

  it("ignores stale completion callbacks", function()
    start_and_submit()
    local stale = requests[1].on_complete
    patch.cancel()
    stale(nil, "cancelled")

    patch.start()
    input.submit("new change")
    stale("stale response", nil)

    assert.is_nil(mocks.replacement.applied)
    assert.are.equal(2, #requests)
  end)

  it("opens the model menu and records a selection", function()
    patch.open_menu()

    assert.are.equal("provider/current", mocks.ui.menu.selected)
    assert.are.equal("model", mocks.ui.menu.models[1].id)
    mocks.ui.menu.submit(mocks.ui.menu.models[1])

    assert.is_truthy(notification("patch: using provider/model", vim.log.levels.INFO))
  end)

  it("warns when actions have no active workflow", function()
    patch.accept()
    patch.reject()
    patch.retry()
    patch.cancel()

    assert.is_truthy(notification("patch: no active proposal to accept", vim.log.levels.WARN))
    assert.is_truthy(notification("patch: no active proposal to reject", vim.log.levels.WARN))
    assert.is_truthy(notification("patch: no active proposal to retry", vim.log.levels.WARN))
    assert.is_truthy(notification("patch: nothing to cancel", vim.log.levels.WARN))
  end)
end)
