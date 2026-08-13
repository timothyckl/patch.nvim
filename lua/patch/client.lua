local M = {}
local notify = require("patch.notify")

local SYSTEM_PROMPT = "You are an inline code editor. Given the selection and an instruction, reply with only the replacement code for the SELECTED region. No commentary, no explanations, no markdown fences."

local active_process = nil

--- Abort the active Pi request, if one exists.
function M.cancel()
  if active_process then
    active_process:write(vim.json.encode({ type = "abort" }) .. "\n")
    notify.send("patch: cancelled", vim.log.levels.INFO)
  else
    notify.send("patch: nothing to cancel", vim.log.levels.WARN)
  end
end

--- Send a prompt to Pi and deliver its final assistant text.
---
--- @param message string prompt containing the selection and surrounding context
--- @param on_complete fun(res: string|nil, err: string|nil)
function M.request(message, on_complete)
  local process

  local stdout_buffer = ""
  local assistant_text
  local completed = false

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
    if completed then
      return
    end

    completed = true

    vim.schedule(function()
      on_complete(res, err)
    end)
  end

  --- Report a request failure and complete it.
  ---
  --- @param err string
  local function fail(err)
    if completed then
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
    if active_process == process then
      active_process = nil
    end

    process = nil
  end

  --- Close the process input stream and clear its references.
  local function close_process()
    local current_process = process

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

    if not completed then
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

  --- Buffer Pi output and dispatch each complete JSONL record.
  ---
  --- @param error_message string|nil
  --- @param data string|nil
  local function handle_stdout(error_message, data)
    if error_message then
      fail("Failed to read Pi output: " .. error_message)
      close_process()
      return
    end

    stdout_buffer = stdout_buffer .. (data or "")

    while true do
      local newline = stdout_buffer:find("\n", 1, true)
      if not newline then
        return
      end

      local line = stdout_buffer:sub(1, newline -1):gsub("\r$", "")
      stdout_buffer = stdout_buffer:sub(newline + 1)

      if line ~= "" then
        local decoded, record = pcall(vim.json.decode, line)

        if not decoded then
          fail("Failed to decode Pi output: " .. record)
          close_process()
          return
        end

        handle_record(record)
      end
    end
  end

  local started, process_or_error = pcall(vim.system,
    { "pi", "--mode", "rpc", "--system-prompt", SYSTEM_PROMPT, "--no-session", "--thinking", "off" },
    { stdin = true, stdout = handle_stdout },
    handle_exit
  )

  if not started then
    fail("Failed to start Pi: " .. tostring(process_or_error))
    return
  end

  process = process_or_error
  active_process = process

  local sent, write_error = pcall(function()
    process:write(vim.json.encode({
      type = "prompt",
      message = message,
    }) .. "\n")
  end)

  if not sent then
    fail("Failed to send prompt to Pi: " .. tostring(write_error))
    close_process()
  end
end

return M
