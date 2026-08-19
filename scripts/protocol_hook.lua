-- protocol_hook.lua
-- handlers.json: https://searchfox.org/mozilla-central/source/uriloader/exthandler/tests/unit/handlers.json
-- named pipe: mpv.exe --input-ipc-server=\\.\pipe\mpvsocket
--
-- LOCAL MODIFICATIONS (upstream: https://github.com/FirefoxUniverse/FirefoxTweaksVN/tree/main/mpv)
-- Giu lai khi cap nhat tu upstream:
--   1. safe_url(): loc URL va tham so ngay tai on_load hook, truoc khi dispatch.
--   2. Moi lenh ngoai chay bang argv (run()) thay vi noi chuoi cho mp.command().
--   3. ipc() ghi thang JSON vao named pipe, khong qua cmd.exe.
--   4. piper() bo pipeline shell, dung yt-dlp -g roi spawn mpv bang argv.
--   5. EA() chi chay app nam trong allowed_apps (mac dinh rong = tat).
--
-- SHELL INJECTION -- vi sao phai doi:
-- Script nay la handler cho scheme mpv://, tuc URL den THANG TU TRINH DUYET.
-- Ban cu dung mp.command('run cmd /c ... ' .. url .. ' ...'). Tren Windows
-- `cmd /c` phan tich lai chuoi do, nen mot dau '&' -- co mat trong gan nhu moi
-- URL YouTube -- da du de cat lenh lam doi va chay lenh thu hai. Ham escape duy
-- nhat cua ban cu, escapeqs(), chi doi '&' thanh '^&' va chi duoc goi trong
-- piper(). Tren Linux khong co shell nen '&' vo hai, nhung URL bat dau bang '-'
-- lai bi streamlink/yt-dlp hieu la option (--player=..., --exec=...) va cung
-- chay duoc lenh tuy y.

local utils = require 'mp.utils'
local msg = require 'mp.msg'
local opts = require "mp.options"

local options = {
    cwd = '',
    ipcMode = false,
    proxy = '',
    nogeometry = true,
    stream_quality = '720p,best,worst',
    -- Danh sach app duoc phep chay qua `mpv://...?app=<base64>`, ngan cach bang
    -- dau phay. De RONG (mac dinh) = tat han tinh nang do: tham so `app` do
    -- trang web quyet dinh, nen neu khong gioi han thi bat ky trang nao cung
    -- chay duoc chuong trinh bat ky tren may.
    allowed_apps = '',
}

opts.read_options(options, "protocol_hook")


-- MPV folder
local cwd = options.cwd
--Beta feature, Windows only (for now), true = on, false = off. check -- named pipe
local ipcMode = options.ipcMode
local proxy = options.proxy
print(proxy)
if proxy == '' then
    proxy = false
end
print(proxy)
local nogeometry = options.nogeometry
local stream_quality = options.stream_quality

local allowed_apps = {}
for app in options.allowed_apps:gmatch('[^,]+') do
    allowed_apps[app:match('^%s*(.-)%s*$')] = true
end

print(cwd)

local function getOS()
    local BinaryFormat = package.cpath
    --print(BinaryFormat)
    if BinaryFormat:match("dll$") then
        return "Windows"
    elseif BinaryFormat:match("so$") then
        if BinaryFormat:match("homebrew") then
            return "MacOS"
        else
            return "Linux"
        end
    elseif BinaryFormat:match("dylib$") then
        return "MacOS"
    end
end

local function exedir()
    --local path1 = debug.getinfo(1).source
    local path = mp.command_native({'expand-path', '~~home/'})
    print(path)
    path = path:gsub('/portable_config.*', '')
    print(path)
    return path
end

local osv = getOS()
if cwd == '' then
    cwd = exedir()
    print(cwd)
end

--[[function getOS(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

function getOS()
	-- ask LuaJIT first
	if jit then
		return jit.os
	end

	-- Unix, Linux variants
	local fh,err = assert(io.popen("uname -o 2>/dev/null","r"))
	if fh then
		osname = fh:read()
	end

	return osname or "Windows"
end

print(getOS())]]--



--print(getOS())

local function parseqs(url)
    -- return 0-based index to use with --playlist-start

    local query = url:match("%?.+")
    if not query then return nil end

    local args = {}
    for arg, param in query:gmatch("(%a+)=([^&?]+)") do
        if arg and param then
            args[arg] = param
        end
    end
    return args
end

local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

local function split(text, delim)
    -- returns an array of fields based on text and delimiter (one character only)
    local result = {}
    local magic = "().%+-*?[]^$"

    if delim == nil then
        delim = "%s"
    elseif string.find(delim, magic, 1, true) then
        -- escape magic
        delim = "%"..delim
    end

    local pattern = "[^"..delim.."]+"
    for w in string.gmatch(text, pattern) do
        table.insert(result, w)
    end
    return result
end

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' -- You will need this for encoding/decoding
-- encoding
local function enc(data)
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- decoding
local function dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
    end))
