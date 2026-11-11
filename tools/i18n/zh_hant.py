"""Writes apps/pure_live/assets/translations/zh_Hant.json from zh.json.

Traditional Chinese with Taiwan's words (OpenCC `s2twp`: 设置 → 設定,
视频 → 影片), key for key; `{placeholders}` and Latin text are left as
they are. Run it after changing zh.json:

    python3 -m venv /tmp/opencc && /tmp/opencc/bin/pip install opencc
    /tmp/opencc/bin/python3 tools/i18n/zh_hant.py

`FIXES` replaces what the conversion gets wrong for this app, after it.
"""

import json
import pathlib
import sys

import opencc

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'apps/pure_live/assets/translations/zh.json'
TARGET = ROOT / 'apps/pure_live/assets/translations/zh_Hant.json'

# Words s2twp turns into something else than the app means.
FIXES: dict[str, str] = {
    '分割槽': '分區',  # 分区 is the platforms' categories, not a disk partition
    '許可權': '權限',  # 权限: a permission
    '全域性': '全域',  # 全局: everywhere in the app
    '色程式碼': '色碼',  # 颜色代码: a colour code
    '進位制': '進位',  # 十六进制
}


def convert(text: str, converter: opencc.OpenCC) -> str:
    out = converter.convert(text)
    for wrong, right in FIXES.items():
        out = out.replace(wrong, right)
    return out


def main() -> int:
    converter = opencc.OpenCC('s2twp')
    source = json.loads(SOURCE.read_text(encoding='utf-8'))
    table = {key: convert(value, converter) for key, value in sorted(source.items())}
    TARGET.write_text(json.dumps(table, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')
    print(f'wrote {TARGET.relative_to(ROOT)} ({len(table)} keys)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
