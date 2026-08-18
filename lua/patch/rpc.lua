local M = {}

---@class PatchRpcConnection
---@field process? vim.SystemObj
---@field closed boolean
---@field send fun(self: PatchRpcConnection, record: table): boolean, string|nil
---@field close fun(self: PatchRpcConnection)

---@class PatchRpcHandlers
---@field on_record fun(record: table)
---@field on_error fun(err: string)
---@field on_exit fun(result: vim.SystemCompleted)

--- Create a callback that decodes newline-delimited JSON records.
---
---@param on_record fun(record: table)
---@param on_error fun(err: string)
---@return fun(error_message: string|nil, data: string|nil)
local function read_jsonl(on_record, on_error)
  local buffer = ""
  local stopped = false

  local function emit(line)
    line = line:gsub("\r$", "")
    if line == "" then
      return true
    end

    local decoded, record = pcall(vim.json.decode, line)
    if not decoded then
      stopped = true
      on_error("Failed to decode Pi output: " .. record)
      return false
    end

    on_record(record)
    return true
  end

  return function(error_message, data)
    if stopped then
      return
    end

    if error_message then
      stopped = true
      on_error("Failed to read Pi output: " .. error_message)
      return
    end

    buffer = buffer .. (data or "")

    while true do
      local newline = buffer:find("\n", 1, true)
      if not newline then
        break
      end

      local line = buffer:sub(1, newline - 1)
      buffer = buffer:sub(newline + 1)

      if not emit(line) then
        return
      end
    end

    if data == nil and buffer ~= "" then
      local line = buffer
      buffer = ""
      emit(line)
    end
  end
end

--- Format a non-zero Pi process result, including captured stderr when available.
---
---@param result vim.SystemCompleted
---@return string message
function M.format_exit_error(result)
  local message = "Pi exited with code " .. result.code
  local stderr = vim.trim(result.stderr or "")

  if stderr ~= "" then
    return message .. ": " .. stderr
  end

  return message
end

--- Start a Pi RPC connection.
---
---@param args string[] additional Pi command arguments
---@param handlers PatchRpcHandlers
---@return PatchRpcConnection|nil connection
---@return string|nil error_message
function M.start(args, handlers)
  local connection = {
    process = nil,
    closed = false,
  }

  function connection:send(record)
    if self.closed or not self.process then
      return false, "Pi connection is closed"
    end

    local sent, write_error = pcall(function()
      self.process:write(vim.json.encode(record) .. "\n")
    end)

    if not sent then
      return false, tostring(write_error)
    end

    return true, nil
  end

  function connection:close()
    if self.closed then
      return
    end

    self.closed = true
    local process = self.process
    self.process = nil

    if process then
      pcall(process.write, process, nil)
    end
  end

  local function handle_error(err)
    connection:close()
    handlers.on_error(err)
  end

  local handle_stdout = read_jsonl(handlers.on_record, handle_error)
  local command = { "pi", "--mode", "rpc" }
  vim.list_extend(command, args)

  local started, process_or_error = pcall(
    vim.system,
    command,
    { stdin = true, stdout = handle_stdout },
    function(result)
      connection.process = nil
      connection.closed = true
      handlers.on_exit(result)
    end
  )

  if not started then
    connection.closed = true
    return nil, "Failed to start Pi: " .. tostring(process_or_error)
  end

  connection.process = process_or_error
  return connection, nil
end

--- Run a one-shot Pi RPC command and return its response.
---
---@param command table
---@param on_complete fun(record: table|nil, err: string|nil)
function M.request(command, on_complete)
  command = vim.deepcopy(command)
  command.id = command.id or command.type

  local connection
  local connection_error
  local completed = false

  local function complete(record, err)
    if completed then
      return
    end

    completed = true
    if connection then
      connection:close()
    end
    on_complete(record, err)
  end

  connection, connection_error = M.start({ "--no-session" }, {
    on_record = function(record)
      if record.type ~= "response" or record.command ~= command.type or record.id ~= command.id then
        return
      end

      if not record.success then
        complete(nil, "Pi rejected " .. command.type .. ": " .. tostring(record.error))
        return
      end

      complete(record, nil)
    end,
    on_error = function(err)
      complete(nil, err)
    end,
    on_exit = function(result)
      if completed then
        return
      end

      if result.code ~= 0 then
        complete(nil, M.format_exit_error(result))
      else
        complete(nil, "Pi exited before returning " .. command.type)
      end
    end,
  })

  if not connection then
    complete(nil, tostring(connection_error))
    return
  end

  local sent, write_error = connection:send(command)
  if not sent then
    complete(nil, "Failed to send " .. command.type .. " to Pi: " .. tostring(write_error))
  end
end

return M
