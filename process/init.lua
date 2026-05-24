local config = require 'process.config'
local action = require 'process.action'

local M = {}

function M.meta()
  return {
    icon = '󰒋',
    desc = 'Process manager',
    color = 'green',
  }
end

local function register_page_keymaps()
  local keymap = (config.get() or {}).keymap or {}
  local path = '/process/**'
  if keymap.kill and keymap.kill ~= '' then
    deck.keymap.set('main', keymap.kill, action.kill, { path = path, desc = 'kill process' })
  end
end

function M.setup(opt)
  config.setup(opt or {})
  register_page_keymaps()

  local has_ps = deck.system.executable(config.get().ps_command)
  local has_pstree = deck.system.executable(config.get().pstree_command)

  if not has_ps then
    deck.notify('Error: ' .. config.get().ps_command .. ' command not found')
    deck.log('error', '{} command not found', config.get().ps_command)
  elseif not has_pstree then
    deck.log('warn', '{} command not found, preview may not work', config.get().pstree_command)
  else
    deck.log('info', '{} and {} commands are available', config.get().ps_command, config.get().pstree_command)
  end
end

function M.list(_, cb)
  deck.system({ config.get().ps_command, '-eo', 'pid,command' }, function(out)
    if out.code ~= 0 then
      cb({
        {
          key = 'error',
          kind = 'info',
          selectable = false,
          message = 'Failed to list processes',
          color = 'red',
          display = deck.style.line { deck.style.span('Failed to list processes'):fg 'red' },
        },
      })
      return
    end

    local lines = out.stdout:trim():split '\n'
    local entries = {}
    for _, raw in ipairs(lines) do
      local pid, cmd = raw:match '^%s*(%d+)%s+(.+)$'
      if pid and cmd then
        table.insert(entries, {
          key = pid,
          kind = 'process',
          pid = tonumber(pid),
          command = cmd,
          display = raw,
        })
      end
    end

    cb(entries)
  end)
end

function M.preview(entry, cb)
  if not entry then
    cb(deck.style.text { deck.style.line { 'process' } })
    return
  end

  if entry.kind == 'process' then
    action.preview(entry, cb)
    return
  end

  cb(action.info_preview(entry))
end

return M
