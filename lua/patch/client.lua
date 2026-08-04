local M = {}

local SYSTEM_PROMPT = "You are an inline code editor. Given the selection and an instruction, reply with only the replacement code for the SELECTED region. No commentary, no explanations, no markdown fences."

function M.request(message)
  local process

  local stdout_buffer = ""
  local assistant_text
  local finished = false

  vim.api.nvim_echo({ { "Generating...", "Comment" } }, false, {})


  local function display(message)
    vim.schedule(function()
      print(message)
    end)
  end

  local function extract_text(message)
    local parts = {}

    for _, content in ipairs(message.content) do
      if content.type == "text" then
        table.insert(parts, content.text)
      end
    end

    return table.concat(parts, "\n")
  end

  local function close_process()
    if process then
      process:write(nil)
    end
  end

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
    { "pi", "--mode", "rpc", "--system-prompt", SYSTEM_PROMPT, "--no-session" },
    { stdin = true, stdout = handle_stdout },
    function(result)
      if result.code ~= 0 and not finished then
        display("Pi exited with code " .. result.code)
      end
    end
  )

  process:write(vim.json.encode({
    type = "prompt",
    message = "Repeat what the selected content is.\n" .. message,
  }) .. "\n")
end

return M
