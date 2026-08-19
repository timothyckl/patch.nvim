local M = {}

function M.new_buffer(lines)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)

  local undolevels = vim.bo[buffer].undolevels
  vim.bo[buffer].undolevels = -1
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines or {})
  vim.bo[buffer].undolevels = undolevels

  return buffer
end

function M.set_visual_lines(buffer, start_line, end_line)
  vim.fn.setpos("'<", { buffer, start_line, 1, 0 })
  vim.fn.setpos("'>", { buffer, end_line, 1, 0 })
end

function M.delete_buffer(buffer)
  if buffer and vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
end

function M.wait_for(predicate)
  assert.is_true(vim.wait(500, predicate, 5), "timed out waiting for scheduled callback")
end

function M.unload_modules(names)
  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end
end

return M
