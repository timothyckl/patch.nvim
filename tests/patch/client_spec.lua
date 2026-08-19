local helpers = require("tests.helpers")

describe("patch.client", function()
  local client
  local rpc
  local connection
  local handlers
  local start_args
  local sent

  before_each(function()
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

    package.loaded["patch.rpc"] = rpc
    package.loaded["patch.client"] = nil
    client = require("patch.client")
    client.setup()
  end)

  after_each(function()
    package.loaded["patch.client"] = nil
    package.loaded["patch.rpc"] = nil
  end)

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

  it("sends a prompt and completes only after the agent settles", function()
    local result = {}
    local request = client.request("replace this", function(value, err)
      record(result, { value = value, err = err })
    end)

    assert.are.equal("pending", request.state)
    assert.are.same({ type = "prompt", message = "replace this" }, sent[1])
    assert.are.same({ "--system-prompt", start_args[2], "--no-session", "--thinking", "off" }, start_args)

    handlers.on_record({ type = "message_end", message = assistant_message("replacement") })
    vim.wait(20)
    assert.is_nil(result.called)

    handlers.on_record({ type = "agent_settled" })
    wait_for_result(result)

    assert.are.equal("replacement", result.value)
    assert.is_nil(result.err)
    assert.are.equal("completed", request.state)
    assert.is_true(connection.closed)
  end)

  it("uses the last assistant message and joins text parts", function()
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

    assert.are.equal("first\nsecond", result.value)
    assert.is_nil(result.err)
  end)

  it("passes configured system prompt and model arguments", function()
    client.setup({ system_prompt = "custom prompt", model = " openai/model " })
    client.request("prompt", function() end)

    assert.are.same({
      "--system-prompt", "custom prompt", "--no-session", "--thinking", "off",
      "--model", "openai/model",
    }, start_args)
  end)

  it("treats empty assistant output as a deletion", function()
    local result = {}
    client.request("prompt", function(value, err)
      record(result, { value = value, err = err })
    end)

    handlers.on_record({ type = "message_end", message = assistant_message("", { content = {} }) })
    handlers.on_record({ type = "agent_settled" })
    wait_for_result(result)

    assert.are.equal("", result.value)
    assert.is_nil(result.err)
  end)

  it("cancels a pending request once", function()
    local result = {}
    local request = client.request("prompt", function(value, err)
      record(result, { value = value, err = err })
    end)

    assert.is_true(client.cancel(request))
    assert.is_false(client.cancel(request))
    wait_for_result(result)

    assert.are.equal("cancelled", request.state)
    assert.are.same({ type = "abort" }, sent[2])
    assert.is_nil(result.value)
    assert.are.equal("cancelled", result.err)

    handlers.on_record({ type = "agent_settled" })
    assert.is_true(connection.closed)
  end)

  it("reports prompt rejection", function()
    local result = {}
    client.request("prompt", function(value, err)
      record(result, { value = value, err = err })
    end)

    handlers.on_record({ type = "response", command = "prompt", success = false, error = "denied" })
    wait_for_result(result)

    assert.is_nil(result.value)
    assert.are.equal("Pi rejected the prompt: denied", result.err)
    assert.is_true(connection.closed)
  end)

  it("reports assistant and missing-response failures", function()
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
    assert.are.equal("model failed", error_result.err)

    client.setup()
    connection.closed = false
    local missing_result = {}
    client.request("prompt", function(_, err)
      record(missing_result, { err = err })
    end)
    handlers.on_record({ type = "agent_settled" })
    wait_for_result(missing_result)
    assert.are.equal("Pi returned no response", missing_result.err)
  end)

  it("reports process start and exit failures", function()
    rpc.start = function()
      return nil, "cannot start"
    end
    local start_result = {}
    client.request("prompt", function(_, err)
      record(start_result, { err = err })
    end)
    wait_for_result(start_result)
    assert.are.equal("cannot start", start_result.err)

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
    assert.are.equal("exit 7", exit_result.err)
  end)

  it("retrieves and validates available models", function()
    local callback
    rpc.request = function(command, on_complete)
      assert.are.same({ type = "get_available_models" }, command)
      callback = on_complete
    end

    local result = {}
    client.get_available_models(function(models, err)
      record(result, { models = models, err = err })
    end)
    local models = { { provider = "openai", id = "model", name = "Model" } }
    callback({ data = { models = models } }, nil)
    wait_for_result(result)
    assert.are.same(models, result.models)

    result = {}
    client.get_available_models(function(value, err)
      record(result, { value = value, err = err })
    end)
    callback({ data = {} }, nil)
    wait_for_result(result)
    assert.is_nil(result.value)
    assert.are.equal("Pi returned an invalid model list", result.err)
  end)

  it("resolves configured, session, and cached primary models", function()
    local result = {}
    client.setup({ model = "configured/model" })
    client.resolve_model(function(value, err)
      record(result, { value = value, err = err })
    end)
    wait_for_result(result)
    assert.are.equal("configured/model", result.value)

    assert.are.equal("provider/session", client.select_model({ provider = "provider", id = "session" }))
    result = {}
    client.resolve_model(function(value)
      record(result, { value = value })
    end)
    wait_for_result(result)
    assert.are.equal("provider/session", result.value)

    local requests = 0
    local state_callback
    rpc.request = function(command, on_complete)
      requests = requests + 1
      assert.are.same({ type = "get_state" }, command)
      state_callback = on_complete
    end
    client.setup()
    result = {}
    client.resolve_model(function(value, err)
      record(result, { value = value, err = err })
    end)
    state_callback({ data = { model = { provider = "primary", id = "model" } } }, nil)
    wait_for_result(result)
    assert.are.equal("primary/model", result.value)

    result = {}
    client.resolve_model(function(value)
      record(result, { value = value })
    end)
    wait_for_result(result)
    assert.are.equal("primary/model", result.value)
    assert.are.equal(1, requests)
  end)
end)
