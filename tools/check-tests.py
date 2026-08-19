#!/usr/bin/env python3
"""Chạy các file test Lua trong tests/.

Chạy: python3 tools/check-tests.py

Test được viết bằng Lua và chạy trên LuaJIT — cùng runtime mpv nhúng — với một
bộ giả lập API mpv tối thiểu (tests/mpv_stub.lua). Nhờ vậy có thể kiểm chứng
logic của script mà không cần mở mpv.

Quy ước: mỗi file `tests/*_spec.lua` là một test, exit 0 = pass.

Exit code: 0 nếu tất cả pass, 1 nếu có test fail, 2 nếu không có LuaJIT.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")


def main() -> int:
    # Chỉ LuaJIT: bộ giả lập và các script đều nhắm Lua 5.1 như mpv dùng.
    luajit = shutil.which("luajit")
    if luajit is None:
        print("ERROR: không tìm thấy luajit. Cài để chạy test: apt install luajit")
        return 2

    if not os.path.isdir(TESTS):
        print("Không có thư mục tests/, bỏ qua.")
        return 0

    specs = sorted(
        os.path.join(TESTS, name)
        for name in os.listdir(TESTS)
        if name.endswith("_spec.lua")
    )
    if not specs:
        print("Không tìm thấy tests/*_spec.lua.")
        return 0

    failed = []
    for spec in specs:
        result = subprocess.run([luajit, spec], cwd=ROOT)
        if result.returncode != 0:
            failed.append(os.path.relpath(spec, ROOT))

    print("\n%d test — %d fail" % (len(specs), len(failed)))
    for name in failed:
        print("  FAIL: " + name)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
