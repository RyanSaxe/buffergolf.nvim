if vim.g.buffergolf_loaded then
  return
end

vim.g.buffergolf_loaded = true

require("buffergolf").setup()
