local helpers = require("tests.helpers")
local replacement = require("patch.replacement")
local selection = require("patch.selection")

describe("patch.replacement", function()
  local buffer
  local location

  before_each(function()
    buffer = helpers.new_buffer({ "before", "old one", "old two", "after" })
    helpers.set_visual_lines(buffer, 2, 3)
    location = assert(selection.capture())
  end)

  after_each(function()
    helpers.delete_buffer(buffer)
  end)

  local function lines()
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  end

  it("previews generated lines without changing buffer text", function()
    local proposal = assert(replacement.apply(location, "new one\nnew two\n"))

    assert.are.same({ "before", "old one", "old two", "after" }, lines())
    assert.are.same({ "new one", "new two" }, proposal.generated_lines)
    assert.are.equal("pending", proposal.status)
    assert.is_number(proposal.generated_mark)
  end)

  it("removes a CRLF terminal newline", function()
    local proposal = assert(replacement.apply(location, "new one\r\n"))

    assert.are.same({ "new one" }, proposal.generated_lines)
  end)

  it("accepts a proposal and replaces the original lines", function()
    local proposal = assert(replacement.apply(location, "new one\nnew two"))

    assert.is_true(replacement.accept(proposal))
    assert.are.same({ "before", "new one", "new two", "after" }, lines())
    assert.are.equal("finished", proposal.status)
    assert.is_nil(selection.resolve(location))
  end)

  it("supports an empty response as a deletion", function()
    local proposal = assert(replacement.apply(location, ""))

    assert.are.same({}, proposal.generated_lines)
    assert.is_true(replacement.accept(proposal))
    assert.are.same({ "before", "after" }, lines())
  end)

  it("leaves the buffer unchanged when rejected", function()
    local proposal = assert(replacement.apply(location, "replacement"))

    assert.is_true(replacement.reject(proposal))
    assert.are.same({ "before", "old one", "old two", "after" }, lines())
    assert.are.equal("finished", proposal.status)
  end)

  it("undoes an accepted proposal as one buffer change", function()
    local proposal = assert(replacement.apply(location, "replacement"))
    assert.is_true(replacement.accept(proposal))

    vim.cmd.undo()

    assert.are.same({ "before", "old one", "old two", "after" }, lines())
  end)

  it("hides the old preview and completes a retry", function()
    local proposal = assert(replacement.apply(location, "first"))

    assert.is_true(replacement.begin_retry(proposal))
    assert.are.equal("retrying", proposal.status)
    assert.are.same({}, proposal.generated_lines)
    assert.is_nil(proposal.generated_mark)

    assert.are.equal(proposal, replacement.complete_retry(proposal, "second\nthird"))
    assert.are.equal("pending", proposal.status)
    assert.are.same({ "second", "third" }, proposal.generated_lines)
  end)

  it("finalises an aborted retry", function()
    local proposal = assert(replacement.apply(location, "first"))
    assert.is_true(replacement.begin_retry(proposal))

    assert.is_true(replacement.abort_retry(proposal))
    assert.are.equal("finished", proposal.status)
    assert.is_nil(selection.resolve(location))
  end)

  it("rejects lifecycle operations in the wrong state", function()
    local proposal = assert(replacement.apply(location, "first"))
    assert.is_true(replacement.reject(proposal))

    assert.is_false(replacement.accept(proposal))
    assert.is_false(replacement.reject(proposal))
    assert.is_false(replacement.begin_retry(proposal))
    assert.is_false(replacement.abort_retry(proposal))
    assert.is_nil(replacement.complete_retry(proposal, "second"))
  end)

  it("fails safely after the source buffer is unloaded", function()
    local proposal = assert(replacement.apply(location, "replacement"))
    vim.api.nvim_buf_delete(buffer, { force = true })
    buffer = nil

    assert.is_false(replacement.accept(proposal))
    assert.are.equal("finished", proposal.status)
  end)
end)
