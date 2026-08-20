local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local function dependency_path(environment_name, directory_name)
  local configured = vim.env[environment_name]
  if configured and configured ~= "" then
    return configured
  end

  local local_dependency = root .. "/.deps/" .. directory_name
  if vim.fn.isdirectory(local_dependency) == 1 then
    return local_dependency
  end

  return vim.fn.stdpath("data") .. "/lazy/" .. directory_name
end

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(dependency_path("MINITEST_DIR", "mini.test"))
require("mini.test").setup({ collect = { emulate_busted = false } })

vim.o.swapfile = false
vim.o.writebackup = false
