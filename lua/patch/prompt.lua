local M = {}

--- Format a named capture group for display.
---
--- @param name string group name
--- @param lines string[] captured lines
--- @return string formatted_group
local function format_group(name, lines)
  local contents = #lines > 0 and table.concat(lines, "\n") or "(empty)"
  return string.format("--- %s ---\n%s", name, contents)
end

--- Format captured buffer context for display or inclusion in a prompt.
---
--- @param capture PatchCapture captured buffer context
--- @return string formatted_capture
function M.format_capture(capture)
  return table.concat({
    format_group("BEFORE", capture.content.before),
    format_group("SELECTED", capture.content.selected),
    format_group("AFTER", capture.content.after),
  }, "\n")
end

--- Build a model prompt from captured buffer context and the user's instruction.
---
--- @param capture PatchCapture captured buffer context
--- @param instruction string requested transformation
--- @return string message
function M.build(capture, instruction)
  return table.concat({
    M.format_capture(capture),
    string.format("--- INSTRUCTION ---\n%s", instruction),
  }, "\n")
end

return M
