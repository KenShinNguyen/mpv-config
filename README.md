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

### Phát stream (YouTube/URL) không có tiếng

YouTube đang dần triển khai giao thức streaming mới (SABR) khiến các format
audio-only dạng DASH mà yt-dlp trước giờ vẫn dùng bị chặn hoặc thiếu URL. Khi
đó `ytdl-format=bestvideo+bestaudio/best` có thể fallback nhầm sang một format
chỉ có video, không có audio — phát vẫn chạy bình thường nhưng im lặng.

Cách khắc phục:

1. **Cập nhật yt-dlp lên bản mới nhất** — đây là nguyên nhân phổ biến nhất,
   vì các bản cũ chưa có cơ chế fallback qua client khác (`tv`, `ios`...) khi
   client mặc định bị chặn SABR:
   ```sh
   yt-dlp -U
   # hoặc: pip install -U yt-dlp
   ```
2. `mpv.conf` đã đặt `ytdl-format=bestvideo+bestaudio/best[acodec!=none]/best`
   để đảm bảo nếu phải fallback, mpv luôn chọn format có audio thay vì chọn
   nhầm video-only.
3. Nếu vẫn mất tiếng ở một video cụ thể, mở console (`` ` ``) rồi xem log —
   dòng `Some ... formats have been skipped as they are missing a url` hoặc
   `YouTube is forcing SABR streaming` xác nhận đúng nguyên nhân trên.

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
