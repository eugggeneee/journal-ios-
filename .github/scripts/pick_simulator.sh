#!/bin/bash
# Печатает UDID подходящего iPhone-симулятора (самый новый iOS, предпочтительно 17 Pro).
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
preferred = ["iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro", "iPhone 16"]
found = []
for runtime, devices in sorted(data.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for d in devices:
        if d["name"].startswith("iPhone") and d.get("isAvailable", True):
            found.append((runtime, d["name"], d["udid"]))
    if found:
        break
if not found:
    sys.exit("Нет доступных iPhone-симуляторов")
pick = None
for name in preferred:
    for r, n, u in found:
        if n == name:
            pick = (r, n, u)
            break
    if pick:
        break
pick = pick or found[0]
print("Симулятор:", pick[1], pick[0], file=sys.stderr)
print(pick[2])
'
