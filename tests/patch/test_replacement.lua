local helpers = require("tests.helpers")
local replacement = require("patch.core.replacement")
local selection = require("patch.core.selection")
local eq = MiniTest.expect.equality

local buffer
local location
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      buffer = helpers.new_buffer({ "before", "old one", "old two", "after" })
      helpers.set_visual_lines(buffer, 2, 3)
      location = assert(selection.capture())
    end,
    post_case = function()
      helpers.delete_buffer(buffer)
    end,
  },
})

local function lines()
  return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

T["previews generated lines without changing buffer text"] = function()
  local proposal = assert(replacement.apply(location, "new one\nnew two\n"))

  eq(lines(), { "before", "old one", "old two", "after" })
  eq(proposal.generated_lines, { "new one", "new two" })
  eq(proposal.status, "pending")
  eq(type(proposal.generated_mark), "number")
end

T["removes a CRLF terminal newline"] = function()
  local proposal = assert(replacement.apply(location, "new one\r\n"))

  eq(proposal.generated_lines, { "new one" })
end

T["accepts a proposal and replaces the original lines"] = function()
  local proposal = assert(replacement.apply(location, "new one\nnew two"))

  eq(replacement.accept(proposal), true)
  eq(lines(), { "before", "new one", "new two", "after" })
  eq(proposal.status, "finished")
  eq(selection.resolve(location), nil)
end

T["supports an empty response as a deletion"] = function()
  local proposal = assert(replacement.apply(location, ""))

  eq(proposal.generated_lines, {})
  eq(replacement.accept(proposal), true)
  eq(lines(), { "before", "after" })
end

T["leaves the buffer unchanged when rejected"] = function()
  local proposal = assert(replacement.apply(location, "replacement"))

  eq(replacement.reject(proposal), true)
  eq(lines(), { "before", "old one", "old two", "after" })
  eq(proposal.status, "finished")
end

T["undoes an accepted proposal as one buffer change"] = function()
  local proposal = assert(replacement.apply(location, "replacement"))
  eq(replacement.accept(proposal), true)

  vim.cmd.undo()

  eq(lines(), { "before", "old one", "old two", "after" })
end

T["hides the old preview and completes a retry"] = function()
  local proposal = assert(replacement.apply(location, "first"))

  eq(replacement.begin_retry(proposal), true)
  eq(proposal.status, "retrying")
  eq(proposal.generated_lines, {})
  eq(proposal.generated_mark, nil)

  eq(replacement.complete_retry(proposal, "second\nthird"), proposal)
  eq(proposal.status, "pending")
  eq(proposal.generated_lines, { "second", "third" })
end

T["finalises an aborted retry"] = function()
  local proposal = assert(replacement.apply(location, "first"))
  eq(replacement.begin_retry(proposal), true)

  eq(replacement.abort_retry(proposal), true)
  eq(proposal.status, "finished")
  eq(selection.resolve(location), nil)
end

T["rejects lifecycle operations in the wrong state"] = function()
  local proposal = assert(replacement.apply(location, "first"))
  eq(replacement.reject(proposal), true)

  eq(replacement.accept(proposal), false)
  eq(replacement.reject(proposal), false)
  eq(replacement.begin_retry(proposal), false)
  eq(replacement.abort_retry(proposal), false)
  eq(replacement.complete_retry(proposal, "second"), nil)
end

T["fails safely after the source buffer is unloaded"] = function()
  local proposal = assert(replacement.apply(location, "replacement"))
  vim.api.nvim_buf_delete(buffer, { force = true })
  buffer = nil

  eq(replacement.accept(proposal), false)
  eq(proposal.status, "finished")
end

return T
