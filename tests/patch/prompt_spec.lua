local prompt = require("patch.prompt")

describe("patch.prompt", function()
  it("formats captured context in order", function()
    local result = prompt.format_context({
      before = { "local before = true", "" },
      selected = { "old()" },
      after = { "return before" },
    })

    assert.are.equal(table.concat({
      "--- BEFORE ---",
      "local before = true",
      "",
      "--- SELECTED ---",
      "old()",
      "--- AFTER ---",
      "return before",
    }, "\n"), result)
  end)

  it("marks empty context groups", function()
    assert.are.equal(table.concat({
      "--- BEFORE ---",
      "(empty)",
      "--- SELECTED ---",
      "(empty)",
      "--- AFTER ---",
      "(empty)",
    }, "\n"), prompt.format_context({ before = {}, selected = {}, after = {} }))
  end)

  it("appends a multiline instruction", function()
    local message = prompt.build({
      before = {},
      selected = { "value" },
      after = {},
    }, "Rename this.\nKeep its type.")

    assert.is_truthy(message:find("--- SELECTED ---\nvalue", 1, true))
    assert.is_truthy(message:find("--- INSTRUCTION ---\nRename this.\nKeep its type.", 1, true))
  end)
end)
