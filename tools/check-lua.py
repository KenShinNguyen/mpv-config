#!/usr/bin/env python3
"""Kiểm tra cú pháp mọi file Lua trong scripts/.

Chạy: python3 tools/check-lua.py

mpv nhúng LuaJIT (tương đương Lua 5.1). Một script sai cú pháp KHÔNG làm mpv
báo lỗi ra màn hình — nó chỉ ghi một dòng vào log rồi bỏ qua script đó, nên
biểu hiện với người dùng chỉ là "phím tắt tự dưng không ăn". Check này biến
lỗi đó thành CI FAIL.

Ưu tiên `luajit` vì đó đúng là runtime của mpv. Các bản Lua độc lập được chấp
nhận như phương án thay thế, nhưng lưu ý cú pháp khác nhau giữa các đời
(`goto` chỉ có từ 5.2, `//` từ 5.3), nên kết quả có thể lệch so với mpv thật.

Exit code: 0 nếu sạch, 1 nếu có lỗi cú pháp, 2 nếu không tìm thấy trình biên
dịch Lua nào.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")

# (tên lệnh, tham số chỉ-kiểm-tra-cú-pháp-không-xuất-file)
CANDIDATES = [
    ("luajit", ["-bl"]),      # đúng runtime của mpv
    ("luac5.1", ["-p"]),
    ("luac", ["-p"]),
    ("luac5.2", ["-p"]),
    ("luac5.4", ["-p"]),
]


def find_compiler() -> tuple[str, list[str]] | None:
    for name, args in CANDIDATES:
        path = shutil.which(name)
        if path:
            return path, args
    return None


def lua_files() -> list[str]:
    found = []
    for dirpath, _dirnames, filenames in os.walk(SCRIPTS):
        for filename in filenames:
            if filename.endswith(".lua"):
                found.append(os.path.join(dirpath, filename))
    return sorted(found)


def main() -> int:
    compiler = find_compiler()
    if compiler is None:
        print(
            "ERROR: không tìm thấy trình biên dịch Lua nào (%s).\n"
            "       Cài luajit để chạy check này: apt install luajit"
            % ", ".join(name for name, _ in CANDIDATES)
        )
        return 2

    path, args = compiler
    failures = 0
    files = lua_files()

    for lua in files:
        result = subprocess.run(
            [path, *args, lua],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            failures += 1
            rel = os.path.relpath(lua, ROOT)
            print("ERROR:   %s\n         %s" % (rel, result.stderr.strip()))

    print(
        "\n%s: %d file Lua — %d lỗi cú pháp"
        % (os.path.basename(path), len(files), failures)
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
