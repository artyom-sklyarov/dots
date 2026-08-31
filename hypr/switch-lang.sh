#!/bin/bash
target=$(hyprctl devices -j | python3 -c "
import sys, json
kb = next(k for k in json.load(sys.stdin)['keyboards'] if k['name'] == 'at-translated-set-2-keyboard')
print(1 if 'English' in kb['active_keymap'] else 0)
")
hyprctl switchxkblayout all "$target"
