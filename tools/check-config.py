#!/usr/bin/env python3
"""Kiểm tra tính nhất quán của bộ cấu hình mpv trong repo này.

Chạy: python3 tools/check-config.py

Các lỗi được bắt (mpv chỉ ghi vào log rồi bỏ qua, rất khó phát hiện bằng mắt):

  * input.conf trỏ tới `script-binding <script>/<name>` của script không tồn tại
  * `apply-profile <name>` trỏ tới profile chưa được định nghĩa
  * đường dẫn `~~/...` (shader, include...) không có trên đĩa
  * hai dòng input.conf gán cùng một phím (dòng sau lặng lẽ ghi đè dòng trước)
  * script có phím mặc định bị input.conf chiếm mất và không được bind lại
    => script nằm đó nhưng không bao giờ chạy được
  * script-opts/*.conf chứa key mà script không đọc (sai chính tả => bị bỏ qua)
  * script-opts/*.conf bọc giá trị trong dấu nháy (read_options KHÔNG bóc nháy,
    dấu nháy sẽ nằm luôn trong giá trị)
  * script-opts/*.conf không có script tương ứng

Exit code 1 nếu có ERROR, 0 nếu chỉ có WARNING hoặc sạch.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Script dựng sẵn trong mpv (không nằm trong scripts/). Cập nhật khi mpv đổi tên.
BUILTIN_SCRIPTS = {
    "auto_profiles",
    "autoload",
    "commands",     # console / command palette (mpv 0.40+)
    "console",
    "positioning",  # cursor-centric-zoom, drag-to-pan (mpv 0.40+)
    "select",
    "stats",
    "ytdl_hook",
}

# Đường dẫn `~~/...` được tạo lúc chạy, không có sẵn trong repo.
RUNTIME_PATHS = {
    "~~/memo-history.log",
    "~~/subtitles",
    "~~/watch_later",
}

# Script tự bóc dấu nháy khỏi giá trị script-opts, nên nháy ở đây là hợp lệ.
SCRIPTS_STRIPPING_QUOTES = {"slicing_copy"}

errors: list[str] = []
warnings: list[str] = []


def error(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def read(path: str) -> str:
    with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def lines(path: str):
    """Trả về (số dòng, nội dung đã strip) cho các dòng không phải comment."""
    for no, raw in enumerate(read(path).splitlines(), 1):
        stripped = raw.strip()
        if stripped and not stripped.startswith("#"):
            yield no, raw, stripped


# ---------------------------------------------------------------- inventory

def script_names() -> set[str]:
    """Tên script như mpv thấy: bỏ .lua, đổi '-' thành '_'."""
    names = set()
    scripts_dir = os.path.join(ROOT, "scripts")
    for entry in os.listdir(scripts_dir):
        full = os.path.join(scripts_dir, entry)
        if entry.endswith(".lua"):
            names.add(entry[:-4].replace("-", "_"))
        elif os.path.isdir(full) and os.path.exists(os.path.join(full, "main.lua")):
            names.add(entry.replace("-", "_"))
    return names


def profile_names() -> set[str]:
    names = set()
    for conf in ("mpv.conf", "profiles.conf"):
        for match in re.finditer(r"^\[([^\]]+)\]", read(conf), re.M):
            names.add(match.group(1))
    return names


SCRIPTS = script_names()
PROFILES = profile_names()


def lua_for(script: str) -> str | None:
    for candidate in (
        "scripts/%s.lua" % script,
        "scripts/%s.lua" % script.replace("_", "-"),
        "scripts/%s/main.lua" % script,
    ):
        if os.path.exists(os.path.join(ROOT, candidate)):
            return candidate
    return None


# ------------------------------------------------------- key normalisation

def normalize_key(key: str) -> str:
    """Đưa tên phím về dạng chuẩn của mpv để so sánh.

    Modifier không phân biệt hoa thường và không phụ thuộc thứ tự; phím ký tự
    đơn thì phân biệt hoa thường ('d' khác 'D'); Shift+<chữ cái> == <CHỮ HOA>.
    """
    parts = key.split("+")
    # "Alt+=" và "Ctrl++" -> phần cuối rỗng nghĩa là phím chính là '+'
    if parts[-1] == "":
        parts = parts[:-1]
        parts[-1] = parts[-1] + "+" if len(parts) > 1 else "+"
    base, mods = parts[-1], [p.lower() for p in parts[:-1]]
    if len(base) > 1:
        base = base.lower()
    if "shift" in mods and len(base) == 1 and base.isalpha():
        mods.remove("shift")
        base = base.upper()
    return "+".join(sorted(mods) + [base])


# ------------------------------------------------------------ input.conf

def check_input_conf() -> tuple[dict[str, int], set[str]]:
    bound_keys: dict[str, int] = {}
    referenced_bindings: set[str] = set()

    for no, raw, stripped in lines("input.conf"):
        key = stripped.split(None, 1)[0]
        command = stripped[len(key):].strip()
        if key == "#":  # mục menu uosc không gắn phím
            pass
        else:
            norm = normalize_key(key)
            if norm in bound_keys:
                error(
                    "input.conf:%d: phím '%s' đã được gán ở dòng %d, "
                    "dòng sau sẽ ghi đè dòng trước" % (no, key, bound_keys[norm])
                )
            else:
                bound_keys[norm] = no

        # `script-binding foo/bar` hoặc dạng rút gọn `script-binding bar`
        for script, binding in re.findall(
            r"script-binding\s+(?:([A-Za-z0-9_-]+)/)?([A-Za-z0-9_-]+)", command
        ):
            if script:
                name = script.replace("-", "_")
                referenced_bindings.add("%s/%s" % (name, binding))
                if name not in SCRIPTS and name not in BUILTIN_SCRIPTS:
                    error(
                        "input.conf:%d: script-binding trỏ tới script '%s' "
                        "không tồn tại trong scripts/" % (no, script)
                    )
            else:
                referenced_bindings.add(binding)

        for profile in re.findall(r"apply-profile\s+([A-Za-z0-9_.-]+)", command):
            if profile not in PROFILES:
                error(
                    "input.conf:%d: apply-profile '%s' chưa được định nghĩa"
                    % (no, profile)
                )

    return bound_keys, referenced_bindings


def check_trailing_whitespace() -> None:
    for conf in ("mpv.conf", "profiles.conf", "input.conf"):
        for no, raw, _stripped in lines(conf):
            if raw != raw.rstrip():
                warn("%s:%d: có khoảng trắng thừa ở cuối dòng" % (conf, no))
        if not read(conf).endswith("\n"):
            warn("%s: thiếu ký tự xuống dòng ở cuối file" % conf)


# ----------------------------------------------------- script default keys

def check_dead_script_bindings(bound_keys, referenced_bindings) -> None:
    """Script khai báo phím mặc định nhưng input.conf chiếm mất phím đó.

    mpv luôn ưu tiên input.conf hơn phím mặc định của script, nên nếu binding
    cũng không được gọi lại ở đâu thì script coi như không dùng được.
    """
    pattern = re.compile(
        r"""mp\.add_key_binding\(\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']"""
    )
    for script in sorted(SCRIPTS):
        lua = lua_for(script)
        if not lua:
            continue
        for key, binding in pattern.findall(read(lua)):
            full = "%s/%s" % (script, binding)
            if full in referenced_bindings or binding in referenced_bindings:
                continue  # đã được bind lại bằng phím khác, không sao
            shadow = bound_keys.get(normalize_key(key))
            if shadow:
                error(
                    "scripts/: '%s' đăng ký phím mặc định '%s' nhưng "
                    "input.conf:%d đã dùng phím đó cho việc khác, và "
                    "'script-binding %s' không được gán phím nào "
                    "=> chức năng này không gọi được"
                    % (script, key, shadow, full)
                )


