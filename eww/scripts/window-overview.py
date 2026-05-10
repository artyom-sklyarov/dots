#!/usr/bin/env python3

import curses
import glob
import json
import os
import subprocess
import threading
import time

def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except (OSError, IOError):
        return None

def get_gpu_info():
    """Get all GPU usage/temp. Returns list of {label, usage, temp}."""
    gpus = []

    for card_dir in sorted(glob.glob("/sys/class/drm/card[0-9]")):
        busy = read_file(f"{card_dir}/device/gpu_busy_percent")
        if busy is None:
            continue
        try:
            usage = int(busy)
        except ValueError:
            continue
        temp = None
        for hwmon in glob.glob(f"{card_dir}/device/hwmon/hwmon*"):
            t = read_file(f"{hwmon}/temp1_input")
            if t:
                temp = int(t) // 1000
                break
        label = None
        mname = read_file(f"{card_dir}/device/product_name")
        if not mname:
            uevent = read_file(f"{card_dir}/device/uevent")
            if uevent:
                for line in uevent.split("\n"):
                    if line.startswith("DRIVER="):
                        label = line.split("=", 1)[1]
                        break
        if mname:
            label = mname
        if not label:
            vendor = read_file(f"{card_dir}/device/vendor")
            if vendor == "0x1002":
                label = "AMD"
            elif vendor == "0x8086":
                label = "Intel"
            else:
                label = os.path.basename(card_dir)
        gpus.append({"label": label, "usage": usage, "temp": temp})

    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=1,
        )
        if r.returncode == 0:
            for line in r.stdout.strip().split("\n"):
                parts = [p.strip() for p in line.split(",")]
                if len(parts) >= 3:
                    gpus.append({
                        "label": parts[0],
                        "usage": int(parts[1]),
                        "temp": int(parts[2]),
                    })
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass

    return gpus

def sample_all(pids):
    """Single-pass: read system CPU + per-process CPU, sleep once, read again."""
    hz = os.sysconf("SC_CLK_TCK")

    def read_sys():
        with open("/proc/stat") as f:
            parts = f.readline().split()
        idle = int(parts[4])
        total = sum(int(x) for x in parts[1:])
        return idle, total

    def read_procs():
        stats = {}
        for pid in pids:
            try:
                with open(f"/proc/{pid}/stat") as f:
                    parts = f.read().split()
                stats[pid] = int(parts[13]) + int(parts[14])
            except (OSError, IndexError, ValueError):
                pass
        return stats

    si1, st1 = read_sys()
    p1 = read_procs()
    t1 = time.monotonic()
    time.sleep(0.04)
    si2, st2 = read_sys()
    p2 = read_procs()
    t2 = time.monotonic()

    dt_total = st2 - st1
    dt_idle = si2 - si1
    cpu_pct = round((1 - dt_idle / dt_total) * 100) if dt_total > 0 else 0

    dt = t2 - t1
    proc_stats = {}
    for pid in pids:
        ram_mb = 0
        try:
            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        ram_mb = int(line.split()[1]) / 1024
                        break
        except (OSError, ValueError):
            pass
        cpu = 0.0
        if pid in p1 and pid in p2 and dt > 0:
            delta = p2[pid] - p1[pid]
            cpu = (delta / hz) / dt * 100
        proc_stats[pid] = {"cpu": cpu, "ram_mb": ram_mb}

    mem = {}
    with open("/proc/meminfo") as f:
        for line in f:
            parts = line.split()
            mem[parts[0].rstrip(":")] = int(parts[1])
    total_kb = mem.get("MemTotal", 1)
    avail_kb = mem.get("MemAvailable", 0)
    used_gb = (total_kb - avail_kb) / 1048576
    total_gb = total_kb / 1048576

    cpu_temp = None
    for hwmon in glob.glob("/sys/class/hwmon/hwmon*"):
        name = read_file(f"{hwmon}/name")
        if name in ("coretemp", "k10temp", "zenpower"):
            t = read_file(f"{hwmon}/temp1_input")
            if t:
                cpu_temp = int(t) // 1000
                break

    return {
        "cpu_pct": cpu_pct,
        "cpu_temp": cpu_temp,
        "ram_used_gb": used_gb,
        "ram_total_gb": total_gb,
    }, proc_stats

def hyprctl(cmd):
    r = subprocess.run(["hyprctl", cmd, "-j"], capture_output=True, text=True)
    return json.loads(r.stdout) if r.stdout.strip() else []

