local M = {}

--- @type vim.SystemObj|nil
M.process = nil

local SYSTEM_PROMPT = "You are an inline code editor. Given the selection and an instruction, reply with only the replacement code for the SELECTED region. No commentary, no explanations, no markdown fences."

--- Check whether a Pi process is active.
---
--- @return boolean is_running
function M.is_running()
  return M.process ~= nil
end

--- Abort the active Pi request, if one exists.
function M.cancel()
  if M.process then
    M.process:write(vim.json.encode({ type = "abort" }) .. "\n")
    vim.api.nvim_echo({ { "Cancelled", "Comment" } }, false, {})
  else
    vim.api.nvim_echo({ { "Nothing to cancel", "Comment" } }, false, {})
  end
end

--- Send a prompt to Pi and display its final response.
---
--- @param message string prompt containing the selection and surrounding context
function M.request(message)
  local process

  local stdout_buffer = ""
  local assistant_text
  local finished = false

  vim.api.nvim_echo({ { "Generating...", "Comment" } }, false, {})

  --- Schedule a message for display on Neovim's main event loop.
  ---
  --- @param message string
  local function display(message)
    vim.schedule(function()
      print(message)
    end)
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
    if M.process == process then
      M.process = nil
    end

    process = nil
  end

  --- Close the process input stream and clear its references.
  local function close_process()
    if process then
      process:write(nil)
    end

    clear_process()
  end

  --- Report an unexpected process failure and release the process.
  ---
  --- @param result vim.SystemCompleted
  local function handle_exit(result)
    clear_process()

    if result.code ~= 0 and not finished then
      display("Pi exited with code " .. result.code)
    end
  end

  --- Handle a decoded record from Pi's JSONL output.
  ---
  --- @param record table
  local function handle_record(record)
    if record.type == "response" and record.command == "prompt" and not record.success then
      finished = true
      display("Pi rejected the prompt: " .. record.error)
      close_process()
      return
    end

    if record.type == "message_end" and record.message.role == "assistant" then
      assistant_text = extract_text(record.message)
      return
    end

    if record.type == "agent_settled" then
      finished = true
      display(assistant_text or "Pi returned empty response.")
      close_process()
    end
  end

  --- Buffer Pi output and dispatch each complete JSONL record.
  ---
  --- @param error_message string|nil
  --- @param data string|nil
  local function handle_stdout(error_message, data)
    if error_message then
      display("Failed to read Pi output: " .. error_message)
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
        handle_record(vim.json.decode(line))
      end
    end
  end

  process = vim.system(
    { "pi", "--mode", "rpc", "--system-prompt", SYSTEM_PROMPT, "--no-session", "--thinking", "off" },
    { stdin = true, stdout = handle_stdout },
    handle_exit
  )

  M.process = process

  process:write(vim.json.encode({
    type = "prompt",
    message = "Repeat what the selected content is.\n" .. message,
  }) .. "\n")
end

return M
