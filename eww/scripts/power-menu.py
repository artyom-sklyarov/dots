#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, GtkLayerShell, GLib, Gdk
import subprocess, os, sys, signal

BAR_HEIGHT = 26
PIDFILE = "/tmp/power-menu.pid"

ACTIONS = [
    ("Lock",     "hyprlock"),
    ("Sleep",    "systemctl suspend"),
    ("Logout",   "hyprctl dispatch exit"),
    ("Reboot",   "systemctl reboot"),
    ("Shutdown", "systemctl -i poweroff"),
]

class PowerMenu(Gtk.Window):
    def __init__(self):
        super().__init__()
        self._visible = True

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 0)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, 0)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)

        self.set_decorated(False)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        for label, cmd in ACTIONS:
            btn = Gtk.Button(label=label)
            btn.set_name("power-btn")
            btn.set_relief(Gtk.ReliefStyle.NONE)
            btn.set_size_request(120, -1)
            btn.get_child().set_xalign(0)
            btn.connect("clicked", lambda _, c=cmd: self._run(c))
            btn.connect("realize", lambda b: b.get_window().set_cursor(
                Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "pointer")))
            box.pack_start(btn, False, False, 0)

        self.add(box)
        self.connect("key-press-event", self.on_key)
        self.connect("leave-notify-event", self.on_leave)
        self.connect("focus-out-event", self.on_focus_out)

        signal.signal(signal.SIGUSR1, lambda *_: GLib.idle_add(self.toggle))
        signal.signal(signal.SIGTERM, lambda *_: GLib.idle_add(self._quit))

        self.show_all()

    def toggle(self):
        if self._visible:
            self.hide()
            self._visible = False
        else:
            self.show_all()
            self._visible = True
        return False

    def _run(self, cmd):
        self.hide()
        self._visible = False
        subprocess.Popen(cmd, shell=True)

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
}
window {
    background-color: #222222;
    border: 1px solid #444444;
}
    color: #cccccc;
    font-family: "SF Pro Display", "JetBrainsMono Nerd Font", sans-serif;
    font-size: 14px;
    font-weight: 400;
    letter-spacing: 0;
    padding: 0 12px;
    min-height: 28px;
    background: transparent;
    border: none;
    border-bottom: 1px solid #444444;
    border-radius: 0;
    margin: 0;
}
    border-bottom: none;
}
    background-color: #333333;
    color: #ffffff;
}
""")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(),
    css,
    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
)

with open(PIDFILE, "w") as f:
    f.write(str(os.getpid()))
PowerMenu()
Gtk.main()