def get_window_data():
    clients = hyprctl("clients")
    workspaces = hyprctl("workspaces")
    monitors = hyprctl("monitors")

    mon_map = {m["id"]: m["name"] for m in monitors}
    ws_monitor = {}
    for m in monitors:
        if "activeWorkspace" in m:
            ws_monitor[m["activeWorkspace"]["id"]] = m["name"]
    for ws in workspaces:
        if ws["id"] not in ws_monitor and ws.get("monitorID", -1) >= 0:
            ws_monitor[ws["id"]] = mon_map.get(ws.get("monitorID", -1), "?")

    ws_clients = {}
    for c in clients:
        wid = c["workspace"]["id"]
        wname = c["workspace"]["name"]
        if wid not in ws_clients:
            ws_clients[wid] = {"name": wname, "clients": []}
        ws_clients[wid]["clients"].append(c)
    for ws in workspaces:
        if ws["id"] not in ws_clients:
            ws_clients[ws["id"]] = {"name": ws["name"], "clients": []}

    regular = sorted([(k, v) for k, v in ws_clients.items() if k > 0], key=lambda x: x[0])
    special = sorted([(k, v) for k, v in ws_clients.items() if k <= 0], key=lambda x: x[0])
    return regular + special, ws_monitor

def truncate(s, maxlen):
    if len(s) <= maxlen:
        return s
    return s[:maxlen - 1] + "…"

def fmt_ram(mb):
    if mb >= 1024:
        return f"{mb / 1024:.1f}G"
    return f"{mb:.0f}M"

EMPTY = ("", False, None, "", "")

def build_lines(ws_list, ws_monitor, proc_stats):
    lines = []
    total_cpu = 0.0
    total_ram = 0.0

    for wid, ws in ws_list:
        mon = ws_monitor.get(wid, "")
        mon_str = f"  ({mon})" if mon else ""
        tag = "S" if wid <= 0 else str(wid)
        lines.append((f" [{tag}] {ws['name']}{mon_str}", False, None, "", ""))

        clients = ws["clients"]
        if not clients:
            lines.append(("  └─ (empty)", False, None, "", ""))
        else:
            for i, c in enumerate(clients):
                is_last = i == len(clients) - 1
                branch = "└─" if is_last else "├─"
                cls = c.get("class", "") or "?"
                title = c.get("title", "") or ""
                addr = c.get("address", "")
                pid = c.get("pid", 0)
                floating = " [F]" if c.get("floating", False) else ""
                ps = proc_stats.get(pid, {"cpu": 0, "ram_mb": 0})
                total_cpu += ps["cpu"]
                total_ram += ps["ram_mb"]
                right = f"{ps['cpu']:5.1f}%  {fmt_ram(ps['ram_mb']):>6}"
                lines.append((f"  {branch} {cls}{floating}", True, addr, title, right))
        lines.append(EMPTY)

    if lines and lines[-1] == EMPTY:
        lines.pop()

    total_right = f"{total_cpu:5.1f}%  {fmt_ram(total_ram):>6}"
    return lines, total_right

def refresh_data():
    ws_list, ws_monitor = get_window_data()
    all_pids = []
    for _, ws in ws_list:
        for c in ws["clients"]:
            pid = c.get("pid", 0)
            if pid > 0:
                all_pids.append(pid)
    sys_stats, proc_stats = sample_all(all_pids)
    lines, total_right = build_lines(ws_list, ws_monitor, proc_stats)
    selectable = [i for i, l in enumerate(lines) if l[1]]
    return lines, selectable, sys_stats, total_right

def draw_confirm(stdscr, app_name):
    h, w = stdscr.getmaxyx()
    msg = f" Kill '{app_name}'? [y/n] "
    try:
        stdscr.addnstr(h - 1, 0, "└─" + msg + "─" * max(0, w - len(msg) - 4) + "─┘",
                        w, curses.color_pair(7) | curses.A_BOLD)
    except curses.error:
        pass
    stdscr.refresh()
    while True:
        key = stdscr.getch()
        if key == curses.KEY_MOUSE:
            continue
        return key in (ord("y"), ord("Y"))

