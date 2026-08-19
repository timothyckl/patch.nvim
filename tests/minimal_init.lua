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
vim.opt.runtimepath:prepend(dependency_path("PLENARY_DIR", "plenary.nvim"))
vim.opt.runtimepath:prepend(dependency_path("NUI_DIR", "nui.nvim"))
vim.cmd("runtime plugin/plenary.vim")

vim.o.swapfile = false
vim.o.writebackup = false
