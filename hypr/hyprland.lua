


require("monitors")
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.workspace_rule({ workspace = "special:Special", persistent = true })



local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "vicinae toggle"



local autostart = {
    "~/.config/eww/scripts/open-bars.sh",
    "python3 ~/.config/eww/scripts/brightness-slider.py",
    "swaync",
    "hypridle",
    "hyprpolkitagent",
    "dbus-update-activation-environment --systemd --all",
    "gnome-keyring-daemon --start --components=secrets,pkcs11,ssh",
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
    "nm-applet --indicator",
    "vicinae server",
    "hyprpm reload -n",
    "~/.config/hypr/mpvpaper-watch.sh",
    "~/.config/hypr/mpvpaper-pauser.sh",
}

hl.on("hyprland.start", function()
    for _, cmd in ipairs(autostart) do
        hl.exec_cmd(cmd)
    end
end)

hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("~/.config/hypr/lid.sh close"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/lid.sh open"),  { locked = true })

local function reapply_clamshell()
    hl.exec_cmd("grep -q closed /proc/acpi/button/lid/*/state && ~/.config/hypr/lid.sh close")
end
hl.on("hyprland.start", reapply_clamshell)
hl.on("config.reloaded", reapply_clamshell)



hl.env("XCURSOR_THEME", "Adwaita")
hl.env("HYPRCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("GTK_THEME", "adw-gtk3-dark")



hl.permission({ binary = "/usr/(bin|local/bin)/grim",   type = "screencopy", mode = "allow" })
hl.permission({ binary = "/usr/(bin|local/bin)/hyprpm", type = "plugin",     mode = "allow" })



hl.config({
    general = {
        gaps_in     = 3,
        gaps_out    = 5,
        border_size = 2,
        col = {
            active_border   = "rgba(a0a0a0ff)",
            inactive_border = "rgba(282828ff)",
        },
        resize_on_border = true,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding         = 8,
        rounding_power   = 4,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 1,
            render_power = 2,
            color        = "rgba(00000033)",
        },

        blur = {
            enabled  = false,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        vrr                      = 1,
    },

    xwayland = {
        force_zero_scaling = false,
    },

    render = {
        cm_auto_hdr = 0,
    },

    cursor = {
        no_hardware_cursors  = true,
        enable_hyprcursor    = false,
        sync_gsettings_theme = true,
    },

    debug = {
        disable_logs       = false,
        enable_stdout_logs = true,
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}  } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}  } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}     } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}  } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}   } })

hl.animation({ leaf = "global",           enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",           enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",          enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",        enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",       enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",           enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",          enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",             enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",           enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",         enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",        enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",     enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut",    enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",       enabled = true, speed = 7,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "workspacesIn",     enabled = true, speed = 5,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "workspacesOut",    enabled = true, speed = 7,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 1,    bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",       enabled = true, speed = 7,    bezier = "quick" })



hl.config({
    input = {
        kb_layout  = "us,ru",
        kb_variant = "",
        kb_model   = "",
        kb_options = "grp:alt_shift_toggle,keyd:f13",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = -0.15,

        touchpad = {
            natural_scroll       = true,
            scroll_factor        = 0.1,
            clickfinger_behavior = true,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace", scale = 0.1 })

hl.device({ name = "logitech-g304-1",                 sensitivity = -0.35 })
hl.device({ name = "logitech-usb-receiver-mouse",     sensitivity = -0.35 })
hl.device({ name = "apple-inc.-magic-trackpad-usb-c", sensitivity = 0.15, scroll_factor = 0.15 })
hl.device({ name = "beken-2.4g-wireless-device-1",    sensitivity = -0.35 })



local mainMod = "SUPER"

hl.bind("CTRL + ALT + delete", hl.dsp.exec_cmd(
    "kitty --class hyprland-overview --title 'Window Overview' -o remember_window_size=no"
    .. " -o initial_window_width=100c -o initial_window_height=30c -o confirm_os_window_close=0"
    .. " -e python3 ~/.config/eww/scripts/window-overview.py"))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())

hl.bind(mainMod .. " + M", hl.dsp.submap("movewindow"))
hl.define_submap("movewindow", "reset", function()
    hl.bind("1", hl.dsp.window.move({ monitor = "DP-3" }))
    hl.bind("2", hl.dsp.window.move({ monitor = "DP-1" }))
    hl.bind("3", hl.dsp.window.move({ monitor = "eDP-1" }))
    hl.bind("escape", hl.dsp.submap("reset"))
end)

hl.bind(mainMod .. " + SHIFT + M", hl.dsp.submap("moveworkspace"))
hl.define_submap("moveworkspace", "reset", function()
    hl.bind("1", hl.dsp.workspace.move({ monitor = "DP-3" }))
    hl.bind("2", hl.dsp.workspace.move({ monitor = "DP-1" }))
    hl.bind("3", hl.dsp.workspace.move({ monitor = "eDP-1" }))
    hl.bind("escape", hl.dsp.submap("reset"))
end)

hl.bind(mainMod .. " + E",         hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R",         hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + P",         hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("~/.config/hypr/tile-workspace.sh"))

local focusKeys = {
    left  = { "left",  "H", "code:83" },
    right = { "right", "L", "code:85" },
    up    = { "up",    "K", "code:80" },
    down  = { "down",  "J", "code:88" },
}
for direction, keys in pairs(focusKeys) do
    for _, key in ipairs(keys) do
        hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = direction }))
    end
    hl.bind(mainMod .. " + SHIFT + " .. direction, hl.dsp.window.move({ direction = direction }))
