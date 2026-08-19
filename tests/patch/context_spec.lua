local helpers = require("tests.helpers")
local context = require("patch.context")
local selection = require("patch.selection")

describe("patch.context", function()
  local buffer

  after_each(function()
    helpers.delete_buffer(buffer)
  end)

  local function capture(start_line, end_line, lines)
    buffer = helpers.new_buffer(lines)
    helpers.set_visual_lines(buffer, start_line, end_line)
    return context.capture(assert(selection.capture()))
  end

  it("splits the buffer around the selection", function()
    assert.are.same({
      before = { "one" },
      selected = { "two", "three" },
      after = { "four" },
    }, capture(2, 3, { "one", "two", "three", "four" }))
  end)

  it("captures a selection at the start of the buffer", function()
    assert.are.same({
      before = {},
      selected = { "one" },
      after = { "two" },
    }, capture(1, 1, { "one", "two" }))
  end)

  it("captures a selection at the end of the buffer", function()
    assert.are.same({
      before = { "one" },
      selected = { "two" },
      after = {},
    }, capture(2, 2, { "one", "two" }))
  end)

  it("returns nil for a missing tracked selection", function()
    buffer = helpers.new_buffer({ "one" })
    helpers.set_visual_lines(buffer, 1, 1)
    local location = assert(selection.capture())
    selection.clear(location)

    assert.is_nil(context.capture(location))
  end)
end)
