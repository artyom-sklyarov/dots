#!/usr/bin/env python3
"""Keep a Hyprland workspace arranged as a fixed columns x rows dwindle grid.

Unlike a full makegrid rebuild, this only makes small fixes:
  - order: real windows are packed row by row using swapwindow (structure untouched)
  - a window opened/closed and broke a column: only that column is rebuilt,
    topping up or trimming kitty placeholders so every cell stays filled
A full rebuild (tile-workspace.sh) only happens when the layout is outside that
model, and a circuit breaker stops the manager if it keeps having to act.

Runs in the foreground: Ctrl+C stops it.
"""
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time

PLACEHOLDER_CLASS = "tile-placeholder"
FILLER_CLASSES = {PLACEHOLDER_CLASS, "kitty"}
PLACEHOLDER_CMD = f"kitty --class {PLACEHOLDER_CLASS} -o confirm_os_window_close=0"
TOLERANCE = 0.2  # fraction of a cell a window may be off and still count as "in its cell"
DEBOUNCE = 0.25
FAILED_FIX_LIMIT = 3  # consecutive fixes that don't produce a clean grid before giving up
REBUILD = os.path.expanduser("~/.config/hypr/tile-workspace.sh")
STATE_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "makegrid")


LOG_FILE = None


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    if LOG_FILE:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")


def rebuild_running(workspace):
    """tile-workspace.sh holds this lock while it rebuilds; never fix things mid-rebuild."""
    try:
        with open(os.path.join(STATE_DIR, f"ws-{workspace}.rebuilding")) as f:
            os.kill(int(f.read().split()[0]), 0)
        return True
    except (OSError, ValueError, IndexError):
        return False


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, check=True).stdout


def hypr_json(what):
    return json.loads(hyprctl("-j", what))


