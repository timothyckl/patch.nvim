local eq = MiniTest.expect.equality
local generation
local requests

local function reset()
  requests = {}

  package.loaded["patch.pi.client"] = {
    request = function(message, on_complete)
      local request = { message = message, on_complete = on_complete }
      table.insert(requests, request)
      return request
    end,
    cancel = function(request)
      request.cancelled = true
      return true
    end,
  }
  package.loaded["patch.pi.prompt"] = {
    build = function(_, instruction)
      return "built:" .. instruction
    end,
  }
  package.loaded["patch.core.generation"] = nil
  generation = require("patch.core.generation")
end

local function cleanup()
  for _, name in ipairs({
    "patch.core.generation", "patch.pi.client", "patch.pi.prompt",
  }) do
    package.loaded[name] = nil
  end
end

local T = MiniTest.new_set({ hooks = { pre_case = reset, post_case = cleanup } })

T["builds prompts and completes current requests"] = function()
  local workflow = { phase = "input", message = "message" }
  local applied
  local completed = false

  eq(generation.build({}, "change it"), "built:change it")
  generation.run(workflow, "generating", {
    is_current = function(request)
      return workflow.request == request
    end,
    apply_response = function(response)
      applied = response
      return {}
    end,
    on_failure = function() error("unexpected failure") end,
    on_complete = function() completed = true end,
  })

  eq(workflow.phase, "generating")
  eq(requests[1].message, "message")
  requests[1].on_complete("replacement", nil)

  eq(applied, "replacement")
  eq(workflow.request, nil)
  eq(workflow.phase, "reviewing")
  eq(completed, true)
end

T["reports request and application failures"] = function()
  local workflow = { phase = "input", message = "message" }
  local failures = {}
  local apply_result = nil
  local apply_error = "invalid replacement"

  local function run()
    generation.run(workflow, "retrying", {
      is_current = function() return true end,
      apply_response = function() return apply_result, apply_error end,
      on_failure = function(err, kind)
        table.insert(failures, { err, kind })
      end,
      on_complete = function() error("unexpected completion") end,
    })
  end

  run()
  requests[1].on_complete(nil, "request failed")
  eq(failures[1], { "request failed", "request" })

  run()
  requests[2].on_complete("replacement", nil)
  eq(failures[2], { "invalid replacement", "application" })
end

T["ignores stale completions"] = function()
  local workflow = { phase = "input", message = "message" }
  local called = false

  generation.run(workflow, "generating", {
    is_current = function() return false end,
    apply_response = function() called = true end,
    on_failure = function() called = true end,
    on_complete = function() called = true end,
  })
  requests[1].on_complete("replacement", nil)

  eq(called, false)
  eq(workflow.request, requests[1])
  eq(workflow.phase, "generating")
end

T["delegates cancellation"] = function()
  local request = {}

  eq(generation.cancel(request), true)
  eq(request.cancelled, true)
end

return T
