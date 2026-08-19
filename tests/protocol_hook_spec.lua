-- Kiem tra protocol_hook.lua khong con truyen du lieu tu trinh duyet vao shell.
--
-- protocol_hook la handler cua scheme mpv://, nen URL o day den THANG tu trang
-- web. Test nay chay dung ham dispatch that (on_load hook) va kiem tra hai dieu:
--
--   1. Khong lenh ngoai nao con duoc dung bang cach noi chuoi.
--   2. Payload tan cong khong bao gio tro thanh mot phan tu argv rieng -- tuc
--      la no khong the bien thanh lenh hay option thu hai.
--
-- Chay: python3 tools/check-tests.py   (hoac: luajit tests/protocol_hook_spec.lua)

local here = arg[0]:match('^(.*)[/\\][^/\\]*$') or '.'
package.path = here .. '/?.lua;' .. package.path
local stub = require('mpv_stub')

local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        io.write(string.format('  SAI: %s\n       %s\n', name, tostring(detail)))
    end
end

-- base64url, khop voi atobUrl() cua script
local B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64(data)
    return ((data:gsub('.', function(x)
        local r, byte = '', x:byte()
        for i = 8, 1, -1 do r = r .. (byte % 2^i - byte % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) end
        return B:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end
local function b64url(s) return (b64(s):gsub('/', '_'):gsub('%+', '-')) end

-- Script goi print() rat nhieu, ca luc nap lan luc dispatch. Tat han; ket qua
-- test deu di qua io.write nen khong bi anh huong.
_G.print = function() end
dofile(here .. '/../scripts/protocol_hook.lua')

assert(stub.hook, 'protocol_hook chua dang ky on_load hook')

local function dispatch(action, rawurl, query)
    stub.reset()
    local u = 'mpv://' .. action .. '/' .. b64url(rawurl)
    if query then u = u .. '/' .. query end
    stub.props['stream-open-filename'] = u
    stub.hook()
    return stub.spawned
end

local function flat(spawned)
    local out = {}
    for _, argv in ipairs(spawned) do out[#out + 1] = table.concat(argv, ' \30 ') end
    return table.concat(out, ' || ')
end

-- Payload chua ky tu dieu khien shell hoac dan dau bang '-' (option injection).
local ATTACKS = {
    'https://x/?a=1" & calc.exe & "',
    'https://x/|calc.exe',
    'https://x/`calc.exe`',
    'https://x/&calc.exe',
    '--exec=calc.exe',
    '-oevil/etc/passwd',
    'https://x/\ncalc.exe',
    'https://x/ && calc.exe',
    'https://x/^&calc.exe',
    'https://x/>owned.txt',
    'https://x/;calc.exe',
}

-- Cac action lam script spawn chuong trinh ngoai.
local SPAWNING = { 'stream', 'ytdl', 'ytdla', 'mpvy', 'mg' }

io.write('== Payload tan cong tren moi action co spawn lenh ngoai ==\n')
for _, action in ipairs(SPAWNING) do
    for _, attack in ipairs(ATTACKS) do
        local spawned = dispatch(action, attack)
        local joined = flat(spawned)
        local via_string = joined:find('<<STRING-COMMAND>>', 1, true) ~= nil
        local bad_argv = false
        for _, argv in ipairs(spawned) do
            for _, a in ipairs(argv) do
                -- Payload xuat hien nguyen ven nhu MOT phan tu argv thi vo hai
                -- (chuong trinh dich nhan no nhu du lieu). Nguy hiem la khi no
                -- bi tach ra thanh phan tu rieng => da thanh lenh/option.
                if a ~= attack and (a:find('calc.exe', 1, true)
                        or a:find('owned.txt', 1, true)
                        or a:find('/etc/passwd', 1, true)) then
                    bad_argv = true
                end
            end
        end
        check(action .. ' <- ' .. attack:gsub('\n', '\\n'),
              not via_string and not bad_argv, joined)
    end
end

io.write('== URL that phai chay duoc, nguyen ven trong mot phan tu argv ==\n')
local REAL = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s'
for _, action in ipairs({ 'stream', 'ytdl', 'mpvy' }) do
    local spawned = dispatch(action, REAL)
    local intact = false
    for _, argv in ipairs(spawned) do
        for _, a in ipairs(argv) do if a == REAL then intact = true end end
    end
    check(action .. ': URL nguyen ven trong argv', intact, flat(spawned))
    check(action .. ': khong con lenh dang chuoi',
          not flat(spawned):find('<<STRING-COMMAND>>', 1, true), flat(spawned))
end

io.write('== EA: app ngoai allowed_apps phai bi tu choi ==\n')
local spawned = dispatch('play', REAL, '?app=' .. b64url('calc.exe'))
check('app tuy y bi chan khi allowed_apps rong',
      not flat(spawned):find('calc.exe', 1, true), flat(spawned))

io.write(string.format('\nprotocol_hook_spec: %d pass, %d fail\n', pass, fail))
os.exit(fail == 0 and 0 or 1)