def lua_str(s):
    """Quote s as a Lua string literal."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def _lua_exec(arg):
    if arg.startswith("[workspace ") and "] " in arg:
        rule, cmd = arg[len("[workspace "):].split("] ", 1)
        return f"hl.dsp.exec_cmd({lua_str(cmd)}, {{ workspace = {lua_str(rule)} }})"
    return f"hl.dsp.exec_cmd({lua_str(arg)})"


def _lua_move_silent(arg):
    workspace, _, window = arg.partition(",")
    workspace = workspace if workspace.lstrip("-").isdigit() else lua_str(workspace)
    return f"hl.dsp.window.move({{ window = {lua_str(window)}, workspace = {workspace}, follow = false }})"


LEGACY_TO_LUA = {
    "exec":                  _lua_exec,
    "movetoworkspacesilent": _lua_move_silent,
    "focuswindow":           lambda a: f"hl.dsp.focus({{ window = {lua_str(a)} }})",
    "swapwindow":            lambda a: f"hl.dsp.window.swap({{ target = {lua_str(a)} }})",
    "closewindow":           lambda a: f"hl.dsp.window.close({{ window = {lua_str(a)} }})",
    "layoutmsg":             lambda a: f"hl.dsp.layout({lua_str(a)})",
}


def to_lua(command):
    name, _, arg = command.partition(" ")
    return LEGACY_TO_LUA[name](arg)


def dispatch_batch(commands):
    """Run dispatches in one hyprctl call so they land together instead of one by one.
    pcall keeps one bad dispatch from aborting the rest, like the old --batch did."""
    if commands:
        hyprctl("eval", " ".join(f"pcall(hl.dispatch, {to_lua(c)})" for c in commands))


def notify(msg, urgent=False):
    log(msg)
    try:
        subprocess.run(["notify-send", "-a", "makegrid", *(["-u", "critical"] if urgent else []),
                        "makegrid", msg], check=False)
    except FileNotFoundError:
        pass


SHELLS = {"fish", "bash", "zsh", "sh", "dash"}


def child_pids(pid):
    out = subprocess.run(["pgrep", "-P", str(pid)], capture_output=True, text=True).stdout
    return [int(p) for p in out.split()]


def placeholder_is_idle(pid):
    """A kitty is idle when its shell owns the terminal, i.e. sits at a prompt.

    Running a command hands the terminal's foreground process group to that command;
    prompt helpers and slow shell startup (starship etc.) never do, so they can't make
    an empty terminal look busy.
    """
    if not pid or pid <= 0:
        return False
    for child in child_pids(pid):
        try:
            with open(f"/proc/{child}/comm") as f:
                comm = f.read().strip()
            with open(f"/proc/{child}/stat") as f:
                fields = f.read().rsplit(")", 1)[1].split()
        except OSError:
            continue
        if comm == "kitten":  # kitty's own helper
            continue
        if comm not in SHELLS:
            return False  # kitty is running a program directly
        pgrp, tpgid = int(fields[2]), int(fields[5])
        if tpgid > 0 and tpgid != pgrp:
            return False  # something else has the terminal: a command is running
    return True


class Grid:
    """Snapshot of the workspace's tiled windows mapped onto a columns x rows grid."""

    def __init__(self, workspace, columns, rows):
        self.columns, self.rows, self.cells = columns, rows, columns * rows
        self.windows = [
            c for c in hypr_json("clients")
            if c["workspace"]["id"] == workspace and c["mapped"] and not c["hidden"]
            and not c["pinned"] and not c.get("fullscreen") and not c["floating"]
        ]
        for w in self.windows:
            w["idle"] = w["class"] in FILLER_CLASSES and placeholder_is_idle(w.get("pid", 0))
            w["closable"] = w["idle"] and w["class"] == PLACEHOLDER_CLASS
        self.real = [w for w in self.windows if not w["idle"]]
        self.idle = [w for w in self.windows if w["idle"]]
        if not self.windows:
            return
        left = min(w["at"][0] for w in self.windows)
        top = min(w["at"][1] for w in self.windows)
        right = max(w["at"][0] + w["size"][0] for w in self.windows)
        bottom = max(w["at"][1] + w["size"][1] for w in self.windows)
        self.cw = max(right - left, 1) / columns
        self.ch = max(bottom - top, 1) / rows
        for w in self.windows:
            cx = w["at"][0] + w["size"][0] / 2
            cy = w["at"][1] + w["size"][1] / 2
            w["col"] = min(max(int((cx - left) / self.cw), 0), columns - 1)
            w["row"] = min(max(int((cy - top) / self.ch), 0), rows - 1)
            w["cell"] = w["row"] * columns + w["col"]
            w["cy"], w["cx"] = cy, cx
            w["fits_width"] = abs(w["size"][0] - self.cw) <= self.cw * TOLERANCE
            w["proper"] = w["fits_width"] and abs(w["size"][1] - self.ch) <= self.ch * TOLERANCE

    def column(self, k):
        return sorted((w for w in self.windows if w["col"] == k), key=lambda w: (w["cy"], w["cx"]))

    def column_intact(self, k):
        col = self.column(k)
        return len(col) == self.rows and all(w["proper"] for w in col) \
            and len({w["row"] for w in col}) == self.rows

    def broken_columns(self):
        return [k for k in range(self.columns) if not self.column_intact(k)]

    def in_model(self):
        """Every column still exists and no window spans columns: fixable column by column."""
        if not self.windows:
            return False
        for k in range(self.columns):
            col = self.column(k)
            if not col or any(w["size"][0] > self.cw * (1 + TOLERANCE) for w in col):
                return False
            if max(w["size"][0] for w in col) < self.cw * (1 - TOLERANCE):
                return False
        return True

    def holes(self):
        """Placeholders sitting where real windows should be (row-major, first len(real) cells)."""
        n = len(self.real)
        return sorted((w for w in self.idle if w["cell"] < n), key=lambda w: w["cell"])

    def stragglers(self):
        n = len(self.real)
        return sorted((w for w in self.real if w["cell"] >= n), key=lambda w: w["cell"])


