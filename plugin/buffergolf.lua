if vim.g.buffergolf_loaded then
  return
end

vim.g.buffergolf_loaded = true

-- Don't call setup() here - let the user's plugin manager handle it
-- This prevents conflicts with user configuration