end

local function atobUrl(url)
    url = string.gsub(url, '_', '/')
    url = string.gsub(url, '-', '+')
    url = dec(url)
    return url
end

local function regexEscape(str)
    return str:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
end
-- you can use return and set your own name if you do require() or dofile()

-- like this: str_replace = require("string-replace")
-- return function (str, this, that) -- modify the line below for the above to work
local function replace (str, this, that)
    return str:gsub(regexEscape(this), that:gsub("%%", "%%%%")) -- only % needs to be escaped for 'that'
end

local function exec(args)
    print("Running: " .. table.concat(args, " "))

    return mp.command_native({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
    })
end

local function stripqs(s)
    return string.gsub(s, '&.*', '')
end

-- (Da xoa escapeqs(): no chi doi '&' -> '^&' cho cmd.exe. Sau khi moi lenh
-- deu chay bang argv thi khong con shell nao de escape, va giu lai mot ham
-- ten "escape" khong con tac dung se de gay hieu nham la co bao ve.)

-- Ky tu KHONG BAO GIO duoc phep xuat hien nguyen ban trong URL (RFC 3986 goi la
-- "excluded"): khoang trang, " < > \ ^ ` { } | va moi ky tu dieu khien. URL that
-- se ma hoa chung thanh %XX. Do cung dung la tap ky tu dieu khien shell, nen
-- chan o day vua khong pha URL hop le vua bit duong tan cong.
-- Luu y: '&' va '%' KHONG bi chan vi chung hop le trong query string; an toan
-- cua chung do viec moi lenh deu chay bang argv (khong co shell) bao dam.
local URL_FORBIDDEN = '[%s"<>\\%^`{}|%c]'

-- Tra ve url neu an toan, nguoc lai tra ve nil + ly do.
local function safe_url(url, what)
    what = what or 'URL'
    if type(url) ~= 'string' or url == '' then
        return nil, what..' rong'
    end
    local bad = url:match(URL_FORBIDDEN)
    if bad then
        return nil, string.format('%s chua ky tu khong hop le (%q)', what, bad)
    end
    -- Chuoi bat dau bang '-' se bi moi cong cu CLI hieu la option. Vi du
    -- '--exec=calc.exe' cho yt-dlp hay '--player=cmd' cho streamlink deu chay
    -- duoc lenh tuy y du khong he co shell.
    if url:sub(1, 1) == '-' then
        return nil, what..' bat dau bang "-" nen se bi hieu la option'
    end
    return url
end

local function reject(reason)
    msg.error('tu choi: '..tostring(reason))
    mp.osd_message('protocol_hook: tu choi URL khong an toan', 4)
end

-- Chay chuong trinh ngoai bang argv. `run` cua mpv thuc thi truc tiep, KHONG
-- qua shell, nen moi phan tu trong args den chuong trinh dich nguyen ven --
-- khong con quoting hay ky tu dieu khien nao duoc dien giai.
-- mpv thuong nhung LuaJIT (unpack la global, Lua 5.1) nhung cung co ban dung
-- Lua 5.2+ (table.unpack). Nhan ca hai.
local unpack = unpack or table.unpack

local function run(args)
    msg.info('run: '..table.concat(args, ' '))
    mp.commandv('run', unpack(args))
end

function magiclines(s)
        if s:sub(-1)~="\n" then s=s.."\n" end
        return s:gmatch("(.-)\n")
end

local function getDomain(url)
    return split(url, '/')[2]
end