class Manager:
    def __init__(self, workspace, columns, rows):
        self.workspace, self.columns, self.rows = workspace, columns, rows
        self.seen = set()  # addresses of real windows seen on earlier ticks
        self.failed_fixes = 0
        self.started = False
        self.too_broken = False
        self.overflowed = False
        self.placeholders = set()

    def scratch_workspace(self):
        used = {w["id"] for w in hypr_json("workspaces")}
        ws = 2147483646
        while ws in used:
            ws -= 1
        return ws

    def spawn_placeholders(self, count, scratch):
        known = {c["address"] for c in hypr_json("clients") if c["class"] == PLACEHOLDER_CLASS}
        dispatch_batch([f"exec [workspace {scratch} silent] {PLACEHOLDER_CMD}"] * count)
        for _ in range(50 + 10 * count):
            fresh = [c["address"] for c in hypr_json("clients")
                     if c["class"] == PLACEHOLDER_CLASS and c["mapped"] and c["address"] not in known]
            if len(fresh) >= count:
                return fresh[:count]
            time.sleep(0.1)
        raise RuntimeError("timed out waiting for kitty placeholders")

    def repair_columns(self, grid, active):
        """Rebuild only the broken columns, trimming or topping up placeholders."""
        broken = grid.broken_columns()
        surplus = len(grid.idle) - (grid.cells - len(grid.real))  # >0 close, <0 spawn
        commands = []

        in_broken = [w for k in broken for w in grid.column(k)]
        closable = [w for w in in_broken if w["closable"]]
        if surplus > len(closable):
            outside = [w for w in grid.idle if w["closable"] and w["col"] not in broken]
            movers = sorted((w for w in in_broken if not w["closable"]),
                            key=lambda w: (w["address"] in self.seen, -w["cell"]))
            for mover, placeholder in zip(movers, outside[:surplus - len(closable)]):
                commands += [f"focuswindow address:{mover['address']}",
                             f"swapwindow address:{placeholder['address']}"]
                mover["col"], placeholder["col"] = placeholder["col"], mover["col"]
                closable.append(placeholder)
            in_broken = [w for w in grid.windows if w["col"] in broken]
            if surplus > len(closable):
                return False
        to_close = {w["address"] for w in closable[:max(surplus, 0)]}

        scratch = self.scratch_workspace()
        spawned = self.spawn_placeholders(-surplus, scratch) if surplus < 0 else []

        anchors, pools, spare = {}, {}, []
        for k in broken:
            col = [w for w in grid.windows if w["col"] == k and w["address"] not in to_close]
            col.sort(key=lambda w: (w["idle"], w["cy"], w["cx"]))
            if not col:
                return False
            anchors[k] = col[0]["address"]
            rest = [w["address"] for w in sorted(col[1:], key=lambda w: (w["cy"], w["cx"]))]
            pools[k], extra = rest[:self.rows - 1], rest[self.rows - 1:]
            spare += extra
        spare += spawned
        for k in broken:
            while len(pools[k]) < self.rows - 1:
                if not spare:
                    raise RuntimeError("column repair ran out of windows")
                pools[k].append(spare.pop(0))

        for k in broken:
            for address in pools[k]:
                if address not in spawned:
                    commands.append(f"movetoworkspacesilent {scratch},address:{address}")
        for address in spare:  # shouldn't happen, but never leave spawned kitties lying around
            if address in spawned:
                to_close.add(address)
        for address in to_close:
            commands += [f"movetoworkspacesilent {scratch},address:{address}",
                         f"closewindow address:{address}"]
        for k in broken:
            previous = anchors[k]
            for row, address in enumerate(pools[k], start=1):
                commands += [f"focuswindow address:{previous}",
                             "layoutmsg preselect d",
                             f"movetoworkspacesilent {self.workspace},address:{address}",
                             f"focuswindow address:{previous}",
                             f"layoutmsg splitratio {2 / (self.rows - row + 1):.6f} exact"]
                previous = address
        if active:
            commands.append(f"focuswindow address:{active}")
        dispatch_batch(commands)
        log(f"repaired column(s) {', '.join(str(k + 1) for k in broken)}"
            f" (closed {len(to_close)}, spawned {len(spawned)} placeholder(s))")
        return True

    def compact(self, grid, active):
        """Swap real windows into the first cells so they fill row by row. Returns swap count."""
        holes, stragglers = grid.holes(), grid.stragglers()
        stragglers.sort(key=lambda w: (w["address"] not in self.seen, w["cell"]))
        commands = []
        for hole, window in zip(holes, stragglers):
            commands += [f"focuswindow address:{window['address']}",
                         f"swapwindow address:{hole['address']}"]
        if commands and active:
            commands.append(f"focuswindow address:{active}")
        dispatch_batch(commands)
        if commands:
            log(f"packed {len(commands) // 2} window(s) row by row")
        return len(commands) // 2

    def tick(self):
        """Returns True if it changed anything."""
        if hypr_json("activeworkspace")["id"] != self.workspace:
            return False
        active = hypr_json("activewindow").get("address") or None
        grid = Grid(self.workspace, self.columns, self.rows)
        self.placeholders = {w["address"].removeprefix("0x") for w in grid.windows
                             if w["class"] in FILLER_CLASSES}
        if not grid.windows:
            return False
        if len(grid.real) > grid.cells:
            if not self.overflowed:
                notify(f"workspace {self.workspace}: {len(grid.real)} windows don't fit "
                       f"{self.columns}x{self.rows}, leaving it alone", urgent=True)
            self.overflowed = True
            return False
        self.overflowed = False

        changed = False
        if grid.broken_columns() or len(grid.windows) != grid.cells:
            if grid.in_model() and self.repair_columns(grid, active):
                changed = True
            elif not self.started:
                log("grid is off at startup, doing one full rebuild")
                subprocess.run([REBUILD, "--tick", "-w", str(self.workspace),
                                str(self.columns), str(self.rows)], check=False)
                changed = True
            else:
                if not self.too_broken:
                    notify(f"workspace {self.workspace} is too messed up to fix in place, "
                           f"press Opt+Shift+T to rebuild it", urgent=True)
                self.too_broken = True
                self.started = True
                return False
            grid = Grid(self.workspace, self.columns, self.rows)
        if not grid.broken_columns() and self.compact(grid, active):
            changed = True
            grid = Grid(self.workspace, self.columns, self.rows)
        self.started = True
        if changed:
            if grid.broken_columns() or grid.holes():
                self.failed_fixes += 1
                log(f"fix didn't produce a clean grid ({self.failed_fixes}/{FAILED_FIX_LIMIT})")
            else:
                self.failed_fixes = 0
        elif not grid.broken_columns():
            self.failed_fixes = 0
            self.too_broken = False
        self.seen = {w["address"] for w in Grid(self.workspace, self.columns, self.rows).real}
        return changed

    def breaker(self):
        if self.failed_fixes >= FAILED_FIX_LIMIT:
            notify(f"stopped managing workspace {self.workspace}: {self.failed_fixes} fixes in a row "
                   f"didn't work (log: {LOG_FILE})", urgent=True)
            sys.exit(1)

    def relevant(self, line):
        event, _, data = line.partition(">>")
        if event in ("openwindow", "closewindow", "movewindowv2", "changefloatingmode",
                     "fullscreen", "pin"):
            return True
        if event == "workspacev2":
            return data.split(",", 1)[0] == str(self.workspace)
        if event == "focusedmonv2":
            return data.rsplit(",", 1)[-1] == str(self.workspace)
        if event == "windowtitlev2":
            return data.split(",", 1)[0] in self.placeholders
        return False

    def read_events(self, wake):
        """Background reader: keeps the socket drained so Hyprland never drops us for lagging
        (a rebuild emits hundreds of events), and reconnects if it does anyway."""
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr",
                            os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket2.sock")
        failures = 0
        while failures < 10:
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                    sock.connect(path)
                    failures = 0
                    buffer = b""
                    while chunk := sock.recv(65536):
                        buffer += chunk
                        *lines, buffer = buffer.split(b"\n")
                        if any(self.relevant(l.decode(errors="replace")) for l in lines):
                            wake.set()
                wake.set()
            except OSError:
                pass
            failures += 1
            time.sleep(0.5)
        log("can't reach the Hyprland event socket, exiting")
        os.kill(os.getpid(), signal.SIGTERM)

    def run(self):
        log(f"managing workspace {self.workspace} as {self.columns}x{self.rows} (Ctrl+C to stop)")
        wake = threading.Event()
        threading.Thread(target=self.read_events, args=(wake,), daemon=True).start()
        self.safe_tick()
        while True:
            wake.wait(timeout=1 if rebuild_running(self.workspace) else None)
            while True:
                wake.clear()
                time.sleep(DEBOUNCE)
                if not wake.is_set():
                    break
            self.safe_tick()

    def safe_tick(self):
        if rebuild_running(self.workspace):
            return  # the rebuild's own events will wake us again once it's done
        try:
            self.tick()
        except (subprocess.CalledProcessError, RuntimeError, KeyError, IndexError, json.JSONDecodeError) as e:
            log(f"tick failed: {e}")
            self.failed_fixes += 1
        self.breaker()


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: makegrid-manage.py workspace columns rows")
    workspace, columns, rows = map(int, sys.argv[1:])
    os.makedirs(STATE_DIR, exist_ok=True)
    global LOG_FILE
    LOG_FILE = os.path.join(STATE_DIR, f"ws-{workspace}.log")
    pidfile = os.path.join(STATE_DIR, f"ws-{workspace}.manager")
    with open(pidfile, "w") as f:
        f.write(f"{os.getpid()} {columns} {rows}\n")
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    try:
        Manager(workspace, columns, rows).run()
    except KeyboardInterrupt:
        pass
    finally:
        try:
            with open(pidfile) as f:
                if f.read().split()[0] == str(os.getpid()):
                    os.remove(pidfile)
        except (OSError, IndexError):
            pass
        log("stopped")


if __name__ == "__main__":
    main()
