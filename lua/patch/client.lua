local M = {}
local notify = require("patch.notify")

local DEFAULT_SYSTEM_PROMPT = "You are an inline code editor. Given the selection and an instruction, reply with only the replacement code for the SELECTED region. No commentary, no explanations, no markdown fences."
local system_prompt = DEFAULT_SYSTEM_PROMPT
local configured_model
local session_model
local primary_model

---@class PatchClientOptions
---@field system_prompt? string
---@field model? string

---@param opts? PatchClientOptions
function M.setup(opts)
  opts = opts or {}
  system_prompt = opts.system_prompt or DEFAULT_SYSTEM_PROMPT
  configured_model = opts.model and vim.trim(opts.model) or nil
  configured_model = configured_model ~= "" and configured_model or nil
  session_model = nil
  primary_model = nil
end

---@class PatchModel
---@field id string
---@field name string
---@field provider string

--- Create a callback that decodes newline-delimited JSON records.
---
---@param on_record fun(record: table)
---@param on_error fun(err: string)
---@return fun(error_message: string|nil, data: string|nil)
local function read_jsonl(on_record, on_error)
  local buffer = ""
  local stopped = false

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
        return
      end

      local line = buffer:sub(1, newline - 1):gsub("\r$", "")
      buffer = buffer:sub(newline + 1)

      if line ~= "" then
        local decoded, record = pcall(vim.json.decode, line)

        if not decoded then
          stopped = true
          on_error("Failed to decode Pi output: " .. record)
          return
        end

        on_record(record)
      end
    end
  end
end

--- Run a one-shot Pi RPC command and return its response.
---
---@param command table
---@param on_complete fun(record: table|nil, err: string|nil)
local function request_rpc(command, on_complete)
  local process
  local completed = false

  command.id = command.id or command.type

  local function close_process()
    local current_process = process
    process = nil

    if current_process then
      pcall(current_process.write, current_process, nil)
    end
  end

  ---@param record table|nil
  ---@param err string|nil
  local function complete(record, err)
    if completed then
      return
    end

    completed = true
    close_process()

    vim.schedule(function()
      on_complete(record, err)
    end)
  end

  ---@param result vim.SystemCompleted
  local function handle_exit(result)
    process = nil

    if completed then
      return
    end

    if result.code ~= 0 then
      complete(nil, "Pi exited with code " .. result.code)
    else
      complete(nil, "Pi exited before returning " .. command.type)
    end
  end

  ---@param record table
  local function handle_record(record)
    if record.type ~= "response" or record.command ~= command.type or record.id ~= command.id then
      return
    end

    if not record.success then
      complete(nil, "Pi rejected " .. command.type .. ": " .. tostring(record.error))
      return
    end

    complete(record, nil)
  end

  local handle_stdout = read_jsonl(handle_record, function(err)
    complete(nil, err)
  end)

  local started, process_or_error = pcall(vim.system,
    { "pi", "--mode", "rpc", "--no-session" },
    { stdin = true, stdout = handle_stdout },
    handle_exit
  )

  if not started then
    complete(nil, "Failed to start Pi: " .. tostring(process_or_error))
    return
  end

  process = process_or_error

  local sent, write_error = pcall(function()
    process:write(vim.json.encode(command) .. "\n")
  end)

  if not sent then
    complete(nil, "Failed to send " .. command.type .. " to Pi: " .. tostring(write_error))
  end
end

---@class PatchRequest
---@field state "pending"|"cancelled"|"completed"
---@field process? vim.SystemObj
---@field on_complete fun(res: string|nil, err: string|nil)

--- Abort a Pi request.
---
---@param request PatchRequest
---@return boolean cancelled
function M.cancel(request)
  if request.state ~= "pending" then
    return false
  end

  request.state = "cancelled"

  if request.process then
    pcall(
      request.process.write,
      request.process,
      vim.json.encode({ type = "abort" }) .. "\n"
    )
  end

  vim.schedule(function()
    request.on_complete(nil, "cancelled")
  end)

  return true
end

-- TODO: Cache available models per session to avoid RPC startup latency on every menu open.
--- Retrieve the models available to Pi.
---
---@param on_complete fun(models: PatchModel[]|nil, err: string|nil)
function M.get_available_models(on_complete)
  request_rpc({ type = "get_available_models" }, function(record, err)
    if err then
      on_complete(nil, err)
      return
    end

    if type(record.data) ~= "table" or type(record.data.models) ~= "table" then
      on_complete(nil, "Pi returned an invalid model list")
      return
    end

    on_complete(record.data.models, nil)
  end)
end

