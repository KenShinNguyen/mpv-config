-- Bo gia lap toi thieu API mpv, du de nap va chay mot script trong scripts/
-- ben ngoai mpv. Muc dich: kiem chung logic dispatch va -- quan trong nhat --
-- ghi lai CHINH XAC nhung gi script yeu cau he dieu hanh chay.
--
-- Diem mau chot: mp.commandv('run', a, b, c) ghi lai mot bang argv, con
-- mp.command('run ...') ghi lai mot chuoi duy nhat co danh dau
-- '<<STRING-COMMAND>>'. Nho vay test phan biet duoc "truyen tham so bang argv"
-- (an toan) voi "noi chuoi roi de shell phan tich lai" (co the bi inject).

local stub = {}

stub.spawned = {}   -- moi lenh ngoai da duoc yeu cau chay
stub.rejected = {}  -- moi thong bao loi (URL bi tu choi)
stub.props = {}
stub.hook = nil

-- stdout gia cho `yt-dlp -g`; test co the ghi de.
stub.subprocess_stdout = 'https://direct.example/video.mp4\n'

function stub.reset()
    stub.spawned, stub.rejected = {}, {}
end

local mp = {}

function mp.commandv(...)
    local a = {...}
    if a[1] == 'run' then
        local argv = {}
        for i = 2, #a do argv[#argv + 1] = a[i] end
        table.insert(stub.spawned, argv)
    end
end

function mp.command(cmd)
    -- Bat ky lenh nao van con di qua duong chuoi deu bi danh dau ro rang.
    table.insert(stub.spawned, {'<<STRING-COMMAND>>', cmd})
end

function mp.command_native(t)
    if t[1] == 'expand-path' then return '/fake/mpv/config' end
    if t.name == 'subprocess' then
        table.insert(stub.spawned, t.args)
        return {status = 0, stdout = stub.subprocess_stdout, stderr = ''}
    end
    return nil
end

function mp.get_property(k, d) return stub.props[k] or d end
function mp.get_property_native(k, d) return stub.props[k] or d end
function mp.get_property_number(k, d) return tonumber(stub.props[k]) or d end
function mp.get_property_bool(k, d) return stub.props[k] or d end
function mp.set_property(k, v) stub.props[k] = v end
function mp.set_property_native(k, v) stub.props[k] = v end
function mp.set_property_bool(k, v) stub.props[k] = v end
function mp.osd_message() end
function mp.register_event() end
function mp.register_script_message() end
function mp.observe_property() end
function mp.unobserve_property() end
function mp.add_key_binding() end
function mp.add_forced_key_binding() end
function mp.add_periodic_timer() return {kill = function() end} end
function mp.add_hook(_, _, fn) stub.hook = fn end
function mp.get_script_name() return 'stub' end

local utils = {}
function utils.format_json(t)
    local function esc(v)
        return '"' .. tostring(v):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
    end
    local parts = {}
    for _, v in ipairs(t.command or {}) do parts[#parts + 1] = esc(v) end
    return '{"command":[' .. table.concat(parts, ',') .. ']}'
end
function utils.subprocess(t)
    table.insert(stub.spawned, t.args)
    return {status = 0, stdout = ''}
end
function utils.file_info() return nil end
function utils.join_path(a, b) return a .. '/' .. b end
function utils.parse_json() return nil end

local msg = {}
function msg.error(s) table.insert(stub.rejected, s) end
function msg.warn() end
function msg.info() end
function msg.verbose() end
function msg.debug() end

local mpoptions = {}
function mpoptions.read_options() end

package.preload['mp'] = function() return mp end
package.preload['mp.utils'] = function() return utils end
package.preload['mp.msg'] = function() return msg end
package.preload['mp.options'] = function() return mpoptions end
package.preload['mp.input'] = function() return {select = function() end} end

mp.utils = utils
mp.msg = msg
mp.options = mpoptions
_G.mp = mp

stub.mp = mp
return stub
