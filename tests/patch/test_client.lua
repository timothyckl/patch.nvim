local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

local function is_nil(value)
  eq(value, nil)
end

local function is_true(value)
  eq(value, true)
end

local function is_false(value)
  eq(value, false)
end

local client
local rpc
local connection
local handlers
local start_args
local sent

local function reset()
  sent = {}
  connection = { closed = false }
  function connection:send(record)
    table.insert(sent, record)
    return true
  end
  function connection:close()
    self.closed = true
  end

  rpc = {
    start = function(args, supplied_handlers)
      start_args = args
      handlers = supplied_handlers
      return connection
    end,
    request = function() end,
    format_exit_error = function(result)
      return "exit " .. result.code
    end,
  }

  package.loaded["patch.pi.rpc"] = rpc
  package.loaded["patch.pi.client"] = nil
  client = require("patch.pi.client")
  client.setup()
end

local function cleanup()
  package.loaded["patch.pi.client"] = nil
  package.loaded["patch.pi.rpc"] = nil
end

local T = MiniTest.new_set({ hooks = { pre_case = reset, post_case = cleanup } })

local function test(name, action)
  T[name] = action
end

local function wait_for_result(result)
  helpers.wait_for(function()
    return result.called
  end)
end

local function record(result, values)
  result.called = true
  for key, value in pairs(values) do
    result[key] = value
  end
end

local function assistant_message(text, overrides)
  return vim.tbl_extend("force", {
    role = "assistant",
    content = { { type = "text", text = text } },
    stopReason = "stop",
  }, overrides or {})
end

test("sends a prompt and completes only after the agent settles", function()
  local result = {}
  local request = client.request("replace this", function(value, err)
    record(result, { value = value, err = err })
  end)

  eq(request.state, "pending")
  eq(sent[1], { type = "prompt", message = "replace this" })
  eq(start_args, { "--system-prompt", start_args[2], "--no-session", "--thinking", "off" })

  handlers.on_record({ type = "message_end", message = assistant_message("replacement") })
  vim.wait(20)
  is_nil(result.called)

  handlers.on_record({ type = "agent_settled" })
  wait_for_result(result)

  eq(result.value, "replacement")
  is_nil(result.err)
  eq(request.state, "completed")
  is_true(connection.closed)
end)

test("uses the last assistant message and joins text parts", function()
  local result = {}
  client.request("prompt", function(value, err)
    record(result, { value = value, err = err })
  end)

  handlers.on_record({ type = "message_end", message = assistant_message("discarded") })
  handlers.on_record({
    type = "message_end",
    message = assistant_message("ignored", {
      content = {
        { type = "text", text = "first" },
        { type = "toolCall", name = "tool" },
        { type = "text", text = "second" },
      },
    }),
  })
  handlers.on_record({ type = "agent_settled" })
  wait_for_result(result)

  eq(result.value, "first\nsecond")
  is_nil(result.err)
end)

test("passes configured system prompt and model arguments", function()
  client.setup({ system_prompt = "custom prompt", model = " openai/model " })
  client.request("prompt", function() end)

  eq(start_args, {
    "--system-prompt", "custom prompt", "--no-session", "--thinking", "off",
    "--model", "openai/model",
  })
end)

test("treats empty assistant output as a deletion", function()
  local result = {}
  client.request("prompt", function(value, err)
    record(result, { value = value, err = err })
  end)

  handlers.on_record({ type = "message_end", message = assistant_message("", { content = {} }) })
  handlers.on_record({ type = "agent_settled" })
  wait_for_result(result)

  eq(result.value, "")
  is_nil(result.err)
end)

test("cancels a pending request once", function()
  local result = {}
  local request = client.request("prompt", function(value, err)
    record(result, { value = value, err = err })
  end)

  is_true(client.cancel(request))
  is_false(client.cancel(request))
  wait_for_result(result)

  eq(request.state, "cancelled")
  eq(sent[2], { type = "abort" })
  is_nil(result.value)
  eq(result.err, "cancelled")

  handlers.on_record({ type = "agent_settled" })
  is_true(connection.closed)
end)

test("reports prompt rejection", function()
  local result = {}
  client.request("prompt", function(value, err)
    record(result, { value = value, err = err })
  end)

  handlers.on_record({ type = "response", command = "prompt", success = false, error = "denied" })
  wait_for_result(result)

  is_nil(result.value)
  eq(result.err, "Pi rejected the prompt: denied")
  is_true(connection.closed)
end)

test("reports assistant and missing-response failures", function()
  local error_result = {}
  client.request("prompt", function(_, err)
    record(error_result, { err = err })
  end)
  handlers.on_record({
    type = "message_end",
    message = assistant_message("", { stopReason = "error", errorMessage = "model failed" }),
  })
  handlers.on_record({ type = "agent_settled" })
  wait_for_result(error_result)
  eq(error_result.err, "model failed")

  client.setup()
  connection.closed = false
  local missing_result = {}
  client.request("prompt", function(_, err)
    record(missing_result, { err = err })
  end)
  handlers.on_record({ type = "agent_settled" })
  wait_for_result(missing_result)
  eq(missing_result.err, "Pi returned no response")
end)

test("reports process start and exit failures", function()
  rpc.start = function()
    return nil, "cannot start"
  end
  local start_result = {}
  client.request("prompt", function(_, err)
    record(start_result, { err = err })
  end)
  wait_for_result(start_result)
  eq(start_result.err, "cannot start")

  rpc.start = function(args, supplied_handlers)
    handlers = supplied_handlers
    return connection
  end
  local exit_result = {}
  client.request("prompt", function(_, err)
    record(exit_result, { err = err })
  end)
  handlers.on_exit({ code = 7 })
  wait_for_result(exit_result)
  eq(exit_result.err, "exit 7")
end)

test("retrieves and validates available models", function()
  local callback
  rpc.request = function(command, on_complete)
    eq(command, { type = "get_available_models" })
    callback = on_complete
  end

  local result = {}
  client.get_available_models(function(models, err)
    record(result, { models = models, err = err })
  end)
  local models = { { provider = "openai", id = "model", name = "Model" } }
  callback({ data = { models = models } }, nil)
  wait_for_result(result)
  eq(result.models, models)

  result = {}
  client.get_available_models(function(value, err)
    record(result, { value = value, err = err })
  end)
  callback({ data = {} }, nil)
  wait_for_result(result)
  is_nil(result.value)
  eq(result.err, "Pi returned an invalid model list")
end)

test("resolves configured, session, and cached primary models", function()
  local result = {}
  client.setup({ model = "configured/model" })
  client.resolve_model(function(value, err)
    record(result, { value = value, err = err })
  end)
  wait_for_result(result)
  eq(result.value, "configured/model")

  eq(client.select_model({ provider = "provider", id = "session" }), "provider/session")
  result = {}
  client.resolve_model(function(value)
    record(result, { value = value })
  end)
  wait_for_result(result)
  eq(result.value, "provider/session")

  local requests = 0
  local state_callback
  rpc.request = function(command, on_complete)
    requests = requests + 1
    eq(command, { type = "get_state" })
    state_callback = on_complete
  end
  client.setup()
  result = {}
  client.resolve_model(function(value, err)
    record(result, { value = value, err = err })
  end)
  state_callback({ data = { model = { provider = "primary", id = "model" } } }, nil)
  wait_for_result(result)
  eq(result.value, "primary/model")

  result = {}
  client.resolve_model(function(value)
    record(result, { value = value })
  end)
  wait_for_result(result)
  eq(result.value, "primary/model")
  eq(requests, 1)
end)
return T
