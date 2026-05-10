#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, GtkLayerShell, GLib, Gdk
import subprocess, json, os, signal, re, glob, threading

SLIDER_WIDTH = 500
PIDFILE = "/tmp/brightness-slider.pid"
DEBOUNCE_MS = 150
POLL_INTERVAL_S = 10
DDC_MIN = 0

def get_cursor_on_monitor():
    try:
        cur = json.loads(subprocess.check_output(["hyprctl", "cursorpos", "-j"]).decode())
        mons = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"]).decode())
        cx, cy = cur["x"], cur["y"]
        for m in mons:
            mx, my, mw = m["x"], m["y"], m["width"]
            if mx <= cx < mx + mw and my <= cy < my + m["height"]:
                return cx - mx
        return cx
    except Exception:
        return 400

def get_laptop_backlights():
    devs = []
    try:
        for path in glob.glob("/sys/class/backlight/*/"):
            name = os.path.basename(path.rstrip("/"))
            out = subprocess.check_output(["brightnessctl", "-d", name, "info", "-m"]).decode()
            pct = int(out.strip().split(",")[3].replace("%", ""))
            devs.append((name, pct))
    except Exception:
        pass
    return devs

def get_ddc_monitors():
    monitors = []
    try:
        out = subprocess.check_output(["ddcutil", "detect", "--brief"],
                                       stderr=subprocess.DEVNULL, timeout=10).decode()
        blocks = re.split(r'(?=Display \d+)', out)
        procs = {}
        for block in blocks:
            if not re.search(r'Display \d+', block):
                continue
            bus_match = re.search(r'I2C bus:\s+/dev/i2c-(\d+)', block)
            model_match = re.search(r'Monitor:\s+\w+:(.+?):', block)
            if not bus_match:
                continue
            bus = bus_match.group(1)
            model = model_match.group(1).strip() if model_match else f"Display {bus}"
            procs[bus] = (model, subprocess.Popen(
                ["ddcutil", "--bus", bus, "getvcp", "10", "--brief"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL))

        for bus, (model, proc) in procs.items():
            try:
                stdout, _ = proc.communicate(timeout=5)
                cur = int(stdout.decode().strip().split()[3])
                monitors.append((bus, model, cur))
            except Exception:
                continue
    except Exception:
        pass
    return monitors

class BrightnessPopup(Gtk.Window):
    def __init__(self):
        super().__init__()
        self._updating = False
        self._visible = False
        self._scales = {}
        self._pending = {}
        self._cached_backlights = []
        self._cached_ddc = []

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 0)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, 0)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)

        self.set_default_size(SLIDER_WIDTH, -1)
        self.set_decorated(False)

        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(self.main_box)

        self.connect("key-press-event", self.on_key)
        self.connect("leave-notify-event", self.on_leave)
        self.connect("focus-out-event", self.on_focus_out)
        signal.signal(signal.SIGUSR1, lambda *_: GLib.idle_add(self.toggle))
        signal.signal(signal.SIGTERM, lambda *_: GLib.idle_add(self._quit))

        self.realize()
        self._poll_monitors()

    def _poll_monitors(self):
        """Poll monitor info in a background thread."""
        def _worker():
            bl = get_laptop_backlights()
            ddc = get_ddc_monitors()
            GLib.idle_add(self._update_cache, bl, ddc)
        threading.Thread(target=_worker, daemon=True).start()
        GLib.timeout_add_seconds(POLL_INTERVAL_S, self._poll_monitors)
        return False

    def _update_cache(self, backlights, ddc):
        self._cached_backlights = backlights
        self._cached_ddc = ddc
        if self._visible:
            self._sync_sliders()
        return False

    def _sync_sliders(self):
        self._updating = True
        if self._cached_backlights and "backlight" in self._scales:
            avg = sum(p for _, p in self._cached_backlights) // len(self._cached_backlights)
            self._scales["backlight"].set_value(avg)
        for bus, _, cur in self._cached_ddc:
            if bus in self._scales:
                self._scales[bus].set_value(cur)
        self._updating = False

    def _build_sliders(self):
        for child in self.main_box.get_children():
            self.main_box.remove(child)
        self._scales = {}
        self._updating = True

        if self._cached_backlights:
            avg_pct = sum(p for _, p in self._cached_backlights) // len(self._cached_backlights)
            dev_names = [n for n, _ in self._cached_backlights]
            scale = self._add_slider("Backlight", avg_pct, 1, 100,
                             lambda val, devs=dev_names: self._set_backlight(devs, val))
            self._scales["backlight"] = scale

        for bus, model, cur in self._cached_ddc:
            scale = self._add_slider(model, cur, DDC_MIN, 100,
                             lambda val, b=bus: self._set_ddc(b, val))
            self._scales[bus] = scale

        self._updating = False

    def _add_slider(self, label, value, min_val, max_val, callback):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.set_margin_start(16)
        box.set_margin_end(16)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        lbl = Gtk.Label(label=label)
        lbl.set_name("bri-label")
        lbl.set_xalign(0)
        lbl.set_size_request(120, -1)
        box.pack_start(lbl, False, False, 0)

        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, min_val, max_val, 1)
        scale.set_draw_value(True)
        scale.set_value_pos(Gtk.PositionType.RIGHT)
        scale.set_name("bri-slider")
        scale.set_value(value)
        scale.connect("value-changed", lambda s, cb=callback: self._on_changed(s, cb))
        box.pack_start(scale, True, True, 0)

        self.main_box.pack_start(box, False, False, 0)
        return scale

    def _on_changed(self, scale, callback):
        if self._updating:
            return
        val = int(scale.get_value())
        sid = id(scale)
        if sid in self._pending:
            GLib.source_remove(self._pending[sid])
        self._pending[sid] = GLib.timeout_add(DEBOUNCE_MS,
            lambda: self._fire(sid, callback, val))

    def _fire(self, sid, callback, val):
        self._pending.pop(sid, None)
        callback(val)
        return False

    def _set_backlight(self, dev_names, val):
        for dev in dev_names:
            subprocess.Popen(["brightnessctl", "-d", dev, "set", f"{val}%"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _set_ddc(self, bus, val):
        subprocess.Popen(["ddcutil", "--bus", bus, "setvcp", "10", str(val), "--noverify"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def toggle(self):
        if self._visible:
            self.hide()
            self._visible = False
        else:
            self._build_sliders()
            self._reposition()
            self.show_all()
            self._visible = True
        return False

    def _reposition(self):
        local_x = get_cursor_on_monitor()
        left_margin = max(0, local_x - SLIDER_WIDTH // 2)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, left_margin)

    def on_key(self, widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.toggle()
            return True
        return False

    def on_leave(self, widget, event):
        if event.detail == Gdk.NotifyType.INFERIOR:
            return False
        if self._visible:
            self.hide()
            self._visible = False
        return False

    def on_focus_out(self, widget, event):
        if self._visible:
            self.hide()
            self._visible = False
        return False

    def _quit(self):
        try:
            os.remove(PIDFILE)
        except FileNotFoundError:
            pass
        Gtk.main_quit()
        return False

css = Gtk.CssProvider()
css.load_from_data(b"""
* {
    transition-duration: 0s;
    transition-delay: 0s;
    animation-duration: 0s;
}
window {
    background-color: #222222;
    border: 1px solid #444444;
    border-radius: 0;
}
    color: #cccccc;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-weight: 400;
    letter-spacing: 0;
    font-size: 12px;
}
    color: #cccccc;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-weight: 400;
    letter-spacing: 0;
    font-size: 11px;
    min-width: 280px;
}
    min-height: 6px;
    background-color: #444444;
    border-radius: 3px;
}
    background-color: #cccccc;
    border-radius: 3px;
}
    min-width: 16px;
    min-height: 16px;
    background-color: #cccccc;
    border: 1px solid #444444;
    border-radius: 8px;
    margin: -5px;
}
    background-color: #ffffff;
}
""")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(),
    css,
    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
)

with open(PIDFILE, "w") as f:
    f.write(str(os.getpid()))
BrightnessPopup()
Gtk.main()
