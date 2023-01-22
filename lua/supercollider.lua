local S = {}
local ts_utils = require 'nvim-treesitter.ts_utils'

local DEFAULTS = {
  boot = {
    enabled = false,
    split = 'h',
  },
  keymaps = {
    send_line = "<C-L>",
    send_node = "<Leader>s",
    send_visual = "<C-L>",
    hush = "<C-H>"
  }
}

local KEYMAPS = {
  send_line = {
    mode = 'n',
    action = "Vy<cmd>lua require('supercollider').send_reg()<CR><ESC>",
    description = "send line to SuperCollider REPL",
  },
  send_node = {
    mode = 'n',
    action = function () S.send_node() end,
    description = "send treesitter node to SuperCollider REPL",
  },
  send_visual = {
    mode = 'v',
    action = "y<cmd>lua require('supercollider').send_reg()<CR>",
    description = "send selection to SuperCollider REPL",
  },
  hush = {
    mode = 'n',
    action = "<cmd>lua require('supercollider').send('CmdPeriod.run;')<CR>",
    description = "stops all sound at the SuperCollider REPL",
  }
}

local state = {
  launched = false,
  sclang = nil,
  sclang_process = nil
}

local function boot_sclang(args)
  if state.sclang then
    local ok = pcall(vim.api.nvim_set_current_buf, state.sclang)
    if not ok then
      state.sclang = nil
      boot_sclang(args)
    end
  else
    state.sclang = vim.api.nvim_create_buf(false, false)
    boot_sclang(args)
    return
  end
  state.sclang_process = vim.fn.termopen('sclang', { on_exit = function ()
    if #vim.fn.win_findbuf(state.sclang) > 0 then
      vim.api.nvim_win_close(vim.fn.win_findbuf(state.sclang)[1], true)
    end
    vim.api.nvim_buf_delete(state.sclang)
    state.sclang = nil
    state.sclang_process = nil
  end })
  S.send("s.boot;\n")
end

local function launch_sclang(args)
  local current_win = vim.api.nvim_get_current_win()
  if not args.enabled then return end
  if state.launched then return end
  vim.cmd(args.split == 'v' and 'vsplit' or 'split')
  boot_sclang(args)
  vim.api.nvim_set_current_win(current_win)
  state.launched = true
end

local function exit_sclang()
  if not state.launched then return end
  if state.sclang_process then
    vim.fn.jobstop(state.sclang_process)
  end
  state.launched = false
end

local function key_map(key, mapping)
  vim.keymap.set(KEYMAPS[key].mode, mapping, KEYMAPS[key].action, {
    buffer = true,
    desc = KEYMAPS[key].description
  })
end

function S.send(text)
  if not state.sclang_process then return end
  vim.api.nvim_chan_send(state.sclang_process, text .. '\n')
end

function S.send_reg(register)
  if not register then register = "" end
  local text = table.concat(vim.fn.getreg(register, 1, true), ' ')
  S.send(text)
end

function S.send_node()
  local node = ts_utils.get_node_at_cursor(0)
  local root
  if node then
    root = ts_utils.get_root_for_node(node)
  end
  if not root then return end
  local parent
  if node then
    parent = node:parent()
  end
  while node ~= nil and node ~= root do
    local t = node:type()
    if t == "code_block" or t == "function_block" then break end
    node = parent
    if node then
      parent = node:parent()
    end
  end
  if not node then return end
  local start_row, start_col, end_row, end_col = ts_utils.get_node_range(node)
  local text = table.concat(vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {}), ' ')
  S.send(text)
end

function S.setup(args)
  args = vim.tbl_deep_extend("force", DEFAULTS, args)
  vim.api.nvim_create_user_command('SclangLaunch',
    function () launch_sclang(args.boot) end,
    { desc = "launches Sclang REPL if so configured"})
  vim.api.nvim_create_user_command('SclangExit', exit_sclang,
    { desc = "quits Sclang REPL instance"})
  vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
    pattern = {"*.sc", "*.scd"},
    callback = function ()
      vim.cmd 'set ft=supercollider'
      for key, value in pairs(args.keymaps) do
        key_map(key, value)
      end
    end
  })
end

return S
