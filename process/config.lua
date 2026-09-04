local M = {}

local cfg = {
  ps_command = 'ps',
  keymap = {
    kill = 'dd', -- SIGTERM (15)
    kill9 = 'dk', -- SIGKILL (9)
  },
}

function M.setup(opt)
  cfg = deck.tbl_deep_extend('force', cfg, opt or {})
end

function M.get() return cfg end

return M
