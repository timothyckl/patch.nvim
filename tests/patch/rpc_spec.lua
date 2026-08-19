describe("patch.rpc", function()
  local rpc
  local original_system

  before_each(function()
    package.loaded["patch.rpc"] = nil
    rpc = require("patch.rpc")
    original_system = vim.system
  end)

  after_each(function()
    vim.system = original_system
  end)

  local function fake_system()
    local invocation = {}
    local process = { writes = {} }

    function process:write(value)
      table.insert(self.writes, value == nil and vim.NIL or value)
    end

    vim.system = function(command, options, on_exit)
      invocation.command = command
      invocation.options = options
      invocation.on_exit = on_exit
      invocation.process = process
      return process
    end

    return invocation
  end

  it("starts Pi in RPC mode and sends JSONL records", function()
    local invocation = fake_system()
    local connection = assert(rpc.start({ "--no-session" }, {
      on_record = function() end,
      on_error = function() end,
      on_exit = function() end,
    }))

    assert.are.same({ "pi", "--mode", "rpc", "--no-session" }, invocation.command)
    assert.is_true(invocation.options.stdin)
    assert.is_function(invocation.options.stdout)
    assert.is_true(connection:send({ type = "prompt", message = "hello" }))

    local sent = vim.json.decode(invocation.process.writes[1])
    assert.are.same({ type = "prompt", message = "hello" }, sent)
  end)

  it("decodes records split across stdout chunks", function()
    local invocation = fake_system()
    local records = {}
    assert(rpc.start({}, {
      on_record = function(record)
        table.insert(records, record)
      end,
      on_error = function() end,
      on_exit = function() end,
    }))

    invocation.options.stdout(nil, '{"type":"fir')
    invocation.options.stdout(nil, 'st"}\n{"type":"second"}\n')

    assert.are.same({ { type = "first" }, { type = "second" } }, records)
  end)

  it("decodes a final record without a newline", function()
    local invocation = fake_system()
    local records = {}
    assert(rpc.start({}, {
      on_record = function(record)
        table.insert(records, record)
      end,
      on_error = function() end,
      on_exit = function() end,
    }))

    invocation.options.stdout(nil, '{"type":"final"}')
    invocation.options.stdout(nil, nil)

    assert.are.same({ { type = "final" } }, records)
  end)

  it("reports malformed JSON once and closes the connection", function()
    local invocation = fake_system()
    local errors = {}
    local connection = assert(rpc.start({}, {
      on_record = function() end,
      on_error = function(err)
        table.insert(errors, err)
      end,
      on_exit = function() end,
    }))

    invocation.options.stdout(nil, "not-json\n")
    invocation.options.stdout(nil, "still-not-json\n")

    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find("Failed to decode Pi output:", 1, true))
    assert.is_true(connection.closed)
  end)

  it("reports stdout errors", function()
    local invocation = fake_system()
    local received
    assert(rpc.start({}, {
      on_record = function() end,
      on_error = function(err)
        received = err
      end,
      on_exit = function() end,
    }))

    invocation.options.stdout("broken pipe", nil)

    assert.are.equal("Failed to read Pi output: broken pipe", received)
  end)

  it("closes idempotently and rejects later writes", function()
    local invocation = fake_system()
    local connection = assert(rpc.start({}, {
      on_record = function() end,
      on_error = function() end,
      on_exit = function() end,
    }))

    connection:close()
    connection:close()
    local sent, err = connection:send({ type = "prompt" })

    assert.is_false(sent)
    assert.are.equal("Pi connection is closed", err)
    assert.are.equal(1, #invocation.process.writes)
    assert.are.equal(vim.NIL, invocation.process.writes[1])
  end)

  it("reports process start failures", function()
    vim.system = function()
      error("not executable")
    end

    local connection, err = rpc.start({}, {
      on_record = function() end,
      on_error = function() end,
      on_exit = function() end,
    })

    assert.is_nil(connection)
    assert.is_truthy(err:find("Failed to start Pi:", 1, true))
    assert.is_truthy(err:find("not executable", 1, true))
  end)

  it("formats process errors with trimmed stderr", function()
    assert.are.equal("Pi exited with code 3: failure", rpc.format_exit_error({ code = 3, stderr = "  failure\n" }))
    assert.are.equal("Pi exited with code 2", rpc.format_exit_error({ code = 2, stderr = "" }))
  end)

  describe("one-shot requests", function()
    local handlers
    local connection
    local sent

    before_each(function()
      connection = { closed = false }
      function connection:send(record)
        sent = record
        return true
      end
      function connection:close()
        self.closed = true
      end

      rpc.start = function(args, supplied_handlers)
        assert.are.same({ "--no-session" }, args)
        handlers = supplied_handlers
        return connection
      end
    end)

    it("matches the command and request id", function()
      local result
      rpc.request({ type = "get_state" }, function(record, err)
        result = { record, err }
      end)

      assert.are.same({ type = "get_state", id = "get_state" }, sent)
      handlers.on_record({ type = "event" })
      assert.is_nil(result)
      handlers.on_record({ type = "response", command = "get_state", id = "other", success = true })
      assert.is_nil(result)

      local record = { type = "response", command = "get_state", id = "get_state", success = true }
      handlers.on_record(record)
      assert.are.equal(record, result[1])
      assert.is_nil(result[2])
      assert.is_true(connection.closed)
    end)

    it("reports a rejected command", function()
      local received
      rpc.request({ type = "get_state" }, function(_, err)
        received = err
      end)

      handlers.on_record({
        type = "response",
        command = "get_state",
        id = "get_state",
        success = false,
        error = "denied",
      })

      assert.are.equal("Pi rejected get_state: denied", received)
    end)

    it("reports an early process exit", function()
      local received
      rpc.request({ type = "get_state" }, function(_, err)
        received = err
      end)

      handlers.on_exit({ code = 0, stderr = "" })

      assert.are.equal("Pi exited before returning get_state", received)
    end)

    it("completes only once", function()
      local completions = 0
      rpc.request({ type = "get_state" }, function()
        completions = completions + 1
      end)

      handlers.on_error("failed")
      handlers.on_exit({ code = 1, stderr = "later" })

      assert.are.equal(1, completions)
    end)
  end)
end)
