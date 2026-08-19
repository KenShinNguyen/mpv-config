-- sponsorblock_minimal.lua
--
-- This script skips sponsored segments of YouTube videos
-- using data from https://github.com/ajayyy/SponsorBlock
--
-- LOCAL MODIFICATIONS (upstream: https://codeberg.org/jouni/mpv_sponsorblock_minimal)
-- Giữ lại khi cập nhật từ upstream:
--   1. skip_ads() và toggle() kiểm tra `ranges` trước khi dùng.
--   2. end_file() luôn dọn state, kể cả khi ON == false.
--   3. Key binding đăng ký một lần lúc load, không đăng ký trong callback fetch.

local opt = require 'mp.options'
local utils = require 'mp.utils'

local ON = false
local ranges = nil

local options = {
	server = "https://sponsor.ajay.app/api/skipSegments",

	-- Categories to fetch and skip
	categories = '"sponsor"',

	-- Set this to "true" to use sha256HashPrefix instead of videoID
	hash = ""
}

opt.read_options(options)

function skip_ads(name,pos)
	if pos and ranges then
		for _, i in pairs(ranges) do
			v = i.segment[2]
			if i.segment[1] <= pos and v > pos then
				--this message may sometimes be wrong
				--it only seems to be a visual thing though
				mp.osd_message(("[sponsorblock] skipping forward %ds"):format(math.floor(v-mp.get_property("time-pos"))))
				--need to do the +0.01 otherwise mpv will start spamming skip sometimes
				--example: https://www.youtube.com/watch?v=4ypMJzeNooo
				mp.set_property("time-pos",v+0.01)
				return
			end
		end
	end
end

function file_loaded()
	local video_path = mp.get_property("path", "")
	local video_referer = string.match(mp.get_property("http-header-fields", ""), "Referer:([^,]+)") or ""

	local urls = {
		"ytdl://youtu%.be/([%w-_]+).*",
		"ytdl://w?w?w?%.?youtube%.com/v/([%w-_]+).*",
		"https?://youtu%.be/([%w-_]+).*",
		"https?://w?w?w?%.?youtube%.com/v/([%w-_]+).*",
		"/watch.*[?&]v=([%w-_]+).*",
		"/embed/([%w-_]+).*",
		"^ytdl://([%w-_]+)$",
		"-([%w-_]+)%."
	}
	local youtube_id = nil
	local purl = mp.get_property("metadata/by-key/PURL", "")
	for i,url in ipairs(urls) do
		youtube_id = youtube_id or string.match(video_path, url) or string.match(video_referer, url) or string.match(purl, url)
		if youtube_id then break end
	end

	if not youtube_id or string.len(youtube_id) < 11 then return end
	youtube_id = string.sub(youtube_id, 1, 11)

	local args = {"curl", "-L", "-s", "-G", "--data-urlencode", ("categories=[%s]"):format(options.categories)}
	local url = options.server
	if options.hash == "true" then
		local sha = mp.command_native{
			name = "subprocess",
			capture_stdout = true,
			args = {"sha256sum"},
			stdin_data = youtube_id
		}
		url = ("%s/%s"):format(url, string.sub(sha.stdout, 0, 4))
	else
		table.insert(args, "--data-urlencode")
		table.insert(args, "videoID=" .. youtube_id)
	end
	table.insert(args, url)

	local sponsors = mp.command_native{
		name = "subprocess",
		capture_stdout = true,
		playback_only = false,
		args = args
	}
	if sponsors.stdout then
		local json = utils.parse_json(sponsors.stdout)
		if type(json) == "table" then
			if options.hash == "true" then
				for _, i in pairs(json) do
					if i.videoID == youtube_id then
						ranges = i.segments
						break
					end
				end
			else
				ranges = json
			end

			if ranges then
				ON = true
				mp.observe_property("time-pos", "native", skip_ads)
			end
		end
	end
end

function end_file()
	-- Luôn dọn state, kể cả khi người dùng đã tắt bằng toggle (ON == false).
	-- Nếu return sớm ở đây, `ranges` của video trước còn lại; video sau không
	-- phải YouTube sẽ thoát sớm trong file_loaded() và giữ nguyên `ranges` cũ,
	-- nên bật lại sẽ skip nhầm timestamp của video khác.
	-- unobserve_property khi chưa observe là no-op nên gọi vô điều kiện được.
	mp.unobserve_property(skip_ads)
	ranges = nil
	ON = false
end

function toggle()
	if not ranges then
		mp.osd_message("[sponsorblock] no segments for this video")
		return
	end
	if ON then
		mp.unobserve_property(skip_ads)
		mp.osd_message("[sponsorblock] off")
		ON = false
	else
		mp.observe_property("time-pos", "native", skip_ads)
		mp.osd_message("[sponsorblock] on")
		ON = true
	end
end

-- Đăng ký một lần lúc load thay vì bên trong callback fetch: binding luôn tồn
-- tại và deterministic, còn việc "có dữ liệu hay không" do toggle() tự kiểm tra.
mp.add_key_binding("b", "sponsorblock", toggle)

mp.register_event("file-loaded", file_loaded)
mp.register_event("end-file", end_file)