--- Use a model for the remainder of the current Neovim session.
---
---@param model PatchModel
---@return string selector
function M.select_model(model)
  session_model = model.provider .. "/" .. model.id
  return session_model
end

--- Resolve the model label used by Patch.
---
---@param on_complete fun(model: string|nil, err: string|nil)
function M.resolve_model(on_complete)
  local override = session_model or configured_model
  if override then
    vim.schedule(function()
      on_complete(override, nil)
    end)
    return
  end

  if primary_model then
    vim.schedule(function()
      on_complete(primary_model, nil)
    end)
    return
  end

  request_rpc({ type = "get_state" }, function(record, err)
    if err then
      on_complete(nil, err)
      return
    end

    local model = type(record.data) == "table" and record.data.model or nil
    if type(model) ~= "table" or type(model.provider) ~= "string" or type(model.id) ~= "string" then
      on_complete(nil, "Pi returned no primary model")
      return
    end

    primary_model = model.provider .. "/" .. model.id
    on_complete(primary_model, nil)
  end)
end

--- Send a prompt to Pi and deliver its final assistant text.
---
--- @param message string prompt containing the selection and surrounding context
--- @param on_complete fun(res: string|nil, err: string|nil)
--- @return PatchRequest request
function M.request(message, on_complete)
  local request = {
    state = "pending",
    process = nil,
    on_complete = on_complete,
  }

  local assistant_text

  notify.send("patch: generating...", vim.log.levels.INFO)

  --- Schedule a message for display on Neovim's main event loop.
  ---
  --- @param message string
  local function display(message)
    vim.schedule(function()
      notify.send(message, vim.log.levels.ERROR)
    end)
  end

  --- Complete this request exactly once on Neovim's main event loop.
  ---
  --- @param res string|nil
  --- @param err string|nil
  local function complete(res, err)
    if request.state ~= "pending" then
      return
    end

    request.state = "completed"

    vim.schedule(function()
      request.on_complete(res, err)
    end)
  end

  --- Report a request failure and complete it.
  ---
  --- @param err string
  local function fail(err)
    if request.state ~= "pending" then
      return
    end

    complete(nil, err)
    display(err)
  end

  --- Join the text parts of an assistant message.
  ---
  --- @param message table Pi assistant message
  --- @return string text
  local function extract_text(message)
    local parts = {}

    for _, content in ipairs(message.content) do
      if content.type == "text" then
        table.insert(parts, content.text)
      end
    end

    return table.concat(parts, "\n")
  end

  --- Clear references to this request's process.
  local function clear_process()
    request.process = nil
  end

  --- Close the process input stream and clear its references.
  local function close_process()
    local current_process = request.process

    clear_process()

    if current_process then
      pcall(current_process.write, current_process, nil)
    end
  end

  --- Report an unexpected process failure and release the process.
  ---
  --- @param result vim.SystemCompleted
  local function handle_exit(result)
    clear_process()

    if request.state == "pending" then
      if result.code ~= 0 then
        fail("Pi exited with code " .. result.code)
      else
        fail("Pi exited before returning a response")
      end
    end
  end

  --- Handle a decoded record from Pi's JSONL output.
  ---
  --- @param record table
  local function handle_record(record)
    if request.state == "cancelled" then
      if record.type == "agent_settled" then
        close_process()
      end

      return
    end

    if record.type == "response" and record.command == "prompt" and not record.success then
      fail("Pi rejected the prompt: " .. record.error)
      close_process()
      return
    end

    if record.type == "message_end" and record.message.role == "assistant" then
      assistant_text = extract_text(record.message)
      return
    end

    if record.type == "agent_settled" then
      local replacement = assistant_text

      if replacement == nil then
        fail("Pi returned no response")
      else
        complete(replacement, nil)
      end

      close_process()
      return
    end
  end

  local handle_stdout = read_jsonl(handle_record, function(err)
    if request.state == "pending" then
      fail(err)
    end

    close_process()
  end)

  local command = { "pi", "--mode", "rpc", "--system-prompt", system_prompt, "--no-session", "--thinking", "off" }
  local model = session_model or configured_model

  if model then
    table.insert(command, "--model")
    table.insert(command, model)
  end

  local started, process_or_error = pcall(vim.system,
    command,
    { stdin = true, stdout = handle_stdout },
    handle_exit
  )

  if not started then
    fail("Failed to start Pi: " .. tostring(process_or_error))
    return request
  end

  request.process = process_or_error

  local sent, write_error = pcall(function()
    request.process:write(vim.json.encode({
      type = "prompt",
      message = message,
    }) .. "\n")
  end)

  if not sent then
    fail("Failed to send prompt to Pi: " .. tostring(write_error))
    close_process()
  end

  return request
end

return M
