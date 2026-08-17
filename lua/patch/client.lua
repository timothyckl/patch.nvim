local M = {}
local rpc = require("patch.rpc")

local DEFAULT_SYSTEM_PROMPT = "You are an inline code editor. Given the selection and an instruction, reply with only the replacement code for the SELECTED region. No commentary, no explanations, no markdown fences."
local system_prompt = DEFAULT_SYSTEM_PROMPT
local configured_model
local session_model
local primary_model

---@param callback function
---@param value any
---@param err string|nil
local function schedule_complete(callback, value, err)
  vim.schedule(function()
    callback(value, err)
  end)
end

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

---@class PatchRequest
---@field state "pending"|"cancelled"|"completed"
---@field connection? PatchRpcConnection
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

  if request.connection then
    request.connection:send({ type = "abort" })
  end

  vim.schedule(function()
    request.on_complete(nil, "cancelled")
  end)

  return true
end

-- TODO: Cache available models and effective model state per session to avoid RPC startup latency when opening the menu.
--- Retrieve the models available to Pi.
---
---@param on_complete fun(models: PatchModel[]|nil, err: string|nil)
function M.get_available_models(on_complete)
  rpc.request({ type = "get_available_models" }, function(record, err)
    if err then
      schedule_complete(on_complete, nil, err)
      return
    end

    if type(record.data) ~= "table" or type(record.data.models) ~= "table" then
      schedule_complete(on_complete, nil, "Pi returned an invalid model list")
      return
    end

    schedule_complete(on_complete, record.data.models, nil)
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

--- Resolve the effective model selector used by Patch.
---
---@param on_complete fun(model: string|nil, err: string|nil)
function M.resolve_model(on_complete)
  local override = session_model or configured_model
  if override then
    schedule_complete(on_complete, override, nil)
    return
  end

  if primary_model then
    schedule_complete(on_complete, primary_model, nil)
    return
  end

  rpc.request({ type = "get_state" }, function(record, err)
    if err then
      schedule_complete(on_complete, nil, err)
      return
    end

    local model = type(record.data) == "table" and record.data.model or nil
    if type(model) ~= "table" or type(model.provider) ~= "string" or type(model.id) ~= "string" then
      schedule_complete(on_complete, nil, "Pi returned no primary model")
      return
    end

    primary_model = model.provider .. "/" .. model.id
    schedule_complete(on_complete, primary_model, nil)
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
    connection = nil,
    on_complete = on_complete,
  }

  local assistant_text

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

  --- Clear references to this request's connection.
  local function clear_connection()
    request.connection = nil
  end

  --- Close the connection and clear its references.
  local function close_connection()
    local connection = request.connection

    clear_connection()

    if connection then
      connection:close()
    end
  end

  --- Report an unexpected process failure and release the process.
  ---
  --- @param result vim.SystemCompleted
  local function handle_exit(result)
    clear_connection()

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
        close_connection()
      end

      return
    end

    if record.type == "response" and record.command == "prompt" and not record.success then
      fail("Pi rejected the prompt: " .. record.error)
      close_connection()
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

      close_connection()
      return
    end
  end

  local args = { "--system-prompt", system_prompt, "--no-session", "--thinking", "off" }
  local model = session_model or configured_model

  if model then
    table.insert(args, "--model")
    table.insert(args, model)
  end

  local connection, start_error = rpc.start(args, {
    on_record = handle_record,
    on_error = function(err)
      if request.state == "pending" then
        fail(err)
      end

      close_connection()
    end,
    on_exit = handle_exit,
  })

  if not connection then
    fail(tostring(start_error))
    return request
  end

  request.connection = connection

  local sent, write_error = connection:send({
    type = "prompt",
    message = message,
  })

  if not sent then
    fail("Failed to send prompt to Pi: " .. tostring(write_error))
    close_connection()
  end

  return request
end

return M
