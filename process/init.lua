local config = require 'process.config'
local action = require 'process.action'

-- 会话内页面缓存：同一路径再次进入（back/forward 导航）直接复用上次结果，不再执行 ps
-- reload（r 键 / dd、dk 杀进程后的自动刷新）时通过 pre_reload 钩子清空
-- 注意：必须声明在 M.setup 之前，否则 setup 里的 hook 闭包看不到这个局部变量
local page_cache = {}

local M = {}

function M.meta()
  return {
    icon = '󰒋',
    desc = 'Process manager',
    color = 'green',
  }
end

local function line(parts) return deck.style.line(parts) end
local function text(parts) return deck.style.text(parts) end
local function span(value, color)
  local s = deck.style.span(tostring(value or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function register_page_keymaps()
  local keymap = (config.get() or {}).keymap or {}
  local path = '/process/**'
  if keymap.kill and keymap.kill ~= '' then
    deck.keymap.set('main', keymap.kill, action.kill, { path = path, desc = 'terminate process (SIGTERM)' })
  end
  if keymap.kill9 and keymap.kill9 ~= '' then
    deck.keymap.set('main', keymap.kill9, action.kill9, { path = path, desc = 'force kill process (SIGKILL)' })
  end
end

function M.setup(opt)
  config.setup(opt or {})
  register_page_keymaps()

  -- 主动 reload 时清空页面缓存，保证 r / kill 后能拿到最新进程表
  deck.hook.pre_reload(function()
    page_cache = {}
  end)

  local ps_command = config.get().ps_command
  if not deck.system.executable(ps_command) then
    deck.notify('Error: ' .. ps_command .. ' command not found')
    deck.log('error', '{} command not found', ps_command)
  else
    deck.log('info', '{} command is available', ps_command)
  end
end

-- ps 输出字段（command 必须排在最后，否则无法从一行里切出完整命令行）
local PS_FIELDS = 'pid=,ppid=,user=,uid=,%cpu=,%mem=,stat=,tty=,etime=,nice=,command='

local function info_entry(key, message, color)
  return {
    key = key,
    kind = 'info',
    selectable = false,
    message = message,
    color = color or 'darkgray',
    display = line { span(message, color or 'darkgray') },
  }
end

-- 底部提示：根据当前配置的快捷键生成
local function kill_hint()
  local km = (config.get() or {}).keymap or {}
  local parts = {}
  if km.kill9 and km.kill9 ~= '' then
    parts[#parts + 1] = km.kill9 .. ' kill -9'
  end
  if km.kill and km.kill ~= '' and km.kill ~= km.kill9 then
    parts[#parts + 1] = km.kill .. ' term'
  end
  parts[#parts + 1] = '→ view child process tree'
  return table.concat(parts, ' | ')
end

local function parse_ps_line(raw)
  local pid, ppid, user, uid, cpu, mem, stat, tty, etime, nice, command =
    raw:match('^%s*(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(.+)$')
  if not pid then return nil end
  return {
    pid = tonumber(pid),
    ppid = tonumber(ppid),
    user = user,
    uid = tonumber(uid),
    cpu = cpu,
    mem = mem,
    stat = stat,
    tty = tty,
    etime = etime,
    nice = nice,
    command = command,
  }
end

local function parse_all(stdout)
  local processes, child_counts = {}, {}
  for _, raw in ipairs((stdout or ''):trim():split '\n') do
    local info = parse_ps_line(raw)
    if info then
      processes[#processes + 1] = info
      child_counts[info.ppid] = (child_counts[info.ppid] or 0) + 1
    end
  end
  table.sort(processes, function(a, b) return a.pid < b.pid end)
  return processes, child_counts
end

local function build_entry(info, child_counts)
  local display = line {
    span(info.pid, 'yellow'),
    '  ',
    span(info.user, 'blue'),
    '  ',
    span(info.command),
  }
  return {
    key = tostring(info.pid),
    kind = 'process',
    pid = info.pid,
    ppid = info.ppid,
    user = info.user,
    uid = info.uid,
    cpu = info.cpu,
    mem = info.mem,
    stat = info.stat,
    tty = info.tty,
    etime = info.etime,
    nice = info.nice,
    command = info.command,
    child_count = child_counts[info.pid] or 0,
    display = display,
    bottom_line = kill_hint(),
  }
end

local function align_displays(entries)
  local displays = {}
  for _, e in ipairs(entries) do displays[#displays + 1] = e.display end
  deck.style.align_columns(displays)
end

-- 按 CPU 占用降序，CPU 相同再按内存降序；两者都相同按 pid 升序保证稳定
local function sort_by_usage(entries)
  table.sort(entries, function(a, b)
    local ac = tonumber(a.cpu) or -1
    local bc = tonumber(b.cpu) or -1
    if ac ~= bc then return ac > bc end
    local am = tonumber(a.mem) or -1
    local bm = tonumber(b.mem) or -1
    if am ~= bm then return am > bm end
    return (a.pid or 0) < (b.pid or 0)
  end)
end

local function with_loading(path, cb, message)
  local expected = deck.api.get_current_path()
  cb({ info_entry('loading', message, 'darkgray') })
  return function(fn)
    return function(...)
      if not deck.deep_equal(expected, deck.api.get_current_path()) then return end
      fn(...)
    end
  end
end

local function list_processes(path, cb)
  local guard = with_loading(path, cb, 'Loading processes...')
  deck.system({ config.get().ps_command, '-eo', PS_FIELDS }, guard(function(out)
    if out.code ~= 0 then
      cb({ info_entry('error', 'Failed to list processes: ' .. tostring(out.stderr or 'unknown error'), 'red') })
      return
    end
    local processes, child_counts = parse_all(out.stdout)
    local entries = {}
    for _, info in ipairs(processes) do
      entries[#entries + 1] = build_entry(info, child_counts)
    end
    if #entries == 0 then
      cb({ info_entry('empty', 'No processes found', 'yellow') })
      return
    end
    sort_by_usage(entries)
    align_displays(entries)
    page_cache[table.concat(path, '/')] = entries
    cb(entries)
  end))
end

--- 树形/链式行：pid + command；prefix 为缩进树线（子孙用），color 区分层级
-- 颜色：父进程链=红，当前 pid=黄加粗，子孙=青
local function build_tree_entry(info, prefix, child_count, color, bold)
  local pid_span = span(string.format('%-7s', tostring(info.pid or '')), color or 'cyan')
  if bold then pid_span = pid_span:bold() end
  return {
    key = tostring(info.pid),
    kind = 'process',
    pid = info.pid,
    ppid = info.ppid,
    user = info.user,
    uid = info.uid,
    cpu = info.cpu,
    mem = info.mem,
    stat = info.stat,
    tty = info.tty,
    etime = info.etime,
    nice = info.nice,
    command = info.command,
    child_count = child_count or 0,
    display = line {
      span(prefix),
      pid_span,
      span('  ' .. info.command),
    },
    bottom_line = kill_hint(),
  }
end

-- 递归展开 pid 的子孙并写入 entries（不含 pid 自身行，自身行由调用方生成）
-- indent：祖先链的延续符串（'' 表示刚进入树的第一层）
local function emit_children(info_map, children_map, direct_counts, pid, indent, seen, entries)
  local kids = children_map[pid] or {}
  local n = #kids
  for i, kid in ipairs(kids) do
    if not seen[kid.pid] then
      seen[kid.pid] = true
      local prefix = indent .. (i == n and '└─ ' or '├─ ')
      entries[#entries + 1] = build_tree_entry(info_map[kid.pid], prefix, direct_counts[kid.pid] or 0)
      emit_children(info_map, children_map, direct_counts, kid.pid, indent .. (i == n and '   ' or '│  '), seen, entries)
    end
  end
end

--- /process/<pid> 及其更深页面：list 展示 父进程链 + pid 本身 + 其子孙树
local function list_process_tree(path, cb)
  local root_pid = tonumber(path[#path])
  if not root_pid then
    cb({ info_entry('error', 'Invalid process id: ' .. tostring(path[#path]), 'red') })
    return
  end

  local guard = with_loading(path, cb, 'Loading process tree...')
  deck.system({ config.get().ps_command, '-eo', PS_FIELDS }, guard(function(out)
    if out.code ~= 0 then
      cb({ info_entry('error', 'Failed to list processes: ' .. tostring(out.stderr or 'unknown error'), 'red') })
      return
    end

    local info_map, children_map = {}, {}
    for _, raw in ipairs((out.stdout or ''):trim():split '\n') do
      local info = parse_ps_line(raw)
      if info then
        info_map[info.pid] = info
        local kids = children_map[info.ppid] or {}
        kids[#kids + 1] = info
        children_map[info.ppid] = kids
      end
    end

    if not info_map[root_pid] then
      cb({ info_entry('empty', 'Process ' .. root_pid .. ' not found (may have exited)', 'yellow') })
      return
    end

    for ppid, kids in pairs(children_map) do
      table.sort(kids, function(a, b) return a.pid < b.pid end)
    end

    local direct_counts = {}
    for ppid, kids in pairs(children_map) do
      direct_counts[ppid] = #kids
    end

    -- 父进程链：从直接父进程一路向上到顶层（都是不缩进的单行）
    local chain = {}
    local seen_chain = {}
    local cur = info_map[root_pid].ppid
    while cur and cur ~= 0 and not seen_chain[cur] do
      local info = info_map[cur]
      if not info then break end
      seen_chain[cur] = true
      chain[#chain + 1] = info
      cur = info.ppid
    end

    local entries = {}
    local seen = { [root_pid] = true }
    -- 1) 父进程链：顶层在前、直接父进程在后，不缩进，红色
    for i = #chain, 1, -1 do
      local info = chain[i]
      seen[info.pid] = true
      entries[#entries + 1] = build_tree_entry(info, '', direct_counts[info.pid] or 0, 'red')
    end
    -- 2) pid 本身：不缩进，黄色加粗高亮
    local root_info = info_map[root_pid]
    entries[#entries + 1] = build_tree_entry(root_info, '', direct_counts[root_pid] or 0, 'yellow', true)
    -- 3) 子孙树：缩进
    emit_children(info_map, children_map, direct_counts, root_pid, '', seen, entries)

    page_cache[table.concat(path, '/')] = entries
    cb(entries)
    -- 默认选中 pid 本身（父进程链行不抢占焦点）
    if deck.deep_equal(path, deck.api.get_current_path()) then
      local hover = {}
      for _, seg in ipairs(path) do hover[#hover + 1] = seg end
      hover[#hover + 1] = tostring(root_pid)
      deck.api.set_hovered(hover)
    end
  end))
end

--- path 形如 { 'process' } 或 { 'process', '<pid>', ... }
function M.list(path, cb)
  if not path or #path == 0 then
    cb({})
    return
  end

  -- 同一路径再次进入：直接复用上次构建的 entries，避免来回导航反复执行 ps 刷新
  local cached = page_cache[table.concat(path, '/')]
  if cached then
    cb(cached)
    return
  end

  if #path == 1 then
    list_processes(path, cb)
    return
  end
  -- 进入某个进程后，list 以树状展示它及其所有子进程
  list_process_tree(path, cb)
end

function M.preview(entry, cb)
  if not entry then
    cb(text { line { 'process' } })
    return
  end

  if entry.kind == 'process' then
    action.preview(entry, cb)
    return
  end

  cb(action.info_preview(entry))
end

return M
