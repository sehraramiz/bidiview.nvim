local M = {}

local utf8 = require("bidiview.utf8.lua.utf8")
local bid = -1
local wid = -1
local view_wid = -1
local view_bid = -1

local function reverse_fa(text)
    local reversed = {}

    for _, char in utf8.codes(text) do
        table.insert(reversed, 1, char)
    end

    return table.concat(reversed)
end

local function to_bidi(text)
    --[[
    Find all farsi sections and reverse them
    keep the non farsi parts unchanged

    example:
        from this:
            '<p>یک متن فارسی و english قاطی در یک html است.</p>'
        to this:
            '<p>کی نتم یسراف و english یطاق رد کی html تسا.</p>'
    ]]
    local pattern = "([\u{0600}-\u{06FF}\u{200c}]+)"
    local bidi_text = string.gsub(text, pattern, reverse_fa)
    return bidi_text
end

local function bidi_lines(lines)
    local result = {}
    for _, line in ipairs(lines) do
        table.insert(result, to_bidi(line))
    end
    return result
end

local function multi_dig()
    character_info = vim.api.nvim_command_output("ascii")
    local p = "<.*> +([0-9]+)"
    local char_dec = string.match(character_info, p)
    if char_dec then
        char_dec = tonumber(char_dec)
        if char_dec >= 1548 and char_dec <= 1785 then
            return true
        end
    end
    return false
end

local function view_is_valid()
    if view_wid == -1 then
        return false
    end
    local view_buf_valid = vim.api.nvim_call_function("nvim_buf_is_valid", {view_bid})
    local view_win_valid = vim.api.nvim_call_function("nvim_win_is_valid", {view_wid})
    local buf_valid = vim.api.nvim_call_function("nvim_buf_is_valid", {bid})
    local win_valid = vim.api.nvim_call_function("nvim_win_is_valid", {wid})
    return view_buf_valid and view_win_valid and buf_valid and win_valid
end

local function view_set_text(lines)
    vim.api.nvim_call_function("nvim_buf_set_lines", {
        view_bid, 0, -1, false, bidi_lines(lines)
    })
end

local function view_get_text()
    return vim.api.nvim_call_function("nvim_buf_get_lines", {bid, 0, -1, false})
end

local function view_set_modifiable(modifiable)
    vim.api.nvim_call_function("nvim_buf_set_option", {view_bid, "modifiable", modifiable})
end

local function view_update()
    local lines = view_get_text()
    view_set_modifiable(true)
    view_set_text(lines)
    view_set_modifiable(false)
end

local function window_binds_set(target_wid)
    if not target_wid then
        vim.api.nvim_command("set scrollbind")
        vim.api.nvim_command("set cursorbind")
        return
    end
    vim.api.nvim_call_function("nvim_win_set_option", {target_wid, "scrollbind", true})
    vim.api.nvim_call_function("nvim_win_set_option", {target_wid, "cursorbind", true})
end

local function window_binds_unset(target_wid)
    if not target_wid or target_wid == -1 then
        vim.api.nvim_command("set noscrollbind")
        vim.api.nvim_command("set nocursorbind")
        return
    end
    vim.api.nvim_call_function("nvim_win_set_option", {target_wid, "scrollbind", false})
    vim.api.nvim_call_function("nvim_win_set_option", {target_wid, "cursorbind", false})
end

local function highlight_cursor()
    local cursor_pos = vim.api.nvim_call_function(
        "nvim_buf_clear_namespace", {view_bid, 0, 0, -1}
    )
    local cursor_pos = vim.api.nvim_call_function("nvim_win_get_cursor", {wid})
    local cursor_pos_y = cursor_pos[1] - 1
    local cursor_pos_x = cursor_pos[2]

    local end_cursor_pos_x = cursor_pos_x
    if multi_dig() then
        end_cursor_pos_x = end_cursor_pos_x + 2
    else
        end_cursor_pos_x = end_cursor_pos_x + 1
    end

    vim.api.nvim_call_function("nvim_buf_add_highlight", {
        view_bid, 0, "Error", cursor_pos_y, cursor_pos_x, end_cursor_pos_x
    })
end

local function create_view_buf()
    return vim.api.nvim_call_function("nvim_create_buf", {true, true})
end

local function view_set_name()
    local buf_name = vim.api.nvim_call_function("bufname", {bid})
    local view_buf_name = "bidi-" .. buf_name
    vim.api.nvim_call_function("nvim_buf_set_name", {view_bid, view_buf_name})
end

local function view_init()
    window_binds_set()
    bid = vim.api.nvim_call_function("nvim_buf_get_number", {0})
    wid = vim.api.nvim_call_function("nvim_get_current_win", {})
    view_bid = create_view_buf()
    view_wnr = vim.api.nvim_command("sp")
    view_wid = vim.api.nvim_call_function("nvim_get_current_win", {})
    --view_wid = vim.api.nvim_call_function("win_getid", {view_wnr})
    vim.api.nvim_call_function("nvim_win_set_buf", {view_wid, view_bid})
    view_update()
    window_binds_set()
    highlight_cursor()
    view_set_name()
end

local function view_show()
    if not view_is_valid() then
        view_init()
        vim.api.nvim_call_function("nvim_set_current_win", {wid})
        vim.api.nvim_command("syncbind")
        return
    end
end

local function view_hide()
    window_binds_unset(view_wid)
    vim.api.nvim_call_function("nvim_win_close", {view_wid, true})
end

local function view_wipe()
    vim.api.nvim_command("bwipeout " .. view_bid)
end

M.setup = function()
    vim.api.nvim_create_autocmd("TextChanged", {callback = function()
        if view_is_valid() then
            view_update()
        end
    end
    })
    vim.api.nvim_create_autocmd("TextChangedI", {callback = function()
        if view_is_valid() then
            view_update()
        end
    end
    })
    vim.api.nvim_create_autocmd("CursorMoved", {callback = function()
        current_wid = vim.api.nvim_call_function("nvim_get_current_win", {})
        if not current_wid == wid then
            return
        end
        if view_is_valid() then
            highlight_cursor()
        end
    end
    })
    vim.api.nvim_create_autocmd("WinClosed", {callback = function()
        currentwid = vim.api.nvim_call_function("nvim_get_current_win", {})
        if current_wid == view_wid then
            view_hide()
            view_wipe()
        end
    end})
    vim.api.nvim_create_user_command("HideBidiView", view_wipe, {})
    vim.api.nvim_create_user_command("ShowBidiView", view_show, {})
end

return M
