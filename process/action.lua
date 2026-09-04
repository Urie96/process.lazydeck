local M = {}

local function line(parts) return deck.style.line(parts) end
local function text(lines) return deck.style.text(lines) end
local function span(value, color)
  local s = deck.style.span(tostring(value or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function current_entry()
  local entry = deck.api.get_hovered()
  if not entry or entry.kind ~= 'process' or not entry.pid then return nil end
  return entry
end

local function do_kill(entry, signal)
  entry = entry or current_entry()
  if not entry then
    deck.notify 'No process selected'
    return
  end

  local args = { 'kill' }
  if signal then args[#args + 1] = signal end
  args[#args + 1] = tostring(entry.pid)
  deck.system(args, function(out)
    if out.code == 0 then
      deck.cmd 'reload'
      return
    end
    deck.notify('Failed to kill process: ' .. tostring(out.stderr or 'unknown error'))
  end)
end

function M.kill(entry)
  -- SIGTERM (15)
  do_kill(entry)
end

function M.kill9(entry)
  -- SIGKILL (9)
  do_kill(entry, '-9')
end

function M.preview(entry, cb)
  if not entry then
    cb(text {
      line { span('Select a process to preview', 'darkgray') },
    })
    return
  end

  if entry.kind ~= 'process' then
    cb(M.info_preview(entry))
    return
  end

  local parts = {}

  local fields = {
    { 'PID', entry.pid },
    { 'PPID', entry.ppid },
    { 'USER', entry.user },
    { 'UID', entry.uid },
    { 'CPU', entry.cpu and entry.cpu .. '%' },
    { 'MEM', entry.mem and entry.mem .. '%' },
    { 'STATE', entry.stat },
    { 'TTY', entry.tty },
    { 'NICE', entry.nice },
    { 'ELAPSED', entry.etime },
  }
  for _, f in ipairs(fields) do
    parts[#parts + 1] = line {
      span(string.format('%-8s', f[1]), 'cyan'),
      span(tostring(f[2] or '-')),
    }
  end

  if entry.command and entry.command ~= '' then
    parts[#parts + 1] = line { span('') }
    parts[#parts + 1] = line { span('COMMAND', 'cyan') }
    parts[#parts + 1] = line { span(entry.command) }
  end

  if entry.child_count ~= nil then
    parts[#parts + 1] = line { span('') }
    parts[#parts + 1] = line {
      span(string.format('Children: %d  ', entry.child_count), 'green'),
      span('(press → to view the child process tree)', 'darkgray'),
    }
  end

  cb(text(parts))
end

function M.info_preview(entry)
  return text {
    line { span(entry.message or 'Info', entry.color or 'darkgray') },
  }
end

return M
