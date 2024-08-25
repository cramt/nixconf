vim.api.nvim_create_augroup("AutoFormatting", {})
vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = { "*.lua", "*.rs" },
    group = "AutoFormatting",
    callback = function()
        vim.lsp.buf.format()
    end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    pattern = { "*.norg" },
    command = "set conceallevel=3 | set linebreak"
})

MyBufferHelper = {}

local function mini_confirm(func, bufnr, force)
    if not force and vim.bo[bufnr].modified then
        local bufname = vim.fn.expand "%"
        local empty = bufname == ""
        if empty then bufname = "Untitled" end
        local confirm = vim.fn.confirm(('Save changes to "%s"?'):format(bufname), "&Yes\n&No\n&Cancel", 1, "Question")
        if confirm == 1 then
            if empty then return end
            vim.cmd.write()
        elseif confirm == 2 then
            force = true
        else
            return
        end
    end
    func(bufnr, force)
end

function MyBufferHelper.close(bufnr, force)
    if not bufnr or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
    --if vim.t.bufs > 1 then
    mini_confirm(require("mini.bufremove").delete, bufnr, force)
    --else
    --local buftype = vim.bo[bufnr].buftype
    --vim.cmd(("silent! %s %d"):format((force or buftype == "terminal") and "bdelete!" or "confirm bdelete", bufnr))
    --end
end

function MyBufferHelper.close_all(keep_current, force)
    if keep_current == nil then keep_current = false end
    local original = vim.api.nvim_get_current_buf()
    vim.cmd(":bnext")
    while original ~= vim.api.nvim_get_current_buf() do
        MyBufferHelper.close(0, force)
    end
    if not keep_current then
        MyBufferHelper.close(0, force)
    end
end
