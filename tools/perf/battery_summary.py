#!/usr/bin/env python3
"""The app's estimated drain from `adb shell dumpsys batterystats` (R05.1).

usage: adb -s <device> shell dumpsys batterystats | python3 tools/perf/battery_summary.py <app uid>

Prints the app's estimated use in mAh (total and in the background) and the
device's total, from the "Estimated power use (mAh)" section. Reset the
stats (`dumpsys batterystats --reset`) and, on a charging phone, count it as
unplugged (`dumpsys battery unplug`) before a run; `dumpsys battery reset`
after it.
"""
import re
import sys


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print(__doc__.strip(), file=sys.stderr)
        return 2
    uid = int(sys.argv[1])
    label = f'u0a{uid - 10000}' if uid >= 10000 else str(uid)
    text = sys.stdin.read()
    start = text.find('Estimated power use (mAh):')
    if start < 0:
        print('no "Estimated power use" section', file=sys.stderr)
        return 1
    section = text[start:]
    total = re.search(r'Computed drain: ([\d.]+)', section)
    app = re.search(rf'UID {re.escape(label)}: ([\d.]+)(?: bg: ([\d.]+))?', section)
    print(f'device computed drain: {total.group(1) if total else "?"} mAh')
    if app:
        print(f'app {label}: {app.group(1)} mAh (background {app.group(2) or "0"} mAh)')
    else:
        print(f'app {label}: not listed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
