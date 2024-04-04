
vim.keymap.set('n', "<leader>bn", "<cmd>tabnew<cr>", {desc = "New tab"})
vim.keymap.set("n", "L", function() require("astrocore.buffer").nav(vim.v.count1) end, {desc = "Next buffer"})
vim.keymap.set("n", "H", function() require("astrocore.buffer").nav(-vim.v.count1) end, {desc = "Previous buffer"})
