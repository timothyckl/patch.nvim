local helpers = require("tests.helpers")
local context = require("patch.context")
local selection = require("patch.selection")
local eq = MiniTest.expect.equality

local buffer
local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      helpers.delete_buffer(buffer)
    end,
  },
})

local function capture(start_line, end_line, lines)
  buffer = helpers.new_buffer(lines)
  helpers.set_visual_lines(buffer, start_line, end_line)
  return context.capture(assert(selection.capture()))
end

T["splits the buffer around the selection"] = function()
  eq(capture(2, 3, { "one", "two", "three", "four" }), {
    before = { "one" },
    selected = { "two", "three" },
    after = { "four" },
  })
end

T["captures a selection at the start of the buffer"] = function()
  eq(capture(1, 1, { "one", "two" }), {
    before = {},
    selected = { "one" },
    after = { "two" },
  })
end

T["captures a selection at the end of the buffer"] = function()
  eq(capture(2, 2, { "one", "two" }), {
    before = { "one" },
    selected = { "two" },
    after = {},
  })
end

T["returns nil for a missing tracked selection"] = function()
  buffer = helpers.new_buffer({ "one" })
  helpers.set_visual_lines(buffer, 1, 1)
  local location = assert(selection.capture())
  selection.clear(location)

  eq(context.capture(location), nil)
end

return T