end

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i, on_current_monitor = true }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("Special"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:Special", follow = false }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse:274", hl.dsp.window.drag(),   { mouse = true })

local held = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), held)
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      held)
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     held)
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   held)
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("~/.config/hypr/brightness.sh up 5"),              held)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/brightness.sh down 5"),            held)

hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

hl.bind("ALT + code:49", hl.dsp.exec_cmd("~/.config/hypr/switch-lang.sh"), { dont_inhibit = true })

local snapToSatty = "bash -c 'grim -g \"$(slurp)\" - | satty --filename - "
    .. "--output-filename /tmp/satty-screenshot.png --copy-command wl-copy'"
hl.bind("CTRL + ALT + code:13",         hl.dsp.exec_cmd("bash -c 'grim -g \"$(slurp)\" - | wl-copy'"))
hl.bind("ALT + SHIFT + code:13",        hl.dsp.exec_cmd(snapToSatty))
hl.bind("CTRL + ALT + SHIFT + code:13", hl.dsp.exec_cmd(snapToSatty))
hl.bind("CTRL + ALT + SHIFT + F4",      hl.dsp.exec_cmd(snapToSatty))

hl.bind("SUPER + SHIFT + F23", hl.dsp.exec_cmd("kitty claude --chrome"))



hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "wow-fullscreen",
    match = { class = "^steam_app_default$", title = "^World of Warcraft$" },
    fullscreen     = true,
    suppress_event = "fullscreen maximize",
})

hl.window_rule({
    name  = "coinpoker-tiled",
    match = { class = [[^(CoinPoker|coinpoker\.exe)$]] },
    tile  = true,
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

hl.window_rule({
    name      = "window-overview",
    match     = { class = "hyprland-overview" },
    float     = true,
    size      = "70% 60%",
    center    = true,
    animation = "popin",
})

hl.window_rule({
    name      = "chromium-vfs-to-ws10",
    match     = { class = "^chromium-browser$", title = "Google Chrome for Testing$" },
    workspace = "10 silent",
})

hl.window_rule({
    name    = "transparent-utilities",
    match   = { class = [[^(org\.kde\.dolphin|com\.saivert\.pwvucontrol|pavucontrol|blueman-manager|nm-connection-editor|nm-applet)$]] },
    opacity = "0.8",
})

hl.window_rule({
    name      = "wowser-to-ws7",
    match     = { title = "^wowser" },
    workspace = "7 silent",
})



hl.layer_rule({ name = "vicinae-blur", match = { namespace = "vicinae" }, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ name = "eww-bar-blur", match = { namespace = "eww-bar" }, blur = true, ignore_alpha = 0.3 })



if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    hg.config({
        enabled        = true,
        default_theme  = "dark",
        default_preset = "valakas",

        blur_strength     = 3.0,
        blur_iterations   = 4,
        glass_opacity     = 1.0,
        tint_color        = 0x00000055,
        brightness        = 1.5,
        saturation        = 1.0,
        contrast          = 1.0,
        vibrancy          = 0.0,
        adaptive_dim      = 0.0,
        adaptive_boost    = 0.0,
        specular_strength = 0.0,

        layers = { enabled = true },
    })

    hg.preset("valakas", {
        refraction_strength  = 0.7,
        fresnel_strength     = 0.6,
        chromatic_aberration = 0.4,
        edge_thickness       = 0.05,
        lens_distortion      = 0.3,
    })

    hg.preset("bar", {
        blur_strength        = 4.5,
        blur_iterations      = 5,
        refraction_strength  = 0.0,
        fresnel_strength     = 0.0,
        chromatic_aberration = 0.0,
        edge_thickness       = 0.0,
        lens_distortion      = 0.0,
        specular_strength    = 0.0,
    })

    hg.layer("eww-bar", { preset = "bar", mask_threshold = 0.001 })
    hg.layer("swaync-control-center")
    hg.layer("swaync-notification-window")
    hg.layer("vicinae")
end
