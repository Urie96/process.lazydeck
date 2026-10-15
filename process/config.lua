local M = {}

-- macOS 上 PATH 里的 ps 往往是 nix-darwin/home-manager 装进去的未签名版本，
-- 读 %mem 会报 "requires entitlement" 并以退出码 1 结束；系统自带的 /bin/ps
-- 是 setuid root 且带 entitlement，能正常读到所有进程。这里按编译期目标平台选择。
local function default_ps_command()
  local ok, target = pcall(function() return deck.target_os() end)
  if ok and target == 'macos' then return '/bin/ps' end
  return 'ps'
end

local cfg = {
  -- nil / 空字符串 = 自动：macOS 用 /bin/ps，其它平台用 PATH 里的 ps
  ps_command = nil,
  keymap = {
    kill = 'dd', -- SIGTERM (15)
    kill9 = 'dk', -- SIGKILL (9)
  },
}

function M.setup(opt)
  cfg = deck.tbl_deep_extend('force', cfg, opt or {})
end

function M.get()
  -- 懒解析：插件可能不会调用 setup（如配置里只写了插件名），所以在这里兜底
  if cfg.ps_command == nil or cfg.ps_command == '' then
    cfg.ps_command = default_ps_command()
  end
  return cfg
end

return M
