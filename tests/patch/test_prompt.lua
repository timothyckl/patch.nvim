local prompt = require("patch.pi.prompt")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["formats captured context in order"] = function()
  local result = prompt.format_context({
    before = { "local before = true", "" },
    selected = { "old()" },
    after = { "return before" },
  })

  eq(result, table.concat({
    "--- BEFORE ---",
    "local before = true",
    "",
    "--- SELECTED ---",
    "old()",
    "--- AFTER ---",
    "return before",
  }, "\n"))
end

T["marks empty context groups"] = function()
  eq(prompt.format_context({ before = {}, selected = {}, after = {} }), table.concat({
    "--- BEFORE ---",
    "(empty)",
    "--- SELECTED ---",
    "(empty)",
    "--- AFTER ---",
    "(empty)",
  }, "\n"))
end

T["appends a multiline instruction"] = function()
  local message = prompt.build({
    before = {},
    selected = { "value" },
    after = {},
  }, "Rename this.\nKeep its type.")

  assert(message:find("--- SELECTED ---\nvalue", 1, true))
  assert(message:find("--- INSTRUCTION ---\nRename this.\nKeep its type.", 1, true))
end

return T