def show_loading(stdscr):
    stdscr.erase()
    h, w = stdscr.getmaxyx()
    msg = "Loading..."
    try:
        stdscr.addstr(h // 2, (w - len(msg)) // 2, msg, curses.A_DIM)
    except curses.error:
        pass
    stdscr.refresh()

def render_line(stdscr, y, left, right, content_w, color):
    """Render a line with left text and right-aligned stats."""
    if not right:
        try:
            stdscr.addnstr(y, 1, left, content_w, color)
        except curses.error:
            pass
        return

    rw = len(right)
    max_left = content_w - rw - 1
    padded = left[:max_left].ljust(max_left) + " " + right
    try:
        stdscr.addnstr(y, 1, padded[:content_w], content_w, color)
    except curses.error:
        pass

def main(stdscr):
    curses.curs_set(0)
    curses.use_default_colors()
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)

    curses.init_pair(1, curses.COLOR_WHITE, -1)
    curses.init_pair(2, curses.COLOR_CYAN, -1)
    curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_WHITE)
    curses.init_pair(4, 8, -1)
    curses.init_pair(5, curses.COLOR_YELLOW, -1)
    curses.init_pair(6, curses.COLOR_GREEN, -1)
    curses.init_pair(7, curses.COLOR_RED, -1)

    show_loading(stdscr)

    gpu_result = [None]

    def load_gpus():
        gpu_result[0] = get_gpu_info()

    gpu_thread = threading.Thread(target=load_gpus, daemon=True)
    gpu_thread.start()

    lines, selectable, sys_stats, total_right = refresh_data()
    gpu_thread.join()
    gpus = gpu_result[0] or []

    sel_idx = 0
    scroll_offset = 0

    while True:
        stdscr.erase()
        h, w = stdscr.getmaxyx()

        cpu_t = f" {sys_stats['cpu_temp']}°" if sys_stats.get("cpu_temp") is not None else ""
        hdr = f" CPU {sys_stats['cpu_pct']}%{cpu_t}"
        hdr += f"  RAM {sys_stats['ram_used_gb']:.1f}/{sys_stats['ram_total_gb']:.1f}G"
        for g in gpus:
            gt = f" {g['temp']}°" if g.get("temp") is not None else ""
            hdr += f"  {g['label']} {g['usage']}%{gt}"
        hdr += " "
        title = " Overview "
        fill = max(0, w - len(title) - len(hdr) - 4)
        top = "┌─" + title + "─" * fill + hdr + "─┐"
        try:
            stdscr.addnstr(0, 0, top, w, curses.color_pair(2) | curses.A_BOLD)
        except curses.error:
            pass

        total_line = " Total"
        rw = len(total_right)
        total_padded = total_line + " " * max(0, w - len(total_line) - rw - 4) + total_right
        total_border = "├─" + total_padded + "─┤"
        try:
            stdscr.addnstr(h - 2, 0, total_border[:w], w, curses.color_pair(2) | curses.A_BOLD)
        except curses.error:
            pass

        help_text = " q close  Enter focus  d kill  r refresh  mouse click "
        bot = "└─" + help_text + "─" * max(0, w - len(help_text) - 4) + "─┘"
        try:
            stdscr.addnstr(h - 1, 0, bot, w, curses.color_pair(5))
        except curses.error:
            pass

        content_h = h - 3  # title + total + help
        if content_h < 1:
            stdscr.refresh()
            stdscr.getch()
            continue

        if selectable and sel_idx < len(selectable):
            cur = selectable[sel_idx]
            if cur < scroll_offset:
                scroll_offset = cur
            elif cur >= scroll_offset + content_h:
                scroll_offset = cur - content_h + 1

        content_w = w - 2

        for row in range(content_h):
            line_idx = row + scroll_offset
            y_pos = row + 1

            if line_idx >= len(lines):
                try:
                    stdscr.addstr(y_pos, 0, "│", curses.color_pair(4))
                    stdscr.addstr(y_pos, w - 1, "│", curses.color_pair(4))
                except curses.error:
                    pass
                continue

            left, is_sel, addr, title_text, right = lines[line_idx]
            is_current = (selectable and sel_idx < len(selectable)
                          and selectable[sel_idx] == line_idx)

            try:
                stdscr.addstr(y_pos, 0, "│", curses.color_pair(4))
            except curses.error:
                pass

            if is_current and is_sel:
                display_left = left
                if title_text:
                    rw = len(right)
                    avail = content_w - len(left) - rw - 3
                    if avail > 5:
                        display_left = left + " " + truncate(title_text, avail)
                render_line(stdscr, y_pos, display_left, right, content_w,
                            curses.color_pair(3))
            elif is_sel:
                prefix_end = left.find("─ ") + 2 if "─ " in left else 0
                if prefix_end > 0:
                    try:
                        stdscr.addnstr(y_pos, 1, left[:prefix_end],
                                       min(prefix_end, content_w), curses.color_pair(4))
                    except curses.error:
                        pass
                    cls_part = left[prefix_end:]
                    try:
                        stdscr.addnstr(y_pos, 1 + prefix_end, cls_part,
                                       max(0, content_w - prefix_end), curses.color_pair(6))
                    except curses.error:
                        pass
                else:
                    try:
                        stdscr.addnstr(y_pos, 1, left, content_w, curses.color_pair(1))
                    except curses.error:
                        pass
                if title_text:
                    rw = len(right)
                    left_end = len(left)
                    avail = content_w - left_end - rw - 3
                    if avail > 5:
                        t = truncate(title_text, avail)
                        try:
                            stdscr.addnstr(y_pos, 1 + left_end + 1, t, len(t),
                                           curses.color_pair(4))
                        except curses.error:
                            pass
                if right:
                    pos = 1 + content_w - len(right)
                    try:
                        stdscr.addnstr(y_pos, pos, right, len(right),
                                       curses.color_pair(1))
                    except curses.error:
                        pass
            elif left.startswith(" ["):
                try:
                    stdscr.addnstr(y_pos, 1, left, content_w,
                                   curses.color_pair(2) | curses.A_BOLD)
                except curses.error:
                    pass
            elif left.startswith(" Total"):
                render_line(stdscr, y_pos, left, right, content_w,
                            curses.color_pair(2) | curses.A_BOLD)
            else:
                try:
                    stdscr.addnstr(y_pos, 1, left, content_w, curses.color_pair(4))
                except curses.error:
                    pass

            try:
                stdscr.addstr(y_pos, w - 1, "│", curses.color_pair(4))
            except curses.error:
                pass

        stdscr.refresh()

        key = stdscr.getch()
        if key in (ord("q"), ord("Q"), 27):
            break
        elif key == curses.KEY_MOUSE:
            try:
                _, mx, my, _, bstate = curses.getmouse()
            except curses.error:
                continue
            if 1 <= my <= h - 2:
                clicked = my - 1 + scroll_offset
                if clicked in selectable:
                    new_idx = selectable.index(clicked)
                    if bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED):
                        sel_idx = new_idx
                    if bstate & curses.BUTTON1_DOUBLE_CLICKED:
                        sel_idx = new_idx
                        entry = lines[selectable[sel_idx]]
                        if entry[2]:
                            subprocess.run(["hyprctl", "dispatch", "focuswindow",
                                            f"address:{entry[2]}"])
                        break
            if bstate & curses.BUTTON4_PRESSED and selectable:
                sel_idx = max(sel_idx - 3, 0)
            elif bstate & curses.BUTTON5_PRESSED and selectable:
                sel_idx = min(sel_idx + 3, len(selectable) - 1)
        elif key in (ord("j"), curses.KEY_DOWN) and selectable:
            sel_idx = min(sel_idx + 1, len(selectable) - 1)
        elif key in (ord("k"), curses.KEY_UP) and selectable:
            sel_idx = max(sel_idx - 1, 0)
        elif key == ord("g"):
            sel_idx = 0
        elif key == ord("G") and selectable:
            sel_idx = len(selectable) - 1
        elif key in (ord("d"), ord("x"), curses.KEY_DC) and selectable:
            entry = lines[selectable[sel_idx]]
            addr = entry[2]
            name = entry[0].split("─ ", 1)[-1].strip() if "─ " in entry[0] else "?"
            if addr and draw_confirm(stdscr, name):
                subprocess.run(["hyprctl", "dispatch", "closewindow", f"address:{addr}"])
                time.sleep(0.1)
                lines, selectable, sys_stats, total_right = refresh_data()
                gpus = get_gpu_info()
                sel_idx = min(sel_idx, max(0, len(selectable) - 1))
        elif key in (10, curses.KEY_ENTER) and selectable:
            entry = lines[selectable[sel_idx]]
            if entry[2]:
                subprocess.run(["hyprctl", "dispatch", "focuswindow",
                                f"address:{entry[2]}"])
            break
        elif key == ord("r"):
            show_loading(stdscr)
            gpu_thread = threading.Thread(target=load_gpus, daemon=True)
            gpu_thread.start()
            lines, selectable, sys_stats, total_right = refresh_data()
            gpu_thread.join()
            gpus = gpu_result[0] or []
            sel_idx = min(sel_idx, max(0, len(selectable) - 1))

if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        pass
