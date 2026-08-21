local eq = MiniTest.expect.equality
local rpc
local original_system

local function reset()
  package.loaded["patch.pi.rpc"] = nil
  rpc = require("patch.pi.rpc")
  original_system = vim.system
end

local function cleanup()
  vim.system = original_system
end

local T = MiniTest.new_set({ hooks = { pre_case = reset, post_case = cleanup } })

local function test(name, action)
  T[name] = action
end

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

test("starts Pi in RPC mode and sends JSONL records", function()
  local invocation = fake_system()
  local connection = assert(rpc.start({ "--no-session" }, {
    on_record = function() end,
    on_error = function() end,
    on_exit = function() end,
  }))

  eq(invocation.command, {
    "pi",
    "--mode", "rpc",
    "--no-context-files",
    "--no-skills",
    "--no-extensions",
    "--no-prompt-templates",
    "--no-themes",
    "--no-tools",
    "--no-approve",
    "--append-system-prompt", "",
    "--no-session",
  })
  eq(invocation.options.stdin, true)
  eq(type(invocation.options.stdout), "function")
  eq(connection:send({ type = "prompt", message = "hello" }), true)

  local sent = vim.json.decode(invocation.process.writes[1])
  eq(sent, { type = "prompt", message = "hello" })
end)

test("decodes records split across stdout chunks", function()
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

  eq(records, { { type = "first" }, { type = "second" } })
end)

test("decodes a final record without a newline", function()
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

  eq(records, { { type = "final" } })
end)

test("reports malformed JSON once and closes the connection", function()
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

  eq(#errors, 1)
  assert(errors[1]:find("Failed to decode Pi output:", 1, true))
  eq(connection.closed, true)
end)

test("reports stdout errors", function()
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

  eq(received, "Failed to read Pi output: broken pipe")
end)

test("closes idempotently and rejects later writes", function()
  local invocation = fake_system()
  local connection = assert(rpc.start({}, {
    on_record = function() end,
    on_error = function() end,
    on_exit = function() end,
  }))

  connection:close()
  connection:close()
  local sent, err = connection:send({ type = "prompt" })

  eq(sent, false)
  eq(err, "Pi connection is closed")
  eq(#invocation.process.writes, 1)
  eq(invocation.process.writes[1], vim.NIL)
end)

test("reports process start failures", function()
  vim.system = function()
    error("not executable")
  end

  local connection, err = rpc.start({}, {
    on_record = function() end,
    on_error = function() end,
    on_exit = function() end,
  })

  eq(connection, nil)
  assert(err:find("Failed to start Pi:", 1, true))
  assert(err:find("not executable", 1, true))
end)

test("formats process errors with trimmed stderr", function()
  eq(rpc.format_exit_error({ code = 3, stderr = "  failure\n" }), "Pi exited with code 3: failure")
  eq(rpc.format_exit_error({ code = 2, stderr = "" }), "Pi exited with code 2")
end)

local handlers
local connection
local sent

local function reset_one_shot()
  connection = { closed = false }
  function connection:send(record)
    sent = record
    return true
  end
  function connection:close()
    self.closed = true
  end

  rpc.start = function(args, supplied_handlers)
    eq(args, { "--no-session" })
    handlers = supplied_handlers
    return connection
  end
end

local one_shot = MiniTest.new_set({ hooks = { pre_case = reset_one_shot } })
T["one-shot requests"] = one_shot
local function one_shot_test(name, action)
  one_shot[name] = action
end

one_shot_test("matches the command and request id", function()
  local result
  rpc.request({ type = "get_state" }, function(record, err)
    result = { record, err }
  end)

  eq(sent, { type = "get_state", id = "get_state" })
  handlers.on_record({ type = "event" })
  eq(result, nil)
  handlers.on_record({ type = "response", command = "get_state", id = "other", success = true })
  eq(result, nil)

  local record = { type = "response", command = "get_state", id = "get_state", success = true }
  handlers.on_record(record)
  eq(result[1], record)
  eq(result[2], nil)
  eq(connection.closed, true)
end)

one_shot_test("reports a rejected command", function()
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

  eq(received, "Pi rejected get_state: denied")
end)

one_shot_test("reports an early process exit", function()
  local received
  rpc.request({ type = "get_state" }, function(_, err)
    received = err
  end)

  handlers.on_exit({ code = 0, stderr = "" })

  eq(received, "Pi exited before returning get_state")
end)

one_shot_test("completes only once", function()
  local completions = 0
  rpc.request({ type = "get_state" }, function()
    completions = completions + 1
  end)

  handlers.on_error("failed")
  handlers.on_exit({ code = 1, stderr = "later" })

  eq(completions, 1)
end)
return T
