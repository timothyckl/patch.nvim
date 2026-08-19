local helpers = require("tests.helpers")
local selection = require("patch.selection")

describe("patch.selection", function()
  local buffer

  before_each(function()
    buffer = helpers.new_buffer({ "one", "two", "three", "four" })
  end)

  after_each(function()
    helpers.delete_buffer(buffer)
  end)

  it("captures and resolves a visual-line selection", function()
    helpers.set_visual_lines(buffer, 2, 3)

    local location = assert(selection.capture())
    local range = assert(selection.resolve(location))

    assert.are.same({ source_buf = buffer, start_row = 1, end_row = 3 }, range)
  end)

  it("normalises reversed visual marks", function()
    helpers.set_visual_lines(buffer, 4, 2)

    local range = assert(selection.resolve(assert(selection.capture())))

    assert.are.same({ source_buf = buffer, start_row = 1, end_row = 4 }, range)
  end)

  it("returns nil when no visual selection has been recorded", function()
    vim.fn.setpos("'<", { buffer, 0, 0, 0 })
    vim.fn.setpos("'>", { buffer, 0, 0, 0 })

    assert.is_nil(selection.capture())
  end)

  it("tracks the selected lines when text is inserted before them", function()
    helpers.set_visual_lines(buffer, 2, 3)
    local location = assert(selection.capture())

    vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "zero" })

    assert.are.same({ source_buf = buffer, start_row = 2, end_row = 4 }, selection.resolve(location))
  end)

  it("decorates without changing the tracked range", function()
    helpers.set_visual_lines(buffer, 2, 3)
    local location = assert(selection.capture())
    local original = selection.resolve(location)

    assert.is_true(selection.decorate(location, { hl_group = "DiffDelete", hl_eol = true }))
    assert.are.same(original, selection.resolve(location))
  end)

  it("clears the tracked selection", function()
    helpers.set_visual_lines(buffer, 2, 3)
    local location = assert(selection.capture())

    selection.clear(location)

    assert.is_nil(selection.resolve(location))
  end)

  it("does not resolve a selection in an unloaded buffer", function()
    helpers.set_visual_lines(buffer, 2, 3)
    local location = assert(selection.capture())
    vim.api.nvim_buf_delete(buffer, { force = true })
    buffer = nil

    assert.is_nil(selection.resolve(location))
    assert.has_no.errors(function()
      selection.clear(location)
    end)
  end)
end)