# ------------------------------------------------------------ script-opts

def options_table(lua_source: str) -> set[str] | None:
    """Lấy tên các option từ bảng `options`/`o`/`opts` đầu tiên trong script."""
    match = re.search(
        r"^\s*(?:local\s+)?(?:o|opts|options)\s*=\s*\{", lua_source, re.M
    )
    if not match:
        return None
    depth, index = 0, match.end() - 1
    for index in range(match.end() - 1, len(lua_source)):
        char = lua_source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                break
    body = lua_source[match.end():index]
    return set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*=", body))


def check_script_opts() -> None:
    opts_dir = os.path.join(ROOT, "script-opts")
    for entry in sorted(os.listdir(opts_dir)):
        if not entry.endswith(".conf"):
            continue
        name = entry[:-5].replace("-", "_")
        rel = "script-opts/" + entry
        lua = lua_for(name)

        if lua is None:
            if name not in BUILTIN_SCRIPTS:
                warn("%s: không có script nào tên '%s'" % (rel, name))
            continue

        known = options_table(read(lua))
        for no, _raw, stripped in lines(rel):
            if "=" not in stripped:
                continue
            key, value = (part.strip() for part in stripped.split("=", 1))
            if known is not None and key not in known:
                error(
                    "%s:%d: '%s' không phải option của %s, mpv sẽ bỏ qua"
                    % (rel, no, key, lua)
                )
            if (
                len(value) >= 2
                and value[0] == value[-1]
                and value[0] in "\"'"
                and name not in SCRIPTS_STRIPPING_QUOTES
            ):
                error(
                    "%s:%d: giá trị của '%s' bị bọc trong dấu nháy; "
                    "read_options không bóc nháy nên dấu nháy sẽ nằm "
                    "trong giá trị" % (rel, no, key)
                )


# -------------------------------------------------------------- ~~/ paths

def check_config_paths() -> None:
    for conf in ("mpv.conf", "profiles.conf", "input.conf"):
        for no, _raw, stripped in lines(conf):
            for ref in re.findall(r"~~/[A-Za-z0-9_./-]+", stripped):
                if ref in RUNTIME_PATHS:
                    continue
                if not os.path.exists(os.path.join(ROOT, ref[3:])):
                    error("%s:%d: '%s' không tồn tại trong repo" % (conf, no, ref))


# ------------------------------------------------------------------- main

def main() -> int:
    bound_keys, referenced = check_input_conf()
    check_dead_script_bindings(bound_keys, referenced)
    check_script_opts()
    check_config_paths()
    check_trailing_whitespace()

    for msg in warnings:
        print("WARNING: " + msg)
    for msg in errors:
        print("ERROR:   " + msg)

    print(
        "\n%d script, %d profile, %d phím đã gán — %d lỗi, %d cảnh báo"
        % (len(SCRIPTS), len(PROFILES), len(bound_keys), len(errors), len(warnings))
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
