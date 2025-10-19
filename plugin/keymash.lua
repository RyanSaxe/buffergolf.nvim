if vim.g.loaded_keymash then
  return
end

vim.g.loaded_keymash = true

require("keymash").setup()
