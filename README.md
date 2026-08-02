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
| `Ctrl+v` | Phát file/URL từ clipboard |
| `h` | Lịch sử phát (memo) |
| `-` / `y` | Chọn chất lượng video / audio (stream) |
| `Shift+w` | Cắt video thành WebM |
| `Ctrl+Shift+s` | Cắt video lossless |
| `s` / `e` | Screenshot ra file / clipboard |
| `?` | Xem toàn bộ phím tắt |
| `` ` `` | Mở console |

Toàn bộ phím tắt nằm trong [`input.conf`](input.conf).

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
