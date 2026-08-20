local helpers = require("tests.helpers")
local selection = require("patch.selection")
local eq = MiniTest.expect.equality

local buffer
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      buffer = helpers.new_buffer({ "one", "two", "three", "four" })
    end,
    post_case = function()
      helpers.delete_buffer(buffer)
    end,
  },
})

T["captures and resolves a visual-line selection"] = function()
  helpers.set_visual_lines(buffer, 2, 3)

  local location = assert(selection.capture())
  local range = assert(selection.resolve(location))

  eq(range, { source_buf = buffer, start_row = 1, end_row = 3 })
end

T["normalises reversed visual marks"] = function()
  helpers.set_visual_lines(buffer, 4, 2)

  local range = assert(selection.resolve(assert(selection.capture())))

  eq(range, { source_buf = buffer, start_row = 1, end_row = 4 })
end

T["returns nil when no visual selection has been recorded"] = function()
  vim.fn.setpos("'<", { buffer, 0, 0, 0 })
  vim.fn.setpos("'>", { buffer, 0, 0, 0 })

  eq(selection.capture(), nil)
end

T["tracks the selected lines when text is inserted before them"] = function()
  helpers.set_visual_lines(buffer, 2, 3)
  local location = assert(selection.capture())

  vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "zero" })

  eq(selection.resolve(location), { source_buf = buffer, start_row = 2, end_row = 4 })
end

T["decorates without changing the tracked range"] = function()
  helpers.set_visual_lines(buffer, 2, 3)
  local location = assert(selection.capture())
  local original = selection.resolve(location)

  eq(selection.decorate(location, { hl_group = "DiffDelete", hl_eol = true }), true)
  eq(selection.resolve(location), original)
end

T["clears the tracked selection"] = function()
  helpers.set_visual_lines(buffer, 2, 3)
  local location = assert(selection.capture())

  selection.clear(location)

  eq(selection.resolve(location), nil)
end

T["does not resolve a selection in an unloaded buffer"] = function()
  helpers.set_visual_lines(buffer, 2, 3)
  local location = assert(selection.capture())
  vim.api.nvim_buf_delete(buffer, { force = true })
  buffer = nil

  eq(selection.resolve(location), nil)
  MiniTest.expect.no_error(function()
    selection.clear(location)
  end)
end

return T
