#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, GtkLayerShell, GLib, Gdk
import subprocess, json, os, signal, sys, re

PIDFILE = "/tmp/ws-manage.pid"
MODEFILE = "/tmp/ws-manage.mode"
BAR_HEIGHT = 26
WS_CONF = os.path.expanduser("~/.config/hypr/workspaces.conf")

def hyprctl_json(cmd):
    return json.loads(subprocess.check_output(["hyprctl", cmd, "-j"]))

def hctl(*args):
    subprocess.run(["hyprctl", *args],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def get_special_workspaces():
    out = []
    for ws in hyprctl_json("workspaces"):
        if ws["id"] < 0:
            out.append({
                "name": ws["name"].removeprefix("special:"),
                "full": ws["name"],
                "windows": ws["windows"],
            })
    return out

def get_visible_special():
    for m in hyprctl_json("monitors"):
        if m.get("focused"):
            sw = m.get("specialWorkspace", {}).get("name", "")
            if sw:
                return sw.removeprefix("special:")
    return None

def get_clients_in(full_name):
    return [c["address"] for c in hyprctl_json("clients")
            if c["workspace"]["name"] == full_name]

def get_active_window_address():
    try:
        return hyprctl_json("activewindow").get("address")
    except Exception:
        return None

def _read_conf_lines():
    try:
        with open(WS_CONF) as f:
            return f.readlines()
    except FileNotFoundError:
        return []

def _write_conf_lines(lines):
    with open(WS_CONF, "w") as f:
        f.writelines(lines)

def add_workspace_rule(name):
    """Add persistent rule for special:name, write config + reload."""
    lines = _read_conf_lines()
    for line in lines:
        if f"special:{name}," in line:
            return
    lines.append(f"workspace = special:{name}, persistent:true\n")
    _write_conf_lines(lines)
    hctl("reload")

def remove_workspace_rule(name):
    """Remove persistent rule for special:name, write config + reload."""
    lines = _read_conf_lines()
    _write_conf_lines([l for l in lines if f"special:{name}," not in l])
    hctl("reload")

def rename_workspace_rule(old, new):
    """Rename a workspace rule in the config (no reload)."""
    lines = _read_conf_lines()
    _write_conf_lines([
        l.replace(f"special:{old},", f"special:{new},")
        if f"special:{old}," in l else l
        for l in lines
    ])

class WsManagePopup(Gtk.Window):
    def __init__(self):
        super().__init__()
        self._visible = False
        self._mode = None
        self._pending_addr = None
        self._watch_id = None
        self._initial_active = None

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "ws-manage")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 0)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, 0)
        GtkLayerShell.set_keyboard_mode(
            self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        self.set_decorated(False)

        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(self.box)

        self.connect("key-press-event", self._on_key)
        signal.signal(signal.SIGUSR1, lambda *_: GLib.idle_add(self._on_signal))
        signal.signal(signal.SIGTERM, lambda *_: GLib.idle_add(self._quit))

        self.realize()

    def _on_signal(self):
        mode = "create"
        try:
            with open(MODEFILE) as f:
                mode = f.read().strip()
        except FileNotFoundError:
            pass

        ws_name = None
        if mode.startswith("manage-ws:"):
            ws_name = mode.split(":", 1)[1]
            mode = "manage-ws"

        if mode == "send":
            self._pending_addr = get_active_window_address()
        self._update_position()

        if self._visible and self._mode == mode:
            self._hide()
        else:
            self._show_mode(mode, ws_name=ws_name)
        return False

    def _show_mode(self, mode, ws_name=None):
        self._mode = mode
        if mode == "create":
            self._view_create()
        elif mode == "manage":
            self._view_manage()
        elif mode == "manage-ws":
            self._view_manage_single(ws_name)
        elif mode == "send":
            self._view_send()
        elif mode == "toggle":
            self._view_toggle()

    def _view_create(self):
        self._clear()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.set_margin_start(8)
        box.set_margin_end(8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)

        self._entry = Gtk.Entry()
        self._entry.set_placeholder_text("Workspace name")
        self._entry.set_name("ws-entry")
        self._entry.set_width_chars(16)
        self._entry.connect("activate", self._on_create)
        box.pack_start(self._entry, True, True, 0)

        btn = Gtk.Button(label="✓")
        btn.set_name("ws-btn")
        btn.connect("clicked", self._on_create)
        _pointer(btn)
        box.pack_start(btn, False, False, 0)

        self.box.pack_start(box, False, False, 0)
        self._show()
        self._entry.grab_focus()

    def _on_create(self, *_):
        name = self._entry.get_text().strip()
        if name:
            add_workspace_rule(name)
            hctl("dispatch", "togglespecialworkspace", name)
        self._hide()

    def _view_manage(self):
        self._clear()
        specials = get_special_workspaces()

        if not specials:
            lbl = Gtk.Label(label="No special workspaces")
            lbl.set_name("ws-label")
            lbl.set_margin_top(8)
            lbl.set_margin_bottom(8)
            lbl.set_margin_start(12)
            lbl.set_margin_end(12)
            self.box.pack_start(lbl, False, False, 0)
        else:
            for ws in specials:
                btn = Gtk.Button(label=f"  {ws['name']}  ({ws['windows']})")
                btn.set_name("ws-pick-btn")
                btn.set_relief(Gtk.ReliefStyle.NONE)
                btn.get_child().set_xalign(0)
                btn.set_size_request(200, -1)
                btn.connect("clicked",
                            lambda b, w=ws: self._view_manage_ws(w))
                _pointer(btn)
                self.box.pack_start(btn, False, False, 0)

        self._show()

    def _view_manage_ws(self, ws):
        """Second step: rename/delete for a selected workspace."""
        self._clear()

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        row.set_margin_start(8)
        row.set_margin_end(8)
        row.set_margin_top(6)
        row.set_margin_bottom(6)

        entry = Gtk.Entry()
        entry.set_text(ws["name"])
        entry.set_name("ws-entry")
        entry.set_width_chars(16)
        entry.connect("activate",
                       lambda e: self._on_rename(entry, ws))
        row.pack_start(entry, True, True, 0)

        set_btn = Gtk.Button(label="Set")
        set_btn.set_name("ws-btn")
        set_btn.connect("clicked",
                        lambda b: self._on_rename(entry, ws))
        _pointer(set_btn)
        row.pack_start(set_btn, False, False, 0)

        del_btn = Gtk.Button(label="Delete")
        del_btn.set_name("ws-btn-danger")
        del_btn.connect("clicked",
                        lambda b: self._on_delete(ws))
        _pointer(del_btn)
        row.pack_start(del_btn, False, False, 0)

        self.box.pack_start(row, False, False, 0)
        self.show_all()  # just refresh content, position already set
        entry.grab_focus()

    def _view_manage_single(self, ws_name):
        """Open rename/delete directly for a specific workspace by name."""
        specials = get_special_workspaces()
        ws = next((w for w in specials if w["name"] == ws_name), None)
        if ws is None:
            self._hide()
            return
        self._view_manage_ws(ws)

    def _on_rename(self, entry, ws):
        new = entry.get_text().strip()
        old = ws["name"]
        if not new or new == old:
            return

        for addr in get_clients_in(ws["full"]):
            hctl("dispatch", "movetoworkspacesilent",
                 f"special:{new},address:{addr}")

        if get_visible_special() == old:
            hctl("dispatch", "togglespecialworkspace", old)

        rename_workspace_rule(old, new)
        hctl("reload")
        self._hide()

    def _on_delete(self, ws):
        for addr in get_clients_in(ws["full"]):
            hctl("dispatch", "closewindow", f"address:{addr}")

        try:
            active = json.loads(subprocess.check_output(
                ["hyprctl", "activeworkspace", "-j"]))["id"]
            for addr in get_clients_in(ws["full"]):
                hctl("dispatch", "movetoworkspacesilent",
                     f"{active},address:{addr}")
        except Exception:
            pass

        if get_visible_special() == ws["name"]:
            hctl("dispatch", "togglespecialworkspace", ws["name"])

        remove_workspace_rule(ws["name"])
        self._hide()

    def _view_toggle(self):
        visible = get_visible_special()
        if visible:
            hctl("dispatch", "togglespecialworkspace", visible)
            return

        specials = get_special_workspaces()

        if len(specials) <= 1:
            target = specials[0]["name"] if specials else "Special"
            hctl("dispatch", "togglespecialworkspace", target)
            return

        self._clear()

        for ws in specials:
            label = f"  {ws['name']}  ({ws['windows']})"
            btn = Gtk.Button(label=label)
            btn.set_name("ws-pick-btn")
            btn.set_relief(Gtk.ReliefStyle.NONE)
            btn.get_child().set_xalign(0)
            btn.set_size_request(200, -1)
            btn.connect("clicked",
                        lambda b, n=ws["name"]: self._toggle_and_close(n))
            _pointer(btn)
            self.box.pack_start(btn, False, False, 0)

        self._show()

    def _toggle_and_close(self, name):
        hctl("dispatch", "togglespecialworkspace", name)
        self._hide()

    def _view_send(self):
        specials = get_special_workspaces()

        if len(specials) <= 1:
            target = specials[0]["name"] if specials else "Special"
            self._send_to(target)
            return

        self._clear()

        header = Gtk.Label(label="Send window to:")
        header.set_name("ws-label")
        header.set_margin_top(6)
        header.set_margin_bottom(2)
        header.set_margin_start(8)
        header.set_margin_end(8)
        header.set_xalign(0)
        self.box.pack_start(header, False, False, 0)

        for ws in specials:
            btn = Gtk.Button(label=f"  {ws['name']}  ({ws['windows']})")
            btn.set_name("ws-pick-btn")
            btn.set_relief(Gtk.ReliefStyle.NONE)
            btn.get_child().set_xalign(0)
            btn.set_size_request(200, -1)
            btn.connect("clicked",
                        lambda b, n=ws["name"]: self._send_and_close(n))
            _pointer(btn)
            self.box.pack_start(btn, False, False, 0)

        self._show()

    def _send_to(self, name):
        addr = self._pending_addr or get_active_window_address()
        if addr:
            add_workspace_rule(name)
            hctl("dispatch", "movetoworkspacesilent",
                 f"special:{name},address:{addr}")
        self._pending_addr = None

    def _send_and_close(self, name):
        self._send_to(name)
        self._hide()

    def _clear(self):
        for child in self.box.get_children():
            self.box.remove(child)

    def _update_position(self):
        """Position popup at cursor on the focused monitor."""
        try:
            monitors = hyprctl_json("monitors")
            focused = next(m for m in monitors if m.get("focused"))
            mon_x, mon_y = focused["x"], focused["y"]

            raw = subprocess.check_output(
                ["hyprctl", "cursorpos"]).decode().strip()
            parts = raw.split(",")
            cx, cy = int(parts[0].strip()), int(parts[1].strip())

            local_x = cx - mon_x
            local_y = cy - mon_y

            local_y = max(BAR_HEIGHT, local_y)

            GtkLayerShell.set_margin(
                self, GtkLayerShell.Edge.LEFT, max(0, local_x))
            GtkLayerShell.set_margin(
                self, GtkLayerShell.Edge.TOP, local_y)

            display = Gdk.Display.get_default()
            for i in range(display.get_n_monitors()):
                gdk_mon = display.get_monitor(i)
                geo = gdk_mon.get_geometry()
                if geo.x == mon_x and geo.y == mon_y:
                    GtkLayerShell.set_monitor(self, gdk_mon)
                    break
        except Exception:
            pass

    def _show(self):
        self._update_position()
        self.show_all()
        self._visible = True
        self._initial_active = get_active_window_address()
        if self._watch_id:
            GLib.source_remove(self._watch_id)
        self._watch_id = GLib.timeout_add(150, self._check_outside)

    def _hide(self):
        if self._watch_id:
            GLib.source_remove(self._watch_id)
            self._watch_id = None
        self.hide()
        self._visible = False

    def _check_outside(self):
        if not self._visible:
            return False
        cur = get_active_window_address()
        if cur != self._initial_active:
            self._hide()
            return False
        return True

    def _on_key(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self._hide()
            return True
        return False

    def _quit(self):
        for f in (PIDFILE, MODEFILE):
            try:
                os.remove(f)
            except FileNotFoundError:
                pass
        Gtk.main_quit()
        return False

def _pointer(btn):
    btn.connect("realize", lambda b: b.get_window().set_cursor(
        Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "pointer")))

def write_mode(mode):
    with open(MODEFILE, "w") as f:
        f.write(mode)

css = Gtk.CssProvider()
css.load_from_data(b"""
* {
    all: unset;
    transition-duration: 0s;
    min-height: 0;
    min-width: 0;
}
window {
    background-color: #222222;
    border: 1px solid #444444;
}
    color: #ffffff;
    background-color: #333333;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-weight: 400;
    letter-spacing: 0;
    font-size: 12px;
    padding: 4px 8px;
    border: 1px solid #555555;
    border-radius: 4px;
    caret-color: #ffffff;
}
    color: #cccccc;
    background-color: #333333;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-weight: 400;
    letter-spacing: 0;
    font-size: 12px;
    padding: 4px 10px;
    border: 1px solid #555555;
    border-radius: 4px;
}
    background-color: #ffffff;
    color: #222222;
}
    color: #ff5555;
    background-color: #333333;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-weight: 400;
    letter-spacing: 0;
    font-size: 12px;
    padding: 4px 10px;
    border: 1px solid #555555;
    border-radius: 4px;
}
    background-color: #ff5555;
    color: #222222;
}
    color: #888888;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-weight: 400;
    letter-spacing: 0;
    font-size: 12px;
    padding: 4px 8px;
}
    color: #cccccc;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-weight: 400;
    letter-spacing: 0;
    font-size: 12px;
    padding: 4px 12px;
    background: transparent;
    border: none;
    border-radius: 0;
}
    background-color: #333333;
    color: #ffffff;
}
""")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(), css,
    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else None

    mode_str = mode or "create"
    if mode == "manage-ws" and len(sys.argv) > 2:
        mode_str = f"manage-ws:{sys.argv[2]}"

    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)  # alive?
        write_mode(mode_str)
        os.kill(pid, signal.SIGUSR1)
        sys.exit(0)
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        pass

    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))

    popup = WsManagePopup()

    if mode:
        write_mode(mode_str)
        ws_name = sys.argv[2] if mode == "manage-ws" and len(sys.argv) > 2 else None
        popup._show_mode(mode, ws_name=ws_name)

    Gtk.main()
