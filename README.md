# mpv configuration

Bộ cấu hình mpv cá nhân: giao diện [uosc](https://github.com/tomasklaen/uosc), thumbnail khi tua ([thumbfast](https://github.com/po5/thumbfast)), menu chuột phải đầy đủ, shaders nâng cấp chất lượng hình ảnh và nhiều script tiện ích.

> **Yêu cầu:** mpv **0.40+** (khuyến nghị bản mpv-git mới nhất). Cấu hình dùng các tính năng mới như `script-binding commands/open`, script built-in `positioning`, thuộc tính `clipboard/text` và `autocreate-playlist` — các bản mpv cũ sẽ không hoạt động đầy đủ.

![thumb](https://github.com/tuilakhanh/mpv-conf/assets/17153084/908b4514-d85f-4c99-b9c1-28245795ea94)

## Cài đặt

Clone repo này vào thư mục cấu hình của mpv:

| Hệ điều hành | Đường dẫn |
| --- | --- |
| Windows | `%APPDATA%\mpv` (hoặc `portable_config` cạnh `mpv.exe`) |
| Linux / macOS | `~/.config/mpv` |

```sh
git clone https://github.com/KenShinNguyen/mpv-config <thư-mục-cấu-hình-mpv>
```

Xem/tải phụ đề YouTube và phát URL cần có [yt-dlp](https://github.com/yt-dlp/yt-dlp) trong `PATH`.

## Điểm nổi bật

- **gpu-api tự động theo hệ điều hành**: Windows → `d3d11`, Linux → `vulkan`, macOS → mặc định (xem `profiles.conf`).
- **3 profile chất lượng**: `HighQuality` (RAVU + CfL Prediction), `Balanced` (mặc định), `Fast` — chuyển đổi qua menu chuột phải.
- **Menu chuột phải** (uosc) chứa gần như toàn bộ chức năng: mở file/URL, playlist, track, shaders, screenshot, cắt video…
- **Ưu tiên ngôn ngữ**: audio Nhật → Việt → Anh, phụ đề Việt.
- Screenshot lưu tại `~/Pictures/mpv` (đổi trong `mpv.conf` nếu muốn).

## Phím tắt đáng chú ý

| Phím | Chức năng |
| --- | --- |
| `Chuột phải` / `Shift+m` | Mở menu |
| `Tab` | Ẩn/hiện giao diện |
| `→` | Bấm nhanh: tua tới 5s — Giữ: tua nhanh dần (evafast) |
| `Alt+f` | Bật/tắt chế độ tua nhanh mà không cần giữ phím |
| `Ctrl+v` | Phát file/URL từ clipboard |
| `h` | Lịch sử phát (memo) |
| `Alt+s` | Bật/tắt bỏ qua đoạn quảng cáo YouTube (SponsorBlock) |
| `-` / `y` | Chọn chất lượng video / audio (stream) |
| `Shift+w` | Cắt video thành WebM |
| `Ctrl+Shift+s` | Cắt video lossless |
| `s` / `e` | Screenshot ra file / clipboard |
| `?` | Xem toàn bộ phím tắt |
| `` ` `` | Mở console |

Toàn bộ phím tắt nằm trong [`input.conf`](input.conf).

## Kiểm tra cấu hình

mpv không báo lỗi khi cấu hình sai — nó chỉ ghi một dòng vào log rồi bỏ qua, nên
một phím tắt chết hay một option viết sai chính tả có thể nằm im rất lâu. Script
sau kiểm tra những trường hợp đó mà không cần cài mpv:

```sh
python3 tools/check-config.py   # tính nhất quán của cấu hình
python3 tools/check-lua.py      # cú pháp Lua (cần luajit)
python3 tools/check-tests.py    # test hành vi script (cần luajit)
```

`check-config.py` bắt: `script-binding` trỏ tới script không tồn tại,
`apply-profile` trỏ tới profile chưa định nghĩa, shader thiếu file, hai dòng
`input.conf` gán trùng phím (dòng sau lặng lẽ đè dòng trước), script có phím
mặc định bị `input.conf` chiếm mất nên không gọi được, và key sai chính tả hoặc
bị bọc dấu nháy trong `script-opts/*.conf` (`read_options` không bóc dấu nháy).

`check-lua.py` biên dịch thử mọi file trong `scripts/` bằng **LuaJIT** — đúng
runtime mà mpv nhúng. Script sai cú pháp không làm mpv báo lỗi ra màn hình, nó
chỉ bị bỏ qua, nên biểu hiện duy nhất là "phím tắt tự dưng không ăn".

`check-tests.py` chạy các file `tests/*_spec.lua`. Chúng nạp script thật với một
bộ giả lập API mpv tối thiểu ([`tests/mpv_stub.lua`](tests/mpv_stub.lua)) rồi
kiểm tra hành vi mà không cần mở mpv.

Cả ba chạy tự động trên mỗi push qua GitHub Actions
([`.github/workflows/check-config.yml`](.github/workflows/check-config.yml)).

## Xử lý sự cố

### Phát stream (YouTube/URL) mất tiếng hoặc đứng hình

Hai biểu hiện hay đi cùng nhau: **không có tiếng** và **phát vài giây rồi
đứng hình**. Nguyên nhân nằm ở tầng tải stream, không phải ở audio device —
nếu file local vẫn phát bình thường thì loa/driver không có lỗi.

Lấy log verbose trước khi sửa bất cứ thứ gì:

```sh
mpv --terminal --msg-level=all=v "<URL>" > log.txt 2>&1
```

Mở `log.txt`, tìm `403 Forbidden`, `failed to load segment`, `audio EOF reached`.

**Nguyên nhân 1 — yt-dlp lấy được URL nhưng URL bị YouTube chặn.** Dấu hiệu:

```
stream: Failed to open ...itag=251        ← audio 403 ngay request đầu
timeline: failed to load segment
cplayer: audio EOF reached                 ← mất tiếng hoàn toàn
ffmpeg: https: Will reconnect at 10485760 ... 403 Forbidden
mkv: EOF reached                           ← video chạy hết chunk 10MB rồi đứng
```

Tìm trong log chuỗi `&c=` của URL và `__yt_dlp_client`. Nếu là `ANDROID_VR` /
`android_vr`, yt-dlp đã phải fallback sang client dự phòng (client duy nhất
không cần PO token) nhưng `http_headers` nó khai báo vẫn là User-Agent Chrome.
YouTube đối chiếu chéo và chặn — video qua được chunk đầu rồi 403, audio 403
ngay.

Tách lỗi ra khỏi mpv bằng cách tải trực tiếp đúng format đó:

```sh
yt-dlp -f 251 -o test.webm "<URL>"    # thấy % chạy vài giây là đủ, Ctrl+C rồi xoá
```

(Đừng dùng `-o NUL` trên Windows — yt-dlp hiểu `NUL` thành thư mục và báo lỗi
đường dẫn trước khi kịp tải, không nói lên điều gì.)

- Cũng 403 → lỗi thuộc về yt-dlp/YouTube, mpv vô can. Xử lý theo thứ tự:
  1. `yt-dlp -U` (hoặc `pip install -U yt-dlp`). YouTube đổi cơ chế liên tục,
     bản cũ vài tuần là đủ để hỏng.
  2. Cài PO token provider để yt-dlp dùng lại được client `web`:
     [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider).
  3. Cho yt-dlp mượn cookie trình duyệt — thêm vào `ytdl-raw-options` trong
     `mpv.conf`: `cookies-from-browser=chrome`.
- Tải được bình thường → lỗi ở header mpv gửi đi, không phải ở yt-dlp.

**Nguyên nhân 2 — script proxy tự thêm (VD `http-ytproxy`).** Nếu log có:

```
http_ytproxy: Starting subprocess: [...\http-ytproxy.exe ...]
cplayer: Set property: http-proxy="http://127.0.0.1:6954"
```

thì proxy đó đang đứng giữa và có thể tự nó trả 403. Repo này **không** chứa
script nào như vậy — nếu có là do tự thêm vào `scripts/`. Tắt bằng cách đổi tên
thư mục script đó (thêm hậu tố bất kỳ) rồi mở lại mpv. Lưu ý: tắt proxy mà log
vẫn còn `403 Forbidden` thì proxy không phải thủ phạm, quay lại nguyên nhân 1.

> Đừng ép `extractor-args="youtube:player_client=..."` theo phỏng đoán — chọn
> sai client có thể khiến yt-dlp không lấy được stream nào cả. Chỉ dùng khi log
> chỉ rõ client hiện tại bị chặn và bạn biết client thay thế nào còn chạy được.

## Bảo mật: scheme `mpv://`

[`scripts/protocol_hook.lua`](scripts/protocol_hook.lua) đăng ký `mpv://` làm
protocol handler, nghĩa là **URL đi thẳng từ trình duyệt vào script**. Mọi lệnh
ngoài trong script đều chạy bằng argv (`run` của mpv thực thi trực tiếp, không
qua shell), và URL được lọc ngay tại `on_load` hook.

Một tuỳ chọn cần biết: `mpv://...?app=<base64>` cho phép trang web chỉ định
chương trình để mở link. Tính năng này **mặc định tắt**; muốn dùng phải liệt kê
cụ thể trong `allowed_apps` ở
[`script-opts/protocol_hook.conf`](script-opts/protocol_hook.conf).

## Scripts and Shaders Credits

- [mpv-player/autocrop](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autocrop.lua)
- [ObserverOfTime/clipshot](https://github.com/ObserverOfTime/mpv-scripts/blob/master/clipshot.lua)
- [po5/evafast](https://github.com/po5/evafast)
- [po5/memo](https://github.com/po5/memo)
- [voz.vn/protocol_hook](https://github.com/FirefoxUniverse/FirefoxTweaksVN/tree/main/mpv)
- [natural-harmonia-gropius/quality-menu](https://github.com/natural-harmonia-gropius/mpv-quality-menu)
- [4e6/mpv-reload](https://github.com/4e6/mpv-reload)
- [snylonue/slicing_copy](https://github.com/snylonue/mpv_slicing_copy) (Modified)
- [jouni/mpv_sponsorblock_minimal](https://codeberg.org/jouni/mpv_sponsorblock_minimal)
- [Sagnac/streamsave](https://github.com/Sagnac/streamsave)
- [po5/thumbfast](https://github.com/po5/thumbfast)
- [tomasklaen/uosc](https://github.com/tomasklaen/uosc)
- [serenae-fansubs/webm](https://github.com/serenae-fansubs/mpv-webm)
- [Idlusen/mpv-ytsub](https://github.com/Idlusen/mpv-ytsub)

---

- [bjin/mpv-prescalers](https://github.com/bjin/mpv-prescalers/tree/master/gather)
    - RAVU
    - NNEDI
- [igv/gist](https://gist.github.com/igv)
    - KrigBilateral.glsl
- [Artoriuz/glsl-chroma-from-luma-prediction](https://github.com/Artoriuz/glsl-chroma-from-luma-prediction)
    - CfL_Prediction.glsl
- [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN)
    - ArtCNN (Compute Version)
- [an3223/shaders](https://github.com/AN3223/dotfiles/tree/master/.config/mpv/shaders)
    - nlmeans.glsl
    - hdeband.glsl
- [haasn/libplacebo.org](https://libplacebo.org/custom-shaders/#full-example)
    - filmgrain.glsl