local function livestreamer(url, referer, proxy, hls)
    print('Streamlink: '..url)
    local args = {}
    if osv == 'Windows' then
        args[#args + 1] = cwd..'/streamlink/bin/streamlink.exe'
    else
        args[#args + 1] = 'streamlink'
    end
    args[#args + 1] = url
    args[#args + 1] = stream_quality
    args[#args + 1] = '--config='..cwd..'/streamlink.conf'
    if (hls == true) then
        args[#args + 1] = '--player-args=--demuxer-lavf-format=mpegts'
    end
    if proxy ~= false then
        args[#args + 1] = '--http-proxy='..proxy..'/'
    end
    if referer ~= '' then
        args[#args + 1] = '--http-header=Referer='..referer
    end
    run(args)
end

-- Thank to pTalent: https://voz.vn/t/tong-hop-nhung-addon-chat-cho-firefox-pc-mobile.682181/post-27975348
local function iptv(url, referer, proxy, hls)
    print('IPTV: '..url)
    local url2 = '"'..url..'"'
    local playlist = false
    --if (url:find("hls://") == 1) then
    if (hls == true) then
        playlist = true
        --url = string.gsub(url, 'hls:', 'https:')
    end
    
    local curlpath = ''
    local mpvpath = ''
    local cmdcurl = ''
    local cmdmpv = ''
    local stdout = ''
    local stdfin = ''
    local domain = getDomain(url)
    print(domain)
    print(dump(split(url, '/')))
    if osv == 'Windows' then
        -- Khong duoc co khoang trang cuoi: day la phan tu argv[0], di thang
        -- vao execvp/CreateProcess chu khong qua shell de duoc cat bo.
        curlpath = cwd..'/curl.exe'
    else
        curlpath = 'curl'
    end
    if osv == 'Windows' then
        mpvpath = cwd..'/mpv.exe'
    else
        mpvpath = 'mpv'
    end

	local args = {curlpath, url, "-L", '-s'}
    print(dump(args))
	local p = mp.command_native{
		name = "subprocess",
		capture_stdout = true,
		playback_only = false,
		args = args
	}
	if p.stdout then
        for line in magiclines(p.stdout) do
            if (line:find('/') == 1) then
                stdout = stdout..'https://'..domain..line..'\n'
            else
                stdout = stdout..line..'\n'
            end
        end
        --stdout = string.gsub(stdout, '/hls/', 'https://'..domain..'/hls/')
        print(stdout)
        f = io.open(cwd..'/dummy.m3u8', 'w')
        f:write(stdout)
        f:close()

        if playlist == true then
            mp.commandv('set', 'ytdl', 'no')
            mp.commandv('set', 'prefetch-playlist', 'yes')
            mp.commandv('set', 'demuxer-lavf-format', 'mpegts')
            mp.commandv('loadlist', cwd..'/dummy.m3u8')
        else
            mp.commandv('loadfile', cwd..'/dummy.m3u8')
        end
	end

    --cmdcurl = curlpath..' -L '..url2..' -o magicList.m3u8'
    --cmdmpv = mpvpath..' magicList.m3u8'
    --mp.command(cmdcurl)
    --mp.command(cmdmpv)
    --mp.commandv('loadfile', 'magicList.m3u8')
    --mp.command('quit')
end

local function mpv(url, referer, proxy, command)
    print('MPV: '..url)
    local args = {}
    if osv == 'Windows' then
        args[#args + 1] = cwd..'/mpv.exe'
    else
        args[#args + 1] = 'mpv'
    end
    if proxy ~= false then
        args[#args + 1] = '--http-proxy='..proxy..'/'
    end
    if command then
        url = string.gsub(url, '?geometry', '?geometry2')
        args[#args + 1] = command
    end
    -- '--' de mpv khong hieu nham URL la option.
    args[#args + 1] = '--'
    args[#args + 1] = url
    run(args)
end

local function EA(url, referer, app)
    print('EA: '..url)
    -- `app` do query string cua trang web quyet dinh, tuc la ten chuong trinh
    -- chay o day den tu ben ngoai. Chuyen sang argv khong giup gi cho viec do
    -- -- van la "trang bat ky chay chuong trinh bat ky" -- nen phai co
    -- allowlist. Mac dinh rong => tinh nang tat.
    if not allowed_apps[app] then
        reject('app "'..tostring(app)..'" khong nam trong allowed_apps '
            ..'(dat trong script-opts/protocol_hook.conf de bat)')
        return
    end
    run({app, url})
end

local function ytdl(url, referer, mode)
    print('YTDL: '..url)
    local args = {}
    if osv == 'Windows' then
        args[#args + 1] = cwd..'/yt-dlp.exe'
        -- Ban cu dung 'cmd /c cd /d <cwd> && start yt-dlp.exe' chi de (a) luu
        -- vao <cwd> va (b) chay nen. '-P' lo viec (a) ma khong can shell, con
        -- (b) thi 'run' cua mpv von da bat dong bo nen khong can 'start'.
        args[#args + 1] = '-P'
        args[#args + 1] = cwd
    else
        -- Tren Linux ban cu khong doi thu muc, giu nguyen de khong thay doi
        -- noi file duoc tai ve.
        args[#args + 1] = 'yt-dlp'
    end
    if mode == 'audio' then
        args[#args + 1] = '-f'
        args[#args + 1] = 'ba'
        args[#args + 1] = '--extract-audio'
    end
    args[#args + 1] = '--'
    args[#args + 1] = url
    run(args)
end

local function exec2(args)
    local ret = utils.subprocess({args = args})
    return ret.status, ret.stdout, ret
end

local function gallery(url, referer)
    local es, urls, result = exec2({"gallery-dl", "-g", url})
    print(urls)
    if (es < 0) or (urls == nil) or (urls == "") then
        msg.error("failed to get album list.")
    end
    msg.info(urls)
    mp.commandv("loadlist", "memory://" .. urls)
end

local IPC_PIPE = '\\\\.\\pipe\\mpvsocket'

local function ipc(url, mode)
    -- Ban cu: run cmd /c echo loadfile <url> <mode> >\\.\pipe\mpvsocket
    -- URL khong he duoc quote, nen chi mot dau '&' -- co trong hau het URL
    -- YouTube -- la cmd.exe cat lenh lam doi va chay ve sau nhu lenh rieng.
    -- Khong con di qua shell nua: mpv IPC nhan JSON tren named pipe, va
    -- format_json lo phan escape.
    local payload = utils.format_json({command = {'loadfile', url, mode}})
    if payload == nil then
        msg.error('khong tao duoc JSON cho IPC')
        return
    end
    local pipe, err = io.open(IPC_PIPE, 'w')
    if not pipe then
        msg.error('khong mo duoc IPC pipe '..IPC_PIPE..': '..tostring(err)
            ..' -- can chay mpv voi --input-ipc-server='..IPC_PIPE)
        return
    end
    pipe:write(payload..'\n')
    pipe:close()
end

local function piper(url, mode, proxy, hls)
    -- Ban cu chay: yt-dlp <opts> -o - <url> | mpv - <opts>
    -- Pipeline bat buoc phai co shell, va URL thi noi thang vao chuoi lenh.
    -- Khong the quote an toan: mp.command() tu boc dau nhay cua chuoi truoc khi
    -- cmd.exe kip nhin thay, con mpv thi quote argv theo quy uoc MSVC ma cmd.exe
    -- lai khong hieu. Nen bo han pipeline.
    --
    -- Thay vao do lay URL truc tiep bang 'yt-dlp -g' roi spawn mpv bang argv.
    -- Cach nay von da duoc dung san cho track audio (--audio-file=<url tu -g>),
    -- gio ap dung cho ca video de bo duoc shell.
    --
    -- KHAC BIET HANH VI: yt-dlp khong con lam nguoi tai nua, mpv tu keo URL
    -- truc tiep. URL tu -g co han su dung, nen video rat dai co the phai mo lai.
    print(proxy)
    local playlist = (hls == true)

    local ytdlp = (osv == 'Windows') and (cwd..'/yt-dlp.exe') or 'yt-dlp'

    -- Goi yt-dlp -g voi format chi dinh, tra ve danh sach URL truc tiep.
    local function resolve(format)
        local args = {ytdlp}
        if proxy ~= false then
            args[#args + 1] = '--proxy'
            args[#args + 1] = proxy
        end
        if format then
            args[#args + 1] = '-f'
            args[#args + 1] = format
        end
        args[#args + 1] = '-g'
        args[#args + 1] = '--'
        args[#args + 1] = url
        local p = mp.command_native{
            name = 'subprocess',
            capture_stdout = true,
            capture_stderr = true,
            playback_only = false,
            args = args,
        }
        local out = {}
        if p and p.status == 0 and p.stdout then
            for line in p.stdout:gmatch('[^\r\n]+') do
                local ok, why = safe_url(line, 'URL tu yt-dlp')
                if ok then
                    out[#out + 1] = ok
                else
                    msg.warn('bo qua '..tostring(why))
                end
            end
        else
            msg.error('yt-dlp -g that bai: '..tostring(p and p.stderr or 'khong chay duoc'))
        end
        return out
    end

    local videourl, audiourl
    if string.find(url, 'youtube.com', 1, true) then
        videourl = resolve('bv[height^>=?1080][vcodec*=?avc1]')[1]
        audiourl = resolve('ba')[1]
    else
        -- Khong chi dinh format: yt-dlp co the tra ve 1 dong (da gop) hoac 2
        -- dong (video roi audio).
        local urls = resolve(nil)
        videourl, audiourl = urls[1], urls[2]
    end

    if not videourl then
        reject('yt-dlp khong tra ve URL nao dung duoc cho '..url)
        return
    end

    local args = {}
    args[#args + 1] = (osv == 'Windows') and (cwd..'/mpv.exe') or 'mpv'
    if audiourl then
        args[#args + 1] = '--audio-file='..audiourl
    end
    if proxy ~= false then
        args[#args + 1] = '--http-proxy='..proxy
    end
    if playlist then
        args[#args + 1] = '--demuxer-lavf-format=mpegts'
    end
    args[#args + 1] = '--'
    args[#args + 1] = videourl
    run(args)
end

--print(dump(mp))
--print(mp.find_config_file('.'))
--print(utils.join_path(mp.find_config_file('.'),"streamlink"))
--print(dump(debug.getinfo(1)))
--print(debug.getinfo(1).source)
--current_dir=io.popen"cd":read'*l'
--print(current_dir)
--print(package.path)
--print(package.cpath)
--print(os.getenv('PATH'))
print(dump(options))



if ipcMode == true then
    local ipc = mp.get_property("input-ipc-server", "")
    if ipc ~= "" then
        ipcMode = false
    end
end

local hook_count = 0

mp.add_hook("on_load", 1, function()
    local mode = 'append-play'
    local referer = ''
    local ourl = mp.get_property("stream-open-filename", "")
    local url = ourl
    local qs = {}
    local autopip = false
    local start = false
    local audio = false
    local playlist = false
    local pipe = false
    local hls = false
    if osv == 'MacOS' then
        url = 'mpv://'..url
    end
    if (url:find("mpv://") ~= 1) then
        print("not a mpv url: " .. url)
        return
    end
    --mp.set_property("stream-open-filename", "memory://")
    --mp.commandv('playlist-clear')
    --mp.commandv('playlist-remove', 'current')
    -- `ourl` la chuoi mpv://... nhan tu trinh duyet; no duoc chuyen tiep sang
    -- mpv()/ipc() nen phai qua cung mot bo loc.
    local ok, why = safe_url(ourl, 'mpv:// URL')
    if not ok then
        reject(why)
        return
    end

    local arr = split(url, '/')
    if arr[1] == 'mpv:' then
        url = atobUrl(arr[3])
        if (url:find("data:") == 1) then
            url = atobUrl(split(url, ',')[2])
            --print(url)
        end

        -- CHOT AN TOAN: `url` vua duoc giai base64 tu trang web, va tu day tro
        -- xuong no di vao moi ham spawn chuong trinh ngoai. Loc mot lan o day
        -- de moi nhanh dispatch phia sau deu duoc bao ve.
        local ok2, why2 = safe_url(url, 'URL da giai ma')
        if not ok2 then
            reject(why2)
            return
        end

        if arr[4] then
            qs = parseqs(arr[4])
        end
        local function subadd()
            local subs = qs['subs']
            subs = atobUrl(subs)
            mp.commandv('sub-add', subs)
        end
        local function cleanup()
            mp.commandv("playlist-remove", "0")
        end
        --mp.register_event("file-loaded", cleanup)
        if qs['subs'] then
            mp.register_event("file-loaded", subadd)
        end
        if qs['referer'] then
            referer = atobUrl(qs['referer'])
            local ok3, why3 = safe_url(referer, 'referer')
            if not ok3 then
                reject(why3)
                return
            end
            print(referer)
        end
        if qs['autopip'] then
            autopip = true
            ourl = string.gsub(ourl, '?autopip=1', '')
        end
        if qs['hls'] then
            hls = true
        end
        if qs['start'] then
            start = qs['start']
        end
        if arr[2] == 'mpv69' then
            arr[2] = 'play'
            proxy = 'http://127.0.0.1:9966'
        end
        if arr[2] == 'ls69' then
            arr[2] = 'stream'
            proxy = 'http://127.0.0.1:9966'
        end
        if arr[2] == 'mpva' then
            arr[2] = 'play'
            audio = true
        end
        if arr[2] == 'mpvp' or arr[2] == 'list' then
            arr[2] = 'play'
            mp.commandv('set', 'ytdl', 'no')
            playlist = true
        end
        if arr[2] == 'mpvi' then
            arr[2] = 'play'
            autopip = true
        end
        if arr[2] == 'mpvy' then
            arr[2] = 'play'
            pipe = true
        end
        if arr[2] == 'ytdla' then
            arr[2] = 'ytdl'
            audio = true
        end
        if referer ~= '' then
            mp.commandv('set', 'http-header-fields', 'Referer: '..referer)
        end
        if proxy ~= false then
            local ytdlrawoptions = mp.get_property_native('ytdl-raw-options', '')
            --print(dump(ytdlrawoptions))
            ytdlrawoptions['proxy'] = proxy
            --mp.commandv('set', 'http-proxy', proxy..'/')
            --mp.commandv('set', 'ytdl-raw-options', 'proxy='..proxy..','..ytdlrawoptions)
            mp.set_property('http-proxy', proxy..'/')
            --mp.set_property('ytdl-raw-options', 'proxy='..proxy..','..ytdlrawoptions)
            mp.set_property_native('ytdl-raw-options', ytdlrawoptions)
            --local ytdlrawoptions = mp.get_property_native('ytdl-raw-options', '')
            --print(dump(ytdlrawoptions))
        end
        if arr[2] == 'play' then
            --local pp = mp.get_property('playlist-pos')
            --mp.commandv('playlist-remove', pp)
            if audio == true then
                mp.commandv('set', 'video', 'no')
            end
            if start ~= false then
                mp.commandv('set', 'start', start)
            end
            if ipcMode == false then
                if pipe == true then
                    piper(url, false, proxy, hls)
                    return
                end
                if qs['geometry'] and nogeometry == false then
                    -- Chi cho phep dang WxH[+X+Y] / phan tram, de gia tri nay
                    -- khong bien thanh mot option mpv khac.
                    if not qs['geometry']:match('^[%d%%xX%+%-:%.]+$') then
                        reject('geometry khong hop le: '..tostring(qs['geometry']))
                        return
                    end
                    mpv(ourl, referer, proxy, '--geometry='..qs['geometry'])
                    return
                end
                if autopip == true then
                    ipc(ourl, 'replace')
                else
                    for link in string.gmatch(url, "[^%s]+") do

                        
                        if hook_count > 0 then
                            mode = 'replace'
                        end
                        if playlist == false then
                            mp.commandv('loadfile', link, mode)
                        else
                            --mp.commandv('loadlist', link, mode)
                            iptv(url, referer, proxy, hls)
                        end
                        if hook_count > 0 then
                            mp.commandv('loadfile', ourl, 'append')
                        end
                    end
                end
            else
                ipc(ourl, 'append-play')
            end
        elseif arr[2] == 'stream' then
            for link in string.gmatch(url, "[^%s]+") do
                livestreamer(link, referer, proxy, hls)
            end
            --livestreamer(url, referer)
        elseif arr[2] == 'ytdl' then
            for link in string.gmatch(url, "[^%s]+") do
                if audio == false then
                    ytdl(link, referer, 'video')
                else
                    ytdl(link, referer, 'audio')
                end
            end
            --ytdl(url, referer, 'video')
        elseif arr[2] == 'mg' then
            for link in string.gmatch(url, "[^%s]+") do
                gallery(link, referer)
            end
            --ytdl(url, referer, 'audio')
        elseif qs['app'] then
            for link in string.gmatch(url, "[^%s]+") do
                local app = qs['app']
                app = atobUrl(app)
                EA(link, referer, app)
            end
            --local app = qs['app']
            --app = atobUrl(app)
            --EA(url, referer, app)
        end
        hook_count = hook_count + 1
    end
end)

